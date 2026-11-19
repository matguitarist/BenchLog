import Foundation

// .tvw (Teleplan TestView), ported from BoardViewCraft's reader (crates/bvc-core/src/parser/tvw.rs,
// https://github.com/elbuit/BoardViewCraft, MIT or Apache-2.0). Two kinds:
//
// Text: a .brd (Test_Link) layout with digits turned by 3 and letters by 10.
//
// Binary: "\x13O95w-28ps49m 02v9o." then version 1, little-endian. Its layout isn't published,
// so the reader looks for the records it knows, in hundredths of a mil:
//
//   a layer         a Pascal string "TOP" or "BOTTOM", then somewhere after it a pin table:
//                   u32 first, u32 count, u32 gap, then count pins
//   a pin           u32 net, u32 local, i32 x, i32 y, u8, u8 extra, [extra fields], u8
//   a component     Pascal refdes, i32 box x1 y1 x2 y2, i32 center x y, u32 rotation,
//                   u32 footprint, u32 class, 8 zero bytes, 01 + Pascal value, Pascal comment
//                   twice, Pascal footprint, Pascal code, u32 0, u32 pin count, u32 side
//                   (2 top, 11 bottom), u32 0, then per pin: u32 pad (pin table index × 8),
//                   u32, u32 index, Pascal name, u32
//   the nets        u32 count twice, then that many Pascal names, in the last quarter

enum TVW {
    static let magic: [UInt8] = [0x13] + Array("O95w-28ps49m 02v9o.".utf8) + [1, 0, 0, 0]

    static func isBinary(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 64 && bytes.starts(with: magic)
    }

    /// Undoes the text cipher: digits back by 3, letters back by 10.
    static func unrotate(_ bytes: some Sequence<UInt8>) -> [UInt8] {
        bytes.map { b in
            switch b {
            case 0x30...0x39: (b - 0x30 + 7) % 10 + 0x30
            case 0x61...0x7A: (b - 0x61 + 16) % 26 + 0x61
            case 0x41...0x5A: (b - 0x41 + 16) % 26 + 0x41
            default: b
            }
        }
    }

    /// The text cipher, for tests.
    static func rotate(_ text: String) -> Data {
        Data(text.utf8.map { b in
            switch b {
            case 0x30...0x39: (b - 0x30 + 3) % 10 + 0x30
            case 0x61...0x7A: (b - 0x61 + 10) % 26 + 0x61
            case 0x41...0x5A: (b - 0x41 + 10) % 26 + 0x41
            default: b
            }
        })
    }

    struct Pin: Equatable {
        var net: UInt32
        var local: UInt32
        var x: Int32
        var y: Int32
    }

    struct Component {
        var name: String
        var box: (x1: Int32, y1: Int32, x2: Int32, y2: Int32)
        var center: (x: Int32, y: Int32)
        var footprintIndex: UInt32
        var side: UInt32
        var pads: [UInt32]
    }

    static let maxCoordinate: Int64 = 5_000_000

    // MARK: Reading bytes

    struct Reader {
        let b: [UInt8]

        func u32(_ o: Int) -> UInt32? {
            guard o >= 0, o + 4 <= b.count else { return nil }
            return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
        }

        func i32(_ o: Int) -> Int32? { u32(o).map { Int32(bitPattern: $0) } }

        func u8(_ o: Int) -> UInt8? { b.indices.contains(o) ? b[o] : nil }

        /// A pin record at `o`, and where the next one starts.
        func pin(at o: Int, end: Int) -> (Pin, Int)? {
            var o = o
            guard o + 18 <= end, let net = u32(o), let local = u32(o + 4), let x = i32(o + 8), let y = i32(o + 12),
                  let extra = u8(o + 17) else { return nil }
            o += 18
            if extra != 0 {
                guard o + 3 <= end, let a = u8(o) else { return nil }
                o += 1
                if a == 1 { guard o + 12 <= end else { return nil }; o += 12 }
                guard let bb = u8(o) else { return nil }
                o += 1
                if bb != 0 { guard o + 16 <= end else { return nil }; o += 16 }
                guard let c = u8(o) else { return nil }
                o += 1
                if c != 0 { guard o + 16 <= end else { return nil }; o += 16 }
            }
            guard o + 1 <= end else { return nil }
            return (Pin(net: net, local: local, x: x, y: y), o + 1)
        }

