# Architecture check-in: end of M7

M7 added `Taxes.swift`, `Report.swift`, credit notes and sale invoices in the Kit, two
migrations (v10-credit-notes, v11-sales, which rebuilds `invoice`), and `TaxSection.swift`
and `ReportsPage.swift` in the app. `Totals` changed shape (one line per tax) with a
decoder for documents issued before.

## Billing.swift held pricing and every kind of document  [Strong — done]

Files: Sources/BenchLogKit/Billing.swift (576 lines)
Signal: a file near 600 lines; three of the M7 stories edited it.
Problem: tax pricing and document issuing changed for different reasons and lived in one file.
Proposal: `Documents.swift` takes the document types (`DocumentKind`, `DocumentContent`,
`Invoice`, `BillingError`) and issuing (estimates, invoices, credit notes, sale invoices,
payments, decisions, To Collect). `Billing.swift` keeps the profile, labour, and pricing.
Proof of same behavior: a move only; 122 tests and 104 self-test checks pass before and after.
Plan: one commit (this one).

## App-wide settings read through static variables  [Worth exploring]

Files: Labels.swift (`Money.currencyCode`), Sheets/Fields.swift (`CustomerDraft.defaultLanguage`)
Signal: two `nonisolated(unsafe) static var`s set in `AppModel.reload()`.
Problem: values that follow the business profile live in globals, so a view can read a
stale one, and a test must remember to set them.
Proposal: an `@Observable BusinessContext` on the model (currency, documents language,
tax names) passed in the environment; `Money.text(_:in:)` takes it.
Benefits: one source for profile-derived values. Worth it when a third such value appears.

## The invoice table holds four kinds of document  [Speculative]

Files: Documents.swift, Report.swift, Trash.swift
Signal: `kind` checks (`invoice`, `estimate`, `creditNote`) and a `repairId` / `deviceId` pair.
Problem: each new query must remember which kinds it means. Today every query names them.
Proposal: request helpers (`Invoice.issuedForTax`, `Invoice.estimates`) when a fourth query
filters by kind.

Top recommendation: the split, done. The rest waits for its signal.

Considered, not recommended: a separate `creditNote` table. Credit notes share every
column, the PDF, payment, and the report with invoices; one table keeps the report one query.
