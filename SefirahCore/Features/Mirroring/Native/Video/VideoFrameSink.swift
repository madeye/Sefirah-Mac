import AVFoundation
import CoreMedia
import Foundation

/// Receives decoded-ready samples from the video task. Methods are synchronous and called from
/// that task only; implementations must be thread-safe internally.
public protocol VideoFrameSink: AnyObject, Sendable {
    func formatChanged(_ format: CMFormatDescription, width: Int, height: Int)
    /// Returns false when the sample was dropped: the caller must then wait for (and request) a
    /// keyframe, because every later inter frame references the missing one.
    @discardableResult
    func enqueue(_ sample: CMSampleBuffer, keyFrame: Bool) -> Bool
    /// The renderer needs a flush (and a fresh keyframe) before it decodes again.
    var requiresFlush: Bool { get }
    /// Non-nil once the renderer failed permanently.
    var failure: String? { get }
    func flush()
}

/// Feeds an `AVSampleBufferDisplayLayer` through its thread-safe `AVSampleBufferVideoRenderer`.
public final class DisplayLayerSink: VideoFrameSink, @unchecked Sendable {
    private let renderer: AVSampleBufferVideoRenderer
    private let lock = NSLock()
    private var enqueued = 0
    private var dropped = 0

    public init(renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
    }

    public var counters: (enqueued: Int, dropped: Int) {
        lock.lock(); defer { lock.unlock() }
        return (enqueued, dropped)
    }

    public func formatChanged(_ format: CMFormatDescription, width: Int, height: Int) {
        renderer.flush()
    }

    @discardableResult
    public func enqueue(_ sample: CMSampleBuffer, keyFrame: Bool) -> Bool {
        // `isReadyForMoreMediaData` goes false while the layer is not draining (window minimized /
        // occluded). Dropping an inter frame breaks the reference chain, so the drop is reported and
        // the video loop resyncs on the next keyframe (requesting one via `resetVideo`).
        if !renderer.isReadyForMoreMediaData, !keyFrame {
            lock.lock(); dropped += 1; lock.unlock()
            return false
        }
        renderer.enqueue(sample)
        lock.lock(); enqueued += 1; lock.unlock()
        return true
    }

    public var requiresFlush: Bool { renderer.requiresFlushToResumeDecoding }

    public var failure: String? {
        renderer.status == .failed ? (renderer.error?.localizedDescription ?? "renderer failed") : nil
    }

    public func flush() {
        renderer.flush()
    }
}
