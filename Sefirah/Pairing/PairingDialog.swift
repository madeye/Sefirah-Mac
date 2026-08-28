import SefirahCore
import SwiftUI

struct PairingDialog: View {
    let peer: DiscoveredPeer
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection request")
                .font(.title2.weight(.semibold))
            Text("\(peer.name) wants to pair with this Mac. Confirm the code matches on both devices.")
            Text(peer.verificationKey)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .frame(maxWidth: .infinity)
            HStack {
                Button("Decline", action: onDecline)
                Spacer()
                Button("Accept", action: onAccept)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
