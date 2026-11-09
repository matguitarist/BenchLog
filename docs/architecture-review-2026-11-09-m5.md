# Architecture review: end of M5 (Speed), 2026-11-09

Survey: no Swift file over 600 lines (largest: MarkdownHTML 426, Billing 394). App files stay under 300.
No duplicate `private struct`s. No new fix-log entries in M5.
M5 added Search.swift (Kit), SearchPanel and FindCommands, and Spotlight.swift: each feature is in one or two new files, and Models.swift grew by 26 lines.

## Search index changes need a reinstall step  [Worth exploring]

Files: Sources/BenchLogKit/Search.swift, Library.swift
Signal: the index's SQL is copied into triggers when migration v7 runs. Editing a `Source` later (say, indexing the device colour) changes nothing in existing libraries.
Problem: the next search change can silently do nothing for existing libraries.
Proposal:
```swift
extension SearchIndex {
    /// Drops the table and its triggers and installs the current sources. Call it from a new migration.
    static func reinstall(_ db: Database) throws
}
```
Proof: a unit test that runs v7, changes nothing, runs reinstall, and gets the same hits.
Plan: one commit, together with the first change to a source.

## SelfTest grows by a block per story  [Speculative]

Files: Sources/BenchLog/SelfTest.swift (295 lines)
Signal: about 300 lines, one long function.
Proposal: one `SelfTest+<Milestone>.swift` per area once it passes 400 lines or the compiler slows on it.

## Spotlight rebuilds everything  [Speculative]

Files: Sources/BenchLog/Spotlight.swift
Signal: a full delete and re-add after each settled change. That is fine for hundreds of records.
Proposal: index changed records only, if a library ever reaches thousands of repairs (measure first, with the performance skill).

Top recommendation: none needs doing now. Do the reinstall step with the first change to the search sources.
Considered, not recommended: a Commands file split (App.swift is 177 lines).
