require "rails_helper"

RSpec.describe "Cart", type: :request do
  let(:customer) { create(:user) }
  let(:headers) { auth_headers_for(customer) }
  let(:product) { create(:product, :in_stock, price: "25.00") }

  def add_to_cart(product_id: product.id, quantity: 1, as: headers)
    post "/api/v1/cart/items", params: { product_id:, quantity: }, headers: as
  end

  def cart_body
    response.parsed_body["data"]
  end

  describe "GET /api/v1/cart" do
    it "requires authentication" do
      get "/api/v1/cart"

      expect(response).to have_http_status(:unauthorized)
    end

    # GET must be safe: a cart badge on every page must not insert rows.
    it "returns an empty cart without creating one" do
      expect { get "/api/v1/cart", headers: }.not_to change(Cart, :count)

      expect(response).to have_http_status(:ok)
      expect(cart_body).to include("id" => nil, "items" => [], "item_count" => 0,
                                   "subtotal" => "0.00", "checkout_ready" => false)
    end

    it "returns lines with live prices and a string subtotal" do
      add_to_cart(quantity: 2)

      get "/api/v1/cart", headers: headers

      expect(cart_body["items"].sole).to include(
        "quantity" => 2, "unit_price" => "25.00", "line_total" => "50.00", "availability" => "available"
      )
      expect(cart_body).to include("subtotal" => "50.00", "item_count" => 2, "checkout_ready" => true)
    end

    # The cart stores no price (CartItem#unit_price), so a price change shows
    # immediately rather than letting a customer hold a stale lower price.
    it "reflects a price change made after the item was added" do
      add_to_cart
      product.update!(price: "30.00")

      get "/api/v1/cart", headers: headers

      expect(cart_body["subtotal"]).to eq("30.00")
    end

    it "never reveals stock quantities" do
      add_to_cart

      get "/api/v1/cart", headers: headers

      expect(response.body).not_to include("available_quantity")
    end

    it "shows only the caller's own cart" do
      add_to_cart(as: auth_headers_for(create(:user)))

      get "/api/v1/cart", headers: headers

      expect(cart_body["items"]).to be_empty
    end

    it "does not N+1 as lines are added" do
      add_to_cart
      one = count_queries { get "/api/v1/cart", headers: }

      3.times { add_to_cart(product_id: create(:product, :in_stock).id) }
      create(:product_image, :primary, product:)
      many = count_queries { get "/api/v1/cart", headers: }

      expect(many.size).to eq(one.size)
    end
  end

  describe "POST /api/v1/cart/items" do
    it "adds a line and returns the whole cart" do
      add_to_cart(quantity: 2)

      expect(response).to have_http_status(:ok)
      expect(cart_body["items"].sole["product"]).to include("id" => product.id, "slug" => product.slug)
      expect(cart_body["subtotal"]).to eq("50.00")
    end

    it "defaults the quantity to one" do
      post "/api/v1/cart/items", params: { product_id: product.id }, headers: headers

      expect(cart_body["items"].sole["quantity"]).to eq(1)
    end

    it "increments when the product is added again" do
      add_to_cart
      add_to_cart(quantity: 2)

      expect(cart_body["items"].sole["quantity"]).to eq(3)
    end

    # The same rule as the product page: a draft's existence is not confirmed.
    it "returns 404 for an unpublished product, even to an administrator" do
      draft = create(:product, :draft)

      add_to_cart(product_id: draft.id, as: auth_headers_for(create(:user, :admin)))

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 out_of_stock for a product that cannot be bought" do
      add_to_cart(product_id: create(:product, :out_of_stock).id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "code")).to eq("out_of_stock")
    end

    it "returns 422 with field details for a bad quantity" do
      add_to_cart(quantity: 0)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.dig("error", "details")).to have_key("quantity")
    end

    it "returns 400 when product_id is missing" do
      post "/api/v1/cart/items", params: { quantity: 1 }, headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "PATCH /api/v1/cart/items/:id" do
    let(:item_id) do
      add_to_cart
      cart_body["items"].sole["id"]
    end

    # SET, not increment: repeating it is harmless, so a client may retry.
    it "sets the quantity idempotently" do
      2.times { patch "/api/v1/cart/items/#{item_id}", params: { quantity: 4 }, headers: }

      expect(response).to have_http_status(:ok)
      expect(cart_body["items"].sole["quantity"]).to eq(4)
    end

    it "refuses zero rather than treating it as removal" do
      patch "/api/v1/cart/items/#{item_id}", params: { quantity: 0 }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(CartItem.find(item_id).quantity).to eq(1)
    end

    it "refuses a quantity above the maximum" do
      patch "/api/v1/cart/items/#{item_id}", params: { quantity: 1000 }, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    # An id is a guessable integer; scoping through the caller's cart makes
    # another customer's line 404, not 403.
    it "returns 404 for another customer's line" do
      item_id
      stranger = auth_headers_for(create(:user))
      add_to_cart(product_id: create(:product, :in_stock).id, as: stranger)

      patch "/api/v1/cart/items/#{item_id}", params: { quantity: 9 }, headers: stranger

      expect(response).to have_http_status(:not_found)
      expect(CartItem.find(item_id).quantity).to eq(1)
    end

    it "returns 404 when the caller has no cart at all" do
      item_id

      patch "/api/v1/cart/items/#{item_id}", params: { quantity: 2 },
                                             headers: auth_headers_for(create(:user))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/cart/items/:id" do
    it "removes the line and returns the updated cart" do
      add_to_cart
      add_to_cart(product_id: create(:product, :in_stock).id)
      first_id = cart_body["items"].first["id"]

      delete "/api/v1/cart/items/#{first_id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(cart_body["items"].map { |i| i["id"] }).not_to include(first_id)
      expect(cart_body["items"].size).to eq(1)
    end
  end

  describe "DELETE /api/v1/cart" do
    it "empties the cart but keeps it" do
      add_to_cart

      expect { delete "/api/v1/cart", headers: }.not_to change(Cart, :count)

      expect(response).to have_http_status(:no_content)
      expect(CartItem.count).to eq(0)
    end

    it "is idempotent, including when there is no cart" do
      delete "/api/v1/cart", headers: headers

      expect(response).to have_http_status(:no_content)
    end
  end
end
