# BenchLog — User stories

Source: `docs/BRIEF.md`. No research and no screen index; the functional reference is the HTML draft in `~/Developer/bench-log-server`.
Snapshot pages are named in `Screens:` and are built by snapshot mode.

---

## M1 Intake loop — check in a device and track its repair

### S-001 Library and database on first launch
As the user, I open BenchLog for the first time and it creates its library (`~/Library/Application Support/BenchLog/` with `benchlog.sqlite` and a `Files/` folder), then shows the main window.
Screens: repairs-empty
Acceptance:
- [unit] Migrations create every M1 table. Every row has a UUID `id`, `createdAt`, `updatedAt`, and a nullable `deletedAt`.
- [unit] Saving a record updates `updatedAt`. Deleting sets `deletedAt` instead of removing the row.
- [self] Quitting and relaunching keeps every customer, device, and repair.
- [unit] `BenchLogKit` builds without importing SwiftUI or AppKit.
UX:
- Flow: first launch -> library created silently -> main window opens on Repairs (empty state)
- Surface: none (no window of its own). If the library cannot be created: an alert "Unable to create the BenchLog library", with the path and the reason, and the buttons "Choose Folder…" and "Quit"
- States: first launch shows the Repairs empty state; on a later launch with a database from a newer version: "This library was made by a newer BenchLog. Update the app to open it."
- Words: Library (never "database" in the UI)
- Access: n/a
Status: done

### S-002 Add a customer
As the user, I press ⌘⇧N (or + in Customers), type a name, phone, email, and notes, and save.
Screens: customers-list, customer-new-sheet
Depends: S-001
Acceptance:
- [snap] The sheet shows Name (required), Phone, Email, Address, Notes, and a "Documents language" choice (Français default / English).
- [unit] Phone numbers are stored as typed and searched by digits only, so "514 555-1234" matches "5145551234".
- [snap] The new customer appears in the list, sorted by name, and is selected.
UX:
- Flow: ⌘⇧N, File > New Customer…, + in the Customers toolbar, or "New Customer…" in the New Repair sheet -> Name has focus -> Return saves (Name required) -> sheet closes, customer selected; Escape cancels and asks first only when a field has text
- Surface: sheet titled "New Customer" (one short task that finishes before going on)
- States: empty Customers "No Customers" with "New Customer"; error "Enter a name." under Name; a long name truncates in the list with a tooltip
- Words: "New Customer", "Add Customer" (confirm button), "Documents language: Français / English", tooltip "Add a customer (⌘⇧N)"
- Access: tab order Name → Phone → Email → Address → Notes → language; VoiceOver labels match the field labels
Built: the Notes field becomes the first note on the customer's timeline (one idea of a note). Edit… on the customer page reuses this sheet.
Status: done

### S-003 Add a device to a customer
As the user, I click "Add Device" on a customer's page and pick a category, brand, model, and revision, then enter the serial or IMEI, colour, and condition.
Screens: customer-detail, device-new-sheet
Depends: S-002
Acceptance:
- [snap] Category is a picker (Computer, Phone, Tablet, Console, Handheld, Other). Brand, Model, and Revision are combo boxes fed by the catalog.
- [unit] Typing a brand, model, or revision that is not in the catalog adds it to the catalog under that category.
- [unit] The catalog starts with every console from the draft (Nintendo, Sega, Atari, Sony, Microsoft, …) plus common Apple, Samsung, Google, Dell, HP, and Lenovo models.
- [snap] The customer page lists their devices with an icon per category, then brand, model, and serial.
UX:
- Flow: "Add Device…" on the customer page or ⌘⇧D with a customer selected -> Category picker (Phone by default) -> Brand → Model → Revision combo boxes, each filtered by the field before it -> Serial/IMEI, Colour, Condition -> Return saves -> the device row appears and is selected
- Surface: sheet titled "Add Device" (short task)
- States: an empty device list on a customer shows "No devices yet" with "Add Device"; a new catalog value shows "Adds “OLED Model” to the catalog" under the field; error "Choose a brand and model." when either is empty
- Words: "Add Device", "Serial or IMEI", "Condition" (placeholder "Scratches, cracks, missing screws…")
- Access: the combo boxes accept typing plus ↓ to open; a category is shown with an icon and a word, never the icon alone
Status: done

