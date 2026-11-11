import Foundation

// What a part's name and a net's name say on their own: "C713" is a capacitor, "PP3V3_S0" is
// 3.3 V with the machine on (S0). Read from the letters, never guessed: an unknown name says nothing.

/// What a part on a board is, from the letters of its name.
public enum PartType: String, Sendable, CaseIterable {
    case capacitor, resistor, resistorNetwork, inductor, ferriteBead, chip, transistor, diode, led
    case fuse, connector, crystal, oscillator, switchPart, testPoint, jumper, transformer

    /// Longest letters first, so "FB" isn't read as "F" and "RN" isn't read as "R".
    private static let prefixes: [(String, PartType)] = [
        ("LED", .led), ("OSC", .oscillator),
        ("RP", .resistorNetwork), ("RN", .resistorNetwork), ("FB", .ferriteBead), ("FL", .ferriteBead),
        ("IC", .chip), ("CR", .diode), ("CN", .connector), ("SW", .switchPart), ("TP", .testPoint),
        ("PP", .testPoint), ("XW", .jumper),
        ("C", .capacitor), ("R", .resistor), ("L", .inductor), ("U", .chip), ("Q", .transistor),
        ("D", .diode), ("F", .fuse), ("J", .connector), ("Y", .crystal), ("X", .crystal), ("T", .transformer),
    ]

    /// "C713" → capacitor, "FB7101" → ferrite bead; nil for names like "MH1" or "ZZ".
    public init?(partName: String) {
        let letters = String(partName.uppercased().prefix { $0.isLetter })
        guard !letters.isEmpty, partName.dropFirst(letters.count).first?.isNumber == true,
              let match = Self.prefixes.first(where: { $0.0 == letters }) else { return nil }
        self = match.1
    }
}

/// What a net's name says: its voltage, when it has power, and whether it is ground.
public struct NetInfo: Equatable, Sendable {
    /// In volts, like 3.3 for PP3V3_S0.
    public var volts: Double?
    /// The power state the net is on in, upper case: S0, S3, S5, G3H, ALW…
    public var state: String?
    public var isGround: Bool

    public init(volts: Double? = nil, state: String? = nil, isGround: Bool = false) {
        self.volts = volts
        self.state = state
        self.isGround = isGround
    }

    /// True when the state means the net has power whenever a battery or charger does.
    public var isAlwaysOn: Bool { state == "G3H" || state == "ALW" }

    private static let states: Set<String> = ["S0", "S0SW", "S0IX", "S3", "S4", "S5", "S3S0", "S4S0", "S5S0",
                                              "G3H", "G3", "ALW", "SUS", "RUN", "AWAKE", "SLEEP"]

    private static let signalWords: Set<String> = ["EN", "PGOOD", "PG", "OK", "FB", "SNS", "SENSE", "VSENSE", "ISNS",
                                                   "DIV", "DRV", "PHASE", "LX", "BOOT", "BST", "COMP", "ILIM", "SS",
                                                   "CTRL", "SET", "L", "R", "PWM", "ALERT", "FAULT"]

    public init(netName: String) {
        self.init()
        let upper = netName.uppercased()
        if Board.isGround(upper) { isGround = true; return }
        let tokens = upper.split { $0 == "_" || $0 == "-" }.map(String.init)
        // P3V3S0_EN, PP1V8_PGOOD: a signal about the supply, not the supply.
        if tokens.dropFirst().contains(where: Self.signalWords.contains) { return }
        // The power state is a token of its own, usually last: PP3V3_S0, PP5V_S4SW → S4.
        for token in tokens.dropFirst().reversed() {
            if Self.states.contains(token) { state = token; break }
            if let known = Self.states.first(where: { token.hasPrefix($0) && token.count <= $0.count + 2 }) { state = known; break }
        }
        for token in tokens {
            if let v = Self.volts(in: token) { volts = v; break }
        }
    }

    /// "PP3V3" 3.3, "1V05" 1.05, "+1.8V" 1.8, "PP5V" 5, "1P8V" 1.8, "12V" 12; nil when it holds no voltage.
    static func volts(in token: String) -> Double? {
        var rest = Substring(token)
        // Prefixes that mark a supply.
        for prefix in ["PPV", "PP", "+V", "+", "VCC", "VDD", "VIN", "V", "P"] where rest.hasPrefix(prefix) {
            let after = rest.dropFirst(prefix.count)
            if after.first?.isNumber == true { rest = after; break }
        }
        guard rest.first?.isNumber == true else { return nil }
        let whole = rest.prefix { $0.isNumber }
        guard whole.count <= 2, let units = Double(whole) else { return nil }
        rest = rest.dropFirst(whole.count)
        // 3V3, 1P8V, 1.8V, 5V.
        guard let mark = rest.first, mark == "V" || mark == "P" || mark == "." else { return nil }
        rest = rest.dropFirst()
        let fraction = rest.prefix { $0.isNumber }
        rest = rest.dropFirst(fraction.count)
        if mark != "V" {
            // 1P8 and 1.8 need digits, and V or nothing after them.
            guard !fraction.isEmpty, rest.isEmpty || rest.first == "V" else { return nil }
            if rest.first == "V" { rest = rest.dropFirst() }
        }
        // What follows the voltage is a name (PP3V3S0, 5VALW), not more digits.
        guard rest.first?.isNumber != true else { return nil }
        let value = fraction.isEmpty ? units : Double("\(Int(units)).\(fraction)") ?? units
        return value > 0 && value <= 60 ? value : nil
    }
}
