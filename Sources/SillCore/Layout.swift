import CoreGraphics
import Foundation

/// Frames for the band, the wave and the detail panel, in screen coordinates
/// (AppKit: origin bottom-left, y up).
public enum Layout {
    /// Kept clear of the menu bar shadow and the Dock.
    public static let edgeInset: CGFloat = 2
    /// Gap between the wave and the panel.
    public static let gap: CGFloat = 16
    /// Room kept inboard of the band, while closed, for the hover readout to
    /// live in. The window covers it but stays click-through: only the band
    /// itself takes the mouse.
    public static let hoverGutter: CGFloat = 210
    /// Width of the panel on a left/right edge. The brief says 298; at that
    /// width the readings had to be set too small to read at a glance, which
    /// defeats the point of a glanceable panel.
    public static let panelWidth: CGFloat = 344
    /// The widest a horizontal bar gets, however long the band is.
    public static let maximumBarWidth: CGFloat = 940
    /// How far the panel slides in from the screen edge while appearing.
    public static let panelSlide: CGFloat = 14
    public static let openDuration: Double = 0.34

    /// The band spans the same fraction of the screen whichever edge it is on:
    /// height on left and right, width on top and bottom.
    public static func bandLength(edge: ScreenEdge, visibleFrame: CGRect,
                                  fraction: CGFloat = WaveGeometry.defaultLengthFraction) -> CGFloat {
        let clamped = min(WaveGeometry.maximumLengthFraction,
                          max(WaveGeometry.minimumLengthFraction, fraction))
        let available = edge.isVertical ? visibleFrame.height : visibleFrame.width
        return min(available - 2 * edgeInset, available * clamped)
    }

    /// The strip the wave occupies while closed.
    ///
    /// The band is inset from the VISIBLE frame (so it clears the Dock and the
    /// menu bar) but centred on the WHOLE screen, which is what the Dock does
    /// too: centring on the visible frame instead leaves it sitting half a menu
    /// bar off from everything else on screen, and that reads as a mistake.
    public static func waveFrame(edge: ScreenEdge, visibleFrame: CGRect,
                                 fraction: CGFloat = WaveGeometry.defaultLengthFraction,
                                 screenFrame: CGRect? = nil) -> CGRect {
        let length = bandLength(edge: edge, visibleFrame: visibleFrame, fraction: fraction)
        let t = WaveGeometry.thickness
        let whole = screenFrame ?? visibleFrame
        // Centre on the screen, but never let that push an end past the usable
        // area: a tall band on a screen with a menu bar would clip otherwise.
        let midY = min(max(whole.midY, visibleFrame.minY + length / 2),
                       visibleFrame.maxY - length / 2)
        let midX = min(max(whole.midX, visibleFrame.minX + length / 2),
                       visibleFrame.maxX - length / 2)
        switch edge {
        case .left:
            return CGRect(x: visibleFrame.minX + edgeInset,
                          y: midY - length / 2, width: t, height: length)
        case .right:
            return CGRect(x: visibleFrame.maxX - edgeInset - t,
                          y: midY - length / 2, width: t, height: length)
        case .top:
            return CGRect(x: midX - length / 2,
                          y: visibleFrame.maxY - edgeInset - t, width: length, height: t)
        case .bottom:
            return CGRect(x: midX - length / 2,
                          y: visibleFrame.minY + edgeInset, width: length, height: t)
        }
    }

    /// The window covers the wave plus, when open, the panel inboard of it.
    /// `panelExtent` is the panel's width (vertical edges) or height (horizontal).
    public static func windowFrame(edge: ScreenEdge, visibleFrame: CGRect,
                                   panelExtent: CGFloat,
                                   fraction: CGFloat = WaveGeometry.defaultLengthFraction,
                                   screenFrame: CGRect? = nil) -> CGRect {
        var frame = waveFrame(edge: edge, visibleFrame: visibleFrame, fraction: fraction,
                              screenFrame: screenFrame)
        // Never grow past the far side of the screen: on a small display the
        // gutter is wider than the room inboard of the band, and a window
        // hanging off the edge takes mouse events nobody can reach.
        // The band is already inset from its own edge, so the room inboard is
        // what is left after the band and that inset.
        let room = (edge.isVertical ? visibleFrame.width - frame.width
                                    : visibleFrame.height - frame.height) - edgeInset
        let grow = min(max(0, room), panelExtent > 0 ? panelExtent + gap : hoverGutter)
        switch edge {
        case .left:   frame.size.width += grow
        case .right:  frame.origin.x -= grow; frame.size.width += grow
        case .top:    frame.origin.y -= grow; frame.size.height += grow
        case .bottom: frame.size.height += grow
        }
        return frame
    }