### S-004 Store a device passcode, hidden
As the user, I enter the device's passcode or pattern on intake, and it stays hidden until I click to show it.
Screens: device-detail
Depends: S-003
Acceptance:
- [snap] The passcode shows as dots with an eye button. Clicking the eye shows it, and it hides again when I leave the page.
- [unit] The passcode is never included in invoice, intake slip, or export-to-PDF output.
UX:
- Flow: Passcode field in the Add Device sheet and on the device page -> masked (•••• dots) -> the eye button or ⌘⌥P shows it -> it hides again when the page is left or after 30 s
- Surface: inline field (one value on screen)
- States: empty shows "No passcode"; there is a "Pattern" toggle with a 3×3 dot pad to record Android patterns as numbers 1–9
- Words: "Show Passcode" / "Hide Passcode" (tooltip with the shortcut), "Passcode", "Pattern"
- Access: VoiceOver reads "Passcode, hidden" until shown; the eye button has a label
Status: done

### S-005 Open a repair ticket for a device
As the user, I click "New Repair" on a device (or press ⌘N anywhere, then pick a customer and device) and type the complaint. The ticket gets the next number.
Screens: repair-new-sheet, repair-detail
Depends: S-003
Acceptance:
- [unit] Ticket numbers go up by one with no gaps or repeats, and are formatted #0001.
- [snap] The new repair shows its ticket number, customer, device, complaint, received date, a promised date (optional), and status Intake.
- [snap] From the customer picker in the sheet, "New Customer…" and "New Device…" open inline without losing what I typed.
UX:
- Flow: ⌘N, File > New Repair…, toolbar +, "New Repair" on a device or customer -> sheet with Customer (pre-filled when one is selected) → Device → Complaint (focus) → Promised date -> "Create Repair" (⌘Return) -> sheet closes, the repair opens with #0042 shown
- Surface: sheet titled "New Repair". "New Customer…" and "Add Device…" expand inline sections inside this sheet, never a second sheet
- States: a customer with no devices opens the inline Add Device section automatically; error "Describe the complaint." under Complaint
- Words: "New Repair", "Create Repair", "Complaint" (placeholder "What the customer says is wrong"), "Promised", tooltip "Open a repair for a device (⌘N)"
- Access: the customer field is a search-as-you-type list (name or phone digits), ↓/↑ and Return pick
Status: done

### S-006 Move a repair through its statuses
As the user, I change a repair's status from its detail page, its context menu, or ⌘1–⌘8.
Screens: repair-detail, repairs-list
Depends: S-005
Acceptance:
- [unit] The statuses are Intake, Diagnosing, Awaiting Approval, Waiting on Parts, In Progress, Ready, Picked Up, and Cancelled.
- [unit] Moving to Ready sets `completedAt`. Moving to Picked up sets `pickedUpAt`. Each change writes an automatic note ("Status → Ready").
- [snap] Each status has a coloured pill: grey (Intake/Diagnosing), yellow (Awaiting/Waiting), teal (In progress), green (Ready), faded (Picked up/Cancelled).
UX:
- Flow: the status pill on the repair page is a menu; the row context menu has a Status submenu; Repair > Status ⌘1–⌘8 -> the status changes, the pill colour updates, and a timeline note is added -> ⌘Z undoes
- Surface: inline menu on the pill (changes one value on screen)
- States: Picked Up and Cancelled rows are dimmed; leaving Picked Up needs no confirmation (Undo covers it)
- Words: the status names from the glossary, "Undo Change Status"
- Access: each pill has an icon and a word as well as a colour (circle.dotted, hourglass, wrench, checkmark…)
Status: done

### S-007 Repairs list grouped by status
As the user, I open Repairs in the sidebar and see the open tickets grouped by status, with the oldest first in each group.
Screens: repairs-list, repairs-empty
Depends: S-006
Acceptance:
- [snap] Each row shows ticket #, customer, device (brand and model), complaint (one line), days on the bench, and the status pill.
- [snap] A filter switches between Open (default), Ready, Closed, and All.
- [snap] With no repairs, the page shows "No repairs yet" and a New Repair button.
UX:
- Flow: sidebar Repairs -> list grouped by status in workflow order -> ↑/↓ moves, Return or a double-click opens the repair page, Space shows a Quick Look of the timeline
- Surface: sidebar page with a list and a detail split (a place people come back to)
- States: empty "No Repairs" with "New Repair"; the filter (Open / Ready / Closed / All) is a segmented control in the toolbar; 1,000+ rows scroll in a lazy list; days on the bench turns orange after 14 days, shown with a number and not colour alone
- Words: "Open", "Ready", "Closed", "All", "3 d" for bench days with the tooltip "On the bench for 3 days"
- Access: VoiceOver row "Repair #0042, Mario Tremblay, Nintendo Switch OLED, In Progress, 3 days"
Status: done

