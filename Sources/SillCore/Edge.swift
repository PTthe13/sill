import CoreGraphics
import Foundation

/// Which screen edge the wave is pinned to.
public enum ScreenEdge: String, CaseIterable, Codable, Sendable {
    case left, right, top, bottom

    public var isVertical: Bool { self == .left || self == .right }

    /// Unit vector, in band-local coordinates, pointing from the oldest sample
    /// toward the newest one.
    public var timeDirection: CGVector {
        // Vertical edges: time flows down, newest at the bottom (y == 0).
        // Horizontal edges: newest at the left, content travels rightward.
        isVertical ? CGVector(dx: 0, dy: -1) : CGVector(dx: -1, dy: 0)
    }
}

/// Fixed geometry of the band. Values come straight from the brief (§2).
public enum WaveGeometry {
    /// Band thickness, pt. The brief says 52; at that depth a busy machine
    /// pins the envelope against the edges of the band and the difference
    /// between 80% and 100% stops being visible. More depth is more resolution.
    public static let thickness: CGFloat = 76
    /// Distance between two samples along the time axis, pt.
    public static let step: CGFloat = 4
    /// Fraction of the screen's long side the band spans, on every edge.
    /// User-adjustable; this is the default.
    public static let defaultLengthFraction: CGFloat = 0.4
    public static let minimumLengthFraction: CGFloat = 0.3
    public static let maximumLengthFraction: CGFloat = 1.0
    /// Padding kept clear at the top and bottom of the band, pt.
    public static let depthInset: CGFloat = 8

    /// Band size for an edge, given the length along the time axis.
    public static func size(edge: ScreenEdge, length: CGFloat) -> CGSize {
        edge.isVertical ? CGSize(width: thickness, height: length)
                        : CGSize(width: length, height: thickness)
    }

    /// Number of samples needed to cover `length`.
    public static func sampleCount(forLength length: CGFloat) -> Int {
        Int((length / step).rounded(.down)) + 1
    }
}

/// Maps (alongAxis, depth) pairs into band-local points for one edge.
///
/// `along` is measured from the oldest sample; `depth` is measured from the
/// screen edge inward, so depth 0 always sits against the bezel.
public struct EdgeTransform: Equatable, Sendable {
    public let edge: ScreenEdge
    public let length: CGFloat
    public let thickness: CGFloat

    public init(edge: ScreenEdge, length: CGFloat, thickness: CGFloat = WaveGeometry.thickness) {
        self.edge = edge
        self.length = length
        self.thickness = thickness
    }

    public var size: CGSize { WaveGeometry.size(edge: edge, length: length) }

    public func point(along: CGFloat, depth: CGFloat) -> CGPoint {
        switch edge {
        // Band-local y is up, so `length - along` puts the newest sample at the
        // top of a vertical band and the oldest at the bottom.
        case .left:   return CGPoint(x: depth, y: length - along)
        case .right:  return CGPoint(x: thickness - depth, y: length - along)
        // Horizontal: newest at the right, the way every chart is read.
        case .top:    return CGPoint(x: length - along, y: thickness - depth)
        case .bottom: return CGPoint(x: length - along, y: depth)
        }
    }

    /// Distance and direction the whole bundle travels over one sample interval.
    ///
    /// History moves AWAY from the end where new samples land, never toward it:
    /// down a vertical band (newest at the top) and leftward along a horizontal
    /// one (newest at the right). Getting this sign backwards makes the wave
    /// look like it is being extruded from the wrong end.
    public var scrollPerSample: CGVector {
        switch edge {
        case .left, .right: return CGVector(dx: 0, dy: -WaveGeometry.step)
        case .top, .bottom: return CGVector(dx: -WaveGeometry.step, dy: 0)
        }
    }

    /// Start/end of the colour and fade gradients, in band-local points,
    /// running from the newest sample to the oldest.
    public var gradientAxis: (start: CGPoint, end: CGPoint) {
        switch edge {
        case .left, .right:
            return (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: length))
        case .top, .bottom:
            return (CGPoint(x: 0, y: 0), CGPoint(x: length, y: 0))
        }
    }
}
