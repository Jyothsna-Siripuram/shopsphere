require "rails_helper"

RSpec.describe ProductSearchQuery do
  def search(params)
    described_class.new(relation: Product.all, params: params).call
  end

  describe "sorting" do
    it "orders newest first by default" do
      older = create(:product, published_at: 3.days.ago)
      newer = create(:product, published_at: 1.hour.ago)

      expect(search({})).to eq([ newer, older ])
    end

    it "supports the price orderings" do
      cheap = create(:product, price: "5.00")
      dear = create(:product, price: "500.00")

      expect(search(sort: "price_asc")).to eq([ cheap, dear ])
      expect(search(sort: "price_desc")).to eq([ dear, cheap ])
    end

    # The SQL injection defence. The client sends a KEY into a frozen hash;
    # the fragment it maps to is hardcoded, so a crafted value cannot reach
    # the ORDER BY clause. Active Record cannot parameterize an ORDER BY
    # identifier, which is why an allowlist is the only safe approach.
    it "ignores an unknown sort key instead of using it" do
      create(:product)

      expect { search(sort: "price; DROP TABLE products") }.not_to raise_error
      expect(Product.count).to eq(1)
    end

    it "falls back to the default ordering for an unknown key" do
      older = create(:product, published_at: 3.days.ago)
      newer = create(:product, published_at: 1.hour.ago)

      expect(search(sort: "nonsense")).to eq([ newer, older ])
    end

    it "never puts a raw sort value into the generated SQL" do
      sql = described_class.new(params: { sort: "evil_column" }).call.to_sql

      expect(sql).not_to include("evil_column")
      expect(sql).to include("published_at")
    end

    # ADR-011: without a unique tiebreaker, an ordering over tied values is
    # non-deterministic, so page 2 can repeat a row from page 1 with no writes
    # at all.
    it "appends id to every ordering so paging is deterministic" do
      described_class::SORTS.each_key do |key|
        expect(described_class.new(params: { sort: key }).call.to_sql)
          .to match(/"products"\."id" DESC/)
      end
    end

    it "returns tied rows in a stable order across repeated queries" do
      3.times { create(:product, price: "10.00") }

      first = search(sort: "price_asc").map(&:id)
      second = search(sort: "price_asc").map(&:id)

      expect(first).to eq(second)
    end
  end

  describe "filtering" do
    it "filters by category slug" do
      shoes = create(:category, slug: "shoes")
      wanted = create(:product, category: shoes)
      create(:product, category: create(:category, slug: "hats"))

      expect(search(category: "shoes")).to contain_exactly(wanted)
    end

    it "matches a category slug case-insensitively" do
      create(:product, category: create(:category, slug: "shoes"))

      expect(search(category: "SHOES").count).to eq(1)
    end

    it "filters by a minimum and maximum price inclusively" do
      cheap = create(:product, price: "10.00")
      mid = create(:product, price: "50.00")
      dear = create(:product, price: "100.00")

      expect(search(min_price: "50")).to contain_exactly(mid, dear)
      expect(search(max_price: "50")).to contain_exactly(cheap, mid)
      expect(search(min_price: "10", max_price: "50")).to contain_exactly(cheap, mid)
    end

    # A Float bound would reintroduce the precision problem numeric(12,2)
    # exists to avoid (ADR-002).
    it "binds price filters as decimals, not floats" do
      create(:product, price: "0.30")

      expect(search(min_price: "0.30").count).to eq(1)
    end

    it "ignores a malformed price filter rather than failing" do
      create(:product, price: "10.00")

      expect(search(min_price: "not-a-price").count).to eq(1)
    end

    it "ignores values BigDecimal accepts but a price is not" do
      create(:product, price: "10.00")

      %w[NaN Infinity -5 1e999999 0x10].each do |value|
        expect(search(min_price: value).count).to eq(1), "#{value} was not ignored"
      end
    end

    it "filters to products with stock when asked" do
      stocked = create(:product, :in_stock)
      create(:product, :out_of_stock)
      create(:product) # no inventory row at all

      expect(search(in_stock: "true")).to contain_exactly(stocked)
    end

    it "does not filter by stock unless the flag is truthy" do
      create(:product, :out_of_stock)

      expect(search(in_stock: "false").count).to eq(1)
      expect(search({}).count).to eq(1)
    end
  end

  describe "search" do
    def query(params)
      described_class.new(relation: Product.all, params: params)
    end

    it "matches by stem, which ILIKE cannot" do
      runner = create(:product, name: "Trail Running Shoe")
      create(:product, name: "Wool Scarf")

      expect(search(q: "running shoes")).to contain_exactly(runner)
    end

    it "matches words in the description" do
      described = create(:product, name: "Tote", description: "Waxed canvas with leather handles")

      expect(search(q: "leather")).to contain_exactly(described)
    end

    it "requires every word, in any order" do
      both = create(:product, name: "Leather Boot")
      create(:product, name: "Leather Belt")

      expect(search(q: "boot leather")).to contain_exactly(both)
    end

    it "supports web-search syntax: an excluded word" do
      wool = create(:product, name: "Wool Boot")
      create(:product, name: "Leather Boot")

      expect(search(q: "boot -leather")).to contain_exactly(wool)
    end

    # to_tsquery would raise a syntax error on these; websearch_to_tsquery
    # accepts anything a person can type.
    it "never raises on operator characters in the input" do
      create(:product, name: "Boot")

      [ "boot &", "boot | (", "!!", %q('"), ":*" ].each do |input|
        expect { search(q: input).to_a }.not_to raise_error, "raised on #{input.inspect}"
      end
    end

    it "treats SQL in the term as data" do
      create(:product, name: "Boot")

      expect { search(q: "'); DROP TABLE products; --").to_a }.not_to raise_error
      expect(Product.count).to eq(1)
    end

    # The pg driver rejects a NUL byte before the query is sent, which would be
    # a 500 from a query string.
    it "strips control characters instead of failing" do
      boot = create(:product, name: "Boot")

      expect(search(q: "boot\u0000")).to contain_exactly(boot)
    end

    it "caps the term length" do
      expect(query(q: "boot " * 100).search_term.length).to be <= described_class::MAX_QUERY_LENGTH
    end

    it "ignores a blank term" do
      create(:product)

      q = query(q: "   ")

      expect(q.call.count).to eq(1)
      expect(q.search_mode).to be_nil
      expect(q.search_metadata).to be_nil
    end

    describe "typo fallback" do
      it "falls back to trigram similarity when full text finds nothing" do
        leather = create(:product, name: "Leather Boot")
        create(:product, name: "Wool Scarf")

        q = query(q: "lether")

        expect(q.call).to contain_exactly(leather)
        expect(q.search_mode).to eq("fuzzy")
      end

      # The fallback is slower and noisier, so it must not run when exact
      # results exist — and must not dilute them.
      it "does not fall back when full text has results" do
        exact = create(:product, name: "Leather Boot")
        create(:product, name: "Lather Soap")

        q = query(q: "leather")

        expect(q.call).to contain_exactly(exact)
        expect(q.search_mode).to eq("fulltext")
      end

      it "returns nothing for a term resembling no product" do
        create(:product, name: "Leather Boot")

        q = query(q: "xylophone")

        expect(q.call).to be_empty
        expect(q.search_mode).to eq("fuzzy")
      end

      # Decided against the relation it was given, so the fallback's decision
      # respects every filter rather than the whole catalogue.
      it "decides on the filtered set, not the whole catalogue" do
        boots = create(:category, slug: "boots")
        create(:product, name: "Leather Boot", category: boots)
        create(:product, name: "Leather Belt", category: create(:category, slug: "belts"))

        q = query(q: "belt", category: "boots")

        expect(q.call).to be_empty
        expect(q.search_mode).to eq("fuzzy")
      end
    end

    describe "ordering" do
      it "defaults to relevance, ranking a name match above a description match" do
        mentions = create(:product, name: "Scarf", description: "Matches any boot",
                                    published_at: 1.minute.ago)
        named = create(:product, name: "Boot", description: "Sturdy", published_at: 1.year.ago)

        q = query(q: "boot")

        expect(q.call.to_a).to eq([ named, mentions ])
        expect(q.sort_key).to eq("relevance")
      end

      it "honours an explicit sort over relevance" do
        dear = create(:product, name: "Boot", price: "90.00")
        cheap = create(:product, name: "Boot Liner", price: "10.00")

        expect(search(q: "boot", sort: "price_asc").to_a).to eq([ cheap, dear ])
      end

      it "ranks fuzzy results by similarity" do
        close = create(:product, name: "Leather Wallet")
        create(:product, name: "Feathered Leatherette Cap")

        expect(search(q: "lether wallet").first).to eq(close)
      end

      it "ignores relevance when there is no search" do
        older = create(:product, published_at: 2.days.ago)
        newer = create(:product, published_at: 1.hour.ago)

        q = query(sort: "relevance")

        expect(q.call.to_a).to eq([ newer, older ])
        expect(q.sort_key).to eq(described_class::DEFAULT_SORT)
      end

      it "keeps the id tiebreaker on relevance" do
        expect(query(q: "boot").call.to_sql).to match(/"products"\."id" DESC/)
      end
    end
  end

  describe "composition" do
    it "applies filters together" do
      shoes = create(:category, slug: "shoes")
      wanted = create(:product, :in_stock, category: shoes, price: "50.00")
      create(:product, :in_stock, category: shoes, price: "500.00")
      create(:product, :out_of_stock, category: shoes, price: "50.00")

      result = search(category: "shoes", max_price: "100", in_stock: "true")

      expect(result).to contain_exactly(wanted)
    end

    # The query object must not decide visibility: that belongs to
    # ProductPolicy::Scope, and duplicating it here would create two places
    # where a draft product could leak.
    it "respects the relation it is given rather than widening it" do
      create(:product, :draft)
      published = create(:product, status: "active", published_at: 1.day.ago)

      result = described_class.new(relation: Product.published, params: {}).call

      expect(result).to contain_exactly(published)
    end
  end
end
