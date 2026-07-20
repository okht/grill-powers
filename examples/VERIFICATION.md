# Saved Search Links - example verification record

> Fictional evidence format. The results below show how to report verification; no command was run against this repository.

## Revision

- Example revision: `saved-search-links-demo`
- Specification: `SPEC.md`, example revision 1

## Automated checks

| Check | Example command | Example result | Criteria |
|---|---|---|---|
| Focused request tests | `npm test -- saved-search-sharing` | 12 passed, exit 0 | `AC-1` through `AC-6` |
| Full test suite | `npm test` | 428 passed, exit 0 | Regression guard |
| Static analysis | `npm run typecheck` | Exit 0 | Implementation integrity |
| Formatting | `npm run lint` | Exit 0 | Repository quality gate |

## Observable behavior

- Same-workspace member opens the link and sees the current saved-search definition.
- Cross-workspace request receives the existing not-found response.
- Revoked token fails immediately and does not reveal saved-search metadata.

## Review status

- Specification compliance review: complete, no open findings.
- Code quality review: complete, no open findings.

## Remaining limits

- Expiration and audit events remain deferred by the approved specification.
