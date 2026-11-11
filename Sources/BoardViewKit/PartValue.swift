import Foundation

// A part's value and ratings, read from the words a schematic prints beside its name:
// "C7821 / 22UF / 20% / 6.3V / X5R-CERM-1 / 603" is 22 µF, 20%, 6.3 V, X5R, 0603.
// The words come from the app (PDFKit) with their place on the page; this file has no PDFKit.

/// What the schematic says about one part.
public struct PartValue: Equatable, Sendable, Codable {
    /// "22 µF", "113 kΩ", "2.2 µH", "24 MHz".
    public var value: String?
    public var tolerance: String?
    /// The voltage rating, "6.3 V".
    public var voltage: String?
    /// The power rating, "1/16 W".
    public var power: String?
    /// The current rating, "2 A".
    public var current: String?
    /// The capacitor's dielectric, "X5R".
    public var dielectric: String?
    /// "0603", "DFN".
    public var package: String?
    /// A chip's, transistor's, or diode's part number, "ISL8009B".
    public var partNumber: String?
    /// The schematic page it was read on, from 0.
    public var page: Int?

    public init() {}

    /// Takes the fields this value lacks from another.
    mutating func fill(from other: PartValue) {
        value = value ?? other.value
        tolerance = tolerance ?? other.tolerance
        voltage = voltage ?? other.voltage
        power = power ?? other.power
        current = current ?? other.current
        dielectric = dielectric ?? other.dielectric
        package = package ?? other.package
        partNumber = partNumber ?? other.partNumber
    }

    var fieldCount: Int {
        [value, tolerance, voltage, power, current, dielectric, package, partNumber].compactMap { $0 }.count
    }

    public var isEmpty: Bool { fieldCount == 0 }

