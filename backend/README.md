# ShopSphere API

Rails 8.1 API-only application. PostgreSQL 16 for durable state, Redis for cache and (from Day 16) Sidekiq.

See [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) for the design and [docs/DECISIONS.md](../docs/DECISIONS.md) for the decision record.

## Requirements

- Docker (the only requirement for the containerised path)
- Ruby 4.0.1 and PostgreSQL 16 if running outside Docker

## Running with Docker

From the **repository root**, not this directory:

```bash
docker compose up -d db redis   # PostgreSQL on 127.0.0.1:15432, Redis on 127.0.0.1:6379
docker compose up web           # API on http://localhost:3000
```

Postgres publishes on **15432**, not 5432, because 5432 and 5433 are commonly already taken by a host PostgreSQL install. Containers still reach it as `db:5432` over the compose network.

```bash
curl http://localhost:3000/api/v1/health
# {"data":{"status":"ok"}}
```

## Running outside Docker

Start the containers for the data stores, then point the app at the published ports:

```bash
export DATABASE_URL=postgresql://shopsphere:shopsphere_development_password@localhost:15432/shopsphere_development
export TEST_DATABASE_URL=postgresql://shopsphere:shopsphere_development_password@localhost:15432/shopsphere_test
export REDIS_URL=redis://localhost:6379/0

bin/rails db:prepare
bin/rails server
```

On PowerShell use `$env:DATABASE_URL="..."` instead of `export`.

## Environment

See [.env.example](.env.example) for the full list. The variables that matter:

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | always | |
| `TEST_DATABASE_URL` | test only | Evaluated only when `Rails.env.test?` |
| `REDIS_URL` | always | No default; boot fails without it |
| `JWT_SECRET_KEY` | outside dev/test | Derived from `secret_key_base` locally; **boot fails** without it in production. Generate with `openssl rand -hex 32` |
| `ALLOWED_ORIGINS` | always | Comma-separated browser origins. Never `*` |

No secret belongs in a committed file. `master.key`, `.env`, and `*.tfvars` are gitignored.

## Tests

```bash
bin/rspec                        # whole suite
bin/rspec spec/policies          # one directory
bin/rspec --only-failures        # re-run failures from the last run
bin/rspec --seed 12345           # reproduce a random-order failure
```

Specs are organised by what they prove, not only by class:

| Directory | What it asserts |
|---|---|
| `spec/database/` | The database rejects invalid data **through raw SQL**, with no model involved |
| `spec/models/` | Model behaviour and the validations that mirror those constraints |
| `spec/policies/` | The authorization matrix — who may do what |
| `spec/requests/` | Endpoints end to end, including status codes and information disclosure |
| `spec/services/` | Service workflows, including the JWT and token-rotation security properties |
| `spec/performance/` | Query counts do not grow with record counts |
| `spec/controllers/` | The authorization safety net stays armed |

## Full local gate

```bash
bin/ci
```

Runs setup, RuboCop, bundler-audit, Brakeman, RSpec, and the seeds. This is what CI runs; running it before pushing avoids a red build.

Individually:

```bash
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

## Production image

```bash
# From the repository root
docker build -f backend/Dockerfile -t shopsphere-backend:local backend

docker run --rm --network shopsphere_default \
  -e DATABASE_URL=postgresql://shopsphere:shopsphere_development_password@db:5432/shopsphere_development \
  -e REDIS_URL=redis://redis:6379/0 \
  -e JWT_SECRET_KEY=$(openssl rand -hex 32) \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) \
  -e RAILS_LOG_TO_STDOUT=true \
  shopsphere-backend:local
```

Puma serves directly on port 3000; there is no Thruster in front, because the ALB terminates TLS and there are no static assets to accelerate.

## Current endpoints

| Method | Path | Auth |
|---|---|---|
| `GET` | `/up` | public (liveness) |
| `GET` | `/api/v1/health` | public (readiness: database + Redis) |
| `POST` | `/api/v1/auth/register` | public |
| `POST` | `/api/v1/auth/login` | public |
| `POST` | `/api/v1/auth/refresh` | refresh cookie |
| `POST` | `/api/v1/auth/logout` | bearer token |
| `GET` `PATCH` | `/api/v1/profile` | bearer token |
| `GET` `POST` `PATCH` `DELETE` | `/api/v1/addresses` | bearer token, owner-scoped |
| `GET` `PATCH` | `/api/v1/admin/users` | bearer token, admin |
| `GET` | `/api/v1/products` | public; published products only |
| `GET` | `/api/v1/products/:slug` | public; a draft is `404`, not `403` |
| `GET` | `/api/v1/categories` | public |
| `GET` `DELETE` | `/api/v1/cart` | bearer token; `GET` never creates a cart, `DELETE` empties it |
| `POST` | `/api/v1/cart/items` | bearer token; `{ product_id, quantity }`, **increments** an existing line |
| `PATCH` `DELETE` | `/api/v1/cart/items/:id` | bearer token; `PATCH { quantity }` **sets** the quantity (idempotent) |
| `GET` `POST` `PATCH` `DELETE` | `/api/v1/admin/products` | bearer token, admin; addressed by id; `DELETE` archives |

Every cart mutation returns the whole cart. Each line carries `availability`: `available`, `insufficient_stock`, `out_of_stock` or `unavailable` (archived or unpublished). The cart reports `checkout_ready` but never stock quantities. Prices are live, not stored; see ADR-013.

### Catalogue query parameters

`GET /api/v1/products` accepts:

| Parameter | Meaning | Invalid input |
|---|---|---|
| `q` | Full-text search over name and description (stemmed; supports `"phrases"`, `or`, `-exclude`). Falls back to typo-tolerant matching on name when nothing matches | Control characters stripped; truncated to 100 characters |
| `page`, `per_page` | Offset pagination; `per_page` defaults to 24, max 100; `page` max 10,000 | Coerced to a sensible value, never `400` |
| `sort` | `relevance` (default when searching), `newest` (default otherwise), `oldest`, `price_asc`, `price_desc`, `name` | Falls back to the default |
| `category` | Category **slug** | Unknown slug returns an empty page |
| `min_price`, `max_price` | Inclusive bounds, decimal strings | Ignored |
| `in_stock` | `true` to hide unavailable products | Ignored unless truthy |

Responses carry `meta: { page, per_page, total_count, total_pages }`. A search adds `meta.search: { query, mode, sort }`, where `mode` is `fulltext` or `fuzzy`. A client should label fuzzy results ("showing results for similar terms") rather than present them as exact matches. Prices are two-place strings (`"50.00"`), never JSON numbers. The public shape reports `in_stock` but never the quantity; the admin shape adds `available_quantity`, `reorder_threshold` and `low_stock`.

Authentication is required by default: `ApplicationController` applies `authenticate_user!` to every controller, and an endpoint becomes public only by explicitly skipping it.

## Conventions

- **The database owns correctness.** Constraints, not validations, are the guarantee; validations exist for readable error messages. See [docs/DATABASE.md](../docs/DATABASE.md).
- **Deletion is declared on the foreign key**, never with `dependent:`, which would delete children row by row so the `ON DELETE` clause never fires. The exception is `product_images`, whose children own files in object storage.
- **Authorization is never optional.** `verify_authorized` runs after every action, so forgetting `authorize` raises instead of silently serving data.
- **Eager loading lives in a named scope** (`with_listing_associations`, `with_detail_associations`) so an endpoint opts in by name rather than each controller remembering.
- **Money is `numeric(12,2)`** and must serialize to JSON as a **string**; a JSON number is an IEEE-754 double and drifts under client-side arithmetic.
