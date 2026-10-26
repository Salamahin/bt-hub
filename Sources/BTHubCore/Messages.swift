import Foundation

/// One BT Hub instance on the network.
public struct PeerInfo: Codable, Hashable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A Bluetooth audio device as seen by one peer.
public struct DeviceState: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case headphones, speaker, other
    }

    /// Bluetooth address in `AA:BB:CC:DD:EE:FF` form; the same on every host, so it identifies the device across peers.
    public var address: String
    public var name: String
    public var connected: Bool
    /// Optional so peers that do not report it still decode.
    public var kind: Kind?

    public init(address: String, name: String, connected: Bool, kind: Kind? = nil) {
        self.address = address
        self.name = name
        self.connected = connected
        self.kind = kind
    }
}

public enum Operation: String, Codable, Sendable {
    case status, connect, disconnect
}

public struct Request: Codable, Sendable, Equatable {
    public var op: Operation
    public var address: String?

    public init(op: Operation, address: String? = nil) {
        self.op = op
        self.address = address
    }

    public static let status = Request(op: .status)
    public static func connect(_ address: String) -> Request { Request(op: .connect, address: address) }
    public static func disconnect(_ address: String) -> Request { Request(op: .disconnect, address: address) }
}

public struct Response: Codable, Sendable, Equatable {
    public var ok: Bool
    public var error: String?
    public var peer: PeerInfo?
    public var devices: [DeviceState]?

    public init(ok: Bool, error: String? = nil, peer: PeerInfo? = nil, devices: [DeviceState]? = nil) {
        self.ok = ok
        self.error = error
        self.peer = peer
        self.devices = devices
    }

    public static func failure(_ message: String) -> Response { Response(ok: false, error: message) }
}

/// Length-prefixed JSON: a 4-byte big-endian size, then the body.
public enum Frame {
    public static let headerSize = 4
    public static let maxBodySize = 64 * 1024

    public struct TooLarge: Error {}

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maxBodySize else { throw TooLarge() }
        var size = UInt32(body.count).bigEndian
        return Data(bytes: &size, count: headerSize) + body
    }

    public static func bodySize(fromHeader header: Data) throws -> Int {
        guard header.count == headerSize else { throw TooLarge() }
        let size = header.reduce(0) { ($0 << 8) | Int($1) }
        guard size <= maxBodySize else { throw TooLarge() }
        return size
    }

    public static func decode<T: Decodable>(_ type: T.Type, from body: Data) throws -> T {
        try JSONDecoder().decode(type, from: body)
    }
}
