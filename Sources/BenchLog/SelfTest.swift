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
                    }
                }

                // S-001 Data survives a restart
                let reopened = try? Library(databaseURL: Store.url)
                check("a reopened library has the customer", (try? reopened?.customers(matching: "Self Test"))??.count == 1)
            }

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

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
