import XCTest
@testable import Eclipse

final class PlaybackLifecycleRecoveryPolicyTests: XCTestCase {
    private typealias Policy = PlaybackLifecycleRecoveryPolicy
    private let start = Date(timeIntervalSince1970: 1_000)
    private let duration = 2_640.0

    private func verdict(
        position: Double,
        verified: Double,
        elapsed: TimeInterval,
        speed: Double = 1.0
    ) -> Policy.Verdict {
        Policy.evaluate(
            position: position,
            duration: duration,
            at: start.addingTimeInterval(elapsed),
            lastVerified: .init(position: verified, at: start),
            playbackSpeed: speed
        )
    }

    // Short or long lock mid-content, mpv keep-open seeks to the last frame after the stream died.
    func testUnrequestedJumpToEndAfterLockIsRejectedAndKeepsVerifiedPosition() {
        XCTAssertEqual(
            verdict(position: duration - 0.04, verified: 1_200, elapsed: 8),
            .spuriousEndOfFileJump(resumePosition: 1_200)
        )
        XCTAssertEqual(
            verdict(position: duration, verified: 1_200, elapsed: 2),
            .spuriousEndOfFileJump(resumePosition: 1_200)
        )
    }

    // Normal playback after returning (playing or resumed from pause) is accepted.
    func testOrdinaryPlaybackAfterForegroundIsAccepted() {
        XCTAssertEqual(verdict(position: 1_200.5, verified: 1_200, elapsed: 0.5), .accept)
        XCTAssertEqual(verdict(position: 1_230, verified: 1_200, elapsed: 30), .accept)
        // Paused: position does not move at all.
        XCTAssertEqual(verdict(position: 1_200, verified: 1_200, elapsed: 600), .accept)
    }

    // Background playback that really ran (PiP or background audio) advances with wall time.
    func testRealBackgroundPlaybackIntoTheEndIsAccepted() {
        XCTAssertEqual(verdict(position: duration - 2, verified: duration - 300, elapsed: 298), .accept)
        XCTAssertEqual(verdict(position: duration - 1, verified: duration - 590, elapsed: 295, speed: 2), .accept)
    }

    // Reaching the genuine end of content from nearby is natural playback, not a jump.
    func testGenuineEndOfContentIsAccepted() {
        XCTAssertEqual(verdict(position: duration, verified: duration - 5, elapsed: 5), .accept)
        XCTAssertEqual(verdict(position: duration - 1, verified: duration - 25, elapsed: 0.5), .accept)
    }

    // A forward jump that does not land at the end is not the keep-open signature.
    func testLargeJumpThatDoesNotLandAtEndIsAccepted() {
        XCTAssertEqual(verdict(position: 2_000, verified: 1_200, elapsed: 1), .accept)
    }

    func testInvalidInputsAreAccepted() {
        XCTAssertEqual(
            Policy.evaluate(position: .nan, duration: duration, at: start,
                            lastVerified: .init(position: 10, at: start), playbackSpeed: 1),
            .accept
        )
        XCTAssertEqual(
            Policy.evaluate(position: 9, duration: 0, at: start,
                            lastVerified: .init(position: 1, at: start), playbackSpeed: 1),
            .accept
        )
        XCTAssertEqual(verdict(position: duration, verified: 1_200, elapsed: 2, speed: .nan),
                       .spuriousEndOfFileJump(resumePosition: 1_200))
    }

    func testForegroundStallRequiresPlayingIntentAndNoProgress() {
        let foreground = start
        XCTAssertTrue(Policy.isStalledAfterForeground(
            positionAtForeground: 1_200, currentPosition: 1_200.3,
            foregroundedAt: foreground, now: foreground.addingTimeInterval(16), isPausedIntent: false))
        // User kept it paused: never treated as a stall.
        XCTAssertFalse(Policy.isStalledAfterForeground(
            positionAtForeground: 1_200, currentPosition: 1_200,
            foregroundedAt: foreground, now: foreground.addingTimeInterval(600), isPausedIntent: true))
        // Playback advanced.
        XCTAssertFalse(Policy.isStalledAfterForeground(
            positionAtForeground: 1_200, currentPosition: 1_214,
            foregroundedAt: foreground, now: foreground.addingTimeInterval(16), isPausedIntent: false))
        // Too early to judge (normal re-buffering after resume).
        XCTAssertFalse(Policy.isStalledAfterForeground(
            positionAtForeground: 1_200, currentPosition: 1_200,
            foregroundedAt: foreground, now: foreground.addingTimeInterval(5), isPausedIntent: false))
    }
}
