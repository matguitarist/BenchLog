import BenchLogKit
import SwiftUI

/// Edit Guide: the title, tags, and the catalog models, brands, or categories it covers.
struct GuideSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let guideID: UUID

    @State private var guide: Guide?
    @State private var title = ""
    @State private var tags = ""
    @State private var links: [GuideLink] = []
    @State private var draft = GuideLinkDraft()
    @State private var showErrors = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Edit Guide").font(.headline).padding(.top, Space.lg)
            Form {
                Section {
                    TextField("Title", text: $title)
                    if showErrors, title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Enter a title.").font(.callout).foregroundStyle(.red)
                    }
                    TextField("Tags", text: $tags, prompt: Text("power, nes"))
                        .help("Words to find the guide by, separated by commas or spaces")
                }
                Section {
                    if links.isEmpty {
                        Text("Covers no model yet. A guide shows on a repair when it covers the device.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(links, id: \.self) { link in
                        HStack {
                            GuideLinkChip(link: link)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") { links.removeAll { $0 == link } }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Remove \(link.title)")
                        }
                    }
                } header: {
                    Text("Covers")
                }
                Section("Add") {
                    GuideLinkPicker(draft: $draft) { link in
                        if !links.contains(link) { links.append(link) }
                    }
                }
            }
            .formStyle(.grouped)
            .fitsContent(max: 560)
            SheetButtons(confirm: String(localized: "Save"), cancel: { dismiss() }, action: save)
        }
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func load() {
        guard let found = model.read(nil, { try $0.guide(guideID) }) else { return }
        guide = found
        title = found.title
        tags = found.tagList.joined(separator: ", ")
        links = model.read([]) { try $0.links(of: guideID) }
        if let last = links.last {
            draft.category = last.category
            draft.brand = last.brand
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard var guide, !trimmed.isEmpty else {
            showErrors = true
            return
        }
        guide.title = trimmed
        guide.tags = Guide.tagText(tags.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init))
        guard model.save(guide, links: links) != nil else { return }
        dismiss()
    }
}

struct GuideLinkDraft {
    var category: DeviceCategory = .console
    var brand = ""
    var model = ""
    var revision = ""

    var link: GuideLink {
        let trim = { (text: String) in text.trimmingCharacters(in: .whitespaces) }
        let brand = trim(self.brand)
        let model = brand.isEmpty ? "" : trim(self.model)
        return GuideLink(category: category, brand: brand, model: model, revision: model.isEmpty ? "" : trim(revision))
    }
}

/// Category, then brand, model, and revision, each optional: leave the rest empty to
/// cover a whole brand or category. Suggestions come from the catalog.
struct GuideLinkPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: GuideLinkDraft
    let add: (GuideLink) -> Void

    var body: some View {
        Picker("Category", selection: $draft.category) {
            ForEach(DeviceCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
        }
        TextField("Brand", text: $draft.brand, prompt: Text("Any brand"))
            .textInputSuggestions {
                suggestions(model.read([]) { try $0.catalogBrands(draft.category) }, typed: draft.brand)
            }
        TextField("Model", text: $draft.model, prompt: Text("Any model"))
            .disabled(draft.brand.trimmingCharacters(in: .whitespaces).isEmpty)
            .textInputSuggestions {
                suggestions(model.read([]) { try $0.catalogModels(draft.category, brand: draft.brand) }, typed: draft.model)
            }
        TextField("Revision", text: $draft.revision, prompt: Text("Any revision"))
            .disabled(draft.model.trimmingCharacters(in: .whitespaces).isEmpty)
            .textInputSuggestions {
                suggestions(model.read([]) { try $0.catalogRevisions(draft.category, brand: draft.brand, model: draft.model) }.filter { !$0.isEmpty },
                            typed: draft.revision)
            }
        HStack {
            Spacer()
            Button("Add “\(draft.link.title)”") {
                add(draft.link)
                draft.model = ""
                draft.revision = ""
            }
            .help("Show this guide on repairs for these devices")
        }
    }

    @ViewBuilder
    private func suggestions(_ names: [String], typed: String) -> some View {
        let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
        ForEach(names.filter { typed.isEmpty || $0.lowercased().contains(typed) }.prefix(12), id: \.self) {
            Text(verbatim: $0).textInputCompletion($0)
        }
    }
}
