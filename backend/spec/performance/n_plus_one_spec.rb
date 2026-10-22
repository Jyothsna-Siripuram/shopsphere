require "rails_helper"

# The defining property of an N+1 is that query count grows with record count.
# Each example therefore runs the same code against two different dataset sizes
# and asserts the count did not change — which no snapshot of an absolute number
# can tell you.
RSpec.describe "N+1 query prevention", type: :request do
  describe "Product.with_listing_associations" do
    # Setup happens OUTSIDE the counted block. Creating records inside it would
    # count the factory's INSERTs, which grow with N regardless of eager
    # loading, and the assertion would fail even on perfectly batched reads.
    it "issues the same number of queries for 1 product as for 5" do
      create(:product, :in_stock)
      one = count_queries { read_listing }

      4.times { create(:product, :in_stock) }
      many = count_queries { read_listing }

      expect(many.size).to eq(one.size),
                           "query count grew from #{one.size} to #{many.size}: #{many.last(3)}"
    end

    # Guards the inverse mistake: a scope that eager loads nothing still has a
    # stable count if the spec never touches the associations.
    it "does not fall back to lazy loading when associations are touched" do
      3.times { create(:product, :in_stock) }

      queries = count_queries do
        Product.with_listing_associations.each do |product|
          product.category.slug
          product.inventory&.available_quantity
          product.product_images.map(&:storage_key)
        end
      end

      # One each for products, categories, inventories and images.
      expect(queries.size).to eq(4)
    end

    def read_listing
      Product.with_listing_associations.to_a.each do |product|
        product.category.slug
        product.inventory&.available_quantity
        product.product_images.to_a
      end
    end
  end

  describe "Order.with_detail_associations" do
    it "issues the same number of queries for 1 order as for 4" do
      build_order
      one = count_queries { read_orders }

      3.times { build_order }
      many = count_queries { read_orders }

      expect(many.size).to eq(one.size),
                           "query count grew from #{one.size} to #{many.size}"
    end

    def build_order
      order = create(:order, user: create(:user))
      create(:order_item, order:)
      create(:payment, order:)
    end

    def read_orders
      Order.with_detail_associations.to_a.each do |order|
        order.order_items.map(&:product_name)
        order.order_items.map { |item| item.product.slug }
        order.payments.map(&:status)
      end
    end
  end

  describe "Cart#items_subtotal" do
    # The method reads item.product.price, so it is N+1 free only when the cart
    # is loaded through with_pricing_associations. Nothing in the model forces
    # that; the cart endpoint (Day 10) opts in through CartLoading, and
    # spec/requests/api/v1/cart_spec.rb asserts the endpoint stays flat.
    #
    # Asserted by growth, like every other example here: an absolute
    # eager-vs-lazy comparison broke as soon as the scope legitimately started
    # loading one more association.
    def subtotal_queries(lines, eager:)
      cart = create(:cart)
      lines.times { create(:cart_item, cart:, product: create(:product, :in_stock)) }
      relation = eager ? Cart.with_pricing_associations : Cart.all

      count_queries { relation.find(cart.id).items_subtotal }
    end

    it "stays flat as lines are added when loaded eagerly" do
      expect(subtotal_queries(4, eager: true).size).to eq(subtotal_queries(1, eager: true).size)
    end

    it "grows with lines when loaded lazily — the hazard the scope prevents" do
      expect(subtotal_queries(4, eager: false).size).to be > subtotal_queries(1, eager: false).size
    end
  end

  describe "request endpoints" do
    it "keeps the address listing flat as addresses accumulate" do
      user = create(:user)
      headers = { "Authorization" => "Bearer #{Auth::AccessToken.encode(user)}" }

      create(:address, user:)
      one = count_queries { get "/api/v1/addresses", headers: headers }

      3.times { create(:address, user:, kind: "billing") }
      many = count_queries { get "/api/v1/addresses", headers: headers }

      expect(many.size).to eq(one.size)
    end
  end
end
