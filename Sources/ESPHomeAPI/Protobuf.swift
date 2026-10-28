import Foundation

/// Just enough protobuf for ESPHome's API messages: varints, fixed32 (keys, floats) and
/// length-delimited fields (strings).
struct ProtoReader {
    enum Value {
        case varint(UInt64)
        case fixed32(UInt32)
        case fixed64(UInt64)
        case bytes(Data)
    }

    enum Failure: Error { case truncated, unsupportedWireType(UInt64) }

    private(set) var fields: [Int: [Value]] = [:]

    init(_ data: Data) throws {
        var bytes = [UInt8](data)[...]
        while !bytes.isEmpty {
            let tag = try Self.varint(&bytes)
            let field = Int(tag >> 3)
            let value: Value
            switch tag & 7 {
            case 0: value = .varint(try Self.varint(&bytes))
            case 1:
                guard bytes.count >= 8 else { throw Failure.truncated }
                value = .fixed64(bytes.prefix(8).enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * $1.offset) })
                bytes = bytes.dropFirst(8)
            case 2:
                let length = Int(try Self.varint(&bytes))
                guard bytes.count >= length else { throw Failure.truncated }
                value = .bytes(Data(bytes.prefix(length)))
                bytes = bytes.dropFirst(length)
            case 5:
                guard bytes.count >= 4 else { throw Failure.truncated }
                value = .fixed32(bytes.prefix(4).enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) })
                bytes = bytes.dropFirst(4)
            case let other: throw Failure.unsupportedWireType(other)
            }
            fields[field, default: []].append(value)
        }
    }

    private static func varint(_ bytes: inout ArraySlice<UInt8>) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while let byte = bytes.popFirst() {
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { break }
        }
        throw Failure.truncated
    }

    // Absent fields read as proto3 defaults.
    func uint(_ field: Int) -> UInt64 {
        if case .varint(let value) = fields[field]?.last { return value }
        return 0
    }

    func bool(_ field: Int) -> Bool { uint(field) != 0 }

    func fixed32(_ field: Int) -> UInt32 {
        if case .fixed32(let value) = fields[field]?.last { return value }
        return 0
    }

    func float(_ field: Int) -> Float { Float(bitPattern: fixed32(field)) }

    func string(_ field: Int) -> String {
        if case .bytes(let data) = fields[field]?.last { return String(decoding: data, as: UTF8.self) }
        return ""
    }

    func strings(_ field: Int) -> [String] {
        (fields[field] ?? []).compactMap { value in
            if case .bytes(let data) = value { return String(decoding: data, as: UTF8.self) }
            return nil
        }
    }
}

struct ProtoWriter {
    private(set) var data = Data()

    mutating func uint(_ field: Int, _ value: UInt64) {
        appendVarint(UInt64(field) << 3)
        appendVarint(value)
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        uint(field, value ? 1 : 0)
    }

    mutating func fixed32(_ field: Int, _ value: UInt32) {
        appendVarint(UInt64(field) << 3 | 5)
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func float(_ field: Int, _ value: Float) {
        fixed32(field, value.bitPattern)
    }

    mutating func string(_ field: Int, _ value: String) {
        let bytes = Data(value.utf8)
        appendVarint(UInt64(field) << 3 | 2)
        appendVarint(UInt64(bytes.count))
        data.append(bytes)
    }

    private mutating func appendVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            data.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        data.append(UInt8(value))
    }
}