    /// "22 µF 20% 6.3 V X5R 0603" or "ISL8009B DFN".
    public var summary: String {
        [partNumber, value, tolerance, voltage, current, power, dielectric, package].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: Parsing

    /// The words under a part's name, top to bottom, read for its type.
    public static func parse(_ words: [String], type: PartType?) -> PartValue {
        var result = PartValue()
        for raw in words {
            let word = raw.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;()<>"))
                .replacingOccurrences(of: "-OHMS", with: "OHM").replacingOccurrences(of: "-OHM", with: "OHM")
            guard !word.isEmpty else { continue }
            // "2.2UH-20%-2.0A-0.108OHM": an inductor's ratings in one word.
            let pieces = word.contains("%") || word.filter({ $0 == "-" }).count >= 2 && word.first?.isNumber == true
                ? word.split(separator: "-").map(String.init) : [word]
            for piece in pieces { result.read(piece, type: type) }
        }
        return result
    }

    private mutating func read(_ word: String, type: PartType?) {
        if tolerance == nil, let t = Self.tolerance(word) { tolerance = t; return }
        if value == nil, let v = Self.value(word, type: type) { value = v; return }
        if voltage == nil, let v = Self.number(word, unit: "V", allowed: ["V", "VDC"]) { voltage = v; return }
        if current == nil, let a = Self.number(word, unit: "A", allowed: ["A", "AMP"]) { current = a; return }
        if power == nil, type == nil || type == .resistor || type == .resistorNetwork, let w = Self.power(word) { power = w; return }
        if dielectric == nil, type == nil || type == .capacitor, let d = Self.dielectric(word) { dielectric = d; return }
        if package == nil, let p = Self.package(word) { package = p; return }
        if partNumber == nil, type.map(Self.hasPartNumber) ?? false, Self.isPartNumber(word) { partNumber = word }
    }

    private static func hasPartNumber(_ type: PartType) -> Bool {
        switch type {
        case .chip, .transistor, .diode, .led, .oscillator, .connector, .switchPart, .resistorNetwork: true
        default: false
        }
    }

    /// "20%", "0.5%".
    static func tolerance(_ word: String) -> String? {
        guard word.hasSuffix("%"), Double(word.dropLast()) != nil else { return nil }
        return word
    }

    /// "6.3V" → "6.3 V".
    static func number(_ word: String, unit: String, allowed: [String]) -> String? {
        for suffix in allowed.sorted(by: { $0.count > $1.count }) where word.hasSuffix(suffix) {
            let digits = word.dropLast(suffix.count)
            if let n = Double(digits), n > 0 { return "\(format(n)) \(unit)" }
        }
        return nil
    }

    /// "1/16W", "1W", "0.1W".
    static func power(_ word: String) -> String? {
        guard word.hasSuffix("W") else { return nil }
        let digits = word.dropLast()
        let parts = digits.split(separator: "/")
        if parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil { return "\(digits) W" }
        if let n = Double(digits), n > 0 { return "\(format(n)) W" }
        return nil
    }

    private static let dielectrics = ["X5R", "X7R", "X6S", "X7S", "X7T", "X5S", "X6T", "X8R", "Y5V", "C0G", "COG", "NP0", "NPO",
                                      "POLY", "TANT", "ELEC"]

    /// "X5R-CERM-1" → "X5R", "COG" → "C0G".
    static func dielectric(_ word: String) -> String? {
        guard let d = dielectrics.first(where: { word.hasPrefix($0) }) else { return nil }
        switch d {
        case "COG": return "C0G"
        case "NPO": return "NP0"
        default: return d
        }
    }

    private static let packages: Set<String> = ["DFN", "QFN", "BGA", "LGA", "CSP", "WLCSP", "SOT23", "SOT-23", "SC70", "SC-70",
                                                "SOT563", "SOT363", "SOT323", "SOD323", "SOD523", "SON", "TSSOP", "SOIC", "SOP",
                                                "MSOP", "TQFN", "UQFN", "WQFN", "VQFN", "DSBGA", "XSON", "UDFN", "TDFN"]

    /// "603" → "0603", "0201", "0603-1" → "0603", "2520-SM" → "2520", "DFN".
    static func package(_ word: String) -> String? {
        guard !word.contains("_"), !word.contains("=") else { return nil }
        let head = String(word.prefix { $0 != "-" })
        if packages.contains(word) || packages.contains(head) { return packages.contains(word) ? word : head }
        if head.count == 3 || head.count == 4, head.allSatisfy(\.isNumber),
           ["201", "402", "603", "805", "1206", "1210", "0201", "0402", "0603", "0805", "01005", "1008", "2012", "2016",
            "2520", "3216", "0612", "1608", "1005", "0306", "0508", "2512", "2010"].contains(head) {
            return head.count == 3 ? "0" + head : head
        }
        if word.hasPrefix("SM") || word.hasPrefix("SOT") || word.hasPrefix("QFN") || word.hasPrefix("DFN") || word.hasPrefix("BGA") {
            return head
        }
        return nil
    }

    /// A part number has letters and digits, at least 5 characters, and isn't a schematic word.
    static func isPartNumber(_ word: String) -> Bool {
        guard word.count >= 5, word.count <= 24, word.contains(where: \.isNumber), word.contains(where: \.isLetter),
              !word.contains("="), !word.contains("_"), !word.contains("%") else { return false }
        // Apple's own part numbers, 152S1870, are not the maker's.
        if word.count == 8, word.dropFirst(3).first == "S", word.prefix(3).allSatisfy(\.isNumber) { return false }
        return word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "/" }
    }

    /// A value, by type: "22UF" "22 µF", "113K" "113 kΩ", "2.2UH" "2.2 µH", "24MHZ" "24 MHz".
    static func value(_ word: String, type: PartType?) -> String? {
        switch type {
        case .capacitor:
            // 0.0022UF reads better as 2.2 nF.
            if word.hasSuffix("UF"), let n = Double(word.dropLast(2)), n > 0, n < 0.01 {
                return "\(format((n * 1000 * 1000).rounded() / 1000)) nF"
            }
            return scaled(word, units: [("PF", "pF"), ("NF", "nF"), ("UF", "µF"), ("MF", "mF"), ("F", "F")])
        case .inductor, .ferriteBead:
            if let h = scaled(word, units: [("NH", "nH"), ("UH", "µH"), ("MH", "mH")]) { return h }
            // Ferrite beads go by their impedance at 100 MHz: "120OHM", "FERR-470-OHM"; some are named L.
            if type == .ferriteBead || word.hasSuffix("OHM") { return ohms(word) }
            return nil
        case .resistor, .resistorNetwork:
            return ohms(word)
        case .crystal, .oscillator:
            return scaled(word, units: [("KHZ", "kHz"), ("MHZ", "MHz"), ("GHZ", "GHz"), ("HZ", "Hz")])
        case .fuse:
            return number(word, unit: "A", allowed: ["A", "AMP"])
        default:
            return nil
        }
    }

