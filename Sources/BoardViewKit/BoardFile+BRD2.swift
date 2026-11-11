import Foundation

// BRD2, OpenBoardView's second text layout, ported from BoardViewCraft's reader
// (crates/bvc-core/src/parser/brd2.rs, https://github.com/elbuit/BoardViewCraft, MIT or Apache-2.0):
//
//   BRDOUT: count width height   then count outline points "x y"
//   NETS: count                  then "id name"; "UNCONNECTED" is no net
//   PARTS: count                 then "name x1 y1 x2 y2 firstPin side"; side 1 top, 2 bottom, else both
//   PINS: count                  then "x y netID side"; a part's pins run to the next part's first pin
//   NAILS: count                 then "probe x y netID side"; side 1 top, else bottom

extension BoardFile {
    private static let brd2Sections = ["BRDOUT:", "NETS:", "PARTS:", "PINS:", "NAILS:"]

    static func readBRD2(_ text: String) throws -> Board {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        /// The rows after a section header, up to its count or the next header. Nil when the
        /// header is missing.
        func rows(_ marker: String) -> [[Substring]]? {
            guard let start = lines.firstIndex(where: { $0.hasPrefix(marker) }) else { return nil }
            let count = lines[start].dropFirst(marker.count).split(whereSeparator: \.isWhitespace).first.flatMap { Int($0) } ?? 0
            var result: [[Substring]] = []
            var index = start + 1
            while index < lines.count, result.count < count {
                let line = lines[index]
                if brd2Sections.contains(where: { line.hasPrefix($0) }) { break }
                result.append(line.split(whereSeparator: \.isWhitespace))
                index += 1
            }
            return result
        }

        let outline = (rows("BRDOUT:") ?? []).compactMap { row -> BoardPoint? in
            guard row.count >= 2, let x = Double(row[0]), let y = Double(row[1]) else { return nil }
            return BoardPoint(x: x, y: y)
        }

        var nets: [Int: String] = [:]
        for row in rows("NETS:") ?? [] {
            guard let id = row.first.flatMap({ Int($0) }) else { continue }
            let name = row.dropFirst().joined(separator: " ")
            nets[id] = name == "UNCONNECTED" ? "" : name
        }

        guard let partRows = rows("PARTS:"), !partRows.isEmpty else {
            throw BoardFileError.malformed(String(localized: "no parts"))
        }
        var parts: [(name: String, side: BoardSide, isThroughHole: Bool)] = []
        var firstPins: [Int] = []
        for row in partRows {
            guard row.count >= 7 else { throw BoardFileError.malformed(String(localized: "a part line is cut short")) }
            let side = Int(row[6]) ?? 1
            parts.append((String(row[0]), side == 2 ? .bottom : .top, side != 1 && side != 2))
            firstPins.append(Int(row[5]) ?? 0)
        }

        let pinRows = rows("PINS:") ?? []
        guard !pinRows.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }
        // Files count pins from 0; a few count from 1. The first part starts on the first pin.
        let base = firstPins.first == 1 ? 1 : 0
        var pins: [BoardPin] = []
        pins.reserveCapacity(pinRows.count)
        for (k, first) in firstPins.enumerated() {
            let start = max(first - base, 0)
            let end = min(k + 1 < firstPins.count ? firstPins[k + 1] - base : pinRows.count, pinRows.count)
            guard start < end else { continue }
            for row in pinRows[start..<end] {
                guard row.count >= 3, let x = Double(row[0]), let y = Double(row[1]) else { continue }
                let net = Int(row[2]).flatMap { nets[$0] } ?? ""
                pins.append(BoardPin(position: BoardPoint(x: x, y: y), part: k, number: 0, net: net))
            }
        }
        guard !pins.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }

        let testPoints = (rows("NAILS:") ?? []).compactMap { row -> BoardTestPoint? in
            guard row.count >= 5, let probe = Int(row[0]), let x = Double(row[1]), let y = Double(row[2]) else { return nil }
            let net = Int(row[3]).flatMap { nets[$0] } ?? ""
            return BoardTestPoint(position: BoardPoint(x: x, y: y), side: Int(row[4]) == 1 ? .top : .bottom,
                                  net: net, probe: probe)
        }

        return Board(outline: outline, parts: parts, pins: pins, testPoints: testPoints)
    }
}
