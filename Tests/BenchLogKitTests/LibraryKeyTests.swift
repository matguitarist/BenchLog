import Foundation
import Testing
@testable import BenchLogKit

/// S-054 Passcodes stay private on the server.
@Suite struct LibraryKeyTests {
    let server = MemoryServer()
    let key = LibraryKey()

    @Test func theRecoveryCodeReadsBackAsTyped() throws {
        let code = key.recoveryCode
        #expect(code.count == 52 + 12)   // 52 characters in 13 groups of four
        #expect(LibraryKey(recoveryCode: code) == key)
        #expect(LibraryKey(recoveryCode: code.lowercased().replacingOccurrences(of: "-", with: " ")) == key)
        #expect(LibraryKey(recoveryCode: "ABCD-EFGH") == nil)
        #expect(LibraryKey(recoveryCode: String(code.dropLast()) + "0") == nil)   // 0 is not in the alphabet
    }

    @Test func theServerOnlySeesSealedPasscodes() async throws {
        let mac = try Library()
        let customer = try mac.save(Customer(name: "Léa"))
        let device = try mac.save(Device(customerId: customer.id, category: .phone, brand: "Apple", model: "iPhone 13", passcode: "482916"))
        try await SyncEngine(library: mac, transport: server, key: key).connect()
        let stored = try #require(server.row("device", device.id.stored)?.data["passcode"]?.string)
        #expect(stored.hasPrefix("sealed:v1:") && !stored.contains("482916"))
        #expect(try mac.device(device.id)?.passcode == "482916")   // this Mac keeps it as typed

        let other = try Library()
        try await SyncEngine(library: other, transport: server, key: key).connect(join: true)
        #expect(try other.device(device.id)?.passcode == "482916")
    }

    @Test func joiningWithTheWrongKeyChangesNothing() async throws {
        let mac = try Library()
        try mac.save(Customer(name: "Léa"))
        try await SyncEngine(library: mac, transport: server, key: key).connect()
        let other = try Library()
        let mine = try other.save(Customer(name: "Mine"))
        await #expect(throws: SyncError.wrongKey) {
            try await SyncEngine(library: other, transport: server, key: LibraryKey()).connect(join: true)
        }
        #expect(try other.customers().map(\.id) == [mine.id])
    }
}
