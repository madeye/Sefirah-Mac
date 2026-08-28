import SefirahCore
import SwiftUI

struct CallsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading) {
            Text("Calls").font(.title2.weight(.semibold)).padding()
            if model.callLogs.isEmpty {
                ContentUnavailableView("No call history", systemImage: "phone", description: Text("Incoming and missed calls from your phone appear here."))
            } else {
                List(model.callLogs, id: \.key) { log in
                    HStack {
                        Image(systemName: icon(for: log.callType))
                        VStack(alignment: .leading) {
                            Text(log.phoneNumber)
                            Text(log.callType.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(log.durationSeconds)s").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func icon(for type: CallLogType) -> String {
        switch type {
        case .missed, .rejected: "phone.down"
        case .outgoing: "phone.arrow.up.right"
        default: "phone.arrow.down.left"
        }
    }
}
