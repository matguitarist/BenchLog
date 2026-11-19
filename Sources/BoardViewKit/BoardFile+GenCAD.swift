import Foundation

// GenCAD 1.4 (.cad), ported from BoardViewCraft's reader (crates/bvc-core/src/parser/gencad.rs
// and gencad_geometry.rs, https://github.com/elbuit/BoardViewCraft, MIT or Apache-2.0), which
// follows OpenBoardView's GenCADFile.cpp and TRACE Boardviewer's gencad.ts (MIT).
//
//   $HEADER      UNITS INCH | THOU | MM | MM100 | USER n | USERCM n | USERMM n   (mils come out)
//   $BOARD       LINE, ARC, CIRCLE, RECTANGLE: the board's edge
//   $PADSTACKS   PADSTACK name drill   a drill above 0 makes the part through-hole
//   $SHAPES      SHAPE name, then PIN name pad x y layer rot mirror, and the body's artwork
//   $COMPONENTS  COMPONENT name, then PLACE x y, LAYER TOP|BOTTOM, ROTATION deg,
//                SHAPE name [MIRRORX|MIRRORY|MIRRORXY] [FLIP]
//   $SIGNALS     SIGNAL net, then NODE component pin

extension BoardFile {
    static func readGenCAD(_ text: String) throws -> Board {
        var gencad = GenCAD()
        for raw in text.split(whereSeparator: \.isNewline) {
            gencad.read(line: raw.trimmingCharacters(in: .whitespaces))
        }
        return try gencad.board()
    }
}

/// A GenCAD mirror flag: X turns y over, Y turns x over.
struct GenCADMirror: Equatable {
    var x = false
    var y = false

    init(x: Bool = false, y: Bool = false) {
        self.x = x
        self.y = y
    }

    init(_ token: Substring?) {
        switch token?.uppercased() {
        case "MIRRORX": x = true
        case "MIRRORY": y = true
        case "MIRRORXY": x = true; y = true
        default: break
        }
    }

    /// Mirrors, turns counter-clockwise by `degrees`, then moves by `offset`.
    func place(_ p: BoardPoint, rotation degrees: Double, offset: BoardPoint) -> BoardPoint {
        let x = p.x * (y ? -1 : 1), yy = p.y * (self.x ? -1 : 1)
        let a = degrees * .pi / 180
        return BoardPoint(x: offset.x + x * cos(a) - yy * sin(a), y: offset.y + x * sin(a) + yy * cos(a))
    }
}

struct GenCAD {
    struct ShapePin {
        var name: String
        var pad: String
        var position: BoardPoint
    }

    struct Shape {
        var pins: [ShapePin] = []
        var artwork: [[BoardPoint]] = []
    }

    struct Component {
        var name: String
        var place = BoardPoint(x: 0, y: 0)
        var bottom = false
        var rotation = 0.0
        var shape = ""
        var mirror = GenCADMirror()
    }

    private var section = ""
    private var unit: (Double) -> Double = { $0 }
    private var edge: [[BoardPoint]] = []
    private var drilled: Set<String> = []
    private var shapes: [String: Shape] = [:]
    private var currentShape: String?
    private var components: [Component] = []
    private var nets: [String: String] = [:]
    private var currentSignal: String?

