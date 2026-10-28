import CryptoKit
import Foundation

/// The initiator side of Noise_NNpsk0_25519_ChaChaPoly_SHA256, the handshake of ESPHome's encrypted
/// native API (https://noiseprotocol.org/noise.html; aioesphomeapi's noise.py is the reference client).
///
///     -> psk, e
///     <- e, ee
struct NoiseInitiator {
    enum Failure: Error {
        case shortMessage
    }

    private var ck: Data
    private var h: Data
    private var cipher: CipherState?
    private let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private let psk: Data

    init(psk: Data, prologue: Data) {
        let name = Data("Noise_NNpsk0_25519_ChaChaPoly_SHA256".utf8)
        h = name.count <= 32 ? name + Data(count: 32 - name.count) : Data(SHA256.hash(data: name))
        ck = h
        self.psk = psk
        mixHash(prologue)
    }

    /// The first handshake message: our ephemeral key and an empty, authenticated payload.
    mutating func writeMessage() throws -> Data {
        mixKeyAndHash(psk)
        let e = ephemeral.publicKey.rawRepresentation
        mixHash(e)
        mixKey(e)  // psk handshakes also mix each ephemeral key into the cipher key
        return e + (try encryptAndHash(Data()))
    }

    /// The responder's message; returns the transport ciphers (ours to send, ours to receive).
    mutating func readMessage(_ message: Data) throws -> (send: CipherState, receive: CipherState) {
        guard message.count >= 32 + 16 else { throw Failure.shortMessage }
        let re = Data(message.prefix(32))
        mixHash(re)
        mixKey(re)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: re))
        mixKey(shared.withUnsafeBytes { Data($0) })
        _ = try decryptAndHash(Data(message.dropFirst(32)))
        let keys = Self.hkdf(ck, Data(), outputs: 2)
        return (CipherState(key: keys[0]), CipherState(key: keys[1]))
    }

    // MARK: - Symmetric state

    private mutating func mixHash(_ data: Data) {
        h = Data(SHA256.hash(data: h + data))
    }

    private mutating func mixKey(_ input: Data) {
        let out = Self.hkdf(ck, input, outputs: 2)
        ck = out[0]
        cipher = CipherState(key: out[1])
    }

    private mutating func mixKeyAndHash(_ input: Data) {
        let out = Self.hkdf(ck, input, outputs: 3)
        ck = out[0]
        mixHash(out[1])
        cipher = CipherState(key: out[2])
    }

    private mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        let ciphertext = try cipher.map { try $0.encrypt(plaintext, ad: h) } ?? plaintext
        mixHash(ciphertext)
        return ciphertext
    }

    private mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let plaintext = try cipher.map { try $0.decrypt(ciphertext, ad: h) } ?? ciphertext
        mixHash(ciphertext)
        return plaintext
    }

    /// Noise's HKDF over HMAC-SHA256.
    static func hkdf(_ chainingKey: Data, _ input: Data, outputs: Int) -> [Data] {
        let tempKey = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: chainingKey))))
        var result: [Data] = []
        var previous = Data()
        for index in 1...outputs {
            previous = Data(HMAC<SHA256>.authenticationCode(for: previous + [UInt8(index)], using: tempKey))
            result.append(previous)
        }
        return result
    }
}

/// ChaCha20-Poly1305 with Noise's nonce: 4 zero bytes, then a 64-bit little-endian counter.
final class CipherState {
    private let key: SymmetricKey
    private var counter: UInt64 = 0

    init(key: Data) {
        self.key = SymmetricKey(data: key)
    }

    func encrypt(_ plaintext: Data, ad: Data = Data()) throws -> Data {
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: try nextNonce(), authenticating: ad)
        return box.ciphertext + box.tag
    }

    func decrypt(_ ciphertext: Data, ad: Data = Data()) throws -> Data {
        guard ciphertext.count >= 16 else { throw NoiseInitiator.Failure.shortMessage }
        let box = try ChaChaPoly.SealedBox(
            nonce: try nextNonce(), ciphertext: ciphertext.dropLast(16), tag: ciphertext.suffix(16)
        )
        return try ChaChaPoly.open(box, using: key, authenticating: ad)
    }

    private func nextNonce() throws -> ChaChaPoly.Nonce {
        var bytes = Data(count: 4)
        withUnsafeBytes(of: counter.littleEndian) { bytes.append(contentsOf: $0) }
        counter += 1
        return try ChaChaPoly.Nonce(data: bytes)
    }
}