### S-008 Log a note on a repair
As the user, I type in the note field on a repair and press Return. The note is saved with its time and shows in the repair's timeline.
Screens: repair-detail
Depends: S-005
Acceptance:
- [snap] The timeline mixes my notes and the automatic status notes, newest last, each with a date and time.
- [unit] The same note model attaches to a customer or a device (`ownerType` and `ownerId`).
- [snap] Customer and device pages show their own notes, and the device page also shows the repair history.
UX:
- Flow: Add Note field at the bottom of the timeline, or ⌘⇧K to focus it -> type -> Return adds, ⇧Return makes a new line -> the note appears at the bottom and the field stays focused
- Surface: inline field (repeated input with the result visible)
- States: empty timeline "No notes yet"; a note can be edited or moved to trash from its context menu (⌘Z undoes); status notes are greyed and cannot be edited
- Words: "Add Note", placeholder "Add a note…", "Edit Note", "Move to Trash"
- Access: each note reads "Note, 9 Nov 2026 14:32, <text>"
Built: Return adds the note; ⌥Return makes a new line (macOS's own key for a vertical field), not ⇧Return.
Status: done

### S-009 Sidebar and navigation
As the user, I move between Repairs, Customers, Devices, Parts, and Guides in a sidebar, and links take me from a repair to its customer or device and back.
Screens: repairs-list, customers-list, devices-list
Depends: S-002, S-005
Acceptance:
- [snap] The sidebar shows Repairs (open count badge), Customers, Devices, Parts, and Guides, with SF Symbols.
- [self] Clicking the customer name on a repair opens that customer, and Back (⌘[) returns to the repair.
- [snap] The Devices page lists every device with its customer and the status of its last repair.
UX:
- Flow: ⌘⌥1–5 or a sidebar click moves between pages; customer and device names on a repair are links; Go > Back ⌘[ / Forward ⌘]
- Surface: NavigationSplitView sidebar with a content list and a detail pane
- States: the Repairs badge counts open repairs only; Parts and Guides show "Coming soon" empty states until M2/M3
- Words: "Repairs", "Customers", "Devices", "Parts", "Guides"
- Access: the sidebar is reachable with ⌘⌥S (focus); links are buttons with the label "Open customer Mario Tremblay"
Built: ⌘⌥1–6 pick the pages (Log is the 6th). Not built: ⌘⌥S to focus the sidebar.
Status: done

---

## M2 Bench — photos, files, parts

### S-010 Add photos to a repair, device, or customer
As the user, I drag images in, paste them, or choose "Take Photo with iPhone" (Continuity Camera) on any repair, device, or customer page.
Screens: repair-detail-photos
Depends: S-008
Acceptance:
- [unit] Files are copied into `Files/<yyyy>/<uuid>.<ext>`. The database stores only the relative path, the size, and the original name.
- [snap] Photos show as a grid of thumbnails with captions. Double-click or Space opens Quick Look.
- [manual] Continuity Camera from an iPhone inserts the photo into the open repair.
UX:
- Flow: drop files from Finder, ⌘V a copied image or file, File > Import from iPhone (Take Photo, Scan Documents), or "Add Photo or File…" -> copied into the library -> thumbnail appears in "Photos and Files"
- Surface: inline section on the repair, device, and customer pages
- States: empty "Drop photos or files here, paste them, or use File > Import from iPhone."; click selects, Space or double-click opens Quick Look; Move to Trash with Undo
- Words: "Photos and Files", "Add Photo or File…", "Add Caption…", "Quick Look", "Show in Finder"
- Access: each photo reads "Photo, <kind>, <caption or name>"
Built: from SwiftUI's ImportFromDevicesCommands and importsItemProviders. [manual] Continuity Camera is not tried yet with a real iPhone.
Status: done

### S-011 Mark intake photos
As the user, I mark photos taken at check-in as "Intake" so the device's condition on arrival is on record.
Screens: repair-detail-photos
Depends: S-010
Acceptance:
- [snap] Intake photos show a badge and appear first.
- [unit] An attachment has a `kind` (intake, progress, final, document).
UX:
- Flow: right-click a photo > Kind > Intake, Progress, Final, or Document
- Words: badge "Intake" (« Dépôt »), separate from the Intake status (« Reçue »)
Status: done

### S-012 Attach any file
As the user, I drop a PDF, a boardview (.brd, .bdv, .fz, .cad, .tvw), or any other file onto a repair or device, and it is stored with an icon and opens in its default app.
Screens: repair-detail-photos
Depends: S-010
Acceptance:
- [unit] Unknown types are kept as-is. Boardview extensions are recognised and labelled "Boardview".
- [snap] Non-images show as file rows with an icon, name, and size.
Built: double-click a file opens it in its default app; the Boardview tag uses the extensions in Attachment.boardviewExtensions.
Status: done

### S-013 Add a part to inventory
As the user, I add a part with its name, SKU, vendor, URL, cost, sell price, quantity in stock, low-stock threshold, and compatible models.
Screens: parts-list, part-new-sheet
Depends: S-003
Acceptance:
- [snap] The Parts page has tabs: In stock, Low stock, To order, Incoming.
- [unit] Compatible models are links to catalog models.
Status: done
Built: the tabs are Inventory, Low Stock, To Order, Incoming. Fits are catalog category, brand, and model (no revision). Snapshots: parts-inventory, part-edit-sheet.

### S-014 Use a part on a repair
As the user, I add a part to a repair from inventory (or as free text) with a quantity, and track its status: Needed → Ordered → Received → Installed.
Screens: repair-detail-parts
Depends: S-013, S-005
Acceptance:
- [unit] Marking a stocked part Installed takes it out of stock. Removing it puts the stock back.
- [unit] When any part on a repair is Needed or Ordered, the app offers to set the repair to Waiting on parts.
- [snap] The part search on a repair lists compatible parts for the device's model first.
- [snap] To order and Incoming list the parts needed or ordered across all repairs, with the ticket each one is for (like the draft's "Parts to Order" and "Incoming").
Status: done
Built: a part in stock starts as Received, a typed part as Needed. The Add Part… popover is checked by the `parts(for:matching:)` unit test, not a snapshot (popovers do not show in window captures). Snapshots: repair-parts, parts-toorder, parts-incoming.

### S-015 Low-stock warning
As the user, I see which stock parts are at or below their threshold.
Screens: parts-list
Depends: S-013
Acceptance:
- [snap] The Low stock tab and its sidebar badge count parts with `qty <= threshold`.
Status: done
Built: the sidebar badge on Parts and the count on the Low Stock tab. Snapshot: parts-low.

### S-016 Manage the device catalog
As the user, I open Settings → Catalog to rename, merge, or delete brands, models, and revisions.
Screens: settings-catalog
Depends: S-003
Acceptance:
- [unit] Merging two models moves their devices, guides, and part compatibility to the one that remains.
- [snap] The catalog is an outline: category → brand → model → revision.
Status: todo

---

## M3 Guides — repair guide library

### S-017 Add a guide (PDF or Markdown)
As the user, I drop a PDF or a Markdown note into Guides, give it a title and tags, and link it to one or more catalog models (or to a whole brand or category).
Screens: guides-list, guide-detail
Depends: S-012, S-016
Acceptance:
- [unit] A guide has a `format` (pdf, markdown). Its file is stored as an attachment owned by the guide, and images a Markdown guide embeds are stored as attachments too.
- [snap] The Guides page lists guides grouped by category and brand, with a page-1 thumbnail.
Status: todo

### S-018 Read a guide in the app
As the user, I open a guide and read it in the app: PDFs in a PDF viewer with page thumbnails, search, and zoom, reopening at the page where I left off; Markdown guides rendered with headings, lists, and their images.
Screens: guide-detail
Depends: S-017
Acceptance:
- [snap] The PDFKit view has a thumbnail sidebar and a find bar (⌘F).
- [self] The last page read is remembered for each guide.
- [snap] A Markdown guide renders Obsidian image embeds `![[photo.jpg]]` as well as standard `![](photo.jpg)`, and shows a table of contents built from its `##` headings.
- [manual] "Open in Window" puts the guide in its own window beside the repair.
Status: todo

### S-019 See matching guides on a repair
As the user, I see guides for the device's model, brand, or category on a repair, most specific first.
Screens: repair-detail
Depends: S-017, S-005
Acceptance:
- [unit] Matching order: revision → model → brand → category.
- [snap] A "Guides" section on the repair lists the matches. One click opens one.
Status: todo

### S-020 Bulk import a guide folder
As the user, I drop a folder of PDFs and Markdown notes (for example my Obsidian "Repair Guides" vault), and BenchLog adds each one and guesses its brand and model from the folder path.
Screens: guides-import-sheet
Depends: S-017
Acceptance:
- [unit] `Nintendo/Consoles/NES/blinking-red-light.md` is linked to category Console, brand Nintendo, and model NES; `Portable Consoles` maps to Handheld; `Nintendo/Switch/OLED Model/fan.pdf` is linked to brand Nintendo, model Switch, and revision OLED Model.
- [unit] `_index.md` becomes the model's overview guide. `.obsidian/` folders are skipped. `![[image.jpg]]` is found anywhere in the vault, as Obsidian does.
- [unit] The title comes from the first `# ` heading, or else the file name (`blinking-red-light` → "Blinking Red Light").
- [unit] Importing the same folder again updates the guides that changed and does not duplicate any.
- [self] The test fixture is a copy of the real vault (`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Repair Guides/Repair Guide`) in `Tests/Fixtures/RepairGuides/`.
- [snap] A review sheet lets me fix the guessed links before importing.
Status: todo

---

## M4 Billing — quotes, invoices, and slips in French

### S-021 Price a repair
As the user, I add labour lines (description, hours or flat rate, price), and the parts on the repair are priced at their sell price. I can add a discount.
Screens: repair-detail-billing
Depends: S-014
Acceptance:
- [unit] All money is stored as integer cents. Subtotal = labour + parts − discount. TPS = 5 % of the subtotal and TVQ = 9.975 % of the subtotal, each rounded half-up to the cent.
- [unit] Tax rates come from Settings, and each invoice saves the rates it used, so a later rate change does not alter past invoices.
- [snap] The totals block shows Sous-total, TPS, TVQ, and Total in fr-CA format (« 1 234,56 $ »).
Status: todo

### S-022 Business details for documents
As the user, I enter my business name, address, phone, email, logo, TPS and TVQ registration numbers, the warranty text, and the terms in Settings → Business.
Screens: settings-business
Depends: S-001
Acceptance:
- [snap] Every field has a French label next to what it prints as.
- [unit] Invoice numbers have their own sequence (F-0001), separate from ticket numbers.
Status: todo

### S-023 Print an intake slip (bon de dépôt)
As the user, I print or save a PDF intake slip at check-in, with the customer, the device, the serial, the complaint, the condition, the intake photos (optional), the terms, and a signature line.
Screens: doc-intake-slip
Depends: S-005, S-022, S-011
Acceptance:
- [snap] The slip is in Québec French by default (« Bon de dépôt », « Description du problème », « Signature du client »), or in English when the customer's documents language is English.
- [unit] The passcode never appears on the slip.
- [manual] A French speaker checks that the wording and typography are correct (« », spaces before : ; ! ?, fr-CA dates « 9 novembre 2026 »).
Status: todo

### S-024 Generate an invoice (facture)
As the user, I click "Facturer" on a Ready repair and get an invoice PDF with my business details, the TPS/TVQ numbers, the customer, the device, the labour and parts lines, the taxes, the total, and the warranty text.
Screens: doc-invoice
Depends: S-021, S-022
Acceptance:
- [unit] Once issued, an invoice is frozen (its lines, prices, rates, and number). Changes need a new invoice or a credit note (Later).
- [snap] The invoice matches Québec practice: « Facture », « N° de TPS », « N° de TVQ », « Sous-total », « Total ».
- [self] The PDF is saved as an attachment (kind: document) on the repair and opens in Preview.
Status: todo

### S-025 Quote before work (estimation)
As the user, I print an estimate when the repair is Awaiting approval, and mark it approved or refused.
Screens: doc-estimate
Depends: S-021, S-022
Acceptance:
- [snap] « Estimation » uses the same layout as the invoice, with "valid until" and no invoice number.
- [unit] Marking it approved moves the repair to Waiting on parts or In progress, and writes a note.
Status: todo

### S-026 Record payment and pickup
As the user, I mark an invoice paid (cash, debit, credit, e-transfer) and the repair picked up.
Screens: repair-detail-billing
Depends: S-024
Acceptance:
- [unit] A paid invoice shows « PAYÉ » with the date and method on its reprint.
- [snap] Repairs that are Ready and unpaid show a "To collect" badge.
Status: todo

---

## M5 Speed — find anything fast

### S-027 Global search
As the user, I press ⌘F in the main window and search customers, phones, devices, serials and IMEIs, ticket numbers, notes, and parts at once.
Screens: search-results
Depends: S-009
Acceptance:
- [unit] SQLite FTS5 index. Searching "#12" or "12" finds ticket #0012, and digits match phone numbers.
- [snap] Results are grouped by type, and Return opens the top hit.
Status: todo

### S-028 Keyboard and menu commands
As the user, I do every main action from the menu bar with shortcuts: New Repair ⌘N, New Customer ⌘⇧N, Add Note ⌘⇧K, Add Photo ⌘⇧P, Print Slip ⌘P, Status ⌘1–8.
Screens: menu-file, menu-repair
Depends: S-006, S-010
Acceptance:
- [snap] A Repair menu exists. Every item there is disabled when no repair is selected.
Status: todo

### S-029 Spotlight
As the user, I type a customer name or ticket number in Spotlight and open it in BenchLog.
Depends: S-027
Acceptance:
- [manual] Customers and repairs are indexed with Core Spotlight and open the right page.
Status: todo

---

## M6 Polish — safety and settings

### S-030 Backup and restore
As the user, I export a full backup (database and files as one `.benchlog` zip) and restore one, and BenchLog makes an automatic daily backup.
Screens: settings-backup
Depends: S-001
Acceptance:
- [unit] A backup round-trips: export, wipe, import, and every row and file is identical.
- [snap] Settings → Backup shows the last backup time and the folder; the default keeps 14 daily backups.
Status: todo

### S-031 Empty states and first-run sample data
As the user, every page explains what goes there when it is empty. A Debug-only "Load sample data" fills the app for demos and snapshots.
Screens: repairs-empty, customers-empty, parts-empty, guides-empty
Acceptance:
- [snap] Each empty page has a sentence and a primary button.
- [unit] The sample data only uses fields the stories let the user set.
Status: todo

### S-032 App icon
As the user, I see a BenchLog icon in the Dock (a bench, multimeter, or screwdriver, made with the app-icon skill).
Acceptance:
- [manual] The icon reads well at 16 px and in light, dark, and tinted looks.
Status: done

### S-033 Delete and undo
As the user, I delete a customer, device, repair, part, or guide, and ⌘Z brings it back. Deleting a customer that has open repairs asks first.
Depends: S-001
Acceptance:
- [unit] Deletion is soft, and "Empty trash" in Settings removes rows older than 30 days along with their files.
- [self] ⌘Z after a delete restores the row and its children.
Status: todo

---

## Later
- **v2 Sync**: the Node server becomes a REST and SQLite sync service (pull and push by `updatedAt`, last-writer-wins per row, file upload). The Mac becomes a client.
- **v2 iPhone/iPad app** on `BenchLogKit`: camera-first intake and photos at the bench.
- **Android app** on the same sync API and `docs/SCHEMA.md`.
- Boardview viewer (OpenBoardView-style) for .brd/.bdv/.fz files.
- French app UI (the String Catalog already holds every string).
- Credit notes, refunds, monthly sales and tax report (TPS/TVQ totals per period).
- Customer SMS or email "your device is ready".
- Agent CLI/MCP (`benchlog repair list --open`).
- Warranty tracking: open a repair as "warranty of #0042".

## Dropped
- Accounts and login: a single user on their own Mac.
- Multi-technician assignment: a one-person shop.
- Online booking and payments: outside the scope of a bench tool.
- Analytics and onboarding tours: not needed for a personal app.
