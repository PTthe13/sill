import CoreGraphics
@testable import SillCore

struct PaletteTests {
    func headroomSurvivesNonsenseReadings() {
        // A sampler dividing by a zero interval yields NaN, and Int(NaN) traps.
        expect(Headroom.value(cpuPercent: .nan, memoryPercent: 20) == 91)
        expect(Headroom.value(cpuPercent: .infinity, memoryPercent: .nan) == 100)
        expect(Headroom.value(cpuPercent: -50, memoryPercent: 400) == 55)
        expect(!Headroom.title(cpuPercent: .nan, memoryPercent: .nan).isEmpty)
    }

    let dark = Palette.assumedLuminance
    let light = 0.85

    func darkBackdropKeepsTheDesignedRamp() {
        for ramp in ColorRamp.allCases {
            let style = Palette.style(ramp: ramp, backdropLuminance: dark)
            expect(style.stops == ramp.stops, "\(ramp.rawValue)")
            expect(approx(style.outerOpacity, WaveModel.opacity(strand: 0)))
            expect(approx(style.innerOpacity, WaveModel.opacity(strand: 4)))
            expect(style.outerWidth == WaveModel.outerLineWidth)
            expect(approx(style.fadeFloor, Fade.defaultFloor))
        }
    }

    func lightBackdropUsesTheLightStops() {
        for ramp in ColorRamp.allCases {
            let style = Palette.style(ramp: ramp, backdropLuminance: light)
            expect(style.stops == ramp.lightBackdropStops, "\(ramp.rawValue)")
        }
    }

    func strandsGetDarkerAsTheBackdropLightens() {
        for ramp in ColorRamp.allCases where ramp != .mono {
            let onDark = Palette.style(ramp: ramp, backdropLuminance: dark).stops
            let onLight = Palette.style(ramp: ramp, backdropLuminance: light).stops
            for (a, b) in zip(onDark, onLight) {
                let before = Palette.luminance(red: a.red, green: a.green, blue: a.blue)
                let after = Palette.luminance(red: b.red, green: b.green, blue: b.blue)
                expect(after < before, "\(ramp.rawValue) stop did not darken")
            }
        }
    }

    func monoFlipsToInkRatherThanStayingWhite() {
        let style = Palette.style(ramp: .mono, backdropLuminance: light)
        for stop in style.stops {
            expect(Palette.luminance(red: stop.red, green: stop.green, blue: stop.blue) < 0.2)
            expect(stop.alpha >= 0.46)
        }
    }

    func strandsGetDenserAndHeavierOnLightBackdrops() {
        let onLight = Palette.style(ramp: .load, backdropLuminance: light)
        expect(onLight.innerOpacity > WaveModel.opacity(strand: 4))
        expect(onLight.outerOpacity > WaveModel.opacity(strand: 0))
        expect(onLight.outerWidth > WaveModel.outerLineWidth)
        expect(onLight.fadeFloor > Fade.defaultFloor)
    }

    func lightnessIsSmoothAndMonotonic() {
        expect(Palette.lightness(backdropLuminance: 0) == 0)
        expect(Palette.lightness(backdropLuminance: 0.34) == 0)
        expect(Palette.lightness(backdropLuminance: 1) == 1)
        expect(approx(Palette.lightness(backdropLuminance: 0.51), 0.5, 0.02))
        var last = -1.0
        for v in stride(from: 0.0, through: 1.0, by: 0.01) {
            let t = Palette.lightness(backdropLuminance: v)
            expect(t >= last - 1e-9)
            last = t
        }
    }

    func haloAlwaysSitsOppositeTheBackdrop() {
        let onDark = Palette.style(ramp: .load, backdropLuminance: 0.05).haloColor
        let onLight = Palette.style(ramp: .load, backdropLuminance: 0.95).haloColor
        expect(Palette.luminance(red: onDark.red, green: onDark.green, blue: onDark.blue) < 0.1)
        expect(Palette.luminance(red: onLight.red, green: onLight.green, blue: onLight.blue) > 0.9)
    }

