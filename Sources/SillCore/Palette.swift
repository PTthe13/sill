import CoreGraphics
import Foundation

/// How the wave is drawn against a particular backdrop.
///
/// Thin pastel strands vanish on a light wallpaper. Rather than add a glow or a
/// plate behind the band — both of which the brief rules out, and both of which
/// look like a widget — the strands themselves get darker, denser and slightly
/// heavier as the backdrop gets lighter.
public struct WaveStyle: Equatable, Sendable {
    public var stops: [RampStop]
    public var outerOpacity: CGFloat
    public var innerOpacity: CGFloat
    public var outerWidth: CGFloat
    public var innerWidth: CGFloat
    /// Opacity at the oldest end of the band.
    public var fadeFloor: CGFloat
    /// A hairline drawn under each strand in the backdrop's opposite tone.
    /// Not a glow — no blur, no spread beyond a point and a half — but it is
    /// what keeps the wave readable over a wallpaper that is light in one place
    /// and dark in the next.
    public var haloColor: RampStop
    public var haloOuterAlpha: CGFloat
    public var haloInnerAlpha: CGFloat
    public var haloWidthBoost: CGFloat

    public func haloWidth(strand k: Int) -> CGFloat {
        lineWidth(strand: k) + haloWidthBoost
    }

    public func haloAlpha(strand k: Int) -> CGFloat {
        WaveModel.isOuter(strand: k) ? haloOuterAlpha : haloInnerAlpha
    }

    public func opacity(strand k: Int) -> CGFloat {
        WaveModel.isOuter(strand: k) ? outerOpacity : innerOpacity
    }

    public func lineWidth(strand k: Int) -> CGFloat {
        WaveModel.isOuter(strand: k) ? outerWidth : innerWidth
    }
}

public enum Palette {
    /// Backdrop luminance assumed when the wallpaper can't be read. Dark, so an
    /// unreadable wallpaper keeps the original look rather than inverting it.
    public static let assumedLuminance: Double = 0.25

    /// 0 on a dark backdrop, 1 on a light one, with a smooth transition across
    /// the middle so a wallpaper that drifts in luminance doesn't flicker.
    public static func lightness(backdropLuminance: Double) -> Double {
        let lower = 0.34, upper = 0.68
        let t = min(1, max(0, (backdropLuminance - lower) / (upper - lower)))
        return t * t * (3 - 2 * t)
    }

    /// How mixed the backdrop is, 0 (flat) to 1 (light and dark in the same
    /// band). A photograph needs more help than a plain colour.
    public static func variation(standardDeviation: Double) -> Double {
        min(1, max(0, standardDeviation / 0.22))
    }

    public static func style(ramp: ColorRamp, backdropLuminance: Double,
                             backdropVariation: Double = 0) -> WaveStyle {
        let t = CGFloat(lightness(backdropLuminance: backdropLuminance))
        let v = CGFloat(min(1, max(0, backdropVariation)))
        // White under dark strands on a light wallpaper, near-black under bright
        // strands on a dark one; on a mixed wallpaper both halves get help.
        let halo = blend(RampStop(0.04, 0.05, 0.06), RampStop(1, 1, 1), t)
        return WaveStyle(stops: stops(ramp: ramp, lightness: t),
                         outerOpacity: 0.88 + 0.10 * t,
                         innerOpacity: 0.52 + 0.20 * t,
                         outerWidth: WaveModel.outerLineWidth + 0.4 * t,
                         innerWidth: WaveModel.innerLineWidth + 0.15 * t,
                         fadeFloor: 0.30 + 0.18 * t,
                         haloColor: halo,
                         haloOuterAlpha: 0.26 + 0.30 * v,
                         haloInnerAlpha: 0.16 + 0.24 * v,
                         haloWidthBoost: 1.4 + 0.5 * v)
    }

    /// Crossfades from the ramp's dark-backdrop stops to its light-backdrop
    /// ones as the wallpaper gets lighter.
    public static func stops(ramp: ColorRamp, lightness t: CGFloat) -> [RampStop] {
        guard t > 0 else { return ramp.stops }
        let light = ramp.lightBackdropStops
        return zip(ramp.stops, light).map { blend($0, $1, t) }
    }

    static func blend(_ a: RampStop, _ b: RampStop, _ t: CGFloat) -> RampStop {
        let f = Double(min(1, max(0, t)))
        if f <= 0 { return a }
        if f >= 1 { return b }
        return RampStop(a.red + (b.red - a.red) * f,
                        a.green + (b.green - a.green) * f,
                        a.blue + (b.blue - a.blue) * f,
                        alpha: a.alpha + (b.alpha - a.alpha) * f)
    }

    /// Number of slices the band is measured in, along the time axis.
    public static let profileSlices = 24

    /// Interpolates a three-stop ramp at `t` (0 = idle, 1 = heavy).
    static func rampColor(_ stops: [RampStop], at t: Double) -> RampStop {
        guard stops.count == 3 else { return stops.first ?? RampStop(1, 1, 1) }
        let clamped = min(1, max(0, t))
        return clamped <= 0.5
            ? blend(stops[0], stops[1], CGFloat(clamped * 2))
            : blend(stops[1], stops[2], CGFloat((clamped - 0.5) * 2))
    }

