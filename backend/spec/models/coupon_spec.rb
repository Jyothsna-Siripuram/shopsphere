require "rails_helper"

RSpec.describe Coupon, type: :model do
  describe "#discount_for" do
    it "applies a percentage of the subtotal" do
      coupon = build(:coupon, discount_type: "percentage", discount_value: 10)

      expect(coupon.discount_for(BigDecimal("200.00"))).to eq(BigDecimal("20.00"))
    end

    it "applies a fixed amount regardless of subtotal" do
      coupon = build(:coupon, :fixed_amount, discount_value: 5)

      expect(coupon.discount_for(BigDecimal("200.00"))).to eq(BigDecimal("5.00"))
    end

    it "caps a percentage discount at the maximum discount amount" do
      coupon = build(:coupon, discount_type: "percentage", discount_value: 50,
                              maximum_discount_amount: 30)

      expect(coupon.discount_for(BigDecimal("200.00"))).to eq(BigDecimal("30.00"))
    end

    # The orders table has CHECK (discount_amount <= subtotal_amount), so a
    # discount larger than the order would be rejected at write time. Clamping
    # here turns that into correct behaviour rather than a 500.
    it "never discounts more than the subtotal" do
      coupon = build(:coupon, :fixed_amount, discount_value: 500)

      expect(coupon.discount_for(BigDecimal("20.00"))).to eq(BigDecimal("20.00"))
    end

    it "rounds to two decimal places so the result is storable as money" do
      coupon = build(:coupon, discount_type: "percentage", discount_value: 33)

      # 33% of 10.00 is 3.30 exactly; 33% of 10.01 is 3.3033
      expect(coupon.discount_for(BigDecimal("10.01"))).to eq(BigDecimal("3.30"))
    end
  end

  describe "#redeemable?" do
    it "is false before the window opens and true inside it" do
      coupon = build(:coupon, starts_at: 1.day.from_now, expires_at: 2.days.from_now)

      expect(coupon).not_to be_redeemable
      expect(coupon.redeemable?(at: 36.hours.from_now)).to be(true)
    end

    it "is false once expired" do
      expect(build(:coupon, :expired)).not_to be_redeemable
    end

    it "is false once the usage limit is reached" do
      expect(build(:coupon, :exhausted)).not_to be_redeemable
    end

    it "is false when deactivated even inside a valid window" do
      expect(build(:coupon, active: false)).not_to be_redeemable
    end
  end

  it "rejects a percentage above one hundred" do
    expect(build(:coupon, discount_type: "percentage", discount_value: 150)).not_to be_valid
  end

  it "rejects an expiry that precedes the start" do
    coupon = build(:coupon, starts_at: Time.current, expires_at: 1.day.ago)

    expect(coupon).not_to be_valid
    expect(coupon.errors[:expires_at]).to be_present
  end

  it "matches codes case-insensitively by normalising to uppercase" do
    create(:coupon, code: "save20")

    expect(build(:coupon, code: "SAVE20")).not_to be_valid
  end
end
