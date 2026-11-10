# Architecture check-in, M11 (built-in server)

Survey: no Swift file passes 600 lines (largest: SelfTest.swift 547, Migrations.swift 455). M11 added one
target pair (`BenchLogServerKit`, `BenchLogServer`) that depends only on GRDB, Foundation, and Network, and
nothing in the app reaches into its internals: the app uses `BenchLogServer` (start, stop, token) and
`ServerHost` behind two adapters (login item, in-process).

## One API contract for both servers  [Strong] — done in this check-in

Files: server/src/*.js, Sources/BenchLogServerKit/*.swift, Tests/BenchLogKitTests/ServerTests.swift, BuiltInServerTests.swift
Signal: the same API now has two implementations; a rule changed in one would silently differ in the other.
Problem: the engine tests ran against both, but the HTTP-level tests (status codes, malformed rows, file checks)
ran against the Swift server only.
Proposal: `TestServer` (node | swift) starts either server on a free port; the HTTP tests and the engine tests
take it as an argument, so every contract test runs twice.
Benefits: locality — an API change shows up as a failing test against the server not yet changed.
Proof of same behavior: 161 tests pass, now with HTTP tests on both servers.

## Split SelfTest.swift by area  [Worth exploring]

Files: Sources/BenchLog/SelfTest.swift (547 lines)
Signal: the most edited file after STORIES.md in 30 days; near the 600-line mark.
Proposal: `SelfTest+Sync.swift` (syncEndToEnd, serverOnThisMac) and `SelfTest+Billing.swift`, sharing `check`.
Plan: one commit moving functions, no logic change; the self-test count stays 134.

## Considered, not recommended

- Running the Node server's own JS tests against the Swift server: the Swift HTTP tests now cover the same
  cases on both, in one place.
- Keep-alive in `HTTPServer`: one request per connection is enough on a shop network and keeps the parser small.
