import CoreGraphics
@testable import SillCore

struct WaveModelTests {
    func theUnmeasuredStretchIsAStillLineDownTheMiddle() {
        let cpu = (0..<40).map { i in i % 2 == 0 ? 10.0 : 95.0 }
        let transform = EdgeTransform(edge: .right, length: 160)
        let frame = WaveModel.Frame(cpu: cpu, memory: cpu, available: 10)
        let young = frame.paths(transform: transform, sampleCount: 40)[0]
        // Ten measured samples at the newest end, thirty slots of still line
        // before them — not a blank stretch, and not invented readings.
        let middle = Double(WaveGeometry.thickness / 2)
        let expected = Curve.path(
            depths: [Double](repeating: middle, count: 30) + frame.depths[0].suffix(10),
            transform: transform)
        expect(young == expected)
        // And it still covers the whole strip.
        expect(approx(young.boundingBox.height,
                      frame.paths(transform: transform, sampleCount: 40)[0].boundingBox.height))
    }

    func aBandWithNoMeasurementsIsOneFlatLine() {
        let frame = WaveModel.Frame(cpu: [10, 20, 30], memory: [10, 20, 30], available: 0)
        let transform = EdgeTransform(edge: .top, length: 120)
        for path in frame.paths(transform: transform, sampleCount: 30) {
            expect(!path.isEmpty, "the band shows something from the first frame")
            // Flat: no thickness across the band at all.
            expect(path.boundingBox.height < 0.001, "\(path.boundingBox)")
        }
    }

    let model = WaveModel()

    func mixSpansEnvelopeToEnvelope() {
        expect(approx(WaveModel.mix(strand: 0), 1))
        expect(approx(WaveModel.mix(strand: 4), 0))
        expect(approx(WaveModel.mix(strand: 8), -1))
    }

    func outerStrandsAreFirstAndLast() {
        expect(WaveModel.isOuter(strand: 0))
        expect(WaveModel.isOuter(strand: 8))
        for k in 1...7 { expect(!WaveModel.isOuter(strand: k)) }
    }

    func fillMapping() {
        expect(approx(WaveModel.fill(memoryPercent: 0), 0.16))
        expect(approx(WaveModel.fill(memoryPercent: 100), 1.0))
        expect(approx(WaveModel.fill(memoryPercent: 50), 0.58))
        expect(approx(WaveModel.fill(memoryPercent: 240), 1.0))
        expect(approx(WaveModel.fill(memoryPercent: -5), 0.16))
    }

    var fullAmplitude: Double {
        Double(WaveGeometry.thickness / 2 - WaveGeometry.depthInset)
    }
    var mid: Double { Double(WaveGeometry.thickness / 2) }

    func amplitudeAtKnownInputs() {
        expect(approx(model.amplitude(0), 0))
        expect(approx(model.amplitude(100), fullAmplitude))
        expect(approx(model.amplitude(50), fullAmplitude / 2))
        expect(approx(model.amplitude(130), fullAmplitude))
        // The band keeps room to show the difference near the top of the scale.
        expect(fullAmplitude >= 25, "too little depth to resolve a busy machine")
    }

    func outerStrandsIgnoreMemoryFill() {
        let cpu = [Double](repeating: 100, count: 30)
        let low = [Double](repeating: 0, count: 30)
        let high = [Double](repeating: 100, count: 30)
        expect(model.depths(strand: 0, cpu: cpu, memory: low)
                == model.depths(strand: 0, cpu: cpu, memory: high))
        expect(approx(model.depths(strand: 0, cpu: cpu, memory: low).last!,
                      mid + fullAmplitude))
        expect(approx(model.depths(strand: 8, cpu: cpu, memory: low).last!,
                      mid - fullAmplitude))
    }

    func innerStrandScalesWithMemory() {
        let cpu = [Double](repeating: 100, count: 30)
        let mem = [Double](repeating: 50, count: 30)
        // strand 2: mix = 1 - 4/8 = 0.5, fill(50) = 0.58
        expect(approx(model.depths(strand: 2, cpu: cpu, memory: mem).last!,
                      mid + fullAmplitude * 0.5 * 0.58))
    }

    func strandLagsByThreeSamplesPerIndex() {
        var cpu = [Double](repeating: 0, count: 20)
        cpu[10] = 100
        let mem = [Double](repeating: 100, count: 20)
        let d = model.depths(strand: 1, cpu: cpu, memory: mem)
        expect(approx(d[13], mid + fullAmplitude * 0.75))
        expect(approx(d[10], mid))
    }

