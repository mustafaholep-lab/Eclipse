import Foundation

/// Decides whether a position reported by mpv after the app returns from the background is real
/// playback or a symptom of a media session that did not survive suspension.
///
/// mpv runs with `keep-open=yes`. When the stream dies while the app is suspended (the stream
/// socket or the local header-proxy listener is torn down by iOS), mpv reports end-of-file on the
/// next read. If the video output holds no frame at that moment (the VideoToolbox decoder is
/// rebuilt on foreground), mpv's keep-open handling seeks to the last frame of the file. The
/// reported `time-pos` therefore leaps to the end without any user seek and without the content
/// having played. That position must not reach the UI, progress persistence, or next-episode
/// logic; the item has to be reloaded at the last position that was actually played.
struct PlaybackLifecycleRecoveryPolicy {
    /// Extra forward movement accepted on top of elapsed wall-clock time (decoder catch-up,
    /// timer coalescing, PiP/background audio rounding).
    static let advanceTolerance: TimeInterval = 12
    /// mpv's last-frame seek lands on the final frame; anything this close to the end counts.
    static let endWindow: TimeInterval = 10
    /// Smaller unexplained jumps are not treated as session loss.
    static let minimumUnexplainedJump: TimeInterval = 20
    /// How long after returning to the foreground playback must advance before recovery.
    static let foregroundStallThreshold: TimeInterval = 15
    /// Bounded reload attempts per lifecycle cycle so a dead source cannot loop.
    static let maximumRecoveryAttempts = 2

    struct Sample: Equatable {
        let position: Double
        let at: Date
    }

    enum Verdict: Equatable {
        case accept
        case spuriousEndOfFileJump(resumePosition: Double)
    }

    static func evaluate(
        position: Double,
        duration: Double,
        at now: Date,
        lastVerified: Sample,
        playbackSpeed: Double
    ) -> Verdict {
        guard position.isFinite,
              duration.isFinite,
              duration > endWindow,
              lastVerified.position.isFinite,
              lastVerified.position >= 0 else {
            return .accept
        }
        let elapsed = max(0, now.timeIntervalSince(lastVerified.at))
        let speed = playbackSpeed.isFinite ? max(1.0, playbackSpeed) : 1.0
        let plausibleMaximum = lastVerified.position + elapsed * speed + advanceTolerance
        let landsAtEnd = position >= duration - endWindow
        let unexplainedJump = position - plausibleMaximum
        guard landsAtEnd, unexplainedJump >= minimumUnexplainedJump else {
            return .accept
        }
        return .spuriousEndOfFileJump(resumePosition: min(lastVerified.position, duration))
    }

    static func isStalledAfterForeground(
        positionAtForeground: Double,
        currentPosition: Double,
        foregroundedAt: Date,
        now: Date,
        isPausedIntent: Bool
    ) -> Bool {
        guard !isPausedIntent,
              positionAtForeground.isFinite,
              currentPosition.isFinite else {
            return false
        }
        let elapsed = now.timeIntervalSince(foregroundedAt)
        return elapsed >= foregroundStallThreshold
            && currentPosition < positionAtForeground + 1.0
    }
}
