import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(ScreenBarStore.self) private var store
    @State private var host = Credentials.host
    @State private var key = ""
    @State private var hasKey = Credentials.apiKey != nil
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("ScreenBar bridge") {
                TextField("Address", text: $host, prompt: Text("screenbar-halo2.local"))
                SecureField("API encryption key", text: $key, prompt: Text(hasKey ? "Saved in Keychain" : "api: encryption: key from secrets.yaml"))
                HStack {
                    Spacer()
                    Button("Save and Connect") {
                        Credentials.host = host.trimmingCharacters(in: .whitespaces)
                        if !key.isEmpty {
                            Credentials.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            key = ""
                            hasKey = true
                        }
                        store.connect()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                LabeledContent("Status", value: statusText)
                LabeledContent("Radio", value: store.radioStatus.isEmpty ? "—" : store.radioStatus)
            }
            Section("About") {
                LabeledContent("Version", value: AppInfo.version)
                Link("ScreenBar Halo 2 Companion on GitHub", destination: AppInfo.sourceURL)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private var statusText: String {
        switch store.status {
        case .idle: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Connected to \(Credentials.host)"
        case .failed(let message): message
        }
    }
}
