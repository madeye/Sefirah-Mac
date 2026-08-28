import SefirahCore
import SwiftUI

struct MainSplitView: View {
    @Bindable var model: AppModel
    @State private var tab: MainTab = .calls

    var body: some View {
        HSplitView {
            ScrollView {
                DeviceRailView(model: model)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            .background(.background)

            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    Text("Calls").tag(MainTab.calls)
                    Text("Messages").tag(MainTab.messages)
                    Text("Apps").tag(MainTab.apps)
                    Text("Settings").tag(MainTab.settings)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                .padding(.vertical, 10)

                Divider()

                Group {
                    switch tab {
                    case .calls:
                        CallsView(model: model)
                    case .messages:
                        MessagesView(model: model)
                    case .apps:
                        AppsView(model: model)
                    case .settings:
                        SettingsView(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum MainTab: Hashable {
    case calls, messages, apps, settings
}
