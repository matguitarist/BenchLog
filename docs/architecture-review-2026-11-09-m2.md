# Architecture check-in, end of M2 (2026-11-09)

Survey: 5,800 lines. Largest file was `Models.swift` (415 lines; `AppModel` over 400). Hot spots in the last month: `Models.swift`, `SelfTest.swift`, the string catalog. The fix log has two entries of the same kind: one English word with two French meanings.

## Feature actions out of AppModel  [Strong] (done)

Files: Sources/BenchLog/Models.swift (415 lines)
Signal: a type over 400 lines; every story so far touched it.
Problem: state, reading, navigation, and every feature's actions shared one type body. M3 (guides) and M4 (invoices) would push it past 600.
Proposal: state, `read`, `write`, `reload`, and navigation stay in `Models.swift`; the feature actions move to `extension AppModel` in `Models+Actions.swift`. `write` goes from private to internal (documented as not for views).
Benefits: locality. A feature adds one file, or one section.
Proof of same behavior: 38 unit tests and 48 self-test checks pass before and after; the snapshots are unchanged.
Plan: one commit.

## A check for words with two meanings  [Worth exploring]

Files: tools/l10n-check.sh, Labels.swift
Signal: the same kind of bug twice (FIXLOG: "One English word, two French words", "Received read Reçue le").
Problem: a bare key like "Received" is shared by every use, and French needs a different word for a date label and a part status. Nothing catches it until someone reads a French snapshot.
Proposal: `l10n-check.sh` lists every bare key the compiler found in more than one file, so a reviewer looks at each. Status and filter words always get context keys (rule already in FIXLOG).
Benefits: catches the bug before a snapshot does.
Plan: one commit to the script; port to the other apps with `sync-mac-tools` if it helps.

## Considered, not recommended

- Splitting `BenchLogKit` by feature into several targets: 1,400 lines, one migrator; not worth it before sync exists.
- A protocol over `Library` for tests: it is already in-memory and fast; no second adapter is needed.

Top recommendation: the AppModel split (done in this check-in). The l10n check waits for your call.
