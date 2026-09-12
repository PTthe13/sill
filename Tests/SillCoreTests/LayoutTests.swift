import CoreGraphics
@testable import SillCore

struct LayoutTests {
    // A 1710x1069 visible area starting 25pt up from the screen origin.
    let vf = CGRect(x: 0, y: 25, width: 1710, height: 1069)
    let t = WaveGeometry.thickness

    func verticalBandIsCentredAndFlushToItsEdge() {
        let left = Layout.waveFrame(edge: .left, visibleFrame: vf)
        expect(left.width == t)
        // Same fraction of the screen as a horizontal band, but of the height.
        expect(approx(left.height, vf.height * WaveGeometry.defaultLengthFraction))
        expect(approx(left.minX, vf.minX + Layout.edgeInset))
        expect(approx(left.midY, vf.midY))

        let right = Layout.waveFrame(edge: .right, visibleFrame: vf)
        expect(approx(right.maxX, vf.maxX - Layout.edgeInset))
        expect(approx(right.midY, vf.midY))
    }

    func horizontalBandSpansTheSameFractionCentred() {
        let top = Layout.waveFrame(edge: .top, visibleFrame: vf)
        expect(approx(top.width, vf.width * WaveGeometry.defaultLengthFraction))
        expect(top.height == t)
        expect(approx(top.maxY, vf.maxY - Layout.edgeInset))
        expect(approx(top.midX, vf.midX))

        let bottom = Layout.waveFrame(edge: .bottom, visibleFrame: vf)
        expect(approx(bottom.minY, vf.minY + Layout.edgeInset))
    }

