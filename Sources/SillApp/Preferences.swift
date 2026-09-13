import AppKit
import ServiceManagement
import SillCore
import SwiftUI

/// The settings window. Deliberately small: the seven things the brief lists.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    /// Called when the window closes, so the controller — and the 40MB of
    /// SwiftUI behind it — can be let go rather than kept for a visit that may
    /// never come again.
    var onClose: (() -> Void)?

    init(settings: SillSettings) {
        let view = PreferencesView(settings: settings)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sill"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        // Size the window to its content: a settings sheet this small should
        // never scroll.
        hosting.view.layoutSubtreeIfNeeded()
        window.setContentSize(hosting.view.fittingSize)
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Back to no Dock icon once the settings window goes away, and back to
    /// the footprint of a band: SwiftUI and its hosting view cost about 40MB
    /// here, which is three times what the rest of the app uses.
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let release = onClose
        DispatchQueue.main.async { release?() }
    }
}

/// Mirrors SillSettings into SwiftUI. SillSettings itself stays the source of truth.
final class PreferencesModel: ObservableObject {
    private let settings: SillSettings

    @Published var edge: ScreenEdge { didSet { settings.edge = edge } }
    @Published var ramp: ColorRamp { didSet { settings.ramp = ramp } }
    @Published var material: PanelMaterial { didSet { settings.material = material } }
    @Published var dimWhenFocused: Bool { didSet { settings.dimWhenFocused = dimWhenFocused } }
    @Published var spanMinutes: Double { didSet { settings.spanMinutes = spanMinutes } }
    @Published var lengthFraction: Double { didSet { settings.lengthFraction = CGFloat(lengthFraction) } }
    @Published var displayUUID: String { didSet {
        settings.displayUUID = displayUUID.isEmpty ? nil : displayUUID
    } }
    @Published var showsOnAllDisplays: Bool {
        didSet { settings.showsOnAllDisplays = showsOnAllDisplays }
    }
    @Published var background: BandBackground { didSet { settings.background = background } }
    @Published var areaFill: Bool { didSet { settings.areaFill = areaFill } }
    @Published var liftsWhenOpen: Bool { didSet { settings.liftsWhenOpen = liftsWhenOpen } }
    @Published var envelopeMetric: Metric { didSet { settings.envelopeMetric = envelopeMetric } }
    @Published var fillMetric: Metric { didSet { settings.fillMetric = fillMetric } }
    @Published var launchAtLogin: Bool { didSet { applyLaunchAtLogin() } }
    @Published var screens: [ScreenInfo] = Screens.all()

