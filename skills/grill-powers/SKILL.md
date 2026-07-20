---
name: grill-powers
description: Use when a user wants to take a product idea or feature from unresolved requirements through an approved specification and verified software delivery, especially when Grill Me and Superpowers are both installed.
---

# GrillPowers

## Overview

Connect Grill Me's decision-by-decision clarification to Superpowers' plan-driven delivery. Keep one explicit contract between them: an approved specification produced with `to-spec`, then consumed by `superpowers:writing-plans`.

Before starting, confirm that every named upstream skill is available. If a dependency is missing, identify it and stop at that boundary. Do not replace the missing stage with an improvised equivalent.

## Workflow

### 1. Inspect available facts

Read the repository, issue, supplied documents, and current behavior before asking questions. Separate:

- confirmed facts
- unresolved decisions
- inferences that still need confirmation

Use `grill-with-docs` when the user explicitly wants the discussion recorded in documents. Use `domain-modeling` when the central uncertainty concerns domain concepts, boundaries, or invariants.

### 2. Run the Grill Me stage

Follow `grilling` for the product-discovery conversation:

1. Ask about one decision at a time.
2. Give a concrete recommendation and its short rationale.
3. Offer mutually exclusive choices when useful.
4. Wait for the user's answer before advancing.
5. Continue until material product decisions are resolved.

Do not start implementation planning while product intent remains materially open.

### 3. Confirm shared understanding

Recap the proposed product in plain language. Label confirmed facts, remaining uncertainties, and necessary inferences. Ask the user to approve or correct the recap.

The gate passes only after explicit approval. If the user changes a material decision, continue the Grill Me stage and recap again.

Approval of this recap authorizes specification drafting only. It does not authorize planning or implementation.

### 4. Produce and approve the specification

Follow `to-spec` to turn the confirmed understanding into a durable specification. The specification must satisfy [the handoff contract](references/handoff-contract.md).

Present the specification for approval. Record the approval and the decisions deliberately deferred. Keep implementation details out unless they are product constraints or already confirmed facts.

Open requirements or risk boundaries for permissions, safety, security, data handling, and compliance cannot remain open or deferred at approval time. An implementation technique may remain for planning only when the specification already states the invariant, constraint, and accepted risk boundary. If specification approval is withheld, remain in this stage even when planning is requested.

### 5. Hand off to the plan

After specification approval, follow `superpowers:writing-plans`. Give it the approved specification as the source of product truth.

The plan must trace each work item to an acceptance criterion, include test intent, and identify verification commands or observable evidence.

Present the plan summary and recommend one delivery owner. Wait for the user to approve the plan and confirm the delivery owner before implementation begins. Either action by itself is insufficient.

### 6. Choose one delivery owner

Offer the execution mode that fits the work:

| Situation | Delivery owner |
|---|---|
| Independent tasks in the current session | `superpowers:subagent-driven-development` |
| A written plan executed in a separate session | `superpowers:executing-plans` |

Let the selected delivery owner control implementation sequencing, TDD, task review, and plan checkpoints. Apply `superpowers:systematic-debugging` when unexpected behavior or test failure appears.

The one-owner rule applies to the full approved plan. The selected owner may coordinate subagents according to its own workflow; do not invoke the other executor as a parallel or nested orchestration layer over the same plan.

To change owners mid-plan, stop the current owner, preserve its state and evidence, and get explicit approval for the replacement. The two owners must never overlap on the same active plan.

Avoid adding a second generic review pass when the selected executor already includes the same review. Add `superpowers:requesting-code-review` only for a distinct, justified review boundary.

### 7. Verify and finish

Before any completion claim, follow `superpowers:verification-before-completion` and run fresh checks. Fresh means the planned verification suite plus checks implied by the final changes ran on the current worktree after the last relevant change to code, configuration, migrations, tests, fixtures, or build inputs, during the current completion assessment. Report the exact evidence and any remaining limits.

When work occurs on a development branch, follow `superpowers:finishing-a-development-branch` after verification.

### 8. Route material changes back

Treat a change as material when it changes approved scope, observable behavior, acceptance criteria, domain rules, constraints, permissions, safety, security, or compliance. If implementation reveals such a change, pause affected work and return to:

`grilling → shared-understanding approval → to-spec → writing-plans`

Use `superpowers:systematic-debugging` only to reproduce, inspect, and gather the technical facts needed to describe the decision. Do not make behavior-changing edits to affected work until the product decision is approved. Revise the affected plan before resuming delivery.

A local implementation discovery may stay in delivery only when it preserves the complete approved contract, including scope, behavior, domain rules, constraints, and acceptance criteria. A proposed scope item stays outside the approved contract until the user accepts it for the current delivery. While the decision is pending, pause potentially affected work; independent work may continue. Acceptance triggers the full loop; deferral leaves current delivery on its approved path.

## Quick Reference

| State | Next skill | Exit condition |
|---|---|---|
| Product intent is unresolved | `grilling` | Material decisions are answered |
| Recap is drafted | Wait for the user | Recap is explicitly approved |
| Recap is approved | `to-spec` | Specification is drafted |
| Specification is drafted | Wait for the user | Specification is explicitly approved |
| Specification is approved | `superpowers:writing-plans` | Actionable plan is written |
| Plan is ready | Wait for the user | Plan and one delivery owner are explicitly approved |
| Plan and owner are approved | One delivery owner | Planned work and reviews are complete |
| Implementation and executor-owned reviews are complete | `superpowers:verification-before-completion` | Fresh evidence supports the claim |
| Branch is verified | `superpowers:finishing-a-development-branch` | User selects a finish path |

## Example

User: `Use $grill-powers to take saved-search sharing from idea to delivery.`

1. Grill Me resolves audience, access, expiry, revocation, and audit expectations one decision at a time.
2. The user approves the recap and `SPEC.md`.
3. `superpowers:writing-plans` maps acceptance criteria to implementation and tests.
4. One delivery owner executes the plan.
5. Fresh tests and observable behavior support the completion report.

## Common Mistakes

- Treating a polite recap as approval. Wait for an explicit confirmation.
- Replacing `to-spec` with an informal handoff. Preserve the fixed specification gate.
- Sending unresolved product questions into `superpowers:writing-plans`.
- Running multiple delivery workflows over the same plan.
- Duplicating a review already owned by the executor.
- Claiming completion from an earlier test run or an agent report. Run fresh verification.
- Absorbing a material scope change inside implementation. Route it back through discovery and specification.
