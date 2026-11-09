import BenchLogKit
import LogKitUI
import Observation
import SwiftUI

/// The app's state: the open library, the page shown, and the app's own settings.
@Observable
final class AppModel {
    let library: Library?
    /// Why the library did not open, in words for the Overview page.
    let libraryError: String?
    let log: LogStore
    /// The Log page's viewer; kept here so its filters survive moving between pages.
    let logViewer: LogViewerModel

    var sidebar: SidebarItem? = .overview
    var settingsTab: SettingsTab = .general

    var language: AppLanguage = .current {
        didSet { language.apply() }
    }

    var checksForUpdates: Bool {
        get { access(keyPath: \.checksForUpdates); return Updater.shared.automaticallyChecks }
        set { withMutation(keyPath: \.checksForUpdates) { Updater.shared.automaticallyChecks = newValue } }
    }

    init(library: Result<Library, Error>, log: LogStore) {
        switch library {
        case .success(let opened):
            self.library = opened
            libraryError = nil
        case .failure(let error):
            self.library = nil
            libraryError = error.localizedDescription
        }
        self.log = log
        logViewer = LogViewerModel(store: log)
    }
}

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "wrench.and.screwdriver"
        case .log: "list.bullet.rectangle"
        }
    }
}
