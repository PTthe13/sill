import CoreGraphics
import Foundation

/// Turns CPU and memory history into the depth series for each strand.
///
/// Envelope (outer strands) is CPU; fill (inner strands) is memory pressure.
public struct WaveModel: Sendable {
    public static let strandCount = 9
    /// Samples of lag between neighbouring strands.
    public static let lagPerStrand = 3

    public let thickness: CGFloat

    public init(thickness: CGFloat = WaveGeometry.thickness) {
        self.thickness = thickness
    }

    public static func isOuter(strand k: Int) -> Bool {
        k == 0 || k == strandCount - 1
    }

    /// +1 for the top envelope, 0 on the axis, -1 for the bottom envelope.
    public static func mix(strand k: Int) -> Double {
        1 - 2 * Double(k) / Double(strandCount - 1)
    }

    /// fill[i] = 0.16 + 0.84 * memory/100, clamped to a sane percentage.
    public static func fill(memoryPercent: Double) -> Double {
        0.16 + 0.84 * (clampPercent(memoryPercent) / 100)
    }

    public static func clampPercent(_ v: Double) -> Double {
        min(100, max(0, v))
    }

    /// Half-height of the envelope for a CPU percentage.
    public func amplitude(_ cpuPercent: Double) -> Double {
        (Self.clampPercent(cpuPercent) / 100) * Double(thickness / 2 - WaveGeometry.depthInset)
    }

    /// Depth of strand `k` at each sample index.
    /// `cpu` and `memory` are oldest-first and must be the same length.
    public func depths(strand k: Int, cpu: [Double], memory: [Double]) -> [Double] {
        precondition(cpu.count == memory.count, "cpu and memory histories must match")
        let mix = Self.mix(strand: k)
        let outer = Self.isOuter(strand: k)
        let lag = k * Self.lagPerStrand
        let mid = Double(thickness / 2)
        return cpu.indices.map { i in
            let lagged = cpu[max(0, i - lag)]
            let scale = outer ? 1 : Self.fill(memoryPercent: memory[i])
            return mid + amplitude(lagged) * mix * scale
        }
    }

    /// All nine strands, smoothing the inputs first as the brief requires.
    public func allDepths(cpu: [Double], memory: [Double]) -> [[Double]] {
        allDepths(smoothedCPU: Curve.smooth(cpu), smoothedMemory: Curve.smooth(memory))
    }

    /// The same, for a caller that has already smoothed the histories — the
    /// colour ramp needs the smoothed CPU too, and smoothing it twice a second
    /// is work nobody sees.
    public func allDepths(smoothedCPU: [Double], smoothedMemory: [Double]) -> [[Double]] {
        (0..<Self.strandCount).map {
            depths(strand: $0, cpu: smoothedCPU, memory: smoothedMemory)
        }
    }

    /// Everything the bands need for one frame, computed once.
    ///
    /// Strand depths depend only on the readings, not on where a band is, so
    /// with a band on every display this is calculated once and shared rather
    /// than four times over.
    public struct Frame: Sendable {
        public let cpu: [Double]
        public let memory: [Double]
        public let depths: [[Double]]
        public let loads: [Double]

        /// The nine strand paths for one band.
        ///
        /// Built here rather than in the app so the generic collection work
        /// specializes: across a module boundary Swift falls back to protocol
        /// witnesses for every point access, which showed up in a profile as
        /// the single hottest thing Sill does.
        public func paths(transform: EdgeTransform, sampleCount: Int) -> [CGPath] {
            depths.map { strand in
                let slice = strand.count > sampleCount ? strand.suffix(sampleCount)
                                                       : strand[strand.startIndex...]
                return Curve.path(depths: slice, transform: transform)
            }
        }

        public init(cpu: [Double], memory: [Double], thickness: CGFloat = WaveGeometry.thickness,
                    sliceCount: Int = Palette.profileSlices) {
            self.cpu = cpu
            self.memory = memory
            let smoothedCPU = Curve.smooth(cpu)
            self.depths = WaveModel(thickness: thickness)
                .allDepths(smoothedCPU: smoothedCPU, smoothedMemory: Curve.smooth(memory))
            self.loads = Palette.sliceValues(history: smoothedCPU, count: sliceCount)
        }
    }

    /// Stroke width for a strand, in points (never scaled by the layer).
    ///
    /// The brief sets these at 1.5 and 1.0. Widening the gap gives the band a
    /// clearer hierarchy: the two envelope strands are the CPU reading and
    /// carry the shape, while the seven inner ones are the memory fill and
    /// read as texture between them.
    public static let outerLineWidth: CGFloat = 2.2
    public static let innerLineWidth: CGFloat = 0.7

    public static func lineWidth(strand k: Int) -> CGFloat {
        isOuter(strand: k) ? outerLineWidth : innerLineWidth
    }

    /// A thinner stroke carries less ink, so the fill strands get a little
    /// more opacity to stay present without competing with the envelope.
    public static func opacity(strand k: Int) -> CGFloat {
        isOuter(strand: k) ? 0.88 : 0.52
    }
}
