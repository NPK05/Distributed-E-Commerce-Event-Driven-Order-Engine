# ADR 003: Transactional outbox + idempotent consumers

**Status:** accepted

## Context

A service that writes to its database and then publishes to Kafka can crash in between.
Either the state changed with no event (the saga stalls) or, if it publishes first, an
event describes a change that was rolled back. Kafka also delivers at-least-once, so
consumers see duplicates.

## Decision

**Producer side:** business code never talks to Kafka directly. It calls
`OutboxWriter.stage(...)`, which inserts into `outbox_events` in the *same* transaction as
the business change. `OutboxRelay` polls unpublished rows (`FOR UPDATE SKIP LOCKED`, so
replicas can share the work), publishes them in insertion order, and marks them published.

**Consumer side:** every listener goes through `IdempotentProcessor`, which inserts
`(consumer, eventId)` into `processed_events` in the same transaction as the handler's
changes and any outbox rows it stages. A redelivered event finds its row and is skipped.

Both live in `libs/common-messaging` and switch on automatically for any service with JPA.

## Consequences

- End-to-end effect is **exactly-once processing** on top of at-least-once delivery.
- Events are delayed by up to one poll interval (200-250 ms). Acceptable for this domain.
- Messages keyed by order id keep per-order ordering within a partition.
- The polling relay could be swapped for Debezium CDC on `outbox_events` without
  touching business code.
