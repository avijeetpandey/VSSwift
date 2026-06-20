import Foundation

/// A minimal, dependency-free test harness used because this environment has only
/// the Command Line Tools (no XCTest / swift-testing). Tests run as executables and
/// the process exits non-zero on any failure, so CI/`swift run` can verify them.
public final class TestContext: @unchecked Sendable {
    public private(set) var failures: [String] = []
    public private(set) var assertions = 0
    private let lock = NSLock()

    public init() {}

    private func fail(_ message: String, _ file: StaticString, _ line: UInt) {
        lock.lock(); defer { lock.unlock() }
        failures.append("\(file):\(line): \(message)")
    }

    private func record() {
        lock.lock(); assertions += 1; lock.unlock()
    }

    public func expect(_ condition: Bool, _ message: @autoclosure () -> String = "expected true",
                        file: StaticString = #file, line: UInt = #line) {
        record()
        if !condition { fail(message(), file, line) }
    }

    public func equal<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "",
                                    file: StaticString = #file, line: UInt = #line) {
        record()
        if a != b {
            let extra = message().isEmpty ? "" : " — \(message())"
            fail("expected \(a) == \(b)\(extra)", file, line)
        }
    }

    public func close(_ a: Double, _ b: Double, accuracy: Double = 1e-9,
                      _ message: @autoclosure () -> String = "",
                      file: StaticString = #file, line: UInt = #line) {
        record()
        if abs(a - b) > accuracy { fail("expected \(a) ≈ \(b) (±\(accuracy)) \(message())", file, line) }
    }

    public func notNil<T>(_ value: T?, _ message: @autoclosure () -> String = "expected non-nil",
                          file: StaticString = #file, line: UInt = #line) {
        record()
        if value == nil { fail(message(), file, line) }
    }

    public func isNil<T>(_ value: T?, _ message: @autoclosure () -> String = "expected nil",
                         file: StaticString = #file, line: UInt = #line) {
        record()
        if value != nil { fail(message(), file, line) }
    }

    public func throwsError(_ body: () throws -> Void, _ message: @autoclosure () -> String = "expected throw",
                            file: StaticString = #file, line: UInt = #line) {
        record()
        do { try body(); fail(message(), file, line) } catch { /* expected */ }
    }
}

/// Collects and runs named test closures, printing a summary and setting exit code.
public final class TestSuite: @unchecked Sendable {
    private let name: String
    private var cases: [(String, @Sendable (TestContext) async throws -> Void)] = []

    public init(_ name: String) { self.name = name }

    public func test(_ name: String, _ body: @escaping @Sendable (TestContext) async throws -> Void) {
        cases.append((name, body))
    }

    /// Runs all tests; returns true if all passed.
    @discardableResult
    public func run() async -> Bool {
        print("▶ Suite: \(name) (\(cases.count) tests)")
        var passed = 0
        var failedNames: [String] = []
        for (testName, body) in cases {
            let ctx = TestContext()
            do {
                try await body(ctx)
            } catch {
                ctx.expect(false, "threw unexpected error: \(error)")
            }
            if ctx.failures.isEmpty {
                passed += 1
                print("  ✓ \(testName)")
            } else {
                failedNames.append(testName)
                print("  ✗ \(testName)")
                for f in ctx.failures { print("      \(f)") }
            }
        }
        let ok = failedNames.isEmpty
        print("  → \(passed)/\(cases.count) passed\n")
        return ok
    }
}

/// Runs multiple suites and exits the process with a non-zero code on any failure.
public func runSuitesAndExit(_ suites: [TestSuite]) async -> Never {
    var allOK = true
    for suite in suites {
        let ok = await suite.run()
        allOK = allOK && ok
    }
    if allOK {
        print("✅ ALL TESTS PASSED")
        exit(0)
    } else {
        print("❌ TESTS FAILED")
        exit(1)
    }
}
