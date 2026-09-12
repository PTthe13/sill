import CoreGraphics
import Foundation

/// Reading a point in the band's history.
///
/// The wave is already a record of the last several minutes; scrubbing turns
/// that from decoration into something you can interrogate — what was the
/// machine doing when that spike happened, and how long ago was it.
public enum Scrub {
    /// Index into an oldest-first history for a position along the band,
    /// where 0 is the oldest end of the BAND and 1 the newest.
    ///
    /// `visible` is how many samples that band actually shows — a short display
    /// holds less history than a long one, and the pointer has to read the
    /// sample under it rather than one from a stretch that band never drew.
    public static func index(alongFraction fraction: CGFloat, count: Int,
                             visible: Int? = nil) -> Int {
        guard count > 0 else { return 0 }
        let shown = min(count, max(1, visible ?? count))
        let clamped = min(1, max(0, Double(fraction)))
        let fromOldestShown = Int((clamped * Double(shown - 1)).rounded())
        return min(count - 1, max(0, count - shown + fromOldestShown))
    }

    /// How long ago the sample at `index` was taken.
    public static func age(index: Int, count: Int, interval: TimeInterval) -> TimeInterval {
        guard count > 1 else { return 0 }
        return Double((count - 1) - min(count - 1, max(0, index))) * interval
    }

    /// "now", "20s ago", "4m ago", "1h 05m ago" — short enough for a chip.
    public static func ageText(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds.rounded())
        if value < 5 { return "now" }
        if value < 60 { return "\(Int(value))s ago" }
        let minutes = Int((value / 60).rounded(.down))
        if minutes < 60 { return "\(minutes)m ago" }
        return String(format: "%dh %02dm ago", minutes / 60, minutes % 60)
    }

    /// The chip's one line, naming whatever the wave is actually drawing —
    /// "62% network · 58% memory · 3m ago" when that is what is on screen.
    public static func label(envelope: Double, fill: Double, secondsAgo: TimeInterval,
                             envelopeMetric: Metric = .cpu,
                             fillMetric: Metric = .memory) -> String {
        "\(Int(envelope.rounded()))% \(envelopeMetric.shortName) · "
            + "\(Int(fill.rounded()))% \(fillMetric.shortName) · "
            + ageText(secondsAgo)
    }

    /// How much history the whole band holds, for the panel's summary line.
    public static func spanText(sampleCount: Int, interval: TimeInterval) -> String {
        let seconds = Double(max(0, sampleCount - 1)) * interval
        if seconds < 90 { return "\(Int(seconds.rounded()))s" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
