import Foundation
import SillCore

/// Everything the detail band shows. Updated once per sample while open.
final class PanelModel: ObservableObject {
    /// Fixed number of process rows, so the panel keeps a stable height.
    static let processRowCount = 4

    @Published var cpuPercent: Double = 0
    @Published var memoryPercent: Double = 0
    @Published var memoryUsedBytes: UInt64 = 0
    @Published var diskFreeBytes: Int64?
    @Published var processes: [ProcessUsage] = []
    @Published var gpuPercent: Double?
    @Published var batteryMinutesRemaining: Int?
    @Published var batteryPercent: Int?
    @Published var isCharging = false
    @Published var network = Throughput.zero
    @Published var diskIO = Throughput.zero
    /// How much history the band on screen holds, e.g. "16m".
    @Published var historySpan: String?
    @Published var ramp: ColorRamp = .load
    @Published var material: PanelMaterial = .tinted
    @Published var reduceTransparency = false
    @Published var isHorizontal = false
    @Published var envelopeMetric: Metric = .cpu
    @Published var fillMetric: Metric = .memory
    @Published var envelopeValue: Double = 0
    @Published var fillValue: Double = 0
    /// What full height means when the wave is drawing a rate.
    @Published var fullScaleNote: String?

    var headroomTitle: String {
        Headroom.title(cpuPercent: cpuPercent, memoryPercent: memoryPercent)
    }

    var encodingLine: String {
        Headroom.encoding(envelope: envelopeMetric, fill: fillMetric,
                          envelopeValue: envelopeValue, fillValue: fillValue,
                          fullScale: fullScaleNote)
    }

    var headroomLine: String {
        var line = Headroom.summary(cpuPercent: cpuPercent, memoryPercent: memoryPercent,
                                    envelope: envelopeMetric, fill: fillMetric,
                                    envelopeValue: envelopeValue, fillValue: fillValue)
        // A rate has no natural ceiling, so say what the band's full height means.
        if let fullScaleNote { line += " · full band \(fullScaleNote)" }
        return line
    }

    var memoryText: String { Format.bytes(Int64(memoryUsedBytes)) }
    var diskText: String { diskFreeBytes.map(Format.bytes) ?? "—" }
    var networkDown: String { Format.rate(bytesPerSecond: network.down) }
    var networkUp: String { Format.rate(bytesPerSecond: network.up) }
    var diskRead: String { Format.rate(bytesPerSecond: diskIO.down) }
    var diskWrite: String { Format.rate(bytesPerSecond: diskIO.up) }
    var spanText: String? { historySpan.map { "\($0) shown" } }

    var gpuText: String { gpuPercent.map { "\($0.roundedInt)%" } ?? "—" }

    var batteryText: String? {
        guard let batteryPercent else { return nil }
        var text = "Battery \(batteryPercent)%"
        if let minutes = batteryMinutesRemaining {
            let time = minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60)
                                     : "\(minutes)m"
            text += isCharging ? " · \(time) to full" : " · \(time) left"
        } else if isCharging {
            text += " charging"
        }
        return text
    }
}
