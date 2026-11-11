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
Status: done
Built: Settings → Catalog, one category at a time; Rename…, Merge Into, and Delete from Catalog… in the context menu. Renaming to an existing name merges. Guides do not exist yet: S-017 must move guide links on a merge too. Snapshot: settings-catalog.

---

## M3 Guides — repair guide library

### S-017 Add a guide (PDF or Markdown)
As the user, I drop a PDF or a Markdown note into Guides, give it a title and tags, and link it to one or more catalog models (or to a whole brand or category).
Screens: guides-list, guide-detail
Depends: S-012, S-016
Acceptance:
- [unit] A guide has a `format` (pdf, markdown). Its file is stored as an attachment owned by the guide, and images a Markdown guide embeds are stored as attachments too.
- [snap] The Guides page lists guides grouped by category and brand, with a page-1 thumbnail.
- [unit] Merging catalog models (S-016) moves guide links to the model that remains.
Status: done
Built: Add Guides… (⌘ none), drop files or a folder on Guides; a single dropped note brings the images beside it. Edit Guide sets title, tags, and what it covers (category, brand, model, revision; empty widens). Markdown guides have no page-1 thumbnail: they show a document glyph. Snapshots: guides, guide-edit-sheet.

### S-018 Read a guide in the app
As the user, I open a guide and read it in the app: PDFs in a PDF viewer with page thumbnails, search, and zoom, reopening at the page where I left off; Markdown guides rendered with headings, lists, and their images.
Screens: guide-detail
Depends: S-017
Acceptance:
- [snap] The PDFKit view has a thumbnail sidebar and a find bar (⌘F).
- [self] The last page read is remembered for each guide.
- [snap] A Markdown guide renders Obsidian image embeds `![[photo.jpg]]` as well as standard `![](photo.jpg)`, and shows a table of contents built from its `##` headings.
- [manual] "Open in Window" puts the guide in its own window beside the repair.
Status: done
Built: PDFKit with a thumbnail column, a find bar (⌘F, ⌘G, ⇧⌘G), and zoom (⌘−, ⌘0, ⌘+); the page is saved as you read, without reloading the app. Markdown renders in a web view with the Contents list; wiki links open the linked guide, web links open in the browser. [manual] Open in Window still needs a try by hand. Snapshots: guide-pdf, guide-markdown.

### S-019 See matching guides on a repair
As the user, I see guides for the device's model, brand, or category on a repair, most specific first.
Screens: repair-detail
Depends: S-017, S-005
Acceptance:
- [unit] Matching order: revision → model → brand → category.
- [snap] A "Guides" section on the repair lists the matches. One click opens one.
Status: done
Built: the Guides section on a repair, between Diagnosis and Parts, with "This revision", "This model", the brand, or the category beside each. Snapshot: repair-guides.

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
Status: done
Built: a folder from Add Guides… or a drop opens Import Guides. Change… sets what a guide covers for its whole folder. "Playstation" maps to Sony. The fixture is Tests/Fixtures/RepairGuides (25 notes, 3 images); the unit test imports all of it. Snapshot: guides-import-sheet.

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
Built: Billing section on the repair (labour lines on two rows: description, then hourly or flat × rate = amount; parts at sell price; discount; totals). Unpriced parts are named and left off. Rates come from Settings → Business and are frozen in each document. Snapshot: repair-billing (not repair-detail-billing).
Status: done

### S-022 Business details for documents
As the user, I enter my business name, address, phone, email, logo, TPS and TVQ registration numbers, the warranty text, and the terms in Settings → Business.
Screens: settings-business
Depends: S-001
Acceptance:
- [snap] Every field has a French label next to what it prints as.
- [unit] Invoice numbers have their own sequence (F-0001), separate from ticket numbers.
Built: Settings → Business, each field with « Prints as … » in French; tax rates, hourly rate, estimate validity, warranty and terms in both languages, logo. Invoice numbers F-0001 are a separate sequence in `meta`. Snapshot: settings-business.
Status: done

### S-023 Print an intake slip (bon de dépôt)
As the user, I print or save a PDF intake slip at check-in, with the customer, the device, the serial, the complaint, the condition, the intake photos (optional), the terms, and a signature line.
Screens: doc-intake-slip
Depends: S-005, S-022, S-011
Acceptance:
- [snap] The slip is in Québec French by default (« Bon de dépôt », « Description du problème », « Signature du client »), or in English when the customer's documents language is English.
- [unit] The passcode never appears on the slip.
- [manual] A French speaker checks that the wording and typography are correct (« », spaces before : ; ! ?, fr-CA dates « 9 novembre 2026 »).
Built: Print Intake Slip (⌘P) in the Documents section; intake photos are included. The passcode is never printed. Saved as a document on the repair and opened in Preview. [manual] French wording and typography still need a check by a French speaker. Snapshot: doc-intake-slip.
Status: done

### S-024 Generate an invoice (facture)
As the user, I click "Facturer" on a Ready repair and get an invoice PDF with my business details, the TPS/TVQ numbers, the customer, the device, the labour and parts lines, the taxes, the total, and the warranty text.
Screens: doc-invoice
Depends: S-021, S-022
Acceptance:
- [unit] Once issued, an invoice is frozen (its lines, prices, rates, and number). Changes need a new invoice or a credit note (Later).
- [snap] The invoice matches Québec practice: « Facture », « N° de TPS », « N° de TVQ », « Sous-total », « Total ».
- [self] The PDF is saved as an attachment (kind: document) on the repair and opens in Preview.
Built: Facturer (⇧⌘I) issues the next number and freezes the content; the PDF is saved on the repair and opens in Preview. Pages break between lines, never through one. Snapshots: doc-invoice (English customer), doc-invoice-french.
Status: done

### S-025 Quote before work (estimation)
As the user, I print an estimate when the repair is Awaiting approval, and mark it approved or refused.
Screens: doc-estimate
Depends: S-021, S-022
Acceptance:
- [snap] « Estimation » uses the same layout as the invoice, with "valid until" and no invoice number.
- [unit] Marking it approved moves the repair to Waiting on parts or In progress, and writes a note.
Built: Print Estimate, with « Valide jusqu’au » and an approval signature; Approve or Refuse on the document row moves the repair and writes a note to the timeline. Snapshot: doc-estimate.
Status: done

### S-026 Record payment and pickup
As the user, I mark an invoice paid (cash, debit, credit, e-transfer) and the repair picked up.
Screens: repair-detail-billing
Depends: S-024
Acceptance:
- [unit] A paid invoice shows « PAYÉ » with the date and method on its reprint.
- [snap] Repairs that are Ready and unpaid show a "To collect" badge.
Built: the Paid menu on each invoice (cash, debit, credit, e-transfer, or Mark Unpaid) reprints it with « PAYÉ ». "To Collect" shows on Ready repairs with no paid invoice. Picking up uses the existing status menu (Picked Up). Snapshots: doc-invoice-paid, repairs.
Status: done

---

## M5 Speed — find anything fast

