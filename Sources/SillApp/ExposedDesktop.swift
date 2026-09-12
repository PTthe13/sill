import AppKit
import CoreGraphics
import SillCore

/// Where other apps' windows currently are.
///
/// `CGWindowListCopyWindowInfo` reports window *bounds* without any permission
/// — only reading their contents would need Screen Recording — which is enough
/// to tell which part of the desktop is exposed.
enum ExposedDesktop {
    /// Frames of the on-screen windows of other applications, in AppKit
    /// coordinates (origin bottom-left), clipped to `screen`.
    static func occupiedFrames(on screen: CGRect) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // The window server reports y down from the top of the primary display.
        let flipHeight = (NSScreen.screens.first?.frame.maxY) ?? screen.maxY

        return windows.compactMap { window -> CGRect? in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let alpha = window[kCGWindowAlpha as String] as? Double, alpha > 0.05,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            let flipped = CGRect(x: rect.minX, y: flipHeight - rect.maxY,
                                 width: rect.width, height: rect.height)
            let clipped = flipped.intersection(screen)
            return clipped.isNull || clipped.width < 8 || clipped.height < 8 ? nil : clipped
        }
    }
}
