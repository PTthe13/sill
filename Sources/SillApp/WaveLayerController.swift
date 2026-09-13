import AppKit
import QuartzCore
import SillCore

/// Owns the Core Animation tree that draws the wave.
///
/// Paths change once per sample; the scroll between samples is a single
/// translation animation on the render server, so the app does no per-frame work.
final class WaveLayerController {
    let container = CALayer()

    private let waveLayer = CALayer()
    private let scrollLayer = CALayer()
    private let colorLayer = CAGradientLayer()
    private let strandsLayer = CALayer()
    private let haloLayer = CAGradientLayer()
    private let haloShapesLayer = CALayer()
    private var haloShapes: [CAShapeLayer] = []
    private let fadeMask = CAGradientLayer()
    private let chevron = CAShapeLayer()
    private let chevronHalo = CAShapeLayer()
    private let plate = CALayer()
    private let areaColour = CAGradientLayer()
    private let areaAlpha = CAGradientLayer()
    private let areaShape = CAShapeLayer()
    private let chip = CALayer()
    private let chipText = CATextLayer()
    private var shapes: [CAShapeLayer] = []
    private let model = WaveModel()

    private(set) var edge: ScreenEdge = .right
    private(set) var length: CGFloat = 0
    private(set) var ramp: ColorRamp = .load
    private(set) var style = Palette.style(ramp: .load, backdropLuminance: Palette.assumedLuminance)
    private var profile: [Double] = [Palette.assumedLuminance]
    private var loads: [Double] = []
    private var variation: Double = 0
    private var lastDepths: [[Double]] = []
    private var history: (cpu: [Double], memory: [Double]) = ([], [])
    /// How many of those samples were measured rather than seeded.
    private var available: Int = 0
    private var sampleInterval: TimeInterval = 1
    private var hoverFraction: CGFloat?
    private var envelopeMetric: Metric = .cpu
    private var fillMetric: Metric = .memory
    /// Looks up what was eating the machine at a moment in the past.
    var culpritLookup: ((TimeInterval) -> String?)?
    private var chipIndex: Int?
    private var lastStops: [RampStop] = []
    var reduceMotion = false
    var background: BandBackground = .none
    var showsAreaFill = false
    private var isHovered = false
    private var isOpen = false

    /// The translation animation is keyed to this, never to its own completion.
    private static let scrollKey = "sill.scroll"

    init() {
        container.masksToBounds = false
        container.actions = noImplicitAnimations
        waveLayer.actions = noImplicitAnimations
        scrollLayer.actions = noImplicitAnimations
        colorLayer.actions = noImplicitAnimations
        strandsLayer.actions = noImplicitAnimations
        fadeMask.actions = noImplicitAnimations

        // The scrolling layer has to be an ordinary layer: an animated
        // transform on a mask layer updates the presentation values but is not
        // composited, so the wave would step once per sample instead of gliding.
        colorLayer.mask = strandsLayer
        haloLayer.actions = noImplicitAnimations
        haloShapesLayer.actions = noImplicitAnimations
        haloLayer.mask = haloShapesLayer
        scrollLayer.addSublayer(haloLayer)
        scrollLayer.addSublayer(colorLayer)
        // A plate behind everything, when asked for: flat colour, no blur, so
        // nothing under it has to be recomposited.
        plate.actions = noImplicitAnimations
        plate.cornerRadius = BandBackground.cornerRadius
        plate.cornerCurve = .continuous
        plate.isHidden = true
        container.addSublayer(plate)

        // The area fill: the ramp, masked by an alpha ramp across the depth of
        // the band, masked in turn by the shape between the two envelopes — so
        // it is strongest at the lines and gone at the axis.
        areaColour.actions = noImplicitAnimations
        areaAlpha.actions = noImplicitAnimations
        areaShape.actions = noImplicitAnimations
        areaShape.fillColor = NSColor.white.cgColor
        areaShape.strokeColor = nil
        areaAlpha.mask = areaShape
        areaColour.mask = areaAlpha
        areaColour.isHidden = true

        // Only the strands age away: the mask goes on the wave layer, not on
        // the container, so the hover hint keeps its own opacity.
        scrollLayer.addSublayer(areaColour)
        waveLayer.addSublayer(scrollLayer)
        waveLayer.mask = fadeMask
        container.addSublayer(waveLayer)

        // The hint moves and dims with the wave, but does not fade with it.
        for layer in [chevronHalo, chevron] {
            layer.actions = noImplicitAnimations
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.opacity = 0
            container.addSublayer(layer)
        }

        // The scrub readout: what the machine was doing at the point under the
        // pointer. The band is already the record — this reads it back.
        chip.actions = noImplicitAnimations
        chip.cornerRadius = 7
        chip.cornerCurve = .continuous
        chip.borderWidth = 0.5
        chip.opacity = 0
        chipText.actions = noImplicitAnimations
        chipText.alignmentMode = .center
        chipText.truncationMode = .end
        chipText.font = NSFont.systemFont(ofSize: Self.chipFontSize, weight: .medium)
        chipText.fontSize = Self.chipFontSize
        chip.addSublayer(chipText)
        container.addSublayer(chip)

        shapes = (0..<WaveModel.strandCount).map { k in
            let shape = CAShapeLayer()
            shape.actions = noImplicitAnimations
            shape.fillColor = nil
            shape.strokeColor = NSColor.white.cgColor
            shape.lineWidth = WaveModel.lineWidth(strand: k)
            shape.opacity = Float(WaveModel.opacity(strand: k))
            shape.strokeColor = NSColor.white.cgColor
            shape.lineJoin = .round
            shape.lineCap = .round
            // No transform is ever applied to a shape layer, so strokes keep
            // their point width regardless of the band's size.
            strandsLayer.addSublayer(shape)
            return shape
        }

        // A hairline under each strand, in the backdrop's opposite tone. Same
        // paths, a little wider; no blur, so nine of them don't turn to mud.
        haloShapes = (0..<WaveModel.strandCount).map { _ in
            let shape = CAShapeLayer()
            shape.actions = noImplicitAnimations
            shape.fillColor = nil
            shape.strokeColor = NSColor.white.cgColor
            shape.lineJoin = .round
            shape.lineCap = .round
            haloShapesLayer.addSublayer(shape)
            return shape
        }
    }

