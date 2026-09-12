import Foundation

/// Opt-in switches used to exercise paths that are otherwise driven by system
/// settings. Off unless the matching environment variable is set.
enum Debug {
    static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment[name] == "1"
    }

    static var isEnabled: Bool { flag("SILL_DEBUG") }

    /// Times a block and logs how long it took. Free when SILL_DEBUG is unset.
    @discardableResult
    static func time<T>(_ label: String, _ body: () -> T) -> T {
        guard isEnabled else { return body() }
        let start = Date()
        let result = body()
        log(String(format: "%@ took %.0fms", label, Date().timeIntervalSince(start) * 1000))
        return result
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970
                           .truncatingRemainder(dividingBy: 1000))
        FileHandle.standardError.write(Data(("sill \(stamp): " + message() + "\n").utf8))
    }
}
