# Event catalog

Every message is an `EventEnvelope` (JSON) with `eventId`, `type`, `aggregateId`
(also the Kafka key), `correlationId`, `occurredAt`, `version` and `payload`.
Payload types live in `libs/common-events/.../Events.java`.

Messages about one order are keyed by the order id, so they land in the same partition
and are consumed in order.

## Commands (sent by the order saga orchestrator)

| Topic | Type | Payload | Handled by |
|---|---|---|---|
| `inventory.commands` | `ReserveInventory` | orderId, items[productId, quantity] | inventory-service |
| `inventory.commands` | `ReleaseInventory` | orderId, reason | inventory-service (compensation) |
| `payment.commands` | `ProcessPayment` | orderId, userId, amount, currency, paymentMethodToken | payment-service |
| `payment.commands` | `RefundPayment` | orderId, paymentId, reason | payment-service (compensation) |

## Events (facts)

| Topic | Type | Produced by | Consumed by |
|---|---|---|---|
| `order.events` | `OrderCreated` | order | notification, order-history projection |
| `order.events` | `OrderConfirmed` | order | inventory (commit stock), shipping, cart (clear lines), notification, projection |
| `order.events` | `OrderCancelled` | order | notification, projection |
| `order.events` | `OrderShipped` | order | projection |
| `inventory.events` | `InventoryReserved` | inventory | order saga |
| `inventory.events` | `InventoryReservationFailed` | inventory | order saga |
| `inventory.events` | `InventoryReleased` | inventory | order saga |
| `payment.events` | `PaymentAuthorized` | payment | order saga |
| `payment.events` | `PaymentFailed` | payment | order saga |
| `payment.events` | `PaymentRefunded` | payment | (audit) |
| `shipping.events` | `ShipmentCreated` | shipping | order saga (marks shipped), notification |
| `catalog.events` | `ProductUpserted` | catalog | inventory (create stock row), search (index) |
| `catalog.events` | `ProductDeleted` | catalog | search (remove from index) |

## Dead-letter topics

Each topic has a `<topic>.DLT` twin. A message lands there after retries with exponential
backoff are exhausted (default ~10 s), or immediately if it can't be parsed. Inspect them
in Kafka UI (http://localhost:8090) and replay by producing the record back to the
original topic once the cause is fixed.

## Evolving a contract

- **Additive changes** (new optional field): just add it. Jackson ignores unknown
  fields on old consumers, and records default missing fields to null.
- **Breaking changes**: publish a new type or bump `version`, run both until every
  consumer has moved, then retire the old one.
- For stricter guarantees, move payloads to Avro/Protobuf with a schema registry
  (Confluent or Apicurio) and enforce compatibility in CI.
