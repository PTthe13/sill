import CoreGraphics
@testable import SillCore

struct ScreenSelectionTests {
    let builtin = ScreenInfo(uuid: "A", name: "Built-in Retina Display",
                             visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1069),
                             backingScaleFactor: 2, isMain: true)
    let external = ScreenInfo(uuid: "B", name: "DELL U2720Q",
                              visibleFrame: CGRect(x: 1710, y: 0, width: 2560, height: 1415),
                              backingScaleFactor: 1)

    func noScreensGivesNothing() {
        expect(ScreenSelection.resolve(preferredUUID: "A", screens: []) == nil)
    }

    func noPreferenceUsesTheMainDisplay() {
        expect(ScreenSelection.resolve(preferredUUID: nil, screens: [external, builtin]) == builtin)
    }

    func preferenceWins() {
        expect(ScreenSelection.resolve(preferredUUID: "B", screens: [builtin, external]) == external)
    }

    func missingPreferredDisplayFallsBackToMain() {
        let chosen = ScreenSelection.resolve(preferredUUID: "B", screens: [builtin])
        expect(chosen == builtin)
        expect(ScreenSelection.isFallback(preferredUUID: "B", screens: [builtin]))
    }

    func reconnectingThePreferredDisplayRestoresIt() {
        // Same stored preference, display back on the list.
        let chosen = ScreenSelection.resolve(preferredUUID: "B", screens: [builtin, external])
        expect(chosen == external)
        expect(!ScreenSelection.isFallback(preferredUUID: "B", screens: [builtin, external]))
    }

    func mainDisplayIsNotAFallbackWhenItIsTheChoice() {
        expect(!ScreenSelection.isFallback(preferredUUID: "A", screens: [builtin, external]))
        expect(!ScreenSelection.isFallback(preferredUUID: nil, screens: [builtin]))
    }

    func firstScreenUsedWhenNoneIsFlaggedMain() {
        let a = ScreenInfo(uuid: "X", name: "One", visibleFrame: .zero)
        let b = ScreenInfo(uuid: "Y", name: "Two", visibleFrame: .zero)
        expect(ScreenSelection.resolve(preferredUUID: nil, screens: [a, b]) == a)
    }

    func layoutFollowsTheChosenScreensVisibleFrame() {
        let chosen = ScreenSelection.resolve(preferredUUID: "B", screens: [builtin, external])!
        let frame = Layout.waveFrame(edge: .right, visibleFrame: chosen.visibleFrame)
        expect(approx(frame.maxX, external.visibleFrame.maxX - Layout.edgeInset))
        expect(approx(frame.midY, external.visibleFrame.midY))
    }

    func everyDisplayGetsABandWhenAskedFor() {
        let all = ScreenSelection.bandScreens(showsOnAllDisplays: true, preferredUUID: nil,
                                              screens: [external, builtin])
        expect(all.count == 2)
        // Main first: that is the one people are looking at.
        expect(all[0] == builtin)
    }

    func oneDisplayGetsTheBandOtherwise() {
        let one = ScreenSelection.bandScreens(showsOnAllDisplays: false, preferredUUID: "B",
                                              screens: [builtin, external])
        expect(one == [external])
        let fallback = ScreenSelection.bandScreens(showsOnAllDisplays: false, preferredUUID: "B",
                                                   screens: [builtin])
        expect(fallback == [builtin])
    }

    func noScreensMeansNoBands() {
        expect(ScreenSelection.bandScreens(showsOnAllDisplays: true, preferredUUID: nil,
                                           screens: []).isEmpty)
        expect(ScreenSelection.bandScreens(showsOnAllDisplays: false, preferredUUID: "A",
                                           screens: []).isEmpty)
    }

    func theChosenDisplayIsIgnoredWhenShowingOnAll() {
        let all = ScreenSelection.bandScreens(showsOnAllDisplays: true, preferredUUID: "B",
                                              screens: [builtin, external])
        expect(all.count == 2)
    }

    func differentBackingScalesAreCarriedThrough() {
        expect(builtin.backingScaleFactor == 2)
        expect(external.backingScaleFactor == 1)
    }
}
