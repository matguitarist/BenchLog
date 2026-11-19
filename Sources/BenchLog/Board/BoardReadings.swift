import BenchLogKit
import BoardViewKit
import SwiftUI

/// A reading drawn on the board.
struct ReadingTag: Equatable {
    var position: BoardPoint
    /// nil shows on both sides.
    var side: BoardSide?
    var text: String
}

// S-084: meter readings on a pin or net, kept on the repair and shown on the board.
extension BoardViewer {
    /// What a reading would be taken on: a pin ("U7100.3"), or a net (also a test point's).
    var readingTarget: (name: String, isPin: Bool)? {
        guard let board else { return nil }
        switch selection {
        case .pin(let index):
            let pin = board.pins[index]
            return ("\(board.parts[pin.part].name).\(pin.number)", true)
        case .net(let name):
            return (name, false)
        case .testPoint(let index):
            let net = board.testPoints[index].net
            return net.isEmpty ? nil : (net, false)
        case .part, nil:
            return nil
        }
    }

    func reloadReadings() {
        guard let repair = readingRepair, let model else { readings = []; return }
        readings = model.read([]) { try $0.boardReadings(repair: repair, board: boardName) }
    }

    /// Saves a reading on the selected pin or net. False when there is no target or the
    /// value isn't a reading.
    @discardableResult
    func addReading(mode: ReadingMode, text: String, note: String) -> Bool {
        guard let repair = readingRepair, let target = readingTarget, let model, let value = mode.parse(text) else { return false }
        let reading = BoardReading(repairId: repair, board: boardName, target: target.name, isPin: target.isPin,
                                   mode: mode, value: value, note: note)
        let saved = model.write("Added a \(mode.rawValue) reading on \(target.name) to repair \(repair.stored)") {
            try $0.addBoardReading(reading)
        }
        reloadReadings()
        return saved != nil
    }

    func deleteReading(_ id: UUID) {
        model?.write("Deleted board reading \(id.stored)") { try $0.trash(BoardReading.self, id: id) }
        reloadReadings()
    }

    /// Selects what a reading was taken on.
    func select(reading: BoardReading) {
        guard let board else { return }
        if reading.isPin {
            let parts = reading.target.split(separator: ".")
            guard parts.count >= 2, let part = board.part(named: parts.dropLast().joined(separator: ".")),
                  let number = Int(parts.last!) else { return }
            let range = board.parts[part].pins
            guard let pin = range.first(where: { board.pins[$0].number == number }) else { return }
            select(.pin(pin), from: .search)
        } else if let net = board.net(named: reading.target) {
            select(.net(net), from: .search)
        }
    }

    /// Readings on the selection, for the bar: ". Diode 0.38 V, OL".
    var readingNote: String {
        guard let target = readingTarget else { return "" }
        let mine = readings.filter { $0.target == target.name && $0.isPin == target.isPin }
        guard !mine.isEmpty else { return "" }
        return ". " + mine.suffix(3).map { "\($0.mode.label) \($0.mode.format($0.value))" }.joined(separator: ", ")
    }

    /// One tag per pin or net, with its latest reading: on the pin, or on a net's first test
    /// point (else its first pin on each side).
    var readingTags: [ReadingTag] {
        guard let board else { return [] }
        var latest: [String: BoardReading] = [:]
        for reading in readings { latest[(reading.isPin ? "pin:" : "net:") + reading.target] = reading }
        return latest.values.sorted { $0.createdAt < $1.createdAt }.flatMap { reading -> [ReadingTag] in
            let text = reading.mode.format(reading.value)
            if reading.isPin {
                let parts = reading.target.split(separator: ".")
                guard parts.count >= 2, let part = board.part(named: parts.dropLast().joined(separator: ".")),
                      let pin = board.parts[part].pins.first(where: { board.pins[$0].number == Int(parts.last!) }) else { return [] }
                let p = board.parts[part]
                return [ReadingTag(position: board.pins[pin].position, side: p.isThroughHole ? nil : p.side, text: text)]
            }
            guard let net = board.net(named: reading.target) else { return [] }
            if let point = board.testPoints(onNet: net).first {
                return [ReadingTag(position: board.testPoints[point].position, side: board.testPoints[point].side, text: text)]
            }
            return BoardSide.allCases.compactMap { side in
                board.pins(onNet: net).first { board.shows(pin: $0, on: side) }
                    .map { ReadingTag(position: board.pins[$0].position, side: side, text: text) }
            }
        }
    }
}

/// The Readings popover: add a reading on the selection, and the repair's readings on this board.
struct ReadingsView: View {
    @Bindable var viewer: BoardViewer
    @AppStorage("boardReadingMode") private var mode: ReadingMode = .diode
    @State private var value = ""
    @State private var note = ""
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if viewer.readingRepair == nil {
                ContentUnavailableView {
                    Label("No Repair", systemImage: "gauge.with.dots.needle.33percent")
                } description: {
                    Text("Readings are kept on a repair. Open this board from a repair, or from a device with a repair in progress.")
                }
            } else {
                form
                Divider()
                list
            }
        }
        .padding(Space.lg)
        .gridArea("board-readings", inset: Space.lg)
    }

    @ViewBuilder private var form: some View {
        if let target = viewer.readingTarget {
            Text(target.isPin ? "Pin \(target.name)" : "Net \(target.name)")
                .font(.headline)
            Picker("Mode", selection: $mode) {
                ForEach(ReadingMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack(spacing: Space.sm) {
                TextField("Value", text: $value, prompt: Text(mode == .resistance ? "12k, OL" : mode == .diode ? "0.452, OL" : "3.3"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 112)
                    .onSubmit(add)
                TextField("Note", text: $note, prompt: Text("Note (optional)"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
            }
            HStack {
                if invalid {
                    Text("Type a number, with k or M for ohms, or OL.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Add Reading", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            Text("Select a pin, a net, or a test point to add a reading.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var list: some View {
        if viewer.readings.isEmpty {
            Text("No readings on this board yet.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(viewer.readings.reversed()) { reading in
                        Button { viewer.select(reading: reading) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                Text(reading.target).fontWeight(.medium)
                                Text("\(reading.mode.label) \(reading.mode.format(reading.value))")
                                    .monospacedDigit()
                                Text(reading.note)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(reading.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help("Select \(reading.target) on the board")
                        .contextMenu {
                            Button("Delete Reading", role: .destructive) { viewer.deleteReading(reading.id) }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
    }

    private func add() {
        invalid = !viewer.addReading(mode: mode, text: value, note: note)
        if !invalid {
            value = ""
            note = ""
        }
    }
}
