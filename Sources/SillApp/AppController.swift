import AppKit
import IOKit.ps
import QuartzCore
import SillCore

/// Wires the window, the wave, the panel, the sampler and the system
/// notifications together.
final class AppController: NSObject, NSApplicationDelegate {
    private let settings = SillSettings()
    /// One band per display it is shown on. They share the sampler: the
    /// readings are the same everywhere, only the styling is per-desktop.
    private var bands: [Band] = []
    /// The band whose detail panel is open, if any.
    private var openBand: Band?
    /// Built on first open: the detail band pulls in SwiftUI's runtime, and a
    /// wave that is never clicked should never pay for it.
    private var loadedPanel: PanelController?
    private let processes = ProcessSampler()
    /// A second sampler for spike attribution, so its reads cannot disturb the
    /// baseline the panel's own list is measured against.
    private let spikeProcesses = ProcessSampler()
    private let power = PowerSource()
    private var preferences: PreferencesWindowController?
    private lazy var engine = SampleEngine(capacity: 128,
                                           preferredInterval: settings.sampleInterval)


    private var mouseMonitor: Any?
    private var signalSources: [DispatchSourceSignal] = []
    private var panelSize: CGSize = .zero
    /// Where the open panel sits on screen, chosen to land on exposed desktop.
    private var panelScreenFrame: CGRect = .zero
    /// How covered the best available spot has to be before the panel gives up
    /// on staying behind the windows.
    static let hiddenThreshold = 0.35
    private var panelExtent: CGFloat {
        Layout.panelExtent(edge: settings.edge, panelSize: panelSize)
    }
    private var frozenProcesses: [ProcessUsage] = []
    /// Set by `--hover`, so the hint can be inspected without a pointer.
    private var hoverOverride: Bool?
    private var lastPointer: NSPoint = .zero
    private var outsideClickMonitor: Any?
    private var appliedSettings: SettingsSnapshot?
    private var settingsChangePending = false

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard !anotherInstanceIsRunning() else {
            // Two copies would draw two bands on every display, and both would
            // sample. The one already on screen wins.
            NSApp.terminate(nil)
            return
        }

        engine.lockProbe = { Power.isScreenLocked() }
        engine.topProcessName = { [weak self] in
            self?.spikeProcesses.sample(limit: 1).first?.name
        }
        // The wallpaper can change without any notification Sill can see (a
        // rotating folder, a dynamic desktop shifting through the day), so the
        // backdrop is re-read on the slow timer too.
        engine.onSlowTick = { [weak self] in self?.refreshBackdrop() }
        engine.onSample = { [weak self] engine, time, interval in
            self?.didSample(engine: engine, time: time, interval: interval)
        }
        // A reading that did not join the history still belongs in the panel.
        engine.onReading = { [weak self] in
            guard let self, self.isOpen else { return }
            self.updatePanelData(engine: self.engine)
        }

