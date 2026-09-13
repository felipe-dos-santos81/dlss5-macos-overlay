import XCTest
@testable import ScreenCore

final class ScreenCoreTests: XCTestCase {
    func testPortraitAndUltrawideSizing() {
        XCTAssertEqual(FrameSize(3840, 2160).processing(longEdge: 512), FrameSize(512, 288))
        XCTAssertEqual(FrameSize(2160, 3840).processing(longEdge: 512), FrameSize(288, 512))
        XCTAssertEqual(FrameSize(3440, 1440).processing(longEdge: 640), FrameSize(640, 266))
        XCTAssertEqual(FrameSize(200, 100).processing(longEdge: 512), FrameSize(200, 100))
    }
    func testCorruptPreferencesDoNotReachGPU() {
        var settings = RenderSettings()
        settings.intensity = .nan; settings.split = .infinity
        settings.captureFPS = -10; settings.processingLongEdge = 100_000
        settings.profile = "unknown"; settings.sanitize()
        XCTAssertEqual(settings.intensity, 1); XCTAssertEqual(settings.split, 0)
        XCTAssertEqual(settings.captureFPS, 5); XCTAssertEqual(settings.processingLongEdge, 1920)
        XCTAssertEqual(settings.profile, "natural")
    }
    func testLatestFrameWinsWithoutQueueGrowth() async {
        let frames = LatestFrames<Int>()
        for i in 0..<1000 { frames.yield(i) }
        frames.finish()
        var received = [Int]()
        for await frame in frames.stream { received.append(frame) }
        XCTAssertEqual(received, [999]); XCTAssertEqual(frames.dropped, 999)
    }
    func testDisplayComparisonDoesNotResetTemporalHistory() {
        var settings = RenderSettings()
        let first = HistoryBoundary(size: FrameSize(512, 288), settings: settings)
        settings.split = 0.5
        XCTAssertEqual(first, HistoryBoundary(size: FrameSize(512, 288), settings: settings))
        settings.tone = 0.4
        XCTAssertNotEqual(first, HistoryBoundary(size: FrameSize(512, 288), settings: settings))
    }
}
