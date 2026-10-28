// swift-tools-version: 6.0
// ScreenBar: a menu bar panel for the BenQ ScreenBar Halo 2, after BenQ's iScreenBar app.
// Talks to the halo2 ESPHome bridge directly over ESPHome's encrypted native API (see README.md).
import PackageDescription

let package = Package(
    name: "ScreenBarMenu",
    platforms: [.macOS("26.0")],
    targets: [
        // ESPHome native API client: Noise handshake, protobuf messages, connection.
        .target(name: "ESPHomeAPI", path: "Sources/ESPHomeAPI"),
        .executableTarget(name: "ScreenBarMenu", dependencies: ["ESPHomeAPI"], path: "Sources/ScreenBarMenu"),
        // Read-only test against a real device: lists entities and states.
        .executableTarget(name: "esphome-probe", dependencies: ["ESPHomeAPI"], path: "Sources/esphome-probe"),
    ]
)
