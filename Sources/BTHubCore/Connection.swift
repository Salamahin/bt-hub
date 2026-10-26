import Foundation
import Network

public struct ConnectionClosed: Error {}

/// Resumes a continuation at most once; NWConnection may report several terminal states.
final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

extension NWConnection {
    /// Starts the connection and waits for the TLS handshake; fails if the peer holds a different key.
    func open(queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once(continuation)
            stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error), .waiting(let error): once.resume(.failure(error))
                case .cancelled: once.resume(.failure(ConnectionClosed()))
                default: break
                }
            }
            start(queue: queue)
        }
    }

    func sendFrame<T: Encodable>(_ value: T) async throws {
        let data = try Frame.encode(value)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func receiveFrame<T: Decodable>(_ type: T.Type) async throws -> T {
        let header = try await receiveExactly(Frame.headerSize)
        let body = try await receiveExactly(try Frame.bodySize(fromHeader: header))
        return try Frame.decode(type, from: body)
    }

    private func receiveExactly(_ count: Int) async throws -> Data {
        if count == 0 { return Data() }
        return try await withCheckedThrowingContinuation { continuation in
            receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ConnectionClosed())
                }
            }
        }
    }
}
