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

    /// The engine for the open library, with its server, token, and key; nil when it is not
    /// connected or a secret is missing.
    private func engine(_ model: AppModel) -> SyncEngine? {
        guard let library = model.library, let server, let id = try? library.libraryID(),
              let token = Self.secret("token", id), let key = Self.secret("key", id).flatMap({ LibraryKey(recoveryCode: $0) }) else { return nil }
        return SyncEngine(library: library, transport: transport(server, token), key: key)
    }

    /// The library key as a recovery code, for another device to join.
    func recoveryCode(_ model: AppModel) -> String? {
        guard let id = model.read(nil, { try $0.libraryID() }) else { return nil }
        return Self.secret("key", id)
    }

    /// Connects the open library. `join` replaces it with the server's library, after a backup;
    /// it needs that library's key as a recovery code.
    func connect(_ model: AppModel, server: URL, token: String, join: Bool, recoveryCode: String = "") async throws {
        guard let library = model.library else { return }
        let key: LibraryKey
        if join {
            guard let given = LibraryKey(recoveryCode: recoveryCode) else { throw SyncError.wrongKey }
            key = given
        } else {
            key = Self.secret("key", try library.libraryID()).flatMap { LibraryKey(recoveryCode: $0) } ?? LibraryKey()
        }
        if join {
            guard await Backups.shared.backUp(model, name: "BenchLog Before Joining \(Backups.stamp(.now, time: true))") != nil else { return }
        }
        status = .syncing
        let engine = SyncEngine(library: library, transport: transport(server, token), key: key)
        do {
            let report = try await engine.connect(join: join)
            let id = try library.libraryID()
            Self.saveSecret(token, "token", id)
            Self.saveSecret(key.recoveryCode, "key", id)
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
        if let id = try? library.libraryID() { Self.deleteSecret("token", id) }   // the key stays: data is sealed with it
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
        guard let library = model.library, let engine = engine(model) else {
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
                let report = try await engine.sync()
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
        guard isConnected else { return nil }
        guard let engine = engine(model) else { throw NumberingError.needsServer }
        do {
            return try await engine.number(sequence)
        } catch {
            model.log.post(.warning, "No \(sequence) number from the server: \(error.localizedDescription)", source: "Sync")
            throw NumberingError.needsServer
        }
    }

    /// Returns a number the document never used, so the sequence keeps no gap.
    func giveBack(_ sequence: String, number: Int, _ model: AppModel) async {
        try? await engine(model)?.giveBack(sequence, number: number)
    }

    /// Snapshots: a library connected to a server, synced two minutes ago, two changes waiting.
    func showConnectedForSnapshot(_ model: AppModel) {
        if let id = model.read(nil, { try $0.libraryID() }) { Self.saveSecret(LibraryKey().recoveryCode, "key", id) }
        server = URL(string: "http://bench-mac.local:8420")
        status = .synced(.now.addingTimeInterval(-120))
        pending = 2
    }

    // MARK: Secrets: the token and the library key, in the Keychain under the library's id

    private static var memorySecrets: [String: String] = [:]
    private static let service = "com.mathieuares.benchlog.sync"

    static func secret(_ kind: String, _ libraryID: String) -> String? {
        let account = "\(kind)-\(libraryID)"
        if Store.isOverridden { return memorySecrets[account] }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func saveSecret(_ value: String, _ kind: String, _ libraryID: String) {
        let account = "\(kind)-\(libraryID)"
        if Store.isOverridden { memorySecrets[account] = value; return }
        deleteSecret(kind, libraryID)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func deleteSecret(_ kind: String, _ libraryID: String) {
        let account = "\(kind)-\(libraryID)"
        if Store.isOverridden { memorySecrets[account] = nil; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
