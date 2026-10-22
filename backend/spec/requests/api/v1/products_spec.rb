require "rails_helper"

RSpec.describe "Products", type: :request do
  let(:customer) { create(:user) }
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/products" do
    it "is browsable without an account" do
      create(:product, :in_stock)

      get "/api/v1/products"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].size).to eq(1)
    end

    # The policy scope, not the query object, is what hides these.
    it "omits draft and archived products from the public listing" do
      live = create(:product, status: "active", published_at: 1.day.ago)
      create(:product, :draft)
      create(:product, :archived)

      get "/api/v1/products"

      expect(response.parsed_body["data"].map { |p| p["id"] }).to contain_exactly(live.id)
    end

    it "shows an administrator every product regardless of status" do
      create(:product, status: "active", published_at: 1.day.ago)
      create(:product, :draft)

      get "/api/v1/products", headers: auth_headers_for(admin)

      expect(response.parsed_body["data"].size).to eq(2)
    end

    describe "money representation" do
      # ADR-002. A JSON number is an IEEE-754 double, so a client summing
      # prices drifts from the server by cents.
      it "serializes price as a string, never a number" do
        create(:product, price: "49.99")

        get "/api/v1/products"

        price = response.parsed_body["data"].first["price"]
        expect(price).to eq("49.99")
        expect(price).to be_a(String)
      end

      # BigDecimal#to_s renders 50.00 as "50.0"; a price label needs both places.
      it "always renders two decimal places" do
        create(:product, price: "50.00", compare_at_price: "60")

        get "/api/v1/products"

        product = response.parsed_body["data"].first
        expect(product["price"]).to eq("50.00")
        expect(product["compare_at_price"]).to eq("60.00")
      end
    end

    describe "stock exposure" do
      # Exact stock lets a competitor measure sales velocity by polling.
      it "reports whether an item is purchasable without revealing the quantity" do
        create(:product, :in_stock, quantity: 7)

        get "/api/v1/products"

        product = response.parsed_body["data"].first
        expect(product["in_stock"]).to be(true)
        expect(product.keys).not_to include("available_quantity", "reorder_threshold", "low_stock")
      end
    end

    describe "pagination" do
      it "returns page metadata alongside the data" do
        3.times { create(:product) }

        get "/api/v1/products", params: { per_page: 2 }

        expect(response.parsed_body["data"].size).to eq(2)
        expect(response.parsed_body["meta"]).to include(
          "page" => 1, "per_page" => 2, "total_count" => 3, "total_pages" => 2
        )
      end

      it "returns the remainder on the final page" do
        3.times { create(:product) }

        get "/api/v1/products", params: { per_page: 2, page: 2 }

        expect(response.parsed_body["data"].size).to eq(1)
      end

      it "caps an oversized per_page" do
        get "/api/v1/products", params: { per_page: 10_000 }

        expect(response.parsed_body.dig("meta", "per_page")).to eq(Pagination::MAX_PER_PAGE)
      end

      # An unbounded page multiplies into an OFFSET beyond bigint, which
      # PostgreSQL rejects — a 500 from nothing but a query string.
      it "survives an absurdly large page number" do
        create(:product)

        get "/api/v1/products", params: { page: "9" * 30 }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("meta", "page")).to eq(Pagination::MAX_PAGE)
      end

      it "returns an empty page rather than an error beyond the last page" do
        create(:product)

        get "/api/v1/products", params: { page: 99 }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]).to be_empty
        expect(response.parsed_body.dig("meta", "total_count")).to eq(1)
      end

      # ADR-011: the tiebreaker is what makes this true.
      it "never repeats a product across pages when values tie" do
        6.times { create(:product, price: "10.00") }

        get "/api/v1/products", params: { sort: "price_asc", per_page: 3, page: 1 }
        first = response.parsed_body["data"].map { |p| p["id"] }

        get "/api/v1/products", params: { sort: "price_asc", per_page: 3, page: 2 }
        second = response.parsed_body["data"].map { |p| p["id"] }

        expect(first & second).to be_empty
        expect((first + second).uniq.size).to eq(6)
      end
    end

    describe "filtering and sorting" do
      it "filters by category slug" do
        wanted = create(:product, category: create(:category, slug: "shoes"))
        create(:product, category: create(:category, slug: "hats"))

        get "/api/v1/products", params: { category: "shoes" }

        expect(response.parsed_body["data"].map { |p| p["id"] }).to contain_exactly(wanted.id)
      end

      it "sorts by price ascending" do
        dear = create(:product, price: "99.00")
        cheap = create(:product, price: "1.00")

        get "/api/v1/products", params: { sort: "price_asc" }

        expect(response.parsed_body["data"].map { |p| p["id"] }).to eq([ cheap.id, dear.id ])
      end

      # BigDecimal("1e999999") is valid Ruby but overflows PostgreSQL numeric.
      it "ignores a price filter PostgreSQL could not represent" do
        create(:product)

        get "/api/v1/products", params: { min_price: "1e999999", max_price: "NaN" }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].size).to eq(1)
      end

      it "ignores a malicious sort parameter" do
        create(:product)

        get "/api/v1/products", params: { sort: "price asc; DROP TABLE products" }

        expect(response).to have_http_status(:ok)
        expect(Product.count).to eq(1)
      end
    end

    describe "search" do
      it "returns matches with the search echoed in meta" do
        boot = create(:product, name: "Leather Boot")
        create(:product, name: "Wool Scarf")

        get "/api/v1/products", params: { q: "boots" }

        expect(response.parsed_body["data"].map { |p| p["id"] }).to contain_exactly(boot.id)
        expect(response.parsed_body.dig("meta", "search")).to eq(
          "query" => "boots", "mode" => "fulltext", "sort" => "relevance"
        )
      end

      # The client must be able to say "showing results for similar terms".
      it "reports a fuzzy fallback" do
        create(:product, name: "Leather Boot")

        get "/api/v1/products", params: { q: "lether" }

        expect(response.parsed_body["data"].size).to eq(1)
        expect(response.parsed_body.dig("meta", "search", "mode")).to eq("fuzzy")
      end

      it "counts search matches, not the catalogue" do
        3.times { |i| create(:product, name: "Boot #{i}") }
        create(:product, name: "Scarf")

        get "/api/v1/products", params: { q: "boot", per_page: 2 }

        expect(response.parsed_body["meta"]).to include("total_count" => 3, "total_pages" => 2)
      end

      it "never surfaces a draft through search" do
        create(:product, :draft, name: "Secret Boot")

        get "/api/v1/products", params: { q: "secret" }

        expect(response.parsed_body["data"]).to be_empty
      end

      it "omits search meta when there is no search" do
        get "/api/v1/products"

        expect(response.parsed_body["meta"]).not_to have_key("search")
      end
    end

    it "does not N+1 as the catalogue grows" do
      create(:product, :in_stock)
      one = count_queries { get "/api/v1/products" }

      4.times { create(:product, :in_stock) }
      many = count_queries { get "/api/v1/products" }

      expect(many.size).to eq(one.size),
                           "query count grew from #{one.size} to #{many.size}"
    end
  end

  describe "GET /api/v1/products/:id" do
    it "finds a published product by slug and includes detail fields" do
      product = create(:product, :in_stock, slug: "nike-air-zoom",
                                            description: "Lightweight runner")
      create(:product_image, :primary, product:)

      get "/api/v1/products/nike-air-zoom"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body["data"]
      expect(body["id"]).to eq(product.id)
      expect(body["description"]).to eq("Lightweight runner")
      expect(body["images"].size).to eq(1)
    end

    # A 403 would confirm an unreleased product exists at that slug.
    it "returns 404, not 403, for a draft product" do
      create(:product, :draft, slug: "unreleased")

      get "/api/v1/products/unreleased"

      expect(response).to have_http_status(:not_found)
    end

    it "lets an administrator fetch a draft product" do
      create(:product, :draft, slug: "unreleased")

      get "/api/v1/products/unreleased", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for an unknown slug" do
      get "/api/v1/products/does-not-exist"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end
  end
end
