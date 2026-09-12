import AppKit
import QuartzCore
import SillCore

/// One wave on one display: its window, its layers, and what the wallpaper
/// under it is doing. Every band shows the same readings — the sampler runs
/// once for all of them — but each is styled for its own desktop.
final class Band {
    let window = WaveWindow()
    let wave = WaveLayerController()
    private(set) var screen: ScreenInfo
    var backdrop: BackdropSample = .unknown

    var onClick: ((Band, NSPoint) -> Void)?

    /// The wave lives in its own view rather than directly on the window's
    /// layer: a subview always draws above a view's own sublayers, so the
    /// optional glass plate could only sit behind the wave if the wave is a
    /// view too.
    private let waveHost = WaveHostView()

    init(screen: ScreenInfo, menu: NSMenu) {
        self.screen = screen
        if let content = window.contentView as? WaveContentView {
            waveHost.frame = content.bounds
            waveHost.autoresizingMask = [.width, .height]
            content.addSubview(waveHost)
            waveHost.layer?.addSublayer(wave.container)
            content.contextMenu = menu
            content.liveRegions = { [weak self] in self?.liveRegions() ?? [] }
            content.onClick = { [weak self] point in
                guard let self else { return }
                self.onClick?(self, point)
            }
        }
    }

    /// Set by the controller: the band, plus the panel while it is open, in
    /// this window's coordinates.
    var liveRegions: () -> [CGRect] = { [] }

    var uuid: String { screen.uuid }

    /// A band behind a fullscreen window has nothing to show, and redrawing it
    /// every second is pure waste. The window server tells us.
    var isVisible: Bool { window.occlusionState.contains(.visible) }
    var contentView: WaveContentView? { window.contentView as? WaveContentView }

    func update(screen: ScreenInfo) { self.screen = screen }

    /// The band's rectangle in screen coordinates, whatever state it is in.
    var waveScreenFrame: CGRect {
        var frame = wave.container.frame
        frame.origin.x += window.frame.minX
        frame.origin.y += window.frame.minY
        return frame
    }

    /// The glass option, which is a real blur and therefore a real cost: it
    /// only exists while it is switched on.
    private var glassView: NSVisualEffectView?

    func setGlass(_ on: Bool, edge: ScreenEdge, bandFrame: CGRect, windowFrame: CGRect) {
        guard on else {
            glassView?.removeFromSuperview()
            glassView = nil
            return
        }
        let view = glassView ?? {
            let effect = NSVisualEffectView()
            effect.blendingMode = .behindWindow
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = BandBackground.cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            contentView?.addSubview(effect, positioned: .below, relativeTo: waveHost)
            glassView = effect
            return effect
        }()
        view.frame = bandFrame.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
    }

    func show() { window.orderFront(nil) }

    func close() {
        window.orderOut(nil)
        window.contentView = nil
    }
}
