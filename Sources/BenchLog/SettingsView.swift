import AppKit
import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        if tab == .catalog {
            CatalogSettings()
        } else {
            form(tab)
        }
    }

    @ViewBuilder
    private func form(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .board: BoardSettings()
            case .updates: UpdateSettings()
            case .catalog: EmptyView()
            case .business: BusinessSettings()
            case .backup:
                BackupSettings()
                TrashSettings()
            case .sync: SyncSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 580)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, business, catalog, backup, sync, appearance, board, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .business: String(localized: "Business")
        case .catalog: String(localized: "Catalog")
        case .backup: String(localized: "Backup")
        case .sync: String(localized: "Sync")
        case .appearance: String(localized: "Appearance")
        case .board: String(localized: "Board")
        case .updates: String(localized: "Updates")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .business: "building.2"
        case .catalog: "list.bullet.indent"
        case .backup: "externaldrive.badge.timemachine"
        case .sync: "arrow.triangle.2.circlepath"
        case .appearance: "paintpalette"
        case .board: "cpu"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("App Language") {
            Picker("Language", selection: $model.language) {
                Text("System (\(AppLanguage.systemName))").tag(AppLanguage.system)
                // Every language the app is translated into, each named in itself.
                ForEach(AppLanguage.available, id: \.self) { language in
                    Text(verbatim: language.name).tag(language)
                }
            }
            Text("Invoices and intake slips use each customer’s documents language, not this one.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if model.language != AppLanguage.atLaunch {
                HStack {
                    Text("The new language applies after a restart.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppLanguage.relaunch() }
                }
            }
        }
    }
}

/// Settings > Updates: Sparkle's automatic checks.
struct UpdateSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Automatic Updates") {
            Toggle(isOn: $model.checksForUpdates) {
                Text("Check for updates automatically")
                Text(updatesNote)
            }
            .disabled(!Updater.shared.isAvailable)
            LabeledContent("Version \(Self.version)") {
                Button("Check Now") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
        }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    private var updatesNote: String {
        guard Updater.shared.isAvailable else { return String(localized: "Updates are off in this build.") }
        guard let last = Updater.shared.lastCheck else { return String(localized: "Looks once a day for a new version on GitHub.") }
        return String(localized: "Looks once a day for a new version on GitHub. Last checked \(last.formatted(.relative(presentation: .named))).")
    }
}
