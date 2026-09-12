import Foundation
@testable import SillCore

struct MetricTests {
    func theRatePeakFadesInSecondsNotInSamples() {
        // Same two minutes of quiet, taken at two different sample rates: the
        // scale has to end up in the same place, or a band set to a long
        // history stays scaled to a download that finished hours ago.
        var fast = RateScale(peak: 100 * 1_048_576)
        for _ in 0..<120 { _ = fast.normalise(0, secondsSinceLast: 1) }
        var slow = RateScale(peak: 100 * 1_048_576)
        for _ in 0..<6 { _ = slow.normalise(0, secondsSinceLast: 20) }
        expect(abs(fast.peak - slow.peak) / fast.peak < 0.01,
               "\(fast.peak) vs \(slow.peak)")
    }

    func theRatePeakNeverFallsThroughTheFloor() {
        var scale = RateScale(peak: 50 * 1_048_576)
        for _ in 0..<50 { _ = scale.normalise(0, secondsSinceLast: 600) }
        expect(scale.peak == RateScale.floor)
    }

    func aBurstRaisesTheScaleImmediately() {
        var scale = RateScale()
        let reading = scale.normalise(80 * 1_048_576, secondsSinceLast: 1)
        expect(reading == 100, "a new peak fills the band")
        expect(scale.peak == 80 * 1_048_576)
    }

    func percentagesAndRatesAreDistinguished() {
        expect(!Metric.cpu.isRate)
        expect(!Metric.memory.isRate)
        expect(!Metric.gpu.isRate)
        expect(Metric.network.isRate)
        expect(Metric.disk.isRate)
    }

    func everyMetricHasAName() {
        for metric in Metric.allCases {
            expect(!metric.displayName.isEmpty)
            expect(!metric.shortName.isEmpty)
        }
        expect(Metric.cpu.displayName == "CPU")
        expect(Metric.network.shortName == "network")
    }

    func aRateScaleStartsAtItsFloorSoIdleNoiseStaysSmall() {
        var scale = RateScale()
        // 200 KB/s against a 2 MB/s floor is a tenth of the band, not all of it.
        let percent = scale.normalise(200_000)
        expect(percent > 0 && percent < 15, "idle traffic filled the band: \(percent)")
    }

    func aBigTransferFillsTheBand() {
        var scale = RateScale()
        expect(approx(scale.normalise(50 * 1_048_576), 100))
        // And the scale now remembers that speed.
        expect(scale.peak >= 50 * 1_048_576)
    }

    func theScaleFollowsTheFastestRecentMoment() {
        var scale = RateScale()
        _ = scale.normalise(100 * 1_048_576)
        // Half that speed reads as half the band, not as nothing.
        let half = scale.normalise(50 * 1_048_576)
        expect(half > 40 && half < 60, "half speed read as \(half)")
    }

    func theScaleDecaysBackDown() {
        var scale = RateScale()
        _ = scale.normalise(200 * 1_048_576)
        let after = scale.peak
        for _ in 0..<200 { _ = scale.normalise(0) }
        expect(scale.peak < after / 2, "one big transfer flattened the band for good")
        expect(scale.peak >= RateScale.floor, "the scale fell through its floor")
    }

    func nothingGoesNegativeOrOverfull() {
        var scale = RateScale()
        expect(scale.normalise(-500) == 0)
        expect(scale.normalise(.greatestFiniteMagnitude) <= 100)
    }
}