    /// Where the wave sits inside the window.
    ///
    /// Closed, it is flush against the screen edge (`atOuterSide`); open, it
    /// slides inboard so the panel can take the outer strip.
    public static func waveFrameInWindow(edge: ScreenEdge, windowSize: CGSize,
                                         atOuterSide: Bool = false) -> CGRect {
        let t = WaveGeometry.thickness
        switch edge {
        case .left:
            return CGRect(x: atOuterSide ? 0 : windowSize.width - t, y: 0,
                          width: t, height: windowSize.height)
        case .right:
            return CGRect(x: atOuterSide ? windowSize.width - t : 0, y: 0,
                          width: t, height: windowSize.height)
        case .top:
            return CGRect(x: 0, y: atOuterSide ? windowSize.height - t : 0,
                          width: windowSize.width, height: t)
        case .bottom:
            return CGRect(x: 0, y: atOuterSide ? 0 : windowSize.height - t,
                          width: windowSize.width, height: t)
        }
    }

    /// Where the hover readout sits, in the band's own coordinates: just
    /// inboard of the band (so outside its bounds, which is why the window
    /// keeps a gutter), centred on the pointer and clamped to the band's ends.
    public static func scrubChipFrame(edge: ScreenEdge, bandSize: CGSize,
                                      alongPoint: CGFloat, chipSize: CGSize) -> CGRect {
        let margin: CGFloat = 10
        var frame = CGRect(origin: .zero, size: chipSize)
        switch edge {
        case .right:
            frame.origin.x = -margin - chipSize.width
            frame.origin.y = alongPoint - chipSize.height / 2
        case .left:
            frame.origin.x = bandSize.width + margin
            frame.origin.y = alongPoint - chipSize.height / 2
        case .top:
            frame.origin.x = alongPoint - chipSize.width / 2
            frame.origin.y = -margin - chipSize.height
        case .bottom:
            frame.origin.x = alongPoint - chipSize.width / 2
            frame.origin.y = bandSize.height + margin
        }
        if edge.isVertical {
            frame.origin.y = min(max(0, frame.origin.y), max(0, bandSize.height - chipSize.height))
        } else {
            frame.origin.x = min(max(0, frame.origin.x), max(0, bandSize.width - chipSize.width))
        }
        return frame
    }

    /// Where the panel sits inside the window: the outer strip, against the
    /// edge, hugging its own content along the time axis.
    ///
    /// `panelSize` is what the panel asked for: a fixed-width card on left and
    /// right, a full-width bar of content height on top and bottom.
    public static func panelFrameInWindow(edge: ScreenEdge, windowSize: CGSize,
                                          panelSize: CGSize) -> CGRect {
        switch edge {
        case .left, .right:
            let height = min(panelSize.height, windowSize.height)
            let x = edge == .left ? 0 : windowSize.width - panelSize.width
            return CGRect(x: x, y: (windowSize.height - height) / 2,
                          width: panelSize.width, height: height)
        case .top, .bottom:
            let width = min(panelSize.width, windowSize.width)
            let y = edge == .top ? windowSize.height - panelSize.height : 0
            return CGRect(x: (windowSize.width - width) / 2, y: y,
                          width: width, height: panelSize.height)
        }
    }

    /// The panel's thickness across the band, which is how much the window grows.
    public static func panelExtent(edge: ScreenEdge, panelSize: CGSize) -> CGFloat {
        edge.isVertical ? panelSize.width : panelSize.height
    }

    /// The parts of the band's window that belong to Sill.
    ///
    /// While the panel is open the window can span a lot of desktop between
    /// the band and the panel, and none of that gap is Sill's to take: a click
    /// there belongs to whatever is underneath.
    public static func liveRegions(band: CGRect, panel: CGRect?, isOpen: Bool) -> [CGRect] {
        var regions = [band]
        if isOpen, let panel, !panel.isEmpty { regions.append(panel) }
        return regions
    }

    public static func takesMouse(at point: CGPoint, band: CGRect, panel: CGRect?,
                                  isOpen: Bool, slack: CGFloat = 6) -> Bool {
        liveRegions(band: band, panel: panel, isOpen: isOpen)
            .contains { $0.insetBy(dx: -slack, dy: -slack).contains(point) }
    }

    /// Offset the panel animates in from: outward, toward the screen edge.
    public static func panelEntryOffset(edge: ScreenEdge) -> CGSize {
        switch edge {
        case .left:   return CGSize(width: -panelSlide, height: 0)
        case .right:  return CGSize(width: panelSlide, height: 0)
        case .top:    return CGSize(width: 0, height: panelSlide)
        case .bottom: return CGSize(width: 0, height: -panelSlide)
        }
    }
}
