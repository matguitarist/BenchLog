# Architecture check-in: end of M6

M6 added `Backup.swift`/`ZipArchive.swift`, `Approval.swift`, `Shop.swift`, and `Trash.swift`
in the Kit, and one or two app files per feature (`Backups.swift`, `RepairApproval.swift`,
`ShopViews.swift`, `Models+Trash.swift`). No Swift file is over 430 lines; the largest are
`MarkdownHTML.swift` (426), `Billing.swift` (397), and `SelfTest.swift` (381). The files
touched most this milestone are the shared hubs (`Models.swift`, `SelfTest.swift`,
`App.swift`, `Library.swift`), each by a few lines per story.

The M5 card "Search index changes need a reinstall step" came due with v9-shop and is done:
`SearchIndex.sources(version:)` and `reinstall`, with a FIXLOG entry.

## Empty Trash must know every table that points at a trashable row  [Strong — done]

Files: Sources/BenchLogKit/Trash.swift
Signal: a bug waiting to happen. `emptyTrash` deletes in dependency order by hand.
Problem: a future table with a foreign key to a repair (say, a warranty claim) makes Empty
Trash fail with a foreign key error, or leaves orphans. Nothing would say so until a user
emptied the Trash 30 days later.
Proposal: `Library.purgedReferences`, the foreign keys `emptyTrash` handles, and a test that
reads every foreign key from SQLite (`PRAGMA foreign_key_list`) and compares.
Benefits: locality. The test names the missing reference the day the table is added.
Proof of same behavior: no code path changed; 104 tests pass.
Plan: one commit (this one).

## The shop is a customer row that lists must leave out  [Speculative]

Files: Library+Customers.swift, Billing.swift, Search.swift, Trash.swift, Shop.swift
Signal: `isShop` appears in 5 Kit files.
Problem: a new list of customers must remember `isShop = 0`. Today the three lists that
matter (Customers, search, To Collect) do, and device lists include the shop on purpose.
Proposal: a `Customer.people` request (not deleted, not the shop) used by every list.
Benefits: one place to read. Worth it once a fourth customer list appears.

## SelfTest grows by a block per story  [Speculative]

Files: Sources/BenchLog/SelfTest.swift (381 lines)
Signal: about 30 lines per story. At 600 lines, split it into one file per milestone
(`SelfTest+M5.swift`, …) with the harness left in `SelfTest.swift`.

Top recommendation: the trash reference guard, done in this check-in. Nothing else needs
doing now.

Considered, not recommended: moving `SeedData` into the Kit so a unit test can check its
fields (it builds `NSImage` photos and PDFs; the Kit has no AppKit).
