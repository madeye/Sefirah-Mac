import AVFoundation
import Foundation
@testable import SefirahCore
import XCTest

final class AudioDecoderTests: XCTestCase {
    /// Opus TOC 0xfc (CELT fullband 20 ms, stereo) + silence frame `ff fe` → 960 frames, minus the
    /// 120-frame pre-skip the converter may apply on the first packet.
    func testOpusSilenceDecodes() throws {
        let decoder = try AudioDecoder(codec: .opus, config: Hex.data("4f70757348656164 01 02 7800 80bb0000 0000 00"))
        let first = try decoder.decode(Hex.data("fcfffe"))
        XCTAssertTrue([0, 840, 960].contains(first.count / 2), "first packet frames: \(first.count / 2)")
        let second = try decoder.decode(Hex.data("fcfffe"))
        XCTAssertEqual(second.count / 2, 960)
        XCTAssertTrue(second.allSatisfy { abs($0) < 1e-3 })
        XCTAssertEqual(decoder.outputFormat.sampleRate, 48_000)
        XCTAssertTrue(decoder.outputFormat.isInterleaved)
    }

    func testAACConverterInitialisesWithConfig() throws {
        let decoder = try AudioDecoder(codec: .aac, config: Hex.data("1190"))
        XCTAssertEqual(decoder.codec, .aac)
        // An empty packet is ignored rather than crashing the converter.
        XCTAssertEqual(try decoder.decode(Data()).count, 0)
    }

    func testRawPassthrough() throws {
        let decoder = try AudioDecoder(codec: .raw, config: nil)
        var packet = Data(count: 4096)
        packet[0] = 0x00; packet[1] = 0x80          // L = -32768
        packet[2] = 0xff; packet[3] = 0x7f          // R = 32767
        let pcm = try decoder.decode(packet)
        XCTAssertEqual(pcm.count / 2, 1024)
        XCTAssertEqual(pcm[0], -1)
        XCTAssertEqual(pcm[1], 32767 / 32768, accuracy: 1e-6)
        XCTAssertThrowsError(try decoder.decode(Data(count: 6)))
    }

    func testUnsupportedCodecRejected() {
        XCTAssertThrowsError(try AudioDecoder(codec: .flac, config: nil))
    }
}

final class PCMRingBufferTests: XCTestCase {
    private func frames(_ n: Int, value: Float = 0.5) -> [Float] { [Float](repeating: value, count: n * 2) }

    func testPrimesAtHalfTargetThenRenders() {
        let ring = PCMRingBuffer(channels: 2, targetFrames: 100)
        var out = [Float](repeating: 9, count: 20)
        ring.push(frames(40))
        XCTAssertFalse(out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, frames: 10) }, "below target/2 → silence")
        XCTAssertTrue(out.allSatisfy { $0 == 0 })
        ring.push(frames(10))
        XCTAssertTrue(out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, frames: 10) })
        XCTAssertTrue(out.allSatisfy { $0 == 0.5 })
        XCTAssertEqual(ring.statistics.bufferedFrames, 40)
    }

    func testUnderrunOutputsSilenceAndReprimes() {
        let ring = PCMRingBuffer(channels: 2, targetFrames: 100)
        ring.push(frames(60))
        var out = [Float](repeating: 9, count: 200)
        XCTAssertFalse(out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, frames: 100) })
        XCTAssertEqual(ring.statistics.underruns, 1)
        XCTAssertEqual(ring.statistics.bufferedFrames, 0)
        ring.push(frames(20))
        XCTAssertFalse(out.withUnsafeMutableBufferPointer { ring.pop(into: $0.baseAddress!, frames: 10) }, "re-priming after underrun")
    }

    func testDropsBacklogAboveTwiceTarget() {
        let ring = PCMRingBuffer(channels: 2, targetFrames: 100)
        ring.push(frames(250))
        let stats = ring.statistics
        XCTAssertEqual(stats.bufferedFrames, 100)
        XCTAssertEqual(stats.droppedFrames, 150)
        XCTAssertEqual(stats.pushedFrames, 250)
    }
}

final class AudioPlayerTests: XCTestCase {
    func testRawPacketsFillTheBufferAndMuteDiscards() throws {
        let player = AudioPlayer(targetLatencyMs: 50, startEngine: false)
        player.configure(codec: .raw, config: nil)
        player.enqueue(packet: Data(count: 4096))
        var stats = player.statistics
        XCTAssertEqual(stats.codec, .raw)
        XCTAssertEqual(stats.packets, 1)
        XCTAssertEqual(stats.decodedFrames, 1024)
        XCTAssertEqual(stats.buffer.bufferedFrames, 1024)
        XCTAssertFalse(stats.engineRunning)

        player.isMuted = true
        player.enqueue(packet: Data(count: 4096))
        stats = player.statistics
        XCTAssertEqual(stats.packets, 2, "muted packets are still drained")
        XCTAssertEqual(stats.buffer.bufferedFrames, 0, "muted PCM is discarded")

        player.stop()
        XCTAssertEqual(player.statistics.packets, 0)
    }

    func testDecoderErrorIsReportedOnce() {
        let player = AudioPlayer(targetLatencyMs: 50, startEngine: false)
        let errors = Counter()
        player.onError = { _ in errors.increment() }
        player.configure(codec: .raw, config: nil)
        player.enqueue(packet: Data(count: 6))
        player.enqueue(packet: Data(count: 6))
        XCTAssertEqual(errors.value, 1)
        XCTAssertEqual(player.statistics.decodeErrors, 2)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func increment() { lock.withLock { n += 1 } }
    }
}