    /// Where a CPU percentage sits on the ramp, using the same thresholds the
    /// discrete picks use: idle up to 45%, mid to 78%, heavy beyond.
    public static func rampPosition(forLoad percent: Double) -> Double {
        let load = min(100, max(0, percent))
        if load <= ColorRamp.midThreshold {
            return 0.5 * load / ColorRamp.midThreshold
        }
        if load <= ColorRamp.heavyThreshold {
            return 0.5 + 0.5 * (load - ColorRamp.midThreshold)
                / (ColorRamp.heavyThreshold - ColorRamp.midThreshold)
        }
        return 1
    }

    /// Colour for one slice: the ramp read at that slice's LOAD, then toned for
    /// the wallpaper under it.
    public static func color(ramp: ColorRamp, load: Double, backdropLuminance: Double) -> RampStop {
        let t = rampPosition(forLoad: load)
        return blend(rampColor(ramp.stops, at: t),
                     rampColor(ramp.lightBackdropStops, at: t),
                     CGFloat(lightness(backdropLuminance: backdropLuminance)))
    }

    /// Colour stops along the band, one per slice.
    ///
    /// Two things vary along the band and neither is position for its own sake:
    /// the ramp is read at the LOAD recorded in that slice — green where the
    /// machine was idle, red where it was pinned, whenever that was — and the
    /// result is toned for the wallpaper under that slice, so the same wave
    /// darkens over a bright patch of desktop and lightens over a dark one.
    ///
    /// `loads` and `profile` both run newest end to oldest.
    public static func gradientStops(ramp: ColorRamp, loads: [Double],
                                     profile: [Double]) -> [RampStop] {
        let tones = profile.isEmpty ? [assumedLuminance] : profile
        guard !loads.isEmpty else {
            return tones.map { color(ramp: ramp, load: 0, backdropLuminance: $0) }
        }
        let count = max(loads.count, tones.count)
        return (0..<count).map { index in
            let t = count == 1 ? 0.0 : Double(index) / Double(count - 1)
            return color(ramp: ramp, load: sample(loads, at: t),
                         backdropLuminance: sample(tones, at: t))
        }
    }

    /// Turns an oldest-first history into `count` newest-first slice values,
    /// which is the order the band's gradient runs in.
    public static func sliceValues(history: [Double], count: Int = profileSlices) -> [Double] {
        guard !history.isEmpty, count > 0 else { return [] }
        guard history.count > 1 else { return [Double](repeating: history[0], count: count) }
        return (0..<count).map { index in
            let t = count == 1 ? 0.0 : Double(index) / Double(count - 1)
            let position = (1 - t) * Double(history.count - 1)
            let low = Int(position.rounded(.down)), high = min(history.count - 1, low + 1)
            let f = position - Double(low)
            return history[low] + (history[high] - history[low]) * f
        }
    }

    /// Reads a newest-first series at a normalised position along the band.
    static func sample(_ values: [Double], at t: Double) -> Double {
        guard let first = values.first else { return 0 }
        guard values.count > 1 else { return first }
        let position = min(1, max(0, t)) * Double(values.count - 1)
        let low = Int(position.rounded(.down)), high = min(values.count - 1, low + 1)
        let f = position - Double(low)
        return values[low] + (values[high] - values[low]) * f
    }

    /// The contrast hairline, per slice: light under dark strands on a bright
    /// stretch, near-black under bright ones on a dark stretch.
    public static func haloStops(profile: [Double]) -> [RampStop] {
        let dark = RampStop(0.04, 0.05, 0.06), light = RampStop(1, 1, 1)
        guard !profile.isEmpty else { return [dark] }
        return profile.map { blend(dark, light, CGFloat(lightness(backdropLuminance: $0))) }
    }

    /// Evenly spaced gradient locations for a stop list.
    ///
    /// A gradient needs at least two stops to paint anything, so a single-stop
    /// list is treated as a flat run from 0 to 1 (see `paddedStops`).
    public static func locations(count: Int) -> [CGFloat] {
        guard count > 1 else { return [0, 1] }
        return (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
    }

    /// Guarantees at least two stops, so a flat colour still renders.
    public static func paddedStops(_ stops: [RampStop]) -> [RampStop] {
        guard let only = stops.first else { return [] }
        return stops.count == 1 ? [only, only] : stops
    }

    /// Hue in degrees, or nil for a colour with no hue to speak of.
    public static func hue(_ stop: RampStop) -> Double? {
        let peak = max(stop.red, max(stop.green, stop.blue))
        let floor = min(stop.red, min(stop.green, stop.blue))
        let span = peak - floor
        guard span > 0.02 else { return nil }
        let degrees: Double
        if peak == stop.red {
            degrees = 60 * ((stop.green - stop.blue) / span)
        } else if peak == stop.green {
            degrees = 60 * (2 + (stop.blue - stop.red) / span)
        } else {
            degrees = 60 * (4 + (stop.red - stop.green) / span)
        }
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Shortest distance between two hues, in degrees.
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    /// Relative luminance of a colour, for measuring a backdrop.
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}
