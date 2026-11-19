import Foundation

// .fz (Foxconn), ported from BoardViewCraft's readers (crates/bvc-core/src/parser/fz.rs and
// fz_zlib.rs, https://github.com/elbuit/BoardViewCraft, MIT or Apache-2.0).
//
// The file is the length of the text (4 bytes, little-endian), then the text compressed with
// zlib. Some files are also scrambled with a 16-byte sliding window and a 44-word key that
// isn't public: BenchLog reads those only when the key is set (`FZ.keyDefaultsKey`).
//
// The text holds sections of "!"-separated rows: "A!REFDES!…" names a section, "S!…" is a row.
//
//   UNIT: millimeters | inches       mils otherwise
//   REFDES    refdes!code!symbol!mirror!rotate     mirror YES is the bottom
//   NET_NAME  net!refdes!pinNumber!pinName!x!y!testPoint!radius
//   TESTVIA   TESTVIA!net!refdes!pinNumber!pinName!x!y!…     a test point

enum FZ {
    /// The UserDefaults key (and environment variable) that holds the scrambling key: 44 words
    /// separated by spaces or commas (decimal or 0x hex), or 176 bytes as hex.
    static let keyDefaultsKey = "BENCHLOG_FZ_KEY"

    /// zlib's header at offset 4: 78 9C, 78 DA, or 78 01.
    static func isCompressed(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 8 && bytes[4] == 0x78 && [0x9C, 0xDA, 0x01].contains(bytes[5])
    }

    /// The text inside a compressed .fz, or nil when the stream is damaged.
    static func inflate(_ bytes: [UInt8]) -> String? {
        // Foundation's .zlib is raw DEFLATE: skip the length and zlib's two header bytes.
        guard bytes.count > 6,
              let raw = try? (Data(bytes[6...]) as NSData).decompressed(using: .zlib) else { return nil }
        return String(decoding: raw as Data, as: UTF8.self)
    }

