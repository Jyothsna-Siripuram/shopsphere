# Offset pagination (ADR-011).
#
# A value object rather than a gem: kaminari and pagy both solve a harder
# problem than this needs — view helpers and template integration — for an API
# that only returns JSON metadata.
class Pagination
  DEFAULT_PER_PAGE = 24
  # An uncapped page size is an availability problem, not a performance one:
  # a single request asking for everything can exhaust memory and hold a
  # connection for the duration.
  MAX_PER_PAGE = 100
  # Without a ceiling, `page=99999999999999999999` multiplies into an OFFSET
  # beyond bigint and PostgreSQL raises — a 500 from a query string. A deep
  # OFFSET is also linear work for the database (it reads and discards every
  # skipped row), so nobody legitimately browses this far; ADR-011 reserves
  # cursor pagination for consumers that need to.
  MAX_PAGE = 10_000

  attr_reader :page, :per_page

  def initialize(page: nil, per_page: nil)
    @page = normalize_page(page)
    @per_page = normalize_per_page(per_page)
  end

  def offset
    (page - 1) * per_page
  end

  def apply(relation)
    relation.limit(per_page).offset(offset)
  end

  # Takes the count rather than computing it, so the caller decides when to pay
  # for it. COUNT(*) over a filtered relation is a second query against the
  # same predicate; a browsable grid needs it for a page count, but an endpoint
  # that does not should not be charged for it.
  def metadata(total_count)
    {
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_count.zero? ? 0 : (total_count.to_f / per_page).ceil
    }
  end

  private

  # Invalid input is coerced to the first page rather than rejected. A stale
  # bookmark or a hand-edited URL should degrade to something sensible, not
  # return 400 — and `to_i` makes "abc" zero, which would otherwise produce a
  # negative OFFSET and a PostgreSQL error.
  def normalize_page(value)
    candidate = value.to_i
    candidate.positive? ? [ candidate, MAX_PAGE ].min : 1
  end

  def normalize_per_page(value)
    return DEFAULT_PER_PAGE if value.blank?

    candidate = value.to_i
    return DEFAULT_PER_PAGE unless candidate.positive?

    candidate.clamp(1, MAX_PER_PAGE)
  end
end
