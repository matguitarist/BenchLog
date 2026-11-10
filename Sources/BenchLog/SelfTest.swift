import AppKit
import BenchLogKit
import PDFKit

/// Self-test for agents: drives the app model on a library in /tmp,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/BenchLog-self.sqlite ~/Applications/BenchLog.app/Contents/MacOS/BenchLog --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden, Store.url.path.hasPrefix("/tmp/") || Store.url.path.hasPrefix("/private/tmp/") else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp so the test never touches your library")
            finish(code: 1)
            return
        }
        Task {
            check("the library opens", model.library != nil, model.libraryError ?? "")
            if let library = model.library {
                check("the library runs its migrations", (try? library.appliedMigrations())?.isEmpty == false)
                check("a new library starts at ticket #0001", (try? library.metaValue("nextTicketNumber")) == "1")
                check("the files folder exists", FileManager.default.fileExists(atPath: library.filesURL.path))
            }

            model.log.post(.info, "Self-test", source: "SelfTest")
            try? await Task.sleep(for: .milliseconds(300))
            check("the app writes a log line", model.log.entries.contains { $0.message == "Self-test" })
            let file = (try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? ""
            check("the log file has the line", file.contains("Self-test"))

            if let library = model.library {
                // S-002 Add a customer
                let customer = model.save(Customer(name: "Self Test", phone: "(514) 555-0000"), firstNote: "First visit")
                check("a new customer is saved", customer != nil)
                check("phone search matches digits only", (try? library.customers(matching: "5145550000"))?.count == 1)
                check("the first note goes on the customer's timeline",
                      customer.map { id in (try? library.notes(for: .customer, id: id.id))?.map(\.text) == ["First visit"] } ?? false)

                // S-003 Add a device
                let device = customer.flatMap { model.save(Device(customerId: $0.id, category: .handheld, brand: "Nintendo",
                                                                   model: "Game Boy", revision: "Self-Test Edition", passcode: "1234")) }
                check("a device is saved for the customer", device != nil)
                check("a new revision joins the catalog",
                      (try? library.catalogRevisions(.handheld, brand: "Nintendo", model: "Game Boy"))?.contains("Self-Test Edition") == true)

                // S-005 Open a repair
                if let device {
                    let first = model.createRepair(deviceID: device.id, complaint: "No power", promisedAt: nil)
                    let second = model.createRepair(deviceID: device.id, complaint: "No sound", promisedAt: nil)
                    check("ticket numbers go up by one", first.map { $0.ticketNumber + 1 } == second?.ticketNumber)
                    check("a new repair is in Intake", first?.status == .intake)

                    // S-034 Starting work an estimate must approve asks first.
                    if let asked = model.createRepair(deviceID: device.id, complaint: "Estimate first", promisedAt: nil, approval: .ask) {
                        model.setStatus(.inProgress, for: asked.id)
                        check("starting unapproved work asks first", model.pendingStart?.repairID == asked.id
                              && model.read(nil) { try $0.repair(asked.id)?.status } == .intake)
                        model.pendingStart = nil
                        model.setStatus(.awaitingApproval, for: asked.id)
                        check("asking for approval needs no confirmation", model.read(nil) { try $0.repair(asked.id)?.status } == .awaitingApproval)
                        model.setStatus(.inProgress, for: asked.id, force: true)
                        check("Start Anyway starts the work", model.read(nil) { try $0.repair(asked.id)?.status } == .inProgress)
                        model.write("Self-test: move the estimate repair to the trash") { try $0.trash(Repair.self, id: asked.id) }
                    }

                    // S-006 Statuses, with Undo
                    if let first {
                        let undo = UndoManager()
                        undo.groupsByEvent = false
                        model.undoManager = undo
                        undo.beginUndoGrouping()
                        model.setStatus(.ready, for: first.id)
                        undo.endUndoGrouping()
                        let ready = try? library.repair(first.id)
                        check("Ready sets the completed date", ready?.status == .ready && ready?.completedAt != nil)
                        check("a status change writes a status note",
                              (try? library.notes(for: .repair, id: first.id))?.compactMap(\.status) == [.ready])
                        undo.undo()
                        check("Undo puts the old status back", (try? library.repair(first.id))?.status == .intake)
                        model.undoManager = nil

                        // S-008 Notes
                        model.addNote("Cleaned the contacts", to: .repair, id: first.id)
                        check("a note is added to the repair",
                              (try? library.notes(for: .repair, id: first.id))?.contains { $0.text == "Cleaned the contacts" } == true)

                        // S-009 Links and Back
                        model.sidebar = .repairs
                        model.selectedRepair = first.id
                        model.open(.customer(device.customerId))
                        check("a customer link opens the customer", model.sidebar == .customers && model.selectedCustomer == device.customerId)
                        model.goBack()
                        check("Back returns to the repair", model.sidebar == .repairs && model.selectedRepair == first.id)
                        model.goForward()
                        check("Forward goes to the customer again", model.sidebar == .customers)
                    }
                    check("the Repairs badge counts open repairs", model.openRepairCount == 2)
                }

                // S-010 to S-012 Photos and files
                if let device, let repair = model.read(nil, { try $0.repairs(of: device.id).last }) {
                    let source = URL(fileURLWithPath: "/tmp/BenchLog-self-photo.png")
                    try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
                    let board = URL(fileURLWithPath: "/tmp/BenchLog-self-board.brd")
                    try? Data([0]).write(to: board)
                    model.addFiles([source, board], to: .repair, id: repair.id)
                    let added = model.read([]) { try $0.attachments(for: .repair, id: repair.id) }
                    check("dropped files are copied into the library", added.count == 2
                          && added.allSatisfy { FileManager.default.fileExists(atPath: library.fileURL(for: $0).path) })
                    check("the original files stay where they were", FileManager.default.fileExists(atPath: source.path))
                    check("a photo on a repair in Intake is an intake photo", added.first { $0.isImage }?.kind == .intake)
                    check("a .brd file is a boardview", added.contains { $0.isBoardview })
                    if let photo = added.first(where: \.isImage) {
                        let undo = UndoManager()
                        undo.groupsByEvent = false
                        model.undoManager = undo
                        undo.beginUndoGrouping()
                        model.trashAttachment(photo.id)
                        undo.endUndoGrouping()
                        check("Move to Trash hides the photo", model.read(0) { try $0.attachments(for: .repair, id: repair.id).count } == 1)
                        undo.undo()
                        check("Undo brings it back", model.read(0) { try $0.attachments(for: .repair, id: repair.id).count } == 2)
                        model.undoManager = nil
                    }
                }

                // S-013 to S-015 Parts
                if let device, let repair = model.read(nil, { try $0.repairs(of: device.id).last }) {
                    let fan = model.save(Part(name: "Self-test fan", priceCents: 2000, quantity: 1, lowStockThreshold: 1),
                                         fits: [PartFit(category: .handheld, brand: "Nintendo", model: "Game Boy")])
                    check("a new part is saved with its fits", fan.map { id in model.read([]) { try $0.fits(of: id.id) }.count == 1 } ?? false)
                    check("a part at its threshold is low", model.lowStockCount >= 1)
                    check("a fitting part comes first for the device",
                          model.read(false) { try $0.parts(for: device, matching: "").fitting.contains { $0.id == fan?.id } })
                    if let fan {
                        model.usePart(fan.id, on: repair.id)
                        let use = model.read(nil) { try $0.partUses(on: repair.id).first }
                        check("a part in stock starts as Received", use?.status == .received)
                        if let use {
                            model.setStatus(.installed, ofUse: use.id)
                            check("Installed takes the part out of stock", model.read(nil) { try $0.part(fan.id) }?.quantity == 0)
                            model.removeUse(use.id)
                            check("removing an installed part puts it back", model.read(nil) { try $0.part(fan.id) }?.quantity == 1)
                            model.count(fan.id, counted: 3, note: "Self-test count")
                            model.removeDamaged(fan.id, quantity: 1, note: "")
                            let history = model.read([]) { try $0.stockHistory(of: fan.id) }
                            check("Count and Remove Damaged change the stock and show in its history",
                                  model.read(nil) { try $0.part(fan.id) }?.quantity == 2
                                  && history.prefix(2).map(\.move.reason) == [.damaged, .counted]
                                  && history.contains { $0.move.reason == .installed && $0.source != nil })
                            model.orderMore(fan.id)
                            let orders = model.read([]) { try $0.restockOrders() }
                            if let order = orders.first(where: { $0.lines.contains { $0.part.id == fan.id } }) {
                                let before = model.read(nil) { try $0.part(fan.id) }?.quantity ?? 0
                                model.markOrdered(order.id)
                                model.receive(order.id)
                                check("a received restock goes into stock as Received",
                                      model.read(nil) { try $0.part(fan.id) }?.quantity == before + order.units
                                      && model.read([]) { try $0.stockHistory(of: fan.id) }.first?.move.reason == .received)
                            } else {
                                check("Order More makes a restock draft", false)
                            }
                        }
                    }
                    model.useFreePart("Self-test speaker", on: repair.id)
                    check("a typed part starts as Needed and the repair waits on it",
                          model.read(false) { try $0.isWaitingOnParts(repair.id) })
                    check("To Order lists it", model.read(false) { try $0.partUseRows(.needed).contains { $0.use.name == "Self-test speaker" } })
                }

                // S-016 Catalog
                model.renameCatalog(CatalogPath(category: .handheld, brand: "Nintendo", model: "Game Boy", revision: "Self-Test Edition"),
                                    to: "Self-Test Edition 2")
                check("renaming a revision renames it on devices",
                      model.read(false) { try $0.deviceRows(matching: "").contains { $0.device.revision == "Self-Test Edition 2" } })
                check("the catalog outline has every category's brands", model.read(0) { try $0.catalogOutline().count } >= 4)

                // S-017 to S-020 Guides
                let guideFolder = URL(fileURLWithPath: "/tmp/BenchLog-self-guides")
                try? FileManager.default.removeItem(at: guideFolder)
                let nesFolder = guideFolder.appending(path: "Nintendo/Portable Consoles/Game Boy")
                try? FileManager.default.createDirectory(at: nesFolder, withIntermediateDirectories: true)
                try? Data("# Dead Speaker\n![[speaker.png]]".utf8).write(to: nesFolder.appending(path: "dead-speaker.md"))
                try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: guideFolder.appending(path: "speaker.png"))
                try? Data("%PDF-1.4".utf8).write(to: guideFolder.appending(path: "Self manual.pdf"))
                let added = model.addGuides([guideFolder.appending(path: "Self manual.pdf")])
                check("a PDF is added as a guide", added.first?.format == .pdf)
                if let pdf = added.first {
                    model.rememberPage(3, of: pdf.id)
                    check("the last page read is remembered", model.read(nil) { try $0.guide(pdf.id) }?.lastPage == 3)
                    model.sheet = nil
                }
                let candidates = model.read([]) { try GuideScanner(library: $0).scan(guideFolder) }
                let speaker = candidates.first { $0.sourcePath.hasSuffix("dead-speaker.md") }
                check("a folder import guesses Handheld, Nintendo, Game Boy",
                      speaker?.link == GuideLink(category: .handheld, brand: "Nintendo", model: "Game Boy"))
                check("an embedded image is found anywhere in the folder", speaker?.images.map(\.lastPathComponent) == ["speaker.png"])
                model.importGuides(candidates)
                let afterFirst = model.read(0) { try $0.guideRows().count }
                model.importGuides(candidates)
                check("importing the folder again adds nothing", model.read(0) { try $0.guideRows().count } == afterFirst)
                if let device {
                    let matches = model.read([]) { try $0.guides(for: device) }
                    check("the repair's device finds the imported guide", matches.first?.guide.title == "Dead Speaker")
                }

                // S-021 to S-026 Billing and documents
                if let device, let repair = model.read(nil, { try $0.repairs(of: device.id).last }) {
                    model.addLabour(to: repair.id)
                    let labour = model.read([]) { try $0.labourLines(on: repair.id) }
                    check("a labour line starts at the hourly rate", labour.first?.unitCents == BusinessProfile().hourlyRateCents)
                    await model.issue(.invoice, for: repair.id)
                    let invoice = model.read(nil) { try $0.invoices(for: repair.id).first }
                    check("an invoice gets the first number", invoice?.numberText == "F-0001")
                    let pdf = invoice?.fileId.flatMap { id in model.read(nil) { try $0.attachment(id) } }
                    check("the invoice PDF is saved on the repair as a document", pdf?.kind == .document && pdf?.contentType == "com.adobe.pdf")
                    let text = pdf.flatMap { PDFDocument(url: library.fileURL(for: $0)) }?.string ?? ""
                    check("the invoice PDF has the French words", text.contains("Facture") && text.contains("Sous-total") && text.contains("TVQ"))
                    check("the invoice PDF does not print the passcode", !text.contains("1234"))
                    if let invoice {
                        await model.setPaid(invoice.id, method: .debit)
                        let reprint = model.read(nil) { try $0.invoice(invoice.id) }?.fileId.flatMap { id in model.read(nil) { try $0.attachment(id) } }
                        let paidText = reprint.flatMap { PDFDocument(url: library.fileURL(for: $0)) }?.string ?? ""
                        check("a paid invoice reprints with PAYÉ", paidText.contains("PAYÉ"))

                        // S-040, S-041 Credit the invoice, then refund it.
                        await model.issueCreditNote(for: invoice.id, reason: "Self-test")
                        let credit = model.read(nil) { try $0.creditNote(of: invoice.id) }
                        check("a credit note gets the first credit number", credit?.numberText == "NC-0001")
                        @MainActor func text(_ document: Invoice?) -> String {
                            document?.fileId.flatMap { id in model.read(nil) { try $0.attachment(id) } }
                                .flatMap { PDFDocument(url: library.fileURL(for: $0)) }?.string ?? ""
                        }
                        check("the credit note PDF names the invoice it credits", text(credit).contains("Note de crédit") && text(credit).contains("F-0001"))
                        if let credit {
                            await model.setPaid(credit.id, method: .debit)
                            check("a refunded credit note reprints with REMBOURSÉ", text(model.read(nil) { try $0.invoice(credit.id) }).contains("REMBOURSÉ"))
                        }
                    }
                }

                // S-027 Global search: a ticket number and a phone find their records, and a hit opens its page.
                if let row = model.read(nil, { try $0.repairRows().first }) {
                    let hits = model.read([]) { try $0.search("#\(row.repair.ticketNumber)") }
                    check("searching a ticket number finds the repair", hits.contains { $0.kind == .repair && $0.id == row.id })
                    let phone = model.read([]) { try $0.search(row.customer.phone) }
                    check("searching a phone number finds the customer", row.customer.phone.isEmpty || phone.contains { $0.id == row.customer.id })
                    if let hit = hits.first(where: { $0.id == row.id }) {
                        model.searching = true
                        model.open(hit)
                        check("opening a search result shows its page and closes the search",
                              model.sidebar == .repairs && model.selectedRepair == row.id && !model.searching)
                    }
                }

                // S-028 Every Repair menu item is disabled when no repair is selected, and enabled with one.
                let repairToSelect = model.read(nil) { try $0.repairRows().first?.id }
                model.sidebar = .repairs
                model.selectedRepair = nil
                try? await Task.sleep(for: .seconds(0.5))
                let off = repairMenuItems()
                check("the Repair menu exists", !off.isEmpty)
                // A submenu item stays enabled in AppKit; what counts is that nothing inside it is.
                let usable = off.filter { item in
                    if let submenu = item.submenu { submenu.update(); return submenu.items.contains(where: \.isEnabled) }
                    return item.isEnabled
                }
                check("every Repair menu item is disabled with no repair selected", usable.isEmpty,
                      usable.map(\.title).joined(separator: ", "))
                model.selectedRepair = repairToSelect
                try? await Task.sleep(for: .seconds(0.5))
                check("the Repair menu is enabled with a repair selected", repairMenuItems().contains { $0.isEnabled })
                let file = NSApp.mainMenu?.items.first { $0.submenu?.items.contains { $0.title == String(localized: "Add Photo or File…") } == true }
                check("File has Add Photo or File… (⇧⌘P)", file?.submenu?.items.first { $0.title == String(localized: "Add Photo or File…") }?.keyEquivalent == "p")

                // S-029 Spotlight: customers and repairs, no passcodes, and each result leads back.
                let entries = Spotlight.entries(model)
                if let row = model.read(nil, { try $0.repairRows().first }) {
                    let entry = entries.first { $0.id == "repair:\(row.id.stored)" }
                    check("Spotlight has the repair, titled with its ticket", entry?.title.hasPrefix(row.repair.ticket.text) == true)
                    if case .repair(let id)? = entry.flatMap({ Spotlight.destination(for: $0.id) }) {
                        check("a Spotlight repair opens that repair", id == row.id)
                    } else {
                        check("a Spotlight repair opens that repair", false)
                    }
                    let passcode = row.device.passcode
                    check("Spotlight never holds a passcode", passcode.isEmpty || !entries.contains {
                        $0.title.contains(passcode) || $0.detail.contains(passcode) || $0.keywords.contains(passcode)
                    })
                }
                check("tests never write to Spotlight", Store.isOverridden)

                // S-035 An internal job: no documents in the Repair menu, never To Collect.
                // S-036 Selling it records a profit and moves the device to the buyer.
                if let shop = model.shopOwner(),
                   let shopDevice = model.write("Self-test shop device", { library in
                       var made = Device(customerId: shop.id, category: .console, brand: "Self-Test", model: "Shop Console")
                       made.purchaseCents = 4_000
                       return try library.save(made)
                   }),
                   let job = model.createRepair(deviceID: shopDevice.id, complaint: "Refurbish", promisedAt: nil) {
                    check("a repair on a shop device is internal", model.read(false) { try $0.isInternal(job.id) })
                    model.sidebar = .repairs
                    model.selectedRepair = job.id
                    try? await Task.sleep(for: .seconds(0.5))
                    let documents = [String(localized: "Print Intake Slip"), String(localized: "Print Estimate"), String(localized: "Invoice")]
                    let enabled = repairMenuItems().filter { documents.contains($0.title) && $0.isEnabled }
                    check("an internal job has no documents in the Repair menu", enabled.isEmpty, enabled.map(\.title).joined(separator: ", "))
                    model.setStatus(.ready, for: job.id, force: true)
                    check("an internal job is never To Collect", !model.read([]) { try $0.toCollectRepairIDs() }.contains(job.id))
                    let buyer = model.write("Self-test buyer") { try $0.save(Customer(name: "Shop Buyer")) }
                    model.setDisposition(.sold, priceCents: 10_000, buyer: buyer?.id, of: shopDevice.id)
                    let sold = model.read([]) { try $0.shopDevices() }.first { $0.id == shopDevice.id }
                    check("a sold shop device shows its profit", sold?.profitCents == 6_000)
                    check("a sold shop device belongs to the buyer", model.read(nil) { try $0.device(shopDevice.id) }?.customerId == buyer?.id)
                    // S-043 Invoice the sale: the PDF goes on the device.
                    await model.issueSaleInvoice(for: shopDevice.id)
                    let sale = model.read(nil) { try $0.saleInvoices(of: shopDevice.id).first }
                    check("a sale invoice takes an invoice number", sale?.numberText?.hasPrefix("F-") == true && sale?.repairId == nil)
                    check("the sale invoice PDF is on the device",
                          model.read([]) { try $0.attachments(for: .device, id: shopDevice.id) }.contains { $0.id == sale?.fileId })
                } else {
                    check("a repair on a shop device is internal", false)
                }

                // S-051 A library starts unconnected; its changes still queue for the day it connects.
                SyncController.shared.load(model)
                check("a library starts with no server and Settings has a Sync tab",
                      !SyncController.shared.isConnected && SettingsTab.allCases.contains(.sync))
                check("local changes queue for sync", model.read(0) { try $0.pendingSyncCount() } > 0)

                // S-046 A walk-in counter sale: an invoice filed with the shop; the part leaves stock as Sold.
                if let cable = model.write("Self-test counter part", { try $0.save(Part(name: "Self-test cable", priceCents: 1_500, quantity: 3), fits: []) }) {
                    await model.issueCounterSale(to: nil, items: [CounterSaleItem(partId: cable.id, description: cable.name, unitCents: 1_500)])
                    let walkIn = model.read(nil) { try $0.existingShop() }.flatMap { shop in model.read([]) { try $0.counterSales(of: shop.id) }.first }
                    check("a walk-in counter sale is invoiced, its PDF on the shop, and the part leaves stock",
                          walkIn?.fileId != nil && model.read(nil) { try $0.part(cable.id) }?.quantity == 2
                          && model.read([]) { try $0.stockHistory(of: cable.id) }.first?.move.reason == .sold)
                }

                // S-033 A customer with an open repair asks first, goes to the Trash with it, and Undo brings both back.
                if let leaving = model.write("Self-test trash customer", { library -> Customer in
                    let customer = try library.save(Customer(name: "Trash Me"))
                    let device = try library.save(Device(customerId: customer.id, category: .phone, brand: "Self-Test", model: "Phone"))
                    _ = try library.createRepair(deviceID: device.id, complaint: "Will be trashed")
                    return customer
                }) {
                    let undo = UndoManager()
                    undo.groupsByEvent = false
                    model.undoManager = undo
                    model.sidebar = .customers
                    model.selectedCustomer = leaving.id
                    model.trashFocused()
                    check("trashing a customer with open repairs asks first", model.pendingTrash?.openRepairs == 1)
                    check("nothing moves before the answer", model.read(0) { try $0.customers(matching: "Trash Me").count } == 1)
                    undo.beginUndoGrouping()
                    model.moveToTrash(.customer(leaving.id), confirmed: true)
                    undo.endUndoGrouping()
                    model.pendingTrash = nil
                    check("Move to Trash hides the customer and their repair",
                          model.read(1) { try $0.customers(matching: "Trash Me").count } == 0
                          && !model.read([]) { try $0.repairRows() }.contains { $0.customer.id == leaving.id })
                    check("Move to Trash clears the selection", model.selectedCustomer == nil)
                    undo.undo()
                    check("Undo brings back the customer and their repair",
                          model.read(0) { try $0.customers(matching: "Trash Me").count } == 1
                          && model.read([]) { try $0.repairRows() }.contains { $0.customer.id == leaving.id })
                    check("Undo selects the customer again", model.selectedCustomer == leaving.id)
                    model.undoManager = nil
                }

                // S-042 This year's report has the invoices, the credit note, and the sale; its CSV a row for each.
                let report = model.read(nil) { try $0.salesReport(ReportPeriod(.year, containing: .now)) }
                check("the report lists invoices and credit notes", report.map { $0.rows.contains { $0.invoice.kind == .creditNote } } == true)
                let csv = report?.csv().split(separator: "\n") ?? []
                check("the CSV has a header and one row per document, each tax in a column",
                      csv.count == (report?.rows.count ?? -1) + 1 && csv.first?.contains(",GST,QST,") == true)
                model.sidebar = .reports
                check("the sidebar opens Reports", model.sidebar == .reports)

                // S-039 Moving the business to the United States shows US dollars and English for new customers.
                let home = model.read(BusinessProfile()) { try $0.businessProfile() }
                var moved = home
                moved.setRegion(.unitedStates, "TX")
                model.save(moved)
                check("a US business shows US dollars", Money.currencyCode == "USD")
                check("a US business's new customers get English documents", CustomerDraft().language == .english)
                model.save(home)
                check("back in Québec, Canadian dollars and French", Money.currencyCode == "CAD" && CustomerDraft().language == .french)

                // S-001 Data survives a restart
                let reopened = try? Library(databaseURL: Store.url)
                check("a reopened library has the customer", (try? reopened?.customers(matching: "Self Test"))??.count == 1)

                // S-030 Back up, change something, restore: the change is gone and the library is open again.
                model.write("Self-test before backup") { try $0.save(Customer(name: "Before Backup")) }
                if let backup = await Backups.shared.backUp(model, name: "Self-Test") {
                    check("a backup file is written", FileManager.default.fileExists(atPath: backup.path))
                    model.write("Self-test after backup") { try $0.save(Customer(name: "After Backup")) }
                    await model.restore(from: backup)
                    check("restore reopens the library", model.library != nil)
                    check("restore brings back the backup's rows", model.read(0) { try $0.customers(matching: "Before Backup").count } == 1)
                    check("restore drops rows added after the backup", model.read(1) { try $0.customers(matching: "After Backup").count } == 0)
                    check("restore keeps a backup of what it replaced",
                          Backups.shared.existing.contains { $0.lastPathComponent.hasPrefix("BenchLog Before Restore") })
                } else {
                    check("a backup file is written", false)
                }
            }

            // S-051 to S-054 end to end: the real server, when Node and the source are here.
            await syncEndToEnd(model)

            for tab in SettingsTab.allCases {
                model.settingsTab = tab
                check("Settings has the \(tab.rawValue) tab", model.settingsTab == tab && !tab.title.isEmpty)
            }
            for page in SidebarItem.allCases {
                model.sidebar = page
                check("the sidebar opens \(page.rawValue)", model.sidebar == page)
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// The Repair menu's commands, after SwiftUI has updated their state.
    private static func repairMenuItems() -> [NSMenuItem] {
        guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == String(localized: "Repair") })?.submenu else { return [] }
        menu.update()
        return menu.items.filter { !$0.isSeparatorItem }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    /// Starts `server/` on a free port, connects the library through SyncController, opens a
    /// repair and issues an invoice with the server's numbers, then disconnects.
    @MainActor
    private static func syncEndToEnd(_ model: AppModel) async {
        // SELFTEST_SERVER=<url> (with SELFTEST_TOKEN) syncs with a server already running, such as
        // the Docker image; it must hold no library yet. Otherwise the self-test starts server/ with Node.
        let environment = ProcessInfo.processInfo.environment
        let server: URL
        let token: String
        var process: Process?
        if let given = environment["SELFTEST_SERVER"].flatMap(URL.init(string:)) {
            server = given
            token = environment["SELFTEST_TOKEN"] ?? ""
            print("sync end to end with \(given.absoluteString)")
        } else {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "server/src/main.js")
            guard let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
                  FileManager.default.fileExists(atPath: source.path) else {
                print("SKIP sync end to end: no Node or no server source")
                return
            }
            let data = Store.url.deletingLastPathComponent().appending(path: "server-\(UUID().uuidString)")
            let port = Int.random(in: 41_000...49_000)
            let started = Process()
            started.executableURL = URL(fileURLWithPath: node)
            started.arguments = [source.path]
            started.environment = ["PORT": "\(port)", "DATA_DIR": data.path, "BENCHLOG_TOKEN": "self-test"]
            started.standardOutput = FileHandle.nullDevice
            guard (try? started.run()) != nil else { check("the sync server starts", false); return }
            process = started
            server = URL(string: "http://127.0.0.1:\(port)")!
            token = "self-test"
        }
        defer { process?.terminate() }
        for _ in 0..<50 where (try? await URLSession.shared.data(from: server.appending(path: "v1/health"))) == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let sync = SyncController.shared
        do {
            try await sync.connect(model, server: server, token: token, join: false)
        } catch {
            check("the library connects to the server", false, error.localizedDescription)
            return
        }
        check("the library connects and uploads", sync.isConnected && model.read(1) { try $0.pendingSyncCount() } == 0)
        check("connecting shows the library key", sync.recoveryCode(model).flatMap(LibraryKey.init(recoveryCode:)) != nil)
        let before = model.read(0) { try $0.repairRows().map(\.repair.ticketNumber).max() ?? 0 }
        if let device = model.read(nil, { try $0.repairRows().first?.device }),
           let repair = model.createRepair(deviceID: device.id, complaint: "Synced repair", promisedAt: nil) {
            check("a connected library opens repairs from its ticket block", repair.ticketNumber > before)
            model.write("Self-test labour") { try $0.save(LabourLine(repairId: repair.id, description: "Bench", kind: .flat, unitCents: 5_000)) }
            let next = (try? await HTTPSyncTransport(baseURL: server, token: token).library())?.numbers["invoice"] ?? 0
            await model.issue(.invoice, for: repair.id)
            let invoice = model.read(nil) { try $0.invoices(for: repair.id).first { $0.kind == .invoice } }
            check("a connected library numbers invoices from the server", invoice?.number == next, "\(invoice?.number ?? 0) vs \(next)")
            await sync.syncNow(model)
            check("Sync Now leaves nothing waiting", model.read(1) { try $0.pendingSyncCount() } == 0 && sync.status != .syncing)
        }
        sync.disconnect(model)
        check("Disconnect forgets the server", !sync.isConnected)
    }

    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
