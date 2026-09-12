import CoreGraphics
import Foundation
import SillCore

/// Draws the app icon: the wave itself, on the dark ledge it lives against.
enum IconRenderer {
    static func image(size: CGFloat) -> CGImage? {
        guard let context = CGContext(data: nil, width: Int(size), height: Int(size),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: WaveRenderer.colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // macOS leaves a margin around the artwork inside the icon canvas.
        let inset = size * 0.09
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let radius = rect.width * 0.2237
        let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                           transform: nil)
        context.addPath(shape)
        context.clip()
        if let background = CGGradient(colorsSpace: WaveRenderer.colorSpace,
                                       colors: [CGColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1),
                                                CGColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1)] as CFArray,
                                       locations: [0, 1]) {
            context.drawLinearGradient(background, start: CGPoint(x: 0, y: rect.maxY),
                                       end: CGPoint(x: 0, y: rect.minY), options: [])
        }

        // Drawn at half size and scaled up, so the strands read as strands
        // rather than hairlines at 32pt.
        let bandLength = rect.width * 0.86
        let drawnLength = bandLength / 2
        let count = WaveGeometry.sampleCount(forLength: drawnLength + 2 * WaveGeometry.step)
        guard let wave = WaveRenderer.image(
            cpu: Fixtures.cpu(count: count), memory: Fixtures.memory(count: count),
            options: WaveRenderer.Options(edge: .top, ramp: .load, length: drawnLength, scale: 2))
        else { return context.makeImage() }

        let bandHeight = WaveGeometry.thickness * (bandLength / drawnLength) * 1.15
        context.draw(wave, in: CGRect(x: rect.midX - bandLength / 2,
                                      y: rect.midY - bandHeight / 2,
                                      width: bandLength, height: bandHeight))
        return context.makeImage()
    }

    static func writeIconset(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                   (256, 1), (256, 2), (512, 1), (512, 2)]
        for (points, scale) in sizes {
            guard let image = image(size: CGFloat(points * scale)) else { continue }
            let suffix = scale == 1 ? "" : "@2x"
            let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
            WaveRenderer.write(image, to: url)
        }
    }
}
