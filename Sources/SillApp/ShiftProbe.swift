import CoreGraphics
import Foundation
import SillCore

/// Measures how far the wave actually moved between two screenshots, by
/// finding the horizontal or vertical offset that best matches them.
///
/// Used to check that the scroll is continuous: equal steps between frames,
/// including across a sample boundary.
enum ShiftProbe {
    static func run(paths: [String], vertical: Bool, maxShift: Int) {
        let images = paths.compactMap { WaveRenderer.read(URL(fileURLWithPath: $0)) }
        guard images.count == paths.count, images.count > 1 else {
            print("could not read all images")
            return
        }
        for i in 1..<images.count {
            guard let shift = bestShift(images[i - 1], images[i],
                                        vertical: vertical, maxShift: maxShift) else {
                print("\(paths[i - 1]) -> \(paths[i]): no match")
                continue
            }
            print(String(format: "%@ -> %@: %+d px (score %.5f)",
                         (paths[i - 1] as NSString).lastPathComponent,
                         (paths[i] as NSString).lastPathComponent, shift.offset, shift.score))
        }
    }

    static func bestShift(_ a: CGImage, _ b: CGImage, vertical: Bool,
                          maxShift: Int) -> (offset: Int, score: Double)? {
        guard a.width == b.width, a.height == b.height,
              let pixelsA = gray(a), let pixelsB = gray(b) else { return nil }
        let width = a.width, height = a.height
        var best: (offset: Int, score: Double)?
        for shift in -maxShift...maxShift {
            var total = 0.0
            var count = 0
            for y in 0..<height {
                for x in 0..<width {
                    let source = vertical ? (y: y - shift, x: x) : (y: y, x: x - shift)
                    guard source.x >= 0, source.x < width, source.y >= 0, source.y < height
                    else { continue }
                    total += abs(pixelsB[y * width + x] - pixelsA[source.y * width + source.x])
                    count += 1
                }
            }
            guard count > 0 else { continue }
            let score = total / Double(count)
            if best == nil || score < best!.score { best = (shift, score) }
        }
        return best
    }

    /// Mean luminance of an image, for watching a fade progress.
    static func meanLuminance(_ image: CGImage) -> Double? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = data.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: WaveRenderer.colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0.0
        for i in 0..<(width * height) {
            total += Palette.luminance(red: Double(data[i * 4]) / 255,
                                       green: Double(data[i * 4 + 1]) / 255,
                                       blue: Double(data[i * 4 + 2]) / 255)
        }
        return total / Double(width * height)
    }

    /// Isolates the wave from the wallpaper behind it: the strands are
    /// saturated, a photographic desktop is not. Correlating on raw luminance
    /// just locks onto the (stationary) wallpaper texture.
    private static func gray(_ image: CGImage) -> [Double]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = data.withUnsafeMutableBytes({ buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: WaveRenderer.colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (0..<(width * height)).map { i in
            let r = Double(data[i * 4]), g = Double(data[i * 4 + 1]), b = Double(data[i * 4 + 2])
            let saturation = (max(r, max(g, b)) - min(r, min(g, b))) / 255
            return saturation
        }
    }
}
