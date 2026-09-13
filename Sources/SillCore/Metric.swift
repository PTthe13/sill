import CoreGraphics
import Foundation

/// What a band is allowed to encode.
///
/// The wave shows two readings: the envelope (its shape) and the fill (its
/// density). Which two is the user's choice — a download should be visible to
/// someone who cares about downloads, and it was not while the shape was
/// hard-wired to CPU.
public enum Metric: String, CaseIterable, Codable, Sendable {
    case cpu, memory, gpu, network, disk

    public var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .disk: return "Disk"
        }
    }

    /// The word used in the panel's summary line.
    public var shortName: String { rawValue }

    /// True for readings that are a rate, not a percentage: those have no
    /// natural full scale and need one derived from what the machine does.
    public var isRate: Bool { self == .network || self == .disk }

    /// Rates are only read while something needs them, so a band using one
    /// costs a little more than a band on CPU and memory alone.
    public var needsRateSampling: Bool { isRate }
}

/// Scales a window of raw rate readings to the height of the band.
///
/// Rates used to be turned into percentages as they were sampled, against a
/// remembered peak that decayed. Two things were wrong with that. The scale
/// drifted, so identical traffic drew a different height depending on when it
/// happened — and because a new maximum is by definition 100%, ordinary
/// background chatter kept redefining full height and slamming the envelope to
/// the top. Scaling the whole visible window at once instead means the band
/// always reads "the biggest burst on screen is full height", every sample on
/// it is drawn to the same scale, and a quiet stretch stays quiet.
public enum RateWindow {
    /// The smallest full scale to use, so idle noise doesn't fill the band.
    public static let floor: Double = 2 * 1_048_576

    /// The steps full height is allowed to take, in megabytes a second.
    ///
    /// Snapping to these is what keeps the picture still: scaling to the exact
    /// maximum would redraw every strand a little differently each time the
    /// busiest moment on the band changed by a few kilobytes.
    private static let steps: [Double] = [2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]

    /// What full height means for this window of readings, in bytes a second.
    public static func scale(for values: [Double]) -> Double {
        let peak = max(floor, values.filter(\.isFinite).max() ?? 0)
        let megabytes = peak / 1_048_576
        let step = steps.first { megabytes <= $0 } ?? (megabytes / 1000).rounded(.up) * 1000
        return step * 1_048_576
    }

    /// The window as 0...100 of its own scale.
    public static func normalised(_ values: [Double]) -> [Double] {
        let full = scale(for: values)
        return values.map { value in
            guard value.isFinite, value > 0 else { return 0 }
            return min(100, value / full * 100)
        }
    }
}

