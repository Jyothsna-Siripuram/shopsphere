# ShopSphere performance

Current as of Day 10. This document records measured facts and known hazards; it does not claim optimisations that have not been made.

## 1. Approach

The project's rule is to prevent the predictable problems structurally and measure before optimising anything else. There is no production traffic, so any number here comes from a local measurement, and none of it is a substitute for the real thing.

Two classes are treated differently:

- **Structural problems** — N+1 queries, missing indexes on hot predicates, unbounded result sets — are prevented up front, because retrofitting them means rewriting endpoints.
- **Everything else** waits for evidence. Caching, query rewrites, and connection-pool tuning without a measurement is guesswork that adds complexity.

## 2. N+1 prevention

Eager loading is declared in **named scopes** rather than left to each controller:

| Scope | Loads | Used by |
|---|---|---|
| `Product.with_listing_associations` | `category`, `inventory`, `product_images` | public and admin catalogue (Day 8) |
| `Order.with_detail_associations` | `order_items → product`, `payments` | order history and detail (Day 13) |
| `Cart.with_pricing_associations` | `cart_items → product → inventory, product_images` | cart endpoints (Day 10), checkout (Day 12) |

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

Measured: the product listing is 4 reads (products, categories, inventories, images) plus one `COUNT` for pagination metadata, for any number of products; the order detail read is flat across 1 and 4 orders.

The Day 8 request spec earned its place immediately: the scope as written on Day 4 did not load `category`, which the serializer embeds in every product. The model-level N+1 spec could not see it — it never touched `category` — but the endpoint-level spec, which runs the real serializer, failed on its first run. N+1 checks belong at the endpoint, where the serializer decides what is read.

### Known hazard, closed at the endpoint on Day 10

`Cart#items_subtotal` reads `item.product.price`, so it emits a query per line **unless** the caller loads the cart through `with_pricing_associations`. Nothing in the model forces that. The cart endpoints opt in through one shared method (`CartLoading#current_cart`), and the request spec asserts `GET /cart` stays flat as lines are added. The model-level spec still asserts that the lazy path grows, so the hazard stays documented for future callers such as checkout.

## 3. Indexing

