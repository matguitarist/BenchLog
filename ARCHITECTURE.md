# BenchLog architecture

## Targets (dependency direction: App → Kit → GRDB)

- **BenchLogKit**: data and rules, no SwiftUI or AppKit, so a future iOS app reuses it as is.
  - `Library.swift` opens `benchlog.sqlite` and `Files/`, and runs the migrations (added, never edited).
  - `Records.swift`: the row types (`Customer`, `Device`, `Repair`, `Note`) and the joined rows (`RepairRow`, `DeviceRow`).
  - `Library+<Domain>.swift`: one file per domain (Customers, Devices and catalog, Repairs, Notes and trash). Every write sets `updatedAt`; deleting sets `deletedAt`.
  - `CatalogSeed.swift`: the catalog a new library starts with.
  - `Attachment.swift`, `Part.swift`, `Catalog.swift` (outline, rename and merge, which also move devices, part fits, and guide links), `Guide.swift` (guides, their links, and matching a device: revision → model → brand → category).
  - `MarkdownHTML.swift`: Obsidian-flavoured Markdown to HTML (wiki links, image embeds, callouts, tags) and the page around it. Plain Foundation, for the iOS app too.
  - `GuideImport.swift`: `GuideScanner` reads a folder or vault and guesses each guide's title, tags, images, and link from its path; `importGuides` adds or updates by source path.
- **BenchLog** (the app, main-actor by default):
  - `Models.swift`: `AppModel` holds the open `Library`, the page and selection, the sheet, history, and undo. Every change goes through its `write`, so it is logged, and pages reload when `dataVersion` changes.
  - `Models+Guides.swift`: adding, importing, and reading guides. Turning a PDF page saves the page without `write`, so the app does not reload.
  - `Models+Actions.swift`: the actions by feature (customers and devices, repairs, notes, photos and files, parts, catalog). State stays in `Models.swift`; a new feature adds its actions here, or its own `Models+<Feature>.swift` once this file passes 300 lines.
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
