import SefirahCore
import SwiftUI

struct NotificationFeedView: View {
    @Bindable var model: AppModel
    @State private var replyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notifications").font(.headline)
            if model.notifications.isEmpty {
                Text("No notifications").foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.notifications) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.appName).font(.caption).foregroundStyle(.secondary)
                            Text(note.title ?? "").font(.headline)
                            Text(note.text ?? "").foregroundStyle(.secondary)
                            HStack {
                                if note.replyResultKey != nil {
                                    TextField("Reply", text: $replyText)
                                    Button("Send") {
                                        model.replyToNotification(note, text: replyText)
                                        replyText = ""
                                    }
                                }
                                ForEach(note.actions, id: \.actionIndex) { action in
                                    Button(action.label ?? "Action") {
                                        model.invokeNotification(note, action: action)
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}