    func busyBackdropsGetAStrongerHairline() {
        let flat = Palette.style(ramp: .load, backdropLuminance: light, backdropVariation: 0)
        let busy = Palette.style(ramp: .load, backdropLuminance: light, backdropVariation: 1)
        expect(busy.haloOuterAlpha > flat.haloOuterAlpha)
        expect(busy.haloInnerAlpha > flat.haloInnerAlpha)
        expect(busy.haloWidthBoost > flat.haloWidthBoost)
        // The hairline stays a hairline: never wide enough to read as a glow.
        expect(busy.haloWidth(strand: 0) < busy.lineWidth(strand: 0) + 2.5)
    }

    func variationIsClampedToAUsefulRange() {
        expect(Palette.variation(standardDeviation: 0) == 0)
        expect(Palette.variation(standardDeviation: 0.22) == 1)
        expect(Palette.variation(standardDeviation: 5) == 1)
        expect(approx(Palette.variation(standardDeviation: 0.11), 0.5))
    }

    func fadeFloorRaisesTheOldEndOnLightBackdrops() {
        let floor = Palette.style(ramp: .load, backdropLuminance: light).fadeFloor
        expect(approx(Fade.alpha(atAge: 0.93, floor: floor), floor))
        expect(Fade.alpha(atAge: 0.93, floor: floor) > Fade.alpha(atAge: 0.93))
        // Both ends still dissolve completely.
        expect(approx(Fade.alpha(atAge: 0, floor: floor), 0))
        expect(approx(Fade.alpha(atAge: 1, floor: floor), 0))
    }

    func haloIsWiderThanTheStrandItSitsUnder() {
        for luminance in [0.05, 0.5, 0.95] {
            let style = Palette.style(ramp: .teal, backdropLuminance: luminance,
                                      backdropVariation: 0.5)
            for k in 0..<WaveModel.strandCount {
                expect(style.haloWidth(strand: k) > style.lineWidth(strand: k))
                expect(style.haloAlpha(strand: k) < style.opacity(strand: k))
            }
        }
    }
}

struct AffordanceTests {
    let size = CGSize(width: WaveGeometry.thickness, height: 432)
    let wide = CGSize(width: 900, height: WaveGeometry.thickness)

    func chevronSitsOnTheInboardSideOfTheBand() {
        // Right edge: inboard is x == 0, the side the panel opens toward.
        let right = Affordance.points(edge: .right, size: size, pointsInboard: true)
        expect(approx(right.tip.x, Affordance.inset))
        expect(approx(right.tip.y, size.height / 2))
        // Left edge mirrors it.
        let left = Affordance.points(edge: .left, size: size, pointsInboard: true)
        expect(approx(left.tip.x, size.width - Affordance.inset))
    }

    func chevronPointsAwayFromTheScreenEdgeWhileClosed() {
        // Arms trail behind the tip, so the tip is the most inboard point.
        let right = Affordance.points(edge: .right, size: size, pointsInboard: true)
        expect(right.arms.allSatisfy { $0.x > right.tip.x })
        let left = Affordance.points(edge: .left, size: size, pointsInboard: true)
        expect(left.arms.allSatisfy { $0.x < left.tip.x })
        let top = Affordance.points(edge: .top, size: wide, pointsInboard: true)
        expect(top.arms.allSatisfy { $0.y > top.tip.y })
        let bottom = Affordance.points(edge: .bottom, size: wide, pointsInboard: true)
        expect(bottom.arms.allSatisfy { $0.y < bottom.tip.y })
    }

    func chevronReversesOnceThePanelIsOpen() {
        for edge in ScreenEdge.allCases {
            let bandSize = edge.isVertical ? size : wide
            let closed = Affordance.points(edge: edge, size: bandSize, pointsInboard: true)
            let open = Affordance.points(edge: edge, size: bandSize, pointsInboard: false)
            expect(closed.tip == open.tip, "\(edge) tip moved")
            // The arms swap to the other side of the tip.
            if edge.isVertical {
                expect((closed.arms[0].x - closed.tip.x) * (open.arms[0].x - open.tip.x) < 0)
            } else {
                expect((closed.arms[0].y - closed.tip.y) * (open.arms[0].y - open.tip.y) < 0)
            }
        }
    }

