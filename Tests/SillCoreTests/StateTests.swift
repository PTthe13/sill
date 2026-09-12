import Foundation
@testable import SillCore

struct HistoryTests {
    func pushDropsTheOldestValue() {
        var h = History(capacity: 3, filledWith: 0)
        h.push(1); h.push(2); h.push(3); h.push(4)
        expect(h.values == [2, 3, 4])
        expect(h.newest == 4)
    }

    func nonsenseNeverEntersTheHistory() {
        // A NaN in the ring becomes a NaN path coordinate, and Core Graphics
        // draws nothing at all rather than complaining.
        var h = History(capacity: 3, filledWith: 0)
        h.push(.nan); h.push(.infinity); h.push(7)
        expect(h.values.allSatisfy { $0.isFinite }, "\(h.values)")
        expect(h.newest == 7)
    }

    func countsOnlyWhatWasActuallyMeasured() {
        var h = History(capacity: 4, filledWith: 40)
        expect(h.filled == 0, "a seeded ring has measured nothing")
        h.push(1); h.push(2)
        expect(h.filled == 2)
        h.push(3); h.push(4); h.push(5)
        expect(h.filled == 4, "never more than the ring holds")
    }

    func shrinkingCannotLeaveMoreMeasuredThanCapacity() {
        var h = History(capacity: 6, filledWith: 0)
        for i in 1...6 { h.push(Double(i)) }
        h.resize(to: 2)
        expect(h.filled == 2)
        h.resize(to: 8)
        expect(h.filled == 2, "growing does not invent measurements")
    }

    func startsFullSoTheWaveHasSomethingToDraw() {
        expect(History(capacity: 5, filledWith: 12).values == [12, 12, 12, 12, 12])
    }

    func growingKeepsNewestAndPadsTheStart() {
        var h = History(capacity: 3, filledWith: 0)
        h.push(1); h.push(2); h.push(3)
        h.resize(to: 5)
        expect(h.values == [1, 1, 1, 2, 3])
        expect(h.values.count == 5)
    }

    func shrinkingKeepsTheNewestValues() {
        var h = History(capacity: 5, filledWith: 0)
        for v in 1...5 { h.push(Double(v)) }
        h.resize(to: 2)
        expect(h.values == [4, 5])
    }

    func capacityNeverDropsBelowOne() {
        var h = History(capacity: 0)
        h.push(9)
        expect(h.values == [9])
    }
}

struct HeadroomTests {
    func valueWeightsCpuAndMemory() {
        expect(Headroom.value(cpuPercent: 0, memoryPercent: 0) == 100)
        expect(Headroom.value(cpuPercent: 100, memoryPercent: 100) == 0)
        expect(Headroom.value(cpuPercent: 42, memoryPercent: 73) == 44)
    }

    func wordsMatchTheBands() {
        expect(Headroom.word(forHeadroom: 90) == "Plenty of room")
        expect(Headroom.word(forHeadroom: 56) == "Plenty of room")
        expect(Headroom.word(forHeadroom: 55) == "Comfortable")
        expect(Headroom.word(forHeadroom: 31) == "Comfortable")
        expect(Headroom.word(forHeadroom: 30) == "Getting tight")
        expect(Headroom.word(forHeadroom: 16) == "Getting tight")
        expect(Headroom.word(forHeadroom: 15) == "Something is eating the machine")
        expect(Headroom.word(forHeadroom: -20) == "Something is eating the machine")
    }

    func summaryReadsAsTheBriefSpecifies() {
        expect(Headroom.summary(cpuPercent: 42, memoryPercent: 73)
               == "Comfortable · 44 headroom · envelope 42% cpu · fill 73% memory")
    }

    func theSummaryNamesWhateverTheWaveIsDrawing() {
        // Headroom still weighs CPU and memory — that is what headroom means —
        // but the envelope and fill report the metrics actually on screen.
        let line = Headroom.summary(cpuPercent: 42, memoryPercent: 73,
                                    envelope: .network, fill: .disk,
                                    envelopeValue: 88, fillValue: 12)
        expect(line == "Comfortable · 44 headroom · envelope 88% network · fill 12% disk")
    }

    func aMetricWithNoReadingFallsBackToTheCoreOnes() {
        let line = Headroom.summary(cpuPercent: 30, memoryPercent: 60)
        expect(line.contains("envelope 30% cpu"))
        expect(line.contains("fill 60% memory"))
    }

    func byteFormatting() {
        expect(Format.bytes(512) == "512B")
        expect(Format.bytes(1536) == "1.5K")
        expect(Format.bytes(776 * 1_073_741_824) == "776G")
    }
}

