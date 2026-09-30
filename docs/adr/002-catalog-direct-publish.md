# ADR 002: Catalog publishes events directly (no outbox)

**Status:** accepted, with a known trade-off

## Context

Every PostgreSQL service uses the transactional outbox (ADR 003) so a state change and
its event commit atomically. The catalog lives in MongoDB, which has no shared
transaction with our outbox relay.

## Options

1. Mongo outbox collection + multi-document transaction (needs a replica set).
2. Change Data Capture (Debezium MongoDB connector) streaming the products collection.
3. Save, then publish directly, and provide a repair path.

## Decision

Option 3 for now: `ProductService` saves to MongoDB, then publishes synchronously via
`DirectEventPublisher`. `POST /api/products/admin/reindex` republishes every product.

## Why

- Catalog changes are rare, admin-driven and idempotent (upserts by id).
- A missed event causes stale search results or a missing stock row, not lost money,
  and the reindex endpoint repairs it.
- Options 1 and 2 add infrastructure (replica set, Kafka Connect) that isn't justified
  at this scale.

## Revisit when

Catalog writes become frequent or automated (e.g. supplier feeds), at which point
Debezium CDC (option 2) is the natural upgrade.