        func plausible(_ p: Pin) -> Bool {
            abs(Int64(p.x)) <= maxCoordinate && abs(Int64(p.y)) <= maxCoordinate && p.net < 1 << 31 && p.local <= 0x100000
        }

        func looksLikePinTable(at o: Int, end: Int) -> Bool {
            guard o + 30 <= end, o + 16 <= b.count,
                  b[o + 3] == 0, b[o + 7] == 0, b[o + 11] == 0, b[o + 15] == 0,
                  let first = u32(o), let count = u32(o + 4), (1...100_000).contains(count), first <= 100_000,
                  let x = i32(o + 20), let y = i32(o + 24) else { return false }
            return abs(Int64(x)) <= maxCoordinate && abs(Int64(y)) <= maxCoordinate
        }

        func pinTable(at o: Int, end: Int) -> [Pin]? {
            guard o + 12 <= end, let first = u32(o), let count = u32(o + 4) else { return nil }
            guard count > 0, count <= 200_000, first <= 200_000 else { return nil }
            var pins: [Pin] = []
            var cursor = o + 12
            for _ in 0..<count {
                guard let (pin, next) = pin(at: cursor, end: end), plausible(pin) else { break }
                pins.append(pin)
                cursor = next
            }
            guard !pins.isEmpty else { return nil }
            if count >= 10, Double(pins.count) < max(2, Double(count) * 0.5) { return nil }
            return pins
        }

        /// The longest pin table that starts between `start` and `end`, trying every fourth byte.
        func bestPinTable(from start: Int, to end: Int, regionEnd: Int) -> [Pin] {
            var best: [Pin] = []
            var o = start
            while o < end {
                if looksLikePinTable(at: o, end: regionEnd), let pins = pinTable(at: o, end: regionEnd), pins.count > best.count {
                    best = pins
                }
                o += 4
            }
            return best
        }

        /// Printable Pascal strings one after another from `start`.
        func pascalRun(from start: Int) -> [String] {
            var names: [String] = []
            var o = start
            while o < b.count {
                let n = Int(b[o])
                guard n > 0, n <= 64, o + 1 + n <= b.count else { break }
                let s = b[(o + 1)...(o + n)]
                guard s.allSatisfy({ (32...126).contains($0) }) else { break }
                names.append(String(decoding: s, as: UTF8.self))
                o += 1 + n
            }
            return names
        }

        /// The net names: "count, count, names" in the last quarter, else the longest run there.
        func netNames() -> [String] {
            let start = max(b.count - (b.count / 4 + 4096), 0)
            var o = start
            while o + 8 < b.count {
                if let c1 = u32(o), c1 > 0, c1 <= 100_000, u32(o + 4) == c1 {
                    let names = pascalRun(from: o + 8)
                    if names.count == Int(c1) { return names }
                }
                o += 1
            }
            var best: [String] = []
            o = start
            while o + 4 < b.count {
                let names = pascalRun(from: o)
                if !names.isEmpty, names.count >= best.count { best = names }
                o += 1
            }
            return best
        }

