import Foundation
@testable import SillCore

struct SpikeLogTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func theProcessTableIsOnlyReadWhenTheMachineIsBusy() {
        let log = SpikeLog()
        expect(!log.shouldSample(cpuPercent: 10, now: now))
        expect(!log.shouldSample(cpuPercent: SpikeLog.threshold - 0.1, now: now))
        expect(log.shouldSample(cpuPercent: SpikeLog.threshold, now: now))
        expect(log.shouldSample(cpuPercent: 99, now: now))
    }

    func itIsNotReadAgainImmediately() {
        var log = SpikeLog()
        log.record(name: "Xcode", cpuPercent: 80, now: now)
        expect(!log.shouldSample(cpuPercent: 90, now: now.addingTimeInterval(1)))
        expect(!log.shouldSample(cpuPercent: 90,
                                 now: now.addingTimeInterval(SpikeLog.minimumGap - 0.1)))
        expect(log.shouldSample(cpuPercent: 90,
                                now: now.addingTimeInterval(SpikeLog.minimumGap)))
    }

    func scrubbingASpikeFindsItsCulprit() {
        var log = SpikeLog()
        log.record(name: "Xcode", cpuPercent: 82, now: now.addingTimeInterval(-120))
        log.record(name: "ffmpeg", cpuPercent: 95, now: now.addingTimeInterval(-30))
        expect(log.culprit(secondsAgo: 120, now: now)?.name == "Xcode")
        expect(log.culprit(secondsAgo: 30, now: now)?.name == "ffmpeg")
        expect(approx(log.culprit(secondsAgo: 30, now: now)?.cpuPercent ?? 0, 95))
    }

    func aQuietStretchNamesNobody() {
        var log = SpikeLog()
        log.record(name: "Xcode", cpuPercent: 82, now: now.addingTimeInterval(-300))
        // Nothing was recorded near this moment, so nothing is claimed.
        expect(log.culprit(secondsAgo: 60, now: now) == nil)
        expect(SpikeLog().culprit(secondsAgo: 10, now: now) == nil)
    }

    func anEntryFromADifferentSpikeIsNotClaimed() {
        var log = SpikeLog()
        log.record(name: "ffmpeg", cpuPercent: 95, now: now.addingTimeInterval(-30))
        // Eight seconds away is a different moment, not that spike.
        expect(log.culprit(secondsAgo: 38, now: now) == nil)
        expect(log.culprit(secondsAgo: 32, now: now)?.name == "ffmpeg")
    }

    func theNearestEntryWinsWithinTolerance() {
        var log = SpikeLog()
        log.record(name: "early", cpuPercent: 70, now: now.addingTimeInterval(-63))
        log.record(name: "closer", cpuPercent: 70, now: now.addingTimeInterval(-61))
        expect(log.culprit(secondsAgo: 60, now: now)?.name == "closer")
    }

    func theLogStaysSmall() {
        var log = SpikeLog(capacity: 4)
        for i in 0..<10 {
            log.record(name: "p\(i)", cpuPercent: 70, now: now.addingTimeInterval(Double(i)))
        }
        expect(log.entries.count == 4)
        expect(log.entries.first?.name == "p6")
        expect(log.entries.last?.name == "p9")
    }

    func entriesOlderThanTheBandArePruned() {
        var log = SpikeLog()
        log.record(name: "old", cpuPercent: 70, now: now.addingTimeInterval(-900))
        log.record(name: "recent", cpuPercent: 70, now: now.addingTimeInterval(-60))
        log.prune(olderThan: 600, now: now)
        expect(log.entries.map(\.name) == ["recent"])
    }

    func anEmptyNameIsNotRecordedButStillCountsAsARead() {
        var log = SpikeLog()
        log.record(name: "", cpuPercent: 70, now: now)
        expect(log.entries.isEmpty)
        expect(!log.shouldSample(cpuPercent: 90, now: now.addingTimeInterval(1)))
    }
}
