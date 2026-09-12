import Foundation
import IOKit

/// GPU utilisation, read from the accelerator's own performance statistics.
///
/// Every rival shows a GPU figure and Sill did not. This needs no helper, no
/// entitlement and no admin — it is one IOKit registry lookup — and like the
/// process list it only runs while the detail band is open.
public enum GPUSampler {
    /// Percentage 0...100, or nil when no accelerator reports utilisation.
    public static func utilisation() -> Double? {
        var iterator = io_iterator_t()
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                  let properties = unmanaged?.takeRetainedValue() as? [String: Any],
                  let statistics = properties["PerformanceStatistics"] as? [String: Any]
            else { continue }
            // Apple Silicon and Intel spell this differently.
            let keys = ["Device Utilization %", "GPU Activity(%)", "Renderer Utilization %"]
            for key in keys {
                if let value = statistics[key] as? NSNumber {
                    let percent = min(100, max(0, value.doubleValue))
                    best = max(best ?? 0, percent)
                    break
                }
            }
        }
        return best
    }
}
