import BTHubCore
import Foundation
import Network
import os

let log = Logger(subsystem: "dev.salamahin.bthub", category: "hub")

/// Everything the panel shows: which peers are around, which audio devices each one has, and where they are connected.
@MainActor
final class Hub: ObservableObject {
    struct Peer: Identifiable, Equatable {
        let id: String
        var name: String
        let isLocal: Bool
        var endpoint: NWEndpoint?
        var reachable: Bool
        var devices: [DeviceState]

        var title: String { isLocal ? String(localized: "This Mac") : name }
    }

    struct AudioDevice: Identifiable {
        var id: String { address }
        let address: String
        let name: String
        let kind: DeviceState.Kind
        /// Ids of the peers it is connected to right now.
        let connectedOn: [String]
    }

    private static let refreshInterval: TimeInterval = 5
    private static let statusTimeout: TimeInterval = 4
    private static let connectTimeout: TimeInterval = 20
    private static let releaseWait: TimeInterval = 8

    @Published private(set) var peers: [Peer] = []
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var lastError: String?
    @Published private(set) var networkKey: String?
    @Published private(set) var name: String
    @Published private(set) var settings: SharedSettings
    /// Every Mac running BT Hub nearby, members or not.
    @Published private(set) var nearby: [PeerBrowser.Found] = []
    @Published private(set) var joining: Joining?

    struct Joining: Equatable {
        let name: String
        var code: String?
    }

    /// Asks the user whether a Mac showing `code` may join; set by the app delegate.
    var approveJoin: ((PeerInfo, String) -> Bool)?

    let ownID: String
    private let bluetooth = Bluetooth()
    private var server: PeerServer?
    private var browser: PeerBrowser?
    private var timer: Timer?
    private var reconciling = false
    private var pairingServer: PairingServer?
    private var pairingBrowser: PeerBrowser?