    func chevronStaysInsideTheBand() {
        for edge in ScreenEdge.allCases {
            let bandSize = edge.isVertical ? size : wide
            for inboard in [true, false] {
                let points = Affordance.points(edge: edge, size: bandSize, pointsInboard: inboard)
                for point in [points.tip] + points.arms {
                    expect(point.x >= 0 && point.x <= bandSize.width, "\(edge) x out of band")
                    expect(point.y >= 0 && point.y <= bandSize.height, "\(edge) y out of band")
                }
            }
        }
    }

    func chevronIsCentredAlongTheBand() {
        let top = Affordance.points(edge: .top, size: wide, pointsInboard: true)
        expect(approx(top.tip.x, wide.width / 2))
        let bottom = Affordance.points(edge: .bottom, size: wide, pointsInboard: false)
        expect(approx(bottom.tip.x, wide.width / 2))
    }

    func chevronPathHasThreePoints() {
        let path = Affordance.path(edge: .right, size: size, pointsInboard: true)
        expect(!path.isEmpty)
        expect(path.boundingBox.width <= Affordance.depth + 1)
        expect(approx(path.boundingBox.height, Affordance.halfSpan * 2, 0.001))
    }

    func chevronColourOpposesTheBackdrop() {
        let onLight = Affordance.color(style: Palette.style(ramp: .load, backdropLuminance: 0.9))
        let onDark = Affordance.color(style: Palette.style(ramp: .load, backdropLuminance: 0.05))
        expect(Palette.luminance(red: onLight.red, green: onLight.green, blue: onLight.blue) < 0.2)
        expect(Palette.luminance(red: onDark.red, green: onDark.green, blue: onDark.blue) > 0.8)
    }
}

struct ContentAwareTests {
    let n = Palette.profileSlices
    var allLight: [Double] { [Double](repeating: 0.9, count: n) }
    var allDark: [Double] { [Double](repeating: 0.06, count: n) }
    var idle: [Double] { [Double](repeating: 8, count: n) }
    var pinned: [Double] { [Double](repeating: 96, count: n) }

    func rampPositionFollowsTheDocumentedThresholds() {
        expect(approx(Palette.rampPosition(forLoad: 0), 0))
        expect(approx(Palette.rampPosition(forLoad: 45), 0.5))
        expect(approx(Palette.rampPosition(forLoad: 78), 1))
        expect(approx(Palette.rampPosition(forLoad: 100), 1))
        expect(approx(Palette.rampPosition(forLoad: 22.5), 0.25))
        // Out of range values clamp rather than run off the ramp.
        expect(approx(Palette.rampPosition(forLoad: -20), 0))
        expect(approx(Palette.rampPosition(forLoad: 400), 1))
    }

    func colourIsLoadNotAge() {
        // Same position in the band, different load: different colour.
        let quiet = Palette.color(ramp: .load, load: 0, backdropLuminance: 0.06)
        let middling = Palette.color(ramp: .load, load: 45, backdropLuminance: 0.06)
        let busy = Palette.color(ramp: .load, load: 95, backdropLuminance: 0.06)
        expect(quiet == ColorRamp.load.stops[0])
        expect(middling == ColorRamp.load.stops[1])
        expect(busy == ColorRamp.load.stops[2])
        // A light load sits near the idle stop, not at the far end of the ramp.
        let light = Palette.color(ramp: .load, load: 5, backdropLuminance: 0.06)
        expect(approx(light.green, ColorRamp.load.stops[0].green, 0.05))
    }

    func aQuietBandIsAllIdleColour() {
        let stops = Palette.gradientStops(ramp: .load, loads: idle, profile: allDark)
        expect(stops.allSatisfy { approx($0.red, stops[0].red) && approx($0.blue, stops[0].blue) })
        // Idle, so nothing on the band is anywhere near the heavy stop.
        expect(stops[0].red < ColorRamp.load.stops[2].red)
    }