struct SettingsTests {
    func makeSettings() -> (SillSettings, UserDefaults) {
        let suite = "sill.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SillSettings(defaults: defaults), defaults)
    }

    func defaultsMatchTheBrief() {
        let (settings, _) = makeSettings()
        expect(settings.edge == .right)
        expect(settings.ramp == .load)
        expect(settings.material == .tinted)
        expect(settings.dimWhenFocused)
        expect(settings.sampleInterval == 1.0)
        expect(settings.lengthFraction == WaveGeometry.defaultLengthFraction)
        expect(settings.displayUUID == nil)
    }

    func valuesRoundTripThroughDefaults() {
        let (settings, defaults) = makeSettings()
        settings.edge = .bottom
        settings.ramp = .violet
        settings.material = .clear
        settings.displayUUID = "SCREEN-UUID"
        settings.dimWhenFocused = false
        settings.lengthFraction = 0.55
        // A second instance over the same store is a stand-in for relaunching.
        let reopened = SillSettings(defaults: defaults)
        expect(reopened.edge == .bottom)
        expect(reopened.ramp == .violet)
        expect(reopened.material == .clear)
        expect(reopened.displayUUID == "SCREEN-UUID")
        expect(!reopened.dimWhenFocused)
        expect(approx(reopened.lengthFraction, 0.55))
    }

    func lengthFractionIsClampedToItsRange() {
        let (settings, _) = makeSettings()
        settings.lengthFraction = 3
        expect(settings.lengthFraction == WaveGeometry.maximumLengthFraction)
        settings.lengthFraction = 0.05
        expect(settings.lengthFraction == WaveGeometry.minimumLengthFraction)
        settings.lengthFraction = 0.65
        expect(approx(settings.lengthFraction, 0.65))
    }

    func sampleIntervalIsClampedToTheSliderRange() {
        let (settings, _) = makeSettings()
        settings.sampleInterval = 12
        expect(settings.sampleInterval == 5)
        settings.sampleInterval = 0.1
        expect(settings.sampleInterval == 0.5)
        settings.sampleInterval = 2.5
        expect(settings.sampleInterval == 2.5)
    }

    func materialAlphasDifferPerVariant() {
        expect(PanelMaterial.clear.backgroundAlpha == 0.62)
        expect(PanelMaterial.tinted.backgroundAlpha == 0.84)
        expect(PanelMaterial.clear.borderAlpha == 0.30)
        expect(PanelMaterial.tinted.secondaryTextAlpha == 0.78)
    }
}

struct SamplePlanTests {
    func timerSlackGrowsWithTheInterval() {
        // A band showing an hour does not need a wakeup accurate to 0.2s.
        expect(SamplePlan.tolerance(for: 1) == 0.2)
        expect(SamplePlan.tolerance(for: 0.5) == 0.2)
        expect(approx(SamplePlan.tolerance(for: 20), 1))
        expect(SamplePlan.tolerance(for: 30) > SamplePlan.tolerance(for: 5))
    }

    func fullSpeedWhenPluggedInAndVisible() {
        expect(SamplePlan.interval(preferred: 1, state: PowerState()) == 1)
        expect(SamplePlan.interval(preferred: 0.5, state: PowerState()) == 0.5)
    }

    func suspendedWhenNothingCanBeSeen() {
        expect(SamplePlan.interval(preferred: 1, state: PowerState(occluded: true)) == nil)
        expect(SamplePlan.interval(preferred: 1, state: PowerState(displayAsleep: true)) == nil)
        expect(SamplePlan.interval(preferred: 1, state: PowerState(screenLocked: true)) == nil)
        expect(SamplePlan.isSuspended(PowerState(occluded: true)))
        expect(!SamplePlan.isSuspended(PowerState()))
    }

    func batteryHalvesTheRateWithAFloor() {
        expect(SamplePlan.interval(preferred: 1, state: PowerState(onBattery: true)) == 2)
        expect(SamplePlan.interval(preferred: 5, state: PowerState(onBattery: true)) == 10)
        expect(SamplePlan.interval(preferred: 0.5, state: PowerState(onBattery: true)) == 2)
    }

    func lowPowerModeSlowsFurtherAndBeatsBattery() {
        let state = PowerState(onBattery: true, lowPowerMode: true)
        expect(SamplePlan.interval(preferred: 1, state: state) == 4)
        expect(SamplePlan.interval(preferred: 5, state: state) == 20)
    }

    func suspensionBeatsEveryOtherRule() {
        let state = PowerState(onBattery: true, lowPowerMode: true, occluded: true)
        expect(SamplePlan.interval(preferred: 1, state: state) == nil)
    }
}

