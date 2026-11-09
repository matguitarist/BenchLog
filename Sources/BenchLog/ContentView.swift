import BenchLogKit
import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            page(model.sidebar ?? .overview)
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.sidebar) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .overview: OverviewPage()
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Messages"),
                emptyMessage: String(localized: "What BenchLog does with your library shows here.")))
                .navigationTitle("Log")
        }
    }
}

/// What BenchLog will do, until the Repairs, Customers, Devices, Parts and Guides pages arrive.
struct OverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let error = model.libraryError {
                ContentUnavailableView {
                    Label("Unable to Open the Library", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                }
            } else {
                ContentUnavailableView {
                    Label("BenchLog", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Track your customers, their devices, and every repair from check-in to pickup, with parts, guides, photos, and invoices.")
                }
            }
        }
        .navigationTitle("Overview")
    }
}
