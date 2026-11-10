import BenchLogKit
import CoreSpotlight
import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .dashboard)
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
        .confirmationDialog("Start Without Approval?", isPresented: Binding(get: { model.pendingStart != nil },
                                                                             set: { if !$0 { model.pendingStart = nil } }),
                            presenting: model.pendingStart) { pending in
            Button("Ask for Approval") {
                model.setStatus(.awaitingApproval, for: pending.repairID, force: true)
                model.pendingStart = nil
            }
            Button("Start Anyway") {
                model.setStatus(pending.status, for: pending.repairID, force: true)
                model.pendingStart = nil
            }
            Button("Cancel", role: .cancel) { model.pendingStart = nil }
        } message: { pending in
            Text(pending.message)
        }
        .confirmationDialog(model.pendingTrash.map { String(localized: "Move “\($0.name)” to the Trash?") } ?? "",
                            isPresented: Binding(get: { model.pendingTrash != nil }, set: { if !$0 { model.pendingTrash = nil } }),
                            presenting: model.pendingTrash) { pending in
            Button("Move to Trash", role: .destructive) {
                model.moveToTrash(pending.item, confirmed: true)
                model.pendingTrash = nil
            }
            Button("Cancel", role: .cancel) { model.pendingTrash = nil }
        } message: { pending in
            Text("Open repairs: \(pending.openRepairs). They go to the Trash with the customer; Edit > Undo brings everything back.")
        }
        .alert("Unable to Save", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK") { model.problem = nil }
        } message: {
            Text(model.problem ?? "")
        }
        // A customer or repair picked in Spotlight.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let destination = Spotlight.destination(for: identifier) else { return }
            model.searching = false
            model.open(destination)
        }
        .onChange(of: undoManager, initial: true) { _, manager in model.undoManager = manager }
        .task {
            SeedData.fillIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings, openWindow: openWindow)
        }
        .task { await Backups.shared.runDaily(model) }
        .task { await SyncController.shared.run(model) }
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
        .safeAreaInset(edge: .bottom, spacing: 0) { SidebarFooter() }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .dashboard: DashboardPage()
        case .counterSales: CounterSalesPage()
        case .repairs: RepairsPage()
        case .customers: CustomersPage()
        case .devices: DevicesPage()
        case .parts: PartsPage()
        case .guides: GuidesPage()
        case .reports: ReportsPage()
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Messages"),
                emptyMessage: String(localized: "What BenchLog does with your library shows here.")))
                .navigationTitle("Log")
        }
    }
}
