import CoreGraphics
@testable import SillCore

struct CurveTests {
    func smoothingIsWeightedAverage() {
        // One pass; ends clamp to themselves: (0+0+4)/4 == 1, (0+8+0)/4 == 2.
        expect(Curve.smooth([0, 4, 0], passes: 1) == [1, 2, 1])
    }

    func twoPassesAreCalmerThanOneAndKeepTheShape() {
        let spiky: [Double] = [0, 0, 90, 0, 0, 0, 70, 0, 0]
        let once = Curve.smooth(spiky, passes: 1)
        let twice = Curve.smooth(spiky, passes: 2)
        // Calmer: the peaks come down and the troughs come up.
        expect(twice.max()! < once.max()!)
        // But a spike is still a spike, in the same place.
        expect(twice.firstIndex(of: twice.max()!) == once.firstIndex(of: once.max()!))
        expect(twice.max()! > spiky.reduce(0, +) / Double(spiky.count))
    }

    func smoothingNeverInventsRange() {
        let values: [Double] = [10, 90, 20, 80]
        for passes in 1...4 {
            let smoothed = Curve.smooth(values, passes: passes)
            expect(smoothed.allSatisfy { $0 >= values.min()! && $0 <= values.max()! })
        }
    }

    func smoothingPreservesConstantSeries() {
        expect(Curve.smooth([7, 7, 7, 7]) == [7, 7, 7, 7])
        expect(Curve.smooth([7, 7, 7, 7], passes: 5) == [7, 7, 7, 7])
    }

    func smoothingLeavesShortSeriesAlone() {
        expect(Curve.smooth([3, 9]) == [3, 9])
    }

    func tangentIsZeroAtALocalExtreme() {
        expect(approx(Curve.tangents([0, 10, 0], step: 1)[1], 0))
    }

    func neverOvershootsInputRange() {
        let series: [[Double]] = [
            [0, 100, 0, 100, 0],
            [5, 5, 90, 90, 5],
            [40, 41, 39, 80, 12, 12, 60],
            [0, 0, 0, 100],
        ]
        for values in series {
            let lo = values.min()!, hi = values.max()!
            for t in stride(from: 0.0, through: Double(values.count - 1), by: 0.01) {
                let v = Curve.value(values, at: t)
                expect(v >= lo - 1e-9, "under at \(t) in \(values)")
                expect(v <= hi + 1e-9, "over at \(t) in \(values)")
            }
        }
    }

    func monotoneSegmentStaysMonotone() {
        let values: [Double] = [0, 1, 2, 3, 10, 11]
        var last = -Double.infinity
        for t in stride(from: 0.0, through: 5.0, by: 0.01) {
            let v = Curve.value(values, at: t)
            expect(v >= last - 1e-9)
            last = v
        }
    }

    func interpolationPassesThroughSamples() {
        let values: [Double] = [12, 88, 40, 51]
        for (i, v) in values.enumerated() {
            expect(approx(Curve.value(values, at: Double(i)), v))
        }
    }

    func pathEndsAtTheNewestSample() {
        let t = EdgeTransform(edge: .right, length: 12)
        let path = Curve.path(depths: [10, 20, 30, 40], transform: t)
        expect(!path.isEmpty)
        expect(approx(path.currentPoint.y, 0, 0.001))  // newest sample at the bottom
    }
}

struct SlicedPathTests {
    func aSliceDrawsTheSameShapeAsTheValuesAlone() {
        let all: [Double] = [10, 40, 12, 33, 28, 19, 41, 22]
        let transform = EdgeTransform(edge: .right, length: 12)
        let fromSlice = Curve.path(depths: all.suffix(4), transform: transform)
        let fromArray = Curve.path(depths: Array(all.suffix(4)), transform: transform)
        expect(fromSlice == fromArray)
        expect(!fromSlice.isEmpty)
        expect(fromSlice.boundingBox.equalTo(fromArray.boundingBox))
    }

    func aSliceIsNotTheWholeHistory() {
        let all: [Double] = [10, 40, 12, 33, 28, 19, 41, 22]
        let transform = EdgeTransform(edge: .right, length: 12)
        let whole = Curve.path(depths: all, transform: transform)
        expect(whole != Curve.path(depths: all.suffix(4), transform: transform))
    }

    func tangentsWorkOnASliceWithANonZeroStart() {
        let all: [Double] = [0, 0, 0, 5, 10, 15]
        let sliced = Curve.tangents(all.suffix(3), step: 1)
        let copied = Curve.tangents(Array(all.suffix(3)), step: 1)
        expect(sliced == copied)
    }
}

struct AreaPathTests {
    let transform = EdgeTransform(edge: .right, length: 40)

    func theAreaSpansBetweenTheTwoStrands() {
        let top: [Double] = [50, 60, 55, 58]
        let bottom: [Double] = [26, 20, 24, 22]
        let area = Curve.areaPath(top: top, bottom: bottom, transform: transform)
        expect(!area.isEmpty)
        let box = area.boundingBox
        let strandBox = Curve.path(depths: top, transform: transform).boundingBox
            .union(Curve.path(depths: bottom, transform: transform).boundingBox)
        // The fill covers exactly the ground the two strands cover.
        expect(approx(box.minX, strandBox.minX, 0.5))
        expect(approx(box.maxX, strandBox.maxX, 0.5))
        expect(approx(box.minY, strandBox.minY, 0.5))
        expect(approx(box.maxY, strandBox.maxY, 0.5))
    }

    func theAreaContainsThePointsBetweenTheStrands() {
        let top = [Double](repeating: 60, count: 6)
        let bottom = [Double](repeating: 20, count: 6)
        let area = Curve.areaPath(top: top, bottom: bottom, transform: transform)
        // Depth 40 is between 20 and 60; the band's own mid-line.
        let inside = transform.point(along: 10, depth: 40)
        expect(area.contains(inside), "the fill has a hole where the wave is")
        let outside = transform.point(along: 10, depth: 5)
        expect(!area.contains(outside), "the fill spilled past the strands")
    }

    func aDegenerateAreaIsEmptyRatherThanWrong() {
        expect(Curve.areaPath(top: [], bottom: [], transform: transform).isEmpty)
        expect(Curve.areaPath(top: [10], bottom: [20], transform: transform).isEmpty)
        // Mismatched lengths are a caller error, not a shape.
        expect(Curve.areaPath(top: [10, 20], bottom: [5], transform: transform).isEmpty)
    }

    func aSliceWorksAsWellAsAnArray() {
        let top: [Double] = [0, 50, 60, 55, 58, 40]
        let bottom: [Double] = [0, 26, 20, 24, 22, 30]
        let fromSlices = Curve.areaPath(top: top.suffix(4), bottom: bottom.suffix(4),
                                        transform: transform)
        let fromArrays = Curve.areaPath(top: Array(top.suffix(4)), bottom: Array(bottom.suffix(4)),
                                        transform: transform)
        expect(fromSlices == fromArrays)
    }
}
