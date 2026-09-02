import AVFoundation
import SwiftUI

struct MirrorSurfaceView: NSViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    let input: MirrorInputHandler?

    func makeNSView(context: Context) -> MirrorNSView {
        let view = MirrorNSView(displayLayer: displayLayer)
        view.input = input
        return view
    }

    func updateNSView(_ nsView: MirrorNSView, context: Context) {
        nsView.input = input
    }
}