        power.onChange = { [weak self] in self?.powerSourceChanged() }
        power.start()
        appliedSettings = settings.snapshot
        engine.waveMetrics = [settings.envelopeMetric, settings.fillMetric]
        rebuildBands()
        observe()
        engine.start()
        buildMenu()
        introduceIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
        power.stop()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        stopOutsideClickMonitor()
    }

    /// True when another copy of Sill is already running.
    private func anotherInstanceIsRunning() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains { $0.processIdentifier != mine }
    }

    private var reduceTransparency: Bool {
        Debug.flag("SILL_FORCE_REDUCE_TRANSPARENCY")
            || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var reduceMotion: Bool {
        Debug.flag("SILL_FORCE_REDUCE_MOTION")
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Settings and Quit, reachable by right-clicking the wave — there is no
    /// Dock icon and no menu bar item by design.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openPreferences),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sill",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    /// The same items again as a real menu bar, for when Settings is frontmost.
    private func buildMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        item.submenu = makeMenu()
        main.addItem(item)
        NSApp.mainMenu = main
    }

    @objc private func openPreferences() {
        if preferences == nil {
            let controller = PreferencesWindowController(settings: settings)
            controller.onClose = { [weak self] in self?.preferences = nil }
            preferences = controller
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        preferences?.showWindow(nil)
        // An accessory app that has just become regular does not reliably come
        // forward on activation alone, so the window is ordered front itself.
        preferences?.window?.makeKeyAndOrderFront(nil)
        preferences?.window?.orderFrontRegardless()
        preferences?.window?.center()
    }

    /// On a first launch the band is a thin quiet line, and nothing says it can
    /// be clicked. Once — and only once — the hint fades in by itself and then
    /// goes away, the way a good door shows you its handle.
    private func introduceIfNeeded() {
        guard !settings.hasIntroduced else { return }
        settings.hasIntroduced = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.hoverOverride = true
            for band in self.bands {
                band.wave.setHovered(true, open: false, alongFraction: 1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                self.hoverOverride = nil
                self.updateHitTesting(force: true)
            }
        }
    }

    private var panel: PanelController {
        if let loadedPanel { return loadedPanel }
        let controller = PanelController()
        controller.model.ramp = settings.ramp
        controller.applyMaterial(settings.material, reduceTransparency: reduceTransparency)
        loadedPanel = controller
        return controller
    }

    // MARK: - Sampling

    private func didSample(engine: SampleEngine, time: CFTimeInterval, interval: TimeInterval) {
        Debug.log("tick cpu=\(String(format: "%.1f", engine.latest.cpuPercent)) interval=\(interval)")
        // One computation for every band: the readings are the same on each.
        let visible = bands.filter(\.isVisible)
        if !visible.isEmpty {
            let series = engine.series(envelope: settings.envelopeMetric,
                                       fill: settings.fillMetric)
            let measured = engine.measured(envelope: settings.envelopeMetric,
                                           fill: settings.fillMetric)
            let frame = WaveModel.Frame(cpu: series.envelope, memory: series.fill,
                                        available: measured)
            if Debug.isEnabled {
                // Old readings must never change. Log the tail of the history
                // (everything but the newest few) so a retroactive edit shows
                // up as a changed digest between ticks.
                let settled = series.envelope.dropLast(3)
                let digest = settled.reduce(into: 0.0) { $0 = $0 * 1.000001 + $1 }
                Debug.log(String(format: "history digest %.6f count %d measured %d newest %.2f",
                                 digest, series.envelope.count, measured,
                                 series.envelope.last ?? -1))
            }
            for band in visible {
                band.wave.update(frame: frame, interval: interval, tickTime: time)
            }
        }
        // Safety net: a missed mouse-moved event would otherwise leave the band
        // deaf to clicks until the pointer moves again.
        updateHitTesting(force: true)
        // Refreshing the panel means reading the whole process table, about
        // 2.5ms, and the GPU statistics, another 2ms. Worth it while someone is
        // looking at the panel; pure waste while it sits open under somebody's
        // browser window. This takes effect on the next tick, which is what
        // `wantsDetail` is read on.
        let watched = isOpen && (openBand?.isVisible ?? false)
        engine.wantsDetail = watched
        guard watched else { return }
        updatePanelData(engine: engine)
    }

    private func updatePanelData(engine: SampleEngine) {
        let model = panel.model
        model.cpuPercent = engine.latest.cpuPercent
        model.memoryPercent = engine.latest.memoryPercent
        model.memoryUsedBytes = engine.latest.memoryUsedBytes
        model.diskFreeBytes = engine.diskFreeBytes
        model.network = engine.network
        model.diskIO = engine.diskIO
        model.batteryPercent = power.percent
        model.isCharging = power.isCharging
        model.batteryMinutesRemaining = power.minutesRemaining
        model.gpuPercent = engine.gpuPercent
        model.envelopeMetric = settings.envelopeMetric
        model.fillMetric = settings.fillMetric
        let series = engine.series(envelope: settings.envelopeMetric, fill: settings.fillMetric)
        model.envelopeValue = series.envelope.last ?? 0
        model.fillValue = series.fill.last ?? 0
        model.fullScaleNote = engine.fullScaleText(for: settings.envelopeMetric)
            ?? engine.fullScaleText(for: settings.fillMetric)
        // The band the panel belongs to, not the longest one on the desk.
        let shown = openBand?.wave.sampleCount ?? engine.cpu.values.count
        // Never claim more history than was measured: a band two minutes into
        // its life covers two minutes, however long the strip is.
        let measured = engine.measured(envelope: settings.envelopeMetric,
                                       fill: settings.fillMetric)
        model.historySpan = Scrub.spanText(sampleCount: min(shown, measured),
                                           interval: engine.effectiveInterval
                                               ?? settings.sampleInterval)

        let fresh = Debug.time("process sample") {
            processes.sample(limit: PanelModel.processRowCount)
        }
        if frozenProcesses.isEmpty {
            frozenProcesses = fresh
            model.processes = fresh
        } else {
            // Rows stay put while the panel is open; they re-sort on close.
            model.processes = ProcessSampler.merge(frozen: frozenProcesses, fresh: fresh)
        }
    }

    // MARK: - Bands

    /// Creates, moves and retires the bands so that exactly the wanted
    /// displays have one. Called on launch, on any screen change, and whenever
    /// a setting that affects placement changes.
    private func rebuildBands() {
        let screens = Screens.all()
        let wanted = ScreenSelection.bandScreens(showsOnAllDisplays: settings.showsOnAllDisplays,
                                                 preferredUUID: settings.displayUUID,
                                                 screens: screens)
        // Retire bands whose display has gone (or is no longer wanted).
        for band in bands where !wanted.contains(where: { $0.uuid == band.uuid }) {
            if openBand === band { closePanelImmediately() }
            band.close()
        }
        bands.removeAll { band in !wanted.contains { $0.uuid == band.uuid } }

        let menu = makeMenu()
        for screen in wanted where !bands.contains(where: { $0.uuid == screen.uuid }) {
            let band = Band(screen: screen, menu: menu)
            band.onClick = { [weak self] band, point in self?.handleClick(on: band, at: point) }
            band.liveRegions = { [weak self, weak band] in
                guard let self, let band else { return [] }
                return self.liveRegions(of: band)
            }
            band.wave.culpritLookup = { [weak self] age in
                self?.engine.spikes.culprit(secondsAgo: age)?.name
            }
            bands.append(band)
        }
        for band in bands {
            if let screen = wanted.first(where: { $0.uuid == band.uuid }) {
                band.update(screen: screen)
            }
        }

        layoutBands()
        bands.forEach { $0.show() }
        observeOcclusion()
        updateDim()
        Debug.log("bands: \(bands.map(\.screen.name).joined(separator: ", "))")
    }

    private func layoutBands() {
        bands.forEach { place($0) }
        let capacity = bands.map(\.wave.sampleCount).max() ?? 128
        engine.resize(capacity: capacity)
        // A chosen span decides how often to sample: the band holds the time
        // the user asked for, whatever its length happens to be.
        engine.preferredInterval = Span.interval(minutes: settings.spanMinutes,
                                                 samples: capacity,
                                                 fallback: settings.sampleInterval)
        redraw()
    }

    /// Where a band sits on its screen. Every caller goes through here: a
    /// `Layout.waveFrame` call that forgets `screenFrame` centres on the
    /// visible area instead of the display, and the band jumps by half a menu
    /// bar the moment some other code path lays it out.
    private func bandFrame(on band: Band) -> CGRect {
        Layout.waveFrame(edge: settings.edge, visibleFrame: band.screen.visibleFrame,
                         fraction: settings.lengthFraction, screenFrame: band.screen.frame)
    }

    /// Positions one band's window and restyles its wave for the desktop it
    /// sits on.
    private func place(_ band: Band) {
        let edge = settings.edge
        let visible = band.screen.visibleFrame
        let length = Layout.bandLength(edge: edge, visibleFrame: visible,
                                       fraction: settings.lengthFraction)
        let isOpenHere = openBand === band

        if let loadedPanel {
            loadedPanel.model.isHorizontal = !edge.isVertical
            loadedPanel.model.ramp = settings.ramp
            loadedPanel.applyMaterial(settings.material, reduceTransparency: reduceTransparency)
        }
        if isOpenHere {
            panelSize = panel.measure(edge: edge, bandLength: length)
        }
        let bandFrame = bandFrame(on: band)
        let frame = isOpenHere && !panelScreenFrame.isEmpty
            ? bandFrame.union(panelScreenFrame).insetBy(dx: -2, dy: -2)
            : Layout.windowFrame(edge: edge, visibleFrame: visible, panelExtent: 0,
                                 fraction: settings.lengthFraction,
                                 screenFrame: band.screen.frame)
        band.window.setFrame(frame, display: true)
        band.placeCatcher(over: bandFrame, isOpen: isOpenHere)
        Debug.log("place[\(openBand === band ? "open" : "closed")] \(band.screen.name) window=\(frame.debugDescription) "
                  + "wave=\(waveFrame(open: isOpenHere, in: frame, on: band, edge: edge).debugDescription)")

        band.backdrop = backdropSample(for: band.screen, edge: edge, visible: visible)
            .behind(settings.background)
        band.wave.reduceMotion = reduceMotion
        band.wave.background = settings.background
        band.wave.showsAreaFill = settings.areaFill
        band.setGlass(settings.background == .glass, edge: edge, bandFrame: bandFrame,
                      windowFrame: frame)
        // Size first, then position: configure sets the band's own geometry.
        band.wave.configure(edge: edge, length: length, ramp: settings.ramp,
                            scale: band.screen.backingScaleFactor,
                            backdropLuminance: band.backdrop.luminance,
                            backdropVariation: band.backdrop.variation,
                            backdropProfile: band.backdrop.profile,
                            envelopeMetric: settings.envelopeMetric,
                            fillMetric: settings.fillMetric)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.wave.container.frame = bandFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        CATransaction.commit()

        if isOpenHere, let content = band.contentView {
            panel.attach(to: content)
            panel.place(at: panelScreenFrame.offsetBy(dx: -frame.minX, dy: -frame.minY),
                        progress: 1)
        }
    }

    /// Wave position inside a band's window, for either state.
    private func waveFrame(open: Bool, in windowFrame: CGRect, on band: Band,
                           edge: ScreenEdge) -> CGRect {
        let extent = open ? panelExtent : 0
        let stateWindow = Layout.windowFrame(edge: edge, visibleFrame: band.screen.visibleFrame,
                                             panelExtent: extent,
                                             fraction: settings.lengthFraction,
                                             screenFrame: band.screen.frame)
        var frame = Layout.waveFrameInWindow(edge: edge, windowSize: stateWindow.size,
                                             atOuterSide: !open)
        frame.origin.x += stateWindow.minX - windowFrame.minX
        frame.origin.y += stateWindow.minY - windowFrame.minY
        return frame
    }

    /// How light the wallpaper is where a band sits, so its strands can be
    /// toned to read against it.
    private func backdropSample(for screen: ScreenInfo, edge: ScreenEdge,
                                visible: CGRect) -> BackdropSample {
        guard let nsScreen = Screens.screen(withUUID: screen.uuid) ?? NSScreen.main else {
            return .unknown
        }
        let band = Layout.waveFrame(edge: edge, visibleFrame: visible,
                                    fraction: settings.lengthFraction,
                                    screenFrame: screen.frame)
        return Backdrop.measure(screen: nsScreen, rect: band, edge: edge)
    }

    private func redraw() {
        let visible = bands.filter(\.isVisible)
        guard !visible.isEmpty else { return }
        let series = engine.series(envelope: settings.envelopeMetric, fill: settings.fillMetric)
        let frame = WaveModel.Frame(cpu: series.envelope, memory: series.fill,
                                    available: engine.measured(envelope: settings.envelopeMetric,
                                                               fill: settings.fillMetric))
        for band in visible {
            band.wave.update(frame: frame, interval: 0, tickTime: CACurrentMediaTime())
        }
    }


    // MARK: - Open and close

    private var isOpen: Bool { openBand != nil }

    private func handleClick(on band: Band, at point: NSPoint) {
        Debug.log("click on \(band.screen.name) at \(point.debugDescription)")
        // A click inside the open panel is for the panel, not a close gesture.
        if openBand === band, let loadedPanel, loadedPanel.view.frame.contains(point) { return }
        setOpen(openBand !== band, on: band)
    }

    /// Opens the detail band on one display and closes it anywhere else: the
    /// numbers are the same on every screen, so two open panels would only be
    /// two copies of one answer.
    private func setOpen(_ open: Bool, on band: Band) {
        if open, let current = openBand, current !== band {
            setOpen(false, on: current)
        }
        guard open != (openBand === band) else { return }
        let edge = settings.edge
        let visible = band.screen.visibleFrame
        let length = Layout.bandLength(edge: edge, visibleFrame: visible,
                                       fraction: settings.lengthFraction)

        if open {
            frozenProcesses = []
            processes.reset()
            engine.wantsDetail = true
            openBand = band
            if let content = band.contentView { panel.attach(to: content) }
            panel.model.isHorizontal = !edge.isVertical
            panelSize = Debug.time("panel measure") { panel.measure(edge: edge, bandLength: length) }
            Debug.log("panel size \(panelSize.debugDescription) band \(Int(length))pt")
            Debug.time("panel data") { updatePanelData(engine: engine) }

            // Open into whatever part of the desktop is actually showing, so
            // the panel can stay on the wallpaper without hiding behind a
            // window that happens to sit beside the band.
            let bandFrame = bandFrame(on: band)
            let occupied = settings.liftsWhenOpen ? []
                : ExposedDesktop.occupiedFrames(on: visible)
            panelScreenFrame = PanelPlacement.choose(edge: edge, band: bandFrame,
                                                     panelSize: panelSize,
                                                     visibleFrame: visible, windows: occupied)
            // Staying behind is the rule; being invisible is not. If the best
            // spot on the desktop is still mostly covered — a screen full of
            // windows — the panel comes forward for as long as it is open.
            if settings.liftsWhenOpen
                || PanelPlacement.isHidden(panelScreenFrame, by: occupied,
                                           threshold: AppController.hiddenThreshold) {
                band.window.setElevated(true)
                startOutsideClickMonitor()
            }
            let openFrame = bandFrame.union(panelScreenFrame).insetBy(dx: -2, dy: -2)
            band.window.setFrame(openFrame, display: true)
            Debug.log("panel at \(panelScreenFrame.debugDescription) "
                      + "coverage \(String(format: "%.2f", PanelPlacement.coverage(of: panelScreenFrame, by: occupied)))")

            let waveInWindow = bandFrame.offsetBy(dx: -openFrame.minX, dy: -openFrame.minY)
            let panelTo = panelScreenFrame.offsetBy(dx: -openFrame.minX, dy: -openFrame.minY)
            band.wave.setHovered(true, open: true, alongFraction: nil)
            animate(band: band, waveFrom: waveInWindow, waveTo: waveInWindow,
                    panelFrom: offset(panelTo, by: Layout.panelEntryOffset(edge: edge)),
                    panelTo: panelTo, opening: true) { [weak self] in
                guard let self, let view = self.loadedPanel?.view else { return }
                Debug.log("panel view frame=\(view.frame.debugDescription) "
                          + "alpha=\(view.alphaValue) hidden=\(view.isHidden) "
                          + "window=\(band.window.frame.debugDescription) "
                          + "level=\(band.window.level.rawValue) "
                          + "super=\(view.superview != nil)")
            }
            // A second, delayed read gives the process list real deltas to show.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.openBand === band else { return }
                self.frozenProcesses = []
                self.updatePanelData(engine: self.engine)
            }
        } else {
            openBand = nil
            frozenProcesses = []
            engine.wantsDetail = false
            stopOutsideClickMonitor()
            band.wave.setHovered(true, open: false, alongFraction: nil)
            let windowFrame = band.window.frame
            let waveTo = band.wave.container.frame
            let panelFrom = panelScreenFrame.offsetBy(dx: -windowFrame.minX,
                                                      dy: -windowFrame.minY)
            animate(band: band, waveFrom: waveTo, waveTo: waveTo,
                    panelFrom: panelFrom,
                    panelTo: offset(panelFrom, by: Layout.panelEntryOffset(edge: edge)),
                    opening: false) { [weak self] in
                guard let self else { return }
                self.panelSize = .zero
                self.panelScreenFrame = .zero
                band.window.setElevated(false)
                self.place(band)
            }
        }
        updateHitTesting(force: true)
    }

    /// A click anywhere else puts the band away, the way any floating panel
    /// behaves. A global monitor only sees events meant for other apps, so a
    /// click inside the panel itself never reaches it.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, let band = self.openBand else { return }
                let point = NSEvent.mouseLocation
                guard !band.window.frame.contains(point) else { return }
                self.setOpen(false, on: band)
            }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    /// Closes the panel with no animation — for a display being pulled out
    /// from under it, where there is nothing left to animate on.
    private func closePanelImmediately() {
        openBand?.window.setElevated(false)
        stopOutsideClickMonitor()
        openBand = nil
        panelSize = .zero
        frozenProcesses = []
        engine.wantsDetail = false
        loadedPanel?.layout(edge: settings.edge, windowSize: .zero, panelSize: .zero, progress: 0)
    }

    private func offset(_ rect: CGRect, by size: CGSize) -> CGRect {
        rect.offsetBy(dx: size.width, dy: size.height)
    }

    /// Animates the wave's slide and the panel's fade together, in both
    /// directions, with explicit from/to values.
    ///
    /// `animator()` plus an `isHidden` flip in the same pass silently skips the
    /// opening animation — the layer has no presentation state to animate from,
    /// so it snaps — which is why open used to appear instant while close
    /// animated. Both directions now run the same explicit animations.
    private func animate(band: Band, waveFrom: CGRect, waveTo: CGRect,
                         panelFrom: CGRect, panelTo: CGRect,
                         opening: Bool, completion: @escaping () -> Void) {
        let duration = Layout.openDuration
        let timing = CAMediaTimingFunction(name: .easeOut)
        let panelView = panel.view

        panelView.isHidden = false
        panelView.wantsLayer = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panelView.frame = panelFrom
        panelView.alphaValue = opening ? 0 : 1
        panelView.layer?.opacity = opening ? 0 : 1
        band.wave.container.frame = waveFrom
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            if !opening { panelView.isHidden = true }
            completion()
        }
        CATransaction.setDisableActions(true)

        if let panelLayer = panelView.layer {
            let from = panelLayer.position
            panelView.frame = panelTo
            let slide = CABasicAnimation(keyPath: "position")
            slide.fromValue = NSValue(point: from)
            slide.toValue = NSValue(point: panelLayer.position)
            slide.duration = duration
            slide.timingFunction = timing
            panelLayer.add(slide, forKey: "slide")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = opening ? 0 : 1
            fade.toValue = opening ? 1 : 0
            fade.duration = duration
            fade.timingFunction = timing
            panelLayer.opacity = opening ? 1 : 0
            panelLayer.add(fade, forKey: "fade")
            panelView.alphaValue = 1
        }

        let waveLayer = band.wave.container
        let fromPosition = waveLayer.position
        waveLayer.frame = waveTo
        let slide = CABasicAnimation(keyPath: "position")
        slide.fromValue = NSValue(point: fromPosition)
        slide.toValue = NSValue(point: waveLayer.position)
        slide.duration = duration
        slide.timingFunction = timing
        waveLayer.add(slide, forKey: "slide")

        CATransaction.commit()
    }

    // MARK: - System notifications

    private func observe() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged),
                           name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: SillSettings.didChange, object: nil)
        // Defaults edited from outside the app (including by `defaults write`)
        // land here too.
        center.addObserver(self, selector: #selector(settingsChanged),
                           name: UserDefaults.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(powerChanged),
                           name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(activeAppChanged),
                              name: NSWorkspace.didActivateApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displayPower(_:)),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displayPower(_:)),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        // Wallpapers are per Space, so the backdrop has to be re-read on a
        // Space switch as well as when the picture itself changes.
        workspace.addObserver(self, selector: #selector(backdropChanged),
                              name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(accessibilityChanged),
                              name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                              object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenLock(_:)),
                                name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenLock(_:)),
                                name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(debugToggle),
            name: NSNotification.Name("app.sill.debug.toggle"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(settingsChanged),
            name: NSNotification.Name("app.sill.debug.reload"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(openPreferences),
            name: NSNotification.Name("app.sill.debug.settings"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(debugSetOpen(_:)),
            name: NSNotification.Name("app.sill.debug.setOpen"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(debugHover(_:)),
            name: NSNotification.Name("app.sill.debug.hover"), object: nil)

        // Distributed notifications reach a background app late — sometimes
        // seconds late — which is no good for timing an animation. Signals
        // arrive immediately, so the debug hooks use them.
        installSignalHooks()
        updatePowerState()
        startMouseTracking()
    }

    @objc private func screensChanged() {
        Backdrop.invalidate()
        rebuildBands()
    }

    @objc private func backdropChanged() {
        Backdrop.invalidate()
        rebuildBands()
    }

    /// Opens and closes the band without a pointer, so the animation and the
    /// panel layout can be exercised from a script.
    /// Forces the hover hint on or off, so it can be looked at without a mouse.
    @objc private func debugHover(_ note: Notification) {
        let on = note.object as? String != "off"
        Debug.log("hover \(on ? "on" : "off")")
        hoverOverride = on ? true : nil
        for band in bands {
            band.wave.setHovered(on, open: openBand === band, alongFraction: 0.5)
        }
    }

    private func installSignalHooks() {
        for (signalNumber, action) in [(SIGUSR1, { [weak self] in
            guard let self, let band = self.openBand ?? self.bands.first else { return }
            self.setOpen(self.openBand !== band, on: band)
            Debug.log("signal: open=\(self.isOpen)")
        }), (SIGUSR2, { [weak self] in
            guard let self else { return }
            self.hoverOverride = self.hoverOverride == true ? nil : true
            for band in self.bands {
                band.wave.setHovered(self.hoverOverride ?? false,
                                     open: self.openBand === band, alongFraction: 0.5)
            }
            Debug.log("signal: hover=\(self.hoverOverride == true)")
        }), (SIGWINCH, { [weak self] in
            self?.openPreferences()
            Debug.log("signal: settings")
        })] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler(handler: action)
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func debugSetOpen(_ note: Notification) {
        guard let band = openBand ?? bands.first else { return }
        setOpen(note.object as? String == "open", on: band)
        Debug.log("setOpen -> \(isOpen)")
    }

    @objc private func debugToggle() {
        guard let band = openBand ?? bands.first else { return }
        setOpen(openBand !== band, on: band)
        Debug.log("open=\(isOpen) window=\(band.window.frame.debugDescription) "
                  + "panel=\(panel.view.frame.debugDescription)")
    }

    /// Settings changed — maybe.
    ///
    /// This also fires on `UserDefaults.didChangeNotification`, which any part
    /// of the process can trigger (SwiftUI registers defaults while laying
    /// out). Acting on it synchronously re-entered the layout that raised it;
    /// so the work is coalesced to the next pass and skipped entirely unless a
    /// value Sill actually uses has moved.
    @objc private func settingsChanged() {
        guard !settingsChangePending else { return }
        settingsChangePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsChangePending = false
            let snapshot = self.settings.snapshot
            guard snapshot != self.appliedSettings else { return }
            self.appliedSettings = snapshot
            self.engine.waveMetrics = [snapshot.envelopeMetric, snapshot.fillMetric]
            self.loadedPanel?.model.ramp = snapshot.ramp
            self.loadedPanel?.applyMaterial(snapshot.material,
                                            reduceTransparency: self.reduceTransparency)
            self.rebuildBands()
        }
    }

    /// Re-reads each band's wallpaper and restyles it, without moving anything.
    private func refreshBackdrop() {
        let edge = settings.edge
        for band in bands {
            let visible = band.screen.visibleFrame
            let sample = backdropSample(for: band.screen, edge: edge, visible: visible)
            guard sample != band.backdrop else { continue }
            band.backdrop = sample
            let length = Layout.bandLength(edge: edge, visibleFrame: visible,
                                           fraction: settings.lengthFraction)
            band.wave.configure(edge: edge, length: length, ramp: settings.ramp,
                                scale: band.screen.backingScaleFactor,
                                backdropLuminance: sample.luminance,
                                backdropVariation: sample.variation,
                                backdropProfile: sample.profile,
                                envelopeMetric: settings.envelopeMetric,
                                fillMetric: settings.fillMetric)
        }
        redraw()
    }

    @objc private func accessibilityChanged() {
        loadedPanel?.applyMaterial(settings.material, reduceTransparency: reduceTransparency)
        bands.forEach { $0.wave.reduceMotion = reduceMotion }
        redraw()
    }

    /// Watches every band's window: sampling only stops when no band is
    /// visible anywhere.
    private func observeOcclusion() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification,
                              object: nil)
        for band in bands {
            center.addObserver(self, selector: #selector(occlusionChanged),
                               name: NSWindow.didChangeOcclusionStateNotification,
                               object: band.window)
        }
        occlusionChanged()
    }

    @objc private func occlusionChanged() {
        var state = engine.powerState
        state.occluded = !bands.isEmpty && bands.allSatisfy { !$0.isVisible }
        engine.powerState = state
        // A band that has just come back into view is showing a stale wave.
        redraw()
        Debug.log("occluded=\(state.occluded) interval=\(String(describing: engine.effectiveInterval))")
    }

    @objc private func displayPower(_ note: Notification) {
        var state = engine.powerState
        state.displayAsleep = note.name == NSWorkspace.screensDidSleepNotification
        engine.powerState = state
    }

    @objc private func screenLock(_ note: Notification) {
        var state = engine.powerState
        state.screenLocked = note.name.rawValue == "com.apple.screenIsLocked"
        engine.powerState = state
        Debug.log("screen locked=\(state.screenLocked)")
    }

    @objc private func powerChanged() { updatePowerState() }

    private func powerSourceChanged() {
        updatePowerState()
        panel.model.batteryPercent = power.percent
        panel.model.isCharging = power.isCharging
    }

    private func updatePowerState() {
        var state = engine.powerState
        state.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        state.onBattery = power.isOnBattery
        engine.powerState = state
    }

    @objc private func activeAppChanged() { updateDim() }

    private func updateDim() {
        // An open band is being read: it does not dim behind the app in front.
        guard openBand == nil else {
            bands.forEach { $0.wave.setDimmed(false) }
            return
        }
        guard settings.dimWhenFocused else {
            bands.forEach { $0.wave.setDimmed(false) }
            return
        }
        let front = NSWorkspace.shared.frontmostApplication
        let desktopExposed = front == nil
            || front?.bundleIdentifier == "com.apple.finder"
            || front?.bundleIdentifier == Bundle.main.bundleIdentifier
        bands.forEach { $0.wave.setDimmed(!desktopExposed) }
    }

    // MARK: - Click-through

    /// The window ignores the mouse unless the pointer is over the band (or the
    /// open panel), so the strip stays usable screen space.
    private func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateHitTesting()
        }
        updateHitTesting()
    }

    private func updateHitTesting(force: Bool = false) {
        let point = NSEvent.mouseLocation
        // Mouse-moved events arrive at screen refresh rate; a pointer that has
        // shifted less than a couple of points cannot have changed the answer.
        if !force, abs(point.x - lastPointer.x) < 2, abs(point.y - lastPointer.y) < 2 {
            return
        }
        lastPointer = point

        for band in bands {
            let isOpenHere = openBand === band
            // Only the band and, while open, the panel: the window may span a
            // lot of desktop between them and none of that is ours to take.
            let inside = Layout.takesMouse(at: point, band: band.waveScreenFrame,
                                           panel: panelScreenFrame.isEmpty ? nil
                                               : panelScreenFrame,
                                           isOpen: isOpenHere)
            if band.window.ignoresMouseEvents == inside {
                band.window.ignoresMouseEvents = !inside
            }
            // Hovering the band shows the hint, and where along it the pointer
            // sits picks the sample the readout reads back.
            band.wave.setHovered(hoverOverride ?? inside, open: isOpenHere,
                                 alongFraction: fraction(on: band, at: point))
        }
    }

    /// The parts of a band's window that take the mouse: the band itself, and
    /// the panel while it is open. Everything else is a hole.
    private func liveRegions(of band: Band) -> [CGRect] {
        let window = band.window.frame
        return Layout.liveRegions(
            band: band.wave.container.frame,
            panel: panelScreenFrame.isEmpty ? nil
                : panelScreenFrame.offsetBy(dx: -window.minX, dy: -window.minY),
            isOpen: openBand === band)
    }

    /// Where the pointer sits along a band: 0 at the oldest end, 1 at the
    /// newest — the bottom on a vertical edge, the left on a horizontal one.
    private func fraction(on band: Band, at point: NSPoint) -> CGFloat {
        let frame = band.waveScreenFrame
        guard frame.width > 0, frame.height > 0 else { return 1 }
        let raw = settings.edge.isVertical
            ? (point.y - frame.minY) / frame.height
            : (point.x - frame.minX) / frame.width
        return min(1, max(0, 1 - raw))
    }
}
