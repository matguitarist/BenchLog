import BenchLogKit
import SwiftUI

/// Settings → Catalog: the brands, models, and revisions the device fields suggest, as an
/// outline per category. Rename, merge, or delete from each row's context menu.
struct CatalogSettings: View {
    @Environment(AppModel.self) private var model
    @State private var category: DeviceCategory = .console
    @State private var outline: [CatalogNode] = []
    @State private var selection: CatalogPath?
    @State private var renaming: CatalogPath?
    @State private var newName = ""
    @State private var deleting: CatalogPath?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Picker("Category", selection: $category) {
                ForEach(DeviceCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .fixedSize()
            List(selection: $selection) {
                OutlineGroup(outline, children: \.children) { node in
                    row(node).tag(node.path)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .contextMenu(forSelectionType: CatalogPath.self) { paths in
                if let path = paths.first { actions(path) }
            }
            Text("Right-click a name to rename it, merge it into another, or delete it. Devices keep their names when you delete one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.lg)
        .frame(width: 520, height: 520)
        .task(id: "\(model.dataVersion) \(category.rawValue)") {
            outline = model.read([:]) { try $0.catalogOutline() }[category] ?? []
        }
        .alert("Rename “\(renaming?.name ?? "")”", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.renameCatalog(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Devices and parts with this name change too. A name that already exists merges the two.")
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")” from the Catalog?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { model.deleteFromCatalog(deleting) }
                deleting = nil
            }
        } message: {
            Text("It stops showing as a suggestion. Devices keep their names.")
        }
    }

    private func row(_ node: CatalogNode) -> some View {
        HStack {
            Text(node.name).lineLimit(1)
            Spacer()
            if node.deviceCount > 0 {
                Text("^[\(node.deviceCount) device](inflect: true)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func actions(_ path: CatalogPath) -> some View {
        Button("Rename…") {
            newName = path.name
            renaming = path
        }
        let siblings = model.read([]) { try $0.catalogSiblings(of: path) }
        Menu("Merge Into") {
            ForEach(siblings, id: \.self) { name in
                Button(name) { model.renameCatalog(path, to: name) }
            }
        }
        .disabled(siblings.isEmpty)
        Divider()
        Button("Delete from Catalog…", role: .destructive) { deleting = path }
    }
}
