import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/BenchLog-test.sqlite APP_SNAPSHOT=/tmp/shots ~/Applications/BenchLog.app/Contents/MacOS/BenchLog
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=overview,log limits the pages. Add "settings" to include Settings.
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real library.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            if env["APP_SNAPSHOT_MIN"] != nil, let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) {
                // The window clamps to its content's minimum size.
                main.setContentSize(NSSize(width: 1, height: 1))
                try? await Task.sleep(for: .seconds(0.5))
            }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            // Page states: each Parts tab, and a repair with parts on it.
            let firstPart = model.read(nil) { try $0.parts(matching: "").first?.id }
            let waiting = model.read(nil) { library in
                try library.repairRows().first { try library.isWaitingOnParts($0.id) && $0.repair.status != .waitingOnParts }?.id
            }
            let guides = model.read([]) { try $0.guideRows() }
            let markdownGuide = guides.first { $0.guide.title == "Blinking Red Light" }?.id
            let pdfGuide = guides.first { $0.guide.format == .pdf }?.id
            let switchRepair = model.read(nil) { try $0.repairRows().first { $0.device.model == "Switch" }?.id }
            let states: [(String, () -> Void)] = [
                ("guide-markdown", { model.sidebar = .guides; model.selectedGuide = markdownGuide }),
                ("guide-pdf", { model.sidebar = .guides; model.selectedGuide = pdfGuide }),
                ("repair-guides", { model.sidebar = .repairs; model.repairFilter = .open; model.selectedRepair = switchRepair }),
                ("parts-inventory", { model.sidebar = .parts; model.partsTab = .inventory; model.selectedPart = firstPart }),
                ("parts-low", { model.sidebar = .parts; model.partsTab = .low }),
                ("parts-toorder", { model.sidebar = .parts; model.partsTab = .toOrder }),
                ("parts-incoming", { model.sidebar = .parts; model.partsTab = .incoming }),
                ("repair-parts", { model.sidebar = .repairs; model.repairFilter = .open; model.selectedRepair = waiting }),
            ]
            for (name, setUp) in states where only == nil || only?.contains(name) == true || only?.contains("states") == true {
                setUp()
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(0.8))
                    if name == "repair-parts" { scrollDetail(toShow: 0.45) }
                    if name == "repair-guides" { scrollDetail(toShow: 0.42) }
                    if name.hasPrefix("guide-") { try? await Task.sleep(for: .seconds(1)) }
                    try? await Task.sleep(for: .seconds(0.3))
                    capture(to: "\(dir)/\(name)-\(mode).png")
                }
            }
            model.partsTab = .inventory
            // The sheets, each over the page it opens from.
            let customer = model.selectedCustomer
            let sheets: [(String, SidebarItem, SheetKind)] = [
                ("customer-new-sheet", .customers, .newCustomer),
                ("device-new-sheet", .customers, customer.map { .addDevice(customer: $0) } ?? .newCustomer),
                ("repair-new-sheet", .repairs, .newRepair(customer: nil, device: nil)),
                ("repair-new-for-customer-sheet", .customers, .newRepair(customer: customer, device: nil)),
                ("part-edit-sheet", .parts, firstPart.map { .editPart($0) } ?? .newPart),
                ("guide-edit-sheet", .guides, markdownGuide.map { .editGuide($0) } ?? .newPart),
                ("guides-import-sheet", .guides, .importGuides(Self.sampleVault())),
            ]
            for (name, page, sheet) in sheets where only == nil || only?.contains(name) == true || only?.contains("sheets") == true {
                model.sidebar = page
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    model.sheet = sheet
                    try? await Task.sleep(for: .seconds(1))
                    let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                    capture(to: "\(dir)/\(name)-\(mode).png", window: main?.attachedSheet)
                    model.sheet = nil
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    /// A small vault for the import sheet: model folders, a revision, a general note.
    private static func sampleVault() -> URL {
        let root = URL(fileURLWithPath: "/tmp/BenchLog-snapshot-vault")
        try? FileManager.default.removeItem(at: root)
        let notes = ["Nintendo/Consoles/NES/_index.md": "# Nintendo Entertainment System",
                     "Nintendo/Consoles/NES/blank-screen.md": "# Blank Screen", "Nintendo/Consoles/NES/audio-problems.md": "![[missing.png]]",
                     "Nintendo/Switch/OLED Model/fan.pdf": "%PDF", "Microsoft/Consoles/Xbox/frag-error.md": "# FRAG Error",
                     "Sega/Portable Consoles/Game Gear/capacitors.md": "# Recapping the Game Gear", "Electronic Repair Guide.md": "# Electronic Repair Guide"]
        for (path, text) in notes {
            let url = root.appending(path: path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url)
        }
        return root
    }

    /// Scrolls the rightmost scroll view (the detail form) so the given fraction of its content is at the top.
    private static func scrollDetail(toShow fraction: CGFloat) {
        guard let root = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet })?.contentView else { return }
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
        }
        guard let detail = scrollViews(root).max(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }),
              let document = detail.documentView else { return }
        let y = document.bounds.height * fraction
        document.scroll(NSPoint(x: 0, y: document.isFlipped ? y : document.bounds.height - y - detail.contentSize.height))
    }

    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
