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
