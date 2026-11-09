import BenchLogKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Business: what the intake slips, estimates, and invoices print. Each field
/// shows the French label it prints under.
struct BusinessSettings: View {
    @Environment(AppModel.self) private var model
    @State private var profile = BusinessProfile()
    @State private var loaded = false
    @State private var choosingLogo = false
    @State private var hourly: Decimal?
    @State private var tps: Decimal?
    @State private var tvq: Decimal?

    var body: some View {
        Group {
            Section {
                field("Business name", "Nom de l’entreprise", text: $profile.name)
                LabeledContent {
                    TextField("Address", text: $profile.address, axis: .vertical)
                        .labelsHidden()
                        .lineLimit(2...4)
                } label: {
                    printed("Address", "Adresse")
                }
                field("Phone", "Tél.", text: $profile.phone)
                field("Email", "Courriel", text: $profile.email)
                field("Website", "Site web", text: $profile.website)
                LabeledContent {
                    HStack {
                        if let image = logo {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 120, maxHeight: 40)
                            Button("Remove") { model.removeLogo() }
                        }
                        Button(logo == nil ? "Choose…" : "Change…") { choosingLogo = true }
                    }
                } label: {
                    printed("Logo", "En-tête")
                }
            }
            Section("Taxes") {
                field("GST number", "N° de TPS", text: $profile.tpsNumber)
                field("QST number", "N° de TVQ", text: $profile.tvqNumber)
                rate("GST rate", "TPS", value: $tps)
                rate("QST rate", "TVQ", value: $tvq)
            }
            Section("Pricing") {
                LabeledContent {
                    TextField("Hourly rate", value: $hourly, format: Money.format).labelsHidden().multilineTextAlignment(.trailing)
                } label: {
                    Text("Hourly rate")
                    Text("New labour lines start at this rate").font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $profile.estimateValidDays, in: 1...365) {
                    LabeledContent {
                        Text("^[\(profile.estimateValidDays) day](inflect: true)").monospacedDigit()
                    } label: {
                        printed("Estimates are valid for", "Valide jusqu’au")
                    }
                }
            }
            Section("Printed Text") {
                text("Warranty, in French", "Garantie", $profile.warrantyFrench)
                text("Warranty, in English", "Warranty", $profile.warrantyEnglish)
                text("Terms, in French", "Conditions", $profile.termsFrench)
                text("Terms, in English", "Terms", $profile.termsEnglish)
            }
            Section {
                HStack {
                    Spacer()
                    Button("Save") { save() }
                        .keyboardShortcut("s")
                        .help("Save the business details (⌘S); new documents use them")
                }
            } footer: {
                Text("Documents already issued keep the details and rates they printed with.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $choosingLogo, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                model.setLogo(from: url)
                if access { url.stopAccessingSecurityScopedResource() }
            }
        }
        .task(id: model.dataVersion) {
            let saved = model.read(BusinessProfile()) { try $0.businessProfile() }
            if !loaded {
                profile = saved
                hourly = Money.decimal(saved.hourlyRateCents)
                tps = Decimal(saved.tpsRate) / 10_000
                tvq = Decimal(saved.tvqRate) / 10_000
                loaded = true
            } else {
                profile.logoPath = saved.logoPath
            }
        }
        .onDisappear(perform: save)
    }

    private var logo: NSImage? {
        guard let library = model.library, !profile.logoPath.isEmpty else { return nil }
        return NSImage(contentsOf: library.filesURL.appending(path: profile.logoPath))
    }

    private func save() {
        var changed = profile
        changed.hourlyRateCents = Money.cents(hourly) ?? profile.hourlyRateCents
        changed.tpsRate = tps.map { Self.millionths($0) } ?? profile.tpsRate
        changed.tvqRate = tvq.map { Self.millionths($0) } ?? profile.tvqRate
        let saved = model.read(BusinessProfile()) { try $0.businessProfile() }
        changed.logoPath = saved.logoPath
        guard changed != saved else { return }
        model.save(changed)
    }

    /// 9.975 (percent) → 99 750 millionths.
    static func millionths(_ percent: Decimal) -> Int {
        var scaled = percent * 10_000
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// The field's name, and below it what it prints as.
    private func printed(_ title: LocalizedStringKey, _ french: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text("Prints as « \(french) »").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func field(_ title: LocalizedStringKey, _ french: String, text: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: text).labelsHidden()
        } label: {
            printed(title, french)
        }
    }

    private func rate(_ title: LocalizedStringKey, _ french: String, value: Binding<Decimal?>) -> some View {
        LabeledContent {
            HStack(spacing: Space.xs) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0...4)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(verbatim: "%").foregroundStyle(.secondary)
            }
        } label: {
            printed(title, french)
        }
    }

    private func text(_ title: LocalizedStringKey, _ printedAs: String, _ binding: Binding<String>) -> some View {
        LabeledContent {
            TextField(title, text: binding, axis: .vertical).labelsHidden().lineLimit(2...5)
        } label: {
            printed(title, printedAs)
        }
    }
}
