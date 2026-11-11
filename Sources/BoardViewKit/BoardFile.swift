import Foundation

// Reads boardview files into a Board.
//
// .brd (the OpenBoardView "Test_Link" layout), plain or substitution-encoded. The rules
// follow BoardViewCraft's reader (crates/bvc-core/src/parser/brd.rs and test_link.rs,
// https://github.com/elbuit/BoardViewCraft, MIT or Apache-2.0), which follows OpenBoardView's
// BRDFile.cpp:
//
//   str_length: …            ignored
//   var_data:                counts of outline points, parts, pins, test points
//   Format:   x y            the outline
//   Parts:    name type end  type: 1, 4–7 top; 2 or 8+ bottom; (type & 0x0C) != 0 is SMD
//   Pins:     x y probe part [net]   part is 1-based
//   Nails:    probe x y side net    side 1 is top

public enum BoardFileError: Error, Equatable, LocalizedError {
    /// A format BenchLog does not read yet.
    case unsupported(String)
    /// The file says it is a .brd but its sections are missing or broken.
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let format):
            String(localized: "BenchLog can't read \(format) boards yet.")
        case .malformed(let detail):
            String(localized: "The board file is damaged: \(detail).")
        }
    }
}

public enum BoardFile {
    /// Extensions the viewer opens. Other boardview files open in their default app.
    public static let readableExtensions: Set<String> = ["brd"]

    public static func canRead(fileName: String) -> Bool {
        readableExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    /// The first bytes of a substitution-encoded .brd.
    static let encodedMagic: [UInt8] = [0x23, 0xE2, 0x63, 0x28]

    public static func read(_ data: Data) throws -> Board {
        let bytes = [UInt8](data)
        let text: String
        if bytes.starts(with: encodedMagic) {
            text = String(decoding: decode(bytes), as: UTF8.self)
        } else {
            text = String(decoding: bytes, as: UTF8.self)
        }
        guard text.contains("var_data:") else {
            if text.hasPrefix("BRDOUT:") { throw BoardFileError.unsupported("BRD2") }
            throw BoardFileError.unsupported(String(localized: "this kind of .brd"))
        }
        return try readTestLink(text)
    }

    /// Undoes the substitution: each byte is rotated left by two and inverted. Line breaks
    /// and zeros are left as they are.
    static func decode(_ bytes: [UInt8]) -> [UInt8] {
        bytes.map { b in
            b == 0x0D || b == 0x0A || b == 0 ? b : ~((b >> 6) | (b << 2))
        }
    }

    /// Encodes plain .brd text the way the decoder expects; the sample board and tests use it.
    public static func encode(_ text: String) -> Data {
        Data(Array(text.utf8).map { b in
            if b == 0x0D || b == 0x0A || b == 0 { return b }
            let inverted = ~b
            return (inverted >> 2) | (inverted << 6)
        })
    }

    private static let sections = ["str_length:", "var_data:", "Format:", "Parts:", "Pins:", "Nails:"]

    static func readTestLink(_ text: String) throws -> Board {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func rows(after marker: String, count: Int?) -> [[Substring]] {
            guard let start = lines.firstIndex(where: { $0.hasPrefix(marker) }) else { return [] }
            var result: [[Substring]] = []
            var index = start + 1
            while index < lines.count {
                let line = lines[index]
                if sections.contains(where: { line.hasPrefix($0) }) { break }
                if !line.isEmpty { result.append(line.split(whereSeparator: \.isWhitespace)) }
                if let count, result.count == count { break }
                index += 1
            }
            return result
        }

        guard let counts = rows(after: "var_data:", count: 1).first?.compactMap({ Int($0) }), counts.count >= 4 else {
            throw BoardFileError.malformed(String(localized: "no part and pin counts"))
        }

        let outline = rows(after: "Format:", count: counts[0]).compactMap { row -> BoardPoint? in
            guard row.count >= 2, let x = Double(row[0]), let y = Double(row[1]) else { return nil }
            return BoardPoint(x: x, y: y)
        }

        let parts = rows(after: "Parts:", count: counts[1]).compactMap { row -> (name: String, side: BoardSide, isThroughHole: Bool)? in
            guard row.count >= 2, let type = Int(row[1]) else { return nil }
            let side: BoardSide = type == 2 || type >= 8 ? .bottom : .top
            return (String(row[0]), side, type & 0x0C == 0)
        }
        guard !parts.isEmpty else { throw BoardFileError.malformed(String(localized: "no parts")) }

        let pins = rows(after: "Pins:", count: counts[2]).compactMap { row -> BoardPin? in
            guard row.count >= 4, let x = Double(row[0]), let y = Double(row[1]), let part = Int(row[3]),
                  part >= 1, part <= parts.count else { return nil }
            let net = row.count >= 5 ? String(row[4]) : ""
            return BoardPin(position: BoardPoint(x: x, y: y), part: part - 1, number: 0, net: net)
        }
        guard !pins.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }

        let testPoints = rows(after: "Nails:", count: counts[3]).compactMap { row -> BoardTestPoint? in
            guard row.count >= 5, let probe = Int(row[0]), let x = Double(row[1]), let y = Double(row[2]),
                  let side = Int(row[3]) else { return nil }
            return BoardTestPoint(position: BoardPoint(x: x, y: y), side: side == 1 ? .top : .bottom,
                                  net: String(row[4]), probe: probe)
        }

        return Board(outline: outline, parts: parts, pins: pins, testPoints: testPoints)
    }
}
