import AppKit
import BenchLogKit
import LogKitUI
import SwiftUI

// BenchLog
//   BenchLog                          the app, on the library in ~/Library/Application Support/BenchLog
//   APP_STORE=<file> BenchLog         a library at <file> (a .sqlite in /tmp), its files and log next to it; never touches the real one
//   APP_SNAPSHOT=<dir> BenchLog       save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 BenchLog               with APP_STORE: fill an empty library with sample data (tools/snap.sh)
//   BenchLog --selftest               run the self-test on a /tmp library and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> BenchLog          run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 BenchLog               draw the 8 pt grid and the layout probes over the window

@main
struct BenchLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(library: Store.openLibrary(), log: Store.log)

    var body: some Scene {
        Window("BenchLog", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            // Grouped: older SDKs take at most ten commands per builder (CI builds on one).
            Group {
                SidebarCommands()
                // File > Import from iPhone: Take Photo, Scan Documents (Continuity Camera).
                ImportFromDevicesCommands()
                ToolbarCommands()
                FindCommands(model: model)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Repair…") { model.newRepair() }
                    .keyboardShortcut("n")
                    .disabled(model.library == nil || model.sheet != nil)
                Button("New Customer…") { model.sheet = .newCustomer }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(model.library == nil || model.sheet != nil)
                Button("New Counter Sale…") { model.sheet = .newCounterSale(customer: model.customerForNewDevice) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .disabled(model.library == nil || model.sheet != nil)
                Button("Add Device…") {
                    if let customer = model.customerForNewDevice { model.sheet = .addDevice(customer: customer) }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.customerForNewDevice == nil || model.sheet != nil)
                Divider()
                Button("Add Note") { model.focusNoteField = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(model.focusedRecord == nil || model.sheet != nil)
                Button("Add Photo or File…") { model.choosingFilesFor = model.focusedRecord?.id }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(model.focusedRecord == nil || model.sheet != nil)
            }
            CommandGroup(after: .newItem) {
                Button("New Part…") { model.sheet = .newPart }
                    .keyboardShortcut("n", modifiers: [.command, .control])
                    .disabled(model.library == nil || model.sheet != nil)
                Menu("Add Starter Parts") { StarterPartsButtons(model: model) }
                    .disabled(model.library == nil || model.sheet != nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Move to Trash") { model.trashFocused() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.focusedTrashItem == nil || model.sheet != nil)
            }
            // Help: BenchLog Help (⌘?), its topics, the release notes, and Report a Problem.
            HelpCommands(model: model)
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
            CommandGroup(after: .sidebar) {
                Divider()
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { model.sidebar = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
                }
            }
            CommandMenu("Repair") {
                Menu("Status") {
                    StatusButtons(model: model, repairID: model.focusedRepairID, current: model.focusedRepairStatus)
                }
                .disabled(model.focusedRepairID == nil)
                Button("Print Intake Slip") {
                    if let id = model.focusedRepairID { Task { await model.printIntakeSlip(for: id) } }
                }
                .keyboardShortcut("p")
                .disabled(model.focusedRepairID == nil || model.focusedRepairIsInternal)
                Button("Print Estimate") {
                    if let id = model.focusedRepairID { Task { await model.issue(.estimate, for: id) } }
                }
                .disabled(model.focusedRepairID == nil || model.focusedRepairIsInternal)
                Button("Invoice") {
                    if let id = model.focusedRepairID { Task { await model.issue(.invoice, for: id) } }
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.focusedRepairID == nil || model.focusedRepairIsInternal)
                Divider()
                Button("Open Customer") {
                    if let id = model.focusedRepairID, let row = model.read(nil, { try $0.repairRow(id) }) { model.open(.customer(row.customer.id)) }
                }
                .disabled(model.focusedRepairID == nil)
                Button("Open Device") {
                    if let id = model.focusedRepairID, let row = model.read(nil, { try $0.repairRow(id) }) { model.open(.device(row.device.id)) }
                }
                .disabled(model.focusedRepairID == nil)
            }
            CommandMenu("Go") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[")
                    .disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }
                    .keyboardShortcut("]")
                    .disabled(!model.canGoForward)
            }
        }

        // Help > BenchLog Help: the topics, beside the main window.
        Window("BenchLog Help", id: "help") {
            HelpWindow()
                .themed()
        }
        .defaultSize(width: 900, height: 640)

        // Open in Window: a guide beside the main window.
        WindowGroup("Guide", id: "guide", for: UUID.self) { $guideID in
            GuideWindow(guideID: guideID)
                .environment(model)
                .themed()
        }
        .defaultSize(width: 760, height: 860)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the library lives: ~/Library/Application Support/BenchLog/benchlog.sqlite and Files/.
/// With APP_STORE set (tests, snapshots, self-test), a library at that path in /tmp instead.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "BenchLog", directoryHint: .isDirectory)
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return folder.appending(path: "benchlog.sqlite")
    }

    /// ~/Library/Logs/BenchLog/BenchLog.log, or next to APP_STORE in a test run.
    static var logURL: URL {
        isOverridden ? url.deletingPathExtension().appendingPathExtension("log")
                     : LogStore.defaultFileURL(app: "BenchLog")
    }

    static let log = LogStore(fileURL: logURL)

    /// The library, or the reason it could not open (shown on the Overview page).
    static func openLibrary() -> Result<Library, Error> {
        do {
            let library = try Library(databaseURL: url)
            log.post(.info, "Opened the library at \(url.path)", source: "Library")
            return .success(library)
        } catch {
            log.post(.error, "Unable to open the library at \(url.path): \(error.localizedDescription)", source: "Library")
            return .failure(error)
        }
    }
}
