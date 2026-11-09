# Architecture review — 2026-11-09 (end of M1)

Survey: 3,932 lines in 25 Swift files; the largest are `Models.swift` (291), `Library+Data.swift` (282),
`Records.swift` (220). No file is near 600 lines, there are no duplicate private types, the Kit has no
SwiftUI or AppKit, and the Library has two adapters (on disk and in memory), so its seam is real.
The next milestone (M2: photos, files, parts inventory) adds two domains to the Kit and the app.

## Library by domain  [Strong]

Files: Sources/BenchLogKit/Library+Data.swift (282 lines)
Signal: before a big feature. M2 adds attachments and parts (about 300 more lines) to this one file.
Problem: customers, devices, catalog, repairs, notes, and trash share one file. A change to parts would
scroll past repairs and catalog code, and two milestones from now the file would pass 600 lines.
Proposal: the same `extension Library` split by domain, with no interface change:
`Library+Customers.swift`, `Library+Devices.swift` (devices and catalog), `Library+Repairs.swift`,
`Library+Notes.swift` (notes and trash). M2 then adds `Library+Attachments.swift` and `Library+Parts.swift`.
Benefits: locality: each domain's queries sit in one short file; the tests already follow the same split.
Proof of same behavior: the 22 unit tests and the 31 self-test checks, before and after.
Plan: one commit (a move only).

## Navigation out of AppModel  [Worth exploring]

Files: Sources/BenchLog/Models.swift (291 lines)
Signal: a model that owns everything is starting: page and selection state, history, sheets, writes, undo.
Problem: Back and Forward rules live next to database writes; testing history needs the whole model.
Proposal: a `Navigator` value type (`Place`, back and forward stacks, `open`, `back`, `forward`) that
AppModel holds; pages keep calling `model.open(.customer(id))`.
Benefits: history becomes a unit test with no library; AppModel shrinks by about 70 lines.
Proof: the self-test's link, Back, and Forward checks.
Plan: when AppModel passes about 400 lines, or when M5's search adds another way to navigate.

## Reloads on every change  [Worth exploring]

Files: Models.swift (`dataVersion`), every page's `.task(id: model.dataVersion)`, Sheets/Fields.swift
Signal: state that changes on every write is observed by every visible page.
Problem: one note added reloads the list, the detail, and the timeline. `DeviceFields` also runs up to six
catalog queries in its body on each keystroke. Fine at bench scale (hundreds of rows), measurable at thousands.
Proposal: GRDB `ValueObservation` per page query, or per-table versions (`repairsVersion`, `notesVersion`).
Proof: the same snapshots; an Instruments trace of typing in Add Device before and after.
Plan: measure first with the `performance` skill once a real library has a year of repairs.

## Considered, not recommended

- A repository protocol in front of `Library`: one production type plus an in-memory twin already gives
  tests their seam; a protocol would only forward calls.
- Moving `Labels.swift` (status and category words) into the Kit: the Kit stays free of interface strings,
  and documents get their own fr-CA wording in M4.

**Top recommendation:** Library by domain, now, before M2.