struct ProcessListTests {
    let rows = [
        ProcessUsage(pid: 1, name: "Xcode", cpuPercent: 18.4),
        ProcessUsage(pid: 2, name: "node", cpuPercent: 11.9),
        ProcessUsage(pid: 3, name: "Chrome Helper", cpuPercent: 9.1),
    ]

    func freshValuesLandInTheFrozenOrder() {
        let fresh = [
            ProcessUsage(pid: 3, name: "Chrome Helper", cpuPercent: 40),
            ProcessUsage(pid: 1, name: "Xcode", cpuPercent: 2),
        ]
        let merged = ProcessSampler.merge(frozen: rows, fresh: fresh)
        // Order is the frozen one; the numbers are the new ones.
        expect(merged.map(\.pid) == [1, 2, 3])
        expect(approx(merged[0].cpuPercent, 2))
        expect(approx(merged[2].cpuPercent, 40))
    }

    func processesThatWentAwayReadZeroRatherThanDisappearing() {
        let merged = ProcessSampler.merge(frozen: rows, fresh: [])
        expect(merged.count == 3)
        expect(merged.allSatisfy { $0.cpuPercent == 0 })
    }

    func anEmptyFreezeTakesTheFreshListWholesale() {
        expect(ProcessSampler.merge(frozen: [], fresh: rows) == rows)
    }

    func throughputFormatting() {
        expect(Format.throughput(bytesPerSecond: 0) == "0.0 MB/s")
        expect(Format.throughput(bytesPerSecond: 2_516_582) == "2.4 MB/s")
    }
}

struct SettingsSnapshotTests {
    func makeSettings() -> SillSettings {
        SillSettings(defaults: UserDefaults(suiteName: "sill.tests.\(UUID().uuidString)")!)
    }

    func aSnapshotCarriesEverythingPlacementDependsOn() {
        let settings = makeSettings()
        let before = settings.snapshot
        settings.edge = .top
        expect(settings.snapshot != before)
        expect(settings.snapshot.edge == .top)
    }

    func anUnchangedStoreProducesAnEqualSnapshot() {
        // This is what stops a defaults notification from rebuilding anything:
        // the chatter is constant, the values are not.
        let settings = makeSettings()
        expect(settings.snapshot == settings.snapshot)
        let other = settings.snapshot
        settings.launchAtLogin = !settings.launchAtLogin   // not a placement value
        expect(settings.snapshot == other)
    }

    func everyPlacementValueIsInTheSnapshot() {
        let settings = makeSettings()
        var seen: [SettingsSnapshot] = [settings.snapshot]
        settings.edge = .bottom;            seen.append(settings.snapshot)
        settings.ramp = .amber;             seen.append(settings.snapshot)
        settings.material = .clear;         seen.append(settings.snapshot)
        settings.dimWhenFocused = false;    seen.append(settings.snapshot)
        settings.sampleInterval = 2.5;      seen.append(settings.snapshot)
        settings.lengthFraction = 0.45;     seen.append(settings.snapshot)
        settings.displayUUID = "SCREEN";    seen.append(settings.snapshot)
        settings.showsOnAllDisplays = true; seen.append(settings.snapshot)
        // Each change produced a snapshot different from the one before it.
        for i in 1..<seen.count { expect(seen[i] != seen[i - 1], "step \(i) went unnoticed") }
    }
}

struct ThroughputTests {
    func directionsAreKeptApart() {
        let rate = Throughput(down: 2_500_000, up: 300_000)
        expect(rate.down > rate.up)
        expect(approx(rate.total, 2_800_000))
        expect(Throughput.zero.total == 0)
    }

    func compactRatesFitATile() {
        expect(Format.rate(bytesPerSecond: 0) == "0.0")
        expect(Format.rate(bytesPerSecond: 2_516_582) == "2.4")
        expect(Format.rate(bytesPerSecond: 12 * 1_048_576) == "12")
        expect(Format.rate(bytesPerSecond: 250 * 1_048_576) == "250")
        // A counter that went backwards is not a negative rate.
        expect(Format.rate(bytesPerSecond: -500) == "0.0")
    }

    func theFirstSampleHasNoBaselineToSubtract() {
        // Both samplers report zero until they have something to compare with,
        // rather than reporting the machine's lifetime total as one second.
        expect(NetworkSampler().sample() == .zero)
        expect(DiskIOSampler().sample() == .zero)
    }

    func aSecondSampleReportsARate() {
        let network = NetworkSampler()
        _ = network.sample()
        let second = network.sample()
        // Real traffic may be zero on an idle link; it must never be negative.
        expect(second.down >= 0 && second.up >= 0)
    }
}