    func bandCentresOnTheWholeScreenNotTheVisibleFrame() {
        // Menu bar at the top: the visible frame's middle sits 12.5pt below the
        // screen's, and a band centred on it looks off against the Dock.
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1094)
        let right = Layout.waveFrame(edge: .right, visibleFrame: vf, screenFrame: screen)
        expect(approx(right.midY, screen.midY))
        expect(!approx(right.midY, vf.midY))
        // Still inset from the visible frame on the edge it hugs.
        expect(approx(right.maxX, vf.maxX - Layout.edgeInset))
        // The window it lives in moves with it.
        let window = Layout.windowFrame(edge: .right, visibleFrame: vf, panelExtent: 0,
                                        screenFrame: screen)
        expect(approx(window.midY, screen.midY))
    }

    func centringNeverPushesABandOutOfTheVisibleArea() {
        // A full-length band on a screen with a menu bar: centring on the whole
        // screen would hang it over the bar, so the clamp wins.
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1094)
        let f = Layout.waveFrame(edge: .left, visibleFrame: vf, fraction: 1, screenFrame: screen)
        expect(f.minY >= vf.minY - 0.001)
        expect(f.maxY <= vf.maxY + 0.001)
    }

    func bandNeverExceedsTheVisibleFrame() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 300)
        let f = Layout.waveFrame(edge: .right, visibleFrame: small, fraction: 1)
        expect(f.height <= small.height)
        expect(approx(f.height, 300 - 2 * Layout.edgeInset))
    }

    func lengthFractionAppliesEquallyOnEveryEdge() {
        for fraction in [0.3, 0.5, 0.8, 1.0] as [CGFloat] {
            let vertical = Layout.bandLength(edge: .right, visibleFrame: vf, fraction: fraction)
            let horizontal = Layout.bandLength(edge: .top, visibleFrame: vf, fraction: fraction)
            expect(approx(vertical, min(vf.height - 2 * Layout.edgeInset, vf.height * fraction)))
            expect(approx(horizontal, min(vf.width - 2 * Layout.edgeInset, vf.width * fraction)))
        }
    }

    func lengthFractionIsClampedToItsRange() {
        let tiny = Layout.bandLength(edge: .right, visibleFrame: vf, fraction: 0.01)
        expect(approx(tiny, vf.height * WaveGeometry.minimumLengthFraction))
        let huge = Layout.bandLength(edge: .top, visibleFrame: vf, fraction: 4)
        expect(approx(huge, min(vf.width - 2 * Layout.edgeInset, vf.width)))
    }

    func aLongerBandStaysCentred() {
        for edge in ScreenEdge.allCases {
            let short = Layout.waveFrame(edge: edge, visibleFrame: vf, fraction: 0.4)
            let long = Layout.waveFrame(edge: edge, visibleFrame: vf, fraction: 0.9)
            expect(approx(short.midX, long.midX), "\(edge)")
            expect(approx(short.midY, long.midY), "\(edge)")
            if edge.isVertical {
                expect(long.height > short.height)
                expect(approx(long.width, short.width))
            } else {
                expect(long.width > short.width)
                expect(approx(long.height, short.height))
            }
        }
    }

    func theClosedWindowKeepsAGutterForTheHoverReadout() {
        for edge in ScreenEdge.allCases {
            let band = Layout.waveFrame(edge: edge, visibleFrame: vf)
            let window = Layout.windowFrame(edge: edge, visibleFrame: vf, panelExtent: 0)
            // The band keeps its place against the screen edge...
            switch edge {
            case .left:   expect(approx(window.minX, band.minX))
            case .right:  expect(approx(window.maxX, band.maxX))
            case .top:    expect(approx(window.maxY, band.maxY))
            case .bottom: expect(approx(window.minY, band.minY))
            }
            // ...and the window reaches inboard far enough to show a chip.
            let grown = edge.isVertical ? window.width - band.width
                                        : window.height - band.height
            expect(approx(grown, Layout.hoverGutter), "\(edge)")
        }
    }

    func theBandStaysFlushWhileClosedAndSlidesInboardWhenOpen() {
        for edge in ScreenEdge.allCases {
            let closedWindow = Layout.windowFrame(edge: edge, visibleFrame: vf,
                                                  panelExtent: 0).size
            let closed = Layout.waveFrameInWindow(edge: edge, windowSize: closedWindow,
                                                  atOuterSide: true)
            let openWindow = Layout.windowFrame(edge: edge, visibleFrame: vf,
                                                panelExtent: Layout.panelWidth).size
            let open = Layout.waveFrameInWindow(edge: edge, windowSize: openWindow,
                                                atOuterSide: false)
            switch edge {
            case .left:
                expect(approx(closed.minX, 0)); expect(approx(open.maxX, openWindow.width))
            case .right:
                expect(approx(closed.maxX, closedWindow.width)); expect(approx(open.minX, 0))
            case .top:
                expect(approx(closed.maxY, closedWindow.height)); expect(approx(open.minY, 0))
            case .bottom:
                expect(approx(closed.minY, 0)); expect(approx(open.maxY, openWindow.height))
            }
        }
    }

    func thePanelIsWideEnoughToReadAtAGlance() {
        // A 23pt reading plus its label needs room; the panel earns its width.
        expect(Layout.panelWidth >= 320)
        // And the window still fits the chip's gutter beside the band.
        expect(Layout.hoverGutter >= 180)
    }

    func theHoverChipSitsInboardOfTheBand() {
        let size = CGSize(width: 170, height: 24)
        for edge in ScreenEdge.allCases {
            let band = WaveGeometry.size(edge: edge, length: 600)
            let along = edge.isVertical ? band.height / 2 : band.width / 2
            let chip = Layout.scrubChipFrame(edge: edge, bandSize: band,
                                             alongPoint: along, chipSize: size)
            let bandRect = CGRect(origin: .zero, size: band)
            expect(!chip.intersects(bandRect), "\(edge): chip overlaps the band")
            // Inboard means away from the screen edge, which is where the
            // window keeps its gutter.
            switch edge {
            case .right:  expect(chip.maxX < 0)
            case .left:   expect(chip.minX > band.width)
            case .top:    expect(chip.maxY < 0)
            case .bottom: expect(chip.minY > band.height)
            }
            expect(size.width + 10 <= Layout.hoverGutter, "the gutter cannot show the chip")
        }
    }

    func theChipIsClampedToTheEndsOfTheBand() {
        let size = CGSize(width: 170, height: 24)
        for edge in ScreenEdge.allCases {
            let band = WaveGeometry.size(edge: edge, length: 600)
            let span = edge.isVertical ? band.height : band.width
            let positions: [CGFloat] = [-500, 0, span / 2, span, span + 500]
            for along in positions {
                let chip = Layout.scrubChipFrame(edge: edge, bandSize: band,
                                                 alongPoint: along, chipSize: size)
                if edge.isVertical {
                    expect(chip.minY >= -0.001 && chip.maxY <= band.height + 0.001, "\(edge)")
                } else {
                    expect(chip.minX >= -0.001 && chip.maxX <= band.width + 0.001, "\(edge)")
                }
            }
        }
    }

    func openWindowGrowsInboardAndStaysFlush() {
        let extent = Layout.panelWidth
        let grow = extent + Layout.gap
        for edge in ScreenEdge.allCases {
            let closed = Layout.waveFrame(edge: edge, visibleFrame: vf)
            let open = Layout.windowFrame(edge: edge, visibleFrame: vf, panelExtent: extent)
            switch edge {
            case .left:
                expect(approx(open.minX, closed.minX))
                expect(approx(open.width, closed.width + grow))
            case .right:
                expect(approx(open.maxX, closed.maxX))
                expect(approx(open.width, closed.width + grow))
            case .top:
                expect(approx(open.maxY, closed.maxY))
                expect(approx(open.height, closed.height + grow))
            case .bottom:
                expect(approx(open.minY, closed.minY))
                expect(approx(open.height, closed.height + grow))
            }
        }
    }

    func panelTakesTheOuterStripAndWaveTheInboardOne() {
        let extent: CGFloat = 200
        for edge in ScreenEdge.allCases {
            let window = Layout.windowFrame(edge: edge, visibleFrame: vf, panelExtent: extent).size
            let wave = Layout.waveFrameInWindow(edge: edge, windowSize: window)
            let panel = Layout.panelFrameInWindow(
                edge: edge, windowSize: window,
                panelSize: edge.isVertical ? CGSize(width: extent, height: window.height)
                                           : CGSize(width: window.width, height: extent))
            expect(!wave.intersects(panel), "\(edge) wave and panel overlap")
            switch edge {
            case .left:
                expect(approx(panel.minX, 0)); expect(approx(wave.maxX, window.width))
            case .right:
                expect(approx(panel.maxX, window.width)); expect(approx(wave.minX, 0))
            case .top:
                expect(approx(panel.maxY, window.height)); expect(approx(wave.minY, 0))
            case .bottom:
                expect(approx(panel.minY, 0)); expect(approx(wave.maxY, window.height))
            }
        }
    }

    func horizontalPanelIsFullWidthAndSizedToContent() {
        let window = Layout.windowFrame(edge: .top, visibleFrame: vf, panelExtent: 137).size
        let panel = Layout.panelFrameInWindow(edge: .top, windowSize: window,
                                              panelSize: CGSize(width: window.width, height: 137))
        expect(approx(panel.width, window.width))
        expect(approx(panel.height, 137))       // never stretched, never clipped
        expect(approx(panel.maxY, window.height))
    }

    func verticalPanelHugsItsContentAndCentres() {
        let window = Layout.windowFrame(edge: .right, visibleFrame: vf,
                                        panelExtent: Layout.panelWidth).size
        let size = CGSize(width: Layout.panelWidth, height: 210)
        let panel = Layout.panelFrameInWindow(edge: .right, windowSize: window, panelSize: size)
        expect(approx(panel.height, 210))
        expect(approx(panel.midY, window.height / 2))
        expect(approx(panel.maxX, window.width))
    }

    func panelExtentIsTheThicknessAcrossTheBand() {
        let size = CGSize(width: 298, height: 210)
        expect(Layout.panelExtent(edge: .left, panelSize: size) == 298)
        expect(Layout.panelExtent(edge: .bottom, panelSize: size) == 210)
    }

    func panelSlidesInFromTheScreenEdge() {
        expect(Layout.panelEntryOffset(edge: .right).width == Layout.panelSlide)
        expect(Layout.panelEntryOffset(edge: .left).width == -Layout.panelSlide)
        expect(Layout.panelEntryOffset(edge: .top).height == Layout.panelSlide)
        expect(Layout.panelEntryOffset(edge: .bottom).height == -Layout.panelSlide)
    }
}

