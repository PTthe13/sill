import CoreGraphics
import Foundation

public struct RampStop: Equatable, Sendable {
    public let red: Double, green: Double, blue: Double, alpha: Double

    public init(_ red: Double, _ green: Double, _ blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    /// Hex in 0xRRGGBB form.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255,
                  Double((hex >> 8) & 0xFF) / 255,
                  Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// What sits behind the strands, if anything.
///
/// Nothing is the default and the honest one: the wave belongs to the
/// wallpaper. But on a photograph with light and dark in the same band, a
/// plate behind it is the difference between reading the wave and hunting for
/// it — so it is offered, with its cost stated.
public enum BandBackground: String, CaseIterable, Codable, Sendable {
    /// The wallpaper, untouched.
    case none
    /// A pale plate, for a dark desktop or simply for a lighter look.
    case light
    /// A dark plate. Costs nothing: no blur, no recomposite. Stored as
    /// "shade", the name it had when it was the only plate there was, so an
    /// existing setting keeps working.
    case shade
    /// A real blur. The brief warns against it, and rightly: a blur behind the
    /// band forces the window server to recomposite whenever anything under it
    /// moves. Offered because on some wallpapers it is the only thing that works.
    case glass

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .light: return "Light"
        case .shade: return "Dark"
        case .glass: return "Glass"
        }
    }

    /// Opacity of the flat plate.
    ///
    /// Light enough to sit under a wave rather than behind a window: these are
    /// deliberately far softer than the first version, which covered the
    /// wallpaper almost completely and made the band look like a widget.
    public func plateAlpha(lightness: CGFloat) -> CGFloat {
        switch self {
        case .none, .glass: return 0
        // A little heavier over a light desktop, where it has more to cover.
        case .shade: return 0.22 + 0.14 * lightness
        // And a little heavier over a dark one, for the same reason.
        case .light: return 0.24 + 0.14 * (1 - lightness)
        }
    }

    /// True when the plate is pale rather than dark.
    public var isPale: Bool { self == .light }

    /// What the strands are actually sitting on once a plate is behind them.
    ///
    /// This is the point of the option: put something dark behind the band and
    /// the wave should go back to its bright colours, rather than staying inked
    /// for a wallpaper it can no longer see. A pale plate does the reverse.
    public func effectiveLuminance(wallpaper: Double) -> Double {
        switch self {
        case .none: return wallpaper
        // Not 0 and not 1: the plate is soft enough that the wallpaper still
        // shows through it, so the strands are toned for a blend of the two.
        case .shade: return min(wallpaper, 0.24)
        case .light: return max(wallpaper, 0.74)
        case .glass: return 0.30
        }
    }

    /// Corner radius of the plate, in points.
    public static let cornerRadius: CGFloat = 14
}

public enum ColorRamp: String, CaseIterable, Codable, Sendable {
    case load, teal, violet, amber, mono

    public var displayName: String {
        switch self {
        case .load: return "Load"
        case .teal: return "Teal"
        case .violet: return "Blue → purple"
        case .amber: return "Amber"
        case .mono: return "Mono"
        }
    }

    /// idle → mid → heavy
    public var stops: [RampStop] {
        switch self {
        case .load:   return [RampStop(hex: 0x4FD1A5), RampStop(hex: 0xFFC53D), RampStop(hex: 0xFF5B4A)]
        // Teal travels mint -> cyan -> ocean: three shades of one hue read as
        // "darker", not "busier", now that colour carries the load.
        case .teal:   return [RampStop(hex: 0x6FE3C0), RampStop(hex: 0x22B8C6), RampStop(hex: 0x1E88C7)]
        case .violet: return [RampStop(hex: 0x4FA8F5), RampStop(hex: 0x7B74E0), RampStop(hex: 0xA855F7)]
        // Amber travels gold -> orange -> rust, so a pinned machine reads hot.
        case .amber:  return [RampStop(hex: 0xF6D06B), RampStop(hex: 0xED8F2E), RampStop(hex: 0xD2422A)]
        case .mono:   return [RampStop(1, 1, 1, alpha: 0.92),
                              RampStop(1, 1, 1, alpha: 0.58),
                              RampStop(1, 1, 1, alpha: 0.34)]
        }
    }

