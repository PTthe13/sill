import AppKit
import CoreGraphics
import SillCore

/// Bridges NSScreen to the plain ScreenInfo the selection logic works with.
enum Screens {
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Stable across reconnects, unlike the display ID or the array index.
    static func uuid(for screen: NSScreen) -> String {
        guard let id = displayID(for: screen),
              let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            // Last resort: the name plus the panel size still survives a replug.
            return "\(screen.localizedName)-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        }
        return CFUUIDCreateString(nil, cf) as String
    }

    static func info(for screen: NSScreen) -> ScreenInfo {
        // "Main" here means the primary display — the one with the menu bar —
        // NOT `NSScreen.main`, which is wherever the keyboard focus happens to
        // be. Using that would make the band hop between displays as you move
        // between windows.
        ScreenInfo(uuid: uuid(for: screen),
                   name: screen.localizedName,
                   visibleFrame: screen.visibleFrame,
                   frame: screen.frame,
                   backingScaleFactor: screen.backingScaleFactor,
                   isMain: displayID(for: screen) == CGMainDisplayID())
    }

    static func all() -> [ScreenInfo] {
        NSScreen.screens.map { info(for: $0) }
    }

    static func screen(withUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { Self.uuid(for: $0) == uuid }
    }
}
