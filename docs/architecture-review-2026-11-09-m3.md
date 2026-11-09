# Architecture check-in, end of M3 (2026-11-09)

Survey: 8,000 lines. No file over 600. The largest are `MarkdownHTML.swift` (426, one job) and `GuideReader.swift` (379, two readers). `AppModel` stays at 254 lines plus feature extensions.

## Two readers, two files  [Strong] (done)

Files: Sources/BenchLog/Views/GuideReader.swift (379 lines)
Signal: a view file over the 300-line guide, holding two unrelated readers.
Proposal: `GuideReader.swift` keeps the switch and the PDF reader; `MarkdownGuideReader.swift` takes the Markdown reader and the web view.
Proof of same behavior: the build, 51 tests, 54 self-test checks, and the guide snapshots.

## A real Markdown parser  [Speculative]

Files: Sources/BenchLogKit/MarkdownHTML.swift
Signal: none yet. The renderer is line-based with regular expressions, which covers the vault today (tests in `MarkdownTests`).
Proposal: if notes start to break (nested quotes in lists, HTML blocks, footnotes), parse with `swift-markdown` (cmark-gfm) and keep the Obsidian steps (embeds, wiki links, callouts) as a pass before it. The interface (`render` → body and headings) stays.

## The l10n check for words with two meanings  [Worth exploring]

Carried over from the M2 review; still waiting for your call.

Top recommendation: the reader split (done).
