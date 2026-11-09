import BenchLogKit
import SwiftUI

/// The notes on a customer, device, or repair, oldest first, with the Add Note field
/// at the bottom. Status notes are written by BenchLog and cannot be edited.
struct Timeline: View {
    @Environment(AppModel.self) private var model
    let owner: NoteOwner
    let ownerID: UUID

    @State private var notes: [Note] = []
    @State private var draft = ""
    @State private var editing: UUID?
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if notes.isEmpty {
                Text("No notes yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(notes) { note in
                row(note)
            }
            TextField("Add a note…", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($fieldFocused)
                .onSubmit(add)
                .accessibilityLabel(Text("Add Note"))
        }
        .task(id: [model.dataVersion, ownerID.hashValue]) {
            notes = model.read([]) { try $0.notes(for: owner, id: ownerID) }
        }
        .onChange(of: model.focusNoteField, initial: true) { _, wanted in
            if wanted {
                fieldFocused = true
                model.focusNoteField = false
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.addNote(text, to: owner, id: ownerID)
        draft = ""
        fieldFocused = true
    }

    @ViewBuilder
    private func row(_ note: Note) -> some View {
        if let status = note.status {
            HStack(spacing: Space.sm) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.color)
                    .frame(width: 16)
                Text("Status → \(status.title)")
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else if note.kind == .estimate {
            let approved = note.text == EstimateDecision.approved.rawValue
            HStack(spacing: Space.sm) {
                Image(systemName: approved ? "hand.thumbsup" : "hand.thumbsdown")
                    .foregroundStyle(approved ? .green : .red)
                    .frame(width: 16)
                Text(approved ? "Estimate approved" : "Estimate refused")
                Spacer()
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        } else if editing == note.id {
            TextField("Note", text: $editText, axis: .vertical)
                .lineLimit(1...8)
                .onSubmit {
                    model.editNote(note.id, text: editText)
                    editing = nil
                }
                .onExitCommand { editing = nil }
        } else {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(note.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .contextMenu {
                Button("Edit Note") {
                    editText = note.text
                    editing = note.id
                }
                Button("Move to Trash", role: .destructive) { model.trashNote(note.id) }
            }
        }
    }
}
