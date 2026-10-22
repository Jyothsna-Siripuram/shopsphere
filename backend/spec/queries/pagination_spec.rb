require "rails_helper"

RSpec.describe Pagination do
  describe "normalisation" do
    # A negative or zero page would produce a negative OFFSET, which
    # PostgreSQL rejects outright. Coercing is kinder than 400-ing on a stale
    # bookmark.
    it "coerces an absent, zero, negative or unparseable page to the first" do
      [ nil, "", "0", "-3", "abc" ].each do |value|
        expect(described_class.new(page: value).page).to eq(1)
      end
    end

    it "caps the page so the OFFSET cannot overflow bigint" do
      expect(described_class.new(page: "9" * 30).page).to eq(described_class::MAX_PAGE)
    end

    it "caps per_page so one request cannot ask for the whole table" do
      expect(described_class.new(per_page: "5000").per_page).to eq(described_class::MAX_PER_PAGE)
    end

    it "falls back to the default for an unusable per_page" do
      [ nil, "", "0", "-10", "nonsense" ].each do |value|
        expect(described_class.new(per_page: value).per_page)
          .to eq(described_class::DEFAULT_PER_PAGE)
      end
    end

    it "honours a per_page within bounds" do
      expect(described_class.new(per_page: "10").per_page).to eq(10)
    end
  end

  describe "#offset" do
    it "is zero on the first page and a multiple of per_page thereafter" do
      expect(described_class.new(page: 1, per_page: 10).offset).to eq(0)
      expect(described_class.new(page: 4, per_page: 10).offset).to eq(30)
    end
  end

  describe "#metadata" do
    it "rounds total_pages up so a partial final page is counted" do
      meta = described_class.new(page: 1, per_page: 10).metadata(25)

      expect(meta).to include(page: 1, per_page: 10, total_count: 25, total_pages: 3)
    end

    it "reports zero pages for an empty result rather than one empty page" do
      expect(described_class.new(per_page: 10).metadata(0)).to include(total_pages: 0)
    end

    it "reports one page when the count exactly fills it" do
      expect(described_class.new(per_page: 10).metadata(10)).to include(total_pages: 1)
    end
  end

  describe "#apply" do
    it "limits and offsets the relation" do
      5.times { create(:product) }

      result = described_class.new(page: 2, per_page: 2).apply(Product.order(:id))

      expect(result.to_a.size).to eq(2)
      expect(result.to_a).to eq(Product.order(:id).to_a[2..3])
    end
  end
end
