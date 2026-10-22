# Search, filtering and ordering for the catalogue.
#
# A query object rather than scopes on Product because the combination logic —
# which filters are present, how they compose, what the fallback ordering is —
# is request-shaped rather than domain-shaped.
#
# Search (ADR-012) is full-text first, with a trigram fallback for typos:
#
#   1. `search_vector @@ websearch_to_tsquery(q)` — stemmed, weighted, indexed.
#      "running shoes" finds "Trail Running Shoe"; ILIKE finds nothing.
#   2. Only if that finds NOTHING, `q <% name` — trigram word similarity, which
#      tolerates "lether" for "leather" but is slower and noisier, so the
#      common path never pays for it.
#
# #search_mode reports which one ran, so the client can say "showing results
# for similar terms" instead of presenting fuzzy matches as exact ones.
#
# The relation is supplied by the caller and is expected to be already
# authorized (ProductPolicy::Scope), so this object never decides visibility.
class ProductSearchQuery
  # The ORDER BY allowlist, and the reason this is a frozen hash rather than
  # string handling.
  #
  # `ORDER BY #{params[:sort]}` is SQL injection: Active Record cannot
  # parameterize an ORDER BY identifier, so a bind variable is not available
  # here. The client sends a KEY; the fragment it maps to is hardcoded. An
  # attacker can therefore only choose among these orderings.
  SORTS = {
    "newest" => { published_at: :desc },
    "oldest" => { published_at: :asc },
    "price_asc" => { price: :asc },
    "price_desc" => { price: :desc },
    "name" => { name: :asc }
  }.freeze

  # Not in SORTS: its ORDER BY depends on the search term, so it is built
  # rather than looked up. Meaningful only alongside a search.
  RELEVANCE = "relevance"

  DEFAULT_SORT = "newest"

  # websearch_to_tsquery cost grows with input, and no real product search is
  # longer than this. Truncated rather than rejected, like every other
  # malformed browsing parameter.
  MAX_QUERY_LENGTH = 100

  # A plain non-negative amount: digits, optionally a fractional part.
  #
  # Validated by shape rather than handed to BigDecimal(), which accepts far
  # more than a price — "NaN", "Infinity", "1e999999". The last one overflows
  # PostgreSQL's numeric and turns a query string into a 500. Ten integer
  # digits is the ceiling numeric(12,2) can hold anyway.
  PRICE_FORMAT = /\A\d{1,10}(?:\.\d+)?\z/

  def initialize(relation: Product.all, params: {})
    @relation = relation
    @params = params || {}
  end

  # nil when no search was requested, otherwise "fulltext" or "fuzzy". Set by
  # #call.
  attr_reader :search_mode

  def call
    scope = relation
    scope = filter_by_category(scope)
    scope = filter_by_price(scope)
    scope = filter_by_stock(scope)
    scope = search(scope)
    order(scope)
  end

  # The sort actually applied. A search defaults to relevance; an unknown key,
  # or relevance without a search, falls back to the default.
  def sort_key
    key = params[:sort].to_s
    return key if SORTS.key?(key)
    return RELEVANCE if search_term && (key.empty? || key == RELEVANCE)

    DEFAULT_SORT
  end

  # Echoed in the response `meta`, so a client can show what was actually
  # searched (after truncation) and whether the results are fuzzy. nil without
  # a search, and only meaningful after #call.
  def search_metadata
    return nil unless search_term

    { query: search_term, mode: search_mode, sort: sort_key }
  end

  # The term as searched: control characters removed (a NUL byte makes the pg
  # driver raise before the query is even sent), whitespace collapsed, length
  # capped. nil when nothing searchable remains.
  def search_term
    return @search_term if defined?(@search_term)

    @search_term = params[:q].to_s.gsub(/[[:cntrl:]]/, " ").squish
                             .first(MAX_QUERY_LENGTH).presence
  end

  private

  attr_reader :relation, :params

  # Accepts a category slug rather than an id, so a storefront link survives a
  # database reseed and reads meaningfully.
  def filter_by_category(scope)
    slug = params[:category].presence
    return scope if slug.nil?

    scope.where(category: Category.where(slug: slug.to_s.downcase))
  end

  # BigDecimal, not Float: a Float bound would reintroduce the precision
  # problem that numeric(12,2) exists to avoid (ADR-002).
  def filter_by_price(scope)
    scope = scope.where(price: decimal(params[:min_price])..) if decimal(params[:min_price])
    scope = scope.where(price: ..decimal(params[:max_price])) if decimal(params[:max_price])
    scope
  end

  # Joins rather than includes: this is a filter, not a read of the
  # association. The caller adds eager loading via with_listing_associations,
  # and Rails deduplicates the inventories reference.
  def filter_by_stock(scope)
    return scope unless ActiveModel::Type::Boolean.new.cast(params[:in_stock])

    scope.joins(:inventory).where(Inventory.arel_table[:available_quantity].gt(0))
  end

  # websearch_to_tsquery, never to_tsquery: it accepts any string a person can
  # type — quotes, OR, a leading "-" to exclude — and never raises a syntax
  # error. to_tsquery raises on "shoes &", so user input would become a 500.
  #
  # The term is a bind parameter in both branches. It is data, not SQL, so
  # unlike the ORDER BY key it never needs an allowlist.
  def search(scope)
    return scope unless search_term

    fulltext = scope.where("products.search_vector @@ websearch_to_tsquery('english', ?)",
                           search_term)
    # One cheap EXISTS (it stops at the first match and uses the GIN index)
    # decides whether the fallback is needed. Measured: the fallback costs
    # 20-40 ms at 10k products, so it must not run on searches that already
    # have results.
    if fulltext.exists?
      @search_mode = "fulltext"
      fulltext
    else
      @search_mode = "fuzzy"
      scope.where("? <% products.name", search_term)
    end
  end

  # Every ordering carries `id` as a tiebreaker (ADR-011).
  #
  # Without it, ORDER BY price ASC across products sharing a price is
  # non-deterministic: PostgreSQL may return them in any order, so page 2 can
  # repeat a row from page 1 even when nothing has been written. This is a more
  # common bug than the insertion drift offset pagination is usually criticised
  # for.
  def order(scope)
    return scope.order(relevance_order, id: :desc) if sort_key == RELEVANCE

    scope.order(**SORTS.fetch(sort_key), id: :desc)
  end

  # ts_rank, not ts_rank_cd. Cover density also weighs how close the terms sit,
  # but it measured 10-40x slower (197 ms vs 19 ms for a common term at 10k
  # products) because every match must be ranked before LIMIT applies. The
  # A/B weights already put name matches first, which is most of what
  # relevance means for product titles.
  def relevance_order
    sql =
      if search_mode == "fulltext"
        "ts_rank(products.search_vector, websearch_to_tsquery('english', ?)) DESC"
      else
        "word_similarity(?, products.name) DESC"
      end

    Arel.sql(Product.sanitize_sql_array([ sql, search_term ]))
  end

  # A malformed price filter is ignored rather than fatal, consistent with how
  # Pagination treats a malformed page.
  def decimal(value)
    string = value.to_s.strip
    return nil unless PRICE_FORMAT.match?(string)

    BigDecimal(string)
  end
end
