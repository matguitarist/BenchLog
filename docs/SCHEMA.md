# BenchLog library schema

The library is one SQLite file (`benchlog.sqlite`) plus a `Files/` folder next to it.
Any client (the Mac app, a future iOS app, an Android app, or a sync server) can read it.
Migrations live in `Sources/BenchLogKit/Migrations.swift`. They are only ever added, never edited.

## Conventions

- `id`: a lowercase UUID as TEXT, made by the client that creates the row.
- Dates: TEXT `YYYY-MM-DD HH:MM:SS.SSS` in UTC.
- `createdAt` and `updatedAt` on every row; every write sets `updatedAt`. A sync can use last-writer-wins per row.
- `deletedAt`: NULL while the row is live. Deleting sets it (soft delete), so the deletion can sync and Undo can bring the row back.
- Booleans are INTEGER 0/1. Money (from M4 on) is INTEGER cents.

## Tables

| Table | Columns |
| --- | --- |
| `meta` | `key` TEXT PK, `value` TEXT. Keys: `nextTicketNumber`, `nextInvoiceNumber`, `business` (the business profile, JSON: details, `country` `CA`/`US`, `region` code, `taxes` [{kind, rate, number}], `localRate`, `taxesLabour`; a profile without `taxes` reads as Québec from its old `tpsRate`/`tvqRate`/`tpsNumber`/`tvqNumber`). |
| `customer` | `name`, `phone` (as typed), `phoneDigits` (digits only, for search), `email`, `address`, `documentsLanguage` (`fr` or `en`), `isShop` (v9; one row, the business as an owner, left out of lists and search) |
| `device` | `customerId` → customer, `category` (`computer` `phone` `tablet` `console` `handheld` `other`), `brand`, `model`, `revision`, `serial`, `colour`, `condition`, `passcode`, `passcodeIsPattern` (the pattern is stored as `1-5-9-6`), `purchaseCents`, `disposition` (`forSale` `kept` `sold`, null = in stock), `salePriceCents`, `soldAt` (v9) |
| `repair` | `deviceId` → device, `ticketNumber` INTEGER UNIQUE (shown as `#0042`), `status`, `complaint`, `diagnosis`, `receivedAt`, `promisedAt`, `completedAt`, `pickedUpAt`, `discountCents`, `approvalRule` (`go`, `ask`, `upTo`), `approvalLimitCents` (with `upTo`, before taxes) |
| `note` | `ownerType` (`customer` `device` `repair`), `ownerId`, `kind` (`text`, or `status`, where `text` holds the new status), `text` |
| `labourLine` | `repairId` → repair, `description`, `kind` (`hourly` or `flat`), `hundredthHours` (1.5 h = 150), `unitCents` (the rate, or the flat price) |
| `invoice` | Estimates and invoices. `repairId` → repair, `kind` (`estimate` or `invoice`), `number` INTEGER UNIQUE (invoices only, shown as `F-0001`), `issuedAt`, `validUntil`, `language`, `content` (the frozen document as JSON: business, customer, lines, totals with one entry per tax in `totals.taxes` [{kind, rate in millionths, cents}] and `taxableCents`; documents issued before M7 have `tpsRate`/`tvqRate`/`tpsCents`/`tvqCents` instead, still read), `totalCents`, `paidAt`, `paymentMethod` (`cash` `debit` `credit` `eTransfer`), `decision` (`approved` or `refused`), `decidedAt`, `fileId` → the PDF attachment. v10: `kind` may be `creditNote`, with `creditNumber` INTEGER UNIQUE (`NC-0001`) and `creditsInvoiceId` → invoice (unique: one credit per invoice); a credit note's `paidAt`/`paymentMethod` record its refund. `meta.nextCreditNumber` holds the next credit number. v11 rebuilds the table: `repairId` is optional and `deviceId` → device marks the sale of a shop device. v14 rebuilds it again with `customerId` → customer for a counter sale (the shop customer for a walk-in); one of `repairId`, `deviceId`, `customerId` is always set. |
| `part` | `name`, `sku`, `vendor`, `url`, `costCents`, `priceCents` (what a customer pays for one), `quantity`, `lowStockThreshold` (0 = none). v16: `kind` (`part` `accessory` `cable` `controller` `supply`), `condition` (`new` `used` `refurbished`, null = not set), `location` (shelf, bin, or drawer), `notes`. v17: `barcode` (the UPC or EAN on the box, digits only with a right check digit, a 13-digit code starting with 0 stored as its 12-digit UPC; '' = none); `kind` may be `game`. The models it fits are in `partFit` (`partId`, `category`, `brand`, `model`), local; they travel inside the part's sync row as `_fits`. |
| `stockMove` | v12. One change to a part's stock: `partId` → part, `delta` (units in, or out when negative), `quantityAfter`, `reason` (`opening` `installed` `returned` `received` `counted` `damaged` `sold` `adjusted`), `repairId` → repair, `invoiceId` → invoice, `restockId`, `note`. A part's `quantity` equals the sum of its moves. |
| `restock` | v13. An order of stock for the shelf: `vendor`, `status` (`draft` `ordered` `received`), `orderedAt`, `receivedAt`. |
| `restockLine` | v13. `restockId` → restock, `partId` → part, `quantity`, `costCents` (what the vendor charges; receiving copies it to the part). Receiving adds a `received` stock move with `restockId`. |
| `search` | FTS5, derived: never edit it by hand. `kind`, `itemId`, `targetKind`, `targetId` (what opens), `title`, `subtitle`, `keys` (ticket digits, phone digits, diagnosis, note text). Triggers named `search_<table>_*` keep it current. A sync client can rebuild it. |
| `catalog` | `category`, `brand`, `model`, `revision` ('' for the model itself). PK is all four. No id: it is reference data that grows from what people enter. |

