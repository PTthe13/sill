import CoreGraphics
import Foundation
import IOKit.ps

enum Power {
    /// The screen-lock notifications are not reliably delivered, so ask the
    /// window server session directly.
    static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

/// Battery percentage and charging state, refreshed when the system says so.
final class PowerSource {
    private(set) var percent: Int?
    private(set) var isCharging = false
    private(set) var isOnBattery = false
    /// Minutes until empty (or until full while charging), when the system has
    /// an estimate — it reports -1 while it is still working one out.
    private(set) var minutesRemaining: Int?

    var onChange: (() -> Void)?
    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
    }

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let source = Unmanaged<PowerSource>.fromOpaque(context).takeUnretainedValue()
            source.refresh()
            source.onChange?()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    func refresh() {
        isOnBattery = (IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?)
            .map { $0 != kIOPMACPowerKey } ?? false

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            percent = nil
            return
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any] else { continue }
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 {
                percent = Int((Double(current) / Double(max) * 100).rounded())
            }
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = description[key] as? Int ?? -1
            minutesRemaining = minutes > 0 ? minutes : nil
        }
    }
}
