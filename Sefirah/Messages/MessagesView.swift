import SefirahCore
import SwiftUI

struct MessagesView: View {
    @Bindable var model: AppModel

    var body: some View {
        // Nested HSplitView inside the main window split does not
        // fill its parent on macOS; use a fixed two-column stack.
        HStack(spacing: 0) {
            conversationList
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            threadPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var conversationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Messages")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Divider()
            if model.conversations.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No conversations")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("On the phone, turn on Message sync for this Mac, grant SMS permission, then reconnect.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.conversations, id: \.threadId, selection: threadSelection) { conversation in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.addresses.joined(separator: ", "))
                            .font(.headline)
                            .lineLimit(1)
                        Text(conversation.lastMessage ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(conversation.threadId)
                }
                .listStyle(.sidebar)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var threadSelection: Binding<Int64?> {
        Binding(
            get: { model.selectedThreadID },
            set: { if let id = $0 { model.selectThread(id) } }
        )
    }

    private var threadPane: some View {
        VStack(spacing: 0) {
            if model.selectedThreadID == nil {
                ContentUnavailableView("Select a conversation", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(model.messages) { message in
                            HStack {
                                if message.outgoing { Spacer() }
                                Text(message.body)
                                    .padding(8)
                                    .background(
                                        message.outgoing
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.secondary.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                if !message.outgoing { Spacer() }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    TextField("Message", text: $model.composeText)
                    Button("Send") { model.sendSms() }
                        .keyboardShortcut(.return)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
