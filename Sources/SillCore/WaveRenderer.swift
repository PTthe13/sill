import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the wave offscreen, exactly as the layer tree does: colour gradient
/// along the time axis, clipped to the nine strokes, then the age fade.
///
/// Used by the golden-image tests, so a refactor can't silently change how the
/// wave looks.
public enum WaveRenderer {
    /// sRGB, or the device space if sRGB is somehow unavailable.
    public static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    public struct Options {
        public var edge: ScreenEdge
        public var ramp: ColorRamp
        public var length: CGFloat
        public var scale: CGFloat
        public var background: CGColor?
        public var style: WaveStyle
        /// Backdrop luminance slice by slice, newest end first. One entry (or
        /// none) means a single tone for the whole band.
        public var profile: [Double]
        /// How mixed the backdrop is, kept so local restyling can reuse it.
        public var variation: Double
        /// Draws the hover chevron: `nil` for none, true pointing inboard
        /// (closed), false pointing back out (open).
        public var affordance: Bool?
        /// The plate behind the strands, as opposed to `background`, which is
        /// the colour the test harness paints the whole image with.
        public var plate: BandBackground = .none
        public var areaFill = false

        public init(edge: ScreenEdge, ramp: ColorRamp, length: CGFloat = 240,
                    scale: CGFloat = 2, background: CGColor? = nil,
                    backdropLuminance: Double = Palette.assumedLuminance,
                    backdropVariation: Double = 0) {
            self.edge = edge
            self.ramp = ramp
            self.length = length
            self.scale = scale
            self.background = background
            self.style = Palette.style(ramp: ramp, backdropLuminance: backdropLuminance,
                                       backdropVariation: backdropVariation)
            self.affordance = nil
            self.profile = [backdropLuminance]
            self.variation = backdropVariation
        }
    }

    public static func image(cpu: [Double], memory: [Double], options: Options) -> CGImage? {
        let size = WaveGeometry.size(edge: options.edge, length: options.length)
        guard let context = makeContext(size: size, scale: options.scale),
              let strands = strandsImage(cpu: cpu, memory: memory, options: options),
              let mask = fadeMask(size: size, scale: options.scale, edge: options.edge,
                                  profile: options.profile.isEmpty ? [Palette.assumedLuminance]
                                                                   : options.profile)
        else { return nil }

        let rect = CGRect(origin: .zero, size: size)
        if let background = options.background {
            context.setFillColor(background)
            context.fill(rect)
        }
        drawPlate(in: context, rect: rect, options: options)
        context.saveGState()
        context.clip(to: rect, mask: mask)
        context.draw(strands, in: rect)
        context.restoreGState()

        // The hint is not data, so it is drawn after the age mask, not through it.
        if let pointsInboard = options.affordance {
            drawAffordance(in: context, size: size, options: options,
                           pointsInboard: pointsInboard)
        }
        return context.makeImage()
    }

