# Architecture check-in: end of M8

M8 added `Stock.swift`, `Restock.swift`, `CounterSale.swift`, and `Inventory.swift` in the
Kit, three migrations (v12-stock, v13-restock, v14-counter-sales, which rebuilds `invoice`
again), and `StockViews.swift`, `RestockViews.swift`, and `CounterSaleSheet.swift` in the app.
Each story added one Kit file with its own tests; no Swift file is over 460 lines.

Survey: the largest files are `Library.swift` (457, mostly migrations), `SelfTest.swift` (448),
and `MarkdownHTML.swift` (426). The hot spots in the last day are the docs, the self-test, the
string catalog, and `Models.swift` (one enum case per story). `Part.quantity` is written in one
place only, `Library.moveStock`, apart from saving a part (which records its own move), so
the stored count and the stock history cannot drift apart.

## Migrations live inside Library.swift  [Worth exploring]

Files: Sources/BenchLogKit/Library.swift (457 lines, 14 migrations)
Signal: the file grows by one migration per milestone and will pass 600 lines in v2.
Problem: opening the library, file storage, and 300 lines of append-only SQL share a file;
a migration is hard to find by name.
Proposal: `Migrations.swift` with `extension Library { static var migrator: DatabaseMigrator }`;
`Library.swift` keeps opening, files, and meta.
Benefits: locality for schema work; `docs/SCHEMA.md` and the migrations sit side by side.
Proof of same behavior: a move; ModelTests checks the applied migration list, and the
v11/v14 rebuild tests open old invoices.
Plan: one commit, at the start of v2 (sync), when the schema grows next.

## The invoice table is rebuilt to change its CHECK  [Worth exploring]

Files: Library.swift (v11-sales, v14-counter-sales)
Signal: the same rebuild, with its column list copied, written twice.
Problem: every new kind of invoice owner means another table rebuild and another copied
column list; a missed column would drop data silently.
Proposal: a helper `rebuildInvoice(_ db:, columns:, check:)` used by future migrations (the
old ones stay as written: migrations are never edited), or drop the CHECK and enforce
"one owner" in `Documents.swift`, where the tests already cover it.
Benefits: one place to get a rebuild right. Worth it if v2 adds another owner.

## App-wide settings read through static variables  [Worth exploring, carried from M7]

`Money.currencyCode` and `CustomerDraft.defaultLanguage` are still the only two; no third
value appeared in M8, so the card stays as it was.

## Top recommendation

None is `Strong`: M8 kept to one Kit file per feature, each with its own test suite, and
nothing crossed the size or repetition triggers. Ship 1.0.0 as it is; do the Migrations.swift
move as the first commit of v2.

Considered, not recommended:
- Deriving `Part.quantity` from the sum of moves on every read: slower lists for no gain,
  since `moveStock` is the only writer and StockTests checks that they agree.
- Splitting `SelfTest.swift` by feature: it reads as one script in order, and order matters
  (invoice numbers); splitting would hide that.
