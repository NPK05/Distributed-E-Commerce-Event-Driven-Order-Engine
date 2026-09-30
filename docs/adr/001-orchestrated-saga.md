# ADR 001: Orchestrate the order saga instead of choreographing it

**Status:** accepted

## Context

Placing an order spans three services that each own their data: inventory (reserve
stock), payment (charge the customer) and order (record the outcome). There is no
distributed transaction, so we need a saga: a sequence of local transactions with
compensating actions when a later step fails.

Two styles exist:

- **Choreography**: each service reacts to the previous service's events. No central
  coordinator.
- **Orchestration**: one component (the orchestrator) sends commands, waits for replies
  and decides what happens next.

## Decision

The order saga is **orchestrated** by `OrderSagaOrchestrator` in order-service.
Commands go to `inventory.commands` / `payment.commands`; replies come back on
`inventory.events` / `payment.events`. The saga's current step is persisted in
`saga_state`.

Everything *after* the order is confirmed (shipping, emails, cart cleanup, search)
stays **choreographed**: those services react to `OrderConfirmed` and are not part of
the saga's success criteria.

## Why

- The whole flow, including every failure path, is readable in one class.
- Timeouts need an owner. With choreography, "no reply from payment" has nobody
  responsible for it. Here `SagaTimeoutSweeper` compensates stuck sagas.
- Late or duplicate replies are easy to reason about: each handler checks the saga is at
  the step that expects that reply and ignores anything else.
- Participants stay simple and reusable: inventory doesn't know payment exists.

## Consequences

- order-service knows the participants' command contracts (coupling at the contract level).
- The orchestrator is a critical path; it is scaled horizontally, with row locks on
  `saga_state` so replicas don't race.
- Adding a step (e.g. fraud check) means changing the orchestrator, which is intended:
  the process has one owner.
