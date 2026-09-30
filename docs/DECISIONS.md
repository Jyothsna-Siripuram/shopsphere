# Architecture decision record

Each entry states the decision, the alternatives considered, the reasoning, and — most importantly — **the condition that would reverse it**. A decision without a reversal condition is a preference, not an engineering choice.

---

## ADR-001 — Inventory concurrency: pessimistic row locking plus a `CHECK` backstop

**Date:** 2026-09-28 (Day 3) · **Status:** accepted

### Problem

N concurrent checkouts for the last unit of stock must not oversell it. PostgreSQL's default isolation level is `READ COMMITTED`, under which a plain read-then-write is a lost update: two transactions both read `available = 1`, both decrement to `0`, both commit, two units sold.

### Alternatives considered

**A. Pessimistic row locking** — `SELECT ... FOR UPDATE` on inventory rows in deterministic `product_id` order, validate the basket under the lock, decrement, commit.

**B. Atomic conditional `UPDATE`** — a single `UPDATE ... WHERE available_quantity >= :qty`, using the affected-row count as the answer. Correct because under `READ COMMITTED`, an `UPDATE` blocked on a locked row re-reads the newly committed version and re-evaluates its `WHERE` clause, so the guard cannot be bypassed.

**C. Two-phase reservation** — split stock into `on_hand` and `reserved`, reserve with a TTL at checkout start, confirm after payment, sweep expired reservations with a background job.

### Decision

**A as the mechanism, with B's `CHECK (available_quantity >= 0)` as a database backstop.** Both, deliberately.

### Reasoning

*Why not C.* Two-phase reservation exists to hold stock across a slow external boundary — a payment gateway, a 3-D Secure redirect, a timed cart hold. ShopSphere's payment provider is a mock, so there is no such boundary, and no requirement asks a cart to hold inventory. Adopting it now would buy a sweeper job, an alarm, a state machine, and a *new* oversell race (confirm-versus-expiry) in exchange for a capability nothing needs.

*Why A over B.* Checkout validates a multi-item basket. Under A the whole basket is validated against one consistent snapshot, so the API can return every shortage with its true available quantity in a single response — which matters, because "something in your cart is unavailable" is a conversion killer. Under B, shortages surface one statement at a time and the complete picture cannot be assembled cheaply. The transaction is held anyway for order, line-item, and payment creation, so A's longer critical section costs less than it appears. Contention is per-SKU, not global.

*Why the constraint regardless.* A's correctness depends entirely on application code remembering to lock. One future path that forgets — an admin bulk adjustment, a Sidekiq job, a console fix — silently reintroduces overselling and fails quietly. The constraint converts that into an immediate `StatementInvalid`.

> The lock is the mechanism. The constraint is the guarantee. Mechanisms get forgotten; constraints do not.

### Consequences

- Hot SKUs serialize. Acceptable for a single-merchant storefront; would not survive a flash sale.
- Nothing slow may run inside the checkout transaction — no HTTP calls, no image work — because lock duration multiplies contention.
- Lock ordering must stay deterministic or deadlock returns.
- `lock_timeout` must be set so a pathological wait fails fast rather than holding a Puma thread.

### Reversal condition

Adopt **C** when a real payment provider introduces network latency inside checkout, or when cart-level stock holds become a product requirement. The schema is shaped so `available_quantity` can become `on_hand - reserved` behind the same service interface.

### Explicitly not solved by this decision

Duplicate checkout requests. That is a separate problem with a separate mechanism: a unique index on `orders.idempotency_key`. Conflating the two is a common error.

---

## ADR-002 — Money stored as `numeric(12,2)`

**Date:** 2026-09-28 (Day 3) · **Status:** accepted

**Alternatives:** integer minor units (`price_cents bigint`), as used by payment processors.

**Decision:** `numeric(12,2)`. PostgreSQL `numeric` is exact decimal, not binary floating point, and Active Record maps it to `BigDecimal`, so values stay exact end to end. Minor units add a conversion at every boundary for a correctness property `numeric` already provides in a single-currency system.

**Consequence:** money must serialize to JSON as a **string**. JavaScript's `number` is IEEE-754 double and would silently degrade precision.

**Reversal condition:** multi-currency. Minor-unit exponents vary by currency (JPY 0, KWD 3), so a fixed scale of 2 becomes wrong the moment a second currency appears.

---

## ADR-003 — Status columns as `varchar` + `CHECK`, not native PostgreSQL enums

**Date:** 2026-09-28 (Day 3) · **Status:** accepted

**Decision:** `varchar` with a `CHECK (status IN (...))` constraint.

**Reasoning:** identical integrity, far better evolvability. `ALTER TYPE ... ADD VALUE` carries transaction restrictions and enum values can never be removed, whereas a `CHECK` is dropped and recreated inside an ordinary transactional migration. For a schema this young, cheap evolution beats the few bytes an enum saves.

**Reversal condition:** a status set that has genuinely stabilised combined with a table large enough for the storage difference to matter.

---

## ADR-004 — `users.role` as a column rather than a `Role` entity

**Date:** 2026-09-28 (Day 3) · **Status:** accepted · **Deviates from the original specification**