    func laggedIndexClampsAtStartOfHistory() {
        let flat = [Double](repeating: 30, count: 10)
        let d = model.depths(strand: 8, cpu: flat, memory: flat)
        expect(d.count == 10)
        expect(!d.contains { $0.isNaN })
    }

    func allDepthsReturnsNineStrandsInsideTheBand() {
        let cpu = (0..<60).map { Double(($0 * 13) % 101) }
        let mem = (0..<60).map { Double(($0 * 7) % 101) }
        let all = model.allDepths(cpu: cpu, memory: mem)
        expect(all.count == 9)
        for strand in all {
            expect(strand.count == 60)
            expect(strand.allSatisfy {
                $0 >= Double(WaveGeometry.depthInset) - 0.001
                    && $0 <= Double(WaveGeometry.thickness - WaveGeometry.depthInset) + 0.001
            })
        }
    }

    func strokeWidthsAndOpacities() {
        // The envelope carries the shape; the fill strands are texture.
        expect(WaveModel.lineWidth(strand: 0) == WaveModel.outerLineWidth)
        expect(WaveModel.lineWidth(strand: 3) == WaveModel.innerLineWidth)
        expect(WaveModel.outerLineWidth > WaveModel.innerLineWidth * 2,
               "the two main strands should read as clearly heavier")
        expect(WaveModel.opacity(strand: 8) > WaveModel.opacity(strand: 4))
        expect(WaveModel.opacity(strand: 4) > 0.4, "fill strands must stay visible")
    }
}

struct PresmoothedDepthsTests {
    let model = WaveModel()

    func presmoothedMatchesSmoothingInside() {
        let cpu = (0..<40).map { Double(($0 * 17) % 101) }
        let memory = (0..<40).map { Double(($0 * 11) % 101) }
        let a = model.allDepths(cpu: cpu, memory: memory)
        let b = model.allDepths(smoothedCPU: Curve.smooth(cpu),
                                smoothedMemory: Curve.smooth(memory))
        expect(a.count == b.count)
        for (left, right) in zip(a, b) { expect(left == right) }
    }
}

struct SharedFrameTests {
    func aSharedFrameMatchesComputingItPerBand() {
        let cpu = (0..<50).map { Double(($0 * 13) % 101) }
        let memory = (0..<50).map { Double(($0 * 7) % 101) }
        let frame = WaveModel.Frame(cpu: cpu, memory: memory)
        let direct = WaveModel().allDepths(cpu: cpu, memory: memory)
        expect(frame.depths.count == direct.count)
        for (a, b) in zip(frame.depths, direct) { expect(a == b) }
        expect(frame.loads == Palette.sliceValues(history: Curve.smooth(cpu),
                                                  count: Palette.profileSlices))
        // The raw readings ride along for the hover readout.
        expect(frame.cpu == cpu)
        expect(frame.memory == memory)
    }
}

struct FramePathTests {
    func aFramesPathsMatchBuildingThemByHand() {
        let cpu = (0..<40).map { Double(($0 * 9) % 101) }
        let memory = (0..<40).map { Double(($0 * 5) % 101) }
        let frame = WaveModel.Frame(cpu: cpu, memory: memory)
        let transform = EdgeTransform(edge: .right, length: 100)
        let paths = frame.paths(transform: transform, sampleCount: 26)
        expect(paths.count == WaveModel.strandCount)
        for (k, path) in paths.enumerated() {
            let expected = Curve.path(depths: frame.depths[k].suffix(26), transform: transform)
            expect(path == expected, "strand \(k)")
        }
    }

    func askingForMoreSamplesThanExistPadsTheRestWithStillLine() {
        let cpu = [Double](repeating: 40, count: 10)
        let frame = WaveModel.Frame(cpu: cpu, memory: cpu)
        let transform = EdgeTransform(edge: .top, length: 40)
        let paths = frame.paths(transform: transform, sampleCount: 500)
        expect(paths.allSatisfy { !$0.isEmpty })
        // The ten samples it has, with the other 490 slots drawn down the
        // middle of the band rather than left blank.
        let middle = Double(WaveGeometry.thickness / 2)
        let padded = [Double](repeating: middle, count: 490) + frame.depths[0]
        expect(paths[0] == Curve.path(depths: padded, transform: transform))
    }
}
