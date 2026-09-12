import Darwin
import Foundation

/// One point in time, as the wave and the panel see it.
public struct Sample: Sendable, Equatable {
    public var cpuPercent: Double
    public var memoryPercent: Double
    public var memoryUsedBytes: UInt64

    public init(cpuPercent: Double = 0, memoryPercent: Double = 0, memoryUsedBytes: UInt64 = 0) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.memoryUsedBytes = memoryUsedBytes
    }
}

/// Total CPU busy percentage, from the delta between two host_statistics64 reads.
public final class CPUSampler {
    private var previous: host_cpu_load_info?

    public init() {}

    private func read() -> host_cpu_load_info? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// Busy percentage since the previous call. The first call returns 0.
    public func sample() -> Double {
        guard let now = read() else { return 0 }
        defer { previous = now }
        guard let last = previous else { return 0 }
        let user = Double(now.cpu_ticks.0 &- last.cpu_ticks.0)
        let system = Double(now.cpu_ticks.1 &- last.cpu_ticks.1)
        let idle = Double(now.cpu_ticks.2 &- last.cpu_ticks.2)
        let nice = Double(now.cpu_ticks.3 &- last.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        guard total > 0 else { return 0 }
        return min(100, max(0, busy / total * 100))
    }
}

/// Memory pressure and bytes in use, from vm_statistics64.
public enum MemorySampler {
    public static let totalBytes = ProcessInfo.processInfo.physicalMemory

    public static func sample() -> (percent: Double, usedBytes: UInt64) {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
                                          / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS, totalBytes > 0 else { return (0, 0) }
        let page = UInt64(vm_kernel_page_size)
        // Activity Monitor's "Memory Used" = app memory + wired + compressed,
        // where app memory is internal (anonymous) pages less purgeable ones.
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count),
                                                          UInt64(stats.purgeable_count))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let percent = min(100, Double(used) / Double(totalBytes) * 100)
        return (percent, used)
    }
}

/// Free space on the boot volume. Sampled once a minute.
public enum DiskSampler {
    public static func availableBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Bytes per second in each direction.
public struct Throughput: Equatable, Sendable {
    public var down: Double
    public var up: Double

    public init(down: Double = 0, up: Double = 0) {
        self.down = down
        self.up = up
    }

    public var total: Double { down + up }
    public static let zero = Throughput()
}

/// Throughput across all non-loopback interfaces, as a delta over the interval,
/// split by direction — "2.4 down" and "0.3 up" answer different questions.
public final class NetworkSampler {
    private var previous: (down: UInt64, up: UInt64)?
    private var previousTime = Date()

    public init() {}

    private func counters() -> (down: UInt64, up: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var down: UInt64 = 0, up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                down += UInt64(data.pointee.ifi_ibytes)
                up += UInt64(data.pointee.ifi_obytes)
            }
            pointer = interface.ifa_next
        }
        return (down, up)
    }

    /// Bytes per second since the previous call. The first call returns zero:
    /// there is no baseline to subtract yet.
    public func sample() -> Throughput {
        let now = counters()
        let time = Date()
        defer { previous = now; previousTime = time }
        guard let previous else { return .zero }
        let elapsed = time.timeIntervalSince(previousTime)
        guard elapsed > 0 else { return .zero }
        // Counters reset when an interface goes away; a negative delta is not
        // a measurement, it is a restart.
        let down = now.down >= previous.down ? Double(now.down - previous.down) / elapsed : 0
        let up = now.up >= previous.up ? Double(now.up - previous.up) / elapsed : 0
        return Throughput(down: down, up: up)
    }
}
