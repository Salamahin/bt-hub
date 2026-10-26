import Foundation
import Network

public enum PeerClient {
    private static let queue = DispatchQueue(label: "bthub.client", attributes: .concurrent)

    /// Sends one request and waits for the answer; gives up after `timeout` seconds.
    public static func send(_ request: Request, to endpoint: NWEndpoint, key: String, timeout: TimeInterval) async throws -> Response {
        let connection = NWConnection(to: endpoint, using: NetworkKey.parameters(key: key))
        // Cancelling fails whatever step is pending, which ends the call with an error.
        queue.asyncAfter(deadline: .now() + timeout) { connection.cancel() }
        defer { connection.cancel() }
        try await connection.open(queue: queue)
        try await connection.sendFrame(request)
        return try await connection.receiveFrame(Response.self)
    }

    public static func send(_ request: Request, toHost host: String, port: UInt16, key: String, timeout: TimeInterval) async throws -> Response {
        try await send(request, to: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!), key: key, timeout: timeout)
    }
}
