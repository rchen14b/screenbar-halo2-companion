import SwiftUI

@main
struct ScreenBarApp: App {
    @State private var store = ScreenBarStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView().environment(store)
        } label: {
            Image(nsImage: ScreenBarIcon.image(on: store.isOn))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
        }
    }
}

/// The app's version and where its source lives (linked from the panel's menu and from Settings).
enum AppInfo {
    static let sourceURL = URL(string: "https://github.com/rchen14b/screenbar-halo2-companion")!
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