    func aSpikeColoursTheSliceItHappenedIn() {
        var loads = [Double](repeating: 6, count: n)
        loads[3] = 95                                  // fourth slice from the newest end
        let stops = Palette.gradientStops(ramp: .load, loads: loads, profile: allDark)
        let heavy = ColorRamp.load.stops[2]
        expect(approx(stops[3].red, heavy.red, 0.02), "spike slice is not the heavy colour")
        expect(!approx(stops[12].red, heavy.red, 0.02), "a quiet slice went heavy")
    }

    func eachSliceIsTonedByTheWallpaperUnderIt() {
        let split = [Double](repeating: 0.9, count: n / 2) + [Double](repeating: 0.06, count: n / 2)
        let stops = Palette.gradientStops(ramp: .load, loads: idle, profile: split)
        let overBright = stops[2], overDark = stops[n - 3]
        let brightLuma = Palette.luminance(red: overBright.red, green: overBright.green,
                                           blue: overBright.blue)
        let darkLuma = Palette.luminance(red: overDark.red, green: overDark.green,
                                         blue: overDark.blue)
        // Same load in both halves: the only difference is the desktop behind.
        expect(brightLuma < darkLuma, "ink \(brightLuma) over bright vs \(darkLuma) over dark")
    }

    func aUniformBackdropMatchesTheGlobalChoice() {
        let light = Palette.gradientStops(ramp: .teal, loads: pinned, profile: allLight)
        let dark = Palette.gradientStops(ramp: .teal, loads: pinned, profile: allDark)
        expect(light[0] == ColorRamp.teal.lightBackdropStops[2])
        expect(dark[0] == ColorRamp.teal.stops[2])
    }

    func theHairlineFlipsWithTheBackdropSliceBySlice() {
        let split = [Double](repeating: 0.9, count: n / 2) + [Double](repeating: 0.06, count: n / 2)
        let halo = Palette.haloStops(profile: split)
        expect(halo.count == split.count)
        expect(Palette.luminance(red: halo[2].red, green: halo[2].green, blue: halo[2].blue) > 0.8)
        let dark = halo[halo.count - 3]
        expect(Palette.luminance(red: dark.red, green: dark.green, blue: dark.blue) < 0.1)
    }

    func sliceValuesRunNewestFirst() {
        // History is oldest-first; the band draws newest-first.
        let history: [Double] = [0, 10, 20, 30, 40]
        let slices = Palette.sliceValues(history: history, count: 5)
        expect(slices == [40, 30, 20, 10, 0])
        expect(Palette.sliceValues(history: [7], count: 3) == [7, 7, 7])
        expect(Palette.sliceValues(history: [], count: 3).isEmpty)
    }

    func emptyInputsFallBackRatherThanCrash() {
        expect(Palette.gradientStops(ramp: .amber, loads: [], profile: []).count == 1)
        expect(Palette.haloStops(profile: []).count == 1)
    }

    func locationsAreEvenlySpaced() {
        expect(Palette.locations(count: 5) == [0, 0.25, 0.5, 0.75, 1])
    }

    func aFlatColourStillPaints() {
        // A gradient with one stop draws nothing at all — which is how the
        // settings preview came up blank.
        let single = [RampStop(hex: 0x4FD1A5)]
        expect(Palette.paddedStops(single).count == 2)
        expect(Palette.paddedStops(single)[0] == single[0])
        expect(Palette.locations(count: 1).count == 2)
        expect(Palette.paddedStops([]).isEmpty)
        let pair = [RampStop(hex: 0x000000), RampStop(hex: 0xFFFFFF)]
        expect(Palette.paddedStops(pair) == pair)
    }
}

struct ContentAwareRenderTests {
    static let length: CGFloat = 240
    static let slices = Palette.profileSlices

    /// Band luminance measured against the backdrop it actually sits on, which
    /// is the only thing that decides whether a strand can be seen.
    func contrastPerHalf(profile: [Double], backdrop: [Double]) -> (newest: Double, oldest: Double)? {
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        var options = WaveRenderer.Options(edge: .right, ramp: .load, length: Self.length, scale: 2)
        options.profile = profile
        options.variation = 1
        guard let wave = WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                                            memory: Fixtures.memory(count: count),
                                            options: options) else { return nil }

