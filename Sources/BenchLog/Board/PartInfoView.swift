import BoardViewKit
import SwiftUI

/// Part Info: what a part is, its value and ratings from the schematic, the pages it is on, and its pins.
struct PartInfoView: View {
    @Bindable var viewer: BoardViewer
    let partIndex: Int

    var body: some View {
        if let board = viewer.board, board.parts.indices.contains(partIndex) {
            let part = board.parts[partIndex]
            Form {
                Section {
                    LabeledContent("Type", value: PartType(partName: part.name).map(BoardViewer.word(for:))?.localizedCapitalized
                                   ?? String(localized: "Unknown"))
                    LabeledContent("Side", value: part.side == .top ? String(localized: "Top") : String(localized: "Bottom"))
                } header: {
                    Text(part.name).font(.title3.bold()).foregroundStyle(.primary)
                }
                Section("Schematic") { schematic(part) }
                Section("Pins") { pins(part, board) }
                ExplainSection(viewer: viewer, partIndex: partIndex)
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func schematic(_ part: BoardPart) -> some View {
        if let value = viewer.value(ofPart: partIndex) {
            ForEach(Self.fields(of: value), id: \.0) { label, text in
                LabeledContent(label) { Text(text).textSelection(.enabled) }
            }
        } else if viewer.isReadingFacts {
            LabeledContent("Value") { ProgressView().controlSize(.small) }
        } else {
            Text(viewer.schematic == nil ? "No schematic is open beside the board." : "The schematic gives no value for this part.")
                .foregroundStyle(.secondary)
        }
        if let pages = viewer.facts.pages[part.name.uppercased()], !pages.isEmpty {
            LabeledContent(pages.count == 1 ? "Page" : "Pages") {
                HStack(spacing: Space.xs) {
                    ForEach(pages.prefix(8), id: \.self) { page in
                        Button("\(page + 1)") { viewer.openPageLarge(page) }
                            .help("See page \(page + 1) large")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pins(_ part: BoardPart, _ board: Board) -> some View {
        let all = part.pins.map { board.pins[$0] }
        let grounds = all.filter { Board.isGround($0.net) }
        ForEach(all.filter { !Board.isGround($0.net) }, id: \.number) { pin in
            LabeledContent {
                if pin.net.isEmpty {
                    Text("No net").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(pin.net).textSelection(.enabled)
                        let note = BoardViewer.netNote(pin.net).dropFirst(2)
                        if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } label: {
                Text("Pin \(pin.number)").monospacedDigit()
            }
        }
        if !grounds.isEmpty {
            let nets = Set(grounds.map(\.net)).sorted().joined(separator: ", ")
            LabeledContent(grounds.count == 1 ? String(localized: "Pin \(grounds[0].number)") : String(localized: "\(grounds.count) pins"), value: nets)
        }
    }

    /// The value's fields that the schematic gives, with their labels.
    static func fields(of value: PartValue) -> [(String, String)] {
        [
            (String(localized: "Part Number"), value.partNumber), (String(localized: "Value"), value.value),
            (String(localized: "Tolerance"), value.tolerance), (String(localized: "Voltage"), value.voltage),
            (String(localized: "Current"), value.current), (String(localized: "Power"), value.power),
            (String(localized: "Dielectric"), value.dielectric), (String(localized: "Package"), value.package),
        ].compactMap { label, text in text.map { (label, $0) } }
    }
}

/// Explain This Part: placeholder until S-080.
private struct ExplainSection: View {
    @Bindable var viewer: BoardViewer
    let partIndex: Int

    var body: some View { EmptyView() }
}
