import Foundation
import Network

/// A client for ESPHome's encrypted native API (port 6053), the connection Home Assistant itself
/// uses. It lists the device's entities, streams their states and sends commands; covers lights,
/// selects, numbers, switches, buttons and text sensors. Reconnects with backoff.
@MainActor
public final class ESPHomeClient {
    public enum Status: Equatable, Sendable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    public enum Kind: Sendable { case light, select, number, `switch`, button, textSensor }

    public struct Entity: Sendable {
        public let kind: Kind
        public let key: UInt32
        public let objectID: String
        public let name: String
        /// Select options.
        public var options: [String] = []
        /// Number range and step.
        public var minimum: Float = 0, maximum: Float = 0, step: Float = 0
        /// Light colour temperature range, in mireds.
        public var minMireds: Float = 0, maxMireds: Float = 0
    }

    public enum State: Sendable {
        case light(key: UInt32, on: Bool, brightness: Float, mireds: Float)
        case select(key: UInt32, option: String?)
        case number(key: UInt32, value: Float?)
        case `switch`(key: UInt32, on: Bool)
        case text(key: UInt32, value: String?)
    }

    public struct Failure: LocalizedError, Sendable {
        public let message: String
        public init(message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    public var onStatus: (Status) -> Void = { _ in }
    /// All entities, once listed after each (re)connect.
    public var onEntities: ([Entity]) -> Void = { _ in }
    public var onState: (State) -> Void = { _ in }

    private var target: (host: String, port: UInt16, psk: Data)?
    private var connection: NWConnection?
    private var sendCipher: CipherState?
    private var generation = 0
    private var reconnectDelay: Duration = .seconds(2)
    private var keepAlive: Task<Void, Never>?
    private var lastReceived = ContinuousClock.now
    private var listed: [Entity] = []

    public init() {}

    /// `key` is the device's `api: encryption: key:` (base64, 32 bytes).
    public func connect(host: String, port: UInt16 = 6053, key: String) {
        guard let psk = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines)), psk.count == 32 else {
            onStatus(.failed("The API encryption key must be 32 bytes, base64"))
            return
        }
        target = (host, port, psk)
        reconnectDelay = .seconds(2)
        open()
    }

    public func disconnect() {
        target = nil
        close()
        onStatus(.idle)
    }

    // MARK: - Commands

    /// Values left nil are not changed. Brightness is 0...1; colour temperature in mireds.
    public func light(_ key: UInt32, on: Bool? = nil, brightness: Float? = nil, mireds: Float? = nil) throws {
        var message = ProtoWriter()
        message.fixed32(1, key)
        if let on {
            message.bool(2, true)
            message.bool(3, on)
        }
        if let brightness {
            message.bool(4, true)
            message.float(5, brightness)
        }
        if let mireds {
            message.bool(12, true)
            message.float(13, mireds)
        }
        try send(32, message)
    }

    public func select(_ key: UInt32, option: String) throws {
        var message = ProtoWriter()
        message.fixed32(1, key)
        message.string(2, option)
        try send(54, message)
    }

    public func number(_ key: UInt32, value: Float) throws {
        var message = ProtoWriter()
        message.fixed32(1, key)
        message.float(2, value)
        try send(51, message)
    }

    public func setSwitch(_ key: UInt32, on: Bool) throws {
        var message = ProtoWriter()
        message.fixed32(1, key)
        message.bool(2, on)
        try send(33, message)
    }

    public func press(_ key: UInt32) throws {
        var message = ProtoWriter()
        message.fixed32(1, key)
        try send(62, message)
    }

    // MARK: - Connection

    private func open() {
        guard let target else { return }
        close()
        generation += 1
        let current = generation
        onStatus(.connecting)
        let connection = NWConnection(
            host: NWEndpoint.Host(target.host), port: NWEndpoint.Port(rawValue: target.port)!, using: .tcp
        )
        self.connection = connection
        Task { await run(connection, psk: target.psk, generation: current) }
    }

    private func close() {
        keepAlive?.cancel()
        keepAlive = nil
        connection?.cancel()
        connection = nil
        sendCipher = nil
    }

