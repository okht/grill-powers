# Saved Search Links - approved product PRD

> Fictional example. This document demonstrates the product-only GrillPowers handoff contract.

## Problem and outcome

Workspace members need to share a repeatable search view without asking each recipient to recreate filters. Success means an eligible recipient can open the current saved search from one stable link, while ineligible recipients learn nothing about it.

## Users and context

- Workspace editors share saved searches with colleagues in the same workspace.
- Signed-in workspace members open links they receive through their normal collaboration channels.
- Saved-search owners may end access when a link should no longer be usable.

## In scope

- Editors can create one active link for a saved search.
- Any signed-in member of the same workspace can open the link.
- The owner can revoke the link immediately.
- The shared view always reflects the latest saved-search definition.
- Access is re-evaluated whenever someone opens the link.

## Out of scope

- Public or cross-workspace sharing
- Per-recipient permissions
- Automatic expiration
- Copying a shared search into the recipient's account
- Audit history

## User flows

1. An editor opens a saved search and chooses to create a share link.
2. The product creates or returns the currently active link.
3. A signed-in member of the same workspace opens the link and sees the current search view.
4. An ineligible visitor sees the standard unavailable state and no saved-search details.
5. The owner revokes the link; every later attempt to open it shows the unavailable state.
6. If the owner shares again later, the product creates a different link and the revoked link remains unusable.

## Product rules

- A saved search has at most one active share link.
- Repeating the create action while a link is active returns that same link.
- Access requires current membership in the saved search's workspace.
- Revocation takes effect before the product reports success.
- Revocation is permanent for that link.
- An unavailable link reveals no saved-search name, filters, owner, or workspace details.

## Acceptance criteria

- `AC-1`: An editor can create a link for a saved search in the current workspace.
- `AC-2`: Repeating creation while a link is active returns the same active link.
- `AC-3`: A signed-in member of the same workspace can open the current saved-search view.
- `AC-4`: A visitor without current workspace access sees the standard unavailable state.
- `AC-5`: Revocation invalidates the link before the success response appears.
- `AC-6`: A revoked or unknown link reveals no saved-search details.
- `AC-7`: Sharing again after revocation creates a different link; the revoked link remains unusable.

## Open product decisions

None.

## Deferred product decisions

- Whether links can expire automatically
- Whether owners can grant access to selected recipients
- Whether the product should display a sharing audit history

## Approval record

- Approver: Fictional product owner
- Date: 2026-07-20
- Revision: Example PRD revision 1
- Status: Approved for autonomous technical delivery
