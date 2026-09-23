# ShopSphere

ShopSphere is a production-oriented e-commerce portfolio project. It is deliberately designed to demonstrate senior-level Ruby on Rails, React, PostgreSQL, AWS, and delivery practices through an incremental 30-day build.

## Product scope

ShopSphere supports two personas:

- **Customers** browse a searchable catalogue, manage addresses, cart and wishlist, apply coupons, submit idempotent checkout requests, track orders, and leave product reviews.
- **Administrators** manage the catalogue, inventory, orders, coupons, customers, and operational sales/low-stock views.

The first release is a single-store marketplace. It explicitly excludes multi-vendor settlement, real payment-provider integration, multi-currency, and advanced tax calculation. Payments use a mock provider behind a replaceable boundary; this keeps the project focused while preserving a credible production integration path.

## Architecture at a glance

- **Frontend:** React + TypeScript SPA built with Vite and served from S3 through CloudFront.
- **API:** Rails API-only application exposing a versioned REST interface at \`/api/v1\`.
- **Data:** PostgreSQL is the transactional source of truth. Redis is used only for cache, rate-limit counters, and Sidekiq infrastructure.
- **Async work:** Sidekiq workers process notifications, cleanup, and reports outside API request paths.
- **AWS:** API and worker containers run on ECS Fargate behind an ALB; RDS and ElastiCache remain private.

See [the architecture document](docs/ARCHITECTURE.md) for the design, boundaries, data ownership, and deployment diagram.

## Repository layout

\`\`\`text
.
├── backend/                 # Rails API (introduced on Day 2)
├── frontend/                # React + TypeScript SPA (introduced on Day 21)
├── terraform/
│   ├── environments/        # Environment composition and configuration
│   └── modules/             # Reusable AWS infrastructure modules
├── docs/                    # Architecture decisions and evolving technical docs
└── .github/workflows/       # CI/CD workflows (introduced later)
\`\`\`

## Delivery roadmap

The project is built in small, reviewable increments. Day 1 establishes the architecture and repository only. Day 2 begins Rails, PostgreSQL, and local container setup; no application API has been implemented yet.

## Engineering principles

- PostgreSQL constraints and transactions enforce business correctness.
- Controllers coordinate HTTP concerns; services model multi-step workflows; query objects encapsulate complex retrieval/reporting.
- Authorization is server-side and is never delegated to the SPA.
- External side effects are asynchronous, idempotent where possible, observable, and safe to retry.
- Secrets are injected at runtime and never committed.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)

Additional documentation—database design, API contracts, security, performance, AWS, decisions, and interview notes—will be added as the related implementation is introduced.

## Current status

**Day 1 / 30 — architecture and repository setup complete.**

No Rails API, frontend application, Docker environment, or AWS resources have been implemented yet.
