# ShopSphere security

Current as of Day 5. Sections marked *planned* have not been implemented; this document does not claim controls that do not exist.

## 1. Authentication model

Two tokens with deliberately different properties:

| | Access token | Refresh token |
|---|---|---|
| Format | JWT, HS256 | 256-bit opaque random string |
| Lifetime | 15 minutes | 30 days |
| Transport | JSON body → SPA memory | `HttpOnly` cookie |
| Stored server-side | No | SHA-256 digest only |
| Revocable | No — expires only | Yes, immediately |
| Readable by JavaScript | Yes | **No** |

The split exists because the two credentials face different threats. The access token is short-lived precisely *because* it is not revocable; the refresh token is revocable precisely *because* it is long-lived.

### Why the refresh token lives in a cookie

An SPA storing a refresh token in `localStorage` hands full, persistent account takeover to any successful XSS. `HttpOnly` makes the value unreadable to script, so an XSS payload can at worst act within the current page session — it cannot steal a credential and replay it later from elsewhere.

The cost is CSRF exposure, mitigated in two layers:

1. `SameSite=Lax` — a cross-site POST does not carry the cookie. `app.example.com → api.example.com` remains same-site because `SameSite` compares registrable domain, not origin.
2. An `Origin` allowlist check on the refresh endpoint, as defence in depth for browsers predating `SameSite` and for any future move to `SameSite=None`.

The cookie is additionally scoped `Path=/api/v1/auth`, so it is not attached to ordinary API traffic that has no use for it, and `Secure` outside local development.

### Rotation and reuse detection

Every refresh issues a new refresh token and revokes the presented one. Presenting an already-rotated token means two parties hold it, which is a theft signal. The response is to **revoke the entire token family** — every token descended from that login — forcing both the legitimate user and the attacker to re-authenticate.

The asymmetry is intentional: a false positive costs one login, a false negative costs the account.

The API returns an identical `invalid_refresh_token` error for reuse and for ordinary expiry. Telling an attacker their replay was specifically detected only teaches them to avoid detection; the family is already revoked either way.

### Token storage

Refresh tokens are stored as a **SHA-256 digest**, never in raw form, so a database disclosure does not yield usable credentials.

SHA-256 rather than bcrypt is deliberate and is the opposite of the rule for passwords. The token is 256 bits of CSPRNG output: there is no dictionary to attack and brute force is infeasible regardless of hash speed. A slow KDF protects *low-entropy human* secrets; here it would add latency to every refresh and buy nothing.

Passwords use bcrypt via `has_secure_password`, with a 12-character minimum and a 72-byte maximum — the point beyond which bcrypt silently truncates, so accepting more would give a false sense of strength.

## 2. Authorization

Access tokens carry **identity only** — `sub`, `iss`, `iat`, `exp`, `jti`. Role is deliberately not a claim.

Embedding the role would save a database lookup, but a demoted administrator would retain their privileges until the token expired. Since the user record is loaded for Pundit anyway, authorization reads current state at no extra cost. The same reasoning makes account suspension effective immediately rather than up to 15 minutes later — verified by a spec.

Every authorization check goes through `User#admin?` and never `user.role == "admin"`, so the role-as-column decision (ADR-004) stays reversible without touching policy code.

### Pundit enforcement

One policy object per resource, with three structural guarantees:

**Deny by default.** `ApplicationPolicy` returns `false` for every action, and `ApplicationPolicy::Scope#resolve` raises rather than returning the full scope. A policy that forgets a method fails closed; a collection whose policy forgets a `Scope` raises instead of exposing every row.

**Forgetting the check is impossible.** `verify_authorized` and `verify_policy_scoped` run as after-actions on every controller. An action that never calls `authorize` or `policy_scope` raises. Forgetting the check is the most common authorization bug in Rails and it is invisible — the endpoint works and the happy-path test passes. These make it a loud failure instead. `spec/controllers/authorization_enforcement_spec.rb` asserts the callbacks stay armed so they cannot be quietly removed.

**Permitted attributes come from the policy**, not the controller. `UserPolicy#permitted_attributes` returns `role` and `status` only for an administrator, so the allowlist cannot drift away from the rule that justifies it. A customer editing their own profile cannot submit `role` even though an administrator editing the same model can.

