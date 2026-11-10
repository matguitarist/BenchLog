import AppKit
import BenchLogKit
import BenchLogServerKit
import Foundation
import Observation
import ServiceManagement
import SystemConfiguration

/// "Use This Mac as the Server" (Settings > Sync): the server built into the app runs as a
/// login item (Contents/MacOS/BenchLogServer), and this library connects to it.
///
/// Two adapters: the login item through SMAppService, and in test runs (APP_STORE) the same
/// server in this process on a free port, so the self-test and snapshots never touch launchd.
@MainActor
@Observable
final class ServerHost {
    static let shared = ServerHost()

    enum State: Equatable {
        case off
        case starting
        case running
        /// The person turned BenchLog off in System Settings > General > Login Items.
        case needsApproval
        case failed(String)
    }

    private(set) var state: State = .off
    /// Set while Settings asks "Stop the Server on This Mac?" (a property, so snapshots can show it).
    var confirmingStop = false

    private let service = SMAppService.agent(plistName: "com.mathieuares.benchlog.server.plist")
    private var inProcess: BenchLogServer?
    private var inProcessPort: UInt16 = 0

    private init() {
        refresh()
    }

    /// The server's folder: library.sqlite, files/, token, server.log.
    var dataDirectory: URL {
        Store.isOverridden
            ? URL(fileURLWithPath: Store.url.deletingPathExtension().path + "-server", isDirectory: true)   // beside the test library
            : URL.applicationSupportDirectory.appending(path: "BenchLog Server", directoryHint: .isDirectory)
    }

    private var port: UInt16 { Store.isOverridden ? inProcessPort : BenchLogServer.defaultPort }

    /// Where this Mac reaches its own server.
    var localURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    /// What the other Macs enter: this Mac's local network name, such as http://Bench-Mac.local:8420.
    var addressForOthers: String {
        let name = SCDynamicStoreCopyLocalHostName(nil) as String? ?? ProcessInfo.processInfo.hostName
        return "http://\(name.hasSuffix(".local") ? name : name + ".local"):\(BenchLogServer.defaultPort)"
    }

    var token: String? {
        (try? String(contentsOf: dataDirectory.appending(path: "token"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when this library syncs with the server on this Mac.
    func serves(_ server: URL?) -> Bool {
        guard let server, state == .running || state == .starting else { return false }
        return server.host() == "127.0.0.1" && server.port == Int(port)
    }

    /// Reads whether the login item is on.
    func refresh() {
        if Store.isOverridden {
            state = inProcess == nil ? (state == .starting ? .starting : .off) : .running
            return
        }
        switch service.status {
        case .enabled: if state != .starting { state = .running }
        case .requiresApproval: state = .needsApproval
        default: if case .failed = state {} else if state != .starting { state = .off }
        }
    }

    /// Starts the server on this Mac and connects the open library to it.
    func start(_ model: AppModel) async {
        state = .starting
        do {
            try await launch()
            guard let token else { throw ServerError(String(localized: "The server made no token."), status: 500) }
            try await SyncController.shared.connect(model, server: localURL, token: token, join: false)
            state = .running
            model.log.post(.info, "This Mac is the server: \(addressForOthers)", source: "Sync")
        } catch SyncError.otherLibrary(let rows) {
            state = .failed(String(localized: "The server on this Mac holds another library (\(rows) items). Connect to it from Settings > Sync with its address and library key, or move its folder away."))
        } catch {
            if state != .needsApproval { state = .failed(error.localizedDescription) }
            model.log.post(.warning, "The server on this Mac did not start: \(error.localizedDescription)", source: "Sync")
        }
    }

    /// Stops the server and disconnects this library from it. The server's data stays.
    func stop(_ model: AppModel) {
        SyncController.shared.disconnect(model)
        if Store.isOverridden {
            inProcess?.stop()
            inProcess = nil
        } else {
            try? service.unregister()
        }
        state = .off
        model.log.post(.info, "This Mac stopped being the server; its data stays in \(dataDirectory.path)", source: "Sync")
    }

    func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func showDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([dataDirectory])
    }

    // MARK: Launching

    private func launch() async throws {
        if Store.isOverridden {
            if inProcess == nil {
                let (token, _) = try BenchLogServer.token(in: dataDirectory)
                let server = try BenchLogServer(dataDirectory: dataDirectory, token: token)
                inProcessPort = try await server.start(port: 0, localOnly: true)
                inProcess = server
            }
            return
        }
        if service.status != .enabled {
            // Another server on the port (a Docker container, a test run) would answer for ours.
            if await healthy() { throw ServerError(String(localized: "Another server already uses port 8420 on this Mac. Stop it, then try again.")) }
            try service.register()
        }
        if service.status == .requiresApproval {
            state = .needsApproval
            throw ServerError(String(localized: "Allow BenchLog in System Settings > General > Login Items, then try again."))
        }
        for _ in 0..<60 {
            if await healthy() { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        let reason = (try? String(contentsOf: dataDirectory.appending(path: "server.log"), encoding: .utf8))?
            .split(separator: "\n").last.map(String.init)
        throw ServerError(reason ?? String(localized: "The server did not start."))
    }

    private func healthy() async -> Bool {
        var request = URLRequest(url: localURL.appending(path: "v1/health"), timeoutInterval: 1)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
