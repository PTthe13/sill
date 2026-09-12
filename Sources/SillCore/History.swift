import Foundation

/// Fixed-size, oldest-first ring of samples. Resizing keeps the newest values.
public struct History: Sendable {
    public private(set) var values: [Double]
    public private(set) var capacity: Int

    /// How many of the newest values were actually measured, as opposed to the
    /// seed the ring was created with. The band draws only these: a fresh
    /// launch has no idea what the machine was doing five minutes ago, and
    /// drawing the seed as though it were history is a lie the user can see.
    public private(set) var filled: Int = 0

    public init(capacity: Int, filledWith value: Double = 0) {
        self.capacity = max(1, capacity)
        self.values = [Double](repeating: value, count: self.capacity)
    }

    public mutating func push(_ value: Double) {
        // Nothing non-finite is ever allowed into the history: a NaN here
        // spreads through the smoothing into path coordinates and gradient
        // stops, where Core Graphics quietly draws nothing at all.
        values.append(value.isFinite ? value : 0)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
        filled = min(capacity, filled + 1)
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
        filled = min(filled, target)
    }

    public var newest: Double { values.last ?? 0 }
}
