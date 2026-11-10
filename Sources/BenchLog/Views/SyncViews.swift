import AppKit
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
    /// Set once the server turns out to hold another library: joining it needs its key.
    @State private var otherLibraryRows: Int?
    @State private var recoveryCode = ""
    @State private var confirmJoin = false

    var body: some View {
        if let server = sync.server {
            let hosting = ServerHost.shared.serves(server)
            Section(hosting ? "Server on This Mac" : "Server") {
                if !hosting { LabeledContent("Address") { Text(server.absoluteString).textSelection(.enabled) } }
                LabeledContent("Status") { SyncStatusLabel() }
                if sync.pending > 0 { LabeledContent("Waiting to sync", value: "\(sync.pending)") }
                HStack {
                    if hosting {
                        Button("Show Data Folder") { ServerHost.shared.showDataFolder() }
                            .help("Show the server’s library and files in the Finder")
                    } else {
                        Button("Disconnect", role: .destructive) { sync.disconnect(model) }
                            .help("Stop syncing; this Mac keeps its copy of the library")
                    }
                    Spacer()
                    Button("Sync Now") { Task { await sync.syncNow(model) } }
                        .disabled(sync.status == .syncing)
                        .help("Send this Mac’s changes and get the others’ now")
                }
            }
            if hosting { ServerHostDetails() }
            if let code = sync.recoveryCode(model) {
                Section {
                    HStack {
                        Text(code).font(.body.monospaced()).textSelection(.enabled)
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        }
                        .help("Copy the library key, to join another device to this library")
                    }
                } header: {
                    Text("Library Key")
                } footer: {
                    Text("Passcodes are sealed with this key before they reach the server. Another device needs it to join; keep a copy somewhere safe.")
                }
            }
        } else {
            Section {
                TextField("Address", text: $address, prompt: Text(verbatim: "http://192.168.1.20:8420"))
                SecureField("Token", text: $token, prompt: Text("From the server’s first start"))
                if let testResult {
                    Text(testResult).font(.callout).foregroundStyle(.secondary)
                }
                if otherLibraryRows != nil {
                    TextField("Library key", text: $recoveryCode, prompt: Text(verbatim: "ABCD-EFGH-…"))
                        .font(.body.monospaced())
                        .help("The key shown in Settings > Sync on a device already connected to this server")
                }
                HStack {
                    Button("Test Connection") { Task { await test() } }
                        .disabled(!ready || working)
                        .help("Check the address and token, and see what the server holds")
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if otherLibraryRows != nil {
                        Button("Replace This Mac’s Library…") { confirmJoin = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(!ready || working || LibraryKey(recoveryCode: recoveryCode) == nil)
                            .help("Back up this Mac’s library, then take the server’s")
                    } else {
                        Button("Connect") { Task { await connect(join: false) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(!ready || working)
                            .help("Upload this library to an empty server, or keep it in step with its copy there")
                    }
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Run the BenchLog server on a Mac or a NAS in the shop, then share one library between your devices. Away from the shop, reach it with Tailscale.")
            }
            .confirmationDialog("Replace This Mac’s Library?", isPresented: $confirmJoin) {
                Button("Replace This Mac’s Library", role: .destructive) { Task { await connect(join: true) } }
            } message: {
                Text("The server already holds another library (\(otherLibraryRows ?? 0) items). This Mac’s library is backed up, then replaced by the server’s.")
            }
            ServerHostOffer()
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
            otherLibraryRows = library.libraryId != nil && library.libraryId != mine ? library.rows : nil
            testResult = library.libraryId == nil && library.rows == 0
                ? String(localized: "Connected. The server is empty: Connect uploads this library.")
                : library.libraryId == mine
                    ? String(localized: "Connected. The server holds this library.")
                    : String(localized: "Connected. The server holds another library (\(library.rows) items). To join it, enter its library key.")
        } catch {
            testResult = error.localizedDescription
        }
    }

    private func connect(join: Bool) async {
        guard let url else { return }
        working = true
        defer { working = false }
        do {
            try await sync.connect(model, server: url, token: token.trimmingCharacters(in: .whitespaces), join: join,
                                   recoveryCode: recoveryCode)
            token = ""
            recoveryCode = ""
            testResult = nil
            otherLibraryRows = nil
        } catch SyncError.otherLibrary(let rows) {
            otherLibraryRows = rows
            testResult = String(localized: "Connected. The server holds another library (\(rows) items). To join it, enter its library key.")
        } catch {
            testResult = error.localizedDescription
        }
    }
}

/// Synced 2 min ago, Syncing…, Offline, or the error, with a symbol.
struct SyncStatusLabel: View {
    /// Under the sidebar: "2 min ago" beside the cloud, with "Synced 2 min ago" as the tooltip.
    var compact = false
    private var sync: SyncController { .shared }

    var body: some View {
        switch sync.status {
        case .off:
            Label("Not connected", systemImage: "icloud.slash").foregroundStyle(.secondary)
        case .syncing:
            Label("Syncing…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .synced(let date):
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                let ago = date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
                Label(compact ? ago : String(localized: "Synced \(ago)"), systemImage: "checkmark.icloud")
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Synced \(ago)"))
            }
        case .offline:
            Label(sync.pending > 0 ? "Offline, \(sync.pending) waiting" : "Offline", systemImage: "icloud.slash")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label("Sync failed", systemImage: "exclamationmark.icloud").foregroundStyle(.red).help(message)
        }
    }
}
