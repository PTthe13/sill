import CoreGraphics
import Foundation

/// The small chevron that fades in when the pointer is over the band, so the
/// wave admits it can be opened. It points the way the panel will appear —
/// inboard, away from the screen edge — and flips to point back out once the
/// panel is open.
public enum Affordance {
    /// Distance from the band's inboard side to the chevron's tip.
    public static let inset: CGFloat = 9
    /// Half the chevron's span across the time axis.
    public static let halfSpan: CGFloat = 5.5
    /// How far the arms trail behind the tip.
    public static let depth: CGFloat = 5.5
    public static let lineWidth: CGFloat = 1.6
    public static let fadeInDuration: Double = 0.16
    public static let fadeOutDuration: Double = 0.22

    /// Tip and the two arm ends, in band-local coordinates (y-up).
    ///
    /// `pointsInboard` is true while the band is closed: the chevron points the
    /// way the panel will open. Once open it reverses, meaning "put it away".
    public static func points(edge: ScreenEdge, size: CGSize,
                              pointsInboard: Bool) -> (tip: CGPoint, arms: [CGPoint]) {
        let thickness = edge.isVertical ? size.width : size.height
        let along = edge.isVertical ? size.height / 2 : size.width / 2
        // Depth measured from the band's inboard side, which is depth == thickness.
        let tipDepth = thickness - inset
        // Depth grows inboard, so a chevron pointing inboard trails its arms at
        // a shallower depth than its tip.
        let armDepth = pointsInboard ? tipDepth - depth : tipDepth + depth
        let transform = EdgeTransform(edge: edge,
                                      length: edge.isVertical ? size.height : size.width,
                                      thickness: thickness)
        let tip = transform.point(along: along, depth: tipDepth)
        let arms = [transform.point(along: along - halfSpan, depth: armDepth),
                    transform.point(along: along + halfSpan, depth: armDepth)]
        return (tip, arms)
    }

    public static func path(edge: ScreenEdge, size: CGSize, pointsInboard: Bool) -> CGPath {
        let (tip, arms) = points(edge: edge, size: size, pointsInboard: pointsInboard)
        let path = CGMutablePath()
        path.move(to: arms[0])
        path.addLine(to: tip)
        path.addLine(to: arms[1])
        return path
    }

    /// Ink on a light backdrop, light on a dark one — the same rule the halo
    /// follows, inverted, since this is the mark rather than its outline.
    public static func color(style: WaveStyle) -> RampStop {
        let halo = style.haloColor
        let light = Palette.luminance(red: halo.red, green: halo.green, blue: halo.blue) > 0.5
        return light ? RampStop(0.08, 0.09, 0.10, alpha: 0.80)
                     : RampStop(1, 1, 1, alpha: 0.82)
    }
}
