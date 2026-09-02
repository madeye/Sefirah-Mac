import AppKit
import SefirahCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("General") {
                Picker("Theme", selection: $model.general.theme) {
                    Text("System").tag(Theme.default)
                    Text("Light").tag(Theme.light)
                    Text("Dark").tag(Theme.dark)
                }
                Picker("Startup", selection: $model.general.startupOption) {
                    Text("Menu bar only").tag(StartupOptions.inTray)
                    Text("Minimized").tag(StartupOptions.minimized)
                    Text("Window").tag(StartupOptions.maximized)
                    Text("Disabled").tag(StartupOptions.disabled)
                }
                TextField("Device name", text: $model.general.localDeviceName)
                TextField("Received files", text: $model.general.receivedFilesPath)
                Button("Save") { model.saveGeneral() }
            }
            Section("Screen mirroring") {
                LabeledContent("Bundled scrcpy", value: model.bundledScrcpyVersion.map { "v\($0)" } ?? "Not found — reinstall Sefirah")
                MirrorSettingsView(model: model, deviceId: model.selectedDevice?.id)
                DisclosureGroup("Advanced") {
                    HStack {
                        TextField("Custom scrcpy path", text: $model.general.scrcpyPath)
                        Button("Choose…") { choosePath { model.general.scrcpyPath = $0; model.saveGeneral() } }
                    }
                    HStack {
                        TextField("Custom adb path", text: $model.general.adbPath)
                        Button("Choose…") { choosePath { model.general.adbPath = $0; model.saveGeneral() } }
                    }
                    Text("Leave empty to use the bundled copies. A custom scrcpy uses its own scrcpy-server.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Save paths") { model.saveGeneral() }
                    HStack {
                        Button("Restart ADB server") { model.restartAdbServer() }
                        if let result = model.adbRestartResult {
                            Text(result).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Devices") {
                ForEach(model.paired) { device in
                    HStack {
                        LabeledContent(device.name, value: device.isConnected ? "Connected" : "Offline")
                        if !device.isConnected {
                            Button("Connect") { model.reconnect(device) }
                        }
                    }
                }
                ForEach(model.discovered) { peer in
                    HStack {
                        Text("\(peer.name)  \(peer.verificationKey)")
                        Spacer()
                        Button("Pair") { model.pair(peer) }
                    }
                }
            }
            Section("Actions") {
                ForEach(model.general.actions) { action in
                    HStack {
                        Text(action.name.isEmpty ? action.actionId : action.name)
                        Spacer()
                        Button("Run") { model.runAction(action) }
                    }
                }
                if model.general.actions.isEmpty {
                    Text("Add Link, Power, or Run actions. They sync to the phone when connected.")
                        .foregroundStyle(.secondary)
                }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                LabeledContent("Ports", value: "UDP 5149, TLS 5150–5169")
                Link("Sefirah on GitHub", destination: URL(string: "https://github.com/shrimqy/Sefirah")!)
                Link("Android app", destination: URL(string: "https://github.com/shrimqy/Sefirah-Android")!)
                Button("Third-party notices") { model.openThirdPartyNotices() }
                    .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func choosePath(_ apply: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            apply(url.path)
        }
    }
}
