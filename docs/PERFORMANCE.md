# ShopSphere performance

Current as of Day 7. This document records measured facts and known hazards; it does not claim optimisations that have not been made.

## 1. Approach

The project's rule is to prevent the predictable problems structurally and measure before optimising anything else. There is no production traffic, so any number here comes from a local measurement, and none of it is a substitute for the real thing.

Two classes are treated differently:

- **Structural problems** — N+1 queries, missing indexes on hot predicates, unbounded result sets — are prevented up front, because retrofitting them means rewriting endpoints.
- **Everything else** waits for evidence. Caching, query rewrites, and connection-pool tuning without a measurement is guesswork that adds complexity.

## 2. N+1 prevention

Eager loading is declared in **named scopes** rather than left to each controller:

| Scope | Loads | Used by |
|---|---|---|
| `Product.with_listing_associations` | `inventory`, `product_images` | catalogue listing (Day 8) |
| `Order.with_detail_associations` | `order_items → product`, `payments` | order history and detail (Day 13) |
| `Cart.with_pricing_associations` | `cart_items → product → inventory` | cart and checkout (Day 10) |

A named scope makes the fix something an endpoint opts into by name, instead of something each controller author has to remember.

### How this is verified

`spec/performance/n_plus_one_spec.rb` subscribes to `sql.active_record` and counts statements. The assertion is **not** an absolute number — it runs the same read against two dataset sizes and requires the count to be unchanged:

```ruby
create(:product, :in_stock)
one = count_queries { read_listing }

4.times { create(:product, :in_stock) }
many = count_queries { read_listing }

expect(many.size).to eq(one.size)
```

That is the definition of an N+1: query count growing with record count. A snapshot of one number cannot detect it, and asserting `association.loaded?` only proves eager loading was *requested*.

One trap worth recording: the setup must sit **outside** the counted block. Creating records inside it counts the factory's `INSERT`s, which grow with N regardless of eager loading, so the assertion fails even on perfectly batched reads. This cost a debugging cycle on Day 7.

Measured: the product listing is 3 queries (products, inventories, images) for any number of products; the order detail read is flat across 1 and 4 orders.

### Known hazard, deliberately not hidden

`Cart#items_subtotal` reads `item.product.price`, so it emits a query per line **unless** the caller loads the cart through `with_pricing_associations`. Nothing in the model forces that. A spec asserts the eager path is strictly cheaper than the lazy one, which documents the hazard rather than pretending it is solved. The cart endpoint on Day 10 must opt in explicitly.

## 3. Indexing

The full index catalogue, with the query each index serves and its write cost, is in [DATABASE.md §5](DATABASE.md#5-index-catalogue). The performance-relevant principles:

**Composite indexes serve filter and sort together.** `products (status, published_at DESC) WHERE status = 'active'` satisfies the catalogue's `WHERE status = 'active' ORDER BY published_at DESC` from one index scan with no sort step. Separate single-column indexes would force a sort of the whole active set.

**Partial indexes shrink both read and write cost.** Where the hot query only ever touches a subset — active products, approved reviews, default addresses, unrevoked tokens — the index covers only that subset. Draft and archived products are never listed, so indexing them would be pure write overhead.

**Redundant indexes were removed.** `t.references` creates a single-column index by default. On seven foreign keys where a composite index already leads with that column — `order_items.order_id`, `orders.user_id`, `cart_items.cart_id`, `wishlist_items.wishlist_id`, `products.category_id`, `product_images.product_id`, `reviews.user_id` — it was suppressed with `index: false`. A redundant index costs a write on every insert and serves no query the composite cannot. B-trees support leftmost-prefix scans, which is why the composite suffices.

Note that PostgreSQL does **not** auto-index foreign key columns (unlike MySQL/InnoDB). An unindexed referencing column makes `DELETE` on the parent scan all children; the leading-column composites cover that here.

## 4. Pagination

Offset pagination, decided in [ADR-011](DECISIONS.md#adr-011--offset-pagination-for-the-catalogue-with-a-cursor-escape-hatch). The performance-relevant parts:

- `OFFSET` is cheap at this catalogue's size. The pathology — `OFFSET 500000` making Postgres walk and discard half a million rows — is a scale this project will not reach.
- `per_page` is capped. An uncapped page size is an availability problem, not a performance one: one request asking for everything can exhaust memory and a connection.
- **Every paginated ordering carries a unique tiebreaker.** `ORDER BY published_at DESC` alone is non-deterministic when timestamps tie, so two requests for the same page can return different rows with no writes at all. All paginated queries append `id`.

## 5. Not yet done

| Item | Day | Note |
|---|---|---|
| Product search | 9 | `pg_trgm` vs `tsvector` to be chosen **after** measuring against realistic data, not before. `pg_trgm` is deliberately not enabled yet — an unused index is pure write cost |
| `EXPLAIN ANALYZE` on real plans | 9 | Needs a seeded dataset large enough for the planner to choose realistically. Plans against twelve rows are meaningless |
| Redis caching | 15 | Cache keys, TTLs and invalidation to be documented when added |
| Checkout lock contention | 11–12 | `lock_timeout` must be set so a pathological lock wait fails fast rather than holding a Puma thread |
| Connection pool sizing | 26 | `RAILS_MAX_THREADS` and the Active Record pool must agree, and the sum across tasks must stay under the RDS connection limit |
| Image size | 26 | The production image is 799 MB, which is large for a Fargate cold start |

## 6. Measured facts

| Measurement | Value | Context |
|---|---|---|
| Test suite | 206 examples | Split across groups on a 6 GB machine; the whole suite in one process exhausts memory locally |
| Production image | 799 MB | Built and verified booting; `GET /api/v1/health` returns 200 inside the Docker network |
| Product listing | 3 queries, flat | Independent of product count |
| Order detail | flat across 1 and 4 orders | |

The image size and the suite's memory footprint are both real findings rather than targets; both are addressed on Day 26.