The full index catalogue, with the query each index serves and its write cost, is in [DATABASE.md §5](DATABASE.md#5-index-catalogue). The performance-relevant principles:

**Composite indexes serve filter and sort together.** `products (status, published_at DESC) WHERE status = 'active'` satisfies the catalogue's `WHERE status = 'active' ORDER BY published_at DESC` from one index scan with no sort step. Separate single-column indexes would force a sort of the whole active set.

**Partial indexes shrink both read and write cost.** Where the hot query only ever touches a subset — active products, approved reviews, default addresses, unrevoked tokens — the index covers only that subset. Draft and archived products are never listed, so indexing them would be pure write overhead.

**Redundant indexes were removed.** `t.references` creates a single-column index by default. On seven foreign keys where a composite index already leads with that column — `order_items.order_id`, `orders.user_id`, `cart_items.cart_id`, `wishlist_items.wishlist_id`, `products.category_id`, `product_images.product_id`, `reviews.user_id` — it was suppressed with `index: false`. A redundant index costs a write on every insert and serves no query the composite cannot. B-trees support leftmost-prefix scans, which is why the composite suffices.

Note that PostgreSQL does **not** auto-index foreign key columns (unlike MySQL/InnoDB). An unindexed referencing column makes `DELETE` on the parent scan all children; the leading-column composites cover that here.

## 4. Pagination

Offset pagination, decided in [ADR-011](DECISIONS.md#adr-011--offset-pagination-for-the-catalogue-with-a-cursor-escape-hatch). The performance-relevant parts:

- `OFFSET` is cheap at this catalogue's size. The pathology — `OFFSET 500000` making Postgres walk and discard half a million rows — is a scale this project will not reach.
- `page` is capped at 10,000. Without it, `page=999…9` multiplies into an `OFFSET` beyond `bigint` and PostgreSQL raises, turning a query string into a 500.
- `COUNT(*)` runs on the filtered relation **before** eager loading is attached, so it is a single-table count rather than a join.
- `per_page` is capped. An uncapped page size is an availability problem, not a performance one: one request asking for everything can exhaust memory and a connection.
- **Every paginated ordering carries a unique tiebreaker.** `ORDER BY published_at DESC` alone is non-deterministic when timestamps tie, so two requests for the same page can return different rows with no writes at all. All paginated queries append `id`.

## 5. Product search

Decided by measurement in [ADR-012](DECISIONS.md). Reproduce the numbers with:

```bash
bin/rails runner script/benchmarks/product_search.rb                 # 100k products
PRODUCTS=10000 bin/rails runner script/benchmarks/product_search.rb
```

The script loads Zipf-distributed synthetic products, so a few words are very common and most are rare, as in real copy. Everything runs inside one transaction that is rolled back. Timings are the median of 7 `EXPLAIN ANALYZE` runs on PostgreSQL 16 in Docker Desktop on Windows. Treat the **relative** order of strategies as the finding; absolute numbers will differ on RDS.

The cost that matters is the **count**: it touches every match, while the 24-row page can often stop early.

**Count time (ms) and matches, 10k products**

| Query | `ILIKE`, no index | `ILIKE` + trigram GIN | `tsvector` |
|---|---:|---:|---:|
| common term `shoe` | 78–118 (3,202) | 24–116 (4,241)¹ | 16–17 (5,280) |
| two words `leather boot` | 96 (65) | 14 (86) | 2.2 (626) |
| stemmed `running shoes` | 106 (**0**) | 6.9 (**0**) | 2.6 (847) |
| typo `lether` | 97 (0) | 4.5 (0) | 0.6 (0) |

¹ The planner chose an index scan in one run and a sequential scan in another. That is the point at which a trigram index stops helping.


**Same, 100k products**

| Query | `ILIKE`, no index | `ILIKE` + trigram GIN | `tsvector` |
|---|---:|---:|---:|
| common term `shoe` | 288–510 | 356–418 (seq scan) | 76–149 (seq scan) |
| two words `leather boot` | 608–700 | 25–28 | 9–17 |
| stemmed `running shoes` | 687–718 (**0**) | 7.5–10.5 (**0**) | 9–18 (4,113) |

**Ranking a page of 24, common term**

| Ranking | 10k | 100k |
|---|---:|---:|
| none (newest first) | 0.5 ms | 1.3 ms |
| `ts_rank` | **19 ms** | **70 ms** |
| `ts_rank_cd` | 197 ms | 538 ms |

**Typo fallback** (`lether` → "Leather …", trigram `word_similarity` on name)

| Threshold | Matches at 10k | Time at 10k | Time at 100k |
|---|---:|---:|---:|
| 0.6 (pg_trgm default) | **0** | 21 ms | 82 ms |
| 0.4 (chosen) | 1,974 | 19–36 ms | ~650 ms |

**Index size and write cost**

| Index | Size at 100k |
|---|---|
| trigram GIN on name + description | 41 MB |
| trigram GIN on name only (kept) | 14 MB |
| `tsvector` GIN (kept) | 15 MB |

Inserting 5,000 products took 3.5–4.9 s without search indexes and 4.4–5.6 s with them, which is within run-to-run noise on this machine. Ruby-side row building dominates that figure. The honest conclusion is that the write cost is too small to measure here, not that it is zero.

## 6. Not yet done

| Item | Day | Note |
|---|---|---|
| Search-as-you-type | — | Prefix matching (`snea:*`) verified to work but not exposed; needs its own tokenisation of user input |
| `EXPLAIN ANALYZE` against production-shaped data | 27 | Day 9 measured synthetic data. Re-measure on RDS with real product copy before trusting absolute numbers |
| Redis caching | 15 | Cache keys, TTLs and invalidation to be documented when added |
| Checkout lock contention | 11–12 | `lock_timeout` must be set so a pathological lock wait fails fast rather than holding a Puma thread |
| Connection pool sizing | 26 | `RAILS_MAX_THREADS` and the Active Record pool must agree, and the sum across tasks must stay under the RDS connection limit |
| Image size | 26 | The production image is 799 MB, which is large for a Fargate cold start |

## 7. Measured facts

| Measurement | Value | Context |
|---|---|---|
| Test suite | 361 examples | Split across groups on a 6 GB machine; the whole suite in one process exhausts memory locally |
| Production image | 799 MB | Built and verified booting; `GET /api/v1/health` returns 200 inside the Docker network |
| Product listing | 4 reads + 1 count, flat | Independent of product count; asserted on both the public and admin endpoints |
| Order detail | flat across 1 and 4 orders | |
| Search count, common term | 16 ms at 10k, 76–149 ms at 100k | `tsvector`; `ILIKE` was 118 ms and 288–510 ms |
| Search ranking, common term | 19 ms at 10k, 70 ms at 100k | `ts_rank`; `ts_rank_cd` was 10× slower |

The image size and the suite's memory footprint are both real findings rather than targets; both are addressed on Day 26.