struct HeadlineTests {
    func theJudgementStandsAloneOnTheFirstLine() {
        expect(Headroom.title(cpuPercent: 42, memoryPercent: 73) == "Comfortable · 44 headroom")
        expect(Headroom.title(cpuPercent: 0, memoryPercent: 0) == "Plenty of room · 100 headroom")
    }

    func theSecondLineSaysWhatTheWaveDraws() {
        expect(Headroom.encoding(envelopeValue: 34, fillValue: 61)
               == "envelope 34% cpu · fill 61% memory")
        expect(Headroom.encoding(envelope: .network, fill: .disk,
                                 envelopeValue: 88, fillValue: 12, fullScale: "12.3 MB/s")
               == "envelope 88% network · fill 12% disk · full band 12.3 MB/s")
    }

    func theTwoLinesTogetherAreTheOldSummary() {
        let title = Headroom.title(cpuPercent: 42, memoryPercent: 73)
        let encoding = Headroom.encoding(envelopeValue: 42, fillValue: 73)
        expect("\(title) · \(encoding)"
               == Headroom.summary(cpuPercent: 42, memoryPercent: 73))
    }
}

struct LiftSettingTests {
    func theBandStaysBehindWindowsByDefault() {
        let suite = "sill.tests.\(UUID().uuidString)"
        let settings = SillSettings(defaults: UserDefaults(suiteName: suite)!)
        // Sill lives on the wallpaper: opening it must not cover the window
        // someone is working in unless they ask for that.
        expect(!settings.liftsWhenOpen)
        expect(!settings.snapshot.liftsWhenOpen)
        settings.liftsWhenOpen = true
        expect(settings.snapshot.liftsWhenOpen)
    }
}

struct SpanTests {
    func automaticLeavesTheIntervalAlone() {
        expect(Span.interval(minutes: Span.automatic, samples: 300, fallback: 1) == 1)
        expect(Span.interval(minutes: 0, samples: 300, fallback: 2.5) == 2.5)
        // A band with nowhere to put samples cannot be stretched either.
        expect(Span.interval(minutes: 10, samples: 1, fallback: 1) == 1)
    }

    func aSpanPicksTheIntervalThatFillsTheBand() {
        // 301 points over five minutes is one point a second.
        expect(approx(Span.interval(minutes: 5, samples: 301, fallback: 1), 1))
        // Same band, twice the history: sample half as often.
        expect(approx(Span.interval(minutes: 10, samples: 301, fallback: 1), 2))
        // A short band showing an hour samples rarely, which costs less.
        expect(approx(Span.interval(minutes: 60, samples: 121, fallback: 1), 30))
    }

    func anImpossibleSpanGetsAsCloseAsItCan() {
        // Too much history for too few points: the interval hits its ceiling.
        let interval = Span.interval(minutes: 60, samples: 31, fallback: 1)
        expect(interval == Span.slowestDerivedInterval)
        // And the panel can say what it actually holds rather than what was asked.
        let achieved = Span.achievedMinutes(minutes: 60, samples: 31, fallback: 1)
        expect(achieved < 60)
        expect(approx(achieved, 15))
    }

    func aTinySpanNeverSamplesFasterThanTheFloor() {
        let interval = Span.interval(minutes: 1, samples: 3000, fallback: 1)
        expect(interval == SillSettings.minimumInterval)
    }

    func theSettingClampsToItsRange() {
        let settings = SillSettings(defaults: UserDefaults(suiteName: "sill.tests.\(UUID().uuidString)")!)
        expect(settings.spanMinutes == Span.automatic)
        settings.spanMinutes = 900
        expect(settings.spanMinutes == Span.maximumMinutes)
        settings.spanMinutes = 0.2
        expect(settings.spanMinutes == Span.minimumMinutes)
        settings.spanMinutes = -5
        expect(settings.spanMinutes == Span.automatic)
        settings.spanMinutes = 12
        expect(approx(settings.spanMinutes, 12))
    }
}

struct IntroductionTests {
    func theAppIntroducesItselfExactlyOnce() {
        let suite = "sill.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SillSettings(defaults: defaults)
        expect(!settings.hasIntroduced, "a fresh install has not been introduced")
        settings.hasIntroduced = true
        // Across a relaunch, it stays introduced: the hint is a first-run
        // courtesy, not a recurring interruption.
        expect(SillSettings(defaults: defaults).hasIntroduced)
    }

    func theIntroductionIsNotAPlacementSetting() {
        let settings = SillSettings(defaults: UserDefaults(suiteName: "sill.tests.\(UUID().uuidString)")!)
        let before = settings.snapshot
        settings.hasIntroduced = true
        // It must not trigger a rebuild of every band.
        expect(settings.snapshot == before)
    }
}
