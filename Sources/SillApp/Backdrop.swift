import AppKit
import CoreGraphics
import ImageIO
import SillCore

/// Measures how light the desktop is behind the band.
///
/// Reads the wallpaper file rather than capturing the screen, so it needs no
/// Screen Recording permission and costs nothing to repeat.
/// What the wallpaper does behind the band.
struct BackdropSample: Equatable {
    var luminance: Double
    /// Spread of luminance across the band: a photograph scores high, a plain
    /// colour scores zero.
    var variation: Double
    /// Luminance slice by slice along the band, newest end first — what lets
    /// the strands darken over a bright stretch of wallpaper and lighten over
    /// a dark one, rather than picking one tone for the whole band.
    var profile: [Double]

    static let unknown = BackdropSample(luminance: Palette.assumedLuminance, variation: 0,
                                        profile: [Palette.assumedLuminance])

    /// The same measurement, as seen through a plate: with something opaque
    /// behind the band, the wallpaper underneath stops mattering.
    func behind(_ background: BandBackground) -> BackdropSample {
        guard background != .none else { return self }
        let tone = background.effectiveLuminance(wallpaper: luminance)
        return BackdropSample(luminance: tone, variation: 0,
                              profile: [Double](repeating: tone, count: profile.count))
    }
}

enum Backdrop {
    private static var cache: [String: (url: URL, luminance: BackdropSample)] = [:]

    /// Mean luminance of the wallpaper under `rect` (screen coordinates).
    /// Falls back to a dark assumption when the wallpaper can't be read.
    static func measure(screen: NSScreen, rect: CGRect, edge: ScreenEdge) -> BackdropSample {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return .unknown
        }
        // Keyed on the file's modification date too, so a wallpaper that is
        // replaced in place (or a dynamic desktop shifting through the day) is
        // noticed, while an unchanged one costs a stat call.
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(rect.integral.debugDescription)"
        if let cached = cache[key], cached.url == url { return cached.luminance }
        guard let image = loadImage(url) else { return .unknown }

        // Wallpapers are drawn to fill the screen, centred and cropped.
        let screenFrame = screen.frame
        let imageSize = CGSize(width: image.width, height: image.height)
        guard screenFrame.width > 0, screenFrame.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return .unknown }
        let scale = max(screenFrame.width / imageSize.width,
                        screenFrame.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: screenFrame.midX - drawn.width / 2,
                             y: screenFrame.midY - drawn.height / 2)

        // Band rect -> image pixels, with y flipped (images are top-down).
        let inImage = CGRect(x: (rect.minX - origin.x) / scale,
                             y: (drawn.height - (rect.maxY - origin.y)) / scale,
                             width: rect.width / scale,
                             height: rect.height / scale)
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard !inImage.isNull, inImage.width >= 1, inImage.height >= 1,
              let crop = image.cropping(to: inImage.integral),
              let value = measure(crop, edge: edge) else { return .unknown }

        cache[key] = (url, value)
        return value
    }

    static func invalidate() { cache.removeAll() }

    /// The part of the wallpaper that sits under `rect`, at wallpaper resolution.
    static func crop(screen: NSScreen, rect: CGRect) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let screenFrame = screen.frame
        let imageSize = CGSize(width: image.width, height: image.height)
        guard screenFrame.width > 0, imageSize.width > 0 else { return nil }
        let scale = max(screenFrame.width / imageSize.width,
                        screenFrame.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: screenFrame.midX - drawn.width / 2,
                             y: screenFrame.midY - drawn.height / 2)
        let inImage = CGRect(x: (rect.minX - origin.x) / scale,
                             y: (drawn.height - (rect.maxY - origin.y)) / scale,
                             width: rect.width / scale,
                             height: rect.height / scale)
            .intersection(CGRect(origin: .zero, size: imageSize))
        guard !inImage.isNull, inImage.width >= 1, inImage.height >= 1 else { return nil }
        return image.cropping(to: inImage.integral)
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Mean of the perceived luminance, nudged toward the *lightest* parts — a
    /// band that is half dark photo and half bright sky still has to stay
    /// readable across the bright half — plus how far the two extremes sit apart.
    private static func measure(_ image: CGImage, edge: ScreenEdge) -> BackdropSample? {
        // Enough resolution along the band to follow the wallpaper, and a few
        // pixels across it.
        let slices = Palette.profileSlices
        let width = edge.isVertical ? 6 : slices
        let height = edge.isVertical ? slices : 6
        guard width > 0, height > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = data.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: WaveRenderer.colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        func luminance(x: Int, y: Int) -> Double {
            let i = (y * width + x) * 4
            return Palette.luminance(red: Double(data[i]) / 255,
                                     green: Double(data[i + 1]) / 255,
                                     blue: Double(data[i + 2]) / 255)
        }

        // One reading per slice, biased toward the lighter pixels in it: the
        // bright part of a slice is what defeats a pale strand.
        var profile: [Double] = []
        profile.reserveCapacity(slices)
        for slice in 0..<slices {
            var across: [Double] = []
            for other in 0..<(edge.isVertical ? width : height) {
                across.append(edge.isVertical ? luminance(x: other, y: slice)
                                              : luminance(x: slice, y: other))
            }
            guard !across.isEmpty else { continue }
            let mean = across.reduce(0, +) / Double(across.count)
            let brightest = across.max() ?? mean
            profile.append(mean * 0.6 + brightest * 0.4)
        }
        guard !profile.isEmpty else { return nil }

        // The bitmap is top-down and left-to-right; the profile runs from the
        // newest end of the band, which is the bottom on a vertical edge.
        if edge.isVertical { profile.reverse() }

        let mean = profile.reduce(0, +) / Double(profile.count)
        let sorted = profile.sorted()
        let upperQuartile = sorted[min(sorted.count - 1, sorted.count * 3 / 4)]
        let variance = profile.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(profile.count)
        return BackdropSample(luminance: mean * 0.55 + upperQuartile * 0.45,
                              variation: Palette.variation(standardDeviation: variance.squareRoot()),
                              profile: profile)
    }
}
