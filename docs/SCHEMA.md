# BenchLog library schema

The library is one SQLite file (`benchlog.sqlite`) plus a `Files/` folder next to it.
Any client (the Mac app, a future iOS app, an Android app, or a sync server) can read it.
Migrations live in `Sources/BenchLogKit/Library.swift`. They are only ever added, never edited.

## Conventions

- `id`: a lowercase UUID as TEXT, made by the client that creates the row.
- Dates: TEXT `YYYY-MM-DD HH:MM:SS.SSS` in UTC.
- `createdAt` and `updatedAt` on every row; every write sets `updatedAt`. A sync can use last-writer-wins per row.
- `deletedAt`: NULL while the row is live. Deleting sets it (soft delete), so the deletion can sync and Undo can bring the row back.
- Booleans are INTEGER 0/1. Money (from M4 on) is INTEGER cents.

## Tables

| Table | Columns |
| --- | --- |
| `meta` | `key` TEXT PK, `value` TEXT. Keys: `nextTicketNumber`, `nextInvoiceNumber`, `business` (the business profile, JSON). |
| `customer` | `name`, `phone` (as typed), `phoneDigits` (digits only, for search), `email`, `address`, `documentsLanguage` (`fr` or `en`) |
| `device` | `customerId` → customer, `category` (`computer` `phone` `tablet` `console` `handheld` `other`), `brand`, `model`, `revision`, `serial`, `colour`, `condition`, `passcode`, `passcodeIsPattern` (the pattern is stored as `1-5-9-6`) |
| `repair` | `deviceId` → device, `ticketNumber` INTEGER UNIQUE (shown as `#0042`), `status`, `complaint`, `diagnosis`, `receivedAt`, `promisedAt`, `completedAt`, `pickedUpAt`, `discountCents`, `approvalRule` (`go`, `ask`, `upTo`), `approvalLimitCents` (with `upTo`, before taxes) |
| `note` | `ownerType` (`customer` `device` `repair`), `ownerId`, `kind` (`text`, or `status`, where `text` holds the new status), `text` |
| `labourLine` | `repairId` → repair, `description`, `kind` (`hourly` or `flat`), `hundredthHours` (1.5 h = 150), `unitCents` (the rate, or the flat price) |
| `invoice` | Estimates and invoices. `repairId` → repair, `kind` (`estimate` or `invoice`), `number` INTEGER UNIQUE (invoices only, shown as `F-0001`), `issuedAt`, `validUntil`, `language`, `content` (the frozen document as JSON: business, customer, lines, tax rates in millionths, totals), `totalCents`, `paidAt`, `paymentMethod` (`cash` `debit` `credit` `eTransfer`), `decision` (`approved` or `refused`), `decidedAt`, `fileId` → the PDF attachment |
| `search` | FTS5, derived: never edit it by hand. `kind`, `itemId`, `targetKind`, `targetId` (what opens), `title`, `subtitle`, `keys` (ticket digits, phone digits, diagnosis, note text). Triggers named `search_<table>_*` keep it current. A sync client can rebuild it. |
| `catalog` | `category`, `brand`, `model`, `revision` ('' for the model itself). PK is all four. No id: it is reference data that grows from what people enter. |

Repair `status` values, in workflow order: `intake`, `diagnosing`, `awaitingApproval`, `waitingOnParts`,
`inProgress`, `ready`, `pickedUp`, `cancelled`. The last two close a repair.

## Sync notes (v2)

- Ticket numbers come from one counter. With more than one device creating repairs, the server should hand out numbers, or each client should take a block of them.
- Invoice numbers have the same problem as ticket numbers, and the law wants them without gaps: let the server hand them out.
- The passcode is sensitive. Encrypt it before it leaves the Mac.
