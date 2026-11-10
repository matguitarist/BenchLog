import Foundation
import Testing
@testable import BenchLogKit

@Suite struct TicketNumberTests {
    @Test func printsFourDigitsWithAHash() {
        #expect(TicketNumber(1).text == "#0001")
        #expect(TicketNumber(42).text == "#0042")
        #expect(TicketNumber(12345).text == "#12345")
    }

    @Test func readsWhatPeopleType() {
        #expect(TicketNumber(parsing: "#0042") == TicketNumber(42))
        #expect(TicketNumber(parsing: "42") == TicketNumber(42))
        #expect(TicketNumber(parsing: " #7 ") == TicketNumber(7))
        #expect(TicketNumber(parsing: "#") == nil)
        #expect(TicketNumber(parsing: "0") == nil)
        #expect(TicketNumber(parsing: "4a") == nil)
    }

    @Test func nextIsOneMore() {
        #expect(TicketNumber(9).next() == TicketNumber(10))
    }
}

@Suite struct LibraryTests {
    @Test func aNewLibraryStartsAtTicketOne() throws {
        let library = try Library()
        #expect(try library.appliedMigrations() == ["v1-meta", "v2-core", "v3-attachments", "v4-parts", "v5-guides", "v6-billing", "v7-search", "v8-approval", "v9-shop", "v10-credit-notes", "v11-sales", "v12-stock"])
        #expect(try library.metaValue("nextTicketNumber") == "1")
    }

    @Test func aLibraryOnDiskReopens() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "BenchLogTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "benchlog.sqlite")
        _ = try Library(databaseURL: url)
        let again = try Library(databaseURL: url)
        #expect(again.filesURL.lastPathComponent == "Files")
        #expect(try again.appliedMigrations() == ["v1-meta", "v2-core", "v3-attachments", "v4-parts", "v5-guides", "v6-billing", "v7-search", "v8-approval", "v9-shop", "v10-credit-notes", "v11-sales", "v12-stock"])
    }
}
