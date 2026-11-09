import Foundation
import GRDB

/// What a backup says about itself, in `manifest.json` inside the `.benchlog` file.
public struct BackupManifest: Codable, Sendable, Equatable {
    public var format = 1
    public var createdAt: Date
    /// The library's migrations when it was backed up; a backup with one this app does not
    /// know was made by a newer BenchLog.
    public var migrations: [String]
    public var fileCount: Int
}

public enum BackupError: LocalizedError, Equatable {
    case notABackup, madeByNewerVersion, tooLarge

    public var errorDescription: String? {
        switch self {
        case .notABackup: String(localized: "This file is not a BenchLog backup.")
        case .madeByNewerVersion: String(localized: "This backup was made by a newer BenchLog. Update BenchLog, then restore it.")
        case .tooLarge: String(localized: "The library is too large for one backup file (over 4 GB).")
        }
    }
}

/// A backup is one `.benchlog` file: a ZIP holding `manifest.json`, `benchlog.sqlite` (a
/// consistent copy, made with SQLite's backup), and every file under `Files/`.
extension Library {
    public static let backupExtension = "benchlog"

    /// Writes a backup of the whole library to `url`.
    @discardableResult
    public func backUp(to url: URL, now: Date = .now) throws -> BackupManifest {
        let manager = FileManager.default
        let scratch = manager.temporaryDirectory.appending(path: "BenchLog-backup-\(UUID().uuidString)")
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: scratch) }

        // A consistent copy of the database, even while the app writes to it.
        let copyURL = scratch.appending(path: "benchlog.sqlite")
        let copy = try DatabaseQueue(path: copyURL.path)
        try db.backup(to: copy)
        try copy.close()

        let files = Self.files(under: filesURL)
        // Whole seconds: the manifest stores ISO 8601 without fractions.
        let manifest = BackupManifest(createdAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)), migrations: try appliedMigrations(), fileCount: files.count)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let partial = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).partial")
        do {
            let zip = try ZipArchive.Writer(url: partial, date: now)
            try zip.add("manifest.json", data: try encoder.encode(manifest))
            try zip.add("benchlog.sqlite", data: try Data(contentsOf: copyURL))
            for relative in files {
                try zip.add("Files/\(relative)", data: try Data(contentsOf: filesURL.appending(path: relative)))
            }
            try zip.finish()
        } catch ZipArchive.Failure.tooLarge {
            try? manager.removeItem(at: partial)
            throw BackupError.tooLarge
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
        // Only a finished backup takes the name, so a crash never leaves half a file behind.
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
        try manager.moveItem(at: partial, to: url)
        return manifest
    }

    /// Reads a backup's manifest without restoring it.
    public static func manifest(ofBackup url: URL) throws -> BackupManifest {
        let entries = try backupEntries(url)
        guard let data = entries.first(where: { $0.name == "manifest.json" })?.data else { throw BackupError.notABackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(BackupManifest.self, from: data) else { throw BackupError.notABackup }
        return manifest
    }

    /// Replaces the library at `databaseURL` (and its Files folder) with a backup. Close the
    /// open library first. The backup is checked and opened in a scratch folder before
    /// anything is replaced; an older backup is brought up to date by the migrations.
    public static func restore(_ backup: URL, into databaseURL: URL) throws {
        let manager = FileManager.default
        let entries = try backupEntries(backup)
        guard let databaseEntry = entries.first(where: { $0.name == "benchlog.sqlite" }),
              entries.contains(where: { $0.name == "manifest.json" }) else { throw BackupError.notABackup }

        let folder = databaseURL.deletingLastPathComponent()
        let scratch = folder.appending(path: ".restore-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: scratch) }
        let scratchDatabase = scratch.appending(path: "benchlog.sqlite")
        try databaseEntry.data.write(to: scratchDatabase)
        for entry in entries where entry.name.hasPrefix("Files/") {
            let relative = String(entry.name.dropFirst("Files/".count))
            // Never write outside the Files folder.
            guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { throw BackupError.notABackup }
            let target = scratch.appending(path: "Files").appending(path: relative)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: target)
        }

        // Refuse a backup from a newer app, then let the migrations bring an older one up to date.
        let queue = try DatabaseQueue(path: scratchDatabase.path)
        let applied = try queue.read { try migrator.appliedIdentifiers($0) }
        guard applied.isSubset(of: Set(migrator.migrations)) else {
            try queue.close()
            throw BackupError.madeByNewerVersion
        }
        try queue.close()
        let checked = try Library(databaseURL: scratchDatabase)
        try checked.close()

        // Swap: the old database and files go, the restored ones take their place.
        let stem = databaseURL.deletingPathExtension().lastPathComponent
        let filesURL = stem == "benchlog" ? folder.appending(path: "Files", directoryHint: .isDirectory)
                                          : folder.appending(path: "\(stem)-files", directoryHint: .isDirectory)
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            if manager.fileExists(atPath: path) { try manager.removeItem(atPath: path) }
        }
        if manager.fileExists(atPath: filesURL.path) { try manager.removeItem(at: filesURL) }
        try manager.moveItem(at: scratchDatabase, to: databaseURL)
        let restoredFiles = scratch.appending(path: "Files")
        if manager.fileExists(atPath: restoredFiles.path) {
            try manager.moveItem(at: restoredFiles, to: filesURL)
        } else {
            try manager.createDirectory(at: filesURL, withIntermediateDirectories: true)
        }
    }

    /// Closes the database; the library cannot be used afterwards. Restore needs it closed.
    public func close() throws {
        try db.close()
    }

    private static func backupEntries(_ url: URL) throws -> [ZipArchive.Entry] {
        do { return try ZipArchive.entries(of: url) } catch { throw BackupError.notABackup }
    }

    /// Paths of every regular file under `folder`, relative to it, sorted.
    static func files(under folder: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let base = folder.standardizedFileURL.path
        var paths: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            paths.append(String(path.dropFirst(base.count + 1)))
        }
        return paths.sorted()
    }
}