    init(settings: SillSettings) {
        self.settings = settings
        edge = settings.edge
        ramp = settings.ramp
        material = settings.material
        dimWhenFocused = settings.dimWhenFocused
        spanMinutes = settings.spanMinutes
        lengthFraction = Double(settings.lengthFraction)
        displayUUID = settings.displayUUID ?? ""
        showsOnAllDisplays = settings.showsOnAllDisplays
        background = settings.background
        areaFill = settings.areaFill
        liftsWhenOpen = settings.liftsWhenOpen
        envelopeMetric = settings.envelopeMetric
        fillMetric = settings.fillMetric
        launchAtLogin = SMAppService.mainApp.status == .enabled
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.screens = Screens.all()
            }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = launchAtLogin
        } catch {
            // Unsigned builds can't register; put the toggle back rather than lie.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct PreferencesView: View {
    /// Slider rows are pinned to this so their captions cannot resize them.
    static let sliderWidth: CGFloat = 236
    static let lengthRange = Double(WaveGeometry.minimumLengthFraction)
        ... Double(WaveGeometry.maximumLengthFraction)

    @StateObject private var model: PreferencesModel

    init(settings: SillSettings) {
        _model = StateObject(wrappedValue: PreferencesModel(settings: settings))
    }

    var body: some View {
        Form {
            Picker("Edge", selection: $model.edge) {
                Text("Left").tag(ScreenEdge.left)
                Text("Right").tag(ScreenEdge.right)
                Text("Top").tag(ScreenEdge.top)
                Text("Bottom").tag(ScreenEdge.bottom)
            }
            .pickerStyle(.segmented)

            Picker("Display", selection: $model.displayUUID) {
                Text("Main display").tag("")
                ForEach(model.screens, id: \.uuid) { screen in
                    Text(screen.name).tag(screen.uuid)
                }
            }
            .disabled(model.showsOnAllDisplays)

            Toggle("Show on every display", isOn: $model.showsOnAllDisplays)

            Picker("Shape", selection: $model.envelopeMetric) {
                ForEach(Metric.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Fill", selection: $model.fillMetric) {
                ForEach(Metric.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

            Picker("Colour", selection: $model.ramp) {
                ForEach(ColorRamp.allCases, id: \.self) { ramp in
                    Text(ramp.displayName).tag(ramp)
                }
            }
            RampPreview(ramp: model.ramp)
                .frame(height: 52)

            Picker("Background", selection: $model.background) {
                ForEach(BandBackground.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Fill under the lines", isOn: $model.areaFill)

            Picker("Material", selection: $model.material) {
                Text("Clear").tag(PanelMaterial.clear)
                Text("Tinted").tag(PanelMaterial.tinted)
            }
            .pickerStyle(.segmented)

            LabeledContent("Width") {
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $model.lengthFraction,
                           in: PreferencesView.lengthRange, step: 0.05)
                    Text("\((model.lengthFraction * 100).roundedInt)% of the screen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // A slider row is sized by its content, and the caption under
                // the slider changes length as the value changes — so without a
                // fixed width the slider itself grows and shrinks as you drag
                // it. This is the widest the row can be in this window.
                .frame(width: PreferencesView.sliderWidth, alignment: .leading)
            }

            Toggle("Dim when a window is focused", isOn: $model.dimWhenFocused)

            Toggle("Bring forward when opened", isOn: $model.liftsWhenOpen)

            LabeledContent("History") {
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: $model.spanMinutes,
                           in: 0...Span.maximumMinutes, step: 1)
                    Text(model.spanMinutes <= 0 ? "as much as the band holds, a point a second"
                         : model.spanMinutes < 2 ? "1 minute"
                         : "\(model.spanMinutes.roundedInt) minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: PreferencesView.sliderWidth, alignment: .leading)
            }

            Toggle("Launch at login", isOn: $model.launchAtLogin)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Live preview of the selected ramp, drawn with the real wave code.
struct RampPreview: NSViewRepresentable {
    let ramp: ColorRamp

    func makeNSView(context: Context) -> RampPreviewView { RampPreviewView() }

    func updateNSView(_ view: RampPreviewView, context: Context) {
        view.ramp = ramp
    }
}

final class RampPreviewView: NSView {
    private let controller = WaveLayerController()
    var ramp: ColorRamp = .load { didSet { refresh() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(controller.container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        refresh()
    }

    private func refresh() {
        let length = max(bounds.width, 1)
        controller.container.frame = CGRect(x: 0, y: (bounds.height - WaveGeometry.thickness) / 2,
                                            width: length, height: WaveGeometry.thickness)
        // The preview sits on the settings window, which follows the system
        // appearance rather than the wallpaper.
        let luminance = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? 0.12 : 0.92
        controller.configure(edge: .top, length: length, ramp: ramp,
                             scale: window?.backingScaleFactor ?? 2,
                             backdropLuminance: luminance)
        let count = controller.sampleCount
        let cpu = (0..<count).map { i -> Double in
            let t = Double(i) / Double(max(1, count - 1))
            return 18 + 60 * abs(sin(t * 5.2)) * (0.35 + 0.65 * t)
        }
        let memory = (0..<count).map { i in 40 + 45 * sin(Double(i) / 9) }
        controller.reduceMotion = true
        controller.update(frame: WaveModel.Frame(cpu: cpu, memory: memory),
                          interval: 0, tickTime: 0)
    }
}
