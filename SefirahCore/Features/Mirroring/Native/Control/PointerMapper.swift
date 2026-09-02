import CoreGraphics
import Foundation

/// Maps AppKit view points (origin bottom-left, points) to video-frame pixels under aspect-fit letterboxing.
public struct PointerMapper: Sendable, Equatable {
    public let viewSize: CGSize
    public let videoSize: CGSize
    /// Where the video is drawn inside the view (top-left origin, points).
    public let videoRect: CGRect

    public init(viewSize: CGSize, videoSize: CGSize) {
        self.viewSize = viewSize
        self.videoSize = videoSize
        guard viewSize.width > 0, viewSize.height > 0, videoSize.width > 0, videoSize.height > 0 else {
            videoRect = .zero
            return
        }
        let scale = min(viewSize.width / videoSize.width, viewSize.height / videoSize.height)
        let w = videoSize.width * scale
        let h = videoSize.height * scale
        videoRect = CGRect(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2, width: w, height: h)
    }

    public var isValid: Bool { videoRect.width > 0 && videoRect.height > 0 }

    /// Frame pixel for a view point (y flipped); `nil` outside the video rect unless `clamp`.
    public func toFrame(_ point: CGPoint, clamp: Bool = false) -> (x: Int32, y: Int32)? {
        guard isValid else { return nil }
        let topLeft = CGPoint(x: point.x, y: viewSize.height - point.y)
        var rx = (topLeft.x - videoRect.minX) / videoRect.width
        var ry = (topLeft.y - videoRect.minY) / videoRect.height
        if clamp {
            rx = min(1, max(0, rx))
            ry = min(1, max(0, ry))
        } else if rx < 0 || rx > 1 || ry < 0 || ry > 1 {
            return nil
        }
        let fx = min(videoSize.width - 1, max(0, (rx * videoSize.width).rounded(.down)))
        let fy = min(videoSize.height - 1, max(0, (ry * videoSize.height).rounded(.down)))
        return (Int32(fx), Int32(fy))
    }

    /// Point reflected through the frame centre (virtual finger for pinch gestures).
    public static func mirrored(_ p: (x: Int32, y: Int32), in videoSize: CGSize) -> (x: Int32, y: Int32) {
        (Int32(videoSize.width) - 1 - p.x, Int32(videoSize.height) - 1 - p.y)
    }
}
