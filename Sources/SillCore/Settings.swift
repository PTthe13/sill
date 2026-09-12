import Foundation

public enum PanelMaterial: String, CaseIterable, Codable, Sendable {
    case clear, tinted

    public var displayName: String { self == .clear ? "Clear" : "Tinted" }
    /// Background alpha, border alpha, secondary-text alpha.
    public var backgroundAlpha: Double { self == .clear ? 0.62 : 0.84 }
    public var borderAlpha: Double { self == .clear ? 0.30 : 0.22 }
    public var secondaryTextAlpha: Double { self == .clear ? 0.72 : 0.78 }
}

/// The values Sill actually acts on, for telling a real change from the
/// constant background chatter of `UserDefaults.didChangeNotification` — which
/// fires for every framework that registers a default, several times a second
/// while SwiftUI lays out.
public struct SettingsSnapshot: Equatable, Sendable {
    public var edge: ScreenEdge
    public var ramp: ColorRamp
    public var material: PanelMaterial
    public var dimWhenFocused: Bool
    public var sampleInterval: Double
    public var lengthFraction: CGFloat
    public var spanMinutes: Double
    public var displayUUID: String?
    public var showsOnAllDisplays: Bool
    public var liftsWhenOpen: Bool
    public var background: BandBackground
    public var areaFill: Bool
    public var envelopeMetric: Metric
    public var fillMetric: Metric
}

