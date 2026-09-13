import Foundation
@testable import SillCore

struct MetricTests {
    func ratesPrintSomethingSaneForNonsense() {
        expect(Format.throughput(bytesPerSecond: .nan) == "0.0 MB/s")
        expect(Format.rate(bytesPerSecond: .infinity) == "0.0")
        expect(Scrub.ageText(.nan) == "now")
    }

    func oneScaleForTheWholeWindow() {
        // Every sample is drawn against the same scale, whatever the scale
        // happened to be when each was taken. Full height is the step above
        // the busiest moment, so the proportions are what matter here.
        let mb = 1_048_576.0
        let heights = RateWindow.normalised([0, 4 * mb, 1 * mb, 2 * mb])
        expect(approx(heights[1], 80), "\(heights)")   // 4 of a 5 MB/s scale
        expect(approx(heights[2], 20))
        expect(approx(heights[3], 40))
        expect(heights[0] == 0)
    }

    func theScaleSnapsToStepsSoThePictureStaysStill() {
        let mb = 1_048_576.0
        // A busiest moment that creeps from 3.1 to 3.4 MB/s keeps the same
        // full scale, so nothing already on the band is redrawn.
        expect(RateWindow.scale(for: [3.1 * mb]) == RateWindow.scale(for: [3.4 * mb]))
        expect(RateWindow.scale(for: [3.1 * mb]) == 5 * mb)
        expect(RateWindow.scale(for: [12 * mb]) == 20 * mb)
        expect(RateWindow.scale(for: [0]) == RateWindow.floor)
    }

    func aQuietWindowStaysQuiet() {
        // Idle chatter must not fill the band just because it is the loudest
        // thing on it: below the floor, everything is small.
        let heights = RateWindow.normalised([120_000, 40_000, 900])
        expect(heights.allSatisfy { $0 < 7 }, "\(heights)")
        expect(RateWindow.scale(for: [120_000]) == RateWindow.floor)
    }

    func nonsenseReadingsDoNotSetTheScale() {
        // The NaN and the infinity are ignored; the 3 MB/s sets the step.
        expect(RateWindow.scale(for: [.nan, .infinity, 3_000_000]) == 5 * 1_048_576)
        expect(RateWindow.normalised([.nan, 3_000_000])[0] == 0)
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

    func idleChatterStaysSmall() {
        // 200 KB/s against a 2 MB/s floor is a tenth of the band, not all of it.
        let percent = RateWindow.normalised([200_000])[0]
        expect(percent > 0 && percent < 15, "idle traffic filled the band: \(percent)")
    }

    func halfTheBurstIsHalfTheBand() {
        let heights = RateWindow.normalised([0, 50 * 1_048_576, 25 * 1_048_576])
        expect(approx(heights[1], 100))
        expect(approx(heights[2], 50), "half the burst should be half the band")
    }

    func oneHugeTransferDoesNotFlattenTheBandForever() {
        // Once the transfer has scrolled off the band, the window it leaves
        // behind is scaled on its own terms again.
        let during = RateWindow.normalised([200 * 1_048_576, 3 * 1_048_576])
        expect(during[1] < 3, "\(during)")
        let after = RateWindow.normalised([3 * 1_048_576, 3 * 1_048_576])
        expect(after[1] > 50, "\(after)")
    }

    func nothingGoesNegativeOrOverfull() {
        let heights = RateWindow.normalised([-500, .greatestFiniteMagnitude, 10])
        expect(heights[0] == 0)
        expect(heights.allSatisfy { $0 >= 0 && $0 <= 100 })
    }
}