### S-027 Global search
As the user, I press ⌘F in the main window and search customers, phones, devices, serials and IMEIs, ticket numbers, notes, and parts at once.
Screens: search-results
Depends: S-009
Acceptance:
- [unit] SQLite FTS5 index. Searching "#12" or "12" finds ticket #0012, and digits match phone numbers.
- [snap] Results are grouped by type, and Return opens the top hit.
UX:
- Flow: ⌘F (Edit > Search BenchLog…) -> type -> ↑↓ move, Return opens the selected result (the top hit first) -> the page shows it. Escape or a click outside closes. In a PDF guide, ⌘F is Find in Guide and Search moves to ⌥⌘F.
- Surface: a panel over the main window, like Open Quickly (a lookup kept beside the work, not a page to come back to).
- States: hint prompt before typing; "Nothing matches « … »."; up to 6 results per kind.
Built: an FTS5 index (migration v7-search) kept current by triggers on customer, device, repair, note, part, and guide; passcodes are never indexed; accents are ignored. A note opens its customer, device, repair, or guide. Snapshot: search-results.
Status: done

### S-028 Keyboard and menu commands
As the user, I do every main action from the menu bar with shortcuts: New Repair ⌘N, New Customer ⌘⇧N, Add Note ⌘⇧K, Add Photo ⌘⇧P, Print Slip ⌘P, Status ⌘1–8.
Screens: menu-file, menu-repair
Depends: S-006, S-010
Acceptance:
- [snap] A Repair menu exists. Every item there is disabled when no repair is selected.
Built: File has New Repair ⌘N, New Customer ⇧⌘N, Add Device ⇧⌘D, Add Note ⇧⌘K, and Add Photo or File… ⇧⌘P (the last two act on the repair, customer, or device shown). The Repair menu has Status (⌘1–8), Print Intake Slip ⌘P, Print Estimate, Invoice ⇧⌘I, Open Customer, and Open Device, each disabled with no repair selected. Search BenchLog… ⌘F is in Edit. A self-test reads the real menu bar to check this, in place of the menu-file and menu-repair snapshots: an open menu cannot be captured while the snapshot run is going.
Status: done

### S-029 Spotlight
As the user, I type a customer name or ticket number in Spotlight and open it in BenchLog.
Depends: S-027
Acceptance:
- [manual] Customers and repairs are indexed with Core Spotlight and open the right page.
Built: `Spotlight.swift` indexes every customer (name, phone, email, phone digits) and repair ("#0012 Mario Tremblay", device, status, complaint, serial) in Core Spotlight, rebuilt 2 s after changes stop and only when something changed. Choosing a result opens that customer or repair. Libraries in /tmp are never indexed. Passcodes, notes, and addresses stay out. [manual] Still to try on the real library: type a name or "#0012" in Spotlight and pick the result.
Status: done

---

## M6 Polish — safety and settings

