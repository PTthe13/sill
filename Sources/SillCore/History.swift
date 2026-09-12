import Foundation

/// Fixed-size, oldest-first ring of samples. Resizing keeps the newest values.
public struct History: Sendable {
    public private(set) var values: [Double]
    public private(set) var capacity: Int

    public init(capacity: Int, filledWith value: Double = 0) {
        self.capacity = max(1, capacity)
        self.values = [Double](repeating: value, count: self.capacity)
    }

    public mutating func push(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public mutating func resize(to newCapacity: Int) {
        let target = max(1, newCapacity)
        guard target != capacity else { return }
        if target < values.count {
            values.removeFirst(values.count - target)
        } else {
            let pad = values.first ?? 0
            values.insert(contentsOf: [Double](repeating: pad, count: target - values.count), at: 0)
        }
        capacity = target
    }

    public var newest: Double { values.last ?? 0 }
}