    /// The same three steps, picked for a light wallpaper rather than derived
    /// from the dark set: darkening a yellow arithmetically gives olive, so the
    /// mid stops move toward burnt amber instead.
    public var lightBackdropStops: [RampStop] {
        switch self {
        case .load:   return [RampStop(hex: 0x0F7A55), RampStop(hex: 0xA65E06), RampStop(hex: 0xA32316)]
        case .teal:   return [RampStop(hex: 0x17876B), RampStop(hex: 0x0E6E78), RampStop(hex: 0x0B4F7A)]
        case .violet: return [RampStop(hex: 0x1B5FC4), RampStop(hex: 0x4A3BC0), RampStop(hex: 0x6D1BA8)]
        case .amber:  return [RampStop(hex: 0xA97A10), RampStop(hex: 0x97500A), RampStop(hex: 0x8A2411)]
        case .mono:   return [RampStop(0.07, 0.08, 0.09, alpha: 0.88),
                              RampStop(0.07, 0.08, 0.09, alpha: 0.66),
                              RampStop(0.07, 0.08, 0.09, alpha: 0.46)]
        }
    }

    /// Severity thresholds used for discrete picks (process bars, head colour).
    public static let midThreshold: Double = 45
    public static let heavyThreshold: Double = 78

    public func stop(forLoad percent: Double) -> RampStop {
        let s = stops
        if percent < Self.midThreshold { return s[0] }
        if percent < Self.heavyThreshold { return s[1] }
        return s[2]
    }
}

/// Opacity ramp applied along the time axis: newest end solid, oldest faint,
/// dissolving to nothing at both extremes.
public enum Fade {
    public static let defaultFloor: CGFloat = 0.30

    /// Locations run from the newest sample (0) to the oldest (1). `floor` is
    /// the opacity at the oldest end, raised on light backdrops.
    public static func stops(floor: CGFloat = defaultFloor) -> [(location: CGFloat, alpha: CGFloat)] {
        [(0.00, 0.00),
         (0.06, 1.00),
         (0.55, 0.72 + (floor - defaultFloor) * 0.6),
         (0.93, floor),
         (1.00, 0.00)]
    }

    /// The age curve evaluated per slice, with each slice's floor raised for a
    /// light patch of wallpaper. Without this the oldest end washes out over a
    /// bright stretch however well its colour is chosen.
    public static func profileAlphas(profile: [Double]) -> [CGFloat] {
        // A flat backdrop still fades with age, and a gradient needs at least
        // two stops to paint at all — one stop masks the whole band away.
        let tones = profile.count > 1 ? profile
            : [Double](repeating: profile.first ?? Palette.assumedLuminance,
                       count: Palette.profileSlices)
        return tones.enumerated().map { index, luminance in
            let t = CGFloat(index) / CGFloat(tones.count - 1)
            let lightness = CGFloat(Palette.lightness(backdropLuminance: luminance))
            return alpha(atAge: t, floor: defaultFloor + 0.18 * lightness)
        }
    }

    public static func alpha(atAge age: CGFloat, floor: CGFloat = defaultFloor) -> CGFloat {
        let stops = stops(floor: floor)
        let t = min(1, max(0, age))
        for i in 1..<stops.count {
            let a = stops[i - 1], b = stops[i]
            if t <= b.location {
                let span = b.location - a.location
                let f = span <= 0 ? 0 : (t - a.location) / span
                return a.alpha + (b.alpha - a.alpha) * f
            }
        }
        return stops[stops.count - 1].alpha
    }
}
