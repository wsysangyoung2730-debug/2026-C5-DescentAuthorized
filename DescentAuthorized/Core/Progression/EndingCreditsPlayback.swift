import Foundation

/// A scroll target driven by the latest measured position, including manual scrolling.
struct EndingCreditsPlayback: Equatable, Sendable {
    private(set) var offset: Double = 0
    private(set) var maximumOffset: Double = 0

    var isAtEnd: Bool {
        maximumOffset > 0 && offset >= maximumOffset
    }

    mutating func updateLayout(offset: Double, maximumOffset: Double) {
        // A transient invalid measurement must not reset a reader's position.
        guard offset.isFinite, maximumOffset.isFinite else { return }
        self.maximumOffset = max(0, maximumOffset)
        self.offset = min(max(0, offset), self.maximumOffset)
    }

    /// The caller suspends for interaction, overlays, backgrounding and accessibility.
    /// Elapsed time is bounded so a delayed frame cannot skip part of the credits.
    mutating func advance(elapsed: TimeInterval, isSuspended: Bool) -> Double? {
        guard !isSuspended, maximumOffset > 0, !isAtEnd,
              elapsed.isFinite, elapsed > 0 else { return nil }

        let distance = (maximumOffset / 90) * min(elapsed, 0.1)
        let target = min(maximumOffset, offset + distance)
        guard target.isFinite, target > offset else { return nil }
        offset = target
        return target
    }
}