### 403 versus 404

A deliberate distinction, not inconsistency:

| Situation | Response | Reason |
|---|---|---|
| Record outside the caller's policy scope | **404** | A 403 confirms the record exists, letting an attacker enumerate other customers' resource IDs |
| Record in scope but the action is forbidden | **403** | The caller already knows it exists; hiding it would confuse without adding safety |

Mechanically, controllers resolve records through `policy_scope(Model).find(id)`, so an out-of-scope record raises `RecordNotFound` naturally rather than relying on anyone remembering to choose the right status.

### Rules worth noting

- An administrator cannot change their own role or suspend themselves. Without this, the last remaining administrator could lock everyone out with one request and no way back.
- An administrator cannot moderate their own review, which would make moderation decorative.
- An order has no `update?` at all — it is an immutable financial record, and progress happens only through explicit named transitions.
- Cancellation is state-restricted for administrators too, not just customers: reversing a delivered order is a refund, a different operation.
- Carts and wishlists have no administrative access. Staff have no business reading a customer's basket, and not building the capability is the strongest guarantee it will not be misused.

The admin namespace has a coarse `require_admin!` filter, but it is **not** the authorization: every action still calls `authorize`, and `verify_authorized` still fails the request otherwise. Relying on the namespace alone would mean one mis-nested controller silently exposes an admin endpoint.

## 3. Secure defaults

`ApplicationController` applies `before_action :authenticate_user!` to every controller. An endpoint becomes public only by explicitly calling `skip_before_action`.

The inverse — opting in per controller — means a forgotten line ships an unauthenticated endpoint and nothing fails to reveal it. Only the health probe and the four auth endpoints opt out, and each says why in a comment.

## 4. Information disclosure

| Surface | Control |
|---|---|
| Login failures | Identical response for wrong password and unknown account, so login is not a user-enumeration oracle. A dummy bcrypt comparison runs when no user matched, so response time does not leak existence either |
| `404` responses | Never name the missing record — that would let a caller probe for other users' resources |
| `500` responses | Return a fixed message. Exception text and stack traces routinely contain table names, queries and secrets, so they are logged and never returned |
| Readiness probe | Reports up/down without naming which dependency failed |
| User serialization | An explicit attribute allowlist. A "all attributes except…" approach fails open the moment a column is added |
| Registration | `role` is assigned server-side regardless of the request body, with strong parameters as a second layer |

## 5. Secret management

| Secret | Development / test | Production |
|---|---|---|
| `JWT_SECRET_KEY` | Derived from `secret_key_base` so a fresh clone runs | **Required**; boot fails without it |
| `DATABASE_URL`, `REDIS_URL` | `.env` / compose | Injected at runtime |
| `master.key` | Local file, gitignored | Not deployed |

Deriving the JWT key in production was rejected: it would couple JWT rotation to `secret_key_base` rotation, and a missing secret would silently produce a working-but-wrong configuration instead of a loud failure.

No secret is committed. `.gitignore` covers `.env*` (except the example), `master.key`, and `config/credentials/*.key`. AWS Secrets Manager wiring lands on Day 27.

## 6. Verification

Security properties are asserted by specs, not assumed:

- forged-signature, `alg: "none"`, wrong-issuer, expired and malformed tokens are all rejected;
- the access token payload contains no authorization claims;
- a replayed refresh token revokes its whole family but leaves other devices signed in;
- a suspended user's still-valid access token stops working immediately;
- registration cannot self-assign `admin`;
- the refresh token never appears in a response body;
- password material never appears in a response.

`brakeman` and `bundler-audit` run on every push and pull request.

## 7. Not yet implemented

- **Rate limiting** (Rack::Attack) — Day 19. Login and refresh are currently unthrottled and therefore open to credential stuffing. This is the most significant outstanding gap.
- **Security headers** — Day 19.
- **CORS middleware** — Day 21, with the frontend. The origin allowlist already exists and is enforced on the refresh endpoint.
- **Password reset**, email confirmation, MFA — out of scope for the first release.
- **Expired token cleanup** (`CleanupExpiredTokensJob`) — Day 16. Revoked and expired rows currently accumulate.
- **Audit logging** of authentication events beyond reuse detection — Day 22.
