import SefirahCore
import SwiftUI

struct SyncView: View {
    @Bindable var model: AppModel
    var onSkip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(spacing: 12) {
                Text("Scan QR Code")
                    .font(.title2.weight(.semibold))
                Text("Open Sefirah on your phone and scan this code, or pick a discovered device.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let image = model.qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: 220, height: 220)
                        .overlay(Text("QR unavailable").foregroundStyle(.secondary))
                }
                if let port = model.serverPort {
                    Text("Listening on port \(port)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let error = model.sessionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("Available devices")
                    .font(.title2.weight(.semibold))
                if model.discovered.isEmpty {
                    Text("Waiting for devices on this network…")
                        .foregroundStyle(.secondary)
                }
                List(model.discovered) { peer in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(peer.name).font(.headline)
                            Text(peer.verificationKey)
                                .font(.system(.body, design: .monospaced))
                            Text("\(peer.address):\(peer.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { model.pair(peer) }
                    }
                }
                Button("Skip") { onSkip() }
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
