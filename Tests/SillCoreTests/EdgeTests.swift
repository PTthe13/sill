import CoreGraphics
@testable import SillCore

struct EdgeTests {
    let L: CGFloat = 100
    let T = WaveGeometry.thickness

    func transform(_ e: ScreenEdge) -> EdgeTransform { EdgeTransform(edge: e, length: L) }

    func bandSizes() {
        expect(transform(.left).size == CGSize(width: T, height: L))
        expect(transform(.right).size == CGSize(width: T, height: L))
        expect(transform(.top).size == CGSize(width: L, height: T))
        expect(transform(.bottom).size == CGSize(width: L, height: T))
    }

    func depthZeroSitsAgainstTheBezel() {
        // Band-local space is y-up, like Core Animation.
        expect(transform(.left).point(along: 0, depth: 0) == CGPoint(x: 0, y: L))
        expect(transform(.right).point(along: 0, depth: 0) == CGPoint(x: T, y: L))
        expect(transform(.top).point(along: 0, depth: 0) == CGPoint(x: L, y: T))
        expect(transform(.bottom).point(along: 0, depth: 0) == CGPoint(x: L, y: 0))
    }

    func newestSampleSitsAtTheCorrectEnd() {
        // Vertical: newest at the bottom. Horizontal: newest at the left.
        expect(transform(.left).point(along: L, depth: 10).y == 0)
        expect(transform(.right).point(along: L, depth: 10).y == 0)
        expect(transform(.top).point(along: L, depth: 10).x == 0)
        expect(transform(.bottom).point(along: L, depth: 10).x == 0)
    }

    func depthGrowsInwardFromTheEdge() {
        expect(transform(.left).point(along: 0, depth: 20).x == 20)
        expect(transform(.right).point(along: 0, depth: 20).x == T - 20)
        expect(transform(.top).point(along: 0, depth: 20).y == T - 20)
        expect(transform(.bottom).point(along: 0, depth: 20).y == 20)
    }

    func scrollDirectionMatchesTimeDirection() {
        // History moves away from the end new samples land on: down a vertical
        // band, leftward along a horizontal one.
        expect(transform(.left).scrollPerSample == CGVector(dx: 0, dy: -4))
        expect(transform(.right).scrollPerSample == CGVector(dx: 0, dy: -4))
        expect(transform(.top).scrollPerSample == CGVector(dx: -4, dy: 0))
        expect(transform(.bottom).scrollPerSample == CGVector(dx: -4, dy: 0))
    }

    func scrollMovesAnAgeingSampleExactlyOneStep() {
        for edge in ScreenEdge.allCases {
            let t = transform(edge)
            // One tick later the same sample is one step OLDER, so `along`
            // grows: where it lands must be the scroll vector away.
            let before = t.point(along: 9 * WaveGeometry.step, depth: 20)
            let after = t.point(along: 10 * WaveGeometry.step, depth: 20)
            let scroll = t.scrollPerSample
            expect(approx(after.x, before.x + scroll.dx), "\(edge)")
            expect(approx(after.y, before.y + scroll.dy), "\(edge)")
        }
    }

    func gradientRunsNewestToOldest() {
        for edge in ScreenEdge.allCases {
            let t = transform(edge)
            let axis = t.gradientAxis
            let newest = t.point(along: L, depth: T / 2)
            let oldest = t.point(along: 0, depth: T / 2)
            if edge.isVertical {
                expect(axis.start.y == newest.y)
                expect(axis.end.y == oldest.y)
            } else {
                expect(axis.start.x == newest.x)
                expect(axis.end.x == oldest.x)
            }
        }
    }

    func sampleCount() {
        expect(WaveGeometry.sampleCount(forLength: 432) == 109)
        expect(WaveGeometry.sampleCount(forLength: 0) == 1)
    }
}
