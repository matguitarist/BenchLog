import Foundation

/// Where the business is: it decides the taxes, their names, and the currency.
public enum Country: String, Codable, CaseIterable, Sendable, Identifiable {
    case canada = "CA", unitedStates = "US"
    public var id: String { rawValue }

    public var currencyCode: String { self == .canada ? "CAD" : "USD" }

    /// Provinces and territories, or states and DC, by code.
    public var regions: [TaxRegion] { self == .canada ? TaxRegion.provinces : TaxRegion.states }
}

/// A kind of sales tax. Each prints under its own name in the document's language.
public enum TaxKind: String, Codable, CaseIterable, Sendable {
    case gst, hst, qst, pst, rst, sales

    public func name(_ language: DocumentsLanguage) -> String {
        switch (self, language) {
        case (.gst, .french): "TPS"
        case (.gst, .english): "GST"
        case (.hst, .french): "TVH"
        case (.hst, .english): "HST"
        case (.qst, .french): "TVQ"
        case (.qst, .english): "QST"
        case (.pst, .french): "TVP"
        case (.pst, .english): "PST"
        case (.rst, .french): "TVD"
        case (.rst, .english): "RST"
        case (.sales, .french): "Taxe de vente"
        case (.sales, .english): "Sales tax"
        }
    }

    /// The label before the business's registration number.
    public func numberLabel(_ language: DocumentsLanguage) -> String {
        switch (self, language) {
        case (.sales, .french): "N° de permis de vente"
        case (.sales, .english): "Seller's Permit No."
        case (_, .french): "N° de \(name(.french))"
        case (_, .english): "\(name(.english)) No."
        }
    }
}

/// One tax the business charges: its kind, its rate in millionths (5 % = 50 000), and
/// the business's registration number for it.
public struct TaxRate: Codable, Hashable, Sendable {
    public var kind: TaxKind
    public var rate: Int
    public var number: String

    public init(_ kind: TaxKind, rate: Int, number: String = "") {
        self.kind = kind
        self.rate = rate
        self.number = number
    }
}

/// A province, territory, or state, and the taxes a repair shop there charges by default.
/// The rates are the standard ones known when this was written: Settings lets people
/// change any rate, and US local rates are always theirs to enter.
public struct TaxRegion: Hashable, Sendable, Identifiable {
    public var country: Country
    public var code: String
    /// The English name; the app shows it translated.
    public var name: String
    public var taxes: [TaxRate]
    public var id: String { "\(country.rawValue)-\(code)" }

    public static func find(_ country: Country, _ code: String) -> TaxRegion? {
        country.regions.first { $0.code == code }
    }

    private static let gst = TaxRate(.gst, rate: 50_000)

    public static let provinces: [TaxRegion] = [
        TaxRegion(country: .canada, code: "AB", name: "Alberta", taxes: [gst]),
        TaxRegion(country: .canada, code: "BC", name: "British Columbia", taxes: [gst, TaxRate(.pst, rate: 70_000)]),
        TaxRegion(country: .canada, code: "MB", name: "Manitoba", taxes: [gst, TaxRate(.rst, rate: 70_000)]),
        TaxRegion(country: .canada, code: "NB", name: "New Brunswick", taxes: [TaxRate(.hst, rate: 150_000)]),
        TaxRegion(country: .canada, code: "NL", name: "Newfoundland and Labrador", taxes: [TaxRate(.hst, rate: 150_000)]),
        TaxRegion(country: .canada, code: "NS", name: "Nova Scotia", taxes: [TaxRate(.hst, rate: 140_000)]),
        TaxRegion(country: .canada, code: "NT", name: "Northwest Territories", taxes: [gst]),
        TaxRegion(country: .canada, code: "NU", name: "Nunavut", taxes: [gst]),
        TaxRegion(country: .canada, code: "ON", name: "Ontario", taxes: [TaxRate(.hst, rate: 130_000)]),
        TaxRegion(country: .canada, code: "PE", name: "Prince Edward Island", taxes: [TaxRate(.hst, rate: 150_000)]),
        TaxRegion(country: .canada, code: "QC", name: "Quebec", taxes: [gst, TaxRate(.qst, rate: 99_750)]),
        TaxRegion(country: .canada, code: "SK", name: "Saskatchewan", taxes: [gst, TaxRate(.pst, rate: 60_000)]),
        TaxRegion(country: .canada, code: "YT", name: "Yukon", taxes: [gst]),
    ]

