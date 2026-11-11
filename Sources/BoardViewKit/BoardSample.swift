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
}