        let size = WaveGeometry.size(edge: .right, length: Self.length)
        guard let context = CGContext(data: nil, width: wave.width, height: wave.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: WaveRenderer.colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: 2, y: 2)

        // Paint the backdrop the profile describes: entry 0 at the newest end,
        // which is the bottom of a right-edge band.
        let sliceHeight = size.height / CGFloat(backdrop.count)
        for (index, luminance) in backdrop.enumerated() {
            context.setFillColor(CGColor(gray: CGFloat(luminance), alpha: 1))
            context.fill(CGRect(x: 0, y: CGFloat(index) * sliceHeight,
                                width: size.width, height: sliceHeight + 1))
        }
        context.draw(wave, in: CGRect(origin: .zero, size: size))
        guard let composite = context.makeImage() else { return nil }

        func contrast(rows: Range<Int>, backdropLuminance: Double) -> Double? {
            guard let crop = composite.cropping(to: CGRect(x: 0, y: rows.lowerBound,
                                                           width: composite.width,
                                                           height: rows.count))
            else { return nil }
            return WaveRenderer.meanDeviation(crop, from: backdropLuminance)
        }
        let half = composite.height / 2
        // Image rows run top-down: the first half is the oldest end.
        guard let oldest = contrast(rows: 0..<half,
                                    backdropLuminance: backdrop[backdrop.count - 1]),
              let newest = contrast(rows: half..<composite.height,
                                    backdropLuminance: backdrop[0]) else { return nil }
        return (newest, oldest)
    }

    func measuringTheBandAgainstItsOwnBackdrop() {
        // Sanity: on a flat dark wallpaper the strands stand off it.
        let flat = [Double](repeating: 0.05, count: Self.slices)
        guard let contrast = contrastPerHalf(profile: flat, backdrop: flat) else {
            expect(false, "nothing rendered")
            return
        }
        expect(contrast.newest > 0.01)
        expect(contrast.oldest > 0.005)
    }

    func neitherHalfOfASplitWallpaperIsLeftInvisible() {
        // Bright at the newest end, dark at the oldest: the case a single
        // global tone cannot serve. Measured slice by slice, both halves have
        // to stand off the desktop behind them.
        let backdrop = [Double](repeating: 0.92, count: Self.slices / 2)
            + [Double](repeating: 0.04, count: Self.slices / 2)
        guard let aware = contrastPerHalf(profile: backdrop, backdrop: backdrop) else {
            expect(false, "nothing rendered")
            return
        }
        expect(aware.newest > 0.02, "bright half contrast \(aware.newest)")
        expect(aware.oldest > 0.02, "dark half contrast \(aware.oldest)")
    }

    func aSplitBackdropDiffersFromEitherUniformOne() {
        let n = Self.slices
        let count = WaveGeometry.sampleCount(forLength: Self.length + 2 * WaveGeometry.step)
        func render(_ profile: [Double]) -> CGImage? {
            var options = WaveRenderer.Options(edge: .right, ramp: .load,
                                               length: Self.length, scale: 2)
            options.profile = profile
            return WaveRenderer.image(cpu: Fixtures.cpu(count: count),
                                      memory: Fixtures.memory(count: count), options: options)
        }
        let split = [Double](repeating: 0.9, count: n / 2) + [Double](repeating: 0.05, count: n / 2)
        guard let mixed = render(split),
              let light = render([Double](repeating: 0.9, count: n)),
              let dark = render([Double](repeating: 0.05, count: n)) else {
            expect(false, "nothing rendered")
            return
        }
        expect((WaveRenderer.difference(mixed, light) ?? 0) > 0.004)
        expect((WaveRenderer.difference(mixed, dark) ?? 0) > 0.004)
    }

    func theOldEndKeepsMorePresenceOverABrightPatch() {
        let n = Self.slices
        let brightOldEnd = [Double](repeating: 0.05, count: n / 2)
            + [Double](repeating: 0.9, count: n / 2)
        let alphas = Fade.profileAlphas(profile: brightOldEnd)
        let uniformDark = Fade.profileAlphas(profile: [Double](repeating: 0.05, count: n))
        expect(alphas[n - 3] > uniformDark[n - 3])
        expect(approx(alphas[0], 0))
        expect(approx(alphas[n - 1], 0))
    }

    func aFlatOrEmptyProfileStillFadesWithAge() {
        // One stop in a gradient mask hides the entire band — this is what
        // blanked the settings preview.
        for profile in [[Double](), [0.5]] {
            let alphas = Fade.profileAlphas(profile: profile)
            expect(alphas.count > 1, "\(profile.count) entries produced \(alphas.count) stops")
            expect(approx(alphas[0], 0))
            expect(approx(alphas[alphas.count - 1], 0))
            expect(alphas.contains { $0 > 0.9 }, "nothing in the band is fully opaque")
        }
    }

    func aFlatBackdropKeepsTheDesignedFade() {
        let n = Self.slices
        let alphas = Fade.profileAlphas(profile: [Double](repeating: 0.05, count: n))
        let t = CGFloat(n - 3) / CGFloat(n - 1)
        expect(approx(alphas[n - 3], Fade.alpha(atAge: t), 1e-9))
    }
}

