import BenchLogKit
import SwiftUI

extension TaxRegion {
    /// The province's or state's name in the app's language.
    var title: String { String(localized: String.LocalizationValue(name)) }
}

extension Country {
    var title: String { Locale.current.localizedString(forRegionCode: rawValue) ?? rawValue }
    var regionTitle: String {
        self == .canada ? String(localized: "Province or territory") : String(localized: "State")
    }
}

/// Settings → Business → Taxes: where the business is, and each tax it charges with its
/// rate and registration number. Picking a place fills in its standard taxes.
struct TaxSection: View {
    @Binding var profile: BusinessProfile

    var body: some View {
        Section {
            Picker("Country", selection: Binding(get: { profile.country }, set: { country in
                guard country != profile.country else { return }
                profile.setRegion(country, country == .canada ? "QC" : country.regions[0].code)
            })) {
                ForEach(Country.allCases) { Text($0.title).tag($0) }
            }
            Picker(profile.country.regionTitle, selection: Binding(get: { profile.region }, set: { profile.setRegion(profile.country, $0) })) {
                ForEach(profile.country.regions) { Text($0.title).tag($0.code) }
            }
            if profile.taxes.isEmpty {
                LabeledContent("Sales tax") {
                    Text("None at the state level").foregroundStyle(.secondary)
                }
            }
            ForEach($profile.taxes, id: \.kind) { $tax in
                LabeledContent {
                    HStack(spacing: Space.sm) {
                        TextField("Registration number", text: $tax.number, prompt: Text("Registration number"))
                            .labelsHidden()
                            .help("Your \(tax.kind.title) number; it prints at the bottom of estimates and invoices")
                        PercentField(title: tax.kind.title, millionths: $tax.rate)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tax.kind.title)
                        Text("Prints as « \(tax.kind.name(.french)) » and “\(tax.kind.name(.english))”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if profile.country == .unitedStates {
                LabeledContent {
                    PercentField(title: String(localized: "Local rate"), millionths: $profile.localRate)
                } label: {
                    Text("Local rate")
                    Text("Your county and city rate, added to the state's").font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $profile.taxesLabour) {
                    Text("Tax labour")
                    Text("Turn off where repair labour is not taxed: only parts are taxed then").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Taxes")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.country == .unitedStates
                     ? "The state's base rate is filled in. Check your rates with your state."
                     : "The standard rates for the province are filled in.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Use Standard Rates") { profile.useStandardTaxes() }
                    .help("Put back the standard rates for this province or state; numbers stay")
            }
        }
    }
}

/// A rate in millionths, typed as a percentage: 9.975 % is 99 750.
struct PercentField: View {
    let title: String
    @Binding var millionths: Int

    var body: some View {
        HStack(spacing: Space.xs) {
            TextField(title, value: Binding(get: { Decimal(millionths) / 10_000 },
                                            set: { millionths = BusinessSettings.millionths($0) }),
                      format: .number.precision(.fractionLength(0...4)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text(verbatim: "%").foregroundStyle(.secondary)
        }
    }
}