struct LiveRegionTests {
    let band = CGRect(x: 900, y: 100, width: 76, height: 600)
    let panel = CGRect(x: 200, y: 200, width: 344, height: 500)

    func aClosedBandOnlyTakesItsOwnStrip() {
        expect(Layout.liveRegions(band: band, panel: panel, isOpen: false) == [band])
        expect(Layout.takesMouse(at: CGPoint(x: 930, y: 400), band: band, panel: panel,
                                 isOpen: false))
        // The panel is not open, so its ground is not Sill's.
        expect(!Layout.takesMouse(at: CGPoint(x: 300, y: 400), band: band, panel: panel,
                                  isOpen: false))
    }

    func anOpenBandTakesTheBandAndThePanelButNotTheGap() {
        expect(Layout.liveRegions(band: band, panel: panel, isOpen: true).count == 2)
        expect(Layout.takesMouse(at: CGPoint(x: 930, y: 400), band: band, panel: panel,
                                 isOpen: true))
        expect(Layout.takesMouse(at: CGPoint(x: 300, y: 400), band: band, panel: panel,
                                 isOpen: true))
        // The desktop between them belongs to whatever is underneath — this is
        // the whole point of not taking the window's whole frame.
        expect(!Layout.takesMouse(at: CGPoint(x: 700, y: 400), band: band, panel: panel,
                                  isOpen: true), "the gap swallowed a click")
    }

    func aLittleSlackAroundTheBandMakesItClickable() {
        // Just outside the band, within the slack.
        expect(Layout.takesMouse(at: CGPoint(x: band.minX - 3, y: 400), band: band,
                                 panel: nil, isOpen: false))
        expect(!Layout.takesMouse(at: CGPoint(x: band.minX - 40, y: 400), band: band,
                                  panel: nil, isOpen: false))
    }

    func noPanelMeansNoSecondRegion() {
        expect(Layout.liveRegions(band: band, panel: nil, isOpen: true) == [band])
        expect(Layout.liveRegions(band: band, panel: .zero, isOpen: true) == [band])
    }
}
