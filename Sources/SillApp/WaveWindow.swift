import AppKit
import SillCore

/// The desktop-level window that holds the wave and, when open, the panel.
///
/// A non-activating panel: it takes clicks without bringing Sill to the front,
/// so clicking the wave never pulls focus off whatever you were working in.
/// The catcher's content: an ordinary view whose only job is to be hit.
private final class ClickCatcherView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        (window as? ClickCatcher)?.onClick?(NSEvent.mouseLocation)
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = (window as? ClickCatcher)?.contextMenu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

/// An invisible pane that sits ABOVE the desktop icons, exactly over the band.
///
/// The wave window is under the icons so it can never cover a file, but that
/// also puts it under the Finder's desktop, which is the full size of the
/// screen — so a click on the band went to the desktop instead of to us. On
/// macOS that does not just miss: "click wallpaper to reveal desktop" sweeps
/// every window aside. This catches the click first and does nothing else; it
/// is one band wide, so the only thing it takes from the desktop is the strip
/// the band is drawn on.
final class ClickCatcher: NSPanel {
    var onClick: ((NSPoint) -> Void)?
    var contextMenu: NSMenu?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 52, height: 432),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = ClickCatcherView()
    }

}

final class WaveWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// On the wallpaper and UNDER the desktop icons: the band is scenery, so
    /// anything you actually put on the desktop wins the overlap.
    static let restingLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)

    /// Opening the detail band is a deliberate act, and a panel that opens
    /// behind the windows you already have open has not opened at all. While
    /// it is open the window floats above them; closing puts it back on the
    /// wallpaper.
    func setElevated(_ elevated: Bool) {
        let wanted = elevated ? NSWindow.Level.floating : Self.restingLevel
        guard level != wanted else { return }
        level = wanted
        if elevated { orderFront(nil) }
        Debug.log("window level -> \(level.rawValue) frame \(frame.debugDescription)")
    }

    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 52, height: 432),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        level = Self.restingLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = WaveContentView()
    }
}

/// Holds the wave's layers, above anything placed behind the band.
final class WaveHostView: NSView {
    override var isFlipped: Bool { false }
    /// Never takes the mouse: clicks belong to the content view beneath it,
    /// which decides whether they are for Sill at all.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

/// Layer-backed host for the wave and the detail panel.
final class WaveContentView: NSView {
    override var isFlipped: Bool { false }

    var onClick: ((NSPoint) -> Void)?
    var contextMenu: NSMenu?
    /// Which parts of this window are actually Sill's. Everything else is a
    /// hole: while the band is open its window spans the gap between the band
    /// and the panel, and a click in that gap belongs to whatever is beneath.
    var liveRegions: (() -> [CGRect])?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let regions = liveRegions?(), regions.contains(where: { $0.contains(point) })
        else { return nil }
        return super.hitTest(point)
    }

    /// Without this, the first click into a background app only activates it
    /// and never reaches the view — the wave would feel like it ignored you.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let contextMenu else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}
