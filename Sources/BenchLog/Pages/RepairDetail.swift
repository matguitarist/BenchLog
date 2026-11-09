import BenchLogKit
import SwiftUI

/// One repair: ticket and status, its customer and device as links, the complaint,
/// the diagnosis, the dates, and the timeline.
struct RepairDetail: View {
    @Environment(AppModel.self) private var model
    let repairID: UUID

    @State private var row: RepairRow?
    @State private var complaint = ""
    @State private var diagnosis = ""
    @State private var loaded = false

    var body: some View {
        Group {
            if let row {
                form(row)
            } else {
                ContentUnavailableView("No Repair Selected", systemImage: "wrench.and.screwdriver")
            }
        }
        .task(id: model.dataVersion) { load() }
        // Typing saves after a short pause, so every keystroke is not a write.
        .task(id: complaint + "\u{0}" + diagnosis) {
            guard loaded, let repair = row?.repair,
                  repair.complaint != complaint || repair.diagnosis != diagnosis,
                  !complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            var changed = repair
            changed.complaint = complaint
            changed.diagnosis = diagnosis
            model.update(changed)
        }
    }

    private func load() {
        row = model.read(nil) { try $0.repairRow(repairID) }
        if !loaded, let repair = row?.repair {
            complaint = repair.complaint
            diagnosis = repair.diagnosis
            loaded = true
        }
    }

    private func form(_ row: RepairRow) -> some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Text(row.repair.ticket.text)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    StatusMenu(repairID: row.id, status: row.repair.status)
                    Spacer()
                }
                LabeledContent("Customer") {
                    Button(row.customer.name) { model.open(.customer(row.customer.id)) }
                        .buttonStyle(.link)
                        .help("Open customer \(row.customer.name)")
                }
                LabeledContent("Device") {
                    Button(row.device.title) { model.open(.device(row.device.id)) }
                        .buttonStyle(.link)
                        .help("Open device \(row.device.title)")
                }
            }
            Section("Complaint") {
                TextField("Complaint", text: $complaint, prompt: Text("What the customer says is wrong"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...8)
                if complaint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Describe the complaint.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Section("Photos and Files") {
                AttachmentsSection(owner: .repair, ownerID: row.id)
            }
            Section("Diagnosis") {
                TextField("Diagnosis", text: $diagnosis, prompt: Text("What you found"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...8)
            }
            Section("Dates") {
                LabeledContent("Received", value: row.repair.receivedAt.formatted(date: .abbreviated, time: .shortened))
                PromisedDate(repair: row.repair)
                if let done = row.repair.completedAt {
                    LabeledContent("Ready", value: done.formatted(date: .abbreviated, time: .shortened))
                }
                if let picked = row.repair.pickedUpAt {
                    LabeledContent("Picked Up", value: picked.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("On the bench") {
                    Text("\(row.repair.benchDays()) days").monospacedDigit()
                }
            }
            Section("Timeline") {
                Timeline(owner: .repair, ownerID: row.id)
            }
        }
        .formStyle(.grouped)
        .acceptsAttachments(owner: .repair, id: row.id, model: model)
    }
}

/// The promised date: a switch, and a date picker when it is on.
private struct PromisedDate: View {
    @Environment(AppModel.self) private var model
    let repair: Repair

    var body: some View {
        Toggle("Promised", isOn: Binding(
            get: { repair.promisedAt != nil },
            set: { on in
                var changed = repair
                changed.promisedAt = on ? Calendar.current.date(byAdding: .day, value: 3, to: .now) : nil
                model.update(changed)
            }))
        if let promised = repair.promisedAt {
            DatePicker("Promised for", selection: Binding(
                get: { promised },
                set: { date in
                    var changed = repair
                    changed.promisedAt = date
                    model.update(changed)
                }), displayedComponents: .date)
        }
    }
}
