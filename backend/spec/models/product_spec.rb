require "rails_helper"

RSpec.describe Product, type: :model do
  describe ".published" do
    it "returns only active products that have been published" do
      published = create(:product, status: "active", published_at: 1.day.ago)
      create(:product, :draft)
      create(:product, :archived)
      create(:product, status: "active", published_at: nil)

      expect(described_class.published).to contain_exactly(published)
    end
  end

  describe "#purchasable?" do
    it "is true only for an active product with stock" do
      expect(create(:product, :in_stock)).to be_purchasable
    end

    it "is false when stock is exhausted" do
      expect(create(:product, :out_of_stock)).not_to be_purchasable
    end

    # A product can be archived while stock remains; it must still not sell.
    it "is false when the product is not active" do
      product = create(:product, :archived)
      create(:inventory, product:, available_quantity: 5)

      expect(product.reload).not_to be_purchasable
    end

    it "is false when no inventory record exists at all" do
      expect(create(:product)).not_to be_purchasable
    end
  end

  describe "#primary_image" do
    it "prefers the image flagged primary over position order" do
      product = create(:product)
      create(:product_image, product:, position: 0)
      primary = create(:product_image, :primary, product:, position: 5)

      expect(product.reload.primary_image).to eq(primary)
    end

    it "falls back to the first image when none is flagged" do
      product = create(:product)
      first = create(:product_image, product:, position: 0)
      create(:product_image, product:, position: 1)

      expect(product.reload.primary_image).to eq(first)
    end
  end

  describe ".with_listing_associations" do
    it "eager loads inventory and images so a listing does not N+1" do
      product = create(:product, :in_stock)
      create(:product_image, product:)

      loaded = described_class.with_listing_associations.to_a.first

      expect(loaded.association(:inventory)).to be_loaded
      expect(loaded.association(:product_images)).to be_loaded
    end
  end

  it "normalises SKU to uppercase and rejects a case-variant duplicate" do
    create(:product, sku: "abc-1")

    expect(build(:product, sku: "ABC-1")).not_to be_valid
  end

  it "rejects a slug that is not URL safe" do
    expect(build(:product, slug: "Not A Slug")).not_to be_valid
  end
end
