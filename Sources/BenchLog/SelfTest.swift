import AppKit
import BenchLogKit

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
