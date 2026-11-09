import BenchLogKit
import SwiftUI

/// Search BenchLog (⌘F): one field over the main window that finds customers, phones,
/// devices, serials, tickets, notes, parts, and guides at once. Results are grouped by
/// kind; the arrows move, Return opens the selected result (the top hit at first), and
/// Escape or a click outside closes it.
struct SearchPanel: View {
    @Environment(AppModel.self) private var model
    @State private var hits: [SearchHit] = []
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var text: String { model.searchText }

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack(spacing: Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                TextField("Search BenchLog", text: $model.searchText,
                          prompt: Text("Customers, phones, serials, tickets, notes, parts, guides"))
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(openSelected)
            }
            .padding(Space.md)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider()
                if hits.isEmpty {
                    Text("Nothing matches “\(text)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(Space.xl)
                } else {
                    results
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        .onAppear { focused = true }
        .onChange(of: model.searchText, initial: true) {
            hits = model.read([]) { try $0.search(text) }
            selected = 0
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { model.searching = false; return .handled }
        .accessibilityAddTraits(.isModal)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        if index == 0 || hits[index - 1].kind != hit.kind {
                            Text(hit.kind.pluralTitle)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Space.md)
                                .padding(.top, index == 0 ? Space.sm : Space.md)
                                .padding(.bottom, Space.xs)
                        }
                        SearchRow(hit: hit, selected: index == selected)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = index
                                openSelected()
                            }
                    }
                }
                .padding(.horizontal, Space.sm)
                .padding(.bottom, Space.sm)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: selected) { proxy.scrollTo(selected) }
        }
    }

    private func move(_ delta: Int) {
        guard !hits.isEmpty else { return }
        selected = min(max(selected + delta, 0), hits.count - 1)
    }

    private func openSelected() {
        guard hits.indices.contains(selected) else { return }
        model.open(hits[selected])
    }
}

/// One result: the kind's symbol, a title, and what it belongs to.
private struct SearchRow: View {
    let hit: SearchHit
    let selected: Bool

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: hit.kind.symbol)
                .frame(width: 20)
                .foregroundStyle(selected ? .white : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title)
                    .lineLimit(1)
                if !hit.subtitle.isEmpty {
                    Text(hit.subtitle)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs + 2) // grid: ok 6 pt row padding, like a list row
        .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6)) // grid: ok the radius of a macOS list selection
        .help(hit.subtitle.isEmpty ? hit.title : "\(hit.title) — \(hit.subtitle)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Opens the find bar of the guide reader in front. Equal when it is the same guide, so
/// the menu does not rebuild on every update.
struct GuideFindAction: Equatable {
    let guideID: UUID
    let open: () -> Void

    func callAsFunction() { open() }
    static func == (a: Self, b: Self) -> Bool { a.guideID == b.guideID }
}

extension FocusedValues {
    /// Edit > Find in Guide… uses it.
    @Entry var guideFind: GuideFindAction?
}

/// Edit > Search BenchLog… (⌘F), and Find in Guide… (⌘F) when a PDF guide is in front;
/// Search then moves to ⌥⌘F.
struct FindCommands: Commands {
    let model: AppModel
    @FocusedValue(\.guideFind) private var guideFind

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Search BenchLog…") {
                model.searchText = ""
                model.searching = true
            }
                .keyboardShortcut(guideFind == nil ? KeyboardShortcut("f") : KeyboardShortcut("f", modifiers: [.command, .option]))
                .disabled(model.library == nil || model.sheet != nil)
            if let guideFind {
                Button("Find in Guide…") { guideFind() }
                    .keyboardShortcut("f")
            }
        }
    }
}
