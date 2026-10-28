// Read-only check of the ESPHome API client against a real device: connects, prints the entities
// and the states that arrive within a few seconds, then disconnects. Sends no commands.
//
//   SCREENBAR_KEY=<api key> swift run esphome-probe [host] [seconds]
import ESPHomeAPI
import Foundation

@MainActor
func probe() async {
    let arguments = CommandLine.arguments
    let host = arguments.count > 1 ? arguments[1] : "screenbar-halo2.local"
    let seconds = arguments.count > 2 ? Double(arguments[2]) ?? 6 : 6
    guard let key = ProcessInfo.processInfo.environment["SCREENBAR_KEY"] else {
        print("Set SCREENBAR_KEY to the device's API encryption key")
        exit(2)
    }

    let client = ESPHomeClient()
    var names: [UInt32: String] = [:]
    client.onStatus = { print("status:", $0) }
    client.onEntities = { entities in
        for entity in entities {
            names[entity.key] = entity.name.isEmpty ? entity.objectID : entity.name
            var extra = ""
            if !entity.options.isEmpty { extra = " options=\(entity.options)" }
            if entity.kind == .number { extra = " range=\(entity.minimum)...\(entity.maximum) step \(entity.step)" }
            if entity.kind == .light { extra = " mireds=\(entity.minMireds)...\(entity.maxMireds)" }
            print("entity: \(entity.kind) \"\(entity.name)\" object_id=\(entity.objectID) key=\(entity.key)\(extra)")
        }
    }
    client.onState = { state in
        switch state {
        case .light(let key, let on, let brightness, let mireds):
            print("state: \(names[key] ?? "\(key)") on=\(on) brightness=\(brightness) mireds=\(mireds) (\(mireds > 0 ? Int(1_000_000 / mireds) : 0) K)")
        case .select(let key, let option): print("state: \(names[key] ?? "\(key)") = \(option ?? "—")")
        case .number(let key, let value): print("state: \(names[key] ?? "\(key)") = \(value.map { "\($0)" } ?? "—")")
        case .switch(let key, let on): print("state: \(names[key] ?? "\(key)") = \(on ? "on" : "off")")
        case .text(let key, let value): print("state: \(names[key] ?? "\(key)") = \(value ?? "—")")
        }
    }
    client.connect(host: host, key: key)
    try? await Task.sleep(for: .seconds(seconds))
    client.disconnect()
}

await probe()
