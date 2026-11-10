import SwiftUI

/// The bar under the sidebar: Settings, always, and when the library is connected,
/// the sync state and Sync Now.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    private var sync: SyncController { .shared }

    var body: some View {
        HStack(spacing: Space.sm) {
            Button("Settings", systemImage: "gearshape") { openSettings() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Open Settings (⌘,)")
            if sync.isConnected {
                SyncStatusLabel(compact: true)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Sync Now", systemImage: "arrow.clockwise") { Task { await sync.syncNow(model) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(sync.status == .syncing)
                    .help("Send this Mac’s changes and get the others’ now")
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.sm)
    }
}