/// Everything the user can change, persisted in UserDefaults.
public final class SillSettings {
    public static let didChange = Notification.Name("sill.settings.didChange")
    public static let minimumInterval: Double = 0.5
    public static let maximumInterval: Double = 5

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.edge: ScreenEdge.right.rawValue,
            Key.ramp: ColorRamp.load.rawValue,
            Key.material: PanelMaterial.tinted.rawValue,
            Key.dimWhenFocused: true,
            Key.sampleInterval: 1.0,
            Key.lengthFraction: Double(WaveGeometry.defaultLengthFraction),
            Key.spanMinutes: Span.automatic,
            Key.showsOnAllDisplays: false,
            Key.liftsWhenOpen: false,
            Key.background: BandBackground.none.rawValue,
            Key.areaFill: false,
            Key.envelopeMetric: Metric.cpu.rawValue,
            Key.fillMetric: Metric.memory.rawValue,
        ])
    }

    private enum Key {
        static let edge = "edge"
        static let ramp = "ramp"
        static let material = "material"
        static let dimWhenFocused = "dimWhenFocused"
        static let sampleInterval = "sampleInterval"
        static let lengthFraction = "lengthFraction"
        static let spanMinutes = "spanMinutes"
        static let displayUUID = "displayUUID"
        static let showsOnAllDisplays = "showsOnAllDisplays"
        static let liftsWhenOpen = "liftsWhenOpen"
        static let background = "background"
        static let areaFill = "areaFill"
        static let envelopeMetric = "envelopeMetric"
        static let fillMetric = "fillMetric"
        static let launchAtLogin = "launchAtLogin"
        static let hasIntroduced = "hasIntroduced"
    }

    private func post() { NotificationCenter.default.post(name: SillSettings.didChange, object: self) }

    public var edge: ScreenEdge {
        get { ScreenEdge(rawValue: defaults.string(forKey: Key.edge) ?? "") ?? .right }
        set { defaults.set(newValue.rawValue, forKey: Key.edge); post() }
    }

    public var ramp: ColorRamp {
        get { ColorRamp(rawValue: defaults.string(forKey: Key.ramp) ?? "") ?? .load }
        set { defaults.set(newValue.rawValue, forKey: Key.ramp); post() }
    }

    public var material: PanelMaterial {
        get { PanelMaterial(rawValue: defaults.string(forKey: Key.material) ?? "") ?? .tinted }
        set { defaults.set(newValue.rawValue, forKey: Key.material); post() }
    }

    public var dimWhenFocused: Bool {
        get { defaults.bool(forKey: Key.dimWhenFocused) }
        set { defaults.set(newValue, forKey: Key.dimWhenFocused); post() }
    }

    public var sampleInterval: Double {
        get {
            let value = defaults.double(forKey: Key.sampleInterval)
            return min(SillSettings.maximumInterval, max(SillSettings.minimumInterval, value))
        }
        set {
            let clamped = min(SillSettings.maximumInterval, max(SillSettings.minimumInterval, newValue))
            defaults.set(clamped, forKey: Key.sampleInterval)
            post()
        }
    }

    /// How much of the screen's length the band spans, on every edge.
    public var lengthFraction: CGFloat {
        get {
            let value = CGFloat(defaults.double(forKey: Key.lengthFraction))
            return min(WaveGeometry.maximumLengthFraction,
                       max(WaveGeometry.minimumLengthFraction, value))
        }
        set {
            let clamped = min(WaveGeometry.maximumLengthFraction,
                              max(WaveGeometry.minimumLengthFraction, newValue))
            defaults.set(Double(clamped), forKey: Key.lengthFraction)
            post()
        }
    }

    /// How much time the band covers, in minutes. Zero means automatic: the
    /// band holds whatever its length and the sample interval give it.
    public var spanMinutes: Double {
        get {
            let value = defaults.double(forKey: Key.spanMinutes)
            guard value > 0 else { return Span.automatic }
            return min(Span.maximumMinutes, max(Span.minimumMinutes, value))
        }
        set {
            let clamped = newValue <= 0 ? Span.automatic
                : min(Span.maximumMinutes, max(Span.minimumMinutes, newValue))
            defaults.set(clamped, forKey: Key.spanMinutes)
            post()
        }
    }

    /// Stable identifier of the chosen display; nil means "the main display".
    public var displayUUID: String? {
        get { defaults.string(forKey: Key.displayUUID) }
        set { defaults.set(newValue, forKey: Key.displayUUID); post() }
    }

    /// What sits behind the strands: nothing, a flat plate, or a real blur.
    public var background: BandBackground {
        get { BandBackground(rawValue: defaults.string(forKey: Key.background) ?? "") ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.background); post() }
    }

    /// Fills the space between the envelope strands, fading out toward the axis.
    public var areaFill: Bool {
        get { defaults.bool(forKey: Key.areaFill) }
        set { defaults.set(newValue, forKey: Key.areaFill); post() }
    }

    /// Whether opening the detail band brings it above your windows.
    ///
    /// Off by default: Sill lives on the wallpaper and should not cover the
    /// window you are working in. The cost is that a window sitting over that
    /// part of the desktop hides the panel — which is the honest consequence
    /// of staying behind everything.
    public var liftsWhenOpen: Bool {
        get { defaults.bool(forKey: Key.liftsWhenOpen) }
        set { defaults.set(newValue, forKey: Key.liftsWhenOpen); post() }
    }

    /// What the wave's shape encodes.
    public var envelopeMetric: Metric {
        get { Metric(rawValue: defaults.string(forKey: Key.envelopeMetric) ?? "") ?? .cpu }
        set { defaults.set(newValue.rawValue, forKey: Key.envelopeMetric); post() }
    }

    /// What the density between the envelope strands encodes.
    public var fillMetric: Metric {
        get { Metric(rawValue: defaults.string(forKey: Key.fillMetric) ?? "") ?? .memory }
        set { defaults.set(newValue.rawValue, forKey: Key.fillMetric); post() }
    }

    /// A band on every connected display, rather than just the chosen one.
    public var showsOnAllDisplays: Bool {
        get { defaults.bool(forKey: Key.showsOnAllDisplays) }
        set { defaults.set(newValue, forKey: Key.showsOnAllDisplays); post() }
    }

    public var snapshot: SettingsSnapshot {
        SettingsSnapshot(edge: edge, ramp: ramp, material: material,
                         dimWhenFocused: dimWhenFocused, sampleInterval: sampleInterval,
                         lengthFraction: lengthFraction, spanMinutes: spanMinutes,
                         displayUUID: displayUUID,
                         showsOnAllDisplays: showsOnAllDisplays,
                         liftsWhenOpen: liftsWhenOpen, background: background,
                         areaFill: areaFill,
                         envelopeMetric: envelopeMetric, fillMetric: fillMetric)
    }

    /// False until the app has introduced itself once.
    public var hasIntroduced: Bool {
        get { defaults.bool(forKey: Key.hasIntroduced) }
        set { defaults.set(newValue, forKey: Key.hasIntroduced) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }
}
