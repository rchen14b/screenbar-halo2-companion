import ESPHomeAPI
import Foundation
import Observation

/// The ScreenBar's state, read straight from the halo2 bridge over ESPHome's native API, and the
/// panel's actions on it. Home Assistant stays connected to the bridge too; both see every change.
@MainActor
@Observable
final class ScreenBarStore {
    enum Section { case front, back }
    enum Control: Hashable { case kelvin, frontLevel, backLevel }

    private(set) var status: ESPHomeClient.Status = .idle
    private(set) var lastError: String?
    /// Auto brightness as the lamp reports it (the bridge's Auto switch).
    private(set) var autoOn = false
    /// Older bridge firmware only has an Auto button; it lights up briefly when pressed.
    private(set) var autoFlash = false
    /// Slider values sent from the panel that the bridge hasn't reported back yet, so the sliders
    /// don't jump back meanwhile.
    private(set) var pending: [Control: Double] = [:]

    // The lamp, as the bridge reports it.
    private(set) var hasLightState = false
    private(set) var isOn = false
    private(set) var mode = ""
    private(set) var presence = ""
    private(set) var presenceOptions: [String] = []
    private(set) var radioStatus = ""
    private(set) var kelvinRange: ClosedRange<Double> = 2700...6500
    private var reported: [Control: Double] = [:]

    /// Entity keys, matched by name each time the bridge lists its entities.
    private struct Keys {
        var light, lightingMode, ultrasonic, frontLevel, backLevel, autoSwitch, autoButton, radioStatus: UInt32?
    }
    private var keys = Keys()

    private let client = ESPHomeClient()
    @ObservationIgnored private var pendingExpiry: [Control: Task<Void, Never>] = [:]
    @ObservationIgnored private var errorDismissal: Task<Void, Never>?

    init() {
        client.onStatus = { [weak self] status in
            guard let self else { return }
            self.status = status
            if status == .connected { lastError = nil }
            if status != .connected { hasLightState = false }
        }
        client.onEntities = { [weak self] in self?.apply(entities: $0) }
        client.onState = { [weak self] in self?.apply(state: $0) }
        Self.importCredentialsFromEnvironment()
        connect()
    }

    /// scripts/import-credentials.sh launches the app once with these set.
    private static func importCredentialsFromEnvironment() {
        let environment = ProcessInfo.processInfo.environment
        if let host = environment["SCREENBAR_HOST"], !host.isEmpty { Credentials.host = host }
        if let key = environment["SCREENBAR_KEY"], !key.isEmpty { Credentials.apiKey = key }
    }

    var isConfigured: Bool { !(Credentials.apiKey ?? "").isEmpty }

    func connect() {
        guard let key = Credentials.apiKey, !key.isEmpty else {
            client.disconnect()
            status = .failed("Add the bridge's API encryption key in Settings")
            return
        }
        client.connect(host: Credentials.host, key: key)
    }

    // MARK: - Bridge updates

    private func apply(entities: [ESPHomeClient.Entity]) {
        keys = Keys()
        for entity in entities {
            switch (entity.kind, entity.name) {
            case (.light, _):
                keys.light = entity.key
                if entity.minMireds > 0, entity.maxMireds > entity.minMireds {
                    kelvinRange = (1_000_000 / Double(entity.maxMireds)).rounded()...(1_000_000 / Double(entity.minMireds)).rounded()
                }
            case (.select, "Lighting mode"): keys.lightingMode = entity.key
            case (.select, "Ultrasonic sensor"):
                keys.ultrasonic = entity.key
                presenceOptions = entity.options
            case (.number, "Front brightness"): keys.frontLevel = entity.key
            case (.number, "Back brightness"): keys.backLevel = entity.key
            case (.switch, "Auto brightness"): keys.autoSwitch = entity.key
            case (.button, "Auto brightness"): keys.autoButton = entity.key
            case (.textSensor, "Radio status"): keys.radioStatus = entity.key
            default: break
            }
        }
    }

