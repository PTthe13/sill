import Darwin
import Foundation

public struct ProcessUsage: Equatable, Sendable, Identifiable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
    }
}

/// Top processes by CPU. Only runs while the detail band is open.
///
/// The pid list comes from sysctl(KERN_PROC_ALL); the CPU figure is the delta
/// in each process's own CPU time, which is what Activity Monitor shows.
public final class ProcessSampler {
    private var previousTime: [Int32: UInt64] = [:]
    private var previousDate = Date()

    public init() {}

    /// Clears the baseline so the next sample measures from now.
    public func reset() {
        previousTime.removeAll()
        previousDate = Date()
    }

    private func allProcesses() -> [kinfo_proc] {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&name, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        let result = procs.withUnsafeMutableBytes { buffer -> Int32 in
            var length = size
            return sysctl(&name, 4, buffer.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return [] }
        return procs
    }

    private func cpuNanoseconds(pid: Int32) -> UInt64? {
        var info = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_user_time + info.ri_system_time
    }

    /// Top `limit` processes by CPU share since the previous call.
    /// The first call after `reset()` returns an empty list — there is no
    /// baseline to subtract yet.
    public func sample(limit: Int = 4) -> [ProcessUsage] {
        let now = Date()
        let elapsed = now.timeIntervalSince(previousDate)
        var current: [Int32: UInt64] = [:]
        var usage: [ProcessUsage] = []

        for proc in allProcesses() {
            let pid = proc.kp_proc.p_pid
            guard pid > 0, let nanoseconds = cpuNanoseconds(pid: pid) else { continue }
            current[pid] = nanoseconds
            guard let before = previousTime[pid], nanoseconds >= before, elapsed > 0 else { continue }
            let percent = Double(nanoseconds - before) / 1_000_000_000 / elapsed * 100
            guard percent >= 0.1 else { continue }
            var name = proc.kp_proc.p_comm
            let comm: String = withUnsafeBytes(of: &name) { buffer in
                guard let base = buffer.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            // p_comm truncates at 16 characters; the executable path keeps the
            // rest of the name ("Claude Helper (Renderer)").
            let full = Self.executableName(pid: pid) ?? comm
            usage.append(ProcessUsage(pid: pid, name: full.isEmpty ? "pid \(pid)" : full,
                                      cpuPercent: percent))
        }

        previousTime = current
        previousDate = now
        return Array(usage.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
    }

    static func executableName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(cString: buffer)
        guard !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }

    /// Keeps rows in their frozen order while refreshing their numbers, so the
    /// list doesn't jump under the pointer while it is being read.
    public static func merge(frozen: [ProcessUsage], fresh: [ProcessUsage]) -> [ProcessUsage] {
        guard !frozen.isEmpty else { return fresh }
        let byPid = Dictionary(uniqueKeysWithValues: fresh.map { ($0.pid, $0) })
        return frozen.map { row in
            ProcessUsage(pid: row.pid, name: row.name,
                         cpuPercent: byPid[row.pid]?.cpuPercent ?? 0)
        }
    }
}
