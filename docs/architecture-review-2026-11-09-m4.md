# Architecture review: end of M4 (Billing), 2026-11-09

Survey: no Swift file over 600 lines (largest: MarkdownHTML 426, Billing 394, DocumentHTML 303).
Most-changed files in 30 days: STORIES, Models.swift, SelfTest, the string catalog, Library.swift.
No duplicate `private struct`s. One new fix-log entry (offscreen printing), in a new area.

## Page breaking lives in the Kit  [Strong] (done)

Files: Sources/BenchLog/DocumentPrinter.swift
Signal: pure logic inside a `@MainActor` type; only the self-test could reach it, and the iOS app will print the same documents.
Problem: `breaks` and `paginate` use only Core Graphics, but sat in the app's WebKit printer. Changing the break rule meant a full app build and a self-test run to check it.
Proposal:
```swift
public enum PageLayout {
    public static let letter: CGSize
    public static let margin: CGFloat
    public struct Block { public var top, bottom: CGFloat }
    public static func breaks(height: CGFloat, usable: CGFloat, blocks: [Block]) -> [CGFloat]
    public static func paginate(_ tallPDF: Data, blocks: [Block]) -> Data?
}
```
DocumentPrinter keeps only WebKit: load, measure the blocks, make the tall page.
Benefits: unit tests cover the break rule (five cases, including a 3-page PDF); the iOS app reuses it.
Proof of same behavior: the five document snapshots (doc-*.png) are byte-identical before and after (md5).
Plan: one commit.

## Billing.swift splits into values and Library+Billing  [Speculative]

Files: Sources/BenchLogKit/Billing.swift (394 lines)
Signal: none yet. Part.swift and Guide.swift use the same shape (types, then `extension Library`).
Proposal: split when it passes 600, or when credit notes (Later) arrive.

## Document numbering for sync  [Worth exploring]

Signal: invoice numbers, like ticket numbers, come from one local counter, and invoices must have no gaps.
Proposal: a `NumberSource` seam (local counter now, server-issued blocks later), decided with the sync API.

## Snapshot states table  [Speculative]

Files: Sources/BenchLog/Snapshot.swift (234 lines)
Signal: each milestone adds states and per-state scroll fractions inline.
Proposal: one `SnapshotState` struct (name, set-up, scroll) when the file passes 300 lines.

Top recommendation: the PageLayout move, done in its own commit.
Considered, not recommended: splitting AppModel further (Models.swift is 257 lines, and the feature extensions are working).
