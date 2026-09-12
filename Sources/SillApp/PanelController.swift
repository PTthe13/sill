import AppKit
import SillCore
import SwiftUI

/// Hosts the detail band and animates it in and out.
final class PanelController {
    let model = PanelModel()
    private(set) var isOpen = false

    private let effectView = NSVisualEffectView()
    private let hosting: NSHostingView<PanelView>

    init() {
        hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Blur only behind the panel; nothing ever sits behind the wave.
        effectView.blendingMode = .behindWindow
        effectView.material = .hudWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 20
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        effectView.isHidden = true
        effectView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effectView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
    }

    var view: NSView { effectView }

    func attach(to parent: NSView) {
        guard effectView.superview !== parent else { return }
        parent.addSubview(effectView)
    }

    func applyMaterial(_ material: PanelMaterial, reduceTransparency: Bool) {
        model.material = material
        model.reduceTransparency = reduceTransparency
        effectView.material = material == .clear ? .hudWindow : .underWindowBackground
        // With Reduce Transparency on the blur is pointless: the panel draws a
        // solid fill in SwiftUI, so the text keeps its contrast whatever is behind.
        effectView.state = reduceTransparency ? .inactive : .active
        effectView.appearance = NSAppearance(named: .darkAqua)
    }

    /// What the panel asks for: a fixed-width card on left and right, a
    /// full-width bar on top and bottom. Height is always measured, never
    /// assumed, so a long process list can't clip the footer.
    func measure(edge: ScreenEdge, bandLength: CGFloat) -> CGSize {
        model.isHorizontal = !edge.isVertical
        // A band across a 3,800pt display would make a 3,800pt panel: unwieldy
        // to read and impossible to fit into exposed desktop. Cap it.
        let width = edge.isVertical ? Layout.panelWidth
            : min(bandLength, Layout.maximumBarWidth)
        hosting.setFrameSize(CGSize(width: width, height: 1))
        hosting.layoutSubtreeIfNeeded()
        return CGSize(width: width, height: ceil(hosting.fittingSize.height))
    }

    /// Places the panel at an explicit frame in its window — used when the
    /// panel opens into whatever part of the desktop is exposed rather than
    /// straight inboard of the band.
    func place(at frame: CGRect, progress: CGFloat) {
        effectView.frame = frame
        effectView.alphaValue = progress
        effectView.isHidden = progress <= 0.001
    }

    /// Places the panel, with `progress` 0 (closed) to 1 (fully open).
    func layout(edge: ScreenEdge, windowSize: CGSize, panelSize: CGSize, progress: CGFloat) {
        var frame = Layout.panelFrameInWindow(edge: edge, windowSize: windowSize,
                                              panelSize: panelSize)
        let offset = Layout.panelEntryOffset(edge: edge)
        frame.origin.x += offset.width * (1 - progress)
        frame.origin.y += offset.height * (1 - progress)
        effectView.frame = frame
        effectView.alphaValue = progress
        effectView.isHidden = progress <= 0.001
    }

    func setOpen(_ open: Bool) { isOpen = open }
}