    private static func scaled(_ word: String, units: [(String, String)]) -> String? {
        for (suffix, unit) in units where word.hasSuffix(suffix) {
            if let n = Double(word.dropLast(suffix.count)), n >= 0 { return "\(format(n)) \(unit)" }
        }
        return nil
    }

    /// "10" "10 Ω", "4.7K" "4.7 kΩ", "4K7" "4.7 kΩ", "1M" "1 MΩ", "0.002" "0.002 Ω", "0" "0 Ω", "120OHM" "120 Ω".
    static func ohms(_ word: String) -> String? {
        // 201, 402, 603, 805 are packages on a schematic, not ohms.
        if ["201", "402", "603", "805", "0201", "0402", "0603", "0805", "01005", "1206"].contains(word) { return nil }
        var w = word
        if w.hasPrefix("FERR") { w = String(w.drop { !$0.isNumber }) }
        for suffix in ["OHMS", "OHM", "R"] where w.hasSuffix(suffix) && w.count > suffix.count {
            w = String(w.dropLast(suffix.count))
            break
        }
        if let n = Double(w), n >= 0, !(w.count == 1 && w != "0") { return "\(format(n)) Ω" }
        for (letter, prefix) in [("K", "k"), ("M", "M"), ("R", "")] {
            if w.hasSuffix(letter), let n = Double(w.dropLast()), n >= 0 { return "\(format(n)) \(prefix)Ω" }
            // 4K7 is 4.7 k.
            let halves = w.split(separator: Character(letter), maxSplits: 1, omittingEmptySubsequences: false)
            if halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty, halves.allSatisfy({ $0.allSatisfy(\.isNumber) }),
               let n = Double("\(halves[0]).\(halves[1])") {
                return "\(format(n)) \(prefix)Ω"
            }
        }
        return nil
    }

    static func format(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e9 ? String(Int(n)) : String(n)
    }
}

/// A word on a schematic page and where it is, in PDF points with y up.
public struct SchematicWord: Sendable, Equatable {
    public var text: String
    public var page: Int
    public var minX: Double, minY: Double, maxX: Double, maxY: Double

    public init(text: String, page: Int, minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.text = text
        self.page = page
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    var height: Double { maxY - minY }
}

public enum SchematicValues {
    /// Words that sit in a part's column but say nothing about its value.
    private static let ignored: Set<String> = ["CRITICAL", "OMIT", "OMIT_TABLE", "NOSTUFF", "NO_STUFF", "DNP", "STUFF",
                                               "MF", "MF-LF", "CERM", "SHORT", "SM", "SYM_VER-1", "SYM_VER-2"]

    /// Each part's value, from the words of every page. A part named on several pages takes
    /// the page that says the most about it.
    public static func read(_ words: [SchematicWord], partNames: Set<String>) -> [String: PartValue] {
        var byPage: [Int: [SchematicWord]] = [:]
        for word in words { byPage[word.page, default: []].append(word) }
        var found: [String: PartValue] = [:]
        for (_, pageWords) in byPage {
            for (name, value) in read(page: pageWords, partNames: partNames)
            where value.fieldCount > (found[name]?.fieldCount ?? 0) {
                found[name] = value
            }
        }
        return found
    }

    /// The part a word names: itself, or itself less a pin number the PDF glued on ("R78201" is R7820 pin 1).
    public static func partName(_ text: String, in names: Set<String>) -> String? {
        let upper = text.uppercased()
        if names.contains(upper) { return upper }
        if upper.count > 2, upper.last?.isNumber == true, names.contains(String(upper.dropLast())) { return String(upper.dropLast()) }
        return nil
    }

