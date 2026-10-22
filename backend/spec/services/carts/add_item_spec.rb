require "rails_helper"

RSpec.describe Carts::AddItem do
  let(:user) { create(:user) }
  let(:product) { create(:product, :in_stock) }

  def add(quantity = 1, to: product)
    described_class.call(user: user, product: to, quantity: quantity)
  end

  it "creates the active cart on first add" do
    expect { add }.to change(Cart, :count).by(1)

    expect(user.reload.active_cart.cart_items.sole).to have_attributes(product_id: product.id, quantity: 1)
  end

  it "increments the existing line rather than adding a second one" do
    add(2)
    add(3)

    expect(CartItem.sole.quantity).to eq(5)
  end

  it "reuses the active cart rather than creating another" do
    add
    expect { add(1, to: create(:product, :in_stock)) }.not_to change(Cart, :count)
  end

  it "starts a fresh cart once the previous one has converted" do
    create(:cart, user:, status: "converted")

    expect { add }.to change(Cart, :count).by(1)
  end

  # The cap holds even though upsert bypasses validations, because LEAST is
  # applied inside the statement.
  it "caps an incremented line at the maximum" do
    add(60)
    add(60)

    expect(CartItem.sole.quantity).to eq(CartItem::MAX_QUANTITY)
  end

  it "touches the cart so idle carts can be told from active ones" do
    add
    cart = user.reload.active_cart

    travel 1.hour do
      expect { add }.to(change { cart.reload.updated_at })
    end
  end

  describe "refusals" do
    [ 0, -1, 100, "2abc", "abc", "1.5", nil ].each do |bad|
      it "refuses quantity #{bad.inspect}" do
        expect { add(bad) }.to raise_error(Carts::InvalidLine) { |e| expect(e.code).to eq("validation_failed") }
        expect(CartItem.count).to eq(0)
      end
    end

    it "accepts a quantity sent as a numeric string" do
      add("3")

      expect(CartItem.sole.quantity).to eq(3)
    end

    it "refuses an out-of-stock product" do
      expect { add(1, to: create(:product, :out_of_stock)) }
        .to raise_error(Carts::InvalidLine) { |e| expect(e.code).to eq("out_of_stock") }
    end

    it "refuses a product with no inventory row" do
      expect { add(1, to: create(:product)) }.to raise_error(Carts::InvalidLine)
    end

    it "creates no cart when it refuses" do
      expect { add(0) }.to raise_error(Carts::InvalidLine)
      expect(Cart.count).to eq(0)
    end

    # A cart is not a reservation, and refusing would disclose the stock level.
    it "accepts more than is in stock, leaving the line marked insufficient" do
      limited = create(:product, :in_stock, quantity: 2)

      add(5, to: limited)

      expect(CartItem.sole.availability).to eq("insufficient_stock")
    end
  end

  # Real threads on real connections, so these cannot run inside the usual
  # rolled-back transaction: the other connections would never see its rows.
  describe "under concurrency" do
    self.use_transactional_tests = false

    after do
      ActiveRecord::Base.connection.execute(
        "TRUNCATE cart_items, carts, inventories, products, categories, refresh_tokens, users CASCADE"
      )
    end

    # Leaves one connection for the main thread out of the test pool.
    let(:threads) { ActiveRecord::Base.connection_pool.size - 1 }

    def race(count)
      barrier = Concurrent::CyclicBarrier.new(count)

      Array.new(count) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            barrier.wait
            yield
          end
        end
      end.each(&:join)
    end

    # The two races this design exists to close, in one test: every thread
    # finds no cart and tries to create one, then every thread increments the
    # same line. A find-then-save implementation produces several carts, or
    # one line with quantity < N.
    it "loses no increment and creates exactly one cart" do
      user
      product

      race(threads) { described_class.call(user: user, product: product, quantity: 1) }

      expect(Cart.where(user: user).active.count).to eq(1)
      expect(CartItem.sole.quantity).to eq(threads)
    end
  end
end