Repair `status` values, in workflow order: `intake`, `diagnosing`, `awaitingApproval`, `waitingOnParts`,
`inProgress`, `ready`, `pickedUp`, `cancelled`. The last two close a repair.

## Sync (v2)

The server (`server/`) stores rows without knowing their columns: each is `table`, `id`,
`updatedAt`, `deletedAt`, and `data` (the row's columns as JSON, the same names as here).

- Push: a row is stored when its `updatedAt` is later than the server's copy (last writer
  wins). Equal or older is kept out. Each stored row gets the next server sequence number.
- Pull: every row with a sequence number after the client's cursor, oldest first, in pages.
  A client applies a pulled row when it is newer than its own and never queues it again.
- Deleting is a row with `deletedAt` set; Empty Trash on one device does not delete rows
  on the server.
- Numbers: the server keeps `ticket`, `invoice`, and `credit` sequences. Tickets come in
  blocks a client keeps for offline check-in; invoice and credit numbers one at a time.
  `start` moves a sequence forward, never back; `return` takes back an unused number while
  it is still the last one out, so a failed document leaves no gap. A connected library keeps
  its ticket blocks in `meta.ticketBlocks` (local) and never numbers invoices on its own.
- Files: an attachment's bytes go to `/v1/files/<attachment id>` with their SHA-256.
- The first client claims the server with its `libraryId`; a server holds one library.
- Search (`search`) is derived on each device and never synced.
- `device.passcode` travels sealed (`sealed:v1:` + base64 of AES-GCM nonce, text, and tag)
  with the library key, which never reaches the server. `meta/keyCheck` holds the sealed text
  "BenchLog library key", so a joining device can check its key.

## Sync notes

- Ticket numbers come from one counter. With more than one device creating repairs, the server should hand out numbers, or each client should take a block of them.
- Invoice numbers have the same problem as ticket numbers, and the law wants them without gaps: let the server hand them out.
- The passcode is sealed before it leaves the device (S-054).
