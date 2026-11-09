import BenchLogKit
import SwiftUI
import UniformTypeIdentifiers

/// Guides: the library of repair guides grouped by category and brand, beside the selected guide.
struct GuidesPage: View {
    @Environment(AppModel.self) private var model
    @State private var rows: [GuideRow] = []
    @State private var choosingFiles = false
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        HSplitView {
            list
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 460, maxHeight: .infinity)
            detail
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Guides")
        .searchable(text: $model.guideSearch, prompt: Text("Title or tag"))
        .toolbar {
            ToolbarItem {
                Button("Add Guides…", systemImage: "plus") { choosingFiles = true }
                    .help("Add PDF or Markdown guides, or a folder of them")
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.pdf, .folder] + Self.markdownTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addGuides(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addGuides(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.tint, lineWidth: 2).padding(Space.xs)
                    .allowsHitTesting(false)
            }
        }
        .task(id: "\(model.dataVersion) \(model.guideSearch)") {
            rows = model.read([]) { try $0.guideRows(matching: model.guideSearch) }
        }
    }

    static let markdownTypes: [UTType] = [UTType(filenameExtension: "md"), UTType("net.daringfireball.markdown")].compactMap { $0 }

    /// Sections by the guide's first link: "Consoles · Nintendo", and General for guides with none.
    private var sections: [(title: String, rows: [GuideRow])] {
        let grouped = Dictionary(grouping: rows) { row -> String in
            guard let link = row.links.first else { return "" }
            return link.brand.isEmpty ? link.category.pluralTitle : "\(link.category.pluralTitle) · \(link.brand)"
        }
        return grouped.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            return a.localizedStandardCompare(b) == .orderedAscending
        }.map { (title: $0.isEmpty ? String(localized: "General") : $0, rows: grouped[$0] ?? []) }
    }

    @ViewBuilder
    private var list: some View {
        @Bindable var model = model
        if rows.isEmpty {
            if model.guideSearch.isEmpty {
                ContentUnavailableView {
                    Label("No Guides", systemImage: "book.pages")
                } description: {
                    Text("Drop PDF or Markdown guides here, or a whole folder such as an Obsidian vault.")
                } actions: {
                    Button("Add Guides…") { choosingFiles = true }.buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView.search(text: model.guideSearch)
            }
        } else {
            List(selection: $model.selectedGuide) {
                ForEach(sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.rows) { row in
                            GuideListRow(row: row).tag(row.id)
                                .contextMenu {
                                    Button("Edit…") { model.sheet = .editGuide(row.id) }
                                    Button("Open in Window") { openWindow(row.id) }
                                    Divider()
                                    Button("Move to Trash", role: .destructive) { model.trashGuide(row.id) }
                                }
                        }
                    }
                }
            }
            .onDeleteCommand { if let id = model.selectedGuide { model.trashGuide(id) } }
        }
    }

    @Environment(\.openWindow) private var openWindowAction
    private func openWindow(_ id: UUID) { openWindowAction(id: "guide", value: id) }

    @ViewBuilder
    private var detail: some View {
        if let id = model.selectedGuide {
            GuideDetail(guideID: id).id(id)
        } else {
            ContentUnavailableView("No Guide Selected", systemImage: "book.pages",
                                   description: Text("Select a guide to read it."))
        }
    }
}

struct GuideListRow: View {
    @Environment(AppModel.self) private var model
    let row: GuideRow

    var body: some View {
        HStack(spacing: Space.sm) {
            preview
                .frame(width: 32, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.guide.title).fontWeight(.medium).lineLimit(1).help(row.guide.title)
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let models = row.links.map(\.names).filter { !$0.isEmpty }.joined(separator: ", ")
        let kind = row.guide.format == .pdf ? "PDF" : "Markdown"
        if row.guide.isOverview { return [String(localized: "Overview"), models].filter { !$0.isEmpty }.joined(separator: " · ") }
        return models.isEmpty ? kind : "\(models) · \(kind)"
    }

    @ViewBuilder
    private var preview: some View {
        if row.guide.format == .pdf, let file = model.read(nil, { try $0.guideFile(row.guide) }), let library = model.library {
            Thumbnail(url: library.fileURL(for: file), side: 40)
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: row.guide.isOverview ? "list.bullet.rectangle" : "doc.richtext")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One guide: its title, links, and tags above the reader.
struct GuideDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let guideID: UUID
    var showsHeader = true
    @State private var guide: Guide?
    @State private var links: [GuideLink] = []

    var body: some View {
        Group {
            if let guide {
                VStack(spacing: 0) {
                    if showsHeader {
                        header(guide)
                        Divider()
                    }
                    GuideReader(guide: guide)
                }
            } else {
                ContentUnavailableView("No Guide Selected", systemImage: "book.pages")
            }
        }
        .task(id: model.dataVersion) {
            guide = model.read(nil) { try $0.guide(guideID) }.flatMap { $0.deletedAt == nil ? $0 : nil }
            links = model.read([]) { try $0.links(of: guideID) }
        }
    }

    private func header(_ guide: Guide) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(guide.title).font(.title2.weight(.semibold)).lineLimit(2).textSelection(.enabled)
                Spacer()
                Button("Open in Window", systemImage: "macwindow") { openWindow(id: "guide", value: guide.id) }
                    .labelStyle(.iconOnly)
                    .help("Open this guide in its own window, to keep it beside a repair")
                Button("Edit…") { model.sheet = .editGuide(guide.id) }
                    .help("Change the title, tags, and models this guide covers")
            }
            if !links.isEmpty || !guide.tagList.isEmpty {
                HStack(spacing: Space.sm) {
                    ForEach(links, id: \.self) { link in
                        GuideLinkChip(link: link)
                    }
                    ForEach(guide.tagList, id: \.self) { tag in
                        Text(verbatim: "#\(tag)").font(.callout).foregroundStyle(.tint)
                    }
                }
                .lineLimit(1)
            } else {
                Button("Add the Models It Covers…") { model.sheet = .editGuide(guide.id) }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
    }
}

/// "Nintendo NES" with the category's symbol, or "Consoles" for a whole category.
struct GuideLinkChip: View {
    let link: GuideLink

    var body: some View {
        Label(link.title, systemImage: link.category.symbol)
            .font(.callout)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

extension GuideLink {
    var title: String { brand.isEmpty ? category.pluralTitle : names }
}

/// The window Open in Window opens: one guide, beside the main window.
struct GuideWindow: View {
    @Environment(AppModel.self) private var model
    let guideID: UUID?

    var body: some View {
        if let guideID, let guide = model.read(nil, { try $0.guide(guideID) }) {
            GuideDetail(guideID: guideID, showsHeader: false)
                .navigationTitle(guide.title)
                .frame(minWidth: 520, minHeight: 480)
        } else {
            ContentUnavailableView("Guide Not Found", systemImage: "book.pages")
                .frame(minWidth: 420, minHeight: 300)
        }
    }
}
