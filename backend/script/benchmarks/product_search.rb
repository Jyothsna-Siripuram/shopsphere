# Measures candidate product-search strategies against a realistic catalogue.
#
#   bin/rails runner script/benchmarks/product_search.rb            # 100k products
#   PRODUCTS=20000 bin/rails runner script/benchmarks/product_search.rb
#
# Everything — the extension, the generated column, the indexes and every
# inserted row — happens inside ONE transaction that is rolled back, so the
# script leaves the database exactly as it found it and can be rerun freely.
# Run it against development, never production: it rewrites the products table
# inside that transaction and holds an ACCESS EXCLUSIVE lock while it does.
#
# It exists so ADR-012 rests on numbers rather than on received wisdom. The
# figures are only as good as the synthetic data: vocabulary is Zipf-weighted to
# imitate real text, but no generator reproduces how real customers write
# product copy. Re-measure against production-shaped data before relying on
# absolute numbers; the RELATIVE ordering of strategies is the finding.
abort "Refusing to run outside development" unless Rails.env.development?

module ProductSearchBenchmark
  PRODUCTS = Integer(ENV.fetch("PRODUCTS", "100000"))
  WRITE_SAMPLE = 5_000
  RUNS = 7

  BRANDS = %w[Northwind Alpine Vertex Harbor Summit Cobalt Ember Juniper Atlas Meridian
              Solstice Granite Willow Falcon Oakridge Tidal Lumen Quarry Aspen Kestrel].freeze
  ADJECTIVES = %w[Lightweight Waterproof Classic Vintage Slim Rugged Everyday Premium
                  Breathable Insulated Packable Stretch Organic Recycled Heritage].freeze
  MATERIALS = %w[Leather Canvas Wool Cotton Linen Suede Nylon Denim Merino Fleece].freeze
  NOUNS = %w[Shoe Boot Sneaker Sandal Jacket Parka Shirt Sweater Hoodie Backpack Wallet Belt
             Scarf Beanie Glove Sock Trouser Short Dress Skirt Tote Duffel Watch Cap].freeze
  USES = %w[Running Hiking Travel Trail Office Weekend Winter Summer Yoga Cycling].freeze

  # Words a description is built from, most common first. Sampling with a Zipf
  # weight makes a few words very frequent and most of them rare, which is
  # what drives index selectivity in real text — a uniform sample would make
  # every term equally selective and flatter the slow strategies.
  FILLER = (%w[the and with for a of in to is this our that your it on made from
               comfortable durable soft designed perfect all day wear features
               pocket fit easy care lining zip adjustable warm cool dry quality
               style colour season outdoor urban sole strap collar cuff hem] +
            MATERIALS.map(&:downcase) + NOUNS.map(&:downcase) + USES.map(&:downcase) +
            Array.new(3_000) { |i| "term#{i.to_s(36)}" }).freeze

  QUERIES = {
    "common term" => "shoe",
    # Rank 1,500 of the Zipf vocabulary: present in a few hundred descriptions.
    "rare term" => FILLER[1_500],
    "two words" => "leather boot",
    "plural / stem" => "running shoes",
    "typo" => "lether",
    "partial word" => "snea"
  }.freeze

  module_function

  def run
    conn = ActiveRecord::Base.connection
    results = []

    conn.transaction do
      conn.execute("SET LOCAL jit = off") # JIT compile time is noise at this size
      category_ids = seed_categories
      insert_products(category_ids, PRODUCTS, prefix: "bench")
      conn.execute("ANALYZE products")

      write_cost = { "no search index" => timed_insert(category_ids, "w0") }

      results << measure("A. ILIKE, no index") { |q| ilike_sql(q) }

      conn.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
      conn.execute("CREATE INDEX bench_trgm_name ON products USING gin (name gin_trgm_ops)")
      conn.execute("CREATE INDEX bench_trgm_desc ON products USING gin (description gin_trgm_ops)")
      conn.execute("ANALYZE products")
      trgm_size = size_of(%w[bench_trgm_name bench_trgm_desc])
      write_cost["pg_trgm on name + description"] = timed_insert(category_ids, "w1")

      results << measure("B. ILIKE + pg_trgm GIN") { |q| ilike_sql(q) }
      results << measure("D. trigram word_similarity (name), threshold 0.6") { |q| trigram_sql(q) }
      # The default threshold rejects a one-letter typo in a short word:
      # word_similarity('lether', 'Leather') is exactly 0.5.
      conn.execute("SET LOCAL pg_trgm.word_similarity_threshold = 0.4")
      results << measure("D'. trigram word_similarity (name), threshold 0.4") { |q| trigram_sql(q) }

      conn.execute("DROP INDEX bench_trgm_desc")
      conn.execute(<<~SQL)
        ALTER TABLE products ADD COLUMN bench_vector tsvector GENERATED ALWAYS AS (
          setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(description, '')), 'B')
        ) STORED
      SQL
      conn.execute("CREATE INDEX bench_fts ON products USING gin (bench_vector)")
      conn.execute("ANALYZE products")
      fts_size = size_of(%w[bench_fts])
      write_cost["tsvector (stored) + trgm on name"] = timed_insert(category_ids, "w2")

      results << measure("C. tsvector, newest first") { |q| fts_sql(q, ranked: false) }
      results << measure("C'. tsvector, ts_rank_cd") { |q| fts_sql(q, ranked: "ts_rank_cd") }
      results << measure("C''. tsvector, ts_rank") { |q| fts_sql(q, ranked: "ts_rank") }

      report(results, write_cost, trgm_size: trgm_size, fts_size: fts_size,
                                  name_trgm_size: size_of(%w[bench_trgm_name]))
      raise ActiveRecord::Rollback
    end
  end

  # -- data ------------------------------------------------------------------

  def seed_categories
    now = Time.current
    rows = NOUNS.each_with_index.map do |noun, i|
      { name: "Bench #{noun}", slug: "bench-#{noun.downcase}", position: i,
        created_at: now, updated_at: now }
    end
    Category.insert_all!(rows, returning: :id).rows.flatten
  end

  def insert_products(category_ids, count, prefix:)
    rng = Random.new(42)
    zipf = zipf_sampler(FILLER.size, rng)
    now = Time.current

    count.times.each_slice(5_000) do |slice|
      rows = slice.map do |i|
        name = [ BRANDS.sample(random: rng), ADJECTIVES.sample(random: rng),
                 (USES.sample(random: rng) if rng.rand < 0.4),
                 MATERIALS.sample(random: rng), NOUNS.sample(random: rng) ].compact.join(" ")
        description = Array.new(rng.rand(25..70)) { FILLER[zipf.call] }.join(" ")

        { category_id: category_ids.sample(random: rng), name: name, description: description,
          slug: "#{prefix}-#{i}", sku: "#{prefix.upcase}-#{i}",
          price: (rng.rand(500..30_000) / 100.0).round(2), status: "active",
          published_at: now - rng.rand(0..31_536_000), created_at: now, updated_at: now }
      end
      Product.insert_all!(rows)
    end
  end

  # Inverse-CDF sampling over 1/rank weights.
  def zipf_sampler(size, rng)
    weights = (1..size).map { |rank| 1.0 / rank }
    total = weights.sum
    cumulative = weights.each_with_object([]) { |w, acc| acc << (acc.last.to_f + (w / total)) }
    -> { cumulative.bsearch_index { |c| c >= rng.rand } || (size - 1) }
  end

  def timed_insert(category_ids, prefix)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    insert_products(category_ids, WRITE_SAMPLE, prefix: prefix)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  end

  # -- candidate SQL ---------------------------------------------------------
  #
  # Each candidate returns the endpoint's real shape: a page of 24 plus the
  # COUNT for pagination metadata. Measuring only `LIMIT 24` would hide the
  # dominant cost — counting every match of a common term.

  VISIBLE = "status = 'active' AND published_at IS NOT NULL".freeze

  def ilike_sql(term)
    pattern = ActiveRecord::Base.connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    where = "#{VISIBLE} AND (name ILIKE #{pattern} OR description ILIKE #{pattern})"
    page_and_count(where, "published_at DESC, id DESC")
  end

  def trigram_sql(term)
    quoted = ActiveRecord::Base.connection.quote(term)
    page_and_count("#{VISIBLE} AND #{quoted} <% name",
                   "word_similarity(#{quoted}, name) DESC, id DESC")
  end

  def fts_sql(term, ranked:)
    query = "websearch_to_tsquery('english', #{ActiveRecord::Base.connection.quote(term)})"
    order = ranked ? "#{ranked}(bench_vector, #{query}) DESC, id DESC" : "published_at DESC, id DESC"
    page_and_count("#{VISIBLE} AND bench_vector @@ #{query}", order)
  end

  def page_and_count(where, order)
    { page: "SELECT id FROM products WHERE #{where} ORDER BY #{order} LIMIT 24",
      count: "SELECT count(*) FROM products WHERE #{where}" }
  end

  # -- measurement -----------------------------------------------------------

  def measure(label)
    rows = QUERIES.map do |kind, term|
      sql = yield(term)
      matches = ActiveRecord::Base.connection.select_value(sql[:count]).to_i
      page_ms = median_ms(sql[:page])
      count_ms = median_ms(sql[:count])
      { kind: kind, term: term, matches: matches, page_ms: page_ms, count_ms: count_ms,
        plan: scan_nodes(sql[:count]) }
    end
    { label: label, rows: rows }
  end

  def median_ms(sql)
    times = Array.new(RUNS) do
      plan = ActiveRecord::Base.connection.select_value("EXPLAIN (ANALYZE, FORMAT JSON) #{sql}")
      JSON.parse(plan).first["Execution Time"]
    end
    times.sort[RUNS / 2].round(2)
  end

  def scan_nodes(sql)
    plan = JSON.parse(ActiveRecord::Base.connection.select_value("EXPLAIN (FORMAT JSON) #{sql}"))
    nodes = []
    walk = lambda do |node|
      nodes << node["Node Type"] if node["Node Type"].to_s.include?("Scan")
      Array(node["Plans"]).each(&walk)
    end
    walk.call(plan.first["Plan"])
    nodes.uniq.join(", ")
  end

  def size_of(indexes)
    list = indexes.map { |name| ActiveRecord::Base.connection.quote(name) }.join(", ")
    ActiveRecord::Base.connection.select_value(
      "SELECT pg_size_pretty(sum(pg_relation_size(c.oid))) FROM pg_class c WHERE c.relname IN (#{list})"
    )
  end

  def report(results, write_cost, sizes)
    puts "\n# Product search benchmark — #{PRODUCTS} products, median of #{RUNS} runs\n\n"
    puts "| Strategy | Query | Term | Matches | Page ms | Count ms | Scan |"
    puts "|---|---|---|---:|---:|---:|---|"
    results.each do |result|
      result[:rows].each do |r|
        puts "| #{result[:label]} | #{r[:kind]} | `#{r[:term]}` | #{r[:matches]} | " \
             "#{r[:page_ms]} | #{r[:count_ms]} | #{r[:plan]} |"
      end
    end
    puts "\n| Index | Size |\n|---|---|"
    puts "| pg_trgm GIN on name + description | #{sizes[:trgm_size]} |"
    puts "| pg_trgm GIN on name only | #{sizes[:name_trgm_size]} |"
    puts "| tsvector GIN | #{sizes[:fts_size]} |"
    puts "\n| Indexes present | Insert #{WRITE_SAMPLE} products (ms) |\n|---|---:|"
    write_cost.each { |label, ms| puts "| #{label} | #{ms} |" }
  end
end

ProductSearchBenchmark.run
