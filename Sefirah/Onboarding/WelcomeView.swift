import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "iphone")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Sefirah")
                .font(.largeTitle.weight(.semibold))
            Text("Connect your Android phone to share clipboard, notifications, messages, and more.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button("Get Started", action: onContinue)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
