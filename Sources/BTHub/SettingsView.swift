import AppKit
import BTHubCore
import ServiceManagement
import SwiftUI

/// Window-local form state; `@State` is a macro in this SDK and its plugin ships only with Xcode.
final class SettingsForm: ObservableObject {
    @Published var name = ""
    @Published var enteredKey = ""
    @Published var revealed = false
    @Published var confirmNewKey = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}

struct SettingsView: View {
    @ObservedObject var hub: Hub
    @StateObject private var form = SettingsForm()

    var body: some View {
        Form {
            Section("This Mac") {
                TextField("Name on the network", text: $form.name)
                    .onSubmit { hub.rename(form.name) }
                Toggle("Launch at login", isOn: $form.launchAtLogin)
                    .onChange(of: form.launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            form.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                if let key = hub.networkKey {
                    HStack {
                        Text(verbatim: form.revealed ? key : String(repeating: "•", count: key.count))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button(form.revealed ? LocalizedStringKey("Hide") : LocalizedStringKey("Show")) { form.revealed.toggle() }
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(key, forType: .string)
                        }
                    }
                    Button("Create a new key…") { form.confirmNewKey = true }
                } else {
                    Text("Create a key on the first Mac, then enter the same key on the others.")
                    Button("Create a key") { hub.useKey(NetworkKey.generate()) }
                }
                HStack {
                    TextField("Key from another Mac", text: $form.enteredKey)
                        .font(.system(.body, design: .monospaced))
                    Button("Use") {
                        if let key = NetworkKey.normalize(form.enteredKey) {
                            hub.useKey(key)
                            form.enteredKey = ""
                        }
                    }
                    .disabled(NetworkKey.normalize(form.enteredKey) == nil)
                }
            } header: {
                Text("Network key")
            } footer: {
                Text("Macs with the same key see each other's audio devices and can control them. Traffic between them is encrypted with this key; a device on the same network without it cannot connect.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 440)
        .onAppear { form.name = hub.name }
        .confirmationDialog("Create a new key?", isPresented: $form.confirmNewKey) {
            Button("Create", role: .destructive) { hub.useKey(NetworkKey.generate()) }
        } message: {
            Text("Other Macs lose the connection to this one until the new key is entered on them.")
        }
    }
}
