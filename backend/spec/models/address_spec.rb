require "rails_helper"

RSpec.describe Address, type: :model do
  let(:user) { create(:user) }

  describe "default handling" do
    # Regression: the partial unique index previously rejected this with a raw
    # PG::UniqueViolation, so a customer setting a new default got a 500.
    it "demotes the previous default of the same kind instead of failing" do
      first = create(:address, :default, user:, kind: "shipping")

      second = create(:address, :default, user:, kind: "shipping")

      expect(second.reload).to be_is_default
      expect(first.reload).not_to be_is_default
    end

    it "keeps shipping and billing defaults independent" do
      shipping = create(:address, :default, user:, kind: "shipping")
      billing = create(:address, :default, user:, kind: "billing")

      expect(shipping.reload).to be_is_default
      expect(billing.reload).to be_is_default
    end

    it "demotes siblings when an existing address is promoted" do
      current = create(:address, :default, user:, kind: "shipping")
      other = create(:address, user:, kind: "shipping")

      other.update!(is_default: true)

      expect(current.reload).not_to be_is_default
    end

    it "does not touch another customer's defaults" do
      mine = create(:address, :default, user:, kind: "shipping")
      theirs = create(:address, :default, user: create(:user), kind: "shipping")

      create(:address, :default, user:, kind: "shipping")

      expect(theirs.reload).to be_is_default
      expect(mine.reload).not_to be_is_default
    end

    it "leaves defaults alone when saving an unrelated attribute" do
      default = create(:address, :default, user:, kind: "shipping")

      default.update!(city: "Manchester")

      expect(default.reload).to be_is_default
    end
  end

  describe "#to_snapshot" do
    it "returns only the postal fields an order needs, omitting blanks" do
      address = build(:address, user:, line2: nil, region: nil)

      expect(address.to_snapshot.keys)
        .to contain_exactly("recipient_name", "line1", "city", "postal_code", "country_code")
    end

    # The snapshot must not carry database identifiers: it is a copy of the
    # postal data, not a reference (ADR-005).
    it "carries no identifiers that could be mistaken for a reference" do
      snapshot = create(:address, user:).to_snapshot

      expect(snapshot.keys).not_to include("id", "user_id")
    end
  end

  it "normalises the country code to uppercase" do
    expect(create(:address, user:, country_code: "gb").country_code).to eq("GB")
  end

  it "rejects a country code that is not two letters" do
    expect(build(:address, user:, country_code: "GBR")).not_to be_valid
  end
end