    private var noImplicitAnimations: [String: CAAction] {
        ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(),
         "contents": NSNull(), "transform": NSNull(), "colors": NSNull(), "frame": NSNull()]
    }

    static let chipFontSize: CGFloat = 11
    private static let chipPadding = CGSize(width: 10, height: 6)

    /// Samples held, including one step of overflow at each end so the
    /// scrolling bundle never shows a gap.
    var sampleCount: Int {
        WaveGeometry.sampleCount(forLength: extendedLength)
    }

    private var extendedLength: CGFloat { length + 2 * WaveGeometry.step }

    private var transform: EdgeTransform {
        EdgeTransform(edge: edge, length: extendedLength)
    }

    func configure(edge: ScreenEdge, length: CGFloat, ramp: ColorRamp, scale: CGFloat,
                   backdropLuminance: Double, backdropVariation: Double = 0,
                   backdropProfile: [Double] = [],
                   envelopeMetric: Metric = .cpu, fillMetric: Metric = .memory) {
        self.envelopeMetric = envelopeMetric
        self.fillMetric = fillMetric
        self.edge = edge
        self.length = max(0, length)
        self.ramp = ramp
        self.style = Palette.style(ramp: ramp, backdropLuminance: backdropLuminance,
                                   backdropVariation: backdropVariation)
        self.profile = backdropProfile.isEmpty ? [backdropLuminance] : backdropProfile
        self.variation = backdropVariation
        let size = WaveGeometry.size(edge: edge, length: self.length)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The container's POSITION belongs to whoever placed the band — the
        // window now reaches past it for the hover readout — so only its size
        // is set here.
        container.contentsScale = scale
        container.bounds = CGRect(origin: .zero, size: size)
        for layer in [waveLayer, scrollLayer, fadeMask] {
            layer.contentsScale = scale
            layer.frame = CGRect(origin: .zero, size: size)
        }
        chip.contentsScale = scale
        chipText.contentsScale = scale

        // The bundle is drawn one sample longer at each end, so the band never
        // shows a gap while it scrolls.
        let step = WaveGeometry.step
        plate.frame = CGRect(origin: .zero, size: size)
        plate.contentsScale = scale
        colorLayer.frame = edge.isVertical
            ? CGRect(x: 0, y: -step, width: size.width, height: extendedLength)
            : CGRect(x: -step, y: 0, width: extendedLength, height: size.height)
        colorLayer.contentsScale = scale
        for layer in [areaColour, areaAlpha] {
            layer.frame = colorLayer.frame
            layer.contentsScale = scale
        }
        areaShape.frame = areaColour.bounds
        areaShape.contentsScale = scale
        haloLayer.frame = colorLayer.frame
        haloLayer.contentsScale = scale
        haloShapesLayer.frame = haloLayer.bounds
        haloShapesLayer.contentsScale = scale
        strandsLayer.frame = colorLayer.bounds
        strandsLayer.contentsScale = scale
        for shape in shapes {
            shape.frame = strandsLayer.bounds
            shape.contentsScale = scale
        }

        for (k, shape) in shapes.enumerated() {
            shape.lineWidth = style.lineWidth(strand: k)
            shape.opacity = Float(style.opacity(strand: k))
        }
        for (k, shape) in haloShapes.enumerated() {
            shape.frame = haloShapesLayer.bounds
            shape.contentsScale = scale
            shape.lineWidth = style.haloWidth(strand: k)
            shape.opacity = Float(style.haloAlpha(strand: k))
        }
        lastDepths = []          // geometry changed; the cached comparison is void
        lastStops = []
        applyRamp()
        applyFade()
        applyPlate()
        applyChevron()
        CATransaction.commit()
    }

    private func applyRamp() {
        // Colour is load, not age: each slice is the ramp read at the CPU
        // figure recorded there, toned for the wallpaper underneath it.
        let stops = Palette.paddedStops(Palette.gradientStops(ramp: ramp, loads: loads,
                                                              profile: profile))
        // On a quiet machine the colours are the same second after second;
        // handing Core Animation an identical array still costs a commit.
        if stops != lastStops {
            lastStops = stops
            colorLayer.colors = stops.map { $0.cgColor }
            colorLayer.locations = Palette.locations(count: stops.count)
                .map { NSNumber(value: Double($0)) }
        }
        let halo = Palette.paddedStops(Palette.haloStops(profile: profile))
        haloLayer.colors = halo.map { $0.cgColor }
        haloLayer.locations = Palette.locations(count: halo.count)
            .map { NSNumber(value: Double($0)) }
        let unit = unitAxis
        for layer in [colorLayer, haloLayer, areaColour] {
            layer.startPoint = unit.start
            layer.endPoint = unit.end
        }
        areaColour.colors = stops.map { $0.cgColor }
        areaColour.locations = colorLayer.locations
        // Across the band rather than along it: solid at each envelope, gone at
        // the axis, so the fill reads as depth rather than as a slab.
        areaAlpha.colors = [CGColor(gray: 0, alpha: 0.5), CGColor(gray: 0, alpha: 0),
                            CGColor(gray: 0, alpha: 0.5)]
        areaAlpha.locations = [0, 0.5, 1]
        areaAlpha.startPoint = edge.isVertical ? CGPoint(x: 0, y: 0.5) : CGPoint(x: 0.5, y: 0)
        areaAlpha.endPoint = edge.isVertical ? CGPoint(x: 1, y: 0.5) : CGPoint(x: 0.5, y: 1)
    }

    private func applyFade() {
        // Per-slice, so a bright patch of wallpaper keeps its strands legible
        // even at the old end of the band.
        let alphas = Fade.profileAlphas(profile: profile)
        fadeMask.colors = alphas.map { CGColor(gray: 0, alpha: $0) }
        fadeMask.locations = Palette.locations(count: alphas.count)
            .map { NSNumber(value: Double($0)) }
        let unit = unitAxis
        fadeMask.startPoint = unit.start
        fadeMask.endPoint = unit.end
    }

    /// Unit-space gradient axis, newest end to oldest end.
    private var unitAxis: (start: CGPoint, end: CGPoint) {
        edge.isVertical ? (CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1))
                        : (CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5))
    }

    /// The chevron hints that the band opens, and which way. It never animates
    /// its shape — only its opacity — so it costs nothing while idle.
    private func applyChevron() {
        let size = WaveGeometry.size(edge: edge, length: length)
        let path = Affordance.path(edge: edge, size: size, pointsInboard: !isOpen)
        // The hint sits at the middle of the band, so it follows the wallpaper
        // there rather than the band's average.
        let middle = profile.isEmpty ? Palette.assumedLuminance : profile[profile.count / 2]
        let local = Palette.style(ramp: ramp, backdropLuminance: middle,
                                  backdropVariation: variation)
        let colour = Affordance.color(style: local)
        chevron.frame = CGRect(origin: .zero, size: size)
        chevron.path = path
        chevron.lineWidth = Affordance.lineWidth
        chevron.strokeColor = colour.cgColor
        // Same contrast trick as the strands, so the hint survives a busy
        // wallpaper too.
        chevronHalo.frame = chevron.frame
        chevronHalo.path = path
        chevronHalo.lineWidth = Affordance.lineWidth + local.haloWidthBoost
        chevronHalo.strokeColor = local.haloColor.cgColor
    }

    /// Pointer entered, moved along, or left the band.
    ///
    /// `alongFraction` is 0 at the oldest end and 1 at the newest.
    func setHovered(_ hovered: Bool, open: Bool, alongFraction: CGFloat? = nil) {
        if hovered, let alongFraction, alongFraction != hoverFraction {
            hoverFraction = alongFraction
            updateChip()
        }
        guard hovered != isHovered || open != isOpen else { return }
        let directionChanged = open != isOpen
        isHovered = hovered
        isOpen = open
        if directionChanged {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyChevron()
            CATransaction.commit()
        }

        let target: Float = hovered ? 1 : 0
        let duration = hovered ? Affordance.fadeInDuration : Affordance.fadeOutDuration
        if hovered { updateChip(force: true) }
        CATransaction.begin()
        CATransaction.setDisableActions(reduceMotion)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for layer in [chevron, chevronHalo, chip] {
            if !reduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
                fade.toValue = target
                fade.duration = duration
                fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(fade, forKey: "hover")
            }
            layer.opacity = target
        }
        CATransaction.commit()
    }

    /// The optional plate behind the band.
    private func applyPlate() {
        let lightness = CGFloat(Palette.lightness(backdropLuminance:
            profile.isEmpty ? Palette.assumedLuminance : profile[profile.count / 2]))
        let alpha = background.plateAlpha(lightness: lightness)
        plate.isHidden = alpha <= 0
        // Which way the plate goes is the user's choice now, not a guess from
        // the wallpaper: Light is pale over anything, Dark is ink over anything.
        plate.backgroundColor = background.isPale
            ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
            : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
        areaColour.isHidden = !showsAreaFill
    }

    /// Places and fills the hover readout for the current pointer position.
    private func updateChip(force: Bool = false) {
        guard let fraction = hoverFraction, !history.cpu.isEmpty else { return }
        // A young band leaves the old end of the strip blank. There is nothing
        // to read back there, so the readout stays away rather than reporting
        // the oldest sample it does have for a moment it never saw.
        let drawn = min(sampleCount, max(0, available))
        let blankUntil = sampleCount > 0 ? 1 - CGFloat(drawn) / CGFloat(sampleCount) : 0
        chip.isHidden = fraction < blankUntil - 0.001
        guard !chip.isHidden else { return }
        // Only the samples this band has room for are on screen to point at.
        // Only as far back as the band actually draws: on a young band that is
        // fewer samples than the strip is long.
        let index = Scrub.index(alongFraction: fraction, count: history.cpu.count,
                                visible: min(sampleCount, max(2, drawn)))
        // A pointer sliding along the band crosses many pixels per sample:
        // re-measuring and re-committing for each of them is wasted work.
        guard force || index != chipIndex else { return }
        chipIndex = index
        let memory = index < history.memory.count ? history.memory[index] : 0
        let age = Scrub.age(index: index, count: history.cpu.count, interval: sampleInterval)
        let text = Scrub.label(envelope: history.cpu[index], fill: memory, secondsAgo: age,
                               envelopeMetric: envelopeMetric, fillMetric: fillMetric)
        // Name a culprit only for a sample that was actually under load.
        // Only a CPU envelope can name a culprit: the process list explains
        // processor time, not bytes on the wire.
        let busy = envelopeMetric == .cpu && history.cpu[index] >= SpikeLog.attributionFloor
        let labelled = (busy ? culpritLookup?(age) : nil).map { "\(text) · \($0)" } ?? text

        let font = NSFont.systemFont(ofSize: Self.chipFontSize, weight: .medium)
        let measured = (labelled as NSString).size(withAttributes: [.font: font])
        let size = CGSize(width: ceil(measured.width) + Self.chipPadding.width * 2,
                          height: ceil(measured.height) + Self.chipPadding.height * 2)

        // Band-local: the pointer's position along the axis, mapped back out.
        let bandSize = WaveGeometry.size(edge: edge, length: length)
        let along = edge.isVertical ? (1 - fraction) * bandSize.height
                                    : (1 - fraction) * bandSize.width
        let chipFrame = Layout.scrubChipFrame(edge: edge, bandSize: bandSize,
                                              alongPoint: along, chipSize: size)

        let local = Palette.style(ramp: ramp, backdropLuminance:
                                    profile.isEmpty ? Palette.assumedLuminance
                                                    : profile[profile.count / 2],
                                  backdropVariation: variation)
        let ink = Affordance.color(style: local)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        chip.frame = chipFrame
        chip.backgroundColor = local.haloColor.cgColor
        chip.borderColor = CGColor(gray: ink.red, alpha: 0.18)
        chipText.frame = CGRect(x: 0, y: (size.height - measured.height) / 2 - 1,
                                width: size.width, height: measured.height + 2)
        chipText.contentsScale = chip.contentsScale
        chipText.string = labelled
        chipText.foregroundColor = ink.cgColor
        CATransaction.commit()
        Debug.log("chip '\(labelled)' frame=\(chipFrame.debugDescription) "
                  + "opacity=\(chip.opacity) band=\(bandSize.debugDescription) "
                  + "super=\(chip.superlayer != nil)")
    }

    /// New sample arrived: redraw the paths, then hand the scroll to Core Animation.
    /// `tickTime` is the CACurrentMediaTime() of the sample, so the animation
    /// stays in phase with the timer even if this call is late.
    func update(frame: WaveModel.Frame, interval: TimeInterval, tickTime: CFTimeInterval) {
        if let presented = scrollLayer.presentation()?.transform {
            Debug.log(String(format: "before update: translation (%.2f, %.2f)",
                             presented.m41, presented.m42))
        }
        history = (frame.cpu, frame.memory)
        available = frame.available
        if interval > 0 { sampleInterval = interval }
        if hoverFraction != nil, isHovered { updateChip(force: true) }
        let depths = frame.depths

        // An idle machine draws the identical flat band second after second.
        // Nothing to redraw, and scrolling a straight line moves nothing on
        // screen — so the whole frame is skipped, animation included.
        if !lastDepths.isEmpty, Self.matches(depths, lastDepths) { return }
        lastDepths = depths

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        loads = frame.loads
        applyRamp()
        // Only the samples this band has room for, built inside SillCore so the
        // generic collection work specializes.
        let paths = frame.paths(transform: transform, sampleCount: sampleCount)
        if showsAreaFill, let top = depths.first, let bottom = depths.last {
            let wanted = sampleCount
            areaShape.path = Curve.areaPath(
                top: top.count > wanted ? top.suffix(wanted) : top[top.startIndex...],
                bottom: bottom.count > wanted ? bottom.suffix(wanted)
                                              : bottom[bottom.startIndex...],
                transform: transform)
        }
        for (k, shape) in shapes.enumerated() where k < paths.count {
            shape.path = paths[k]
            if k < haloShapes.count { haloShapes[k].path = paths[k] }
        }
        scrollLayer.removeAnimation(forKey: Self.scrollKey)
        scrollLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        guard !reduceMotion, interval > 0 else { return }
        let scroll = transform.scrollPerSample
        let vertical = edge.isVertical
        let animation = CABasicAnimation(keyPath: vertical ? "transform.translation.y"
                                                           : "transform.translation.x")
        animation.fromValue = 0
        animation.toValue = vertical ? scroll.dy : scroll.dx
        animation.duration = interval
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        // Anchor to the sample's own timestamp rather than to "now".
        animation.beginTime = tickTime
        scrollLayer.add(animation, forKey: Self.scrollKey)
        Debug.log("scroll \(vertical ? scroll.dy : scroll.dx)pt over \(interval)s")
    }

    /// Equal to within a fifth of a point — below what a Retina pixel shows.
    private static func matches(_ a: [[Double]], _ b: [[Double]]) -> Bool {
        guard a.count == b.count else { return false }
        for (left, right) in zip(a, b) {
            guard left.count == right.count else { return false }
            for i in left.indices where abs(left[i] - right[i]) > 0.2 { return false }
        }
        return true
    }

    func setDimmed(_ dimmed: Bool, animated: Bool = true) {
        let target: Float = dimmed ? 0.62 : 1
        guard container.opacity != target else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.3)
        container.opacity = target
        CATransaction.commit()
    }
}
