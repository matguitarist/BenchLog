import Foundation

/// What a barcode database knows about a product.
public struct ProductInfo: Hashable, Sendable {
    public var barcode: String
    public var title: String
    public var brand: String
    public var category: String

    public init(barcode: String, title: String, brand: String = "", category: String = "") {
        self.barcode = barcode
        self.title = title
        self.brand = brand
        self.category = category
    }

    /// A guess at what it is, from its title and category; people change it in Edit Part.
    public var suggestedKind: PartKind {
        let title = title.lowercased()
        func has(_ words: String...) -> Bool { words.contains { title.contains($0) } }
        if has("controller", "gamepad", "joystick", "manette", "dualshock", "dualsense", "joy-con") { return .controller }
        if has("cable", "cord", "adapter", "câble") { return .cable }
        if has("memory card", "charger", "headset", "stand", "dock", "case", "remote") { return .accessory }
        if category.lowercased().contains("video game") || has("playstation", "xbox", "nintendo", "sega", "game boy") { return .game }
        return .part
    }
}

public enum BarcodeLookupError: Error, Equatable, LocalizedError {
    /// The free service allows a number of lookups a day.
    case limitReached
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .limitReached: "The barcode service's daily limit is reached."
        case .server(let status): "The barcode service answered \(status)."
        }
    }
}

/// Finds a product by the UPC or EAN on its box, at UPCitemdb (free, no account, 100 lookups a day).
/// Only the barcode's digits leave the Mac.
public enum BarcodeLookup {
    public static let endpoint = URL(string: "https://api.upcitemdb.com/prod/trial/lookup")!

    /// The digits of a UPC-A, EAN-13, EAN-8, or GTIN-14 with a right check digit, or nil. A
    /// 13-digit code that starts with 0 is its 12-digit UPC, so both spellings find each other.
    public static func normalized(_ text: String) -> String? {
        var digits = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) && $0.isASCII }.map { Int($0.value) - 48 }
        guard [8, 12, 13, 14].contains(digits.count) else { return nil }
        let check = digits.removeLast()
        // From the right, weights 3, 1, 3, …
        let sum = digits.reversed().enumerated().reduce(0) { $0 + $1.element * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
        guard (10 - sum % 10) % 10 == check else { return nil }
        var code = (digits + [check]).map(String.init).joined()
        if code.count == 13, code.hasPrefix("0") { code.removeFirst() }
        return code
    }

    public static func request(for barcode: String) -> URLRequest {
        var request = URLRequest(url: endpoint.appending(queryItems: [URLQueryItem(name: "upc", value: barcode)]))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    /// The first product of a lookup answer, or nil when the database does not know the code.
    public static func parse(_ data: Data, barcode: String) -> ProductInfo? {
        struct Answer: Decodable {
            struct Item: Decodable {
                var title: String?
                var brand: String?
                var category: String?
            }
            var items: [Item]?
        }
        guard let item = (try? JSONDecoder().decode(Answer.self, from: data))?.items?.first,
              let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return ProductInfo(barcode: barcode, title: title, brand: item.brand ?? "", category: item.category ?? "")
    }

    /// Looks the barcode up. Nil when the database does not know it.
    public static func find(_ barcode: String, session: URLSession = .shared) async throws -> ProductInfo? {
        let (data, response) = try await session.data(for: request(for: barcode))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 429 { throw BarcodeLookupError.limitReached }
        // 400 and 404 mean a code it cannot use or does not have.
        if status == 400 || status == 404 { return nil }
        guard status == 200 else { throw BarcodeLookupError.server(status) }
        return parse(data, barcode: barcode)
    }
}
