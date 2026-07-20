---
name: grill-powers
description: Use when a user wants product-manager control of product scope while delegating technical design and verified software delivery to agents.
---

# GrillPowers

## Core contract

Connect Grill Me's decision-by-decision clarification to Superpowers' plan-driven delivery through one boundary: a user-approved, product-only PRD.

The user owns product intent and final acceptance. After PRD approval, the agent owns technical design, planning, execution, and verification. Before starting, confirm that every named upstream skill is available. If a dependency is missing, identify it and stop at that boundary.

## Workflow

### 1. Inspect product facts

Read the repository, issue, supplied documents, and current behavior before asking questions. Separate confirmed facts, unresolved product decisions, and inferences that need confirmation.

Repository facts inform the conversation; they do not automatically belong in the PRD. When a technical fact creates a choice that changes product behavior, scope, cost, or risk, present only those product consequences to the user.

Use `grill-with-docs` when the user explicitly wants the discussion recorded. Use `domain-modeling` when the uncertainty concerns product concepts, boundaries, or invariants.

### 2. Resolve product decisions

Follow `grilling`:

1. Ask about one product decision at a time.
2. Give a concrete recommendation and short rationale.
3. Offer mutually exclusive choices when useful.
4. Wait for the user's answer before advancing.
5. Continue until every material product decision is resolved.

Do not ask the user to choose architecture, data models, interfaces, testing strategy, task structure, or delivery tooling.

### 3. Confirm shared understanding

Recap the product in plain language. Label confirmed facts, remaining uncertainties, and necessary inferences. Ask the user to approve or correct the recap.

Explicit approval authorizes PRD drafting only. If a material product decision changes, continue `grilling` and recap again.

### 4. Produce and approve a product-only PRD

Follow `to-spec` only for synthesis and publishing. For GrillPowers, [the handoff contract](references/handoff-contract.md) replaces the upstream skill's default document shape.

The PRD defines users, problems, product behavior, scope, flows, product rules, and observable acceptance criteria. Exclude technical design even when it is known, previously discussed, or suggested by the user. Omit upstream `to-spec` sections for implementation decisions, testing decisions, modules, interfaces, schemas, API contracts, and test seams.

Express permissions, privacy, safety, performance, and compliance as observable product requirements. Leave the implementation mechanism to technical planning.

Use only confirmed product decisions. If a required PRD section exposes missing product behavior, return to `grilling`; do not invent a requirement or silently convert an inference into scope.

Present the exact PRD revision for explicit approval. Recap approval does not approve the PRD. A newly drafted or revised PRD remains `Draft - awaiting approval` until the user approves that revision; the agent cannot approve it on the user's behalf. All blocking product decisions and product risk boundaries must be resolved before approval.

### 5. Hand off to autonomous technical delivery

After PRD approval, follow `superpowers:writing-plans`. Treat the approved PRD as the complete source of product truth.

The agent chooses architecture, data, interfaces, tests, work items, verification commands, and one delivery owner. Do not ask the user to approve the technical plan or choose the delivery owner. Share a concise progress summary when useful, then continue.

Select one owner for the full plan:

| Situation | Delivery owner |
|---|---|
| Independent tasks in the current session | `superpowers:subagent-driven-development` |
| A written plan executed in a separate session | `superpowers:executing-plans` |

The selected owner controls implementation sequencing, TDD, task review, and checkpoints. Apply `superpowers:systematic-debugging` when unexpected behavior or test failure appears. Do not run the other owner in parallel or duplicate a review already owned by the executor.

### 6. Verify and finish

Before any completion claim, follow `superpowers:verification-before-completion` and run fresh checks after the last relevant change. Report exact evidence and remaining limits.

When work occurs on a development branch, follow `superpowers:finishing-a-development-branch` after verification.

### 7. Route product changes back

A change is material when it changes approved product behavior, scope, acceptance criteria, product rules, permissions, privacy, safety, compliance, cost, or risk. Pause affected work and walk this chain in order:

`grilling -> shared-understanding approval -> product-only to-spec -> exact revised PRD approval -> writing-plans -> resume`

Update only the PRD sections affected by the product change and any sections required to restore whole-document consistency. Publish a complete new PRD revision with a short change summary. The user may focus on the diff, but approval applies to the complete revision. Rewrite the full PRD only when the product premise, target users, or core flows have changed so broadly that a local revision cannot remain coherent.

Use technical investigation only to establish the product consequence. Do not place the proposed implementation into the PRD. Independent work may continue while the affected work waits.

Technical discoveries stay in delivery when they preserve the complete approved PRD.

## Quick reference

| State | Next action | Exit condition |
|---|---|---|
| Product intent is unresolved | `grilling` | Material product decisions are answered |
| Recap is drafted | Wait for the user | Recap is explicitly approved |
| Recap is approved | Product-only `to-spec` | PRD is drafted |
| PRD is drafted | Wait for the user | PRD is explicitly approved |
| PRD is approved | `superpowers:writing-plans` | Technical plan is ready |
| Technical plan is ready | Agent-selected delivery owner | Work and reviews are complete |
| Delivery is complete | Fresh verification | Evidence supports the claim |
| Branch is verified | Finish the branch | User selects the final integration path |

## Common mistakes

- Letting upstream `to-spec` add implementation or testing sections to the PRD.
- Copying incidental repository facts into the PRD.
- Treating recap approval as approval of the exact PRD revision.
- Inventing product behavior to fill a required PRD section.
- Asking the user to approve architecture, the technical plan, or the delivery owner.
- Allowing technical choices to silently change the approved product.
