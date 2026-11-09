# BenchLog

A native Mac app for a one-person electronics repair bench (computers, phones, game consoles, any device) to track customers, their devices, repair tickets, parts, guides, photos and invoices.

## Replaces
The Bench Log HTML/Node draft (`~/Developer/bench-log-server`): a single-page tracker with Parts, Projects (tickets #0001…) and Customers, plus a console catalog. Its data file is empty, so no migration is needed.

## Main jobs
1. **Check in a device**: find or create the customer, pick or add their device, open a repair ticket with the complaint, and take intake photos.
2. **Work the bench**: move tickets through statuses, log timestamped notes and photos, open the matching PDF guide, and order or use parts.
3. **Close out**: price labour and parts, print an invoice or receipt, and mark the ticket picked up.

## Data
All records have a `UUID id`, `createdAt` and `updatedAt`, and soft-delete (`deletedAt`), so sync can be added later.
- **Customer**: name, phone, email, address, notes → has many Devices
- **Device**: customer, category (computer / phone / tablet / console / handheld / other), brand, model, revision, serial/IMEI, passcode, colour, condition notes → has many Repairs
- **Repair**: ticket number, device, status (Intake → Diagnosing → Awaiting approval → Waiting on parts → In progress → Ready → Picked up / Cancelled), complaint, diagnosis, labour lines, discount, tax, dates (in, promised, done, picked up)
- **Part**: name, SKU, vendor, URL, cost, sell price, stock quantity, low-stock threshold, compatible models
- **PartUse**: repair, part (or free-text), quantity, status (needed → ordered → received → installed), price charged
- **Note**: text and timestamp, attached to a customer, device or repair
- **Attachment**: file (photo / PDF / boardview later), caption, attached to a customer, device, repair or guide. The file lives in the app's library folder; the database stores only its relative path.
- **Guide**: title, format (PDF or Markdown, imported from the Obsidian "Repair Guides" vault), file attachment and embedded images, linked catalog models, tags
- **Catalog**: category → brand → model → revision. It starts with the draft's console list and grows from what you enter.

## Shape
A sidebar window (Repairs · Customers · Devices · Parts · Guides) on macOS 26 or later. Local data, works offline, no accounts.
Storage is SQLite (GRDB) behind a `BenchLogKit` package with no UI code, so an iPhone/iPad app can reuse it unchanged. The schema is documented in `docs/SCHEMA.md` so an Android app or a sync server can follow it. *(GRDB over SwiftData: decided by the agent, for a portable schema)*

## System hooks
Continuity Camera ("Take Photo" from iPhone) and drag-and-drop for photos and PDFs, Print / Save as PDF for invoices and intake slips, Quick Look, and Spotlight for customers and tickets. A CLI comes later.

## Reference
none (the HTML draft is the functional reference)

## Look
Plain native Mac look with the system accent colour. Status colours: grey / yellow / teal / green, carried over from the draft.

## Locale and documents
- Québec: CAD, TPS 5 % + TVQ 9.975 % on the subtotal. Rates and the business's TPS/TVQ registration numbers are set in Settings and printed on every invoice.
- **Invoices, intake slips and receipts are in polished Québec French first** (fr-CA number, date and currency formats: « 1 234,56 $ »), with English as an option per customer.
- The app interface is English first, with every string in a String Catalog so French can be added later.
- Device passcodes are stored and hidden behind a reveal button. They never print on documents.
- Ticket numbers continue as #0001 and up. *(decided by the agent)*

## Not in version one
- Sync, the iPhone/iPad app and Android (planned: v2 adds a sync server evolved from the Node server, then iOS)
- Boardview viewer (attachments accept the files now; the viewer comes later)
- Customer SMS/email notifications, online booking, payments, multi-user accounts
