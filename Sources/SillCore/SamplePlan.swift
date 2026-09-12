import Foundation

/// Conditions that change how often — or whether — Sill samples.
public struct PowerState: Equatable, Sendable {
    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var occluded: Bool
    public var displayAsleep: Bool
    public var screenLocked: Bool

    public init(onBattery: Bool = false, lowPowerMode: Bool = false, occluded: Bool = false,
                displayAsleep: Bool = false, screenLocked: Bool = false) {
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.occluded = occluded
        self.displayAsleep = displayAsleep
        self.screenLocked = screenLocked
    }
}

/// How much history the band holds, as a duration the user picks rather than a
/// sampling rate they have to work out.
public enum Span {
    /// Automatic: the band holds whatever its length and the sample interval
    /// give it, which is how Sill behaved before this was a choice.
    public static let automatic: Double = 0
    public static let minimumMinutes: Double = 1
    public static let maximumMinutes: Double = 60
    /// Derived intervals are allowed to go slower than the manual slider: a
    /// long span on a short band means sampling rarely, which costs less.
    public static let slowestDerivedInterval: TimeInterval = 30

    /// The sampling interval that fills `samples` points with `minutes` of
    /// history. Clamped, so an impossible span simply gets as close as it can.
    public static func interval(minutes: Double, samples: Int,
                                fallback: TimeInterval) -> TimeInterval {
        guard minutes > 0, samples > 1 else { return fallback }
        let wanted = minutes * 60 / Double(samples - 1)
        return min(slowestDerivedInterval, max(SillSettings.minimumInterval, wanted))
    }

    /// What the band will actually show, once the interval has been clamped.
    public static func achievedMinutes(minutes: Double, samples: Int,
                                       fallback: TimeInterval) -> Double {
        let step = interval(minutes: minutes, samples: samples, fallback: fallback)
        return Double(max(0, samples - 1)) * step / 60
    }
}

/// Decides the sampling cadence. Nothing on screen means nothing to sample.
public enum SamplePlan {
    /// Timer slack, so the OS can coalesce our wakeups with others. Scales
    /// with the interval: a band showing an hour has no need of a wakeup
    /// accurate to a fifth of a second.
    public static func tolerance(for interval: TimeInterval) -> TimeInterval {
        max(0.2, interval * 0.05)
    }

    public static func isSuspended(_ state: PowerState) -> Bool {
        state.occluded || state.displayAsleep || state.screenLocked
    }

    /// nil means "stop the timer".
    public static func interval(preferred: TimeInterval, state: PowerState) -> TimeInterval? {
        guard !isSuspended(state) else { return nil }
        if state.lowPowerMode { return max(preferred * 4, 4) }
        if state.onBattery { return max(preferred * 2, 2) }
        return preferred
    }
}
