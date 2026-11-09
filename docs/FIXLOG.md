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
