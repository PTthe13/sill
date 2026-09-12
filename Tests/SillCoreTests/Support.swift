import CoreGraphics
import Foundation

/// Minimal test harness. The Command Line Tools ship neither XCTest nor a
/// working swift-testing runtime, so the suite is an executable instead
/// (see NOTES.md). `Scripts/gen-test-runner.sh` regenerates Runner.swift.
enum Check {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var currentTest = ""
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "",
            file: StaticString = #file, line: UInt = #line) {
    Check.checks += 1
    guard !condition() else { return }
    let name = "\(file)".split(separator: "/").last.map(String.init) ?? "\(file)"
    Check.failures.append("\(Check.currentTest): \(name):\(line) \(message)")
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }
func approx(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 1e-9) -> Bool { abs(a - b) <= tol }

func runTest(_ name: String, _ body: () -> Void) {
    Check.currentTest = name
    body()
}
