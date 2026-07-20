# Specification handoff contract

The approved specification is the only product contract passed from Grill Me to `superpowers:writing-plans`.

## Required sections

1. **Problem and outcome** - who has the problem and what observable outcome matters.
2. **In scope** - behaviors included in this delivery.
3. **Out of scope** - adjacent work intentionally excluded.
4. **User flows** - happy path plus material alternate and failure paths.
5. **Acceptance criteria** - observable, testable statements with stable identifiers.
6. **Domain rules** - permissions, state transitions, invariants, limits, and terminology.
7. **Constraints** - confirmed technical, operational, compliance, or compatibility limits.
8. **Open decisions** - unresolved items that block planning. This section must be empty at approval time.
9. **Deferred decisions** - named choices intentionally postponed, with their safe boundary. Open requirements or risk boundaries for permissions, safety, security, data handling, and compliance cannot be deferred. Implementation techniques may remain for planning only after the invariant, constraint, and accepted risk boundary are recorded.
10. **Approval record** - approver, date, and the exact specification revision approved.

## Planning rule

`superpowers:writing-plans` may choose implementation structure. It may not silently change product behavior, acceptance criteria, or scope. A material change returns to Grill Me and a revised specification approval.
