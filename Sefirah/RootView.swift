import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var showWelcomeContinue = false

    var body: some View {
        Group {
            if !model.hasCompletedOnboarding {
                if showWelcomeContinue {
                    SyncView(model: model, onSkip: { model.completeOnboarding() })
                } else {
                    WelcomeView { showWelcomeContinue = true }
                }
            } else {
                MainSplitView(model: model)
            }
        }
        .sheet(item: Binding(
            get: { model.pendingPairing },
            set: { if $0 == nil { model.declinePendingPair() } }
        )) { peer in
            PairingDialog(
                peer: peer,
                onAccept: { model.acceptPendingPair() },
                onDecline: { model.declinePendingPair() }
            )
        }
        .alert(item: $model.toolFailure) { failure in
            Alert(
                title: Text(failure.title),
                message: Text(failure.detail.map { "\(failure.message)\n\n\($0)" } ?? failure.message)
            )
        }
        .onChange(of: model.incomingCall) { _, call in
            if call != nil {
                openWindow(id: "call")
            }
        }
    }
}
