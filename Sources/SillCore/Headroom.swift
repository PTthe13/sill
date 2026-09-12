import Foundation

public extension Double {
    /// Rounds to `Int` without trapping.
    ///
    /// Every number in a panel or a readout came from a sampler, and a sampler
    /// that divides by a zero-length interval produces a NaN. `Int(nan)` is a
    /// crash, so no measured value is converted without going through here.
    var roundedInt: Int {
        guard isFinite else { return 0 }
        return Int(min(max(rounded(), -9e15), 9e15))
    }
}

/// The plain-language line at the top of the detail band.
public enum Headroom {
    public static func value(cpuPercent: Double, memoryPercent: Double) -> Int {
        // Converting a NaN or an infinity to Int traps, and these come from
        // samplers: one division by a zero interval would take the app down
        // with it. Clamp to the range percentages are allowed to have.
        let cpu = percent(cpuPercent), memory = percent(memoryPercent)
        return (100 - (cpu * 0.55 + memory * 0.45)).roundedInt
    }

    private static func percent(_ value: Double) -> Double {
        value.isFinite ? min(100, max(0, value)) : 0
    }

    public static func word(forHeadroom headroom: Int) -> String {
        switch headroom {
        case 56...: return "Plenty of room"
        case 31...55: return "Comfortable"
        case 16...30: return "Getting tight"
        default: return "Something is eating the machine"
        }
    }

    /// The headline: the judgement, on its own line, in the panel's largest
    /// text. "Comfortable · 54 headroom".
    public static func title(cpuPercent: Double, memoryPercent: Double) -> String {
        let free = value(cpuPercent: cpuPercent, memoryPercent: memoryPercent)
        return "\(word(forHeadroom: free)) · \(free) headroom"
    }

    /// The second line: what the wave is drawing, which is reference rather
    /// than headline, and is set accordingly.
    public static func encoding(envelope: Metric = .cpu, fill: Metric = .memory,
                                envelopeValue: Double, fillValue: Double,
                                fullScale: String? = nil) -> String {
        var line = "envelope \(envelopeValue.roundedInt)% \(envelope.shortName) · "
                 + "fill \(fillValue.roundedInt)% \(fill.shortName)"
        if let fullScale { line += " · full band \(fullScale)" }
        return line
    }

    public static func summary(cpuPercent: Double, memoryPercent: Double,
                               envelope: Metric = .cpu, fill: Metric = .memory,
                               envelopeValue: Double? = nil,
                               fillValue: Double? = nil) -> String {
        let free = value(cpuPercent: cpuPercent, memoryPercent: memoryPercent)
        let envelopeReading = envelopeValue ?? cpuPercent
        let fillReading = fillValue ?? memoryPercent
        return "\(word(forHeadroom: free)) · \(free) headroom · "
             + "envelope \(envelopeReading.roundedInt)% \(envelope.shortName) · "
             + "fill \(fillReading.roundedInt)% \(fill.shortName)"
    }
}

public enum Format {
    public static func bytes(_ value: Int64) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var v = Double(value), i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return v >= 100 || i == 0 ? "\(v.roundedInt)\(units[i])"
                                  : String(format: "%.1f%@", v, units[i])
    }

    public static func throughput(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "0.0 MB/s" }
        return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
    }

    /// Compact rate for a tile: "2.4", "12", "0.0" — the unit lives in the
    /// label, so two directions fit side by side.
    public static func rate(bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "0.0" }
        let megabytes = max(0, bytesPerSecond) / 1_048_576
        if megabytes >= 100 { return "\(megabytes.roundedInt)" }
        if megabytes >= 10 { return String(format: "%.0f", megabytes) }
        return String(format: "%.1f", megabytes)
    }
}
