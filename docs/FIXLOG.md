# Fix log

## 2026-11-09 One English word, two French words
Symptom: the Intake photo badge read « Reçue » (the repair status), the Ready filter « Prête » instead of « Prêtes », and the Open menu item would have read « Ouvertes ».
Cause: `String(localized: "Open")` uses the English text as the key, so every "Open" shares one French translation, whatever it means.
Fix: keys with a context for the words that differ: `filter.open`, `filter.ready`, `photo.intake`, … with `defaultValue:` and a `comment:`.
Rule: when an English word means two things on screen (a status and a filter, a verb and an adjective), give each its own key with a comment.

## 2026-11-09 UUIDs stored as blobs
Symptom: a unit test found ids saved as 16-byte blobs, not readable text.
Cause: a `databaseUUIDEncodingStrategy` default in a protocol extension lost to GRDB's own; GRDB 7 also made it a function.
Fix: `static func databaseUUIDEncodingStrategy(for:)` on `BenchRecord`, and queries pass `id.stored` (UUID's own database value is a blob).
Rule: compare UUIDs in queries with `.stored`, never the UUID itself.

## 2026-11-09 A Stepper in a Form row widened the whole repair detail

Symptom: with a part on a repair, the repair detail form was wider than its pane and cut off on the left.
Cause: a `Stepper` with a label inside a grouped `Form` row lays out as a full form row, and its minimum width pushed the form past the pane.
Fix: the count is a `Text`, and the `Stepper` beside it has `.labelsHidden()`. The same pattern is in the part sheet.
Rule: in a grouped Form, never give a Stepper a label view; put it in a `LabeledContent` with `.labelsHidden()`.

## 2026-11-09 "Received" read "Reçue le"

Symptom: a part's Received status read "Reçue le", the label of the repair's received date.
Cause: the same English key, "Received", had two meanings.
Fix: part statuses use their own keys (`part.needed`, `part.ordered`, `part.received`, `part.installed`).
Rule: a status or filter word gets a context key; check new words against the existing keys before you use them.

## 2026-11-09 An AppKit view with Auto Layout inside collapsed to nothing

Symptom: the PDF reader and the Markdown reader showed an empty area; the PDFView was 1 point tall.
Cause: SwiftUI sizes an `NSViewRepresentable` by its view's fitting size. A container whose subviews are pinned with constraints fits to zero, and `sizeThatFits` did not override it.
Fix: the PDF container lays out its subviews by hand in `layout()`; the web view has no constraints and a `sizeThatFits` that takes what is offered.
Rule: in an NSViewRepresentable, never pin subviews with Auto Layout to the root view; lay them out in `layout()` and return the proposal from `sizeThatFits`.

## 2026-11-09 Printing a document to PDF never finished

Symptom: the self-test hung at the first invoice; no PDF was written.
Cause: `NSPrintOperation.runModal` on an offscreen WKWebView's window never returns, and `run()` needs a visible window.
Fix: `DocumentPrinter` captures the page with `WKWebView.pdf(configuration:)` as one tall page and cuts it into Letter pages with Core Graphics, breaking between blocks it measured in the page.
Rule: never use NSPrintOperation for a view that is not on screen; make the PDF with `pdf(configuration:)` and paginate it yourself.

## 2026-11-09 A fresh library failed to open after the shop columns

Symptom: every new library failed at migration v7-search with "no such column: c.isShop".
Cause: the search sources leave the shop out with `c.isShop = 0`, but v7 installs its triggers and fills the index from the current sources, before v9 adds the column. Editing a shared source changed what an old migration does.
Fix: `SearchIndex.sources(version:)`; v7 installs version 1, v9 adds the columns and then calls `reinstall(db, version: 2)`.
Rule: a migration installs the search sources of its own version; a change to a source is a new version and a new migration that calls `reinstall`. Never make an old migration depend on code that later changes.

## 2026-11-09 French UI strings with English punctuation spacing

Symptom: Settings read « quotidiennes; celles… » and « Abandonner ce client? », with no space before ; and ?.
Cause: translations written by hand without the French spacing rules; nothing checked them.
Fix: a sweep of Localizable.xcstrings: a narrow no-break space (U+202F) before ; ! ?, a no-break space (U+00A0) before : and inside « ».
Rule: every French string gets U+202F before ; ! ? and U+00A0 before : and inside « »; add them when the string is written, never a plain space or none.
