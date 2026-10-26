import CryptoKit
import Foundation
import Testing
@testable import BTHubCore

@Suite struct NetworkKeyTests {
    @Test func generatedKeyIsCanonical() {
        let key = NetworkKey.generate()
        #expect(key.count == 23) // 4 groups of 5 plus 3 dashes
        #expect(NetworkKey.normalize(key) == key)
    }

    @Test func generatedKeysDiffer() {
        #expect(NetworkKey.generate() != NetworkKey.generate())
    }

    @Test func normalizeAcceptsSloppyInput() {
        let key = NetworkKey.generate()
        let sloppy = " " + key.lowercased().replacingOccurrences(of: "-", with: " ") + "\n"
        #expect(NetworkKey.normalize(sloppy) == key)
    }

    @Test func normalizeRejectsGarbage() {
        #expect(NetworkKey.normalize("") == nil)
        #expect(NetworkKey.normalize("ABCDE-FGHJK") == nil)
        #expect(NetworkKey.normalize("ABCDE-FGHJK-LMNPQ-RSTU0") == nil) // 0 is not in the alphabet
    }
}

@Suite struct FrameTests {
    @Test func roundTrip() throws {
        let response = Response(ok: true, peer: PeerInfo(id: "a", name: "Mac"), devices: [DeviceState(address: "AA:BB:CC:DD:EE:FF", name: "MX5", connected: true)])
        let data = try Frame.encode(response)
        let size = try Frame.bodySize(fromHeader: data.prefix(Frame.headerSize))
        #expect(size == data.count - Frame.headerSize)
        #expect(try Frame.decode(Response.self, from: data.dropFirst(Frame.headerSize)) == response)
    }

    @Test func rejectsOversizedFrame() {
        #expect(throws: Frame.TooLarge.self) { try Frame.bodySize(fromHeader: Data([0x7f, 0xff, 0xff, 0xff])) }
    }
}

@Suite(.serialized) struct PeerTransportTests {
    static let peer = PeerInfo(id: "server", name: "Test Mac")

    func startServer(key: String) async throws -> PeerServer {
        let server = try PeerServer(key: key, advertiseAs: nil) { request in
            switch request.op {
            case .status: Response(ok: true, peer: Self.peer, devices: [])
            case .connect, .disconnect: Response(ok: request.address == "AA:BB:CC:DD:EE:FF", error: nil)
            }
        }
        try await server.start()
        return server
    }

    @Test func sameKeyTalks() async throws {
        let key = NetworkKey.generate()
        let server = try await startServer(key: key)
        defer { server.stop() }

        let status = try await PeerClient.send(.status, toHost: "127.0.0.1", port: server.port!, key: key, timeout: 5)
        #expect(status.peer == Self.peer)
        let connect = try await PeerClient.send(.connect("AA:BB:CC:DD:EE:FF"), toHost: "127.0.0.1", port: server.port!, key: key, timeout: 5)
        #expect(connect.ok)
    }

    @Test func otherKeyIsRejected() async throws {
        let server = try await startServer(key: NetworkKey.generate())
        defer { server.stop() }

        await #expect(throws: (any Error).self) {
            _ = try await PeerClient.send(.status, toHost: "127.0.0.1", port: server.port!, key: NetworkKey.generate(), timeout: 5)
        }
    }

    @Test func unreachablePeerTimesOut() async throws {
        let started = Date()
        await #expect(throws: (any Error).self) {
            // TEST-NET-1 never answers, so only the timeout can end the call.
            _ = try await PeerClient.send(.status, toHost: "192.0.2.1", port: 9, key: NetworkKey.generate(), timeout: 1)
        }
        #expect(Date().timeIntervalSince(started) < 4)
    }
}

@Suite struct ExclusivityTests {
    @Test func ownerKeepsTheDevice() {
        #expect(Exclusivity.winner(holders: ["a", "b"], owner: "b") == "b")
        #expect(Exclusivity.losers(holders: ["a", "b"], owner: "b") == ["a"])
    }

    @Test func absentOwnerFallsBackToStablePick() {
        #expect(Exclusivity.winner(holders: ["c", "a", "b"], owner: "z") == "a")
        #expect(Exclusivity.winner(holders: ["b", "a"], owner: nil) == Exclusivity.winner(holders: ["a", "b"], owner: nil))
    }

