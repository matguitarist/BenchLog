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

## A Stepper in a Form row widened the whole repair detail

Symptom: with a part on a repair, the repair detail form was wider than its pane and cut off on the left.
Cause: a `Stepper` with a label inside a grouped `Form` row lays out as a full form row, and its minimum width pushed the form past the pane.
Fix: the count is a `Text`, and the `Stepper` beside it has `.labelsHidden()`. The same pattern is in the part sheet.
Rule: in a grouped Form, never give a Stepper a label view; put it in a `LabeledContent` with `.labelsHidden()`.

## "Received" read "Reçue le"

Symptom: a part's Received status read "Reçue le", the label of the repair's received date.
Cause: the same English key, "Received", had two meanings.
Fix: part statuses use their own keys (`part.needed`, `part.ordered`, `part.received`, `part.installed`).
Rule: a status or filter word gets a context key; check new words against the existing keys before you use them.
