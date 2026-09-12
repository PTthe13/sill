import CoreGraphics
@testable import SillCore

struct ColorRampTests {
    func everyRampHasThreeStops() {
        for ramp in ColorRamp.allCases { expect(ramp.stops.count == 3, "\(ramp.rawValue)") }
    }

    func loadRampHexValues() {
        let s = ColorRamp.load.stops
        expect(s[0] == RampStop(hex: 0x4FD1A5))
        expect(approx(s[2].red, 1.0))
        expect(approx(s[2].green, 0x5B / 255.0))
        expect(approx(s[2].blue, 0x4A / 255.0))
    }

    func monoIsWhiteAtDecliningAlpha() {
        let s = ColorRamp.mono.stops
        expect(s.map(\.alpha) == [0.92, 0.58, 0.34])
        expect(s.allSatisfy { $0.red == 1 && $0.green == 1 && $0.blue == 1 })
    }

    func everyColourRampTravelsInHueNotJustBrightness() {
        // Colour carries the load, so idle and heavy have to be different
        // colours — three shades of one hue reads as "darker", not "busier".
        // Mono is the deliberate exception.
        for ramp in ColorRamp.allCases where ramp != .mono {
            for stops in [ramp.stops, ramp.lightBackdropStops] {
                guard let idle = Palette.hue(stops[0]), let mid = Palette.hue(stops[1]),
                      let heavy = Palette.hue(stops[2]) else {
                    expect(false, "\(ramp.rawValue) has a stop with no hue")
                    continue
                }
                expect(Palette.hueDistance(idle, heavy) > 25,
                       "\(ramp.rawValue): idle \(Int(idle))° to heavy \(Int(heavy))° is too flat")
                // The mid stop sits between the two, not off on its own.
                expect(Palette.hueDistance(idle, mid) > 8, "\(ramp.rawValue) mid is idle again")
                expect(Palette.hueDistance(mid, heavy) > 8, "\(ramp.rawValue) mid is heavy again")
                expect(Palette.hueDistance(idle, mid) < Palette.hueDistance(idle, heavy) + 1,
                       "\(ramp.rawValue) mid overshoots the heavy end")
            }
        }
    }

    func monoStaysMonochromeOnPurpose() {
        for stops in [ColorRamp.mono.stops, ColorRamp.mono.lightBackdropStops] {
            expect(stops.allSatisfy { Palette.hue($0) == nil })
        }
    }

    func lightBackdropStopsKeepTheirRampsHues() {
        for ramp in ColorRamp.allCases where ramp != .mono {
            for (dark, light) in zip(ramp.stops, ramp.lightBackdropStops) {
                guard let a = Palette.hue(dark), let b = Palette.hue(light) else {
                    expect(false, "\(ramp.rawValue) lost its hue")
                    continue
                }
                expect(Palette.hueDistance(a, b) < 30,
                       "\(ramp.rawValue): \(Int(a))° became \(Int(b))° on a light backdrop")
            }
        }
    }

    func severityThresholds() {
        let ramp = ColorRamp.load
        expect(ramp.stop(forLoad: 0) == ramp.stops[0])
        expect(ramp.stop(forLoad: 44.9) == ramp.stops[0])
        expect(ramp.stop(forLoad: 45) == ramp.stops[1])
        expect(ramp.stop(forLoad: 77.9) == ramp.stops[1])
        expect(ramp.stop(forLoad: 78) == ramp.stops[2])
        expect(ramp.stop(forLoad: 400) == ramp.stops[2])
    }

    func fadeIsFullAtTheNewestEndAndZeroAtBothExtremes() {
        expect(approx(Fade.alpha(atAge: 0), 0))
        expect(approx(Fade.alpha(atAge: 0.06), 1))
        expect(approx(Fade.alpha(atAge: 1), 0))
        expect(approx(Fade.alpha(atAge: 0.93), 0.30))
    }

    func fadeDecreasesWithAgeAfterTheHead() {
        var last = Fade.alpha(atAge: 0.06)
        for t in stride(from: 0.07, through: 0.93, by: 0.01) {
            let v = Fade.alpha(atAge: CGFloat(t))
            expect(v <= last + 1e-9)
            last = v
        }
    }
}
