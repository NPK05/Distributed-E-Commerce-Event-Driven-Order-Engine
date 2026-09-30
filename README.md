# Distributed E-Commerce & Event-Driven Order Engine

A microservices e-commerce platform where checkout is an **orchestrated saga over Kafka**,
with a transactional outbox, idempotent consumers, compensations, timeouts, CQRS,
distributed tracing and a Next.js storefront.

**Stack:** Java 21 · Spring Boot 3.3 · Spring Cloud Gateway · Kafka (KRaft) · PostgreSQL ·
MongoDB · Redis · Elasticsearch · Next.js 14 · Docker Compose · Kubernetes ·
OpenTelemetry/Jaeger · Prometheus/Grafana · Testcontainers · k6 · GitHub Actions

```
Browser ─▶ API gateway ─▶ auth · catalog · cart · order · inventory · payment · shipping · notification · search
                                               │         │           │          │
                                               └──── Kafka: commands & events ──┘
```

See [docs/architecture.md](docs/architecture.md) for diagrams of the system and the saga.

## Quick start

Requirements: Docker (with ~8 GB memory for the full stack). For development also Java 21,
Maven 3.9 and Node 20.

```bash
cp .env.example .env
docker compose up --build -d          # or: make up
```

The first build compiles every service and takes several minutes. Then open:

| What | URL |
|---|---|
| Storefront | http://localhost:3000 |
| API gateway | http://localhost:8080 |
| Kafka UI (topics, messages, DLTs) | http://localhost:8090 |
| Jaeger (distributed traces) | http://localhost:16686 |
| Mailpit (emails the shop sends) | http://localhost:8025 |
| Grafana (with `make up-all`) | http://localhost:3001 (admin / admin) |

Admin login: `admin@shop.local` / `admin12345`.

Run the automated end-to-end check once everything is up (needs `curl` and `jq`):

```bash
./tests/e2e/smoke.sh
```

## Demo: watch the saga work

1. **Happy path.** Register, add a product to the cart, check out with *Test card: approves*.
   The order page updates live: *Checking stock → Processing payment → Confirmed → Shipped*.
   Mailpit shows the "received", "confirmed" and "shipped" emails.
2. **Compensation.** Check out with *Test card: declines* (or buy the $6,499 chair, which
   exceeds the simulator's limit). Stock is reserved, payment fails, the saga releases the
   stock and cancels the order. Check the admin page: the stock count is back where it was.
3. **Oversell protection.** As admin, set a product's stock to 1. Order it from two
   accounts at the same moment: one confirms, the other is cancelled with
   *Insufficient stock*.
4. **One trace, many services.** In Jaeger, pick `order-service` and open a `POST /api/orders`
   trace: it follows the order through Kafka into inventory, payment and shipping.
5. **Timeout.** `docker compose stop payment-service`, place an order, wait ~2 minutes:
   the sweeper cancels it and releases stock. Start payment-service again: the pending
   `ProcessPayment` command is consumed, payment succeeds late, and the saga issues a refund.

## Project layout

```
libs/
  common-events/        Event contracts: envelope, topic names, payload records
  common-messaging/     Outbox, idempotent consumer, retry + DLT, topic creation (auto-configured)
services/
  api-gateway/          Spring Cloud Gateway: routing, JWT, rate limiting, circuit breakers, CORS
  auth-service/         Registration, login, JWT issuing (Postgres)
  catalog-service/      Products (MongoDB), seeds a demo catalog, publishes catalog.events
  cart-service/         Carts in Redis, clears purchased lines on OrderConfirmed
  order-service/        Checkout, saga orchestrator, timeout sweeper, CQRS order history
  inventory-service/    Stock + reservations with row locking (Postgres)
  payment-service/      Idempotent payments: simulator or Stripe test mode
  shipping-service/     Books shipments for confirmed orders
  notification-service/ Emails for each lifecycle event (SMTP → Mailpit)
  search-service/       Elasticsearch index fed by catalog.events, fuzzy search
apps/web/               Next.js storefront + admin page
infra/                  Postgres init, Prometheus, Grafana dashboards, Kubernetes manifests
docker/                 Shared multi-stage Dockerfile for all Java services
tests/e2e/              Bash smoke test through the gateway
tests/load/             k6 flash-sale load test
docs/                   Architecture, event catalog, ADRs
```

## Developing

Run the infrastructure in Docker and a service from your IDE or the command line:

```bash
make infra                                   # Kafka, Postgres, Mongo, Redis, ES, Mailpit, Jaeger
mvn -pl services/order-service -am spring-boot:run
cd apps/web && npm install && npm run dev    # frontend on :3000
```

Every service defaults to `localhost` for its dependencies, so no extra config is needed.
Service ports: gateway 8080, auth 8081, catalog 8082, cart 8083, order 8084,
inventory 8085, payment 8086, shipping 8087, notification 8088, search 8089.

## Tests

```bash
make test-unit    # fast unit tests, no Docker
make test         # everything, including Testcontainers suites (needs Docker)
```

Highlights:

- `OrderSagaOrchestratorTest`: every saga transition, including late payment after timeout → refund.
- `OrderSagaIntegrationTest`: real Postgres + Kafka; confirm, decline, out-of-stock, duplicate
  delivery, timeout, idempotent checkout.
- `OversellPreventionTest`: 40 concurrent buyers, 5 units, exactly 5 reservations succeed.
- `tests/load/checkout.k6.js`: flash-sale load with a p95 checkout threshold.

## Payments

By default payment-service uses a simulator: token `tok_visa` approves, `tok_chargeDeclined`
declines, and any amount above `PAYMENT_DECLINE_ABOVE` (5000) declines. To use Stripe test
mode, set `STRIPE_SECRET_KEY=sk_test_...` in `.env` and check out with Stripe test payment
methods such as `pm_card_visa` / `pm_card_chargeDeclined` (change the tokens in
`apps/web/app/checkout/page.tsx`).

## Kubernetes

Dev-grade manifests (single-replica infrastructure, HPAs and PDBs for the hot services) are
in `infra/k8s/base`. With [kind](https://kind.sigs.k8s.io/) and ingress-nginx:

```bash
make k8s-images    # build all images and load them into kind
make k8s-deploy    # kubectl apply -k infra/k8s/base
# add "127.0.0.1 shop.localhost api.shop.localhost" to /etc/hosts
```

For production, replace the in-cluster Kafka/Postgres/Mongo/Elasticsearch with managed
services or operators (Strimzi, CloudNativePG), and set real secrets.

## Documentation

- [Architecture](docs/architecture.md): system and saga diagrams, patterns, security, observability
- [Event catalog](docs/event-catalog.md): every topic, message and consumer
- ADRs: [orchestrated saga](docs/adr/001-orchestrated-saga.md) ·
  [catalog direct publish](docs/adr/002-catalog-direct-publish.md) ·
  [transactional outbox](docs/adr/003-transactional-outbox.md)
