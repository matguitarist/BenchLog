import CryptoKit
import Foundation

/// The secret that seals device passcodes before they leave a device (S-054). The server
/// only ever sees sealed text. Every device of a library needs the same key: people copy it
/// from Settings > Sync as a recovery code.
public struct LibraryKey: Sendable, Equatable {
    let key: SymmetricKey

    public static func == (lhs: LibraryKey, rhs: LibraryKey) -> Bool { lhs.data == rhs.data }

    public init() { key = SymmetricKey(size: .bits256) }

    public init?(data: Data) {
        guard data.count == 32 else { return nil }
        key = SymmetricKey(data: data)
    }

    public var data: Data { key.withUnsafeBytes { Data($0) } }

    // MARK: Recovery code: base32 in groups of four, such as ABCD-EFGH-…

    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")   // no I, O, 0, 1

    public var recoveryCode: String {
        var bits = 0, value = 0, characters: [Character] = []
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                characters.append(Self.alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
            }
        }
        if bits > 0 { characters.append(Self.alphabet[(value << (5 - bits)) & 31]) }
        return stride(from: 0, to: characters.count, by: 4).map { String(characters[$0..<min($0 + 4, characters.count)]) }
            .joined(separator: "-")
    }

    /// Reads a recovery code as typed: any case, with or without dashes and spaces.
    public init?(recoveryCode: String) {
        var bits = 0, value = 0
        var bytes: [UInt8] = []
        for character in recoveryCode.uppercased() where character != "-" && !character.isWhitespace {
            guard let index = Self.alphabet.firstIndex(of: character) else { return nil }
            value = (value << 5) | index
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
        }
        self.init(data: Data(bytes.prefix(32)))
        guard bytes.count == 32 else { return nil }
    }

    // MARK: Sealing

    static let prefix = "sealed:v1:"

    func seal(_ text: String) throws -> String {
        guard let combined = try AES.GCM.seal(Data(text.utf8), using: key).combined else { throw SyncError.wrongKey }
        return Self.prefix + combined.base64EncodedString()
    }

    func open(_ sealed: String) throws -> String {
        guard sealed.hasPrefix(Self.prefix), let combined = Data(base64Encoded: String(sealed.dropFirst(Self.prefix.count))) else {
            return sealed   // never sealed: a passcode from before S-054
        }
        do {
            return String(decoding: try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key), as: UTF8.self)
        } catch {
            throw SyncError.wrongKey
        }
    }

    /// Seals the passcode of every device row; other rows go as they are.
    func sealed(_ rows: [SyncRow]) throws -> [SyncRow] {
        try rows.map { row in
            guard row.table == "device", let passcode = row.data["passcode"]?.string, !passcode.isEmpty else { return row }
            var row = row
            row.data["passcode"] = .string(try seal(passcode))
            return row
        }
    }

    func opened(_ rows: [SyncRow]) throws -> [SyncRow] {
        try rows.map { row in
            guard row.table == "device", let passcode = row.data["passcode"]?.string, !passcode.isEmpty else { return row }
            var row = row
            row.data["passcode"] = .string(try open(passcode))
            return row
        }
    }

    /// A sealed known text the server keeps, so a joining device can check its key first.
    static let checkText = "BenchLog library key"
}
