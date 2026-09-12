import CoreGraphics
@testable import SillCore

struct PanelPlacementTests {
    let visible = CGRect(x: 0, y: 0, width: 1700, height: 1000)
    let panel = CGSize(width: 344, height: 500)

    func band(_ edge: ScreenEdge) -> CGRect {
        Layout.waveFrame(edge: edge, visibleFrame: visible)
    }

    func itNeverWandersOffToACorner() {
        let edge = ScreenEdge.right
        // The whole desktop is covered: there is no clear spot anywhere, so it
        // stays where it belongs rather than hunting for a corner.
        let chosen = PanelPlacement.choose(edge: edge, band: band(edge), panelSize: panel,
                                           visibleFrame: visible, windows: [visible])
        let preferred = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                  panelSize: panel,
                                                  visibleFrame: visible)[0]
        expect(chosen.equalTo(preferred), "the panel ran off to a corner")
    }

    func everyCandidateStaysBesideItsBand() {
        for edge in ScreenEdge.allCases {
            let options = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                    panelSize: panel, visibleFrame: visible)
            for option in options {
                // Beside the band along its own axis: never across the screen.
                let along = edge.isVertical
                    ? abs(option.midX - band(edge).midX) : abs(option.midY - band(edge).midY)
                expect(along < panel.width * 2.5, "\(edge): candidate is off in the distance")
            }
        }
    }

    func nearnessStillCountsWhenBothSpotsAreClear() {
        let edge = ScreenEdge.right
        let nearest = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                panelSize: panel, visibleFrame: visible)[0]
        let chosen = PanelPlacement.choose(edge: edge, band: band(edge), panelSize: panel,
                                           visibleFrame: visible, windows: [])
        expect(chosen.equalTo(nearest), "wandered off with the whole desktop free")
    }

    func everyCandidateSitsBesideTheBandAndInsideTheScreen() {
        for edge in ScreenEdge.allCases {
            let options = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                    panelSize: panel, visibleFrame: visible)
            expect(!options.isEmpty, "\(edge)")
            for option in options {
                expect(!option.intersects(band(edge)), "\(edge): candidate overlaps the band")
                expect(visible.contains(option), "\(edge): candidate left the screen")
            }
        }
    }

    func anEmptyDesktopKeepsThePreferredSpot() {
        for edge in ScreenEdge.allCases {
            let preferred = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                      panelSize: panel,
                                                      visibleFrame: visible)[0]
            let chosen = PanelPlacement.choose(edge: edge, band: band(edge), panelSize: panel,
                                               visibleFrame: visible, windows: [])
            expect(chosen.equalTo(preferred), "\(edge): moved with nothing in the way")
        }
    }

    func aCoveredSpotIsAbandonedForAClearOne() {
        let edge = ScreenEdge.right
        let preferred = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                  panelSize: panel, visibleFrame: visible)[0]
        // A window sitting exactly where the panel wants to open.
        let window = preferred.insetBy(dx: -40, dy: -40)
        let chosen = PanelPlacement.choose(edge: edge, band: band(edge), panelSize: panel,
                                           visibleFrame: visible, windows: [window])
        expect(!chosen.equalTo(preferred), "the panel opened straight into a window")
        expect(PanelPlacement.coverage(of: chosen, by: [window])
               < PanelPlacement.coverage(of: preferred, by: [window]))
    }

    func aFullyCoveredDesktopStillPlacesThePanel() {
        let edge = ScreenEdge.right
        let chosen = PanelPlacement.choose(edge: edge, band: band(edge), panelSize: panel,
                                           visibleFrame: visible, windows: [visible])
        // Nowhere is clear; it still lands somewhere sane rather than nowhere.
        expect(visible.contains(chosen))
        expect(!chosen.intersects(band(edge)))
    }

    func aMostlyCoveredSpotCountsAsHidden() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 400)
        expect(!PanelPlacement.isHidden(frame, by: []))
        // A quarter covered is still readable; most of it is not.
        let quarter = CGRect(x: 0, y: 0, width: 300, height: 100)
        expect(!PanelPlacement.isHidden(frame, by: [quarter]))
        expect(PanelPlacement.isHidden(frame, by: [frame]))
    }

    func coverageIsMeasuredHonestly() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        expect(approx(PanelPlacement.coverage(of: frame, by: []), 0))
        expect(approx(PanelPlacement.coverage(of: frame, by: [frame]), 1))
        let half = CGRect(x: 0, y: 0, width: 100, height: 50)
        expect(approx(PanelPlacement.coverage(of: frame, by: [half]), 0.5, 0.05))
        // Overlapping windows are not double-counted.
        expect(approx(PanelPlacement.coverage(of: frame, by: [half, half]), 0.5, 0.05))
    }

    func aMarginalImprovementIsNotWorthMovingFor() {
        let edge = ScreenEdge.right
        let options = PanelPlacement.candidates(edge: edge, band: band(edge),
                                                panelSize: panel, visibleFrame: visible)
        // A sliver over the preferred spot: not enough to justify jumping.
        let sliver = CGRect(x: options[0].minX, y: options[0].minY,
                            width: options[0].width, height: 12)
        let chosen = PanelPlacement.choose(edge: edge, band: band(edge), panelSize: panel,
                                           visibleFrame: visible, windows: [sliver])
        expect(chosen.equalTo(options[0]))
    }
}