### S-030 Backup and restore
As the user, I export a full backup (database and files as one `.benchlog` zip) and restore one, and BenchLog makes an automatic daily backup.
Screens: settings-backup
Depends: S-001
Acceptance:
- [unit] A backup round-trips: export, wipe, import, and every row and file is identical.
- [snap] Settings → Backup shows the last backup time and the folder; the default keeps 14 daily backups.
UX:
- Flow: Settings → Backup → Back Up Now writes "BenchLog <date> <time>.benchlog"; Restore from Backup… -> pick a file -> "Restore the Backup from <date>?" -> Restore (destructive) or Cancel.
- Surface: a Settings tab (rare actions and preferences).
- Safety: restore backs the library up first ("BenchLog Before Restore …"), checks the backup before replacing anything, and refuses a backup from a newer BenchLog.
Built: a `.benchlog` file is a stored ZIP (manifest.json, benchlog.sqlite made with SQLite's backup, Files/…) that any unzip tool opens; written to a partial file and renamed when done. Daily backups ("BenchLog Daily <date>") run when the last one is a day old, checked hourly; the 15th oldest daily goes to the Trash; backups you make yourself stay. The folder defaults to ~/Documents/BenchLog Backups. Test and snapshot runs back up next to their /tmp library and never on their own. Snapshot: settings-backup.
Status: done

### S-031 Empty states and first-run sample data
As the user, every page explains what goes there when it is empty. A Debug-only "Load sample data" fills the app for demos and snapshots.
Screens: repairs-empty, customers-empty, parts-empty, guides-empty
Acceptance:
- [snap] Each empty page has a sentence and a primary button.
- [unit] The sample data only uses fields the stories let the user set.
Built: every list page's empty state has a sentence and one primary button (Repairs: New Repair; Customers: New Customer; Devices: New Repair; Shop: Add Shop Device…; Parts: New Part; Guides: Add Guides…). Help > Load Sample Data in debug builds (`./build.sh --debug`) fills an empty library with `SeedData`. `APP_SEED=0 APP_SHOTS=/tmp/BenchLog-shots-empty tools/snap.sh` shoots the empty pages. The [unit] line is held by review, not a test: SeedData lives in the app target, and its header states the rule.
Status: done

### S-032 App icon
As the user, I see a BenchLog icon in the Dock (a bench, multimeter, or screwdriver, made with the app-icon skill).
Acceptance:
- [manual] The icon reads well at 16 px and in light, dark, and tinted looks.
Status: done

### S-034 Approval before work
As the user, I record at check-in whether the customer wants an estimate before I repair: Go ahead, Ask first (an estimate is required), or Go ahead up to an amount. BenchLog holds me to it.
Screens: new-repair-sheet, repair-approval, doc-intake-slip
Depends: S-025
Acceptance:
- [unit] A repair stores its approval rule (`go`, `ask`, or `upTo` with an amount in cents). An approved estimate satisfies it. With `upTo`, a bill whose total exceeds the amount needs an approved estimate again.
- [snap] The repair shows "Estimate required" or "Approved up to 150,00 $" next to its status, and the New Repair sheet has the rule.
- [self] Moving an unapproved repair to In Progress, Waiting on Parts, or Ready asks first: "Ask for Approval" moves it to Awaiting Approval, "Start Anyway" goes ahead.
- [snap] The intake slip prints the rule in French: « Estimation requise avant toute réparation » or « Réparation autorisée jusqu’à 150,00 $, taxes en sus ».
UX:
- Flow: New Repair → Approval: "Before repairing" (Go ahead / Ask for an estimate first / Go ahead up to an amount + "Up to, before taxes"); the last choice is the next default. Changeable on the repair. Moving to Waiting on Parts, In Progress, or Ready while it blocks → "Start Without Approval?" with Ask for Approval, Start Anyway, Cancel.
- Surface: a picker in the sheet and in the repair's top section; a confirmation dialog only when work would start without approval.
- States: badge beside the status: "Estimate required", "Approved up to 150,00 $", "Over the approved 100,00 $", "Estimate approved", "Estimate refused" (symbol + words + color).
Built: `Approval.swift` (rule, state, `approvalState(of:)`; the newest decided estimate counts; with an amount, an approved estimate covers work up to its own subtotal). Migration v8-approval. The intake slip prints the rule above the signature. Snapshots: repair-approval, doc-intake-slip.
Status: done

### S-035 Internal jobs on shop devices
As the user, I repair a device the shop owns (to resell or to keep) without a customer: its repairs are internal.
Screens: new-repair-sheet, repair-internal, devices-shop
Depends: S-021
Acceptance:
- [unit] The shop is one owner record (`customer.isShop`), named after the business, made the first time it is needed. Its devices record what I paid for them (`purchaseCents`).
- [snap] New Repair offers "Shop (internal)" as the owner. An internal repair shows an "Internal" badge, has no intake slip, estimate, or invoice, and its Billing shows cost: parts at cost and hours spent, no taxes.
- [unit] Internal repairs never count as To Collect, and their last status reads "Done" instead of "Picked Up".
Built: `Shop.swift` (`shop(named:)`, `isInternal`, `internalCost`); migration v9-shop. New Repair has "For the Shop" beside the customer picker and no approval section for the shop. An internal repair shows Owner "The shop", the Internal badge, and a Cost section (Log Time, Time spent, Parts at cost, a warning for parts with no cost) in place of Billing and Documents; Print Intake Slip, Print Estimate, and Invoice are disabled for it, and `issue` refuses it. The shop is left out of Customers and search. Snapshot: repair-internal.
Status: done

### S-036 Sell or keep a shop device
As the user, I mark a shop device Kept, For Sale, or Sold (with the price, the date, and an optional buyer), and I see what it cost and what it made.
Screens: devices-shop
Depends: S-035
Acceptance:
- [unit] Cost = purchase + parts at cost on its internal repairs. Profit = sale price − cost. Selling to a customer moves the device to that customer, and later repairs are theirs.
- [snap] The Devices page has a Shop filter showing each device's state, cost, and sale price or profit.
- Later: a sales invoice with taxes for a sold device.
Built: `shopDevices()` and `setDisposition` in `Shop.swift`; `ShopViews.swift`. Devices has an All Devices / Shop picker; the Shop list shows state, cost, asking price or profit, and "Profit on N sold" at the bottom; a shop device's page has a Shop section (Paid, State, Asking or Sold for, Buyer, Cost, Profit). Only work done before the sale counts in the cost; a profit shows only once sold. Snapshot: devices-shop.
Status: done

### S-033 Delete and undo
As the user, I delete a customer, device, repair, part, or guide, and ⌘Z brings it back. Deleting a customer that has open repairs asks first.
Depends: S-001
Acceptance:
- [unit] Deletion is soft, and "Empty trash" in Settings removes rows older than 30 days along with their files.
- [self] ⌘Z after a delete restores the row and its children.
Built: `Trash.swift`. Moving to the Trash stamps the item, its devices and repairs, and the notes and files on each with one time; Undo puts back exactly the rows with that time. A repair with an issued invoice cannot go to the Trash (invoices are tax records), nor can the shop. Edit > Move to Trash (⌘⌫; in a text field ⌘⌫ still deletes to the start of the line), Delete in a list, and the rows' context menus. A customer with open repairs asks "Move “Name” to the Trash?". Settings → Backup → Trash shows what is over 30 days old and Empty Trash… deletes it for good with its files. Snapshot: settings-backup.
Status: done

---

## M7 Money and taxes — any province or state, credit notes, tax report

### S-037 Taxes for my country and province or state
As the user, in Settings → Business I pick Canada or the United States and my province or state. Its taxes fill in at the standard rates, each with its own registration number, and I can change any rate.
Screens: settings-business
Depends: S-021
Acceptance:
- [unit] Canada: QC GST 5 % + QST 9.975 %; ON HST 13 %; NB, NL, PE HST 15 %; NS HST 14 %; BC GST + PST 7 %; MB GST + RST 7 %; SK GST + PST 6 %; AB, NT, NU, YT GST only.
- [unit] United States: one sales tax at the state's base rate plus a local rate I enter; AK, DE, MT, NH, OR have no state sales tax. A "Tax labour" switch, because states differ on repair labour.
- [unit] A profile saved before this story opens as Québec with its GST and QST rates and numbers.
- [snap] Settings → Business → Taxes: Country, Province or State, one row per tax (rate and number), Local rate and Tax labour in the US, and Use Standard Rates.
Built: `Taxes.swift` (`Country`, `TaxKind`, `TaxRate`, `TaxRegion` with 13 provinces and territories and 51 states and DC; `setRegion`, `useStandardTaxes`, `chargedTaxes`). The profile has `country`, `region`, `taxes`, `localRate`, `taxesLabour`; an old profile decodes as Québec with its numbers. `Views/TaxSection.swift`. Snapshot: settings-business.
Status: done

### S-038 Bills and documents use my region's taxes
As the user, the repair's Billing and every estimate and invoice show my region's taxes by their own names.
Screens: repair-billing, doc-invoice
Depends: S-037
Acceptance:
- [unit] Totals have one line per tax, each a share of the taxable amount rounded half up to the cent. With Tax labour off, labour is left out of the taxable amount.
- [unit] An invoice issued before this story still prints its TPS and TVQ as issued.
- [snap] Taxes print by name in the document's language: TPS, TVQ, TVH, TVP, TVD in French; GST, QST, HST, PST, RST, Sales tax in English, with each registration number.
Built: `Totals.taxes` (one `TaxLine` per tax) and `taxableCents`; old documents decode their TPS and TVQ. Documents name each tax with `TaxKind.name(language)`, print every registration number, and add "Taxable amount (parts)" when labour is not taxed. Snapshots: repair-billing, doc-invoice, doc-invoice-us.
Status: done

### S-039 Currency follows the country
As the user in the United States, amounts show and print in US dollars.
Screens: repair-billing, doc-invoice
Depends: S-037
Acceptance:
- [unit] A document keeps the currency it was issued in: CAD in Canada, USD in the US ("$1,234.56").
- [self] Switching the country to the United States changes the money shown in the app.
- [unit] A new customer's document language starts as French in Québec and English elsewhere.
Built: `DocumentHTML.country` comes from the business details a document froze, so it keeps its currency; en_US for a US business. In the app, `Money.currencyCode` and `CustomerDraft.defaultLanguage` follow the profile on every reload. Snapshot: doc-invoice-us.
Status: done

### S-040 Credit note for an invoice
As the user, I cancel or correct an issued invoice with a credit note; the invoice keeps its number and the repair can be billed again.
Screens: repair-billing, doc-credit-note
Depends: S-038
Acceptance:
- [unit] A credit note has its own sequence (NC-0001), refers to its invoice, and reverses its lines and each tax. An invoice is credited at most once.
- [unit] A credited invoice no longer counts as paid for To Collect; a new invoice gets the next invoice number.
- [snap] « Note de crédit » / "Credit Note" prints "Credits invoice F-0003" with negative amounts.
Built: `issueCreditNote(for:reason:)` and `creditNote(of:)` in `Billing.swift`; `DocumentKind.creditNote`, migration v10-credit-notes (`creditNumber`, `creditsInvoiceId`, both unique). The credit note copies the invoice's frozen content with every amount and tax negated, so it reverses exactly what was charged. The invoice row's payment menu has Issue Credit Note… (an alert with an optional reason); the rows read "credited by NC-0001" and "credits F-0002". Snapshot: doc-credit-note.
Status: done

### S-041 Record a refund
As the user, I record that I paid a credit note back, with the method and date.
Screens: repair-billing
Depends: S-040
Acceptance:
- [unit] A refund records method and date on the credit note; the reprinted PDF reads REMBOURSÉ / REFUNDED.
- [snap] The credit note row shows Refunded with its method.
Built with S-040: a refund is the credit note's payment (`setPaid` on it); the row has a Refund menu ("Refunded · Cash", "Not Refunded"), and the PDF reprints with REMBOURSÉ / REFUNDED. Snapshot: doc-credit-note (seeded as refunded).
Status: done

### S-042 Sales and tax report
As the user, I see what I invoiced and the tax I collected for a month, a quarter, or a year, so I can file my returns.
Screens: reports
Depends: S-040
Acceptance:
- [unit] For a period: invoices and credit notes by issue date; sales before taxes, each tax collected, and totals, with credit notes subtracted; amounts paid and still owed.
- [snap] A Reports page in the sidebar: period picker, totals per tax, and the list of documents.
- [self] Export CSV writes one row per document with each tax in its own column.
Built: `Report.swift` (`ReportPeriod` for calendar months, quarters, and years; `SalesReport` with sales before taxes, each tax, total, collected, owed, and `csv()`). `Pages/ReportsPage.swift`: a Reports sidebar page with Month / Quarter / Year, previous and next, the figures, a table of documents (double-click opens the repair or device), and Export CSV…. Credit notes count in the period they were issued. Snapshots: reports, reports-quarter.
Status: done

### S-043 Sales invoice for a shop device
As the user, when I sell a shop device I issue an invoice to the buyer with my region's taxes.
Screens: devices-shop, doc-invoice
Depends: S-036, S-038
Acceptance:
- [unit] The invoice takes the next invoice number, one line for the device at its sale price, and the taxes; it counts in the sales report.
- [snap] The Shop section of a sold device has Invoice Sale, then the invoice with Open and Mark Paid.
Built: `issueSaleInvoice(for:)` and `saleInvoices(of:)`; migration v11-sales rebuilds `invoice` so `repairId` is optional and adds `deviceId` (a CHECK keeps one of them). One `item` line at the sale price, the region's taxes, the shared invoice sequence, no ticket and no repair warranty; the PDF goes on the device. Once per sale unless credited. Snapshots: devices-shop-sold, doc-sale-invoice.
Status: done

## M8 Inventory — stock history, restocking, counter sales, stock value

### S-044 Stock history and counts
As the user, I see why a part's stock changed, and I correct it after counting the shelf.
Screens: part-history
Depends: S-014
Acceptance:
- [unit] Every stock change is a move with its reason: opening, installed (with the repair), returned, received, counted, damaged, sold, adjusted. The sum of a part's moves is its quantity; parts already in stock get an opening move.
- [unit] Count sets the quantity to what I counted and records the difference; Damaged takes stock out with a note.
- [snap] A part's page has a Stock History list, newest first, with the ticket or invoice each move came from, and Count… and Remove Damaged… actions.
Built: `Stock.swift` (`StockMove`, `StockReason`, `moveStock` that never goes below zero and records the units that actually moved, `count`, `removeDamaged`, `stockHistory`). Migration v12-stock adds `stockMove` and an opening move for every part in stock. Saving a part, the stepper, and installing or removing a part on a repair all record moves. `Views/StockViews.swift`: the part's Stock section with Count… and Remove Damaged… popovers, and Stock History (eight newest, Show All). Snapshot: parts-inventory.
Status: done

### S-045 Restock orders
As the user, I order stock for the shelf from a vendor and receive it when it arrives.
Screens: parts-restock
Depends: S-044
Acceptance:
- [unit] Order More adds the part to the vendor's draft order; Add Low Parts fills drafts with every low part (enough to reach twice its threshold).
- [unit] Mark Ordered, then Receive: each line's quantity goes into stock as a Received move, and the part's cost becomes the line's cost.
- [snap] Parts has a Restock tab: one order per vendor with its lines, quantity and cost editable while a draft, and its total at cost.
Built: `Restock.swift` (`Restock`, `RestockLine`, `RestockOrder`; `orderMore`, `addLowParts`, `updateRestockLine`, `markOrdered`, `receive`, `discardRestock`, `restockOrders`, `unitsOnOrder`). Migration v13-restock. `Views/RestockViews.swift`: Parts > Restock, one section per order (drafts, then ordered, then the last ten received), with Add Low Parts in the toolbar. A part's page has Order More and its units on order. Snapshot: parts-restock.
Status: done

### S-046 Counter sales
As the user, I sell parts and accessories over the counter, without a repair, to a customer or a walk-in.
Screens: counter-sale-sheet, doc-counter-sale
Depends: S-044, S-038
Acceptance:
- [unit] A counter sale is an invoice with the next number, its lines, and the region's taxes; stocked parts leave stock as Sold moves. Crediting it puts them back as Returned.
- [snap] File > New Counter Sale… (⌥⌘N) opens a sheet: customer or Walk-in, parts from stock or typed items, quantity and price, the totals, and Invoice.
- [snap] A customer's page lists their counter-sale invoices; a walk-in's PDF goes on the shop.
Built: `CounterSale.swift` (`CounterSaleItem`, `counterSaleTotals`, `issueCounterSale(to:items:)`, `counterSales(of:)`; crediting returns Sold parts as Returned). Migration v14-counter-sales rebuilds `invoice` with `customerId` (the shop for a walk-in). Documents print "Walk-in customer" and skip the device block when there is none. `Sheets/CounterSaleSheet.swift` from File > New Counter Sale… (⌥⌘N) or a customer's Counter Sales section; Reports shows "Walk-in" and opens the customer. Snapshots: counter-sale-sheet, customer-counter-sales, doc-counter-sale.
Status: done

### S-047 Inventory value
As the user, I know what my stock is worth, now and at the end of a period, for my year-end.
Screens: parts, reports
Depends: S-044
Acceptance:
- [unit] Value = quantity × cost for each part, plus the cost of shop devices in stock or for sale; at a past date, quantities come from the stock moves.
- [snap] The Parts list shows the stock value at cost and at price; Reports shows the inventory value at the end of the period, and how many parts have no cost.
Built: `Inventory.swift` (`InventoryValue`, `inventoryValue(at:)`: parts at cost and at price, shop devices in stock or for sale at their cost; at a past date, quantities from the last stock move before it and devices held then; costs are today's). Parts > Inventory has a Stock Value footer; Reports shows the inventory at the end of the period (today for the current one) with parts without cost. Snapshots: parts-inventory, reports.
Status: done

### S-048 Release 1.0.0
As the user, I install BenchLog 1.0.0 from a notarized download, and it updates itself.
Depends: S-044, S-045, S-046, S-047
Acceptance:
- [manual] `tools/release.sh 1.0.0 --check` passes; release notes in French and English; the published release waits for the owner's go-ahead.
Built: `release-notes/1.0.0.md` (English and French). `tools/release.sh 1.0.0 --check` passes; the script sets 1.0.0 in `Info.plist.in` when it publishes. Published 2026-11-09: https://github.com/matguitarist/BenchLog/releases/tag/v1.0.0
Status: done

## M9 Sync — one library on the shop server, shared by every device

The server runs on the shop network (Docker on a NAS or a Mac, Tailscale from away) and
stores rows it does not need to understand: any table in `docs/SCHEMA.md`, keyed by table
and id, last writer wins by `updatedAt`. The Mac keeps its own full copy and works offline.

### S-049 Sync server
As the user, I run one small BenchLog server on my shop network that holds the shared library.
Screens: none (server)
Acceptance:
- [unit] `server/` is a zero-dependency Node service on `node:sqlite`. Push takes rows (table, id, updatedAt, deletedAt, data) and keeps the newer by `updatedAt`; pull returns every row changed after a cursor, in order, in pages.
- [unit] Every request needs the library token (`Authorization: Bearer`); the token is made on first start, saved in the data folder, and printed once.
- [unit] Files: an attachment's bytes are uploaded and downloaded by attachment id, checked by SHA-256.
- [manual] `docker build` and `docker run` with a data volume; README says how to reach it with Tailscale.
Built: `server/` (`src/store.js` rows, sequences, files; `src/server.js` the API; `src/main.js`; `Dockerfile` on node:24-alpine; README with Docker, plain Node, Tailscale, backups). 10 tests under `node --test`, in CI. The sequences (S-050's server side) are in too. `docker build` not yet tried: Docker was not running on this Mac.
Status: done

### S-050 Numbers from the server
As the user, I never get two repairs with the same ticket number, or a gap or a duplicate in my invoice numbers, when two devices work at once.
Depends: S-049
Acceptance:
- [unit] The server hands out the next ticket, invoice, and credit note number; the first Mac to connect sets where each sequence starts.
- [unit] A client may reserve a block of ticket numbers so check-in works offline; invoice and credit numbers always come from the server, one at a time.
Built: in S-049's server (`take`, `startAt`, blocks for tickets only); `SyncEngine.connect` starts each sequence after the library's own numbers. The Mac uses them in S-053.
Status: done

### S-051 Connect the Mac to the server
As the user, I connect BenchLog to my server once, and my library uploads.
Screens: settings-sync
Depends: S-049, S-050
Acceptance:
- [snap] Settings > Sync: server address and token, Test Connection, and Connect. A connected library shows the server, the last sync, and Disconnect.
- [unit] Connecting an empty server uploads every row and file; the server's numbers start after the library's.
- [unit] Connecting to a server that already holds a library asks first, then replaces this Mac's library with the server's (the old one is kept as a backup).
Built: `SyncEngine.connect(join:)` (claims an empty server, starts its sequences, queues everything; joins another library after `clearForJoin`). `SyncController` (app) keeps the server in the library's meta and the token in the Keychain. `Views/SyncViews.swift`: Settings > Sync with Test Connection, Connect, the Replace This Mac's Library confirmation (after a backup named "BenchLog Before Joining …"), and the connected view. Snapshots: settings-sync, settings-sync-connected.
Status: done

### S-052 Changes sync both ways
As the user, what I change on one device shows on the others within a minute, and I can keep working when the server is away.
Screens: sync-status
Depends: S-051
Acceptance:
- [unit] Every local change is queued (triggers record table and id) and pushed; pulled rows apply when newer and are never queued again; a row changed on both sides keeps the later `updatedAt`.
- [unit] Files upload after their row and download when a pulled attachment has no file yet.
- [snap] The sidebar shows the sync state: Synced (with the time), Syncing, Offline (with what is waiting), or the error, with Sync Now.
- [self] Sync runs at launch, a few seconds after each change, and every minute.
Built: migration v15-sync (`syncQueue` with versions, `syncFlag`, triggers on every synced table, fits and links touching their part or guide, `meta.business` with `updatedAt`). `Sync.swift` exports rows (parts carry `_fits`, guides `_links`) and applies pulled ones in one transaction with deferred foreign keys; devices, fits, and links refill the catalog. `SyncEngine.sync()` uploads files before their rows, pushes the queue, pulls every page, and downloads missing files. The sidebar footer shows the state with Sync Now. SyncTests (in-memory server) and ServerTests (the real `server/` under Node). Snapshot: sync-status.
Status: done

### S-053 Invoices and tickets use the server's numbers
As the user, the invoice and ticket numbers I issue come from the server when I am connected.
Depends: S-050, S-052
Acceptance:
- [unit] A connected library issues invoices and credit notes with a number from the server; offline, issuing says to reconnect, and nothing is numbered.
- [unit] A connected library opens repairs with ticket numbers from its reserved block, and tops the block up when it syncs.
Built: `Numbering.swift` (`NumberingError`, ticket blocks of 20 kept in `meta.ticketBlocks`, topped up below 10 at each sync). `nextNumber(_:_:given:)` refuses to number locally when connected; every issue function takes `number:`. The app asks `SyncController.number` before issuing and gives the number back (`/v1/numbers/:name/return`) when issuing fails. NumberingTests.
Status: done

### S-054 Passcodes stay private on the server
As the user, device passcodes never reach the server in clear text.
Depends: S-052
Acceptance:
- [unit] Passcodes are sealed with the library key (AES-GCM) before they are pushed, and opened when pulled; the server stores only sealed text.
- [snap] Settings > Sync shows the library key as a recovery code to copy, needed to join another device.
Built: `LibraryKey.swift` (256-bit key, AES-GCM `sealed:v1:` text, a 52-character recovery code in groups of four without I, O, 0, 1). The engine seals device passcodes on push and opens them on pull; the first upload pushes `meta/keyCheck`, so joining with a wrong key fails before anything is replaced. The app keeps token and key in the Keychain under the library id; Disconnect keeps the key. Settings > Sync shows the key with Copy, and joining asks for it. LibraryKeyTests. Snapshot: settings-sync-connected.
Status: done

### S-055 Release 2.0.0
As the user, I install BenchLog 2.0 and its server, and both devices share one library.
Depends: S-049, S-050, S-051, S-052, S-053, S-054
Acceptance:
- [manual] `tools/release.sh 2.0.0 --check` passes; release notes in French and English explain the server; the published release waits for the owner's go-ahead.
Status: done
Built: published by tools/release.sh 2.0.0 on 2026-11-09 after the owner's go-ahead; https://github.com/matguitarist/BenchLog/releases/tag/v2.0.0, feed offers 2.0.0.

## M10 Help — find Settings and learn the app

### S-056 Settings from the sidebar
As the user, I open Settings from a button at the bottom of the sidebar, without knowing ⌘,.
Acceptance:
- [snap] A gear button sits at the bottom left of the sidebar, always; when the library is connected, the sync status and Sync Now sit beside it.
- [manual] The button opens the Settings window.
UX:
- Flow: click the gear (or ⌘,) -> Settings opens on the last tab -> close it with ⌘W
- Surface: icon-only button in the sidebar's bottom bar (a place people come back to, like Finder and Mail)
- Words: tooltip "Open Settings (⌘,)"; VoiceOver "Settings"
Built: `Views/SidebarFooter.swift` replaces SyncFooter: the gear (openSettings) always, then, when connected, the cloud with the time since the last sync ("2 min ago", the full "Synced 2 min ago" as its tooltip) and Sync Now. Snapshots: every page (bottom left), sync-status.
Status: done

### S-057 BenchLog Help
As the user, I learn how to do each job in BenchLog from the Help menu, in English or French.
Acceptance:
- [snap] Help > BenchLog Help (⌘?) opens a Help window: topics in a sidebar, the topic beside it, and a search field that narrows the topics.
- [snap] Topics: Getting Started, Repairs, Estimates and Invoices, Counter Sales, Parts and Inventory, Shop Devices, Guides, Reports, Backups and Trash, Sync and the Shop Server, Keyboard Shortcuts.
- [self] The Help menu has BenchLog Help, Keyboard Shortcuts, Set Up the Shop Server (each opens its topic), What's New in BenchLog (this version's release page), and Report a Problem (a new GitHub issue with the version filled in).
- [manual] The topics read in French when the Mac is in French.
UX:
- Flow: Help menu or ⌘? -> Help window on the topic -> pick another topic or search -> ⌘W closes it
- Surface: a window (people keep it open beside the main window)
- States: a search with no match shows the system's "No Results for “…”"
- Words: "BenchLog Help", "Keyboard Shortcuts", "Set Up the Shop Server", "What's New in BenchLog", "Report a Problem"
Built: `Help/HelpWindow.swift` (HelpTopic, HelpCenter, HelpWindow, HelpCommands, HelpLinks) and eleven topics as Markdown in `Help/en` and `Help/fr`, package resources read through Bundle.module and rendered like a Markdown guide; `[[topic|…]]` links open another topic. The Help menu replaces the system's (Load Sample Data stays there in debug builds). Self-test: every topic in both languages, the menu, the issue link's version. Snapshots: help-getting-started, help-sync.
Status: done

## M11 Built-in server — this Mac can be the shop server

### S-058 A server built into BenchLog
As the owner, BenchLog carries its own server, so a Mac can hold the shop's library without Docker or Node.
Acceptance:
- [unit] A Swift server (`BenchLogServerKit`) answers the same API as `server/` (health, library, push, pull, numbers, files) with the same rules: last writer wins, numbers without gaps, files checked by SHA-256, the token on every route but health.
- [unit] The sync tests run against both servers: two libraries share one server, a wrong token is refused.
- [unit] Its data folder is the same as the Node server's (library.sqlite, files/, token), so either can open it.
- [manual] `BenchLogServer` inside the app runs it from Terminal with PORT, DATA_DIR, and BENCHLOG_TOKEN, like `npm start`.
Built: `Sources/BenchLogServerKit`: `ServerStore` (GRDB, the same tables as store.js), `HTTPServer` (Network.framework, one request per connection, bodies over 4 MB spooled to a file, files streamed back), `BenchLogServer` (the routes, the token check on SHA-256 digests, the token file). `Sources/BenchLogServer/main.swift` is the helper, built into Contents/MacOS with its login item plist (`LaunchAgents/`). BuiltInServerTests port the Node tests; ServerTests run the engine against both servers. Checked by hand: Node and the helper open each other's data folder (rows, files, numbers).
Status: done

### S-059 Use this Mac as the server
As the owner, I turn this Mac into the shop server from Settings > Sync, and the other Macs connect to it.
Depends: S-058
Acceptance:
- [snap] Settings > Sync, not connected: a "This Mac as the Server" section with "Use This Mac as the Server".
- [self] The button starts the server, connects this library to it, and shows what other Macs enter: the address and the token, each with Copy.
- [manual] The server runs as a login item: after a restart, with BenchLog closed, the other Macs still sync. macOS may ask to allow it in System Settings > General > Login Items; Settings says so with a button that opens it.
- [manual] While it serves, the Mac does not go to sleep on its own.
- [snap] "Stop Using This Mac as the Server…" asks first and says the server's data stays.
UX:
- Flow: Settings > Sync -> Use This Mac as the Server -> (allow in Login Items if asked) -> connected; the address and token for other Macs show with Copy
- Surface: a section in Settings > Sync (changes how this library syncs; Settings is where the server is chosen)
- States: starting "Starting the server…"; needs approval "Allow BenchLog in System Settings > General > Login Items, then try again." with "Open Login Items"; failed: the reason under the button
- Words: "This Mac as the Server", "Use This Mac as the Server", "Other Macs connect with", "Stop Using This Mac as the Server…", confirmation "Stop the Server on This Mac?" with "Stop Server" and "Cancel"
Built: `ServerHost.swift`: SMAppService.agent registers `LaunchAgents/com.mathieuares.benchlog.server.plist` (BenchLogServer --agent: logs to server.log, holds PreventUserIdleSystemSleep), waits for /v1/health, reads the token file, and connects the library to 127.0.0.1:8420; it refuses when another server already answers on 8420. In test runs the same server runs in-process on a free port, in a folder beside the test library. `Views/ServerHostViews.swift`: the offer, Login Items approval, the address and token with Copy, Stop with its question. Help's Sync topic explains it. Self-test: start, connect, address and token, the library on the server, Stop. Snapshots: settings-sync, settings-sync-server, settings-sync-server-stop. Checked by hand: agent mode (log, sleep assertion). Not yet tried: a real login item across a restart.
Status: done

### S-060 Release 2.2.0
Depends: S-059
Acceptance:
- [manual] `tools/release.sh 2.2.0 --check` passes; release notes in French and English; the published release waits for the owner's go-ahead.
Status: todo

## M12 Parts — what a part is, starter parts, a wider page

### S-061 Kind, condition, location, and notes on a part
As the user, I say what a part is, the state it is sold in, where it sits, and I keep notes on it.
Depends: S-013
Acceptance:
- [unit] A part has a kind (Part, Accessory, Cable, Controller, Supply), an optional condition (New, Used, Refurbished), a location, and notes; a part from before is a Part with the rest empty.
- [unit] Search in Parts also matches the location; the inventory filters by kind.
- [unit] A part lists the repairs it is on, newest first.
- [snap] New Part and Edit Part have Kind, Condition, Location, and Notes. A part's page shows them, and Prices shows Cost, Price, Margin (with its share of the price), and Stock value.
Built: `Part.swift` (`PartKind`, `PartCondition`, `marginCents`, `parts(matching:lowOnly:kind:)`, `repairs(usingPart:)`). Migration v16-part-details adds four columns to `part`; they sync as they are (the servers store rows as JSON). `PartSheet`, `PartsPage` (kind icon and price in each row, a Kind filter in the toolbar). File > New Part… (⌃⌘N). Self-test: kind, condition, margin, search by location. Snapshots: parts-inventory, part-edit-sheet.
Status: done

### S-062 Starter parts for a console
As the user, I add the usual parts, accessories, cables, and controllers of a console in one step, then count what I have.
Depends: S-061
Acceptance:
- [unit] Sets for the Sony PS1, Sony PS2, and Microsoft Xbox. Adding a set adds its parts at zero stock with a kind, a suggested price, and the models they fit; a part whose name is already in the inventory is left as it is, so adding twice adds nothing.
- [self] File > Add Starter Parts has one item per console and All Consoles; the empty Parts page offers the same menu beside New Part.
Built: `StarterParts.swift` (`StarterSet`, `StarterPart`, `addStarterParts`, `missingStarterParts`): 58 parts; the PlayStation cables fit both the PS1 and the PS2. Prices are suggestions in CAD, no cost. `StarterPartsButtons` in the File menu and the empty state. The sample data adds every set.
Status: done

### S-063 A part's page uses a wide window
As the user, in full screen a part's page fills the space instead of one narrow column.
Depends: S-061
Acceptance:
- [snap] From 880 pt wide, the page has two columns that start level: Details, Prices, Stock, and Fits; beside them On Repairs, Stock History, and Notes. Narrower, it is one column in that order.
- [snap] The inventory list is wide enough to read a starter part's whole name.
Built: `PartDetail` measures its width (`onGeometryChange`) and lays out one or two grouped forms. Snapshots: parts-inventory (wide), parts-inventory with APP_SNAPSHOT_MIN=1 (one column).
Status: done

### S-064 Add by Barcode
As the user, I scan the barcode on a game or accessory box and it goes into the inventory.
Depends: S-061
Acceptance:
- [unit] A part has a barcode: a UPC or EAN, digits only, refused when its check digit is wrong; a 12-digit UPC and its 13-digit EAN find the same part. Search in Parts matches it.
- [unit] A lookup answer from the barcode service becomes a product (title, brand, category) with a guessed kind; Game is a kind.
- [self] Add by Barcode (File menu ⇧⌘B, Parts toolbar): a barcode the inventory knows adds one to its stock, recorded as Received; a new one is looked up and becomes a part with one in stock; one the service does not know asks for a name; a wrong code is refused.
- [snap] The sheet lists what was added, newest first, each with Edit….
- [manual] A USB or Bluetooth scanner (it types the digits and Return) adds box after box without touching the keyboard; a real lookup at upcitemdb.com answers.
UX:
- Flow: Parts -> Add by Barcode -> scan, scan, scan -> Edit… on a new part for its cost and price -> Done
- Surface: a sheet (a short task that keeps the field focused for the scanner)
- States: looking up (a spinner); "That is not a barcode. Check the digits."; "No product found for …" with Name, Skip, Add Part; the service's daily limit or no network: the same, with why
- Words: "Add by Barcode", "Barcode", "Added", "Skip", "Add Part", "Done"
Built: `BarcodeLookup.swift` (`normalized`, `request`, `parse`, `find` at UPCitemdb's free endpoint: no account, 100 lookups a day, only the barcode leaves the Mac; `ProductInfo.suggestedKind`). Migration v17-part-barcode. `Library.part(barcode:)`, `receiveScanned`. `Sheets/BarcodeSheet.swift`, `AppModel.addScanned` (the lookup is `productLookup`, replaced in the self-test so it never uses the network). Edit Part has Barcode. Checked by hand with curl: the service answers for a Switch game. Not yet tried: a hardware scanner. Not built: scanning with a camera.
Status: done

### S-065 Customers and Devices use a wide window; the smallest window hides nothing
As the user, every detail page fills a wide window, and at its smallest the window still shows the whole sidebar.
Depends: S-063
Acceptance:
- [snap] From 880 pt wide, a customer's and a device's page have two columns that start level: details and lists, beside Photos and Files and Notes.
- [snap] At its smallest (944 pt wide) the window shows the sidebar, the list, and the detail whole on every page.
Built: `UI/TwoColumnForm.swift`, used by PartDetail, CustomerDetail, and DeviceDetail. The window's minimum width goes from 820 to 944 (sidebar 180 + list + detail at their minimums). Snapshots: `APP_SNAPSHOT_SIZE=1600x1000` for the wide pages, `APP_SNAPSHOT_MIN=1` for the smallest.
Status: done

### S-066 Review a scanned product before it is added
As the user, I see what the barcode lookup found and correct it before it goes into the inventory.
Depends: S-064
Acceptance:
- [self] A new barcode the lookup finds adds nothing by itself: it comes back for review. Add Part makes the part as reviewed (name, kind, cost, price) with one in stock; scanning it again adds one to stock without a review.
- [snap] The review shows the barcode, Name and Kind filled from the lookup, Cost, Price, Skip, and Add Part.
- [manual] Return in the review adds the part and puts the cursor back in Barcode for the next scan.
UX:
- Flow: scan -> review (Name, Kind, Cost, Price) -> Return or Add Part -> scan the next box
- Surface: a section of the Add by Barcode sheet, the same one an unknown barcode uses with an empty name
- States: Barcode is off while a review waits, so a scan cannot throw it away; Add Part is off without a name
- Words: "Review the new part for …", "Add Part", "Skip"
Built: `ScanResult.found`, `AppModel.addReviewed`; `addScanned` no longer saves a new part. Snapshot `part-barcode-review-sheet`.
Status: done

## M13 Dashboard — the day at a glance

### S-067 Dashboard
As the user, I open BenchLog on a Dashboard that shows what is going on, and click anything on it to get there.
Acceptance:
- [unit] The dashboard counts open repairs per status and lists the ones that need attention, one reason each, in this order: Overdue (promised date passed, not Ready), Promised Today, To Collect, Awaiting Approval, over 14 days on the bench. Closed repairs never show. It counts Low Stock, To Order, and Incoming, and holds the month's sales.
- [unit] A paid counter sale does not hide To Collect (it did: the invoice has no repair).
- [self] A repair past its promised date is Overdue; once Ready it is To Collect. A tile opens its list, Back returns to the Dashboard, a Parts row opens its tab.
- [snap] Dashboard is the first sidebar page and the one the app opens on: four tiles (Open Repairs, Ready, To Collect, Overdue), Needs Attention beside By Status, Parts, and the month.
UX:
- Flow: open the app -> Dashboard -> click a repair, a tile, a Parts row, or Show Reports -> Go > Back
- Surface: a sidebar page (⌥⌘1)
- States: an empty library: "Nothing on the Bench" with New Repair; nothing to flag: "Nothing needs attention"; more than 12: "N more in Repairs"
- Words: "Dashboard", "Needs Attention", "Overdue", "Promised Today", "By Status"
Built: `BenchLogKit/Dashboard.swift` (`Library.dashboard(now:)`), `Pages/DashboardPage.swift`, `AppModel.show(_:repairs:parts:)`. `toCollectRepairIDs` skips invoices with no repair. Not built: a To Collect or Overdue filter in Repairs (those tiles open Ready and Open).
Status: done

### S-068 A repair's page uses a wide window
As the user, a repair fills a wide window instead of one narrow column.
Depends: S-065
Acceptance:
- [snap] From 820 pt wide, a repair has two columns that start level: Details, Complaint, Diagnosis, Parts, and Billing or Cost and Documents; beside them Photos and Files, Guides, Dates, and Timeline. Narrower, it is one column in the order it had.
Built: `RepairDetail` uses `TwoColumnForm`, whose `side` now also learns whether the page is wide. Two columns start at 820 pt, not 880, on every detail page: at 1600 pt the repair pane is 860 pt.
Status: done

### S-069 Counter Sales page
As the user, I see every counter sale in one place, just under the Dashboard, and start a new one from there.
Depends: S-046, S-067
Acceptance:
- [unit] The list holds every counter sale, to customers and walk-ins, newest first, each with its lines, totals, and the credit note that cancels it; search matches the customer, an item, or the invoice number.
- [self] The page lists a walk-in sale; a sale made from the page is the one selected.
- [snap] Counter Sales is the second sidebar page (⌥⌘2): the list (number, buyer, items, date, total, Paid or Unpaid) beside the sale (customer, date, items, totals, and its invoice with payment, PDF, and credit note).
UX:
- Flow: sidebar > Counter Sales (⌥⌘2) -> New Counter Sale (toolbar, ⌥⌘N) -> Invoice -> the sale is selected; a row in Reports opens its sale; Go > Back
- Surface: a sidebar page (a place people come back to)
- States: none yet: "No Counter Sales" with New Counter Sale; nothing selected: "No Counter Sale Selected"; no match: the system's search empty state
- Words: "Counter Sales", "New Counter Sale", "Walk-in", "Open Counter Sale"
Built: `Library.counterSaleRows(matching:)` (`CounterSaleRow`), `Pages/CounterSalesPage.swift`, `SidebarItem.counterSales`, `Destination.counterSale`. A customer's page keeps its own Counter Sales section. In Reports, a counter sale's row opens the sale (it opened the customer, or the PDF for a walk-in). The other pages' shortcuts move down one (Repairs is ⌥⌘3). Snapshots: counterSales, counter-sale.
Status: done

## M14 Boards — a board and its schematic, side by side

### S-070 Open a board beside its schematic
As the user, I double-click a board file on a repair or device and see the board, top or bottom, beside its schematic. A part or net I pick on one side is found on the other.
Depends: S-012
Acceptance:
- [unit] A .brd file, plain or encoded, reads into parts (side, through-hole), pins (numbered, with their net), the outline, and test points; other formats say they can't be read yet.
- [unit] Search lists parts and nets, exact names first; a click finds the pin, else the smallest part, on the side shown; a pin lights its net, a part its pins.
- [unit] A name in the schematic matches only whole ("C713" is not in "C7130"); the schematic picked is the PDF whose name says "sch" or shares the board's number.
- [self] A board opens with the schematic in its folder; a part or net picked in the schematic is selected on the board, which turns over for a bottom net; a BRD2 file says why it can't open.
- [snap] board, board-part: the board on the left (outline, parts, pins, names once they fit) and the schematic on the right with the match bar; with a part selected, its pins in the accent and its first match in the schematic.
UX:
- Flow: a repair or device > Files > double-click a .brd (or right-click > Open Board) -> the Board window; File > Open Board… (⌥⌘O) opens one from the Mac with the PDFs in its folder.
- Surface: a window per board (a reference people keep open beside the repair).
- Board: Top/Bottom (⌘1, ⌘2, Space), Zoom In/Out/to Fit (⌘+, ⌘−, ⌘0); two fingers pan, a pinch or Command-scroll zooms, a drag pans, a double-click zooms to the part, Esc or ⇧⌘A clears the selection.
- Schematic: the selected part or net, "2 of 5", Previous/Next (⇧⌘G, ⌘G); for a pin, a choice of its net or its part; double-click a name in the schematic to select it on the board; Hide Schematic (⌥⌘S); a picker when the record has several PDFs.
- Find: the toolbar's "Part or Net" field (⌘F), with suggestions.
- States: reading: "Reading the board…"; unreadable: "Can't Open Board" with Open in Default App; no PDF: "No Schematic" with where to add it.
- Words: "Board", "Schematic", "Net", "Open Board", "Open in Default App", "Part or Net"
Built: `BoardViewKit` (Foundation only): `BoardFile` (the .brd reader, ported from BoardViewCraft, MIT or Apache-2.0), `Board`, `Schematic`, `BoardSample`. App: `Board/BoardViewer.swift` (`BoardSource`, `BoardWindow`, `BoardCommands`), `Board/BoardCanvas.swift` (an NSView), `Board/SchematicView.swift` (PDFKit). The schematic is a PDF on the same record or, for a repair, on its device. Sample data puts a made-up board on the Switch repair and its schematic on the Switch. `APP_SNAPSHOT_BOARD=<.brd>` snapshots a real board. Checked with an A1502 board (820-4924-A): 3,794 parts and 10,514 pins read in 40 ms, U7100 found in its 82-page schematic.
Status: done

### S-071 Open BRD2 and .bdv boards
As the user, I double-click a BRD2 or .bdv board on a repair or device, or pick one in File > Open Board…, and it opens in the Board window like a .brd.
Depends: S-070
Acceptance:
- [unit] BRD2 reads its outline, nets ("UNCONNECTED" is none), parts (side 1 top, 2 bottom, else through-hole), pins up to the next part's first pin (counted from 0, or from 1), and nails.
- [unit] A .bdv decodes with either key schedule (by byte: a .brd inside; by line, starting "dd:": the part listing in inches); the key wraps from 285 to 159.
- [unit] The sample board as BRD2 and as .bdv reads the same parts, pins, and test points as its .brd; a file of another kind says "BenchLog can't read this kind of board file yet."
- [self] A .brd2 and a .bdv open in the Board window; an unknown file says why.
Built: `BoardFile+BRD2.swift`, `BoardFile+BDV.swift` (ported from BoardViewCraft's brd2.rs and bdv.rs). `BoardFile.read` picks the reader from the bytes, so a .bdv renamed .brd still opens. `BoardSample.brd2Text` and `bdvData`. No real BRD2 or .bdv was at hand: checked against BoardViewCraft's own test shapes only.
Status: done

## Later
- **v2 iPhone/iPad app** on `BenchLogKit`: camera-first intake and photos at the bench.
- **Android app** on the same sync API and `docs/SCHEMA.md`.
- More board formats in the Board window: .fz, .cad (GenCAD), .tvw, … ported from BoardViewCraft one at a time.
- Board notes and readings: a measurement on a pin or net (diode mode, voltage, resistance) saved on the repair.
- French app UI (the String Catalog already holds every string).
- Customer SMS or email "your device is ready".
- Scan a barcode with the Mac's or iPhone's camera (Add by Barcode takes a scanner or typing today).
- Game prices from PriceCharting (a paid API) when adding by barcode.
- Agent CLI/MCP (`benchlog repair list --open`).
- Warranty tracking: open a repair as "warranty of #0042".

## Dropped
- Accounts and login: a single user on their own Mac.
- Multi-technician assignment: a one-person shop.
- Online booking and payments: outside the scope of a bench tool.
- Analytics and onboarding tours: not needed for a personal app.
