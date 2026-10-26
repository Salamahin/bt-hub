import AppKit
import BTHubCore
import SwiftUI

/// The panel under the status-bar icon: every audio device with a row per peer.
struct PanelView: View {
    @ObservedObject var hub: Hub
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let devices = hub.devices
            if devices.isEmpty {
                Text("No paired audio devices").foregroundStyle(.secondary)
            }
            ForEach(devices) { device in
                DeviceCard(hub: hub, device: device)
            }

            VStack(alignment: .leading, spacing: 4) {
                if hub.networkKey == nil {
                    Text("Network is not set up — only this Mac's devices are shown")
                } else {
                    Text("Online: \(hub.peers.filter(\.reachable).map(\.title).joined(separator: ", "))")
                    let offline = hub.peers.filter { !$0.reachable }
                    if !offline.isEmpty {
                        Text("No connection: \(offline.map(\.name).joined(separator: ", ")) (different key?)")
                    }
                }
                if let error = hub.lastError {
                    Text(verbatim: "⚠︎ " + error).foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()
            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct DeviceCard: View {
    @ObservedObject var hub: Hub
    let device: Hub.AudioDevice

    var body: some View {
        let busy = hub.busy.contains(device.address)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                Text(verbatim: device.name).bold()
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            Toggle("Only one Mac at a time", isOn: Binding(
                get: { hub.isExclusive(device.address) },
                set: { hub.setExclusive(device.address, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(hub.peers.filter(\.reachable)) { peer in
                let connected = device.connectedOn.contains(peer.id)
                HStack {
                    Image(systemName: connected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(connected ? Color.green : Color.secondary)
                    Text(verbatim: peer.title)
                    Spacer()
                    if connected {
                        Button("Disconnect") { Task { await hub.disconnect(device.address, from: peer.id) } }
                    } else if hub.isExclusive(device.address) {
                        Button(device.connectedOn.isEmpty ? LocalizedStringKey("Connect") : LocalizedStringKey("Move")) {
                            Task { await hub.move(device.address, to: peer.id) }
                        }
                    } else {
                        Button("Connect") { Task { await hub.connect(device.address, to: peer.id) } }
                    }
                }
                .disabled(busy)
            }
            if device.connectedOn.count > 1 {
                Button("Disconnect everywhere") { Task { await hub.disconnectEverywhere(device.address) } }
                    .disabled(busy)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private var icon: String {
        switch device.kind {
        case .headphones: "headphones"
        case .speaker: "hifispeaker"
        case .other: "speaker.wave.2"
        }
    }
}