    private func apply(state: ESPHomeClient.State) {
        switch state {
        case .light(let key, let on, _, let mireds) where key == keys.light:
            isOn = on
            // The bridge works in 25 K steps.
            if mireds > 0 { reported[.kelvin] = (1_000_000 / Double(mireds) / 25).rounded() * 25 }
            hasLightState = true
        case .select(let key, let option):
            if key == keys.lightingMode { mode = option ?? "" }
            if key == keys.ultrasonic { presence = option ?? "" }
        case .number(let key, let value):
            if key == keys.frontLevel { reported[.frontLevel] = value.map(Double.init) }
            if key == keys.backLevel { reported[.backLevel] = value.map(Double.init) }
        case .switch(let key, let on) where key == keys.autoSwitch:
            autoOn = on
        case .text(let key, let value) where key == keys.radioStatus:
            radioStatus = value ?? ""
        default:
            return
        }
        for (control, value) in pending where abs((reported[control] ?? .nan) - value) <= (control == .kelvin ? 30 : 1.5) {
            pending[control] = nil
        }
    }

    // MARK: - State

    var isAvailable: Bool { status == .connected && hasLightState }
    var frontOn: Bool { mode == "Front" || mode == "Both" }
    var backOn: Bool { mode == "Back" || mode == "Both" }
    var presenceOn: Bool { !["", "Disabled"].contains(presence) }

    func value(_ control: Control) -> Double {
        pending[control] ?? reported[control] ?? (control == .kelvin ? 4000 : 0)
    }

    /// Short status for the header, and whether it's a problem.
    var radioSummary: (text: String, warning: Bool) {
        if let lastError { return (lastError, true) }
        switch status {
        case .idle, .connecting: return ("Connecting…", false)
        case .failed(let message): return (message, true)
        case .connected: break
        }
        guard hasLightState else { return ("Waiting for the lamp…", false) }
        let lowered = radioStatus.lowercased()
        if lowered.contains("lamp status received") { return ("Synced", false) }
        if lowered.contains("command sent") { return ("Sending…", false) }
        if lowered.contains("discover") { return ("Pairing…", false) }
        if lowered.contains("unavailable") || lowered.contains("error") || lowered.contains("fail") { return (radioStatus, true) }
        return (radioStatus, false)
    }

    // MARK: - Actions

    func togglePower() {
        command(keys.light) { try $0.light($1, on: !self.isOn) }
    }

    /// Toggles Auto on bridges with the Auto switch; otherwise starts it with the button.
    func autoBrightness() {
        if let key = keys.autoSwitch {
            let on = !autoOn
            command(key) { try $0.setSwitch($1, on: on) }
            return
        }
        command(keys.autoButton) { try $0.press($1) }
        autoFlash = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            autoFlash = false
        }
    }

    /// Front and Back map onto the bridge's Lighting mode (Front, Back, Both); one stays lit.
    func toggle(_ section: Section) {
        let front = section == .front ? !frontOn : frontOn
        let back = section == .back ? !backOn : backOn
        guard front || back else { return }
        let option = front && back ? "Both" : front ? "Front" : "Back"
        command(keys.lightingMode) { try $0.select($1, option: option) }
    }

    func set(_ control: Control, to value: Double) {
        hold(control, value)
        switch control {
        case .kelvin: command(keys.light) { try $0.light($1, on: true, mireds: Float(1_000_000 / value)) }
        case .frontLevel: command(keys.frontLevel) { try $0.number($1, value: Float(value)) }
        case .backLevel: command(keys.backLevel) { try $0.number($1, value: Float(value)) }
        }
    }

    func setPresence(_ option: String) {
        command(keys.ultrasonic) { try $0.select($1, option: option) }
    }

    private func command(_ key: UInt32?, _ body: (ESPHomeClient, UInt32) throws -> Void) {
        do {
            guard let key else { throw ESPHomeClient.Failure(message: "The bridge didn't list this control") }
            try body(client, key)
        } catch {
            pending = [:]
            showError(error.localizedDescription)
        }
    }

    private func hold(_ control: Control, _ value: Double) {
        pending[control] = value
        pendingExpiry[control]?.cancel()
        pendingExpiry[control] = Task {
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled, pending[control] == value { pending[control] = nil }
        }
    }

    private func showError(_ message: String) {
        lastError = message
        errorDismissal?.cancel()
        errorDismissal = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { lastError = nil }
        }
    }
}
