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
    @State private var approval: ApprovalState = .notNeeded

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
        approval = model.read(.notNeeded) { try $0.approvalState(of: repairID) }
        if !loaded, let repair = row?.repair {
            complaint = repair.complaint
            diagnosis = repair.diagnosis
            loaded = true
        }
    }

    /// In a wide pane the work (complaint, diagnosis, parts, billing) sits beside what
    /// supports it (photos, guides, dates, timeline).
    private func form(_ row: RepairRow) -> some View {
        TwoColumnForm { wide in
            Section {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Text(row.repair.ticket.text)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                    StatusMenu(repairID: row.id, status: row.repair.status, isInternal: row.customer.isShop)
                    if row.customer.isShop { InternalBadge() }
                    ApprovalBadge(state: approval)
                    Spacer()
                }
                if row.customer.isShop {
                    LabeledContent("Owner", value: String(localized: "The shop"))
                } else {
                    LabeledContent("Customer") {
                        Button(row.customer.name) { model.open(.customer(row.customer.id)) }
                            .buttonStyle(.link)
                            .help("Open customer \(row.customer.name)")
                    }
                }
                LabeledContent("Device") {
                    Button(row.device.title) { model.open(.device(row.device.id)) }
                        .buttonStyle(.link)
                        .help("Open device \(row.device.title)")
                }
                if !row.customer.isShop {
                    RepairApprovalRow(repair: row.repair)
                        .id(row.id)
                }
            } header: {
                if wide { Text("Details") }
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
            if !wide { photos(row) }
            Section("Diagnosis") {
                TextField("Diagnosis", text: $diagnosis, prompt: Text("What you found"), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...8)
            }
            if !wide { guides(row) }
            Section("Parts") {
                RepairParts(repair: row.repair, device: row.device)
            }
            if row.customer.isShop {
                Section("Cost") {
                    InternalCostView(repair: row.repair)
                }
            } else {
                Section("Billing") {
                    RepairBilling(repair: row.repair)
                }
                Section("Documents") {
                    RepairDocuments(repair: row.repair)
                }
            }
        } side: { wide in
            if wide {
                photos(row)
                guides(row)
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
        .acceptsAttachments(owner: .repair, id: row.id, model: model)
    }

    private func photos(_ row: RepairRow) -> some View {
        Section("Photos and Files") {
            AttachmentsSection(owner: .repair, ownerID: row.id)
        }
    }

    private func guides(_ row: RepairRow) -> some View {
        Section("Guides") {
            RepairGuides(device: row.device)
        }
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
