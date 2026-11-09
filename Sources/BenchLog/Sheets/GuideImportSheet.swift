import BenchLogKit
import SwiftUI

/// Import Guides: the guides found in a folder, with the models BenchLog guessed from the
/// folder names. Fix a guess or leave a guide out, then Import.
struct GuideImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let folder: URL

    @State private var candidates: [GuideCandidate] = []
    @State private var skipped: Set<String> = []
    @State private var scanning = true
    @State private var failure: String?
    @State private var editing: GuideCandidate.ID?
    @State private var draft = GuideLinkDraft()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.xs) {
                Text("Import Guides from “\(folder.lastPathComponent)”").font(.headline)
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.top, Space.lg)
            .padding(.bottom, Space.md)
            Group {
                if scanning {
                    ProgressView("Reading the folder…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let failure {
                    ContentUnavailableView("Unable to Read the Folder", systemImage: "folder.badge.questionmark", description: Text(failure))
                } else if candidates.isEmpty {
                    ContentUnavailableView("No Guides in This Folder", systemImage: "folder",
                                           description: Text("BenchLog imports PDF and Markdown files."))
                } else {
                    table
                }
            }
            .frame(height: 380)
            SheetButtons(confirm: String(localized: "Import ^[\(candidates.count - skipped.count) Guide](inflect: true)"),
                         canConfirm: !scanning && candidates.count > skipped.count,
                         cancel: { dismiss() }, action: importChosen)
        }
        .frame(width: 720)
        .task { scan() }
    }

    private var summary: String {
        let missing = candidates.reduce(0) { $0 + $1.missingImages.count }
        let found = String(localized: "^[\(candidates.count) guide](inflect: true) found. Check what each one covers.")
        return missing == 0 ? found : found + " " + String(localized: "^[\(missing) image](inflect: true) not in the folder.")
    }

    private var table: some View {
        Table(candidates) {
            TableColumn(Text(verbatim: "")) { candidate in
                Toggle("Import", isOn: Binding(get: { !skipped.contains(candidate.id) },
                                               set: { if $0 { skipped.remove(candidate.id) } else { skipped.insert(candidate.id) } }))
                    .labelsHidden()
            }
            .width(24)
            TableColumn("Guide") { candidate in
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).lineLimit(1)
                    Text(candidate.sourcePath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .help(candidate.sourcePath)
            }
            TableColumn("Covers") { candidate in
                HStack {
                    if let link = candidate.link {
                        GuideLinkChip(link: link)
                    } else {
                        Text("General").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change…") { startEditing(candidate) }
                        .buttonStyle(.borderless)
                        .help("Change what this guide and the others in its folder cover")
                        .popover(isPresented: Binding(get: { editing == candidate.id }, set: { if !$0 { editing = nil } })) {
                            changePopover(candidate)
                        }
                }
            }
            .width(min: 220, ideal: 280)
        }
        .padding(.horizontal, Space.lg)
    }

    private func changePopover(_ candidate: GuideCandidate) -> some View {
        Form {
            GuideLinkPicker(draft: $draft) { link in
                set(link, on: candidate)
                editing = nil
            }
            Button("Make It General") {
                set(nil, on: candidate)
                editing = nil
            }
            .help("Covers no model; it shows on the Guides page only")
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .environment(model)
    }

    private func startEditing(_ candidate: GuideCandidate) {
        draft = GuideLinkDraft(category: candidate.link?.category ?? .console, brand: candidate.link?.brand ?? "",
                               model: candidate.link?.model ?? "", revision: candidate.link?.revision ?? "")
        editing = candidate.id
    }

    /// Sets the link on the candidate and on every other guide from the same folder.
    private func set(_ link: GuideLink?, on candidate: GuideCandidate) {
        let folder = (candidate.sourcePath as NSString).deletingLastPathComponent
        for index in candidates.indices where (candidates[index].sourcePath as NSString).deletingLastPathComponent == folder {
            candidates[index].link = link
        }
    }

    private func scan() {
        guard let library = model.library else { return }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            candidates = try GuideScanner(library: library).scan(folder)
        } catch {
            failure = error.localizedDescription
        }
        scanning = false
    }

    private func importChosen() {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let chosen = candidates.filter { !skipped.contains($0.id) }
        guard model.importGuides(chosen) != nil else { return }
        dismiss()
    }
}
