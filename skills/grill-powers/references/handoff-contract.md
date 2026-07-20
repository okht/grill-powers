# Product PRD handoff contract

The approved PRD is the only product contract passed from Grill Me to `superpowers:writing-plans`. It defines the observable product without prescribing its technical realization.

## Required sections

1. **Problem and outcome** - who has the problem and what observable outcome matters.
2. **Users and context** - the product actors and the situations in which they use it.
3. **In scope** - product behaviors included in this delivery.
4. **Out of scope** - adjacent product behavior intentionally excluded.
5. **User flows** - the happy path plus material alternate and failure paths.
6. **Product rules** - permissions, user-visible states, business invariants, limits, and terminology expressed in product language.
7. **Acceptance criteria** - stable, observable statements that determine whether the product behavior is complete.
8. **Open product decisions** - unresolved product choices that block approval. Never invent product behavior to empty this section; return to Grill Me. This section must be empty at approval time.
9. **Deferred product decisions** - named product choices postponed beyond this delivery, including their user-visible boundary.
10. **Approval record** - status, approver, date, and the exact PRD revision. A new or revised PRD starts as `Draft - awaiting approval`. Only the user's explicit approval of that exact revision changes the status to approved.

## Content boundary

The PRD contains product intent and observable behavior only. Keep these subjects in technical planning:

- architecture, technology stack, libraries, and frameworks
- databases, schemas, storage, data shapes, and migrations
- APIs, interfaces, events, protocols, modules, files, functions, and algorithms
- authentication, authorization, encryption, token, caching, and performance mechanisms
- test strategy, test seams, mocks, commands, task breakdown, delivery owner, deployment, and observability

When a technical fact changes product behavior, scope, cost, or risk, record the resulting product requirement or trade-off without recording the mechanism.

## Revision rule

For a material product change, update only the affected PRD sections and any sections needed to keep the document internally consistent. Then publish a complete revised PRD with a short change summary. The user may review the diff first, but approval applies to the complete revision. Rewrite the full PRD only when changes to the product premise, target users, or core flows make a local revision incoherent.

## Planning rule

`superpowers:writing-plans` chooses the technical realization and delivery structure without requiring user approval. Every technical work item must trace to the PRD, and technical planning may not silently change product behavior, acceptance criteria, or scope. A material product change returns to Grill Me and a revised PRD approval.
