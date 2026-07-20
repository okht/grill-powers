# Saved Search Links - approved specification

> Fictional example. This document demonstrates the GrillPowers handoff contract.

## Problem and outcome

Workspace members need to share a repeatable search view without asking each recipient to recreate filters. A successful recipient can open the current saved search from one stable link.

## In scope

- Editors can create one active link for a saved search.
- Any authenticated member of the same workspace can open the link.
- The owner can revoke the link immediately.
- The shared view reads the latest saved-search definition.

## Out of scope

- Public or cross-workspace sharing
- Per-recipient permissions
- Automatic expiration
- Copying a shared search into the recipient's account

## User flows

1. An editor opens a saved search and selects `Create share link`.
2. The system creates or returns the active link.
3. A signed-in member of the same workspace opens the link and sees the current search view.
4. The owner revokes the link; later requests show the existing not-found state.

## Acceptance criteria

- `AC-1`: An editor can create a link for a saved search in the current workspace.
- `AC-2`: Repeating creation while a link is active returns the same active link.
- `AC-3`: An authenticated member of the same workspace can open the current saved-search view.
- `AC-4`: A user from another workspace receives the existing not-found response.
- `AC-5`: Revocation invalidates the link before the success response returns.
- `AC-6`: A revoked or unknown token does not reveal saved-search metadata.

## Domain rules

- A saved search has at most one active share token.
- Tokens are unguessable and stored as hashes.
- Authorization is evaluated on every open request.
- Revocation is irreversible; sharing again creates a new token.

## Constraints

- Reuse existing authentication and not-found behavior.
- Do not add a public route.

## Open decisions

None.

## Deferred decisions

- Expiring links may be added later without changing the current access rule.
- Audit events are deferred until the workspace audit project defines its event schema.

## Approval record

- Approver: Fictional product owner
- Date: 2026-07-20
- Revision: Example revision 1
- Status: Approved for planning
