import AppKit
import BTHubCore
import SwiftUI

/// The panel under the status-bar icon: a section per Mac listing every audio device, then Macs that can join.
struct PanelView: View {
    @ObservedObject var hub: Hub
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(hub.peers.filter(\.reachable)) { peer in
                        MacSection(hub: hub, peer: peer)
                    }
                    NearbySection(hub: hub)
                }
            }
            .frame(maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)

            if let error = hub.lastError {
                Text(verbatim: "⚠︎ " + error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

private struct MacSection: View {
    @ObservedObject var hub: Hub
    let peer: Hub.Peer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                Text(verbatim: peer.title).bold()
                if peer.isLocal {
                    Text(verbatim: peer.name).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            let devices = hub.devices
            if devices.isEmpty {
                Text("No paired audio devices").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
                DeviceRow(hub: hub, device: device, peer: peer)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }
}

private struct DeviceRow: View {
    @ObservedObject var hub: Hub
    let device: Hub.AudioDevice
    let peer: Hub.Peer

    var body: some View {
        let paired = peer.devices.contains { $0.address == device.address }
        let here = device.connectedOn.contains(peer.id)
        let elsewhere = device.connectedOn.filter { $0 != peer.id }.compactMap { hub.peer($0)?.title }
        HStack {
            Image(systemName: icon)
                .foregroundStyle(here ? Color.green : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: device.name).lineLimit(1)
                Text(status(paired: paired, here: here, elsewhere: elsewhere))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if hub.busy.contains(device.address) {
                ProgressView().controlSize(.small)
            } else if paired {
                if here {
                    Button("Disconnect") { Task { await hub.disconnect(device.address, from: peer.id) } }
                } else {
                    Button(elsewhere.isEmpty ? LocalizedStringKey("Connect") : LocalizedStringKey("Move here")) {
                        Task { await hub.move(device.address, to: peer.id) }
                    }
                }
            }
        }
        .opacity(paired ? 1 : 0.5)
        .disabled(hub.busy.contains(device.address))
    }

    private func status(paired: Bool, here: Bool, elsewhere: [String]) -> LocalizedStringKey {
        if !paired { return "Not paired with this Mac" }
        if here { return "Connected" }
        if !elsewhere.isEmpty { return "On \(elsewhere.joined(separator: ", "))" }
        return "Not connected"
    }

    private var icon: String {
        switch device.kind {
        case .headphones: "headphones"
        case .speaker: "hifispeaker"
        case .other: "speaker.wave.2"
        }
    }
}

private struct NearbySection: View {
    @ObservedObject var hub: Hub

    var body: some View {
        let joinable = hub.joinable
        VStack(alignment: .leading, spacing: 8) {
            if let joining = hub.joining {
                if let code = joining.code {
                    Text("Allow the join on \(joining.name). It must show the code:")
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: code)
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting to \(joining.name)…")
                    }
                }
            } else if !joinable.isEmpty {
                Text("Macs nearby").bold()
                ForEach(joinable, id: \.id) { found in
                    HStack {
                        Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                        Text(verbatim: found.name).lineLimit(1)
                        Spacer()
                        Button("Join") { Task { await hub.join(found) } }
                    }
                }
                Text("Join pulls this Mac into that Mac's network; you confirm a code there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hub.peers.filter(\.reachable).count < 2 {
                Text("To add another Mac, install BT Hub on it and press Join there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
