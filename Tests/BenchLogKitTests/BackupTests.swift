import Foundation
import GRDB
import Testing
@testable import BenchLogKit

/// S-030 Backup and restore.
@Suite struct BackupTests {
    let folder: URL
    let databaseURL: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "BenchLog-backup-test-\(UUID().uuidString)")
        databaseURL = folder.appending(path: "library/benchlog.sqlite")
    }

    private func fill(_ library: Library) throws -> (Customer, BenchLogKit.Attachment?) {
        let customer = try library.save(Customer(name: "Chloé Bouchard", phone: "514 555-0199"))
        let device = try library.save(Device(customerId: customer.id, category: .handheld, brand: "Nintendo", model: "Game Boy Advance"))
        let repair = try library.createRepair(deviceID: device.id, complaint: "No sound")
        _ = try library.addNote("Speaker is torn", to: .repair, id: repair.id)
        let photo = try library.addAttachment(data: Data((0..<5000).map { UInt8($0 % 251) }), originalName: "speaker.jpg",
                                              to: .repair, id: repair.id)
        return (customer, photo)
    }

    /// Every row of every table, as text, to compare two libraries.
    private func dump(_ library: Library) throws -> [String] {
        try library.db.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'search%'
                ORDER BY name
                """)
            return try tables.flatMap { table in
                try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY 1").map { "\(table) \($0)" }
            }
        }
    }

    @Test func aBackupRoundTrips() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(databaseURL: databaseURL)
        _ = try fill(library)
        let rowsBefore = try dump(library)
        let filesBefore = Library.files(under: library.filesURL)
        let bytesBefore = try filesBefore.map { try Data(contentsOf: library.filesURL.appending(path: $0)) }

        let backup = folder.appending(path: "test.benchlog")
        let manifest = try library.backUp(to: backup)
        #expect(manifest.fileCount == filesBefore.count)
        #expect(try Library.manifest(ofBackup: backup) == manifest)

        // Wipe the library, then restore it.
        try library.close()
        try FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
        try Library.restore(backup, into: databaseURL)

        let restored = try Library(databaseURL: databaseURL)
        #expect(try dump(restored) == rowsBefore)
        let filesAfter = Library.files(under: restored.filesURL)
        #expect(filesAfter == filesBefore)
        #expect(try filesAfter.map { try Data(contentsOf: restored.filesURL.appending(path: $0)) } == bytesBefore)
        // The search index is rebuilt with the rows.
        #expect(try restored.search("chloe").contains { $0.kind == .customer })
    }

    @Test func restoreReplacesWhatIsThere() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(databaseURL: databaseURL)
        _ = try fill(library)
        let backup = folder.appending(path: "before.benchlog")
        try library.backUp(to: backup)
        _ = try library.save(Customer(name: "Added After the Backup"))
        try library.close()

        try Library.restore(backup, into: databaseURL)
        let restored = try Library(databaseURL: databaseURL)
        #expect(try restored.customers(matching: "Added After").isEmpty)
        #expect(try restored.customers(matching: "Chloé").count == 1)
    }

    @Test func aBackupOpensInAnyUnzipTool() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(databaseURL: databaseURL)
        _ = try fill(library)
        let backup = folder.appending(path: "zip.benchlog")
        try library.backUp(to: backup)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-tq", backup.path]
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func notABackupIsRefusedAndChangesNothing() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(databaseURL: databaseURL)
        _ = try fill(library)
        try library.close()
        let junk = folder.appending(path: "junk.benchlog")
        try Data("hello".utf8).write(to: junk)
        #expect(throws: BackupError.notABackup) { try Library.restore(junk, into: databaseURL) }
        #expect(try Library(databaseURL: databaseURL).customers(matching: "Chloé").count == 1)
    }

    @Test func aBackupFromANewerAppIsRefused() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(databaseURL: databaseURL)
        try library.db.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v99-future')")
        }
        let backup = folder.appending(path: "future.benchlog")
        try library.backUp(to: backup)
        try library.close()
        #expect(throws: BackupError.madeByNewerVersion) {
            try Library.restore(backup, into: folder.appending(path: "other/benchlog.sqlite"))
        }
    }

    @Test func crcMatchesTheStandard() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}
