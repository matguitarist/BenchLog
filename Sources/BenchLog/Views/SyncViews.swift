import BenchLogKit
import SwiftUI

/// Settings > Sync: connect this library to the BenchLog server, or see how it syncs.
struct SyncSettings: View {
    @Environment(AppModel.self) private var model
    private var sync: SyncController { .shared }
    @State private var address = ""
    @State private var token = ""
    @State private var testResult: String?
    @State private var working = false
    @State private var joinRows: Int?

    var body: some View {
        if let server = sync.server {
            Section("Server") {
                LabeledContent("Address") { Text(server.absoluteString).textSelection(.enabled) }
                LabeledContent("Status") { SyncStatusLabel() }
                if sync.pending > 0 { LabeledContent("Waiting to sync", value: "\(sync.pending)") }
                HStack {
                    Button("Disconnect", role: .destructive) { sync.disconnect(model) }
                        .help("Stop syncing; this Mac keeps its copy of the library")
                    Spacer()
                    Button("Sync Now") { Task { await sync.syncNow(model) } }
                        .disabled(sync.status == .syncing)
                        .help("Send this Mac’s changes and get the others’ now")
                }
            }
        } else {
            Section {
                TextField("Address", text: $address, prompt: Text(verbatim: "http://192.168.1.20:8420"))
                SecureField("Token", text: $token, prompt: Text("From the server’s first start"))
                if let testResult {
                    Text(testResult).font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Test Connection") { Task { await test() } }
                        .disabled(!ready || working)
                        .help("Check the address and token, and see what the server holds")
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    Button("Connect") { Task { await connect(join: false) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!ready || working)
                        .help("Upload this library to an empty server, or keep it in step with its copy there")
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Run the BenchLog server on a Mac or a NAS in the shop, then share one library between your devices. Away from the shop, reach it with Tailscale.")
            }
            .confirmationDialog("Replace This Mac’s Library?", isPresented: Binding(get: { joinRows != nil }, set: { if !$0 { joinRows = nil } })) {
                Button("Replace This Mac’s Library", role: .destructive) { Task { await connect(join: true) } }
            } message: {
                Text("The server already holds another library (\(joinRows ?? 0) items). This Mac’s library is backed up, then replaced by the server’s.")
            }
        }
    }

    private var url: URL? {
        var text = address.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "http://" + text }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    private var ready: Bool { url != nil && !token.trimmingCharacters(in: .whitespaces).isEmpty }

    private func test() async {
        guard let url else { return }
        working = true
        defer { working = false }
        do {
            let library = try await sync.test(server: url, token: token.trimmingCharacters(in: .whitespaces))
            let mine = model.read("") { try $0.libraryID() }
            testResult = library.libraryId == nil && library.rows == 0
                ? String(localized: "Connected. The server is empty: Connect uploads this library.")
                : library.libraryId == mine
                    ? String(localized: "Connected. The server holds this library.")
                    : String(localized: "Connected. The server holds another library (\(library.rows) items): Connect replaces this Mac’s.")
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func connect(join: Bool) async {
        guard let url else { return }
        working = true
        defer { working = false }
        do {
            try await sync.connect(model, server: url, token: token.trimmingCharacters(in: .whitespaces), join: join)
            token = ""
            testResult = nil
        } catch SyncError.otherLibrary(let rows) {
            joinRows = rows
        } catch {
            testResult = error.localizedDescription
        }
    }
}

/// Synced 2 min ago, Syncing…, Offline, or the error, with a symbol.
struct SyncStatusLabel: View {
    private var sync: SyncController { .shared }

    var body: some View {
        switch sync.status {
        case .off:
            Label("Not connected", systemImage: "icloud.slash").foregroundStyle(.secondary)
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .synced(let date):
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Label("Synced \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
                    .foregroundStyle(.secondary)
            }
        case .offline:
            Label(sync.pending > 0 ? "Offline, \(sync.pending) waiting" : "Offline", systemImage: "icloud.slash")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label("Sync failed", systemImage: "exclamationmark.icloud").foregroundStyle(.red).help(message)
        }
    }
}

/// Under the sidebar, when the library is connected: the sync state and Sync Now.
struct SyncFooter: View {
    @Environment(AppModel.self) private var model
    private var sync: SyncController { .shared }

    var body: some View {
        if sync.isConnected {
            HStack(spacing: Space.sm) {
                SyncStatusLabel()
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Sync Now", systemImage: "arrow.clockwise") { Task { await sync.syncNow(model) } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(sync.status == .syncing)
                    .help("Send this Mac’s changes and get the others’ now")
            }
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.sm)
        }
    }
}
