import Foundation

/// Deterministic sample series, shared by the golden images and the tests so
/// both always draw exactly the same wave.
public enum Fixtures {
    public static func cpu(count: Int) -> [Double] {
        (0..<count).map { i in
            let t = Double(i)
            return WaveModel.clampPercent(
                34 + 30 * sin(t / 7.3) + 18 * sin(t / 2.1) + 12 * sin(t / 23))
        }
    }

    public static func memory(count: Int) -> [Double] {
        (0..<count).map { i in
            let t = Double(i)
            return WaveModel.clampPercent(56 + 34 * sin(t / 17.5) + 6 * sin(t / 3.7))
        }
    }
}
