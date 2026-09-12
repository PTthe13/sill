import AppKit
import Foundation
import QuartzCore
import SillCore

/// Drives sampling: one timer, coalescible wakeups, suspended when nothing
/// can be seen.
final class SampleEngine {
    private(set) var cpu: History
    private(set) var memory: History
    private(set) var latest = Sample()
    private(set) var diskFreeBytes: Int64?
    private(set) var network = Throughput.zero
    private(set) var diskIO = Throughput.zero

    /// A new point joined the history: the wave has something to redraw.
    /// (engine, CACurrentMediaTime of this sample, the history's own interval)
    var onSample: ((SampleEngine, CFTimeInterval, TimeInterval) -> Void)?
    /// A fresh reading arrived that did not join the history — for the panel,
    /// which should show what is happening now rather than the average of the
    /// last half-minute.
    var onReading: (() -> Void)?

    /// How often a point joins the history. With a long span this is much
    /// slower than the sampling itself.
    var preferredInterval: TimeInterval = 1 { didSet { restart() } }

    /// Readings are taken at least this often however slow the history is, so
    /// a long band averages its window instead of sampling one second in
    /// thirty, and the open panel stays live.
    static let readingInterval: TimeInterval = 1
    /// Asked periodically, and again while suspended: the screen-lock
    /// notification is not reliably delivered, so the state is polled instead.
    ///
    /// The probe is an XPC round-trip to the window server — a profile showed
    /// it costing more than drawing the wave — so it runs every few seconds
    /// rather than every sample. A screen that just locked keeps sampling for
    /// a moment; nobody is looking at it.
    var lockProbe: (() -> Bool)?
    static let lockProbeInterval: TimeInterval = 5
    private var lastLockProbe: Date?
    /// Network, disk I/O and GPU are read for the detail band, and for any
    /// metric the wave itself is set to draw. Walking every interface and
    /// registry entry is not free, so nothing is read that nothing shows.
    var wantsDetail = false
    var waveMetrics: Set<Metric> = [.cpu, .memory] { didSet { rebuildHistories() } }
    private(set) var gpuPercent: Double?
    /// Fired with the 60-second disk timer, for anything else that can go stale.
    var onSlowTick: (() -> Void)?
    /// Asked, while the machine is busy, for the name of whatever is eating it.
    var topProcessName: (() -> String?)?
    private(set) var spikes = SpikeLog()
    var powerState = PowerState() { didSet { if powerState != oldValue { restart() } } }

    private var hasRealSample = false
    private var pending: (cpu: Double, memory: Double, count: Double) = (0, 0, 0)
    private var lastHistoryPush = Date()
    private let cpuSampler = CPUSampler()
    private let networkSampler = NetworkSampler()
    private let diskIOSampler = DiskIOSampler()
    private var networkScale = RateScale()
    private var diskScale = RateScale()
    /// One history per metric the wave is drawing.
    private(set) var histories: [Metric: History] = [:]
    private var timer: Timer?
    private var diskTimer: Timer?
    private var resumeTimer: Timer?

    init(capacity: Int, preferredInterval: TimeInterval) {
        self.cpu = History(capacity: capacity, filledWith: 0)
        self.memory = History(capacity: capacity, filledWith: MemorySampler.sample().percent)
        self.preferredInterval = preferredInterval
    }

    func resize(capacity: Int) {
        cpu.resize(to: capacity)
        memory.resize(to: capacity)
        for key in histories.keys { histories[key]?.resize(to: capacity) }
    }

    /// A metric the wave has just been pointed at starts flat at its current
    /// reading rather than at zero.
    private func rebuildHistories() {
        for metric in waveMetrics where histories[metric] == nil {
            histories[metric] = History(capacity: cpu.capacity, filledWith: 0)
        }
        for metric in histories.keys where !waveMetrics.contains(metric) {
            histories[metric] = nil
        }
    }

    private func recordHistories(cpuPercent: Double, memoryPercent: Double) {
        for metric in waveMetrics {
            let value: Double
            switch metric {
            case .cpu: value = cpuPercent
            case .memory: value = memoryPercent
            case .gpu: value = gpuPercent ?? 0
            case .network: value = networkScale.normalise(network.total)
            case .disk: value = diskScale.normalise(diskIO.total)
            }
            if histories[metric] == nil {
                histories[metric] = History(capacity: cpu.capacity, filledWith: value)
            }
            histories[metric]?.push(value)
        }
    }

    /// Readings for the two metrics a band draws.
    func series(envelope: Metric, fill: Metric) -> (envelope: [Double], fill: [Double]) {
        (histories[envelope]?.values ?? cpu.values, histories[fill]?.values ?? memory.values)
    }

