require "rails_helper"

RSpec.describe "Admin products", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:customer) { create(:user) }
  let(:category) { create(:category) }

  let(:valid_params) do
    {
      product: {
        name: "Trail Runner", slug: "trail-runner", sku: "tr-001",
        category_id: category.id, price: "89.50", status: "draft",
        available_quantity: 12, reorder_threshold: 3
      }
    }
  end

  describe "GET /api/v1/admin/products" do
    it "lists every status, with the operational stock figures" do
      create(:product, :in_stock, quantity: 7)
      create(:product, :draft)
      create(:product, :archived)

      get "/api/v1/admin/products", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      data = response.parsed_body["data"]
      expect(data.size).to eq(3)
      expect(data.map { |p| p["available_quantity"] }).to include(7)
    end

    it "filters by status" do
      draft = create(:product, :draft)
      create(:product)

      get "/api/v1/admin/products", params: { status: "draft" }, headers: auth_headers_for(admin)

      expect(response.parsed_body["data"].map { |p| p["id"] }).to contain_exactly(draft.id)
    end

    it "ignores an unknown status rather than returning nothing" do
      create(:product)

      get "/api/v1/admin/products", params: { status: "bogus" }, headers: auth_headers_for(admin)

      expect(response.parsed_body["data"].size).to eq(1)
    end

    it "searches drafts too" do
      draft = create(:product, :draft, name: "Prototype Boot")

      get "/api/v1/admin/products", params: { q: "prototype" }, headers: auth_headers_for(admin)

      expect(response.parsed_body["data"].map { |p| p["id"] }).to contain_exactly(draft.id)
    end

    # Regression: the status filter used to be applied after the query
    # object, so the fallback decision saw products the admin had excluded
    # and returned an empty "fulltext" page instead of falling back.
    it "applies the status filter before deciding on the typo fallback" do
      create(:product, name: "Leather Boot")
      draft = create(:product, :draft, name: "Bootee Sample")

      get "/api/v1/admin/products", params: { q: "boot", status: "draft" },
                                    headers: auth_headers_for(admin)

      expect(response.parsed_body.dig("meta", "search", "mode")).to eq("fuzzy")
      expect(response.parsed_body["data"].map { |p| p["id"] }).to contain_exactly(draft.id)
    end

    it "refuses a customer with 403" do
      get "/api/v1/admin/products", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an unauthenticated caller with 401" do
      get "/api/v1/admin/products"

      expect(response).to have_http_status(:unauthorized)
    end

    it "does not N+1 as the catalogue grows" do
      headers = auth_headers_for(admin)
      create(:product, :in_stock)
      one = count_queries { get "/api/v1/admin/products", headers: }

      4.times { create(:product, :in_stock) }
      many = count_queries { get "/api/v1/admin/products", headers: }

      expect(many.size).to eq(one.size)
    end
  end

  describe "GET /api/v1/admin/products/:id" do
    # By id, so a rename never moves the record an admin is editing.
    it "addresses a product by id, including drafts" do
      product = create(:product, :draft)

      get "/api/v1/admin/products/#{product.id}", headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "id")).to eq(product.id)
    end
  end

  describe "POST /api/v1/admin/products" do
    it "creates the product and its inventory together" do
      expect do
        post "/api/v1/admin/products", params: valid_params, headers: auth_headers_for(admin)
      end.to change(Product, :count).by(1).and change(Inventory, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body["data"]
      expect(body).to include("sku" => "TR-001", "price" => "89.50", "available_quantity" => 12)
    end

    it "defaults inventory to zero when no quantity is given" do
      params = { product: valid_params[:product].except(:available_quantity, :reorder_threshold) }

      post "/api/v1/admin/products", params:, headers: auth_headers_for(admin)

      expect(Product.find_by!(slug: "trail-runner").inventory.available_quantity).to eq(0)
    end

    # The transaction is the point: a product without an inventory row is
    # silently unsellable, so a failure on either write must undo both.
    it "rolls back the product when the inventory is invalid" do
      params = { product: valid_params[:product].merge(available_quantity: -1) }

      expect do
        post "/api/v1/admin/products", params:, headers: auth_headers_for(admin)
      end.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details")).to have_key("available_quantity")
    end

    it "returns field errors for an invalid product" do
      params = { product: valid_params[:product].merge(slug: "Not A Slug", price: "-1") }

      post "/api/v1/admin/products", params:, headers: auth_headers_for(admin)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details").keys).to include("slug", "price")
    end

    it "returns 400 when the product key is missing" do
      post "/api/v1/admin/products", params: { name: "x" }, headers: auth_headers_for(admin)

      expect(response).to have_http_status(:bad_request)
    end

    it "refuses a customer and writes nothing" do
      expect do
        post "/api/v1/admin/products", params: valid_params, headers: auth_headers_for(customer)
      end.not_to change(Product, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/admin/products/:id" do
    it "updates the product" do
      product = create(:product, price: "10.00")

      patch "/api/v1/admin/products/#{product.id}",
            params: { product: { price: "12.00" } }, headers: auth_headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(product.reload.price).to eq(BigDecimal("12.00"))
    end

    it "rejects a slug already taken by another product" do
      create(:product, slug: "taken")
      product = create(:product)

      patch "/api/v1/admin/products/#{product.id}",
            params: { product: { slug: "taken" } }, headers: auth_headers_for(admin)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /api/v1/admin/products/:id" do
    # Regression: set_product authorized `destroy?`, which ProductPolicy
    # denies to everyone, so archiving was a permanent 403.
    it "archives rather than deletes" do
      product = create(:product)

      expect do
        delete "/api/v1/admin/products/#{product.id}", headers: auth_headers_for(admin)
      end.not_to change(Product, :count)

      expect(response).to have_http_status(:ok)
      expect(product.reload).to be_archived
    end

    it "removes the archived product from the public catalogue" do
      product = create(:product, slug: "retired")

      delete "/api/v1/admin/products/#{product.id}", headers: auth_headers_for(admin)
      get "/api/v1/products/retired"

      expect(response).to have_http_status(:not_found)
    end

    it "refuses a customer" do
      product = create(:product)

      delete "/api/v1/admin/products/#{product.id}", headers: auth_headers_for(customer)

      expect(response).to have_http_status(:forbidden)
      expect(product.reload).to be_active
    end
  end
end
