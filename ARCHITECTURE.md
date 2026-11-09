# BenchLog architecture

## Targets (dependency direction: App → Kit → GRDB)

- **BenchLogKit**: data and rules, no SwiftUI or AppKit, so a future iOS app reuses it as is.
  - `Library.swift` opens `benchlog.sqlite` and `Files/`, and runs the migrations (added, never edited).
  - `Records.swift`: the row types (`Customer`, `Device`, `Repair`, `Note`) and the joined rows (`RepairRow`, `DeviceRow`).
  - `Library+<Domain>.swift`: one file per domain (Customers, Devices and catalog, Repairs, Notes and trash). Every write sets `updatedAt`; deleting sets `deletedAt`.
  - `CatalogSeed.swift`: the catalog a new library starts with.
  - `Attachment.swift`, `Part.swift`, `Catalog.swift` (outline, rename and merge, which also move devices, part fits, and guide links), `Guide.swift` (guides, their links, and matching a device: revision → model → brand → category).
  - `MarkdownHTML.swift`: Obsidian-flavoured Markdown to HTML (wiki links, image embeds, callouts, tags) and the page around it. Plain Foundation, for the iOS app too.
  - `Billing.swift`: `BusinessProfile` (in `meta`), labour lines, `Billing.totals` (subtotal, TPS and TVQ each rounded half up), and invoices and estimates. Issuing freezes a `DocumentContent` (business, customer, lines, rates, totals) as JSON, so later edits never change a printed document. Invoice numbers have their own sequence.
  - `Search.swift`: global search. An FTS5 table, `search`, filled and kept current by SQL triggers (one `Source` per table, plus the rows that show its text), so no write path can forget it. `Library.search` groups hits by kind.
  - `PageLayout.swift`: cuts one tall PDF page into Letter pages between blocks (Core Graphics only, for the iOS app too).
  - `DocumentHTML.swift`: the intake slip, estimate, and invoice as printable HTML, in the customer's language, with French typography (`typo`). No WebKit: the app prints it.
  - `GuideImport.swift`: `GuideScanner` reads a folder or vault and guesses each guide's title, tags, images, and link from its path; `importGuides` adds or updates by source path.
- **BenchLog** (the app, main-actor by default):
  - `Models.swift`: `AppModel` holds the open `Library`, the page and selection, the sheet, history, and undo. Every change goes through its `write`, so it is logged, and pages reload when `dataVersion` changes.
  - `Models+Guides.swift`: adding, importing, and reading guides. Turning a PDF page saves the page without `write`, so the app does not reload.
  - `Models+Billing.swift`: labour, discount, Business settings, and issuing documents. Each document is printed to PDF, saved on the repair as a document attachment, and opened in Preview.
  - `DocumentPrinter.swift`: HTML to a Letter PDF with an offscreen WKWebView: one tall `pdf(configuration:)` page plus the blocks it measured, handed to the Kit's `PageLayout`.
  - `Models+Actions.swift`: the actions by feature (customers and devices, repairs, notes, photos and files, parts, catalog). State stays in `Models.swift`; a new feature adds its actions here, or its own `Models+<Feature>.swift` once this file passes 300 lines.
  - `Views/SearchPanel.swift`: Search BenchLog (⌘F) over the main window, and `FindCommands`, which gives ⌘F to a PDF guide's find bar when one is in front.
  - `Pages/`: one file per sidebar page (list beside detail, in an `HSplitView`).
  - `Sheets/`: the sheets, and the customer and device fields they share.
  - `Views/`: parts used by several pages (Timeline, Passcode).
  - `Labels.swift`: the words, symbols, and colors for the Kit's values (Kit values have no interface strings).
  - `UI/`: shared with the other Mac apps (`sync-mac-tools`): Theme, Grid, WindowBehavior, AppearanceSettings, Components.
  - `SeedData`, `Snapshot`, `SelfTest`: test runs on a library in /tmp only (`APP_STORE`).

## Seams

- `Library(databaseURL:)` on disk and `Library()` in memory: tests and the self-test use the same code as the app.
- `APP_STORE`: every test, snapshot, and seed run uses a /tmp library and refuses the real one.

## Data

See `docs/SCHEMA.md`. Ids are lowercase UUID text, dates are UTC text, and money is integer cents, so other clients and a sync server can read the file.
