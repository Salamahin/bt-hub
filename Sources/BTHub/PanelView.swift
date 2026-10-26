import AppKit
import BTHubCore
import SwiftUI

/// The panel under the status-bar icon: each Mac with the audio devices paired to it.
struct PanelView: View {
    @ObservedObject var hub: Hub
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(hub.peers.filter(\.reachable)) { peer in
                MacSection(hub: hub, peer: peer)
            }
            NearbySection(hub: hub)

            if let error = hub.lastError {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button("Settings…", action: openSettings).buttonStyle(.borderless)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

private struct MacSection: View {
    @ObservedObject var hub: Hub
    let peer: Hub.Peer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: peer.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(hub.devices.filter { device in peer.devices.contains { $0.address == device.address } }) { device in
                DeviceRow(hub: hub, device: device, peer: peer)
            }
        }
    }
}

private struct DeviceRow: View {
    @ObservedObject var hub: Hub
    let device: Hub.AudioDevice
    let peer: Hub.Peer

    var body: some View {
        let here = device.connectedOn.contains(peer.id)
        HStack {
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
                .opacity(here ? 1 : 0)
            Text(verbatim: device.name).lineLimit(1)
            Spacer()
            if hub.busy.contains(device.address) {
                ProgressView().controlSize(.small)
            } else if here {
                Button("Disconnect") { Task { await hub.disconnect(device.address, from: peer.id) } }
            } else {
                // Move only makes sense when another Mac has it; otherwise this just connects it.
                Button(device.connectedOn.isEmpty ? LocalizedStringKey("Connect") : LocalizedStringKey("Move here")) {
                    Task { await hub.move(device.address, to: peer.id) }
                }
            }
        }
    }
}

private struct NearbySection: View {
    @ObservedObject var hub: Hub

    var body: some View {
        if let joining = hub.joining {
            VStack(alignment: .leading, spacing: 4) {
                Text("Confirm on \(joining.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let code = joining.code {
                    Text(verbatim: code).font(.system(size: 26, weight: .semibold, design: .monospaced))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        } else if !hub.joinable.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nearby")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(hub.joinable, id: \.id) { found in
                    HStack {
                        Text(verbatim: found.name).lineLimit(1)
                        Spacer()
                        Button("Join") { Task { await hub.join(found) } }
                    }
                }
            }
        }
    }
}
