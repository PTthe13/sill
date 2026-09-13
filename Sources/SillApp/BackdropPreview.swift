import AppKit
import CoreGraphics
import ImageIO
import SillCore

/// Composites the wave over the real wallpaper of each display, so contrast can
/// be judged without needing an uncovered desktop.
enum BackdropPreview {
    static func write(to directory: URL, ramps: [ColorRamp], edge: ScreenEdge,
                      fraction: CGFloat = WaveGeometry.defaultLengthFraction,
                      affordance: Bool? = nil,
                      background: BandBackground = .none, areaFill: Bool = false) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for screen in NSScreen.screens {
            let info = Screens.info(for: screen)
            let band = Layout.waveFrame(edge: edge, visibleFrame: info.visibleFrame,
                                        fraction: fraction, screenFrame: info.frame)
            let sample = Backdrop.measure(screen: screen, rect: band, edge: edge)
                .behind(background)
            for ramp in ramps {
                guard let image = composite(screen: screen, band: band, ramp: ramp, edge: edge,
                                            sample: sample, affordance: affordance,
                                            background: background, areaFill: areaFill)
                else { continue }
                let name = info.name.replacingOccurrences(of: " ", with: "-")
                let url = directory.appendingPathComponent("\(name)-\(ramp.rawValue).png")
                WaveRenderer.write(image, to: url)
            }
        }
        print("wrote previews to \(directory.path)")
    }

    private static func composite(screen: NSScreen, band: CGRect, ramp: ColorRamp,
                                  edge: ScreenEdge, sample: BackdropSample,
                                  affordance: Bool?, background: BandBackground = .none,
                                  areaFill: Bool = false) -> CGImage? {
        let scale: CGFloat = 2
        let size = band.size
        guard let context = CGContext(data: nil,
                                      width: Int(size.width * scale),
                                      height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: WaveRenderer.colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)

        // Whatever the wallpaper puts behind the band, at the same crop.
        if let wallpaper = Backdrop.crop(screen: screen, rect: band) {
            context.draw(wallpaper, in: CGRect(origin: .zero, size: size))
        } else {
            context.setFillColor(CGColor(gray: CGFloat(sample.luminance), alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }

        let length = edge.isVertical ? size.height : size.width
        let count = WaveGeometry.sampleCount(forLength: length + 2 * WaveGeometry.step)
        var options = WaveRenderer.Options(edge: edge, ramp: ramp, length: length, scale: scale)
        options.style = Palette.style(ramp: ramp, backdropLuminance: sample.luminance,
                                      backdropVariation: sample.variation)
        options.affordance = affordance
        options.profile = sample.profile
        options.plate = background
        options.areaFill = areaFill
        guard let wave = WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                                            memory: Fixtures.memory(count: count),
                                            options: options) else { return context.makeImage() }
        context.draw(wave, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