    /// How many of the newest samples in `series` were actually measured. A
    /// band draws no further back than this, so a fresh launch grows in from
    /// the live end rather than claiming a flat stretch it never saw.
    func measured(envelope: Metric, fill: Metric) -> Int {
        min(histories[envelope]?.filled ?? cpu.filled, histories[fill]?.filled ?? memory.filled)
    }

    /// What full height means for a rate metric, for the panel to state.
    func fullScaleText(for metric: Metric) -> String? {
        switch metric {
        case .network: return networkScale.fullScaleText
        case .disk: return diskScale.fullScaleText
        default: return nil
        }
    }

    var effectiveInterval: TimeInterval? {
        SamplePlan.interval(preferred: preferredInterval, state: powerState)
    }

    func start() {
        restart()
        guard diskTimer == nil else { return }
        refreshDisk()
        let disk = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshDisk() }
        disk.tolerance = 10
        RunLoop.main.add(disk, forMode: .common)
        diskTimer = disk
    }

    func stop() {
        timer?.invalidate(); timer = nil
        diskTimer?.invalidate(); diskTimer = nil
        resumeTimer?.invalidate(); resumeTimer = nil
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        resumeTimer?.invalidate()
        resumeTimer = nil
        guard let interval = effectiveInterval else {
            scheduleResumeCheck()
            return
        }
        // Sample at least once a second; the history takes a point at its own,
        // slower pace.
        let sampling = min(interval, Self.readingInterval)
        let timer = Timer(timeInterval: sampling, repeats: true) { [weak self] _ in
            self?.tick(interval: interval)
        }
        timer.tolerance = SamplePlan.tolerance(for: sampling)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Debug.log("sampling every \(sampling)s, history every \(interval)s")
        tick(interval: interval)
    }

    /// While suspended there is no sample timer at all, so a slow poll is what
    /// notices the screen coming back.
    private func scheduleResumeCheck() {
        guard lockProbe != nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let locked = self.lockProbe?() else { return }
            if self.powerState.screenLocked != locked {
                self.powerState.screenLocked = locked
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        resumeTimer = timer
    }

    private func refreshDisk() {
        diskFreeBytes = DiskSampler.availableBytes()
        onSlowTick?()
    }

    private func tick(interval: TimeInterval) {
        let now = Date()
        if lastLockProbe.map({ now.timeIntervalSince($0) >= Self.lockProbeInterval }) ?? true {
            lastLockProbe = now
            if let locked = lockProbe?(), locked != powerState.screenLocked {
                powerState.screenLocked = locked   // restarts or suspends the timer
                if locked { return }
            }
        }
        let time = CACurrentMediaTime()
        let cpuPercent = cpuSampler.sample()
        let mem = MemorySampler.sample()
        let needsNetwork = wantsDetail || waveMetrics.contains(.network)
        let needsDisk = wantsDetail || waveMetrics.contains(.disk)
        let needsGPU = wantsDetail || waveMetrics.contains(.gpu)
        network = needsNetwork ? networkSampler.sample() : .zero
        diskIO = needsDisk ? diskIOSampler.sample() : .zero
        gpuPercent = needsGPU ? GPUSampler.utilisation() : nil
        latest = Sample(cpuPercent: cpuPercent, memoryPercent: mem.percent,
                        memoryUsedBytes: mem.usedBytes)
        if !hasRealSample {
            // Start the band flat at the current reading rather than at zero,
            // so a fresh launch doesn't show a fake idle history.
            hasRealSample = true
            cpu = History(capacity: cpu.capacity, filledWith: cpuPercent)
            memory = History(capacity: memory.capacity, filledWith: mem.percent)
        }
        // Only while it is actually busy, and never twice in quick succession:
        // reading the process table is the most expensive thing Sill can do.
        if spikes.shouldSample(cpuPercent: cpuPercent), let name = topProcessName?() {
            spikes.record(name: name, cpuPercent: cpuPercent)
        }
        // Average the window rather than sampling one moment of it: a band
        // showing half an hour would otherwise miss everything between points.
        pending.cpu += cpuPercent
        pending.memory += mem.percent
        pending.count += 1
        guard now.timeIntervalSince(lastHistoryPush) >= interval - Self.readingInterval / 2 else {
            onReading?()
            return
        }
        lastHistoryPush = now
        let meanCPU = pending.count > 0 ? pending.cpu / pending.count : cpuPercent
        let meanMemory = pending.count > 0 ? pending.memory / pending.count : mem.percent
        pending = (0, 0, 0)
        cpu.push(meanCPU)
        memory.push(meanMemory)
        recordHistories(cpuPercent: meanCPU, memoryPercent: meanMemory)
        onSample?(self, time, interval)
    }
}
