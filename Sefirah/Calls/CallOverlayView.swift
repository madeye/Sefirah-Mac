import SefirahCore
import SwiftUI

struct CallOverlayView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            if let call = model.incomingCall {
                Text("Incoming call").font(.headline)
                Text(call.contactInfo?.displayName ?? call.phoneNumber)
                    .font(.title2)
                HStack {
                    Button("Decline") { model.incomingCall = nil }
                        .tint(.red)
                    Button("Dismiss") { model.incomingCall = nil }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Text("No active call").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 320, height: 160)
    }
}
