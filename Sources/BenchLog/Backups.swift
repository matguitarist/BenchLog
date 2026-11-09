import AppKit
import BenchLogKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Backups of the whole library as `.benchlog` files: Back Up Now, a daily backup that keeps
/// the last 14, and restore. The folder defaults to ~/Documents/BenchLog Backups. In a test
/// or snapshot run (APP_STORE), backups go next to that library and nothing runs by itself.
@MainActor
@Observable
final class Backups {
    static let shared = Backups()
    static let keepDaily = 14
    static let type = UTType(filenameExtension: Library.backupExtension) ?? .data

    private let defaults: UserDefaults?

    var folder: URL {
        didSet { defaults?.set(folder.path, forKey: "backupFolder") }
    }

    var daily: Bool {
        didSet { defaults?.set(daily, forKey: "dailyBackups") }
    }

    private(set) var lastBackupAt: Date? {
        didSet { defaults?.set(lastBackupAt, forKey: "lastBackupAt") }
    }

    private(set) var working = false

    private init() {
        if Store.isOverridden {
            defaults = nil
            folder = Store.url.deletingLastPathComponent().appending(path: "Backups", directoryHint: .isDirectory)
            daily = true
        } else {
            let defaults = UserDefaults.standard
            self.defaults = defaults
            folder = defaults.string(forKey: "backupFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? URL.documentsDirectory.appending(path: "BenchLog Backups", directoryHint: .isDirectory)
            daily = defaults.object(forKey: "dailyBackups") as? Bool ?? true
            lastBackupAt = defaults.object(forKey: "lastBackupAt") as? Date
        }
    }

    /// The backups in the folder, newest first.
    var existing: [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == Library.backupExtension }
            .sorted { modified($0) > modified($1) }
    }

    /// Makes a backup named "BenchLog <date> <time>.benchlog", or `name` when given.
    @discardableResult
    func backUp(_ model: AppModel, name: String? = nil) async -> URL? {
        guard let library = model.library, !working else { return nil }
        working = true
        defer { working = false }
        let now = Date.now
        let url = folder.appending(path: "\(name ?? "BenchLog \(Self.stamp(now, time: true))").\(Library.backupExtension)")
        let folder = folder
        do {
            let manifest = try await Task.detached {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return try library.backUp(to: url, now: now)
            }.value
            lastBackupAt = now
            model.log.post(.info, "Backed up the library (\(manifest.fileCount) files) to \(url.path)", source: "Backup")
            return url
        } catch {
            model.log.post(.error, "Backup failed: \(error.localizedDescription)", source: "Backup")
            model.problem = String(localized: "Unable to back up the library: \(error.localizedDescription)")
            return nil
        }
    }

    /// The daily backup, when the last one is a day old, then the oldest daily ones beyond 14 go.
    func backUpIfDue(_ model: AppModel) async {
        guard daily, !Store.isOverridden else { return }
        if let lastBackupAt, Date.now.timeIntervalSince(lastBackupAt) < 24 * 3600 { return }
        guard await backUp(model, name: "BenchLog Daily \(Self.stamp(.now, time: false))") != nil else { return }
        let dailies = existing.filter { $0.lastPathComponent.hasPrefix("BenchLog Daily ") }
        for old in dailies.dropFirst(Self.keepDaily) {
            try? FileManager.default.trashItem(at: old, resultingItemURL: nil)
        }
    }

    /// Runs the daily backup now and then, for as long as the window is open.
    func runDaily(_ model: AppModel) async {
        while !Task.isCancelled {
            await backUpIfDue(model)
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    /// 2026-11-09, or 2026-11-09 14.32 with the time (no colons: Finder shows them as slashes).
    static func stamp(_ date: Date, time: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = time ? "yyyy-MM-dd HH.mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}

extension AppModel {
    /// Replaces the library with a backup. The library as it is now is backed up first, as
    /// "BenchLog Before Restore <date>", so a wrong choice can be undone by restoring that.
    func restore(from backup: URL) async {
        guard let library else { return }
        do {
            _ = try Library.manifest(ofBackup: backup)
        } catch {
            problem = error.localizedDescription
            return
        }
        guard await Backups.shared.backUp(self, name: "BenchLog Before Restore \(Backups.stamp(.now, time: true))") != nil else { return }
        let databaseURL = Store.url
        do {
            try library.close()
            replaceLibrary(nil)
            try await Task.detached { try Library.restore(backup, into: databaseURL) }.value
            log.post(.info, "Restored the library from \(backup.path)", source: "Backup")
        } catch {
            log.post(.error, "Restore failed: \(error.localizedDescription)", source: "Backup")
            problem = String(localized: "Unable to restore the backup: \(error.localizedDescription)")
        }
        // Open whatever is there now: the restored library, or the old one if nothing changed.
        replaceLibrary(try? Library(databaseURL: databaseURL))
    }
}

/// Settings → Backup.
struct BackupSettings: View {
    @Environment(AppModel.self) private var model
    @State private var backups = Backups.shared
    @State private var choosingFolder = false
    @State private var choosingBackup = false
    @State private var restoring: URL?

    var body: some View {
        Section {
            LabeledContent("Last backup") {
                if let last = backups.lastBackupAt {
                    Text(last.formatted(date: .long, time: .shortened))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Folder") {
                HStack(spacing: Space.sm) {
                    Text(backups.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(backups.folder.path)
                    Button("Change…") { choosingFolder = true }
                    Button("Show in Finder", systemImage: "folder") {
                        try? FileManager.default.createDirectory(at: backups.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([backups.folder])
                    }
                    .labelStyle(.iconOnly)
                    .help("Show the backups folder in the Finder")
                }
            }
            Toggle(isOn: $backups.daily) {
                Text("Back up every day")
                Text("Keeps the last \(Backups.keepDaily) daily backups; backups you make yourself stay.")
            }
        } header: {
            Text("Backups")
        } footer: {
            HStack {
                if backups.working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Restore from Backup…") { choosingBackup = true }
                    .help("Replace the library with a backup; it is backed up first")
                Button("Back Up Now") { Task { await backups.backUp(model) } }
                    .help("Save the database and every photo and file as one .benchlog file")
            }
            .disabled(backups.working || model.library == nil)
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { backups.folder = url }
        }
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [Backups.type]) { result in
            if case .success(let url) = result { restoring = url }
        }
        .confirmationDialog(restoreTitle, isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restore", role: .destructive) {
                if let restoring { Task { await model.restore(from: restoring) } }
                restoring = nil
            }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: {
            Text("The library is replaced by the backup. BenchLog backs up the library first, as “BenchLog Before Restore”.")
        }
    }

    private var restoreTitle: String {
        guard let restoring else { return "" }
        if let manifest = try? Library.manifest(ofBackup: restoring) {
            return String(localized: "Restore the Backup from \(manifest.createdAt.formatted(date: .long, time: .shortened))?")
        }
        return String(localized: "Restore “\(restoring.deletingPathExtension().lastPathComponent)”?")
    }
}
