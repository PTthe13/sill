import Foundation

/// Remembers what was eating the machine when it was busy.
///
/// The single question a glance at a spike raises is "what was that?", and a
/// band that cannot answer it is decoration. Process lists are the most
/// expensive thing Sill can read, so this records one name only while the
/// machine is actually under load, and no more often than `minimumGap`.
public struct SpikeLog: Sendable {
    /// Load at which a spike is worth attributing.
    public static let threshold: Double = 55
    /// Never read the process table more often than this.
    public static let minimumGap: TimeInterval = 3

    public struct Entry: Equatable, Sendable {
        public let time: Date
        public let name: String
        public let cpuPercent: Double

        public init(time: Date, name: String, cpuPercent: Double) {
            self.time = time
            self.name = name
            self.cpuPercent = cpuPercent
        }
    }

    public private(set) var entries: [Entry] = []
    private var lastSampled: Date?
    private let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    /// Whether the process table is worth reading right now.
    public func shouldSample(cpuPercent: Double, now: Date = Date()) -> Bool {
        guard cpuPercent >= Self.threshold else { return false }
        guard let lastSampled else { return true }
        return now.timeIntervalSince(lastSampled) >= Self.minimumGap
    }

    public mutating func record(name: String, cpuPercent: Double, now: Date = Date()) {
        lastSampled = now
        guard !name.isEmpty else { return }
        entries.append(Entry(time: now, name: name, cpuPercent: cpuPercent))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// The culprit recorded nearest a moment in the past, if one is close
    /// enough to be about that spike rather than a different one.
    /// Load at which a sample is worth naming a culprit for. Below this the
    /// machine was not under pressure and attributing the moment to anything
    /// would be a guess dressed as a fact.
    public static let attributionFloor: Double = 45

    public func culprit(secondsAgo: TimeInterval, now: Date = Date(),
                        tolerance: TimeInterval = 4) -> Entry? {
        let target = now.addingTimeInterval(-secondsAgo)
        return entries
            .map { ($0, abs($0.time.timeIntervalSince(target))) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    /// Drops entries older than the band can show.
    public mutating func prune(olderThan span: TimeInterval, now: Date = Date()) {
        entries.removeAll { now.timeIntervalSince($0.time) > span }
    }
}
