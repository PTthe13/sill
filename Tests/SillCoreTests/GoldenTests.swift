import CoreGraphics
import Foundation
@testable import SillCore

/// Golden images: one per edge x ramp, so a refactor can't quietly change how
/// the wave looks. Regenerate deliberately with `swift run sill --render Tests/Golden`.
struct GoldenTests {
    static let length: CGFloat = 240
    static let tolerance = 0.002

    var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // SillCoreTests
            .deletingLastPathComponent()      // Tests
            .appendingPathComponent("Golden")
    }

    /// The two backdrops the goldens cover: the dark wallpaper the ramps were
    /// designed for, and a light busy one.
    static let backdrops: [(folder: String, luminance: Double, variation: Double)] = [
        ("", Palette.assumedLuminance, 0),
        ("light", 0.85, 1),
    ]

    func render(edge: ScreenEdge, ramp: ColorRamp,
                luminance: Double = Palette.assumedLuminance,
                variation: Double = 0) -> CGImage? {
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        return WaveRenderer.image(
            cpu: Fixtures.cpu(count: count),
            memory: Fixtures.memory(count: count),
            options: WaveRenderer.Options(edge: edge, ramp: ramp, length: Self.length, scale: 2,
                                          backdropLuminance: luminance,
                                          backdropVariation: variation))
    }

    func everyEdgeAndRampMatchesItsGolden() {
        for backdrop in Self.backdrops {
            for edge in ScreenEdge.allCases {
                for ramp in ColorRamp.allCases {
                    let name = "\(edge.rawValue)-\(ramp.rawValue)"
                    guard let rendered = render(edge: edge, ramp: ramp,
                                                luminance: backdrop.luminance,
                                                variation: backdrop.variation) else {
                        expect(false, "\(name): nothing rendered")
                        continue
                    }
                    let folder = backdrop.folder.isEmpty ? directory
                        : directory.appendingPathComponent(backdrop.folder)
                    let url = folder.appendingPathComponent("\(name).png")
                    guard let golden = WaveRenderer.read(url) else {
                        expect(false, "\(name): missing golden at \(url.path)")
                        continue
                    }
                    guard let difference = WaveRenderer.difference(rendered, golden) else {
                        expect(false, "\(name): size mismatch")
                        continue
                    }
                    expect(difference < Self.tolerance,
                           "\(backdrop.folder)/\(name): differs from golden by \(difference)")
                }
            }
        }
    }

    func theLightBackdropSetActuallyDiffersFromTheDarkOne() {
        for edge in ScreenEdge.allCases {
            for ramp in ColorRamp.allCases {
                let onDark = render(edge: edge, ramp: ramp)
                let onLight = render(edge: edge, ramp: ramp, luminance: 0.85, variation: 1)
                guard let onDark, let onLight,
                      let difference = WaveRenderer.difference(onDark, onLight) else {
                    expect(false, "\(edge.rawValue)-\(ramp.rawValue): nothing rendered")
                    continue
                }
                expect(difference > 0.01,
                       "\(edge.rawValue)-\(ramp.rawValue) looks the same on both backdrops")
            }
        }
    }

    func theOptionalTreatmentsMatchTheirGoldens() {
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        for edge in ScreenEdge.allCases {
            for (name, plate, fill) in [("dark", BandBackground.shade, false),
                                        ("area", BandBackground.none, true)] {
                var options = WaveRenderer.Options(edge: edge, ramp: .load,
                                                   length: Self.length, scale: 2)
                options.plate = plate
                options.areaFill = fill
                guard let rendered = WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                                                        memory: Fixtures.memory(count: count),
                                                        options: options),
                      let golden = WaveRenderer.read(directory
                        .appendingPathComponent("options/\(edge.rawValue)-\(name).png")),
                      let difference = WaveRenderer.difference(rendered, golden) else {
                    expect(false, "options/\(edge.rawValue)-\(name): missing")
                    continue
                }
                expect(difference < Self.tolerance,
                       "options/\(edge.rawValue)-\(name) differs by \(difference)")
            }
        }
    }

    func eachOptionalTreatmentActuallyChangesThePicture() {
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        func render(_ configure: (inout WaveRenderer.Options) -> Void) -> CGImage? {
            var options = WaveRenderer.Options(edge: .right, ramp: .load,
                                               length: Self.length, scale: 2)
            configure(&options)
            return WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                                      memory: Fixtures.memory(count: count), options: options)
        }
        guard let plain = render({ _ in }),
              let dark = render({ $0.plate = .shade }),
              let filled = render({ $0.areaFill = true }) else {
            expect(false, "nothing rendered")
            return
        }
        expect((WaveRenderer.difference(plain, dark) ?? 0) > 0.01, "the plate drew nothing")
        expect((WaveRenderer.difference(plain, filled) ?? 0) > 0.004, "the fill drew nothing")
        expect((WaveRenderer.difference(dark, filled) ?? 0) > 0.01)
    }

    func theHoverHintMatchesItsGoldens() {
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        for edge in ScreenEdge.allCases {
            for (name, inboard) in [("closed", true), ("open", false)] {
                var options = WaveRenderer.Options(edge: edge, ramp: .load,
                                                   length: Self.length, scale: 2)
                options.affordance = inboard
                guard let rendered = WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                                                        memory: Fixtures.memory(count: count),
                                                        options: options),
                      let golden = WaveRenderer.read(directory
                        .appendingPathComponent("hint/\(edge.rawValue)-\(name).png")),
                      let difference = WaveRenderer.difference(rendered, golden) else {
                    expect(false, "hint/\(edge.rawValue)-\(name): missing")
                    continue
                }
                expect(difference < Self.tolerance,
                       "hint/\(edge.rawValue)-\(name) differs by \(difference)")
            }
        }
    }

    func theHintIsVisibleAndPointsBothWays() {
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        var plain = WaveRenderer.Options(edge: .right, ramp: .load, length: Self.length, scale: 2)
        plain.affordance = nil
        var closed = plain; closed.affordance = true
        var open = plain; open.affordance = false
        let render = { (options: WaveRenderer.Options) in
            WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                               memory: Fixtures.memory(count: count), options: options)
        }
        guard let none = render(plain), let shut = render(closed), let shown = render(open) else {
            expect(false, "nothing rendered")
            return
        }
        // The hint changes the picture, and the two directions differ.
        expect((WaveRenderer.difference(none, shut) ?? 0) > 0.0002)
        expect((WaveRenderer.difference(shut, shown) ?? 0) > 0.0002)
    }

    func eachEdgeProducesItsOwnPixels() {
        // A transform bug that collapsed two edges together would slip past a
        // per-edge comparison, so check the edges differ from each other too.
        var images: [ScreenEdge: CGImage] = [:]
        for edge in ScreenEdge.allCases { images[edge] = render(edge: edge, ramp: .load) }
        expect(WaveRenderer.difference(images[.left]!, images[.right]!)! > Self.tolerance)
        expect(WaveRenderer.difference(images[.top]!, images[.bottom]!)! > Self.tolerance)
        expect(images[.left]!.width == images[.right]!.width)
        expect(images[.top]!.height == images[.bottom]!.height)
    }

    func rampsAreDistinguishable() {
        var images: [ColorRamp: CGImage] = [:]
        for ramp in ColorRamp.allCases { images[ramp] = render(edge: .right, ramp: ramp) }
        let ramps = ColorRamp.allCases
        for i in 0..<ramps.count {
            for j in (i + 1)..<ramps.count {
                let difference = WaveRenderer.difference(images[ramps[i]]!, images[ramps[j]]!)
                expect((difference ?? 0) > Self.tolerance,
                       "\(ramps[i].rawValue) and \(ramps[j].rawValue) render the same")
            }
        }
    }

    func bandSizeFollowsTheEdge() {
        let vertical = render(edge: .right, ramp: .load)!
        let horizontal = render(edge: .top, ramp: .load)!
        expect(vertical.width == Int(WaveGeometry.thickness * 2))
        expect(vertical.height == Int(Self.length * 2))
        expect(horizontal.width == Int(Self.length * 2))
        expect(horizontal.height == Int(WaveGeometry.thickness * 2))
    }
}
