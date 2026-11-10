import BenchLogKit
import SwiftUI
import UniformTypeIdentifiers

extension ReportLength {
    var title: String {
        switch self {
        case .month: String(localized: "Month")
        case .quarter: String(localized: "Quarter")
        case .year: String(localized: "Year")
        }
    }
}

extension ReportPeriod {
    /// "November 2026", "Q4 2026", or "2026".
    var title: String {
        let year = Calendar.current.component(.year, from: start)
        switch length {
        case .month: return start.formatted(.dateTime.month(.wide).year())
        case .quarter: return String(localized: "Q\(Calendar.current.component(.month, from: start) / 3 + 1) \(String(year))")
        case .year: return String(year)
        }
    }
}

/// Reports: what was invoiced in a month, quarter, or year, the tax collected for each
/// tax, and every invoice and credit note behind it, ready to file or export.
struct ReportsPage: View {
    @Environment(AppModel.self) private var model
    @State private var report: SalesReport?
    @State private var inventory: InventoryValue?
    @State private var selection: UUID?
    @State private var exporting = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let report, !report.rows.isEmpty {
                summary(report)
                if let inventory { inventoryLine(inventory) }
                Divider()
                documents(report)
            } else {
                ContentUnavailableView {
                    Label("No Invoices in \(model.reportPeriod.title)", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("Invoices and credit notes issued in the period show here, with the tax collected.")
                } actions: {
                    Button("Show the Year") { model.reportPeriod = ReportPeriod(.year, containing: model.reportPeriod.start) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.reportPeriod.length == .year)
                }
            }
        }
        .navigationTitle("Reports")
        .navigationSubtitle(model.reportPeriod.title)
        .toolbar {
            ToolbarItem {
                Picker("Period", selection: Binding(get: { model.reportPeriod.length },
                                                    set: { model.reportPeriod = ReportPeriod($0, containing: model.reportPeriod.start) })) {
                    ForEach(ReportLength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Report on a month, a quarter, or a year")
            }
            ToolbarItem {
                ControlGroup {
                    Button("Previous", systemImage: "chevron.left") { model.reportPeriod = model.reportPeriod.moved(by: -1) }
                        .help("Show the period before")
                    Button("Next", systemImage: "chevron.right") { model.reportPeriod = model.reportPeriod.moved(by: 1) }
                        .help("Show the period after")
                }
            }
            ToolbarItem {
                Button("Export CSV…", systemImage: "square.and.arrow.up") { exporting = true }
                    .disabled(report?.rows.isEmpty ?? true)
                    .help("Save the period's invoices and credit notes as a spreadsheet, one tax per column")
            }
        }
        .fileExporter(isPresented: $exporting, document: CSVFile(text: report?.csv() ?? ""), contentType: .commaSeparatedText,
                      defaultFilename: "BenchLog \(model.reportPeriod.title).csv") { _ in }
        .task(id: "\(model.dataVersion) \(model.reportPeriod.start) \(model.reportPeriod.length)") {
            report = model.read(nil) { try $0.salesReport(model.reportPeriod) }
            let end = model.reportPeriod.end()
            inventory = model.read(nil) { try $0.inventoryValue(at: end > .now ? nil : end) }
        }
    }

    /// Sales before taxes, each tax, the total, and what was collected and is still owed.
    private func summary(_ report: SalesReport) -> some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            figure("Sales before taxes", report.salesCents)
            ForEach(report.taxKinds, id: \.self) { kind in
                figure(LocalizedStringKey(kind.title), report.taxCents(kind))
            }
            figure("Total", report.totalCents, bold: true)
            Spacer(minLength: Space.lg)
            figure("Collected", report.collectedCents)
            figure("Owed", report.owedCents, color: report.owedCents > 0 ? .orange : nil)
        }
        .padding(Space.margin)
    }

    /// The stock's value at the end of the period (now, for the current one).
    private func inventoryLine(_ value: InventoryValue) -> some View {
        let end = model.reportPeriod.end()
        return HStack(spacing: Space.sm) {
            Image(systemName: "shippingbox").foregroundStyle(.secondary)
            Group {
                if end > .now {
                    Text("Inventory at cost today: \(Money.text(value.totalCents))")
                } else {
                    Text("Inventory at cost on \((end - 1).formatted(date: .abbreviated, time: .omitted)): \(Money.text(value.totalCents))")
                }
            }
            .monospacedDigit()
            Text("Parts \(Money.text(value.partsCostCents)) · shop devices \(Money.text(value.devicesCostCents))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if value.partsWithoutCost > 0 {
                Label("Parts without cost: \(value.partsWithoutCost)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("Parts in stock with no cost count as zero")
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.md)
        .help("Past quantities come from each part's stock history; costs are today's")
    }

    private func figure(_ title: LocalizedStringKey, _ cents: Int, bold: Bool = false, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.text(cents))
                .font(.title3.weight(bold ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(color ?? .primary)
        }
    }

    private func documents(_ report: SalesReport) -> some View {
        Table(report.rows, selection: $selection) {
            TableColumn("Date") { row in Text(row.invoice.issuedAt.formatted(date: .abbreviated, time: .omitted)) }
                .width(min: 90, ideal: 110)
            TableColumn("Number") { row in Text(row.invoice.numberText ?? "").monospacedDigit() }
                .width(min: 70, ideal: 80)
            TableColumn("Customer") { row in
                let name = row.customer.isEmpty ? String(localized: "Walk-in") : row.customer
                Text(name).lineLimit(1).help(name)
            }
            TableColumn("Subtotal") { row in amount(row.subtotalCents) }
                .width(min: 80, ideal: 100)
            TableColumn("Taxes") { row in amount(row.taxes.reduce(0) { $0 + $1.cents }) }
                .width(min: 80, ideal: 100)
            TableColumn("Total") { row in amount(row.totalCents) }
                .width(min: 80, ideal: 100)
            TableColumn("Status") { row in ReportStatus(row: row) }
                .width(min: 90, ideal: 110)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let row = report.rows.first(where: { ids.contains($0.id) }) {
                Button("Open PDF") { model.open(row.invoice) }.disabled(row.invoice.fileId == nil)
                if let repair = row.invoice.repairId { Button("Open Repair") { model.open(.repair(repair)) } }
                if let device = row.invoice.deviceId { Button("Open Device") { model.open(.device(device)) } }
                if let customer = row.invoice.customerId, !row.customer.isEmpty { Button("Open Customer") { model.open(.customer(customer)) } }
            }
        } primaryAction: { ids in
            guard let row = report.rows.first(where: { ids.contains($0.id) }) else { return }
            if let repair = row.invoice.repairId {
                model.open(.repair(repair))
            } else if let device = row.invoice.deviceId {
                model.open(.device(device))
            } else if let customer = row.invoice.customerId, !row.customer.isEmpty {
                model.open(.customer(customer))
            } else {
                model.open(row.invoice)
            }
        }
    }

    private func amount(_ cents: Int) -> some View {
        Text(Money.text(cents)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// Paid, Unpaid, Credited, Refunded, or Not Refunded: words and a symbol.
private struct ReportStatus: View {
    let row: ReportRow

    var body: some View {
        let (text, symbol, color): (String, String, Color) = switch (row.invoice.kind, row.isSettled, row.isCredited) {
        case (.creditNote, true, _): (String(localized: "Refunded"), "checkmark.circle.fill", .green)
        case (.creditNote, false, _): (String(localized: "Not Refunded"), "circle", .secondary)
        case (_, _, true): (String(localized: "Credited"), "arrow.uturn.backward.circle", .secondary)
        case (_, true, _): (String(localized: "Paid"), "checkmark.circle.fill", .green)
        default: (String(localized: "Unpaid"), "circle", .orange)
        }
        Label(text, systemImage: symbol).foregroundStyle(color)
    }
}

/// The report's CSV for Export CSV….
struct CSVFile: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