struct BandBackgroundTests {
    func nothingBehindLeavesTheWallpaperInCharge() {
        expect(approx(BandBackground.none.effectiveLuminance(wallpaper: 0.9), 0.9))
        expect(approx(BandBackground.none.effectiveLuminance(wallpaper: 0.05), 0.05))
        expect(BandBackground.none.plateAlpha(lightness: 1) == 0)
    }

    func aDarkPlateTakesOverFromTheWallpaper() {
        // The whole point: put something dark behind the band and the strands
        // go back to their bright colours instead of staying inked.
        for background in [BandBackground.shade, .glass] {
            let tone = background.effectiveLuminance(wallpaper: 0.95)
            expect(tone < 0.32, "\(background.rawValue) did not darken the backdrop")
            expect(Palette.lightness(backdropLuminance: tone) == 0,
                   "\(background.rawValue) still reads as a light backdrop")
        }
    }

    func aPalePlateDoesTheReverse() {
        // Light behind the band means the strands ink up, even on a dark desktop.
        let tone = BandBackground.light.effectiveLuminance(wallpaper: 0.03)
        expect(tone > 0.7, "the pale plate did not lighten the backdrop")
        expect(Palette.lightness(backdropLuminance: tone) > 0.5)
        expect(BandBackground.light.isPale)
        expect(!BandBackground.shade.isPale)
    }

    func aPlateIsHeavierWhereItHasMoreToCover() {
        expect(BandBackground.shade.plateAlpha(lightness: 1)
               > BandBackground.shade.plateAlpha(lightness: 0), "dark plate over a light desktop")
        expect(BandBackground.light.plateAlpha(lightness: 0)
               > BandBackground.light.plateAlpha(lightness: 1), "pale plate over a dark desktop")
    }

    func platesAreSoftEnoughToSeeThrough() {
        for background in [BandBackground.shade, .light] {
            for lightness in [0.0, 0.5, 1.0] as [CGFloat] {
                let alpha = background.plateAlpha(lightness: lightness)
                expect(alpha > 0.15, "\(background.rawValue) too faint to be worth switching on")
                expect(alpha < 0.45, "\(background.rawValue) is a wall, not a plate")
            }
        }
    }

    func anExistingDarkSettingStillReads() {
        // The dark plate is stored as "shade", the name it had when it was the
        // only one — nobody's settings should change under them.
        expect(BandBackground(rawValue: "shade") == .shade)
        expect(BandBackground.shade.displayName == "Dark")
    }

    func everyBackgroundHasAName() {
        expect(BandBackground.allCases.count == 4)
        for background in BandBackground.allCases { expect(!background.displayName.isEmpty) }
    }
}