**Decision:** `users.role` holding `customer` or `admin`, constrained by `CHECK`.

**Reasoning:** the specification lists `Role` as a core entity, but the system has exactly two roles and no requirement for runtime-editable permissions. A `roles` table plus a join table adds a join to every authorization check in order to model a two-value set — the kind of abstraction the project's own principles prohibit.

**Reversal condition:** genuine RBAC — multiple simultaneous roles per user, or granular permissions an administrator edits at runtime. That is a `roles` + `user_roles` migration taken when the requirement is real, not speculatively.

---

## ADR-005 — Historical records snapshot their inputs

**Date:** 2026-09-28 (Day 3) · **Status:** accepted

**Decision:** `order_items` stores `product_name`, `product_sku`, and `unit_price` as copies taken at purchase time. `orders` stores `shipping_address` and `billing_address` as `jsonb` snapshots rather than foreign keys to `addresses`.

**Reasoning:** an order is a permanent record of what was sold, at what price, to what address. The catalogue and the address book are both mutable. Joining would let a 2027 product rename or profile edit silently rewrite a 2026 invoice.

**Trade-off accepted:** the data is denormalised, so a product rename does not propagate to historical orders — which is exactly the intent.

**Reversal condition:** none foreseen. This is standard practice for financial records.

---

## ADR-008 — Refresh token delivered in an HttpOnly cookie

**Date:** 2026-09-30 (Day 5) · **Status:** accepted · **Resolves the open question at ARCHITECTURE.md §8.1**

**Alternatives:** refresh token in the JSON response body stored in `localStorage`; or in the body held in memory only.

**Decision:** refresh token in an `HttpOnly; Secure; SameSite=Lax; Path=/api/v1/auth` cookie. Access token in the JSON body, held in SPA memory only.

**Reasoning:** `localStorage` hands full persistent account takeover to any successful XSS, which is the likelier attack against an SPA. Memory-only avoids that but logs the user out on every page reload. `HttpOnly` makes the long-lived credential unreadable to script while surviving reload.

**Trade-off accepted:** introduces CSRF exposure, mitigated by `SameSite=Lax` plus an `Origin` allowlist check; and requires restoring cookie middleware that `config.api_only` excludes.

**Reversal condition:** a deployment where the SPA and API are genuinely cross-site (different registrable domains) would force `SameSite=None`, at which point the `Origin` check stops being defence in depth and becomes load-bearing, and a CSRF token should be added.

---

## ADR-009 — Refresh token rotation with family-wide reuse detection

**Date:** 2026-09-30 (Day 5) · **Status:** accepted

**Decision:** every refresh issues a new token and revokes the presented one. A replayed, already-rotated token revokes the entire token family.

**Reasoning:** without rotation, a token exfiltrated once grants access for its full 30-day lifetime and nothing ever reveals the theft. With rotation, the thief and the legitimate user inevitably collide, and the collision is detectable. This is the OAuth 2.0 Security BCP pattern.

**Trade-off accepted:** the legitimate user can be signed out by an attacker's replay. That asymmetry is correct — a false positive costs one login, a false negative costs the account.

**Implementation note worth preserving:** the family revocation must be committed *before* the reuse exception is raised. Raising inside the transaction rolls back the revocation, so the control appears to work while changing nothing. A spec asserts the revocation persists.

---

## ADR-010 — Refresh tokens hashed with SHA-256, not bcrypt

**Date:** 2026-09-30 (Day 5) · **Status:** accepted

**Decision:** store `SHA256(token)`; compare by indexed digest lookup.

**Reasoning:** the deliberate inverse of the password rule. Refresh tokens are 256 bits of CSPRNG output, so there is no dictionary and brute force is infeasible at any hash speed. A slow KDF exists to make *low-entropy human* secrets expensive to guess; applied here it only adds latency to every refresh.

**Reversal condition:** none while tokens remain high-entropy random. If tokens ever became partly predictable or user-derived, a KDF would be required.

---

## ADR-006 — GitHub Actions workflows live at the repository root

**Date:** 2026-09-28 (Day 2 remediation) · **Status:** accepted

**Decision:** `.github/workflows/ci.yml` at the repository root with `defaults.run.working-directory: backend`, not `backend/.github/workflows/`.

**Reasoning:** GitHub only discovers workflows under the root `.github/workflows/`. A workflow nested inside a subdirectory is inert — the original one had never executed. The same applies to `dependabot.yml`.

**Consequence:** CI service images are pinned to the same versions `docker-compose.yml` uses, so CI cannot pass against a different PostgreSQL or Redis version than local development runs against.

---

## ADR-007 — Line endings normalised to LF via `.gitattributes`

**Date:** 2026-09-28 (Day 2 remediation) · **Status:** accepted

**Decision:** `* text=auto eol=lf`.

**Reasoning:** development happens on Windows with `core.autocrlf=true`, while the application builds and runs in Linux containers. Without this, a fresh clone writes CRLF into `backend/bin/*`, Docker copies those bytes into the image, and every shebang script fails at runtime with a `bad interpreter` error caused by the trailing carriage return. Normalising in the repository removes the failure regardless of each developer's local git configuration.