    private func run(_ connection: NWConnection, psk: Data, generation: Int) async {
        do {
            try await waitUntilReady(connection)

            // Handshake: NOISE_HELLO, then our handshake message in a frame tagged 0x00.
            var noise = NoiseInitiator(psk: psk, prologue: Data("NoiseAPIInit".utf8) + [0, 0])
            let handshake = try noise.writeMessage()
            try await write(connection, Data([0x01, 0x00, 0x00]) + frame(Data([0x00]) + handshake))
            let serverHello = try await readFrame(connection)
            guard serverHello.first == 0x01 else { throw Failure(message: "The device offered an unsupported protocol") }
            let reply = try await readFrame(connection)
            guard reply.first == 0x00 else {
                let reason = String(decoding: reply.dropFirst(), as: UTF8.self)
                throw Failure(message: reason.contains("MAC") ? "Wrong API encryption key" : "Handshake failed: \(reason)")
            }
            let ciphers: (send: CipherState, receive: CipherState)
            do {
                ciphers = try noise.readMessage(Data(reply.dropFirst()))
            } catch {
                throw Failure(message: "Wrong API encryption key")
            }
            sendCipher = ciphers.send

            var hello = ProtoWriter()
            hello.string(1, "ScreenBar for macOS")
            hello.uint(2, 1)
            hello.uint(3, 10)
            try send(1, hello)

            lastReceived = .now
            listed = []
            while generation == self.generation {
                let encrypted = try await readFrame(connection)
                let message = try ciphers.receive.decrypt(encrypted)
                guard message.count >= 4 else { throw Failure(message: "Malformed message") }
                lastReceived = .now
                let type = UInt16(message[message.startIndex]) << 8 | UInt16(message[message.startIndex + 1])
                try handle(type, try ProtoReader(Data(message.dropFirst(4))))
            }
        } catch {
            guard generation == self.generation, target != nil else { return }
            close()
            onStatus(.failed(Self.describe(error)))
            let delay = reconnectDelay
            reconnectDelay = min(reconnectDelay * 2, .seconds(30))
            Task {
                try? await Task.sleep(for: delay)
                if generation == self.generation { self.open() }
            }
        }
    }

    private func handle(_ type: UInt16, _ message: ProtoReader) throws {
        switch type {
        case 2:  // HelloResponse: encryption authenticated us; list the entities
            try send(11, ProtoWriter())
        case 15:
            var entity = info(.light, message)
            entity.minMireds = message.float(9)
            entity.maxMireds = message.float(10)
            listed.append(entity)
        case 52:
            var entity = info(.select, message)
            entity.options = message.strings(6)
            listed.append(entity)
        case 49:
            var entity = info(.number, message)
            (entity.minimum, entity.maximum, entity.step) = (message.float(6), message.float(7), message.float(8))
            listed.append(entity)
        case 17: listed.append(info(.switch, message))
        case 61: listed.append(info(.button, message))
        case 18: listed.append(info(.textSensor, message))
        case 19:  // ListEntitiesDoneResponse
            onEntities(listed)
            try send(20, ProtoWriter())  // SubscribeStatesRequest
            reconnectDelay = .seconds(2)
            onStatus(.connected)
            startKeepAlive()
        case 24:
            onState(.light(key: message.fixed32(1), on: message.bool(2), brightness: message.float(3), mireds: message.float(8)))
        case 53:
            onState(.select(key: message.fixed32(1), option: message.bool(3) ? nil : message.string(2)))
        case 50:
            onState(.number(key: message.fixed32(1), value: message.bool(3) ? nil : message.float(2)))
        case 26:
            onState(.switch(key: message.fixed32(1), on: message.bool(2)))
        case 27:
            onState(.text(key: message.fixed32(1), value: message.bool(3) ? nil : message.string(2)))
        case 7:  // PingRequest
            try send(8, ProtoWriter())
        case 5:  // DisconnectRequest
            try? send(6, ProtoWriter())
            throw Failure(message: "The device closed the connection")
        default:
            break  // other entity types and responses
        }
    }

    private func info(_ kind: Kind, _ message: ProtoReader) -> Entity {
        Entity(kind: kind, key: message.fixed32(2), objectID: message.string(1), name: message.string(3))
    }

    /// Ping every 20 s; if nothing arrives for a minute, reconnect.
    private func startKeepAlive() {
        keepAlive?.cancel()
        keepAlive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                if ContinuousClock.now - lastReceived > .seconds(60) {
                    connection?.cancel()  // the read loop fails and reconnects
                    return
                }
                try? send(7, ProtoWriter())
            }
        }
    }

    private func send(_ type: UInt16, _ message: ProtoWriter) throws {
        guard let connection, let sendCipher else { throw Failure(message: "Not connected") }
        let payload = message.data
        var plaintext = Data([UInt8(type >> 8), UInt8(type & 0xFF), UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
        plaintext.append(payload)
        let data = frame(try sendCipher.encrypt(plaintext))
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Framing

    private func frame(_ body: Data) -> Data {
        Data([0x01, UInt8(body.count >> 8), UInt8(body.count & 0xFF)]) + body
    }

    private func readFrame(_ connection: NWConnection) async throws -> Data {
        let header = try await read(connection, count: 3)
        guard header[header.startIndex] == 0x01 else { throw Failure(message: "Unexpected frame from the device") }
        let length = Int(header[header.startIndex + 1]) << 8 | Int(header[header.startIndex + 2])
        return length == 0 ? Data() : try await read(connection, count: length)
    }

    private func read(_ connection: NWConnection, count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: Failure(message: "Connection closed"))
                }
            }
        }
    }

    private func write(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        defer { connection.stateUpdateHandler = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error), .waiting(let error): once.resume(.failure(error))
                case .cancelled: once.resume(.failure(Failure(message: "Cancelled")))
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                once.resume(.failure(Failure(message: "Timed out connecting to the device")))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? NWError {
            switch error {
            case .dns: return "Device not found on the network"
            case .posix(let code) where code == .ECONNREFUSED: return "The device refused the connection"
            default: return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

/// Resumes a continuation once, whichever callback (state change or timeout) comes first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
