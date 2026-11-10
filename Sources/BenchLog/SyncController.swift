import BenchLogKit
import Foundation
import Observation
import Security

/// Keeps the library in step with the BenchLog server: at launch, a few seconds after each
/// change, and every minute. The token is in the Keychain (in memory for test runs).
@MainActor
@Observable
final class SyncController {
    static let shared = SyncController()

    enum Status: Equatable {
        case off
        case syncing
        case synced(Date)
        case offline(String)
        case failed(String)
    }

    private(set) var status: Status = .off
    private(set) var server: URL?
    private(set) var pending = 0
    private var changeTask: Task<Void, Never>?
    private var running = false
    private var again = false

    var isConnected: Bool { server != nil }

    /// Reads the connection of the library the model has open.
    func load(_ model: AppModel) {
        server = model.read(nil) { try $0.syncServer() }
        pending = model.read(0) { try $0.pendingSyncCount() }
        if server == nil {
            status = .off
        } else if case .off = status {
            status = model.read(nil) { try $0.syncedAt() }.map(Status.synced) ?? .syncing
        }
    }

    private func transport(_ server: URL, _ token: String) -> HTTPSyncTransport {
        HTTPSyncTransport(baseURL: server, token: token)
    }

    /// What the server holds, for Test Connection.
    func test(server: URL, token: String) async throws -> ServerLibrary {
        try await transport(server, token).library()
    }

    /// Connects the open library. `join` replaces it with the server's library, after a backup.
    func connect(_ model: AppModel, server: URL, token: String, join: Bool) async throws {
        guard let library = model.library else { return }
        if join {
            guard await Backups.shared.backUp(model, name: "BenchLog Before Joining \(Backups.stamp(.now, time: true))") != nil else { return }
        }
        status = .syncing
        let engine = SyncEngine(library: library, transport: transport(server, token))
        do {
            let report = try await engine.connect(join: join)
            Self.saveToken(token, for: try library.libraryID())
            try library.setSyncServer(server)
            try library.setSyncedAt(.now)
            model.log.post(.info, "Connected to \(server.absoluteString): pushed \(report.pushed), pulled \(report.pulled), "
                + "uploaded \(report.uploaded) and downloaded \(report.downloaded) files", source: "Sync")
            model.reload()
            load(model)
            status = .synced(.now)
        } catch {
            status = .off
            throw error
        }
    }

    func disconnect(_ model: AppModel) {
        guard let library = model.library else { return }
        try? library.setSyncServer(nil)
        if let id = try? library.libraryID() { Self.deleteToken(for: id) }
        model.log.post(.info, "Disconnected from the server", source: "Sync")
        load(model)
    }

    /// After a local change: sync a few seconds later, once the burst of changes is over.
    func changed(_ model: AppModel) {
        guard isConnected else { return }
        pending = model.read(0) { try $0.pendingSyncCount() }
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.syncNow(model)
        }
    }

    /// Syncs at launch and every minute while the window is open.
    func run(_ model: AppModel) async {
        while !Task.isCancelled {
            load(model)
            if isConnected { await syncNow(model) }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    func syncNow(_ model: AppModel) async {
        guard let library = model.library, let server, let token = Self.token(for: (try? library.libraryID()) ?? "") else {
            if isConnected { status = .failed(String(localized: "The token is missing. Connect again in Settings > Sync.")) }
            return
        }
        guard !running else { again = true; return }
        running = true
        defer { running = false }
        repeat {
            again = false
            status = .syncing
            do {
                let report = try await SyncEngine(library: library, transport: transport(server, token)).sync()
                try library.setSyncedAt(.now)
                if report.pulled > 0 || report.downloaded > 0 {
                    model.log.post(.info, "Synced: pushed \(report.pushed), pulled \(report.pulled)", source: "Sync")
                    model.reload()
                }
                status = .synced(.now)
            } catch let error as SyncError {
                if case .unreachable(let detail) = error { status = .offline(detail) } else { status = .failed(error.localizedDescription) }
                model.log.post(.warning, "Sync failed: \(error.localizedDescription)", source: "Sync")
            } catch {
                status = .failed(error.localizedDescription)
                model.log.post(.error, "Sync failed: \(error.localizedDescription)", source: "Sync")
            }
            pending = model.read(0) { try $0.pendingSyncCount() }
        } while again
    }

    /// A number for an invoice or credit note from the server; nil when not connected.
    /// Throws when connected and the server is out of reach.
    func number(_ sequence: String, _ model: AppModel) async throws -> Int? {
        guard let library = model.library, let server else { return nil }
        guard let token = Self.token(for: (try? library.libraryID()) ?? "") else { throw NumberingError.needsServer }
        do {
            return try await SyncEngine(library: library, transport: transport(server, token)).number(sequence)
        } catch {
            model.log.post(.warning, "No \(sequence) number from the server: \(error.localizedDescription)", source: "Sync")
            throw NumberingError.needsServer
        }
    }

    /// Returns a number the document never used, so the sequence keeps no gap.
    func giveBack(_ sequence: String, number: Int, _ model: AppModel) async {
        guard let library = model.library, let server, let token = Self.token(for: (try? library.libraryID()) ?? "") else { return }
        try? await SyncEngine(library: library, transport: transport(server, token)).giveBack(sequence, number: number)
    }

    /// Snapshots: a library connected to a server, synced two minutes ago, two changes waiting.
    func showConnectedForSnapshot() {
        server = URL(string: "http://bench-mac.local:8420")
        status = .synced(.now.addingTimeInterval(-120))
        pending = 2
    }

    // MARK: Token

    private static var memoryTokens: [String: String] = [:]
    private static let service = "com.mathieuares.benchlog.sync"

    static func token(for libraryID: String) -> String? {
        if Store.isOverridden { return memoryTokens[libraryID] }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: libraryID, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func saveToken(_ token: String, for libraryID: String) {
        if Store.isOverridden { memoryTokens[libraryID] = token; return }
        deleteToken(for: libraryID)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: libraryID, kSecValueData as String: Data(token.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteToken(for libraryID: String) {
        if Store.isOverridden { memoryTokens[libraryID] = nil; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: libraryID]
        SecItemDelete(query as CFDictionary)
    }
}
