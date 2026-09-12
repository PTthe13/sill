import CoreGraphics
import Foundation
@testable import SillCore

struct ScrubTests {
    func theNewestEndOfTheBandIsTheNewestSample() {
        expect(Scrub.index(alongFraction: 1, count: 100) == 99)
        expect(Scrub.index(alongFraction: 0, count: 100) == 0)
        expect(Scrub.index(alongFraction: 0.5, count: 101) == 50)
    }

    func aShortBandReadsOnlyTheHistoryItShows() {
        // 100 samples held, but this display only has room for 20 of them.
        expect(Scrub.index(alongFraction: 1, count: 100, visible: 20) == 99)
        // 20 visible means indices 80...99.
        expect(Scrub.index(alongFraction: 0, count: 100, visible: 20) == 80)
        expect(Scrub.index(alongFraction: 0.5, count: 100, visible: 21) == 89)
        // The oldest end of a short band is recent history, not ancient.
        let oldest = Scrub.index(alongFraction: 0, count: 100, visible: 20)
        expect(approx(Scrub.age(index: oldest, count: 100, interval: 1), 19))
    }

    func askingForMoreThanIsHeldIsHarmless() {
        expect(Scrub.index(alongFraction: 0, count: 10, visible: 999) == 0)
        expect(Scrub.index(alongFraction: 1, count: 10, visible: 999) == 9)
        // Nothing visible is treated as the newest sample alone.
        expect(Scrub.index(alongFraction: 0.5, count: 10, visible: 0) == 9)
    }

    func positionsOutsideTheBandClampRatherThanCrash() {
        expect(Scrub.index(alongFraction: -3, count: 40) == 0)
        expect(Scrub.index(alongFraction: 9, count: 40) == 39)
        expect(Scrub.index(alongFraction: 0.5, count: 0) == 0)
        expect(Scrub.index(alongFraction: 0.5, count: 1) == 0)
    }

    func ageCountsBackFromTheNewestSample() {
        expect(approx(Scrub.age(index: 99, count: 100, interval: 1), 0))
        expect(approx(Scrub.age(index: 89, count: 100, interval: 1), 10))
        expect(approx(Scrub.age(index: 0, count: 100, interval: 2), 198))
        expect(approx(Scrub.age(index: 0, count: 1, interval: 1), 0))
    }

    func ageReadsLikeAPersonWouldSayIt() {
        expect(Scrub.ageText(0) == "now")
        expect(Scrub.ageText(4) == "now")
        expect(Scrub.ageText(20) == "20s ago")
        expect(Scrub.ageText(59) == "59s ago")
        expect(Scrub.ageText(60) == "1m ago")
        expect(Scrub.ageText(245) == "4m ago")
        expect(Scrub.ageText(3600) == "1h 00m ago")
        expect(Scrub.ageText(4500) == "1h 15m ago")
    }

    func theChipSaysBothNumbersAndWhen() {
        expect(Scrub.label(envelope: 42.4, fill: 71.5, secondsAgo: 180)
               == "42% cpu · 72% memory · 3m ago")
        expect(Scrub.label(envelope: 0, fill: 0, secondsAgo: 0)
               == "0% cpu · 0% memory · now")
    }

    func theChipNamesWhicheverMetricsTheWaveDraws() {
        // Reading back "cpu" while the band is drawing network traffic is a
        // lie told in small type.
        expect(Scrub.label(envelope: 62, fill: 58, secondsAgo: 60,
                           envelopeMetric: .network, fillMetric: .disk)
               == "62% network · 58% disk · 1m ago")
    }

    func theBandsSpanIsStatedInHumanUnits() {
        expect(Scrub.spanText(sampleCount: 61, interval: 1) == "60s")
        expect(Scrub.spanText(sampleCount: 241, interval: 1) == "4m")
        expect(Scrub.spanText(sampleCount: 241, interval: 5) == "20m")
        expect(Scrub.spanText(sampleCount: 3601, interval: 1) == "1h 00m")
        expect(Scrub.spanText(sampleCount: 1, interval: 1) == "0s")
    }
}
