import AppKit
import SwiftUI

/// The menu bar panel, laid out like BenQ's iScreenBar: round toggles; a brightness slider for each lit
/// section; colour temperature; Presence. Same layout as the Home Assistant card
/// (home-assistant/screenbar-halo2-card.js). Talks to the bridge directly (ScreenBarStore).
struct PanelView: View {
    @Environment(ScreenBarStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 16) {
            header
            if store.isConfigured {
                controls
                    .disabled(!store.isAvailable)
                    .opacity(store.isAvailable ? 1 : 0.45)
            } else {
                setupPrompt
            }
        }
        .padding(18)
        .frame(width: 330)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("ScreenBar Halo 2").font(.system(size: 14, weight: .semibold))
            let summary = store.radioSummary
            Text(summary.text)
                .font(.system(size: 11))
                .foregroundStyle(summary.warning ? Color.orange : Color.secondary)
                .lineLimit(1)
                .help(store.radioStatus.isEmpty ? summary.text : store.radioStatus)
            Spacer()
            Menu {
                Button("Reconnect") { store.connect() }
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                Button("Source on GitHub") { NSWorkspace.shared.open(AppInfo.sourceURL) }
                Divider()
                Button("Quit ScreenBar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 18, height: 18)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .fixedSize()
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 0) {
                    RoundControl(title: "Power", symbol: "power", isOn: store.isOn) { store.togglePower() }
                    RoundControl(title: "Auto", symbol: "a.circle", isOn: store.autoOn || store.autoFlash) { store.autoBrightness() }
                    RoundControl(title: "Front", symbol: "lamp.desk", isOn: store.frontOn) { store.toggle(.front) }
                    RoundControl(title: "Back", symbol: "light.strip.2", isOn: store.backOn) { store.toggle(.back) }
                }
            }

            // The lamp keeps a level per section and ignores the level of an unlit one, so there is a
            // slider for each lit section: one for Front or Back alone, both when both are lit.
            if store.frontOn { levelSlider("Front", .frontLevel) }
            if store.backOn { levelSlider("Back", .backLevel) }

            ControlSlider(
                title: "Colour temperature", value: store.value(.kelvin), range: store.kelvinRange, step: 100,
                track: .gradient([
                    Color(red: 1, green: 0.66, blue: 0.30), Color(red: 1, green: 0.85, blue: 0.66),
                    Color(red: 1, green: 0.96, blue: 0.92), Color(red: 0.89, green: 0.93, blue: 1),
                    Color(red: 0.74, green: 0.83, blue: 1),
                ]),
                leading: "flame", trailing: "snowflake", dimmed: !store.isOn,
                format: { "\(Int($0)) K" }
            ) { store.set(.kelvin, to: $0) }

            presenceMenu
        }
        .animation(.easeOut(duration: 0.2), value: store.mode)
    }

    private var presenceMenu: some View {
        Menu {
            ForEach(store.presenceOptions, id: \.self) { option in
                Button {
                    store.setPresence(option)
                } label: {
                    let title = option == "Disabled" ? "Off" : "Off after \(option)"
                    if option == store.presence { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            PillLabel(
                title: "Presence",
                value: store.presenceOn ? store.presence.replacingOccurrences(of: "minutes", with: "min") : "Off",
                symbol: "figure.stand", isOn: store.presenceOn
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .help("Turn the lamp off when nobody is at the desk")
    }

    private func levelSlider(_ section: String, _ control: ScreenBarStore.Control) -> some View {
        ControlSlider(
            title: "\(section) brightness", value: store.value(control), range: 1...100, step: 1,
            track: .fill(.homeActive), leading: "sun.min", trailing: "sun.max", dimmed: !store.isOn,
            format: { "\(Int($0))%" }
        ) { store.set(control, to: $0) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            Text("Add the bridge's API encryption key in Settings to control the ScreenBar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") {
                NSApp.activate()
                openSettings()
            }
            .buttonStyle(.glass)
        }
        .padding(.vertical, 8)
    }
}