    init() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "peerID") {
            ownID = id
        } else {
            ownID = UUID().uuidString
            defaults.set(ownID, forKey: "peerID")
        }
        name = defaults.string(forKey: "name") ?? Host.current().localizedName ?? "Mac"
        networkKey = KeyStore.load()
        settings = defaults.data(forKey: "sharedSettings").flatMap { try? JSONDecoder().decode(SharedSettings.self, from: $0) } ?? SharedSettings()
        peers = [Peer(id: ownID, name: name, isLocal: true, endpoint: nil, reachable: true, devices: [])]

        startNetwork()
        startPairing()
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    // MARK: - What the menu reads

    var devices: [AudioDevice] {
        var first: [String: DeviceState] = [:]
        var order: [String] = []
        for peer in peers where peer.reachable {
            for device in peer.devices where first[device.address] == nil {
                first[device.address] = device
                order.append(device.address)
            }
        }
        return order
            .map { address in
                AudioDevice(
                    address: address,
                    name: first[address]!.name,
                    kind: first[address]!.kind ?? .other,
                    connectedOn: peers.filter { $0.reachable && $0.devices.contains { $0.address == address && $0.connected } }.map(\.id)
                )
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var anyConnectedHere: Bool {
        peers.first(where: \.isLocal)?.devices.contains(where: \.connected) ?? false
    }

    func peer(_ id: String) -> Peer? {
        peers.first { $0.id == id }
    }

    /// Macs nearby that are not in this network yet (or use another key).
    var joinable: [PeerBrowser.Found] {
        nearby.filter { found in !peers.contains { $0.id == found.id && $0.reachable } }
    }

    // MARK: - Joining

    /// Joins the network of `member`: both Macs show a code and the user allows it on the member.
    func join(_ member: PeerBrowser.Found) async {
        guard joining == nil else { return }
        joining = Joining(name: member.name)
        lastError = nil
        do {
            let key = try await Pairing.join(member.endpoint, as: PeerInfo(id: ownID, name: name), timeout: 120) { code in
                await MainActor.run { self.joining?.code = code }
            }
            useKey(key)
        } catch {
            lastError = "\(member.name): \(error.localizedDescription)"
        }
        joining = nil
    }

    private func startPairing() {
        let me = PeerInfo(id: ownID, name: name)
        do {
            let server = try PairingServer(advertiseAs: me) { [weak self] peer, code in
                await self?.approve(peer, code: code)
            }
            pairingServer = server
            Task { try? await server.start() }
        } catch {
            lastError = String(localized: "Could not open a network port: \(error.localizedDescription)")
        }
        let browser = PeerBrowser(ownID: ownID, type: Pairing.serviceType) { [weak self] found in
            guard let self, found != self.nearby else { return }
            self.nearby = found
        }
        pairingBrowser = browser
        browser.start()
    }

    private func approve(_ peer: PeerInfo, code: String) -> String? {
        guard approveJoin?(peer, code) == true else { return nil }
        // The first Mac to let another one in starts the network.
        if networkKey == nil { useKey(NetworkKey.generate()) }
        return networkKey
    }

    // MARK: - Actions

    /// Connects the device to `target` alone: every other peer lets go of it first.
    func move(_ address: String, to target: String) async {
        setOwner(address, target)
        await act(on: address) {
            let holders = self.holders(of: address).filter { $0 != target }
            for holder in holders {
                try await self.call(holder, .disconnect(address), timeout: Self.statusTimeout)
            }
            if !holders.isEmpty { try await self.waitUntilReleased(address, by: holders) }
            try await self.call(target, .connect(address), timeout: Self.connectTimeout)
        }
    }

    func disconnect(_ address: String, from peerID: String) async {
        await act(on: address) {
            try await self.call(peerID, .disconnect(address), timeout: Self.statusTimeout)
        }
    }

    // MARK: - Settings

    func useKey(_ key: String) {
        KeyStore.save(key)
        networkKey = key
        restartNetwork()
    }

    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        name = trimmed
        UserDefaults.standard.set(trimmed, forKey: "name")
        restartNetwork()
        pairingServer?.stop()
        pairingBrowser?.stop()
        startPairing()
    }

    // MARK: - Internals

    private func act(on address: String, _ body: @escaping () async throws -> Void) async {
        guard !busy.contains(address) else { return }
        busy.insert(address)
        lastError = nil
        do {
            try await body()
        } catch {
            let device = devices.first { $0.address == address }?.name ?? address
            lastError = "\(device): \(error.localizedDescription)"
            log.error("action on \(address, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        busy.remove(address)
        await refresh()
    }

    private func holders(of address: String) -> [String] {
        devices.first { $0.address == address }?.connectedOn ?? []
    }

    private func waitUntilReleased(_ address: String, by holders: [String]) async throws {
        let deadline = Date().addingTimeInterval(Self.releaseWait)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            await refresh()
            if Set(self.holders(of: address)).isDisjoint(with: holders) { return }
        }
        throw Bluetooth.Failure(errorDescription: String(localized: "the other device did not let go of it"))
    }

    @discardableResult
    private func call(_ peerID: String, _ request: Request, timeout: TimeInterval) async throws -> Response {
        guard let peer = peer(peerID) else { throw Bluetooth.Failure(errorDescription: String(localized: "the peer left the network")) }
        let response: Response
        if peer.isLocal {
            response = await handle(request)
        } else {
            guard let endpoint = peer.endpoint, let key = networkKey else { throw Bluetooth.Failure(errorDescription: String(localized: "no connection to \(peer.name)")) }
            do {
                response = try await PeerClient.send(request, to: endpoint, key: key, timeout: timeout)
            } catch {
                throw Bluetooth.Failure(errorDescription: String(localized: "no connection to \(peer.name)"))
            }
        }
        guard response.ok else {
            throw Bluetooth.Failure(errorDescription: "\(peer.title): \(response.error ?? String(localized: "unknown error"))")
        }
        return response
    }

    /// Answers requests from other peers, and from this Mac's own menu.
    private nonisolated func handle(_ request: Request) async -> Response {
        let (me, shared) = await MainActor.run { (PeerInfo(id: self.ownID, name: self.name), self.settings) }
        do {
            switch request.op {
            case .status:
                break
            case .connect:
                guard let address = request.address else { return .failure(String(localized: "no device given")) }
                try await bluetooth.connect(address)
            case .disconnect:
                guard let address = request.address else { return .failure(String(localized: "no device given")) }
                try await bluetooth.disconnect(address)
            }
            return Response(ok: true, peer: me, devices: await bluetooth.audioDevices(), settings: shared)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func refresh() async {
        let local = await bluetooth.audioDevices()
        let remote = peers.filter { !$0.isLocal }
        let key = networkKey

        let statuses = await withTaskGroup(of: (String, Response?).self) { group in
            for peer in remote {
                group.addTask {
                    guard let endpoint = peer.endpoint, let key else { return (peer.id, nil) }
                    return (peer.id, try? await PeerClient.send(.status, to: endpoint, key: key, timeout: Self.statusTimeout))
                }
            }
            var result: [String: Response?] = [:]
            for await (id, response) in group { result[id] = response }
            return result
        }

        // Republishing an unchanged list rebuilds the open menu, which closes it.
        let updated = peers.map { peer in
            var peer = peer
            if peer.isLocal {
                peer.name = name
                peer.devices = local
            } else if let response = statuses[peer.id] ?? nil, response.ok {
                peer.reachable = true
                peer.devices = response.devices ?? []
                if let name = response.peer?.name { peer.name = name }
            } else if statuses[peer.id] != nil {
                peer.reachable = false
            }
            return peer
        }
        if updated != peers { peers = updated }

        for response in statuses.values.compactMap({ $0 }) {
            if let remote = response.settings, remote.updatedAt > settings.updatedAt { adopt(remote) }
        }
        await reconcile()
    }

    /// Keeps every device on a single peer, e.g. when a multipoint device connects to two Macs by itself. Only the peer that should keep it acts,
    /// so peers never fight over a device.
    private func reconcile() async {
        guard !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        for device in devices where !busy.contains(device.address) {
            let holders = device.connectedOn
            if holders.count == 1 {
                // Remember who had it alone, so that peer keeps it when another one grabs it too.
                setOwner(device.address, holders[0])
                continue
            }
            let owner = settings.owners[device.address]
            guard Exclusivity.winner(holders: holders, owner: owner) == ownID else { continue }
            for loser in Exclusivity.losers(holders: holders, owner: owner) {
                do {
                    try await call(loser, .disconnect(device.address), timeout: Self.statusTimeout)
                } catch {
                    log.error("could not take \(device.address, privacy: .public) from \(loser, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func setOwner(_ address: String, _ peerID: String) {
        guard settings.owners[address] != peerID else { return }
        var updated = settings
        updated.owners[address] = peerID
        publish(updated)
    }

    /// Records a local change; the new timestamp makes it win over the other peers' copies.
    private func publish(_ new: SharedSettings) {
        var stamped = new
        stamped.updatedAt = Date().timeIntervalSince1970
        adopt(stamped)
    }

    private func adopt(_ new: SharedSettings) {
        settings = new
        UserDefaults.standard.set(try? JSONEncoder().encode(new), forKey: "sharedSettings")
    }

    private func startNetwork() {
        guard let key = networkKey else { return }
        let me = PeerInfo(id: ownID, name: name)
        do {
            let server = try PeerServer(key: key, advertiseAs: me) { [weak self] request in
                guard let self else { return .failure(String(localized: "shutting down")) }
                return await self.handle(request)
            }
            self.server = server
            Task { try? await server.start() }
        } catch {
            lastError = String(localized: "Could not open a network port: \(error.localizedDescription)")
        }

        let browser = PeerBrowser(ownID: ownID) { [weak self] found in
            self?.updatePeers(found)
        }
        self.browser = browser
        browser.start()
    }

    private func restartNetwork() {
        server?.stop()
        browser?.stop()
        server = nil
        browser = nil
        peers = peers.filter(\.isLocal)
        startNetwork()
        Task { await refresh() }
    }

    private func updatePeers(_ found: [PeerBrowser.Found]) {
        let known = Dictionary(uniqueKeysWithValues: peers.map { ($0.id, $0) })
        let remote = found.map { item -> Peer in
            var peer = known[item.id] ?? Peer(id: item.id, name: item.name, isLocal: false, endpoint: nil, reachable: false, devices: [])
            peer.endpoint = item.endpoint
            return peer
        }
        let updated = peers.filter(\.isLocal) + remote
        guard updated != peers else { return }
        peers = updated
        Task { await refresh() }
    }
}
