import Foundation

/// A small made-up board in .brd form, with the schematic pages that go with it, for sample
/// data, snapshots, the self-test, and unit tests. Real boards are copyrighted; this one is not.
public enum BoardSample {
    public static let fileName = "HAC-001-01 mainboard.brd"
    public static let schematicName = "HAC-001-01 schematic.pdf"

    /// What each schematic page shows: a title, then the part and net names drawn on it.
    public static let schematicPages: [(title: String, names: [String])] = [
        ("Power", ["U2", "L1", "C1", "C2", "C3", "C4", "PPBUS_MAIN", "PP3V3_S0", "PP1V8_S0", "PMIC_EN", "GND"]),
        ("SoC", ["U1", "R1", "R2", "R3", "C5", "C6", "PP1V8_S0", "PP3V3_S0", "I2C_SDA", "I2C_SCL", "SOC_CLK", "PMIC_EN", "GND"]),
        ("USB-C and Fan", ["J1", "Q1", "CN1", "R4", "USBC_VBUS", "USB_DP", "USB_DN", "PPBUS_MAIN", "FAN_PWM", "FAN_TACH", "GND"]),
    ]

    /// The board as plain .brd text. Units are mils; the board is 2000 by 1200.
    public static var text: String {
        var parts: [(String, Int)] = []
        var pins: [(Double, Double, Int, String)] = []
        func part(_ name: String, type: Int, _ pinList: [(Double, Double, String)]) {
            parts.append((name, type))
            for p in pinList { pins.append((p.0, p.1, parts.count, p.2)) }
        }
        let socNets = ["PP1V8_S0", "GND", "I2C_SDA", "I2C_SCL", "SOC_CLK", "PP3V3_S0", "GND", "PMIC_EN"]
        // U1: an 8 by 8 BGA, 40 mil pitch.
        part("U1", type: 5, (0..<64).map { i in
            (560 + Double(i % 8) * 40, 420 + Double(i / 8) * 40, socNets[(i * 3 + i / 8) % socNets.count])
        })
        // U2: a QFN with four pins a side.
        let pmicNets = ["PPBUS_MAIN", "PPBUS_MAIN", "PMIC_EN", "GND", "PP3V3_S0", "PP3V3_S0", "GND", "PP1V8_S0",
                        "PP1V8_S0", "GND", "I2C_SDA", "I2C_SCL", "GND", "PPBUS_MAIN", "GND", "GND"]
        var qfn: [(Double, Double, String)] = []
        for i in 0..<4 { qfn.append((1300 + Double(i) * 30, 360, pmicNets[i])) }
        for i in 0..<4 { qfn.append((1420, 390 + Double(i) * 30, pmicNets[4 + i])) }
        for i in 0..<4 { qfn.append((1390 - Double(i) * 30, 510, pmicNets[8 + i])) }
        for i in 0..<4 { qfn.append((1270, 480 - Double(i) * 30, pmicNets[12 + i])) }
        part("U2", type: 5, qfn)
        part("L1", type: 5, [(1560, 420, "PPBUS_MAIN"), (1660, 420, "PP3V3_S0")])
        let caps: [(String, Double, Double, String)] = [
            ("C1", 1250, 620, "PPBUS_MAIN"), ("C2", 1350, 620, "PP3V3_S0"), ("C3", 1450, 620, "PP1V8_S0"),
            ("C4", 1550, 620, "PP3V3_S0"), ("C5", 520, 780, "PP1V8_S0"), ("C6", 620, 780, "PP3V3_S0"),
        ]
        for (name, x, y, net) in caps { part(name, type: 5, [(x, y, net), (x, y + 40, "GND")]) }
        let resistors: [(String, Double, Double, String, String)] = [
            ("R1", 900, 300, "I2C_SDA", "PP3V3_S0"), ("R2", 960, 300, "I2C_SCL", "PP3V3_S0"),
            ("R3", 1020, 300, "PMIC_EN", "PP1V8_S0"),
        ]
        for (name, x, y, a, b) in resistors { part(name, type: 5, [(x, y, a), (x, y + 40, b)]) }
        // Bottom: the USB-C port, a transistor, and a resistor.
        let usbNets = ["GND", "USBC_VBUS", "USB_DP", "USB_DN", "USBC_VBUS", "GND"]
        part("J1", type: 10, (0..<12).map { i in
            (200 + Double(i % 6) * 40, 900 + Double(i / 6) * 60, usbNets[i % 6])
        })
        part("Q1", type: 10, [(600, 980, "USBC_VBUS"), (660, 980, "PMIC_EN"), (630, 1030, "PPBUS_MAIN")])
        part("R4", type: 10, [(760, 980, "FAN_TACH"), (760, 1020, "PP3V3_S0")])
        // CN1: the fan connector, through-hole.
        part("CN1", type: 1, [(1700, 900, "PP3V3_S0"), (1700, 1000, "FAN_PWM"), (1700, 1100, "FAN_TACH"), (1800, 1000, "GND")])

        let outline: [(Double, Double)] = [(0, 0), (2000, 0), (2000, 1200), (120, 1200), (0, 1080), (0, 0)]
        let nails: [(Int, Double, Double, Int, String)] = [(1, 1100, 200, 1, "PPBUS_MAIN"), (2, 400, 700, 2, "PP3V3_S0")]

        var out = "str_length:\n0\n\nvar_data:\n\(outline.count) \(parts.count) \(pins.count) \(nails.count)\n\nFormat:\n"
        for (x, y) in outline { out += "\(Int(x)) \(Int(y))\n" }
        out += "\nParts:\n"
        var end = 0
        for (index, (name, type)) in parts.enumerated() {
            end += pins.filter { $0.2 == index + 1 }.count
            out += "\(name) \(type) \(end)\n"
        }
        out += "\nPins:\n"
        for (x, y, partIndex, net) in pins { out += "\(Int(x)) \(Int(y)) 0 \(partIndex) \(net)\n" }
        out += "\nNails:\n"
        for (probe, x, y, side, net) in nails { out += "\(probe) \(Int(x)) \(Int(y)) \(side) \(net)\n" }
        return out
    }

