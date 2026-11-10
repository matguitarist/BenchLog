import BenchLogKit
import SwiftUI

/// What one scan did.
enum ScanResult: Equatable {
    /// The text is not a UPC or EAN.
    case invalid
    /// One unit went into stock; `isNew` when the scan created the part.
    case added(Part, isNew: Bool)
    /// No part has the barcode and the lookup found no product (or failed, with why).
    case unknown(barcode: String, problem: String?)
}

/// Add by Barcode: each scan puts one unit on the shelf. A barcode the inventory knows adds
/// to its part; a new one is looked up online and becomes a part; an unknown one asks for a name.
/// A USB or Bluetooth scanner types the digits and Return into the field.
struct BarcodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Parts shown as already added (snapshots).
    var start: [UUID] = []

    @State private var code = ""
    @State private var busy = false
    @State private var invalid = false
    @State private var unknown: String?
    @State private var problem: String?
    @State private var name = ""
    @State private var added: [Entry] = []
    @FocusState private var focus: Field?

    private enum Field { case code, name }

    private struct Entry: Identifiable {
        let id = UUID()
        var part: Part
        var isNew: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add by Barcode")
                .font(.headline)
                .padding(.top, Space.lg)
            Form {
                Section {
                    HStack(spacing: Space.sm) {
                        TextField("Barcode", text: $code, prompt: Text("Scan or type a UPC or EAN"))
                            .focused($focus, equals: .code)
                            .onSubmit(scan)
                            .disabled(busy)
                        if busy { ProgressView().controlSize(.small) }
                    }
                    if invalid {
                        Text("That is not a barcode. Check the digits.").font(.callout).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Each scan adds one to stock. A new barcode is looked up at upcitemdb.com; only the barcode is sent.")
                }
                if let unknown {
                    Section {
                        if let problem { Text(problem).font(.callout).foregroundStyle(.orange) }
                        TextField("Name", text: $name, prompt: Text("What is it?"))
                            .focused($focus, equals: .name)
                            .onSubmit(addNamed)
                        HStack {
                            Spacer()
                            Button("Skip") { clearUnknown() }
                                .help("Leave this barcode out")
                            Button("Add Part", action: addNamed)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("No product found for \(unknown)")
                    }
                }
                if !added.isEmpty {
                    Section("Added") {
                        ForEach(added.reversed()) { entry in
                            HStack(spacing: Space.sm) {
                                Image(systemName: entry.part.kind.symbol)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                    .accessibilityLabel(Text(entry.part.kind.title))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.part.name).lineLimit(1).help(entry.part.name)
                                    Text(entry.isNew ? "New part · \(entry.part.quantity) in stock" : "\(entry.part.quantity) in stock")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Edit…") { model.sheet = .editPart(entry.part.id) }
                                    .help("Set its kind, cost, and price")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 520)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Space.lg)
        }
        .frame(width: 480)
        .onAppear {
            added = start.compactMap { id in model.read(nil) { try $0.part(id) } }.map { Entry(part: $0, isNew: false) }
            focus = .code
        }
    }

    private func scan() {
        let text = code
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !busy else { return }
        clearUnknown()
        busy = true
        Task {
            let result = await model.addScanned(text)
            busy = false
            switch result {
            case .invalid:
                invalid = true
                focus = .code
            case .added(let part, let isNew):
                code = ""
                added.append(Entry(part: part, isNew: isNew))
                focus = .code
            case .unknown(let barcode, let why):
                code = ""
                unknown = barcode
                problem = why
                focus = .name
            }
        }
    }

    private func addNamed() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let unknown, !trimmed.isEmpty else { return }
        if let part = model.save(Part(name: trimmed, quantity: 1, barcode: unknown), fits: []) {
            added.append(Entry(part: part, isNew: true))
        }
        clearUnknown()
    }

    private func clearUnknown() {
        invalid = false
        unknown = nil
        problem = nil
        name = ""
        focus = .code
    }
}
