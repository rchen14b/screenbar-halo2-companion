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
