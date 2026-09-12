import CoreGraphics
import Foundation

/// Chooses where the detail panel opens.
///
/// Sill lives on the wallpaper and should not cover the window you are working
/// in — but a panel hidden behind that window has not opened at all. So rather
/// than lifting it above everything, it opens into whatever part of the desktop
/// is actually exposed: the same level, a better place.
public enum PanelPlacement {
    /// Candidate positions, best first: beside the band at its middle, then
    /// slid along the band, then stepped further in from the edge — because on
    /// a busy desktop the exposed strip is often not the one next to the band.
    public static func candidates(edge: ScreenEdge, band: CGRect, panelSize: CGSize,
                                  visibleFrame: CGRect, gap: CGFloat = Layout.gap) -> [CGRect] {
        var results: [CGRect] = []
        let alongPositions: [CGFloat] = edge.isVertical
            ? [band.midY - panelSize.height / 2,
               visibleFrame.maxY - panelSize.height, visibleFrame.minY,
               band.maxY - panelSize.height, band.minY]
            : [band.midX - panelSize.width / 2,
               visibleFrame.minX, visibleFrame.maxX - panelSize.width,
               band.minX, band.maxX - panelSize.width]
        let depths: [CGFloat] = [gap, gap + panelSize.width * 0.9,
                                 gap + panelSize.width * 1.8]

        for depth in depths {
            for along in alongPositions {
                var frame = CGRect(origin: .zero, size: panelSize)
                switch edge {
                case .right:
                    frame.origin.x = band.minX - depth - panelSize.width
                    frame.origin.y = along
                case .left:
                    frame.origin.x = band.maxX + depth
                    frame.origin.y = along
                case .top:
                    frame.origin.x = along
                    frame.origin.y = band.minY - depth - panelSize.height
                case .bottom:
                    frame.origin.x = along
                    frame.origin.y = band.maxY + depth
                }
                results.append(clamp(frame, into: visibleFrame))
            }
        }
        // Duplicates are cheap to make and pointless to score twice.
        var unique: [CGRect] = []
        for frame in results where !unique.contains(where: { $0.equalTo(frame) }) {
            unique.append(frame)
        }
        return unique
    }

    /// How much of `frame` the given windows cover, as 0...1.
    public static func coverage(of frame: CGRect, by windows: [CGRect]) -> Double {
        let area = frame.width * frame.height
        guard area > 0 else { return 0 }
        // Sampling beats exact rectangle union arithmetic here: it handles
        // overlapping windows correctly without the bookkeeping.
        let columns = 24, rows = 24
        var covered = 0
        for column in 0..<columns {
            for row in 0..<rows {
                let point = CGPoint(x: frame.minX + (CGFloat(column) + 0.5) / CGFloat(columns) * frame.width,
                                    y: frame.minY + (CGFloat(row) + 0.5) / CGFloat(rows) * frame.height)
                if windows.contains(where: { $0.contains(point) }) { covered += 1 }
            }
        }
        return Double(covered) / Double(columns * rows)
    }

    /// How far a spot sits from the band, 0 (touching) to 1 (other side of the
    /// screen). The panel belongs to the band, so distance is a real cost.
    static func distance(from band: CGRect, to frame: CGRect, in visible: CGRect) -> Double {
        let reach = max(visible.width, visible.height)
        guard reach > 0 else { return 0 }
        let dx = frame.midX - band.midX, dy = frame.midY - band.midY
        return min(1, (dx * dx + dy * dy).squareRoot() / reach)
    }

    /// The best spot for the panel.
    ///
    /// The panel belongs beside the middle of its band, and that is where it
    /// opens unless that spot is obstructed. Then it slides along the band, or
    /// one step further in — never off to a corner of the screen. If nothing
    /// beside the band is clear enough to be worth reading, it stays where it
    /// belongs and comes forward instead (see `isHidden`).
    public static func choose(edge: ScreenEdge, band: CGRect, panelSize: CGSize,
                              visibleFrame: CGRect, windows: [CGRect],
                              gap: CGFloat = Layout.gap,
                              acceptableCoverage: Double = 0.35) -> CGRect {
        let options = candidates(edge: edge, band: band, panelSize: panelSize,
                                 visibleFrame: visibleFrame, gap: gap)
        guard let preferred = options.first else {
            return CGRect(origin: visibleFrame.origin, size: panelSize)
        }
        let preferredCoverage = coverage(of: preferred, by: windows)
        // Where it belongs, if it can be read there at all.
        guard preferredCoverage > acceptableCoverage else { return preferred }

        var best = preferred
        var bestCoverage = preferredCoverage
        for option in options.dropFirst() {
            let score = coverage(of: option, by: windows)
            if score < bestCoverage - 0.08 {
                best = option
                bestCoverage = score
            }
            // Good enough is good enough: stop at the first clear spot nearest
            // the preferred one rather than hunting for the very best.
            if bestCoverage <= acceptableCoverage { break }
        }
        return bestCoverage <= acceptableCoverage ? best : preferred
    }

    /// Whether a spot is so covered that opening behind the windows would
    /// mean not opening at all.
    public static func isHidden(_ frame: CGRect, by windows: [CGRect],
                                threshold: Double = 0.35) -> Bool {
        coverage(of: frame, by: windows) > threshold
    }

    static func clamp(_ frame: CGRect, into bounds: CGRect) -> CGRect {
        var result = frame
        result.origin.x = min(max(bounds.minX, result.origin.x), bounds.maxX - frame.width)
        result.origin.y = min(max(bounds.minY, result.origin.y), bounds.maxY - frame.height)
        return result
    }
}