    /// State sales tax base rates in millionths; counties and cities add their own.
    private static let stateRates: [(String, String, Int)] = [
        ("AL", "Alabama", 40_000), ("AK", "Alaska", 0), ("AZ", "Arizona", 56_000), ("AR", "Arkansas", 65_000),
        ("CA", "California", 72_500), ("CO", "Colorado", 29_000), ("CT", "Connecticut", 63_500), ("DE", "Delaware", 0),
        ("DC", "District of Columbia", 60_000), ("FL", "Florida", 60_000), ("GA", "Georgia", 40_000), ("HI", "Hawaii", 40_000),
        ("ID", "Idaho", 60_000), ("IL", "Illinois", 62_500), ("IN", "Indiana", 70_000), ("IA", "Iowa", 60_000),
        ("KS", "Kansas", 65_000), ("KY", "Kentucky", 60_000), ("LA", "Louisiana", 50_000), ("ME", "Maine", 55_000),
        ("MD", "Maryland", 60_000), ("MA", "Massachusetts", 62_500), ("MI", "Michigan", 60_000), ("MN", "Minnesota", 68_750),
        ("MS", "Mississippi", 70_000), ("MO", "Missouri", 42_250), ("MT", "Montana", 0), ("NE", "Nebraska", 55_000),
        ("NV", "Nevada", 68_500), ("NH", "New Hampshire", 0), ("NJ", "New Jersey", 66_250), ("NM", "New Mexico", 48_750),
        ("NY", "New York", 40_000), ("NC", "North Carolina", 47_500), ("ND", "North Dakota", 50_000), ("OH", "Ohio", 57_500),
        ("OK", "Oklahoma", 45_000), ("OR", "Oregon", 0), ("PA", "Pennsylvania", 60_000), ("RI", "Rhode Island", 70_000),
        ("SC", "South Carolina", 60_000), ("SD", "South Dakota", 42_000), ("TN", "Tennessee", 70_000), ("TX", "Texas", 62_500),
        ("UT", "Utah", 61_000), ("VT", "Vermont", 60_000), ("VA", "Virginia", 53_000), ("WA", "Washington", 65_000),
        ("WV", "West Virginia", 60_000), ("WI", "Wisconsin", 50_000), ("WY", "Wyoming", 40_000),
    ]

    public static let states: [TaxRegion] = stateRates.map { code, name, rate in
        TaxRegion(country: .unitedStates, code: code, name: name, taxes: rate == 0 ? [] : [TaxRate(.sales, rate: rate)])
    }
}

extension BusinessProfile {
    /// The region's standard taxes, keeping the registration numbers already entered.
    public mutating func useStandardTaxes() {
        let numbers = Dictionary(taxes.map { ($0.kind, $0.number) }, uniquingKeysWith: { a, _ in a })
        taxes = (TaxRegion.find(country, region)?.taxes ?? []).map { tax in
            var tax = tax
            tax.number = numbers[tax.kind] ?? ""
            return tax
        }
    }

    /// Moves the business to another country or region with its standard taxes.
    public mutating func setRegion(_ country: Country, _ code: String) {
        // A local rate belongs to one place; whether labour is taxed, to one country.
        if country != self.country || code != region { localRate = 0 }
        if country != self.country { taxesLabour = true }
        self.country = country
        region = code
        useStandardTaxes()
    }

    /// The rate each tax is charged at: a US sales tax adds the local rate.
    public var chargedTaxes: [TaxRate] {
        var charged = taxes
        if country == .unitedStates, localRate > 0 {
            if let i = charged.firstIndex(where: { $0.kind == .sales }) {
                charged[i].rate += localRate
            } else {
                charged.append(TaxRate(.sales, rate: localRate))
            }
        }
        return charged
    }

    /// The language a new customer's documents start in.
    public var defaultDocumentsLanguage: DocumentsLanguage {
        country == .canada && region == "QC" ? .french : .english
    }
}
