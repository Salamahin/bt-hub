import Foundation
import Network

public let serviceType = "_bthub._tcp"

/// Accepts one request per connection from other peers and answers it with `handler`.
public final class PeerServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Request) async -> Response

    private let listener: NWListener
    private let queue = DispatchQueue(label: "bthub.server")

    /// `advertiseAs` publishes the server over Bonjour; tests pass nil and connect by port.
    public init(key: String, advertiseAs service: PeerInfo?, handler: @escaping Handler) throws {
        listener = try NWListener(using: NetworkKey.parameters(key: key))
        if let service {
            listener.service = NWListener.Service(name: service.name, type: serviceType, domain: nil, txtRecord: NWTXTRecord(["id": service.id]))
        }
        let queue = self.queue
        listener.newConnectionHandler = { connection in
            Task { await PeerServer.serve(connection, queue: queue, handler: handler) }
        }
    }

    /// Returns once the listener accepts connections.
    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error): once.resume(.failure(error))
                case .cancelled: once.resume(.failure(ConnectionClosed()))
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    public var port: UInt16? { listener.port?.rawValue }

    public func stop() {
        listener.cancel()
    }

    private static func serve(_ connection: NWConnection, queue: DispatchQueue, handler: Handler) async {
        defer { connection.cancel() }
        do {
            try await connection.open(queue: queue)
            let request = try await connection.receiveFrame(Request.self)
            try await connection.sendFrame(await handler(request))
        } catch {
            // A peer with the wrong key fails the handshake here; there is nothing to answer.
        }
    }
}
