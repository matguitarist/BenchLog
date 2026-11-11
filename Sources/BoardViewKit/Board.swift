import Foundation

// A printed circuit board as a boardview file describes it: an outline, parts, their pins,
// the net each pin is on, and test points. Units are the file's (mils for .brd), y up.
// No SwiftUI, AppKit, or PDFKit: the iPhone/iPad app and a standalone viewer can reuse it.

public enum BoardSide: String, Sendable, CaseIterable, Identifiable, Codable {
    case top, bottom

    public var id: String { rawValue }
    public var flipped: BoardSide { self == .top ? .bottom : .top }
}

public struct BoardPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct BoardRect: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The smallest rectangle around the points, or nil for none.
    public init?(around points: some Sequence<BoardPoint>) {
        var rect: BoardRect?
        for p in points {
            if rect == nil {
                rect = BoardRect(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
            } else {
                rect!.minX = min(rect!.minX, p.x)
                rect!.minY = min(rect!.minY, p.y)
                rect!.maxX = max(rect!.maxX, p.x)
                rect!.maxY = max(rect!.maxY, p.y)
            }
        }
        guard let rect else { return nil }
        self = rect
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var center: BoardPoint { BoardPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }

    public func insetBy(_ d: Double) -> BoardRect {
        BoardRect(minX: minX + d, minY: minY + d, maxX: maxX - d, maxY: maxY - d)
    }

    public func union(_ other: BoardRect) -> BoardRect {
        BoardRect(minX: min(minX, other.minX), minY: min(minY, other.minY),
                  maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }

    public func contains(_ p: BoardPoint) -> Bool {
        p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY
    }

    public func intersects(_ other: BoardRect) -> Bool {
        minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
    }
}

public struct BoardPart: Hashable, Sendable, Identifiable {
    /// Its index in `Board.parts`.
    public var id: Int
    /// The reference designator: "U7100", "C7130".
    public var name: String
    public var side: BoardSide
    /// Through-hole parts show their pins on both sides.
    public var isThroughHole: Bool
    /// Its pins, as indexes into `Board.pins`.
    public var pins: Range<Int>
    /// Around its pins, padded by the pin radius.
    public var bounds: BoardRect
    /// A pin's drawn radius: a little under half the closest two pins' distance.
    public var pinRadius: Double
}

public struct BoardPin: Hashable, Sendable {
    public var position: BoardPoint
    /// Its part, as an index into `Board.parts`.
    public var part: Int
    /// 1 for the part's first pin.
    public var number: Int
    /// "PPBUS_G3H"; empty when the file names no net.
    public var net: String
}

/// A test point (a "nail" in .brd files).
public struct BoardTestPoint: Hashable, Sendable {
    public var position: BoardPoint
    public var side: BoardSide
    public var net: String
    public var probe: Int
}

/// What is selected on a board.
public enum BoardSelection: Hashable, Sendable {
    case part(Int)
    case pin(Int)
    case net(String)
    /// A test point, as an index into `Board.testPoints`.
    case testPoint(Int)
}

/// A search result: a part or a net, by name.
public enum BoardMatch: Hashable, Sendable, Identifiable {
    case part(Int, name: String)
    case net(String, pins: Int)

    public var id: String {
        switch self {
        case .part(_, let name): "part:" + name
        case .net(let name, _): "net:" + name
        }
    }

    public var name: String {
        switch self {
        case .part(_, let name): name
        case .net(let name, _): name
        }
    }

    public var selection: BoardSelection {
        switch self {
        case .part(let index, _): .part(index)
        case .net(let name, _): .net(name)
        }
    }
}

public struct Board: Sendable {
    public let outline: [BoardPoint]
    public let parts: [BoardPart]
    public let pins: [BoardPin]
    public let testPoints: [BoardTestPoint]
    /// Around the outline, the pins, and the test points.
    public let bounds: BoardRect
    private let partByName: [String: Int]
    private let pinsByNet: [String: [Int]]
    private let testPointsByNet: [String: [Int]]
    /// A test point's drawn radius: the median pin radius, so it reads beside the pads.
    public let testPointRadius: Double
    /// Every named net, sorted.
    public let nets: [String]

    /// Builds the indexes. Pins must be grouped by part, in the order of `parts`; each part
    /// gets its range, bounds, and pin radius here.
    public init(outline: [BoardPoint], parts: [(name: String, side: BoardSide, isThroughHole: Bool)],
                pins: [BoardPin], testPoints: [BoardTestPoint]) {
        // Group pins by part, keeping their order within a part, and number them.
        var grouped = pins.enumerated().sorted { ($0.element.part, $0.offset) < ($1.element.part, $1.offset) }.map(\.element)
        var ranges = Array(repeating: 0..<0, count: parts.count)
        var start = 0
        while start < grouped.count {
            let part = grouped[start].part
            var end = start
            while end < grouped.count, grouped[end].part == part {
                grouped[end].number = end - start + 1
                end += 1
            }
            if parts.indices.contains(part) { ranges[part] = start..<end }
            start = end
        }

        var built: [BoardPart] = []
        built.reserveCapacity(parts.count)
        for (index, part) in parts.enumerated() {
            let range = ranges[index]
            let positions = grouped[range].map(\.position)
            let radius = Self.pinRadius(positions)
            let bounds = BoardRect(around: positions)?.insetBy(-radius) ?? BoardRect(minX: 0, minY: 0, maxX: 0, maxY: 0)
            built.append(BoardPart(id: index, name: part.name, side: part.side, isThroughHole: part.isThroughHole,
                                   pins: range, bounds: bounds, pinRadius: radius))
        }

        var byNet: [String: [Int]] = [:]
        for (index, pin) in grouped.enumerated() where !pin.net.isEmpty {
            byNet[pin.net, default: []].append(index)
        }
        var byName: [String: Int] = [:]
        for part in built where byName[part.name.uppercased()] == nil {
            byName[part.name.uppercased()] = part.id
        }

        var tpByNet: [String: [Int]] = [:]
        for (index, point) in testPoints.enumerated() where !point.net.isEmpty {
            tpByNet[point.net, default: []].append(index)
        }
        let radii = built.filter { !$0.pins.isEmpty }.map(\.pinRadius).sorted()

        let everything = outline + grouped.map(\.position) + testPoints.map(\.position)
        self.outline = outline
        self.parts = built
        self.pins = grouped
        self.testPoints = testPoints
        self.bounds = BoardRect(around: everything) ?? BoardRect(minX: 0, minY: 0, maxX: 1, maxY: 1)
        self.partByName = byName
        self.pinsByNet = byNet
        self.testPointsByNet = tpByNet
        self.testPointRadius = radii.isEmpty ? 10 : radii[radii.count / 2]
        self.nets = Set(byNet.keys).union(tpByNet.keys).sorted()
    }

    /// Three tenths of the shortest distance between two of a part's pins, so pads
    /// don't touch, kept between 2 and 20 mils. Large parts compare their first 256 pins.
    static func pinRadius(_ positions: [BoardPoint]) -> Double {
        guard positions.count > 1 else { return 10 }
        var shortest = Double.infinity
        let sample = positions.prefix(256)
        for (i, a) in sample.enumerated() {
            for b in positions[(i + 1)...] {
                let d = hypot(a.x - b.x, a.y - b.y)
                if d > 0, d < shortest { shortest = d }
            }
        }
        guard shortest.isFinite else { return 10 }
        return min(max(shortest * 0.3, 2), 20)
    }

    // MARK: Lookups

    /// A part by its name, ignoring case.
    public func part(named name: String) -> Int? {
        partByName[name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    /// The pins on a net, as indexes into `pins`.
    public func pins(onNet net: String) -> [Int] {
        pinsByNet[net] ?? []
    }

    /// The test points on a net, as indexes into `testPoints`.
    public func testPoints(onNet net: String) -> [Int] {
        testPointsByNet[net] ?? []
    }

    /// The test points a selection lights: those on the selected net, or the selected pin's.
    public func highlightedTestPoints(for selection: BoardSelection?) -> [Int] {
        switch selection {
        case .pin(let index): pins[index].net.isEmpty ? [] : testPoints(onNet: pins[index].net)
        case .net(let name): testPoints(onNet: name)
        case .testPoint(let index): testPoints[index].net.isEmpty ? [index] : testPoints(onNet: testPoints[index].net)
        case .part, nil: []
        }
    }

    /// A net by its name as the file spells it, ignoring case.
    public func net(named name: String) -> String? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if pinsByNet[wanted] != nil || testPointsByNet[wanted] != nil { return wanted }
        return nets.first { $0.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// The side a pin shows on: its part's, or both for a through-hole part.
    public func shows(pin index: Int, on side: BoardSide) -> Bool {
        let part = parts[pins[index].part]
        return part.isThroughHole || part.side == side
    }

    /// Ground nets ("GND", "GND_AUDIO") have hundreds of pins; the viewer draws them quieter.
    public static func isGround(_ net: String) -> Bool {
        let upper = net.uppercased()
        return upper == "GND" || upper.hasPrefix("GND_") || upper.hasSuffix("_GND") || upper == "VSS"
    }

    /// The pins a selection lights up: a part's pins, or every pin on the selected pin's or net's net.
    public func highlightedPins(for selection: BoardSelection?) -> [Int] {
        switch selection {
        case .part(let index): Array(parts[index].pins)
        case .pin(let index): pins[index].net.isEmpty ? [index] : pins(onNet: pins[index].net)
        case .net(let name): pins(onNet: name)
        case .testPoint(let index): testPoints[index].net.isEmpty ? [] : pins(onNet: testPoints[index].net)
        case nil: []
        }
    }

    /// The name to look for in the schematic: the part's, or the net's.
    public func schematicTerms(for selection: BoardSelection?) -> [String] {
        switch selection {
        case .part(let index): [parts[index].name]
        case .pin(let index):
            [pins[index].net, parts[pins[index].part].name].filter { !$0.isEmpty }
        case .net(let name): [name]
        case .testPoint(let index): [testPoints[index].net].filter { !$0.isEmpty }
        case nil: []
        }
    }

    /// Parts and nets whose name contains the query, ignoring case: exact names first,
    /// then names that start with it, then the rest, each alphabetical. At most `limit`.
    public func search(_ query: String, limit: Int = 40) -> [BoardMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return [] }
        func rank(_ name: String) -> Int? {
            let upper = name.uppercased()
            if upper == q { return 0 }
            if upper.hasPrefix(q) { return 1 }
            return upper.contains(q) ? 2 : nil
        }
        var found: [(Int, BoardMatch)] = []
        for part in parts {
            if let r = rank(part.name) { found.append((r, .part(part.id, name: part.name))) }
        }
        for net in nets {
            if let r = rank(net) { found.append((r, .net(net, pins: pinsByNet[net]?.count ?? 0))) }
        }
        found.sort { ($0.0, $0.1.name.count, $0.1.name) < ($1.0, $1.1.name.count, $1.1.name) }
        return found.prefix(limit).map(\.1)
    }

    /// What is under a point seen from `side`: a pin within `tolerance` of its edge, else a test
    /// point, else the smallest part around the point, else nothing.
    public func hitTest(_ point: BoardPoint, side: BoardSide, tolerance: Double) -> BoardSelection? {
        var best: (index: Int, distance: Double)?
        for part in parts where part.isThroughHole || part.side == side {
            guard part.bounds.insetBy(-tolerance).contains(point) else { continue }
            for index in part.pins {
                let pin = pins[index]
                let d = hypot(pin.position.x - point.x, pin.position.y - point.y)
                if d <= part.pinRadius + tolerance, d < best?.distance ?? .infinity { best = (index, d) }
            }
        }
        if let best { return .pin(best.index) }
        var nearest: (index: Int, distance: Double)?
        for (index, nail) in testPoints.enumerated() where nail.side == side {
            let d = hypot(nail.position.x - point.x, nail.position.y - point.y)
            if d <= testPointRadius + tolerance, d < nearest?.distance ?? .infinity { nearest = (index, d) }
        }
        if let nearest { return .testPoint(nearest.index) }
        let around = parts.filter { ($0.isThroughHole || $0.side == side) && $0.bounds.contains(point) }
        if let smallest = around.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
            return .part(smallest.id)
        }
        return nil
    }
}
