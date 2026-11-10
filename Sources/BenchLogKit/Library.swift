import Foundation
import GRDB

/// BenchLog's library on disk: the SQLite database and, next to it, the folder
/// of photos and files. The database only stores paths relative to that folder,
/// so the whole library can move, be backed up, or later sync as one unit.
///
///     ~/Library/Application Support/BenchLog/benchlog.sqlite
///     ~/Library/Application Support/BenchLog/Files/
public final class Library: Sendable {
    public let databaseURL: URL
    public let filesURL: URL
    public let db: DatabaseQueue

    /// Opens (or creates) the library at `databaseURL`; the files folder is
    /// `Files` next to it, or `<name>-files` for a database not named benchlog.sqlite.
    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let folder = databaseURL.deletingLastPathComponent()
        let stem = databaseURL.deletingPathExtension().lastPathComponent
        filesURL = stem == "benchlog" ? folder.appending(path: "Files", directoryHint: .isDirectory)
                                      : folder.appending(path: "\(stem)-files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try Self.migrator.migrate(db)
    }

    /// An in-memory library for tests.
    public init() throws {
        databaseURL = URL(fileURLWithPath: "/dev/null")
        filesURL = FileManager.default.temporaryDirectory.appending(path: "BenchLog-\(UUID().uuidString)-files")
        try FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        db = try DatabaseQueue()
        try Self.migrator.migrate(db)
    }

    /// The migrations this library has run, oldest first.
    public func appliedMigrations() throws -> [String] {
        try db.read { try Self.migrator.appliedMigrations($0) }
    }

    public func metaValue(_ key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key]) }
    }
}
