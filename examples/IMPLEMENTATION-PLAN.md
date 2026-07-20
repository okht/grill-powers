# Saved Search Links - example implementation plan

> Fictional plan. Paths and commands illustrate traceability; they do not describe this repository.

## Task 1: Persist the active token

- Acceptance criteria: `AC-1`, `AC-2`, `AC-5`
- Add a migration for a unique active token hash per saved search.
- Write failing model tests for create, reuse, revoke, and recreate.
- Implement the smallest persistence behavior that passes the tests.
- Verification intent: run the saved-search model test file.

## Task 2: Create and revoke links

- Acceptance criteria: `AC-1`, `AC-2`, `AC-5`
- Write failing request tests for editor permission, repeated creation, and synchronous revocation.
- Add create and revoke endpoints using existing authorization helpers.
- Verification intent: run the sharing request tests.

## Task 3: Resolve a shared view

- Acceptance criteria: `AC-3`, `AC-4`, `AC-6`
- Write failing request tests for same-workspace access, cross-workspace access, unknown tokens, and revoked tokens.
- Resolve the current saved-search definition after authorization.
- Reuse the existing not-found response without leaking metadata.
- Verification intent: run request tests and inspect the rendered shared view.

## Task 4: Complete delivery

- Acceptance criteria: all
- Run the focused suite, full suite, formatting checks, and static analysis.
- Complete the reviews owned by the selected executor.
- Record fresh commands, exit status, and observable behavior in `VERIFICATION.md`.
