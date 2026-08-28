import SefirahCore
import SwiftUI

struct AppsView: View {
    @Bindable var model: AppModel
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Apps").font(.title2.weight(.semibold))
                Spacer()
                TextField("Search", text: $query)
                    .frame(width: 200)
                Button("Refresh") { model.refreshDevice() }
            }
            .padding()
            let filtered = model.apps.filter { query.isEmpty || $0.appName.localizedCaseInsensitiveContains(query) }
            if filtered.isEmpty {
                ContentUnavailableView("No apps", systemImage: "square.grid.2x2", description: Text("Connected phones sync their launcher apps here."))
            } else {
                List(filtered, id: \.appKey) { app in
                    HStack {
                        Text(app.appName)
                        Spacer()
                        Button("Launch") { model.launchScrcpy(package: app.packageName, appName: app.appName) }
                    }
                }
            }
        }
    }
}