    /// Compresses text the way a .fz holds it; the sample board and tests use it.
    static func deflate(_ text: String) -> Data {
        let plain = Data(text.utf8)
        var out = Data()
        withUnsafeBytes(of: UInt32(plain.count).littleEndian) { out.append(contentsOf: $0) }
        out.append(contentsOf: [0x78, 0x9C])
        out.append((try? (plain as NSData).compressed(using: .zlib) as Data) ?? Data())
        withUnsafeBytes(of: adler32(plain).bigEndian) { out.append(contentsOf: $0) }
        return out
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    // MARK: Scrambled files

    static func littleEndianWord(_ bytes: [UInt8], at i: Int) -> UInt32 {
        let b0 = UInt32(bytes[i]), b1 = UInt32(bytes[i + 1]) << 8
        let b2 = UInt32(bytes[i + 2]) << 16, b3 = UInt32(bytes[i + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    private static func rotl(_ v: UInt32, _ s: UInt32) -> UInt32 {
        let s = s & 31
        return s == 0 ? v : (v << s) | (v >> (32 - s))
    }

    /// Undoes the sliding-window scrambling with a 44-word key.
    static func unscramble(_ cipher: [UInt8], key k: [UInt32]) -> [UInt8] {
        precondition(k.count == 44)
        var window = [UInt8](repeating: 0, count: 16)
        var n5: UInt32 = 0, n4: UInt32 = 0, n3: UInt32 = 0, n2: UInt32 = 0
        var out = [UInt8](repeating: 0, count: cipher.count)
        func word(_ i: Int) -> UInt32 { littleEndianWord(window, at: i) }
        for (i, b) in cipher.enumerated() {
            n4 &+= k[0]
            n2 &+= k[1]
            for r in 1...20 {
                let mix4 = rotl(n4 &* ((n4 << 1) &+ 1), 5)
                let mix2 = rotl(n2 &* ((n2 << 1) &+ 1), 5)
                let newN5 = rotl(n5 ^ mix4, mix2 & 0xFF) &+ k[r * 2]
                let newN3 = rotl(n3 ^ mix2, mix4 & 0xFF) &+ k[r * 2 + 1]
                n5 = n4
                n4 = newN3
                n3 = n2
                n2 = newN5
            }
            n5 &+= k[42]
            out[i] = b ^ UInt8(truncatingIfNeeded: n5)
            window.removeFirst()
            window.append(b)
            n5 = word(0); n4 = word(4); n3 = word(8); n2 = word(12)
        }
        return out
    }

    /// Reads a key: 44 words separated by spaces or commas, or 176 bytes as 352 hex digits.
    static func parseKey(_ raw: String) -> [UInt32]? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.contains(" ") || s.contains(",") {
            let tokens = s.split(whereSeparator: { $0 == " " || $0 == "," })
            guard tokens.count == 44 else { return nil }
            var words: [UInt32] = []
            for token in tokens {
                if let v = UInt32(token) { words.append(v) }
                else if let v = UInt32(token.hasPrefix("0x") ? token.dropFirst(2) : token, radix: 16) { words.append(v) }
                else { return nil }
            }
            return words
        }
        guard s.count == 352 else { return nil }
        var bytes: [UInt8] = []
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return (0..<44).map { littleEndianWord(bytes, at: $0 * 4) }
    }

    /// The key from the environment or UserDefaults, if one is set.
    static func storedKey() -> [UInt32]? {
        let raw = ProcessInfo.processInfo.environment[keyDefaultsKey] ?? UserDefaults.standard.string(forKey: keyDefaultsKey)
        return raw.flatMap(parseKey)
    }
}

extension BoardFile {
    /// Reads the text of a .fz. Through-hole parts aren't marked; they show on their side.
    static func readFZ(_ text: String) throws -> Board {
        var scale = 1.0
        for line in text.split(whereSeparator: \.isNewline).prefix(50) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("UNIT:") else { continue }
            let unit = l.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased()
            if unit.hasPrefix("millimeter") || unit.hasPrefix("mm") { scale = 1000 / 25.4 }
            else if unit.hasPrefix("inch") { scale = 1000 }
        }

        var section = ""
        var parts: [(name: String, side: BoardSide, isThroughHole: Bool)] = []
        var partIndex: [String: Int] = [:]
        var pins: [BoardPin] = []
        var testPoints: [BoardTestPoint] = []

        func part(_ name: String, side: BoardSide) -> Int {
            if let index = partIndex[name] { return index }
            parts.append((name, side, false))
            partIndex[name] = parts.count - 1
            return parts.count - 1
        }

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("A!") || line.hasPrefix("F!") || line.hasPrefix("SECTION!") {
                let fields = line.split(separator: "!", omittingEmptySubsequences: false)
                if fields.count >= 2 { section = fields[1].trimmingCharacters(in: .whitespaces) }
                continue
            }
            guard line.hasPrefix("S!") else { continue }
            let v = line.dropFirst(2).split(separator: "!", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            switch section {
            case "REFDES":
                guard let name = v.first, !name.isEmpty else { continue }
                let mirrored = v.count >= 4 && v[3].caseInsensitiveCompare("YES") == .orderedSame
                _ = part(name, side: mirrored ? .bottom : .top)
            case "NET_NAME":
                guard v.count >= 6 else { continue }
                let x = (Double(v[4]) ?? 0) * scale, y = (Double(v[5]) ?? 0) * scale
                let owner = part(v[1], side: .top)
                pins.append(BoardPin(position: BoardPoint(x: x, y: y), part: owner, number: 0, net: v[0]))
            case "TESTVIA":
                guard v.count >= 7 else { continue }
                let x = (Double(v[5]) ?? 0) * scale, y = (Double(v[6]) ?? 0) * scale
                testPoints.append(BoardTestPoint(position: BoardPoint(x: x, y: y), side: .top, net: v[1],
                                                 probe: testPoints.count + 1))
            default:
                continue
            }
        }
        guard !parts.isEmpty else { throw BoardFileError.malformed(String(localized: "no parts")) }
        guard !pins.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }
        let outline = boxOutline(around: pins.map(\.position) + testPoints.map(\.position))
        return Board(outline: outline, parts: parts, pins: pins, testPoints: testPoints)
    }
}
