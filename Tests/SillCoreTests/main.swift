import Foundation

var failed = 0
for (name, test) in allTests {
    let before = Check.failures.count
    runTest(name, test)
    if Check.failures.count > before { failed += 1 }
}

for failure in Check.failures { FileHandle.standardError.write(Data(("fail  " + failure + "\n").utf8)) }
print("\(allTests.count) tests, \(Check.checks) checks, \(Check.failures.count) failures")
exit(failed == 0 ? 0 : 1)
