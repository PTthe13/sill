import AppKit
import ServiceManagement
import SillCore

// `sill --probe` prints a few samples and exits: a quick way to check the
// numbers against Activity Monitor without launching the window.
if CommandLine.arguments.contains("--probe") {
    let cpu = CPUSampler()
    _ = cpu.sample()
    for _ in 0..<5 {
        Thread.sleep(forTimeInterval: 1)
        let memory = MemorySampler.sample()
        print(String(format: "cpu %.1f%%  mem %.1f%% (%@ of %@)", cpu.sample(), memory.percent,
                     Format.bytes(Int64(memory.usedBytes)),
                     Format.bytes(Int64(MemorySampler.totalBytes))))
    }
    exit(0)
}

// `sill --open` / `--close` set the band's state explicitly; `--toggle` flips it.
if CommandLine.arguments.contains("--open") || CommandLine.arguments.contains("--close") {
    let wanted = CommandLine.arguments.contains("--open") ? "open" : "close"
    if let index = CommandLine.arguments.firstIndex(of: "--delay"),
       CommandLine.arguments.count > index + 1,
       let delay = Double(CommandLine.arguments[index + 1]) {
        Thread.sleep(forTimeInterval: delay)
    }
    DistributedNotificationCenter.default()
        .postNotificationName(NSNotification.Name("app.sill.debug.setOpen"),
                              object: wanted, userInfo: nil, deliverImmediately: true)
    exit(0)
}

