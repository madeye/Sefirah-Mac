import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Sefirah")
                .font(.largeTitle.weight(.semibold))
            Text("Android companion for Mac")
                .foregroundStyle(.secondary)
            Text("Pairing, clipboard, and notifications are coming next.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

#Preview {
    ContentView()
}
