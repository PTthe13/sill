import CoreGraphics
import Foundation

/// The parts of a display Sill cares about. Lets the selection logic be
/// exercised against invented screen configurations.
public struct ScreenInfo: Equatable, Sendable {
    public let uuid: String
    public let name: String
    public let visibleFrame: CGRect
    /// The whole screen, menu bar and Dock included. The band is centred on
    /// this, not on the visible frame — see `Layout.waveFrame`.
    public let frame: CGRect
    public let backingScaleFactor: CGFloat
    public let isMain: Bool

    public init(uuid: String, name: String, visibleFrame: CGRect,
                frame: CGRect? = nil,
                backingScaleFactor: CGFloat = 2, isMain: Bool = false) {
        self.uuid = uuid
        self.name = name
        self.visibleFrame = visibleFrame
        self.frame = frame ?? visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.isMain = isMain
    }
}

/// Picks which connected display the wave lives on.
///
/// The user's choice is remembered even while that display is absent, so
/// re-plugging it moves the wave back without any further input.
public enum ScreenSelection {
    public static func resolve(preferredUUID: String?, screens: [ScreenInfo]) -> ScreenInfo? {
        guard !screens.isEmpty else { return nil }
        if let preferredUUID, let match = screens.first(where: { $0.uuid == preferredUUID }) {
            return match
        }
        return screens.first(where: \.isMain) ?? screens[0]
    }

    /// Which displays get a band: every connected one, or just the chosen one.
    ///
    /// Ordered with the main display first so the band that opens the detail
    /// panel by default is the one most people are looking at.
    public static func bandScreens(showsOnAllDisplays: Bool, preferredUUID: String?,
                                   screens: [ScreenInfo]) -> [ScreenInfo] {
        guard showsOnAllDisplays else {
            return resolve(preferredUUID: preferredUUID, screens: screens).map { [$0] } ?? []
        }
        return screens.sorted { a, b in
            if a.isMain != b.isMain { return a.isMain }
            return a.uuid < b.uuid
        }
    }

    /// True when the wave is currently on a fallback rather than the choice.
    public static func isFallback(preferredUUID: String?, screens: [ScreenInfo]) -> Bool {
        guard let preferredUUID else { return false }
        return !screens.contains { $0.uuid == preferredUUID }
    }
}
