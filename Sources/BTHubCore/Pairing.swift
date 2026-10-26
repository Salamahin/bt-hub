import CryptoKit
import Foundation
import Network

/// Hands the network key to a new Mac without copying it by hand.
///
/// The joining Mac and a member run an X25519 key agreement over plain TCP. Both derive a six-digit code from the
/// shared secret and show it; a man in the middle would end up with different secrets, so the codes would differ.
/// Once the user sees matching codes and allows the join on the member, it sends the network key sealed with a key
/// derived from the same secret.
public enum Pairing {
    public static let serviceType = "_bthub-pair._tcp"

    public struct Rejected: LocalizedError {
        public var errorDescription: String? { String(localized: "the other Mac declined") }
    }

    struct Hello: Codable {
        var id: String
        var name: String
        var publicKey: Data
    }

    struct Challenge: Codable {
        var publicKey: Data
    }

    struct Outcome: Codable {
        /// The network key sealed with ChaChaPoly; nil when the join was declined.
        var sealedKey: Data?
    }

    /// Joins the network of the member at `endpoint` and returns its network key.
    /// `showCode` runs as soon as the code is known, while the member waits for the user's decision.
    public static func join(_ endpoint: NWEndpoint, as me: PeerInfo, timeout: TimeInterval, showCode: @escaping @Sendable (String) async -> Void) async throws -> String {
        let connection = NWConnection(to: endpoint, using: parameters())
        let queue = DispatchQueue(label: "bthub.pairing.join")
        queue.asyncAfter(deadline: .now() + timeout) { connection.cancel() }
        defer { connection.cancel() }

        let mine = Curve25519.KeyAgreement.PrivateKey()
        try await connection.open(queue: queue)
        try await connection.sendFrame(Hello(id: me.id, name: me.name, publicKey: mine.publicKey.rawRepresentation))
        let challenge = try await connection.receiveFrame(Challenge.self)

        let secrets = try Secrets(mine: mine, theirs: challenge.publicKey, initiator: mine.publicKey.rawRepresentation, responder: challenge.publicKey)
        await showCode(secrets.code)

        let outcome = try await connection.receiveFrame(Outcome.self)
        guard let sealed = outcome.sealedKey else { throw Rejected() }
        let opened = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: secrets.sealingKey)
        guard let key = NetworkKey.normalize(String(decoding: opened, as: UTF8.self)) else { throw Rejected() }
        return key
    }

    static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        return parameters
    }

    struct Secrets {
        let code: String
        let sealingKey: SymmetricKey

        init(mine: Curve25519.KeyAgreement.PrivateKey, theirs: Data, initiator: Data, responder: Data) throws {
            let shared = try mine.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs))
            // Binding both public keys into the derivation makes a swapped key change the code.
            let transcript = initiator + responder
            sealingKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("bthub/pair/seal/v1".utf8), outputByteCount: 32)
            let codeKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("bthub/pair/code/v1".utf8), outputByteCount: 4)
            let number = codeKey.withUnsafeBytes { $0.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } } % 1_000_000
            let digits = String(format: "%06u", number)
            code = "\(digits.prefix(3)) \(digits.suffix(3))"
        }
    }
}

/// The member side of `Pairing`: advertises itself to Macs outside the network and answers join requests.
public final class PairingServer: @unchecked Sendable {
    /// Asked once per request with the joining Mac and the code; returns the network key to hand over, or nil to decline.
    public typealias Approver = @Sendable (PeerInfo, String) async -> String?

    private let listener: NWListener
    private let queue = DispatchQueue(label: "bthub.pairing.server")
    private let gate = Gate()

    public init(advertiseAs service: PeerInfo?, approve: @escaping Approver) throws {
        listener = try NWListener(using: Pairing.parameters())
        if let service {
            listener.service = NWListener.Service(name: service.name, type: Pairing.serviceType, domain: nil, txtRecord: NWTXTRecord(["id": service.id]))
        }
        let queue = self.queue
        let gate = self.gate
        listener.newConnectionHandler = { connection in
            Task { await PairingServer.serve(connection, queue: queue, gate: gate, approve: approve) }
        }
    }

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

    /// One request at a time, so nobody can stack up approval prompts.
    actor Gate {
        private var busy = false

        func enter() -> Bool {
            if busy { return false }
            busy = true
            return true
        }

        func leave() {
            busy = false
        }
    }

    private static func serve(_ connection: NWConnection, queue: DispatchQueue, gate: Gate, approve: Approver) async {
        defer { connection.cancel() }
        guard await gate.enter() else { return }
        do {
            defer { Task { await gate.leave() } }
            try await connection.open(queue: queue)
            let hello = try await connection.receiveFrame(Pairing.Hello.self)
            let mine = Curve25519.KeyAgreement.PrivateKey()
            try await connection.sendFrame(Pairing.Challenge(publicKey: mine.publicKey.rawRepresentation))

            let secrets = try Pairing.Secrets(mine: mine, theirs: hello.publicKey, initiator: hello.publicKey, responder: mine.publicKey.rawRepresentation)
            guard let key = await approve(PeerInfo(id: hello.id, name: hello.name), secrets.code) else {
                try await connection.sendFrame(Pairing.Outcome(sealedKey: nil))
                return
            }
            let sealed = try ChaChaPoly.seal(Data(key.utf8), using: secrets.sealingKey).combined
            try await connection.sendFrame(Pairing.Outcome(sealedKey: sealed))
        } catch {
            // The joining Mac gave up or sent garbage; nothing to answer.
        }
    }
}
