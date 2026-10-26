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
