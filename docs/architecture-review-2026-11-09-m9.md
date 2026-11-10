# Architecture check-in: end of M9

M9 added a second program, `server/` (Node, `node:sqlite`, about 330 lines with tests), and
in the Kit `Sync.swift`, `SyncEngine.swift`, `Numbering.swift`, and `LibraryKey.swift`, one
migration (v15-sync), and in the app `SyncController.swift` and `Views/SyncViews.swift`.

Survey: the server keeps rows it does not understand, so a schema change on the Mac needs
no server change. The engine reaches the server only through `SyncTransport`, which has two
adapters: `HTTPSyncTransport` and the in-memory server in SyncTests (a real seam). ServerTests
and the self-test run the real server when Node is installed. Change capture is in SQLite
triggers, so every write path (including ones written later) queues its row; SyncTests fails
when a table has neither triggers nor a place in `localTables`.

## Migrations lived inside Library.swift  [Strong — done]

Files: Library.swift (499 lines)
Signal: carried from M8 ("first commit of v2"); one more migration this milestone.
Proposal and plan: `Migrations.swift` holds `Library.migrator`; `Library.swift` (48 lines)
opens the library. A move only, one commit; 152 tests pass before and after.

## SelfTest.swift passes 500 lines  [Worth exploring]

Files: Sources/BenchLog/SelfTest.swift (506 lines)
Signal: a file over 400 lines that grows with every story.
Problem: one long `Task` reads in order, which matters (invoice numbers), but finding a
story's checks takes a search.
Proposal: keep the order in `runIfRequested`, and move each milestone's block into a
`static func` in `SelfTest+<Milestone>.swift`, as `syncEndToEnd` already is.
Benefits: locality per feature. Worth it at the next milestone that adds checks.

## Library-wide settings in static variables  [Worth exploring, carried]

Still two values (`Money.currencyCode`, `CustomerDraft.defaultLanguage`); sync adds none.

## Considered, not recommended

- A schema-aware server (one table per type): every Mac migration would need a server
  release, and Android or iOS would need the same. The row store keeps the server stable.
- Clock-based pull (`updatedAt > lastSync`) instead of the server's sequence: device clocks
  disagree; the sequence never misses a row. `updatedAt` only decides conflicts.
- Removing the invoice-table CHECK now (M8 card): no new owner kind came in M9.

## Top recommendation

Done: the Migrations.swift move. Nothing else is `Strong`.