    /// The board encoded, as a real .brd file is.
    public static var data: Data { BoardFile.encode(text) }

    /// The same board as a byte-keyed .bdv.
    public static var bdvData: Data { BDV.encode(text, byLine: false) }

    /// The same board as BRD2 text: nets numbered from 1, pins counted from 0, a
    /// through-hole part on both sides (3).
    public static var brd2Text: String {
        guard let board = try? BoardFile.read(data) else { return "" }
        let netIDs = Dictionary(uniqueKeysWithValues: board.nets.enumerated().map { ($0.element, $0.offset + 1) })
        func side(_ part: BoardPart) -> Int { part.isThroughHole ? 3 : part.side == .top ? 1 : 2 }
        var lines = ["BRDOUT: \(board.outline.count) \(Int(board.bounds.width)) \(Int(board.bounds.height))"]
        lines += board.outline.map { "\(Int($0.x)) \(Int($0.y))" }
        lines.append("NETS: \(board.nets.count)")
        lines += board.nets.map { "\(netIDs[$0]!) \($0)" }
        lines.append("PARTS: \(board.parts.count)")
        lines += board.parts.map { part in
            let b = part.bounds
            return "\(part.name) \(Int(b.minX)) \(Int(b.minY)) \(Int(b.maxX)) \(Int(b.maxY)) \(part.pins.lowerBound) \(side(part))"
        }
        lines.append("PINS: \(board.pins.count)")
        lines += board.pins.map { pin in
            "\(Int(pin.position.x)) \(Int(pin.position.y)) \(netIDs[pin.net] ?? 0) \(side(board.parts[pin.part]))"
        }
        lines.append("NAILS: \(board.testPoints.count)")
        lines += board.testPoints.map { nail in
            "\(nail.probe) \(Int(nail.position.x)) \(Int(nail.position.y)) \(netIDs[nail.net] ?? 0) \(nail.side == .top ? 1 : 2)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Other formats (S-081 to S-083)

    /// The sample read from its .brd; the other formats are written from it.
    static var board: Board? { try? BoardFile.read(data) }

    /// The same board as a compressed .fz, in mils. Test points are TESTVIA rows (on top).
    public static var fzData: Data {
        guard let board else { return Data() }
        var lines = ["UNIT:mils", "A!REFDES!COMP_INSERTION_CODE!SYM_NAME!SYM_MIRROR!SYM_ROTATE"]
        lines += board.parts.map { "S!\($0.name)!!SYM!\($0.side == .bottom ? "YES" : "NO")!0" }
        lines.append("A!NET_NAME!REFDES!PIN_NUMBER!PIN_NAME!PIN_X!PIN_Y!TEST_POINT!RADIUS")
        lines += board.pins.map { pin in
            "S!\(pin.net)!\(board.parts[pin.part].name)!\(pin.number)!\(pin.number)!\(Int(pin.position.x))!\(Int(pin.position.y))!!10"
        }
        lines.append("A!TESTVIA!NET_NAME!REFDES!PIN_NUMBER!PIN_NAME!VIA_X!VIA_Y!TEST_POINT!RADIUS")
        lines += board.testPoints.map { "S!TESTVIA!\($0.net)!!!!\(Int($0.position.x))!\(Int($0.position.y))!!10" }
        return FZ.deflate(lines.joined(separator: "\r\n") + "\r\n")
    }

    /// The same board as GenCAD in thou: each part its own shape placed at its first pin, a
    /// drilled padstack for the through-hole part, and U1's body drawn as a rectangle.
    public static var gencadText: String {
        guard let board else { return "" }
        func n(_ v: Double) -> String { String(Int(v)) }
        var out = ["$HEADER", "GENCAD 1.4", "UNITS THOU", "$ENDHEADER", "$BOARD"]
        let edge = board.outline + [board.outline[0]]
        for (a, b) in zip(edge, edge.dropFirst()) { out.append("LINE \(n(a.x)) \(n(a.y)) \(n(b.x)) \(n(b.y))") }
        out += ["$ENDBOARD", "$PADSTACKS", "PADSTACK SMD 0", "PAD P1 TOP 0 0", "PADSTACK TH 30", "PAD P1 ALL 0 0",
                "$ENDPADSTACKS", "$SHAPES"]
        for part in board.parts {
            let origin = board.pins[part.pins.lowerBound].position
            out.append("SHAPE S_\(part.name)")
            if part.name == "U1" {
                let b = part.bounds
                out.append("RECTANGLE \(n(b.minX - origin.x)) \(n(b.minY - origin.y)) \(n(b.width)) \(n(b.height))")
            }
            for index in part.pins {
                let p = board.pins[index]
                out.append("PIN \(p.number) \(part.isThroughHole ? "TH" : "SMD") \(n(p.position.x - origin.x)) \(n(p.position.y - origin.y)) TOP 0 0")
            }
        }
        out += ["$ENDSHAPES", "$COMPONENTS"]
        for part in board.parts {
            let origin = board.pins[part.pins.lowerBound].position
            out += ["COMPONENT \(part.name)", "PLACE \(n(origin.x)) \(n(origin.y))",
                    "LAYER \(part.side == .bottom ? "BOTTOM" : "TOP")", "ROTATION 0", "SHAPE S_\(part.name) 0 0"]
        }
        out += ["$ENDCOMPONENTS", "$SIGNALS"]
        for net in board.nets {
            out.append("SIGNAL \(net)")
            for index in board.pins(onNet: net) { out.append("NODE \(board.parts[board.pins[index].part].name) \(board.pins[index].number)") }
        }
        out.append("$ENDSIGNALS")
        return out.joined(separator: "\n") + "\n"
    }

    /// The same board as a binary .tvw: a TOP and a BOTTOM pin table, the components with
    /// their boxes, and the net names at the end, in hundredths of a mil.
    public static var tvwData: Data {
        guard let board else { return Data() }
        var out = Data(TVW.magic)
        out.append(Data(count: 64 - out.count))
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func i32(_ v: Double) { u32(UInt32(bitPattern: Int32((v * 100).rounded()))) }
        func pascal(_ s: String) { out.append(UInt8(s.utf8.count)); out.append(contentsOf: Array(s.utf8)) }
        let nets = [""] + board.nets
        let netIndex = Dictionary(uniqueKeysWithValues: nets.enumerated().map { ($0.element, UInt32($0.offset)) })
        // A pin's place in its side's table.
        var slot: [Int: (top: Bool, index: Int)] = [:]
        for top in [true, false] {
            let layer = top ? "TOP" : "BOTTOM"
            pascal(layer)
            // The table starts a whole number of words after the layer's name.
            out.append(Data(count: 12 + (4 - (layer.count + 1) % 4) % 4))
            let list = board.pins.indices.filter { (board.parts[board.pins[$0].part].side == .top) == top }
            u32(0); u32(UInt32(list.count)); u32(0)
            for (k, index) in list.enumerated() {
                slot[index] = (top, k)
                let pin = board.pins[index]
                u32(netIndex[pin.net] ?? 0); u32(UInt32(1000 + k)); i32(pin.position.x); i32(pin.position.y)
                out.append(contentsOf: [0, 0, 0])
            }
            out.append(Data(count: 64))
        }
        // The components and nets sit in the last quarter, past the pin tables' layers.
        let tables = out
        out = Data()
        for part in board.parts {
            let b = part.bounds
            pascal(part.name)
            i32(b.minX); i32(b.minY); i32(b.maxX); i32(b.maxY); i32(b.center.x); i32(b.center.y)
            u32(0); u32(part.side == .top ? 1 : 0); u32(0)
            out.append(Data(count: 8))
            out.append(contentsOf: [1, 0, 0, 0, 0, 0])
            u32(0)
            u32(UInt32(part.pins.count)); u32(part.side == .top ? 2 : 11); u32(0)
            for index in part.pins {
                u32(UInt32(slot[index]!.index * 8)); u32(0); u32(UInt32(board.pins[index].number))
                pascal(String(board.pins[index].number)); u32(0)
            }
        }
        u32(UInt32(nets.count)); u32(UInt32(nets.count))
        for net in nets { pascal(net.isEmpty ? "NC" : net) }
        let rest = out
        out = tables
        out.append(Data(count: max(3 * rest.count - tables.count, 0) + 64))
        out.append(rest)
        return out
    }
}
