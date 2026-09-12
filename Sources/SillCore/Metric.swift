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

/// Turns a rate into a percentage of the band.
///
/// A throughput figure has no ceiling: 5 MB/s is enormous on hotel wifi and
/// nothing on a gigabit link. The scale therefore follows the machine — it
/// rises to whatever the fastest recent moment was, and decays back down so a
/// single huge transfer doesn't flatten the band for the rest of the day.
public struct RateScale: Sendable {
    /// The smallest full scale to use, so idle noise doesn't fill the band.
    public static let floor: Double = 2 * 1_048_576
    /// Decay of the remembered peak, per SECOND: about half over two minutes.
    ///
    /// Per second rather than per sample, because the sample interval is not
    /// fixed — a band set to an hour of history takes one reading every twenty
    /// seconds, and a per-sample decay would leave it scaled to a download that
    /// finished hours ago.
    public static let decay: Double = 0.994

    public private(set) var peak: Double

    public init(peak: Double = RateScale.floor) {
        self.peak = max(RateScale.floor, peak)
    }

    /// Records a reading and returns it as 0...100 of the current scale.
    ///
    /// `secondsSinceLast` is how long the reading covers, so the peak fades at
    /// the same rate in wall-clock time whatever the band's history span.
    public mutating func normalise(_ bytesPerSecond: Double,
                                   secondsSinceLast: Double = 1) -> Double {
        let value = max(0, bytesPerSecond)
        let elapsed = max(0, secondsSinceLast)
        let faded = peak * pow(RateScale.decay, elapsed)
        peak = max(RateScale.floor, max(value, faded))
        guard peak > 0 else { return 0 }
        return min(100, value / peak * 100)
    }

    /// What the full height of the band currently means, for the panel.
    public var fullScaleText: String {
        Format.throughput(bytesPerSecond: peak)
    }
}
