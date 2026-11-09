import Foundation

/// A repair's number, printed as "#0042". Numbers start at 1 and never repeat.
public struct TicketNumber: Hashable, Comparable, Sendable, Codable {
    public let value: Int

    public init(_ value: Int) {
        precondition(value >= 1, "Ticket numbers start at 1")
        self.value = value
    }

    /// "#0042"; numbers past 9999 keep every digit ("#12345").
    public var text: String { "#" + String(format: "%04d", value) }

    /// Reads "#0042", "0042", "#42" or "42". Nil for anything else.
    public init?(parsing text: String) {
        let digits = text.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let value = Int(digits), value >= 1 else { return nil }
        self.value = value
    }

    public func next() -> TicketNumber { TicketNumber(value + 1) }

    public static func < (lhs: TicketNumber, rhs: TicketNumber) -> Bool { lhs.value < rhs.value }
}