    private static func unquote(_ s: Substring) -> String {
        String(s).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// The rest of the line after its first word, without quotes.
    private static func rest(_ line: String, after first: Substring) -> String {
        String(line.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    mutating func read(line: String) {
        guard !line.isEmpty else { return }
        if line.hasPrefix("$") {
            let marker = line.uppercased()
            section = marker.hasPrefix("$END") ? "" : String(marker.dropFirst())
            currentShape = nil
            currentSignal = nil
            return
        }
        let t = line.split(whereSeparator: \.isWhitespace)
        guard let first = t.first else { return }
        let command = first.uppercased()
        switch section {
        case "HEADER":
            guard command == "UNITS", t.count >= 2 else { return }
            let n = t.count >= 3 ? Double(t[2]) : nil
            switch t[1].uppercased() {
            case "INCH": unit = { $0 * 1000 }
            case "THOU": unit = { $0 }
            case "MM": unit = { $0 * 100 / 2.54 }
            case "MM100": unit = { $0 / 2.54 }
            case "USER": let u = n ?? 1000; unit = { u * $0 / 1000 }
            case "USERCM", "USERM": let u = n ?? 1; unit = { u * $0 * 10 / 2.54 }
            case "USERMM": let u = n ?? 1; unit = { u * $0 / 2.54 }
            default: break
            }
        case "BOARD":
            if let path = geometry(t) { edge.append(path) }
        case "PADSTACKS":
            if command == "PADSTACK", t.count >= 3, let drill = Double(t[2]), drill != 0 {
                drilled.insert(Self.unquote(t[1]))
            }
        case "SHAPES":
            if command == "SHAPE", t.count >= 2 {
                let name = Self.unquote(t[1])
                currentShape = name
                if shapes[name] == nil { shapes[name] = Shape() }
            } else if command == "PIN", let name = currentShape, t.count >= 5,
                      let x = Double(t[3]), let y = Double(t[4]) {
                shapes[name]?.pins.append(ShapePin(name: Self.unquote(t[1]), pad: Self.unquote(t[2]),
                                                   position: BoardPoint(x: unit(x), y: unit(y))))
            } else if let name = currentShape, let path = geometry(t) {
                shapes[name]?.artwork.append(path)
            }
        case "COMPONENTS":
            if command == "COMPONENT", t.count >= 2 {
                components.append(Component(name: Self.unquote(t[1])))
                return
            }
            guard !components.isEmpty else { return }
            switch command {
            case "PLACE" where t.count >= 3:
                if let x = Double(t[1]), let y = Double(t[2]) { components[components.count - 1].place = BoardPoint(x: unit(x), y: unit(y)) }
            case "LAYER" where t.count >= 2:
                components[components.count - 1].bottom = t[1].uppercased() == "BOTTOM"
            case "ROTATION" where t.count >= 2:
                components[components.count - 1].rotation = Double(t[1]) ?? 0
            case "SHAPE" where t.count >= 2:
                components[components.count - 1].shape = Self.unquote(t[1])
                var mirror = GenCADMirror()
                for flag in t.dropFirst(2) {
                    let m = GenCADMirror(flag)
                    mirror.x = mirror.x || m.x
                    mirror.y = mirror.y || m.y
                }
                components[components.count - 1].mirror = mirror
            default: break
            }
        case "SIGNALS":
            if command == "SIGNAL", t.count >= 2 {
                currentSignal = Self.rest(line, after: first)
            } else if command == "NODE", let signal = currentSignal, t.count >= 3 {
                nets[Self.unquote(t[1]) + "\u{1F}" + Self.unquote(t[2])] = signal
            }
        default:
            break
        }
    }

    /// A LINE, ARC, CIRCLE, or RECTANGLE row as a polyline, in mils.
    func geometry(_ t: [Substring]) -> [BoardPoint]? {
        guard let command = t.first?.uppercased() else { return nil }
        func num(_ i: Int) -> Double? { t.indices.contains(i) ? Double(t[i]).flatMap { $0.isFinite ? unit($0) : nil } : nil }
        func point(_ i: Int) -> BoardPoint? {
            guard let x = num(i), let y = num(i + 1) else { return nil }
            return BoardPoint(x: x, y: y)
        }
        switch command {
        case "LINE":
            guard let a = point(1), let b = point(3) else { return nil }
            return [a, b]
        case "RECTANGLE":
            // A corner and a size, not two corners.
            guard let a = point(1), let w = num(3), let h = num(4) else { return nil }
            let r = BoardRect(minX: min(a.x, a.x + w), minY: min(a.y, a.y + h), maxX: max(a.x, a.x + w), maxY: max(a.y, a.y + h))
            return [BoardPoint(x: r.minX, y: r.minY), BoardPoint(x: r.maxX, y: r.minY), BoardPoint(x: r.maxX, y: r.maxY),
                    BoardPoint(x: r.minX, y: r.maxY), BoardPoint(x: r.minX, y: r.minY)]
        case "CIRCLE":
            guard let c = point(1), let r = num(3), r >= 0 else { return nil }
            return (0...64).map { i in
                let a = Double(i) * 2 * .pi / 64
                return BoardPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
        case "ARC":
            // Counter-clockwise from start to end around the center.
            guard let s = point(1), let e = point(3), let c = point(5) else { return nil }
            let r = hypot(s.x - c.x, s.y - c.y)
            guard r > 0 else { return nil }
            let start = atan2(s.y - c.y, s.x - c.x), end = atan2(e.y - c.y, e.x - c.x)
            var sweep = (end - start + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
            if sweep == 0 { sweep = 2 * .pi }
            let steps = max(Int((sweep / (.pi / 32)).rounded(.up)), 2)
            var points = (0...steps).map { i in
                let a = start + sweep * Double(i) / Double(steps)
                return BoardPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            }
            points[0] = s
            points[points.count - 1] = e
            return points
        default:
            return nil
        }
    }

    func board() throws -> Board {
        var parts: [(name: String, side: BoardSide, isThroughHole: Bool)] = []
        var pins: [BoardPin] = []
        var outlines: [[BoardPoint]] = []
        // OpenBoardView skips a second copy of a shape placed at the same spot on the same side.
        var placed: Set<String> = []
        for component in components where !component.shape.isEmpty {
            let key = "\(component.bottom) \(component.place.x.rounded()) \(component.place.y.rounded()) \(component.shape)"
            guard placed.insert(key).inserted else { continue }
            let shape = shapes[component.shape] ?? Shape()
            let throughHole = shape.pins.contains { drilled.contains($0.pad) }
            let index = parts.count
            parts.append((component.name, component.bottom ? .bottom : .top, throughHole))
            let rotation = component.rotation.truncatingRemainder(dividingBy: 360)
            func place(_ p: BoardPoint) -> BoardPoint {
                component.mirror.place(p, rotation: rotation, offset: component.place)
            }
            for pin in shape.pins {
                pins.append(BoardPin(position: place(pin.position), part: index, number: 0,
                                     net: nets[component.name + "\u{1F}" + pin.name] ?? ""))
            }
            outlines.append(Self.outerContour(shape.artwork).map(place))
        }
        guard !parts.isEmpty else { throw BoardFileError.malformed(String(localized: "no parts")) }
        guard !pins.isEmpty else { throw BoardFileError.malformed(String(localized: "no pins")) }
        var outline = Self.outerContour(edge)
        if outline.isEmpty {
            outline = BoardFile.boxOutline(around: edge.isEmpty ? pins.map(\.position) : Array(edge.joined()))
        }
        return Board(outline: outline, parts: parts, pins: pins, testPoints: [], partOutlines: outlines)
    }

    // MARK: Contours

    private static func same(_ a: BoardPoint, _ b: BoardPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 1e-5
    }

    /// The largest closed loop the paths make: closed paths stand alone, open ones are joined
    /// end to end. Empty when nothing closes.
    static func outerContour(_ paths: [[BoardPoint]]) -> [BoardPoint] {
        var loops: [[BoardPoint]] = []
        var open: [[BoardPoint]] = []
        for path in paths where path.count > 1 && !path.allSatisfy({ same($0, path[0]) }) {
            if same(path[0], path[path.count - 1]) { loops.append(path) } else { open.append(path) }
        }
        while !open.isEmpty {
            var chain = open.removeFirst()
            var grew = true
            while grew, !same(chain[0], chain[chain.count - 1]) {
                grew = false
                let last = chain[chain.count - 1]
                if let i = open.firstIndex(where: { same($0[0], last) || same($0[$0.count - 1], last) }) {
                    var next = open.remove(at: i)
                    if !same(next[0], last) { next.reverse() }
                    chain += next.dropFirst()
                    grew = true
                } else if let i = open.firstIndex(where: { same($0[0], chain[0]) || same($0[$0.count - 1], chain[0]) }) {
                    var next = open.remove(at: i)
                    if !same(next[next.count - 1], chain[0]) { next.reverse() }
                    chain = next.dropLast() + chain
                    grew = true
                }
            }
            if same(chain[0], chain[chain.count - 1]) { loops.append(chain) }
        }
        func area(_ p: [BoardPoint]) -> Double {
            abs(zip(p, p.dropFirst()).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y })
        }
        return loops.filter { $0.count >= 4 }.max { area($0) < area($1) } ?? []
    }
}