    /// The words right of a name on its row, then those on the line just under the row, left to right;
    /// small page references ("75" before a net name) left out.
    static func rowWords(of nameIndex: Int, name: String, in words: [SchematicWord], names: [Int: String]) -> [String] {
        let anchor = words[nameIndex]
        let h = anchor.height
        let maxX = anchor.minX + (anchor.maxX - anchor.minX) * Double(name.count) / Double(max(anchor.text.count, 1))
        let right = words.indices.filter { i in
            let w = words[i]
            return i != nameIndex && w.minX >= maxX - 1 && w.minX <= maxX + 100 && w.height >= h * 0.5
        }
        let onRow = right.filter { (words[$0].minY + words[$0].maxY) / 2 >= anchor.minY && (words[$0].minY + words[$0].maxY) / 2 <= anchor.maxY }
            .sorted { words[$0].minX < words[$1].minX }
        let under = right.filter { words[$0].maxY >= anchor.minY - h * 0.8 && words[$0].maxY < anchor.minY + h * 0.3 && !onRow.contains($0) }
            .sorted { words[$0].minX < words[$1].minX }
        var result: [String] = []
        for i in onRow {
            if names[i] != nil { break }
            result.append(words[i].text)
        }
        for i in under where names[i] == nil { result.append(words[i].text) }
        return result
    }

    static func read(page words: [SchematicWord], partNames: Set<String>) -> [String: PartValue] {
        let names = words.indices.compactMap { i in partName(words[i].text, in: partNames).map { (i, $0) } }
        guard !names.isEmpty else { return [:] }
        let nameAt = Dictionary(names, uniquingKeysWith: { a, _ in a })
        // Words top to bottom, once.
        let order = words.indices.sorted { words[$0].maxY > words[$1].maxY }
        // Each word goes to the name whose column holds it and that is closest: below it, then centered on it.
        var claimed: [Int: (name: Int, cost: Double)] = [:]
        for (nameIndex, name) in names {
            let anchor = words[nameIndex]
            // "R78201": the name without the pin number glued on.
            let maxX = anchor.minX + (anchor.maxX - anchor.minX) * Double(name.count) / Double(max(anchor.text.count, 1))
            let midX = (anchor.minX + maxX) / 2
            let slack = max(anchor.height, 4)
            var bottom = anchor.minY
            var taken = 0
            for i in order where i != nameIndex {
                let w = words[i]
                guard w.maxY <= anchor.minY + anchor.height * 0.3 else { continue }
                guard w.maxX >= anchor.minX - slack, w.minX <= maxX + slack * 2 else { continue }
                if bottom - w.maxY > slack * 1.6 { break }
                // Another part's name ends this one's column.
                if nameAt[i] != nil { break }
                bottom = min(bottom, w.minY)
                let cost = max(0, anchor.minY - w.maxY) + abs((w.minX + w.maxX) / 2 - midX) * 0.5
                if claimed[i].map({ cost < $0.cost }) ?? true { claimed[i] = (nameIndex, cost) }
                taken += 1
                if taken >= 10 { break }
            }
        }
        var columns: [Int: [Int]] = [:]
        for (word, claim) in claimed { columns[claim.name, default: []].append(word) }
        func keep(_ text: String) -> Bool { !ignored.contains(text.uppercased()) && !(text.count == 1 && text != "0") }
        var result: [String: PartValue] = [:]
        for (nameIndex, name) in names {
            let type = PartType(partName: name)
            let column = (columns[nameIndex] ?? []).sorted { words[$0].maxY > words[$1].maxY }.map { words[$0].text }.filter(keep)
            var value = PartValue.parse(column, type: type)
            // A part drawn sideways: its value on the name's row, its ratings just under the row.
            if value.value == nil, value.partNumber == nil {
                let row = rowWords(of: nameIndex, name: name, in: words, names: nameAt).filter(keep)
                value.fill(from: PartValue.parse(row, type: type))
            }
            value.page = words[nameIndex].page
            if value.fieldCount > (result[name]?.fieldCount ?? 0) { result[name] = value }
        }
        return result
    }
}