    /// The optional plate behind the strands.
    private static func drawPlate(in context: CGContext, rect: CGRect, options: Options) {
        let luminance = options.profile.isEmpty ? Palette.assumedLuminance
            : options.profile[options.profile.count / 2]
        let lightness = CGFloat(Palette.lightness(backdropLuminance: luminance))
        let alpha = options.plate.plateAlpha(lightness: lightness)
        guard alpha > 0 else { return }
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: BandBackground.cornerRadius,
                               cornerHeight: BandBackground.cornerRadius, transform: nil))
        context.setFillColor(options.plate.isPale
            ? CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
            : CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha))
        context.fillPath()
        context.restoreGState()
    }

    private static func drawAffordance(in context: CGContext, size: CGSize,
                                       options: Options, pointsInboard: Bool) {
        // The hint follows the wallpaper where it actually sits: the middle of
        // the band, not the band's average.
        let middle = options.profile.isEmpty ? Palette.assumedLuminance
            : options.profile[options.profile.count / 2]
        let localStyle = Palette.style(ramp: options.ramp, backdropLuminance: middle,
                                       backdropVariation: options.variation)
        let path = Affordance.path(edge: options.edge, size: size,
                                   pointsInboard: pointsInboard)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(localStyle.haloColor.cgColor)
        context.setLineWidth(Affordance.lineWidth + localStyle.haloWidthBoost)
        context.addPath(path)
        context.strokePath()

        let colour = Affordance.color(style: localStyle)
        context.setStrokeColor(colour.cgColor)
        context.setLineWidth(Affordance.lineWidth)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private static func makeContext(size: CGSize, scale: CGFloat) -> CGContext? {
        let context = CGContext(data: nil,
                                width: Int(size.width * scale), height: Int(size.height * scale),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.scaleBy(x: scale, y: scale)
        context?.setLineJoin(.round)
        context?.setLineCap(.round)
        return context
    }

    /// The colour ramp, clipped to the stroked strands.
    private static func strandsImage(cpu: [Double], memory: [Double],
                                     options: Options) -> CGImage? {
        let size = WaveGeometry.size(edge: options.edge, length: options.length)
        guard let context = makeContext(size: size, scale: options.scale) else { return nil }
        let extended = options.length + 2 * WaveGeometry.step
        let transform = EdgeTransform(edge: options.edge, length: extended)
        let depths = WaveModel().allDepths(cpu: cpu, memory: memory)

        // The band shows a window onto a path one sample longer at each end.
        let offset = options.edge.isVertical
            ? CGAffineTransform(translationX: 0, y: -WaveGeometry.step)
            : CGAffineTransform(translationX: -WaveGeometry.step, y: 0)

        let axis = EdgeTransform(edge: options.edge, length: options.length).gradientAxis
        let toneProfile = options.profile.isEmpty ? [Palette.assumedLuminance] : options.profile
        let loads = Palette.sliceValues(history: Curve.smooth(cpu), count: Palette.profileSlices)
        let stops = Palette.paddedStops(Palette.gradientStops(ramp: options.ramp, loads: loads,
                                                              profile: toneProfile))
        guard let gradient = CGGradient(colorsSpace: colorSpace,
                                        colors: stops.map { $0.cgColor } as CFArray,
                                        locations: Palette.locations(count: stops.count))
        else { return nil }
        let haloStops = Palette.paddedStops(Palette.haloStops(profile: toneProfile))
        let haloGradient = CGGradient(colorsSpace: colorSpace,
                                      colors: haloStops.map { $0.cgColor } as CFArray,
                                      locations: Palette.locations(count: haloStops.count))

        var shift = offset
        var strandPaths: [(index: Int, path: CGPath)] = []
        for k in 0..<WaveModel.strandCount {
            guard let shifted = Curve.path(depths: depths[k], transform: transform)
                .copy(using: &shift) else { continue }
            strandPaths.append((k, shifted))
        }

        // The area fill sits under everything: strongest at the envelopes,
        // gone at the axis.
        if options.areaFill, let top = depths.first, let bottom = depths.last,
           let alphaGradient = CGGradient(
               colorsSpace: colorSpace,
               colors: [CGColor(gray: 1, alpha: 0.5), CGColor(gray: 1, alpha: 0),
                        CGColor(gray: 1, alpha: 0.5)] as CFArray,
               locations: [0, 0.5, 1]) {
            var shift = offset
            if let area = Curve.areaPath(top: top, bottom: bottom,
                                         transform: transform).copy(using: &shift) {
                context.saveGState()
                context.addPath(area)
                context.clip()
                // Colour along the band, fading across it.
                context.drawLinearGradient(gradient, start: axis.start, end: axis.end,
                                           options: [.drawsBeforeStartLocation,
                                                     .drawsAfterEndLocation])
                context.setBlendMode(.destinationIn)
                let across = options.edge.isVertical
                    ? (CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0))
                    : (CGPoint(x: 0, y: 0), CGPoint(x: 0, y: size.height))
                context.drawLinearGradient(alphaGradient, start: across.0, end: across.1,
                                           options: [])
                context.restoreGState()
            }
        }

        // Contrast hairline first, so the coloured strand sits on top of it.
        for (k, shifted) in strandPaths {
            let halo = shifted.copy(strokingWithWidth: options.style.haloWidth(strand: k),
                                    lineCap: .round, lineJoin: .round, miterLimit: 10)
            context.saveGState()
            context.setAlpha(options.style.haloAlpha(strand: k))
            context.addPath(halo)
            context.clip()
            if let haloGradient {
                context.drawLinearGradient(haloGradient, start: axis.start, end: axis.end,
                                           options: [.drawsBeforeStartLocation,
                                                     .drawsAfterEndLocation])
            } else {
                context.setFillColor(options.style.haloColor.cgColor)
                context.fill(CGRect(origin: .zero, size: size))
            }
            context.restoreGState()
        }

        for (k, shifted) in strandPaths {
            let path = shifted.copy(strokingWithWidth: options.style.lineWidth(strand: k),
                                    lineCap: .round, lineJoin: .round, miterLimit: 10)
            context.saveGState()
            context.setAlpha(options.style.opacity(strand: k))
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(gradient, start: axis.start, end: axis.end,
                                       options: [.drawsBeforeStartLocation,
                                                 .drawsAfterEndLocation])
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// Grayscale ramp used to fade the band with age.
    private static func fadeMask(size: CGSize, scale: CGFloat, edge: ScreenEdge,
                                 profile: [Double]) -> CGImage? {
        guard let context = CGContext(data: nil,
                                      width: Int(size.width * scale),
                                      height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let alphas = Fade.profileAlphas(profile: profile)
        let colors = alphas.map { CGColor(gray: $0, alpha: 1) } as CFArray
        let locations = Palette.locations(count: alphas.count)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                        colors: colors, locations: locations) else { return nil }
        let axis = EdgeTransform(edge: edge, length: edge.isVertical ? size.height : size.width)
            .gradientAxis
        context.drawLinearGradient(gradient, start: axis.start, end: axis.end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return context.makeImage()
    }

    @discardableResult
    public static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    public static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Mean absolute per-channel difference, 0...1. Zero means identical.
    public static func difference(_ a: CGImage, _ b: CGImage) -> Double? {
        guard a.width == b.width, a.height == b.height else { return nil }
        guard let pixelsA = pixels(a), let pixelsB = pixels(b),
              pixelsA.count == pixelsB.count else { return nil }
        var total = 0.0
        for i in 0..<pixelsA.count {
            total += Double(abs(Int(pixelsA[i]) - Int(pixelsB[i])))
        }
        return total / Double(pixelsA.count) / 255
    }

    /// Mean luminance of an image, for measuring what a change actually did.
    public static func meanLuminance(_ image: CGImage) -> Double? {
        guard let data = pixels(image), !data.isEmpty else { return nil }
        var total = 0.0
        let count = data.count / 4
        for i in 0..<count {
            total += Palette.luminance(red: Double(data[i * 4]) / 255,
                                       green: Double(data[i * 4 + 1]) / 255,
                                       blue: Double(data[i * 4 + 2]) / 255)
        }
        return count > 0 ? total / Double(count) : nil
    }

    /// Mean absolute deviation of each pixel's luminance from `backdrop`.
    ///
    /// The honest measure of how much a band stands off its wallpaper: a dark
    /// strand and the light hairline beside it both count, where a regional
    /// average would let them cancel each other out.
    public static func meanDeviation(_ image: CGImage, from backdrop: Double) -> Double? {
        guard let data = pixels(image), !data.isEmpty else { return nil }
        let count = data.count / 4
        var total = 0.0
        for i in 0..<count {
            let luma = Palette.luminance(red: Double(data[i * 4]) / 255,
                                         green: Double(data[i * 4 + 1]) / 255,
                                         blue: Double(data[i * 4 + 2]) / 255)
            total += abs(luma - backdrop)
        }
        return count > 0 ? total / Double(count) : nil
    }

    private static func pixels(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = data.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}