    @Test func singleHolderLosesNothing() {
        #expect(Exclusivity.losers(holders: ["a"], owner: nil).isEmpty)
        #expect(Exclusivity.losers(holders: [], owner: "a").isEmpty)
    }

    @Test func newerSettingsWin() {
        let old = SharedSettings(owners: ["X": "b"], updatedAt: 1)
        let new = SharedSettings(owners: ["X": "a"], updatedAt: 2)
        #expect(old.merged(with: new) == new)
        #expect(new.merged(with: old) == new)
    }

    @Test func settingsFromVersionWithMultipointDecode() throws {
        let json = #"{"multipoint":["X"],"owners":{"X":"a"},"updatedAt":3}"#
        #expect(try JSONDecoder().decode(SharedSettings.self, from: Data(json.utf8)) == SharedSettings(owners: ["X": "a"], updatedAt: 3))
    }

    @Test func responseFromOlderPeerDecodes() throws {
        let json = #"{"ok":true,"devices":[{"address":"A","name":"N","connected":false}]}"#
        let response = try Frame.decode(Response.self, from: Data(json.utf8))
        #expect(response.settings == nil)
        #expect(response.devices?.first?.kind == nil)
    }
}

@Suite struct KeyLinkTests {
    @Test func linkRoundTrips() {
        let key = NetworkKey.generate()
        let url = NetworkKey.shareURL(for: key)
        #expect(url.scheme == "bthub")
        #expect(NetworkKey.key(from: url) == key)
    }

    @Test func pastedLinkOrKeyIsAccepted() {
        let key = NetworkKey.generate()
        #expect(NetworkKey.parse(" \(NetworkKey.shareURL(for: key).absoluteString)\n") == key)
        #expect(NetworkKey.parse(key.lowercased()) == key)
    }

    @Test func foreignLinksAreRejected() {
        #expect(NetworkKey.key(from: URL(string: "https://example.com/key?k=ABCDE-FGHJK-LMNPQ-RSTUV")!) == nil)
        #expect(NetworkKey.key(from: URL(string: "bthub://other?k=ABCDE-FGHJK-LMNPQ-RSTUV")!) == nil)
        #expect(NetworkKey.key(from: URL(string: "bthub://key?k=short")!) == nil)
    }
}

@Suite(.serialized) struct PairingTests {
    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T?
        var value: T? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    static let joiner = PeerInfo(id: "new", name: "New Mac")

    @Test func approvedJoinReceivesTheKeyAndBothSeeTheSameCode() async throws {
        let key = NetworkKey.generate()
        let memberCode = Box<String>()
        let joinerCode = Box<String>()
        let askedAbout = Box<PeerInfo>()
        let server = try PairingServer(advertiseAs: nil) { peer, code in
            askedAbout.value = peer
            memberCode.value = code
            return key
        }
        try await server.start()
        defer { server.stop() }

        let received = try await Pairing.join(.hostPort(host: "127.0.0.1", port: .init(rawValue: server.port!)!), as: Self.joiner, timeout: 5) { code in
            joinerCode.value = code
        }
        #expect(received == key)
        #expect(askedAbout.value == Self.joiner)
        #expect(joinerCode.value != nil)
        #expect(joinerCode.value == memberCode.value)
        #expect(joinerCode.value?.count == 7) // "123 456"
    }

    @Test func declinedJoinThrows() async throws {
        let server = try PairingServer(advertiseAs: nil) { _, _ in nil }
        try await server.start()
        defer { server.stop() }

        await #expect(throws: Pairing.Rejected.self) {
            _ = try await Pairing.join(.hostPort(host: "127.0.0.1", port: .init(rawValue: server.port!)!), as: Self.joiner, timeout: 5) { _ in }
        }
    }

    @Test func codesDifferBetweenSessions() throws {
        func code() throws -> String {
            let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
            return try Pairing.Secrets(mine: a, theirs: b.publicKey.rawRepresentation, initiator: a.publicKey.rawRepresentation, responder: b.publicKey.rawRepresentation).code
        }
        let codes = try (0..<5).map { _ in try code() }
        #expect(Set(codes).count > 1)
    }
}
