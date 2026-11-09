import BenchLogKit
import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .repairs)
        }
        .overlay(alignment: .top) {
            if model.searching {
                ZStack(alignment: .top) {
                    // A click outside the panel closes it.
                    Color.black.opacity(0.001)
                        .onTapGesture { model.searching = false }
                    SearchPanel()
                        .padding(.top, 72) // grid: ok below the toolbar
                }
            }
        }
        .sheet(item: $model.sheet) { kind in
            SheetHost(kind: kind)
                .environment(model)
                .themed()
        }
        .alert("Unable to Save", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: {
            Text(model.problem ?? "")
        }
        .onChange(of: undoManager, initial: true) { _, manager in model.undoManager = manager }
        .task {
            SeedData.fillIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(item == .repairs ? model.openRepairCount : item == .parts ? model.lowStockCount : 0)
                    .tag(item)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .repairs: RepairsPage()
        case .customers: CustomersPage()
        case .devices: DevicesPage()
        case .parts: PartsPage()
        case .guides: GuidesPage()
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Messages"),
                emptyMessage: String(localized: "What BenchLog does with your library shows here.")))
                .navigationTitle("Log")
        }
    }
}