        static func isRefdes(_ body: ArraySlice<UInt8>) -> Bool {
            guard !body.isEmpty, body.count <= 10 else { return false }
            var letters = 0, digits = 0
            for c in body {
                let isLetter = (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
                let isDigit = (0x30...0x39).contains(c)
                if digits == 0, isLetter { letters += 1; if letters > 5 { return false } }
                else if isDigit, letters > 0 { digits += 1; if digits > 5 { return false } }
                else { return false }
            }
            return letters > 0 && digits > 0
        }

        func components() -> [Component] {
            var starts: [Int] = []
            let n = b.count
            var i = 0
            while i + 40 < n {
                defer { i += 1 }
                let length = Int(b[i])
                guard (2...8).contains(length), i + 1 + length + 32 <= n else { continue }
                let body = b[(i + 1)...(i + length)]
                guard Self.isRefdes(body) else { continue }
                let o = i + 1 + length
                guard let x1 = i32(o), let y1 = i32(o + 4), let x2 = i32(o + 8), let y2 = i32(o + 12),
                      let cx = i32(o + 16), let cy = i32(o + 20) else { continue }
                guard [x1, y1, x2, y2, cx, cy].allSatisfy({ abs(Int64($0)) <= 10_000_000 }), x1 < x2, y1 < y2 else { continue }
                let w = x2 - x1, h = y2 - y1
                guard (100...5_000_000).contains(w), (100...5_000_000).contains(h) else { continue }
                guard x1 - w / 2 <= cx, cx <= x2 + w / 2, y1 - h / 2 <= cy, cy <= y2 + h / 2 else { continue }
                starts.append(i)
            }
            return starts.enumerated().compactMap { k, start in
                component(at: start, end: k + 1 < starts.count ? starts[k + 1] : n)
            }
        }

        func component(at start: Int, end: Int) -> Component? {
            var o = start
            let length = Int(b[o])
            o += 1
            guard (1...12).contains(length), o + length + 32 <= end else { return nil }
            let name = String(decoding: b[o..<(o + length)], as: UTF8.self)
            o += length
            guard let x1 = i32(o), let y1 = i32(o + 4), let x2 = i32(o + 8), let y2 = i32(o + 12),
                  let cx = i32(o + 16), let cy = i32(o + 20), let footprint = u32(o + 28) else { return nil }
            o += 36
            guard o + 8 <= end else { return nil }
            o += 8
            // Value (after 01), comment, comment again, footprint, part code.
            var stringsOK = true
            if o + 2 <= end {
                let n = Int(b[o + 1])
                if b[o] == 1, n <= 64, o + 2 + n <= end { o += 2 + n } else { stringsOK = false }
            }
            for _ in 0..<4 where stringsOK && o + 1 <= end {
                let n = Int(b[o])
                if n <= 64, o + 1 + n <= end { o += 1 + n } else { stringsOK = false }
            }
            if o + 4 <= end { o += 4 }
            var side: UInt32 = 2
            var pads: [UInt32] = []
            if o + 4 <= end {
                let count = u32(o).map { $0 <= 10_000 ? $0 : 0 } ?? 0
                o += 4
                if o + 8 <= end {
                    side = u32(o) ?? 2
                    o += 8
                    for _ in 0..<count {
                        guard o + 13 <= end, let pad = u32(o) else { break }
                        o += 12
                        let n = Int(b[o])
                        o += 1
                        guard n <= 16, o + n + 4 <= end else { break }
                        o += n + 4
                        pads.append(pad)
                    }
                }
            }
            // Layer names (L1…L15) look like reference designators; an inductor has pins.
            if pads.isEmpty, name.count <= 3, name.first == "L", name.dropFirst().allSatisfy(\.isNumber) { return nil }
            return Component(name: name, box: (x1, y1, x2, y2), center: (cx, cy), footprintIndex: footprint,
                             side: side, pads: pads)
        }

        /// Each "TOP"/"BOTTOM" Pascal string, in file order.
        func layers() -> [(offset: Int, top: Bool)] {
            var found: [(Int, Bool)] = []
            for name in ["TOP", "BOTTOM", "top", "bottom"] {
                let needle = [UInt8(name.count)] + Array(name.utf8)
                var o = 0
                while o + needle.count <= b.count {
                    if b[o] == needle[0], Array(b[o..<(o + needle.count)]) == needle { found.append((o, name.uppercased() == "TOP")) }
                    o += 1
                }
            }
            return found.sorted { $0.0 < $1.0 }
        }
    }
}

extension BoardFile {
    static func readTVW(_ bytes: [UInt8]) throws -> Board {
        let r = TVW.Reader(b: bytes)
        let nets = r.netNames()
        let components = r.components()
        let layers = r.layers()
        let tail = bytes.count - bytes.count / 4
        var top: [TVW.Pin] = [], bottom: [TVW.Pin] = []
        for (k, layer) in layers.enumerated() {
            let end = k + 1 < layers.count ? layers[k + 1].offset : tail
            guard layer.offset < end else { continue }
            let pins = r.bestPinTable(from: layer.offset, to: max(end - 30, layer.offset), regionEnd: end)
            if layer.top, pins.count > top.count { top = pins }
            if !layer.top, pins.count > bottom.count { bottom = pins }
        }
        if top.isEmpty, bottom.isEmpty {
            top = r.bestPinTable(from: 64, to: max(tail - 30, 64), regionEnd: tail)
        }

        func net(_ p: TVW.Pin) -> String { Int(p.net) < nets.count ? nets[Int(p.net)] : "" }
        func at(_ p: TVW.Pin) -> BoardPoint { BoardPoint(x: Double(p.x) / 100, y: Double(p.y) / 100) }

        var parts: [(name: String, side: BoardSide, isThroughHole: Bool)] = []
        var outlines: [[BoardPoint]] = []
        var boxes: [BoardRect] = []
        var pins: [BoardPin] = []
        var claimedTop: Set<Int> = [], claimedBottom: Set<Int> = []
        for c in components {
            let side: BoardSide = c.side == 2 ? .top : c.side == 11 ? .bottom : c.footprintIndex & 1 == 1 ? .top : .bottom
            let index = parts.count
            parts.append((c.name, side, false))
            let box = BoardRect(minX: Double(c.box.x1) / 100, minY: Double(c.box.y1) / 100,
                                maxX: Double(c.box.x2) / 100, maxY: Double(c.box.y2) / 100)
            boxes.append(box)
            outlines.append([BoardPoint(x: box.minX, y: box.minY), BoardPoint(x: box.maxX, y: box.minY),
                             BoardPoint(x: box.maxX, y: box.maxY), BoardPoint(x: box.minX, y: box.maxY)])
            func distance(_ p: TVW.Pin) -> Int64 {
                let dx = Int64(p.x) - Int64(c.center.x), dy = Int64(p.y) - Int64(c.center.y)
                return dx * dx + dy * dy
            }
            for pad in c.pads {
                let i = Int(pad / 8)
                let t = top.indices.contains(i) ? top[i] : nil
                let b = bottom.indices.contains(i) ? bottom[i] : nil
                let pin: TVW.Pin
                if let t, b == nil || distance(t) <= distance(b!) {
                    claimedTop.insert(i); pin = t
                } else if let b {
                    claimedBottom.insert(i); pin = b
                } else { continue }
                pins.append(BoardPin(position: at(pin), part: index, number: 0, net: net(pin)))
            }
        }
        // A pin no component claimed belongs to the part whose box it is in, on its side.
        for (list, claimed, side) in [(top, claimedTop, BoardSide.top), (bottom, claimedBottom, .bottom)] {
            for (i, pin) in list.enumerated() where !claimed.contains(i) {
                let p = at(pin)
                if let owner = parts.indices.first(where: { parts[$0].side == side && boxes[$0].insetBy(-5).contains(p) }) {
                    pins.append(BoardPin(position: p, part: owner, number: 0, net: net(pin)))
                }
            }
        }
        guard !parts.isEmpty else { throw BoardFileError.malformed(String(localized: "no parts")) }
        guard !pins.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }
        let outline = boxOutline(around: pins.map(\.position) + outlines.joined())
        return Board(outline: outline, parts: parts, pins: pins, testPoints: [], partOutlines: outlines)
    }
}
