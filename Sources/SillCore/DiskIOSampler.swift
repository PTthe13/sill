import Foundation
import IOKit

/// Disk read and write throughput, from the block storage drivers' own
/// statistics — the same registry route the GPU reading uses, so it needs no
/// helper, no entitlement and no admin.
///
/// Like the process list, this only runs while the detail band is open.
public final class DiskIOSampler {
    /// The registry spellings, straight from IOBlockStorageDriver.h — the
    /// constants themselves are not exposed to Swift.
    private enum Keys {
        static let statistics = "Statistics"
        static let bytesRead = "Bytes (Read)"
        static let bytesWritten = "Bytes (Write)"
    }

    private var previous: (read: UInt64, written: UInt64)?
    private var previousTime = Date()

    public init() {}

    /// Bytes read and written per second since the previous call. `down` is
    /// read, `up` is written, matching how the panel shows network.
    public func sample() -> Throughput {
        let now = counters()
        let time = Date()
        defer { previous = now; previousTime = time }
        guard let previous else { return .zero }
        let elapsed = time.timeIntervalSince(previousTime)
        guard elapsed > 0 else { return .zero }
        let read = now.read >= previous.read ? Double(now.read - previous.read) / elapsed : 0
        let written = now.written >= previous.written
            ? Double(now.written - previous.written) / elapsed : 0
        return Throughput(down: read, up: written)
    }

    private func counters() -> (read: UInt64, written: UInt64) {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, written: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let statistics = properties[Keys.statistics] as? [String: Any]
            else { continue }
            if let bytes = statistics[Keys.bytesRead] as? NSNumber { read += bytes.uint64Value }
            if let bytes = statistics[Keys.bytesWritten] as? NSNumber {
                written += bytes.uint64Value
            }
        }
        return (read, written)
    }
}