if CommandLine.arguments.contains("--toggle") {
    // `--delay <seconds>` gives a screenshot loop time to get going first.
    if let index = CommandLine.arguments.firstIndex(of: "--delay"),
       CommandLine.arguments.count > index + 1,
       let delay = Double(CommandLine.arguments[index + 1]) {
        Thread.sleep(forTimeInterval: delay)
    }
    DistributedNotificationCenter.default()
        .postNotificationName(NSNotification.Name("app.sill.debug.toggle"),
                              object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// `sill --render <dir>` writes one PNG per edge x ramp: the golden images the
// test suite compares against.
if let index = CommandLine.arguments.firstIndex(of: "--render") {
    let directory = URL(fileURLWithPath: CommandLine.arguments.count > index + 1
                        ? CommandLine.arguments[index + 1] : "Tests/Golden")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var length: CGFloat = 240
    if let index = CommandLine.arguments.firstIndex(of: "--length"),
       CommandLine.arguments.count > index + 1,
       let custom = Double(CommandLine.arguments[index + 1]) {
        length = CGFloat(custom)
    }
    let count = WaveGeometry.sampleCount(forLength: length + 2 * WaveGeometry.step)
    let cpu = Fixtures.cpu(count: count)
    let memory = Fixtures.memory(count: count)
    // Two backdrops: the dark wallpaper the ramps were designed for, and a
    // light busy one, which is the case that used to be unreadable.
    let backdrops: [(name: String, luminance: Double, variation: Double)] = [
        ("dark", Palette.assumedLuminance, 0),
        ("light", 0.85, 1),
    ]
    var written = 0
    let onlyEdge = CommandLine.arguments.firstIndex(of: "--edge-only").flatMap {
        CommandLine.arguments.count > $0 + 1 ? ScreenEdge(rawValue: CommandLine.arguments[$0 + 1]) : nil
    }
    for backdrop in backdrops {
        let folder = backdrop.name == "dark" ? directory
            : directory.appendingPathComponent(backdrop.name)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for edge in ScreenEdge.allCases where onlyEdge == nil || onlyEdge == edge {
            for ramp in ColorRamp.allCases {
                let options = WaveRenderer.Options(edge: edge, ramp: ramp, length: length,
                                                   scale: 2,
                                                   backdropLuminance: backdrop.luminance,
                                                   backdropVariation: backdrop.variation)
                guard let image = WaveRenderer.image(cpu: cpu, memory: memory,
                                                     options: options) else {
                    print("failed \(edge.rawValue)-\(ramp.rawValue)")
                    continue
                }
                WaveRenderer.write(image, to: folder
                    .appendingPathComponent("\(edge.rawValue)-\(ramp.rawValue).png"))
                written += 1
            }
        }
    }
    // The two optional treatments: a dark plate behind the band, and the fill
    // between the envelopes.
    let optionsFolder = directory.appendingPathComponent("options")
    try? FileManager.default.createDirectory(at: optionsFolder, withIntermediateDirectories: true)
    for edge in ScreenEdge.allCases {
        for (name, plate, fill) in [("dark", BandBackground.shade, false),
                                    ("light", BandBackground.light, false),
                                    ("area", BandBackground.none, true)] {
            var options = WaveRenderer.Options(edge: edge, ramp: .load, length: length, scale: 2)
            options.plate = plate
            options.areaFill = fill
            guard let image = WaveRenderer.image(cpu: cpu, memory: memory,
                                                 options: options) else { continue }
            WaveRenderer.write(image, to: optionsFolder
                .appendingPathComponent("\(edge.rawValue)-\(name).png"))
            written += 1
        }
    }

    // The hover hint, both directions, on one edge set each.
    let hintFolder = directory.appendingPathComponent("hint")
    try? FileManager.default.createDirectory(at: hintFolder, withIntermediateDirectories: true)
    for edge in ScreenEdge.allCases {
        for (name, inboard) in [("closed", true), ("open", false)] {
            var options = WaveRenderer.Options(edge: edge, ramp: .load, length: length, scale: 2)
            options.affordance = inboard
            guard let image = WaveRenderer.image(cpu: cpu, memory: memory,
                                                 options: options) else { continue }
            WaveRenderer.write(image, to: hintFolder
                .appendingPathComponent("\(edge.rawValue)-\(name).png"))
            written += 1
        }
    }
    print("wrote \(written) images to \(directory.path)")
    exit(0)
}

// `sill --icon <dir.iconset>` renders the app icon at every size macOS wants.
if let index = CommandLine.arguments.firstIndex(of: "--icon") {
    let directory = URL(fileURLWithPath: CommandLine.arguments.count > index + 1
                        ? CommandLine.arguments[index + 1] : "build/Sill.iconset")
    IconRenderer.writeIconset(to: directory)
    print("wrote iconset to \(directory.path)")
    exit(0)
}

// `sill --click <x> <y>` clicks at a screen point (top-left origin), to time
// the path from mouse-down to an open panel.
if let index = CommandLine.arguments.firstIndex(of: "--click"),
   CommandLine.arguments.count > index + 2,
   let x = Double(CommandLine.arguments[index + 1]),
   let y = Double(CommandLine.arguments[index + 2]) {
    let point = CGPoint(x: x, y: y)
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(30_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    print("clicked \(point)")
    exit(0)
}

// `sill --exposed` reports which part of the band's own strip is covered by
// other apps' windows. The band is desktop-level, so anything on top of it
// hides it and suspends sampling — which looks exactly like a drawing bug
// unless you can see the coverage.
if CommandLine.arguments.contains("--exposed") {
    let settings = SillSettings()
    for screen in NSScreen.screens {
        let info = Screens.info(for: screen)
        let band = Layout.waveFrame(edge: settings.edge, visibleFrame: info.visibleFrame,
                                    fraction: settings.lengthFraction,
                                    screenFrame: info.frame)
        let occupied = ExposedDesktop.occupiedFrames(on: info.visibleFrame)
        let covered = PanelPlacement.coverage(of: band, by: occupied)
        print(String(format: "%-28s band %@ covered %.0f%% by %d window(s)",
                     (info.name as NSString).utf8String!, band.debugDescription,
                     covered * 100, occupied.count))
    }
    exit(0)
}

// `sill --backdrop` reports how light each display's wallpaper is behind the
// band, and what that does to the strands.
if CommandLine.arguments.contains("--backdrop") {
    let settings = SillSettings()
    for screen in NSScreen.screens {
        let info = Screens.info(for: screen)
        let band = Layout.waveFrame(edge: settings.edge, visibleFrame: info.visibleFrame,
                                    fraction: settings.lengthFraction,
                                    screenFrame: info.frame)
        let sample = Backdrop.measure(screen: screen, rect: band, edge: settings.edge)
        let style = Palette.style(ramp: settings.ramp, backdropLuminance: sample.luminance,
                                  backdropVariation: sample.variation)
        let wallpaper = NSWorkspace.shared.desktopImageURL(for: screen)?.lastPathComponent ?? "—"
        // A coarse picture of the band, newest end first: # dark, - mid, . light.
        let sparkline = sample.profile.map { value -> String in
            let t = Palette.lightness(backdropLuminance: value)
            return t < 0.25 ? "#" : t < 0.75 ? "-" : "."
        }.joined()
        print(String(format: "%-26@ luminance %.2f  busy %.2f  strand %.2f/%.2f  halo %.2f  %@",
                     info.name as NSString, sample.luminance, sample.variation,
                     style.outerOpacity, style.innerOpacity, style.haloOuterAlpha,
                     wallpaper as NSString))
        print("   \(sparkline)  (newest end first)")
    }
    exit(0)
}

// `sill --preview <dir>` draws the wave over each display's real wallpaper.
if let index = CommandLine.arguments.firstIndex(of: "--preview") {
    let directory = URL(fileURLWithPath: CommandLine.arguments.count > index + 1
                        ? CommandLine.arguments[index + 1] : "build/preview")
    let settings = SillSettings()
    let ramps = CommandLine.arguments.contains("--all-ramps")
        ? ColorRamp.allCases : [settings.ramp]
    // --hover / --hover-open draw the hint in its two directions.
    let affordance: Bool? = CommandLine.arguments.contains("--hover-open") ? false
        : CommandLine.arguments.contains("--hover") ? true : nil
    BackdropPreview.write(to: directory, ramps: ramps, edge: settings.edge,
                          fraction: settings.lengthFraction, affordance: affordance,
                          background: CommandLine.arguments.contains("--shade") ? .shade : .none,
                          areaFill: CommandLine.arguments.contains("--area"))
    exit(0)
}

// `sill --settings` opens the settings window of a running instance.
if CommandLine.arguments.contains("--settings") {
    DistributedNotificationCenter.default()
        .postNotificationName(NSNotification.Name("app.sill.debug.settings"),
                              object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// `sill --hover [off]` shows or hides the hover hint in a running instance.
if CommandLine.arguments.contains("--hover") {
    let state = CommandLine.arguments.contains("off") ? "off" : "on"
    DistributedNotificationCenter.default()
        .postNotificationName(NSNotification.Name("app.sill.debug.hover"),
                              object: state, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// `sill --luma a.png b.png ...` prints each image's mean luminance: enough to
// watch a fade run frame by frame.
if CommandLine.arguments.contains("--luma") {
    for path in CommandLine.arguments.dropFirst() where path.hasSuffix(".png") {
        guard let image = WaveRenderer.read(URL(fileURLWithPath: path)),
              let value = ShiftProbe.meanLuminance(image) else {
            print("\((path as NSString).lastPathComponent): unreadable")
            continue
        }
        print(String(format: "%@ %.4f", (path as NSString).lastPathComponent, value))
    }
    exit(0)
}

// `sill --reload` makes a running instance re-read its defaults, so settings
// changed with `defaults write` apply without a relaunch.
if CommandLine.arguments.contains("--reload") {
    DistributedNotificationCenter.default()
        .postNotificationName(NSNotification.Name("app.sill.debug.reload"),
                              object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

// `sill --login-check` reports whether Launch at login can register, and undoes
// itself: the toggle is only honest if registration actually works.
if CommandLine.arguments.contains("--login-check") {
    let service = SMAppService.mainApp
    print("status before: \(service.status.rawValue)")
    do {
        try service.register()
        print("register: ok, status now \(SMAppService.mainApp.status.rawValue)")
        try service.unregister()
        print("unregister: ok, status now \(SMAppService.mainApp.status.rawValue)")
    } catch {
        print("failed: \(error.localizedDescription)")
    }
    exit(0)
}

// `sill --io` prints network and disk throughput, to check they read anything.
if CommandLine.arguments.contains("--io") {
    let network = NetworkSampler(), disk = DiskIOSampler()
    _ = network.sample(); _ = disk.sample()
    for _ in 0..<4 {
        Thread.sleep(forTimeInterval: 1)
        let n = network.sample(), d = disk.sample()
        print(String(format: "net %.2f down %.2f up   disk %.2f read %.2f write  (MB/s)",
                     n.down / 1_048_576, n.up / 1_048_576,
                     d.down / 1_048_576, d.up / 1_048_576))
    }
    exit(0)
}

// `sill --gpu` prints the GPU reading, to check it reports anything at all.
if CommandLine.arguments.contains("--gpu") {
    for _ in 0..<3 {
        print("gpu: \(GPUSampler.utilisation().map { String(format: "%.1f%%", $0) } ?? "unavailable")")
        Thread.sleep(forTimeInterval: 0.7)
    }
    exit(0)
}

// `sill --dump` prints the settings as the app reads them.
if CommandLine.arguments.contains("--dump") {
    let settings = SillSettings()
    print("""
    edge            \(settings.edge.rawValue)
    display         \(settings.displayUUID ?? "main")
    every display   \(settings.showsOnAllDisplays)
    shape           \(settings.envelopeMetric.rawValue)
    fill            \(settings.fillMetric.rawValue)
    ramp            \(settings.ramp.rawValue)
    behind          \(settings.background.rawValue)
    area fill       \(settings.areaFill)
    material        \(settings.material.rawValue)
    width           \(settings.lengthFraction)
    dim             \(settings.dimWhenFocused)
    lift when open  \(settings.liftsWhenOpen)
    interval        \(settings.sampleInterval)
    span            \(settings.spanMinutes <= 0 ? "auto" : "\(Int(settings.spanMinutes)) min")
    """)
    exit(0)
}

// `sill --windows` prints Sill's own windows as the window server sees them.
if CommandLine.arguments.contains("--windows") {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let all = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
    let everything = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                      as? [[String: Any]]) ?? []
    for (label, list) in [("on screen", all), ("all", everything)] {
        let mine = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "Sill" }
        print("\(label): \(mine.count) window(s)")
        for window in mine {
            let bounds = (window[kCGWindowBounds as String] as? [String: Any])
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            print("   layer \(window[kCGWindowLayer as String] ?? "?") "
                  + "alpha \(window[kCGWindowAlpha as String] ?? "?") "
                  + "bounds \(bounds?.debugDescription ?? "?")")
        }
    }
    exit(0)
}

// `sill --screens` lists the connected displays and their stable identifiers.
if CommandLine.arguments.contains("--screens") {
    for screen in Screens.all() {
        print("\(screen.isMain ? "*" : " ") \(screen.uuid)  \(screen.name)  "
              + "\(Int(screen.visibleFrame.width))x\(Int(screen.visibleFrame.height))"
              + " @\(screen.backingScaleFactor)x")
    }
    exit(0)
}

// `sill --shift [--vertical] a.png b.png ...` reports how far the band moved
// between consecutive screenshots.
if CommandLine.arguments.contains("--shift") {
    let paths = CommandLine.arguments.dropFirst().filter { $0.hasSuffix(".png") }
    ShiftProbe.run(paths: Array(paths),
                   vertical: CommandLine.arguments.contains("--vertical"),
                   maxShift: 24)
    exit(0)
}

let application = NSApplication.shared
let controller = AppController()
application.delegate = controller
application.run()
