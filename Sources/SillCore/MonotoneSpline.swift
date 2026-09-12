import CoreGraphics
import Foundation

/// Monotone cubic interpolation (Fritsch–Carlson) and the smoothing filter
/// applied to sample series before interpolation.
public enum Curve {
    /// How many times the smoothing kernel runs. The brief specifies one pass;
    /// two gives the band a calmer line without losing the shape of a spike,
    /// which is what it is for.
    public static let smoothingPasses = 2

    /// Weighted moving average: (a + 2v + b) / 4, clamped at the ends.
    public static func smooth(_ values: [Double], passes: Int = smoothingPasses) -> [Double] {
        var result = values
        for _ in 0..<max(1, passes) {
            guard result.count > 2 else { return result }
            result = result.indices.map { i in
                let a = i > 0 ? result[i - 1] : result[i]
                let b = i < result.count - 1 ? result[i + 1] : result[i]
                return (a + 2 * result[i] + b) / 4
            }
        }
        return result
    }

    /// Fritsch–Carlson tangents for uniformly spaced samples.
    /// Guarantees the interpolant never overshoots the input range.
    @inlinable
    public static func tangents<C: RandomAccessCollection>(_ values: C, step: Double) -> [Double]
    where C.Element == Double, C.Index == Int {
        let n = values.count
        guard n > 1 else { return [0] }
        let base = values.startIndex
        var secant = [Double](repeating: 0, count: n - 1)
        for i in 0..<(n - 1) {
            secant[i] = (values[base + i + 1] - values[base + i]) / step
        }
        guard n > 2 else { return [secant[0], secant[0]] }

        var m = [Double](repeating: 0, count: n)
        m[0] = secant[0]
        m[n - 1] = secant[n - 2]
        for i in 1..<(n - 1) {
            let s0 = secant[i - 1], s1 = secant[i]
            if s0 * s1 <= 0 {
                m[i] = 0
            } else {
                // Uniform spacing reduces the weighted harmonic mean to w1 == w2.
                let w1 = 3 * step, w2 = 3 * step
                m[i] = (w1 + w2) / (w1 / s0 + w2 / s1)
            }
        }
        return m
    }

    /// A closed path between two strands, for filling the area between them.
    ///
    /// Built from the same monotone curve as the strokes — forward along one,
    /// back along the other — so the fill's edge sits exactly under the line
    /// rather than near it.
    @inlinable
    public static func areaPath<C: RandomAccessCollection>(top: C, bottom: C,
                                                           transform: EdgeTransform,
                                                           step: CGFloat = WaveGeometry.step)
        -> CGPath where C.Element == Double, C.Index == Int {
        let path = CGMutablePath()
        let count = top.count
        guard count > 1, bottom.count == count else { return path }
        let topTangents = tangents(top, step: Double(step))
        let bottomTangents = tangents(bottom, step: Double(step))
        let topBase = top.startIndex, bottomBase = bottom.startIndex
        let third = step / 3

        path.move(to: transform.point(along: 0, depth: CGFloat(top[topBase])))
        for i in 1..<count {
            let a0 = CGFloat(i - 1) * step, a1 = CGFloat(i) * step
            let previous = top[topBase + i - 1], current = top[topBase + i]
            path.addCurve(
                to: transform.point(along: a1, depth: CGFloat(current)),
                control1: transform.point(along: a0 + third,
                                          depth: CGFloat(previous + topTangents[i - 1] * Double(third))),
                control2: transform.point(along: a1 - third,
                                          depth: CGFloat(current - topTangents[i] * Double(third))))
        }

        let lastAlong = CGFloat(count - 1) * step
        path.addLine(to: transform.point(along: lastAlong,
                                         depth: CGFloat(bottom[bottomBase + count - 1])))

        for i in stride(from: count - 1, to: 0, by: -1) {
            let a0 = CGFloat(i - 1) * step, a1 = CGFloat(i) * step
            let current = bottom[bottomBase + i], previous = bottom[bottomBase + i - 1]
            path.addCurve(
                to: transform.point(along: a0, depth: CGFloat(previous)),
                control1: transform.point(along: a1 - third,
                                          depth: CGFloat(current - bottomTangents[i] * Double(third))),
                control2: transform.point(along: a0 + third,
                                          depth: CGFloat(previous + bottomTangents[i - 1] * Double(third))))
        }
        path.closeSubpath()
        return path
    }

    /// Evaluates the monotone cubic through `values` at fractional index `t`.
    public static func value(_ values: [Double], at t: Double, step: Double = 1) -> Double {
        guard let first = values.first else { return 0 }
        guard values.count > 1 else { return first }
        let clamped = min(Double(values.count - 1), max(0, t))
        let i = min(values.count - 2, Int(clamped.rounded(.down)))
        let m = tangents(values, step: step)
        let h = clamped - Double(i)
        let h2 = h * h, h3 = h2 * h
        let p0 = values[i], p1 = values[i + 1]
        let m0 = m[i] * step, m1 = m[i + 1] * step
        return (2 * h3 - 3 * h2 + 1) * p0 + (h3 - 2 * h2 + h) * m0
             + (-2 * h3 + 3 * h2) * p1 + (h3 - h2) * m1
    }

    /// Builds a monotone cubic path through `depths`, laid out along the time
    /// axis at `step` intervals and mapped into band-local space.
    ///
    /// Takes a collection so a band can draw a slice of a longer shared history
    /// — a band on a small display has no use for samples that fall off its end.
    @inlinable
    /// `alongOffset` shifts the whole curve down the band. A band with less
    /// history than it has room for uses it to keep its newest sample at the
    /// newest end, leaving the gap at the old end where the missing time
    /// actually belongs.
    public static func path<C: RandomAccessCollection>(depths: C, transform: EdgeTransform,
                                                       step: CGFloat = WaveGeometry.step,
                                                       alongOffset: CGFloat = 0) -> CGPath
    where C.Element == Double, C.Index == Int {
        let path = CGMutablePath()
        guard let firstDepth = depths.first else { return path }
        let m = tangents(depths, step: Double(step))
        path.move(to: transform.point(along: alongOffset, depth: CGFloat(firstDepth)))
        guard depths.count > 1 else { return path }

        let base = depths.startIndex
        for i in 1..<depths.count {
            let a0 = alongOffset + CGFloat(i - 1) * step, a1 = alongOffset + CGFloat(i) * step
            let third = step / 3
            let previous = depths[base + i - 1], current = depths[base + i]
            let c1 = transform.point(along: a0 + third,
                                     depth: CGFloat(previous + m[i - 1] * Double(third)))
            let c2 = transform.point(along: a1 - third,
                                     depth: CGFloat(current - m[i] * Double(third)))
            let p = transform.point(along: a1, depth: CGFloat(current))
            path.addCurve(to: p, control1: c1, control2: c2)
        }
        return path
    }
}
