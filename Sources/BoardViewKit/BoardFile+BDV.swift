import Foundation

// .bdv (HONHAN BoardViewer), ported from BoardViewCraft's reader
// (crates/bvc-core/src/parser/bdv.rs, https://github.com/elbuit/BoardViewCraft, MIT or Apache-2.0).
// Each byte is a key minus the plain byte; line breaks stay as they are. The key starts at 160
// and runs to 285, then starts over at 159. It moves on in one of two ways:
//
//   by byte: after every byte that isn't a line break; the text is a .brd (Test_Link) layout.
//   by line: after every line; the text is a fixture listing, and the file starts "dd:"
//            (its first line, "<<format.asc>>", encoded):
//
//     <<format.asc>>           then outline points "x y radius", in inches
//     <<pins.asc>>
//     Part U1 (T)              (B) for the bottom
//     id name x y layer net    a pin, in inches; net "(NC)" is none
//     $1 x y …  (T) … net      a test point

enum BDV {
    static let lineKeyedMagic: [UInt8] = Array("dd:".utf8)

    static func decodeByByte(_ bytes: [UInt8]) -> [UInt8] {
        var key = 160
        return bytes.map { b in
            if b == 0x0A || b == 0x0D { return b }
            defer { key = key >= 285 ? 159 : key + 1 }
            return UInt8(truncatingIfNeeded: key - Int(b))
        }
    }

    static func decodeByLine(_ bytes: [UInt8]) -> [UInt8] {
        var key = 160
        return bytes.map { b in
            if b == 0x0A { key = key >= 285 ? 159 : key + 1 }
            if b == 0x0A || b == 0x0D { return b }
            return UInt8(truncatingIfNeeded: key - Int(b))
        }
    }

    /// Encodes plain text the way the decoders expect; the tests use it.
    static func encode(_ text: String, byLine: Bool) -> Data {
        var key = 160
        return Data(Array(text.utf8).map { b in
            if b == 0x0A || b == 0x0D {
                if byLine, b == 0x0A { key = key >= 285 ? 159 : key + 1 }
                return b
            }
            defer { if !byLine { key = key >= 285 ? 159 : key + 1 } }
            return UInt8(truncatingIfNeeded: key - Int(b))
        })
    }
}

extension BoardFile {
    /// Reads the line-keyed listing. Inches become mils, like a .brd.
    static func readBDVFixture(_ text: String) throws -> Board {
        var outline: [BoardPoint] = []
        var parts: [(name: String, side: BoardSide, isThroughHole: Bool)] = []
        var pins: [BoardPin] = []
        var testPoints: [BoardTestPoint] = []
        var inOutline = false
        var inPart = false

        func point(_ x: Substring, _ y: Substring) -> BoardPoint? {
            guard let x = Double(x), let y = Double(y) else { return nil }
            return BoardPoint(x: x * 1000, y: y * 1000)
        }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let fields = line.split(whereSeparator: \.isWhitespace)
            if line.hasPrefix("<<") {
                inOutline = line == "<<format.asc>>"
                inPart = false
            } else if line.contains("Board Outline Contour") {
                inOutline = true
                inPart = false
            } else if fields.first == "Part" {
                inOutline = false
                guard fields.count >= 2 else { continue }
                let side: BoardSide = fields.count >= 3 && fields[2].contains("B") ? .bottom : .top
                parts.append((String(fields[1]), side, false))
                inPart = true
            } else if line.hasPrefix("$") {
                inOutline = false
                guard fields.count >= 4, let at = point(fields[1], fields[2]) else { continue }
                testPoints.append(BoardTestPoint(position: at, side: line.contains("(B)") ? .bottom : .top,
                                                 net: String(fields.last ?? ""), probe: Int(fields[0].dropFirst()) ?? 0))
            } else if inPart, fields.count >= 6 {
                guard let at = point(fields[2], fields[3]) else { continue }
                let net = fields[5] == "(NC)" ? "" : String(fields[5])
                pins.append(BoardPin(position: at, part: parts.count - 1, number: 0, net: net))
            } else if inOutline, fields.count >= 2, let at = point(fields[0], fields[1]) {
                outline.append(at)
            }
        }

        guard !parts.isEmpty else { throw BoardFileError.malformed(String(localized: "no parts")) }
        guard !pins.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }
        return Board(outline: outline, parts: parts, pins: pins, testPoints: testPoints)
    }
}
