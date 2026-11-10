import AppKit
import SwiftUI

/// Settings > Sync, not connected: run the server on this Mac.
struct ServerHostOffer: View {
    @Environment(AppModel.self) private var model
    private var host: ServerHost { .shared }

    var body: some View {
        Section {
            HStack {
                if host.state == .starting {
                    ProgressView().controlSize(.small)
                    Text("Starting the server…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Use This Mac as the Server") { Task { await host.start(model) } }
                    .disabled(host.state == .starting || model.library == nil)
                    .help("Run the BenchLog server on this Mac and connect this library to it")
            }
            switch host.state {
            case .needsApproval:
                HStack {
                    Text("Allow BenchLog in System Settings > General > Login Items, then try again.")
                        .font(.callout).foregroundStyle(.orange)
                    Spacer()
                    Button("Open Login Items") { host.openLoginItems() }
                }
            case .failed(let reason):
                Text(reason).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            default:
                EmptyView()
            }
        } header: {
            Text("This Mac as the Server")
        } footer: {
            Text("Keep the shop’s library on this Mac: the server runs even when BenchLog is closed, and other Macs connect to it on the shop network. This Mac must stay on.")
        }
    }
}

/// Settings > Sync, while this Mac is the server: what the other Macs enter, and Stop.
struct ServerHostDetails: View {
    @Environment(AppModel.self) private var model
    private var host: ServerHost { .shared }

    var body: some View {
        @Bindable var host = host
        Section {
            CopyRow(label: "Address", value: host.addressForOthers, help: "Copy the address other Macs enter in Settings > Sync")
            if let token = host.token {
                CopyRow(label: "Token", value: token, help: "Copy the token other Macs enter in Settings > Sync")
            }
            HStack {
                Button("Stop Using This Mac as the Server…", role: .destructive) { host.confirmingStop = true }
                    .help("Stop the server on this Mac; its data stays")
                Spacer()
            }
        } header: {
            Text("Other Macs connect with")
        } footer: {
            Text("They also need the library key below. Away from the shop, use this Mac’s Tailscale name as the address.")
        }
        .confirmationDialog("Stop the Server on This Mac?", isPresented: $host.confirmingStop) {
            Button("Stop Server", role: .destructive) { host.stop(model) }
        } message: {
            Text("Other Macs stop syncing until they connect to another server. The server’s data stays on this Mac, and this Mac keeps its copy of the library.")
        }
    }
}

/// A label, a value in monospace that can be selected, and Copy.
private struct CopyRow: View {
    let label: LocalizedStringKey
    let value: String
    let help: LocalizedStringKey

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(value).font(.body.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
                .help(help)
            }
        }
    }
}
