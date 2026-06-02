import XCTest
@testable import CodeBurnMenubar

final class DataClientProcessTests: XCTestCase {
    /// Concurrency + timeout smoke test: launch more hung subprocesses than
    /// there are cooperative threads, all at once, with a short timeout, and
    /// assert every call returns once the timeout kills its sleep.
    ///
    /// NOTE: this does NOT reproduce the production permanent deadlock (16/16
    /// cooperative threads parked in waitUntilExit). In a short-lived unit-test
    /// process libdispatch spins up replacement threads for blocked workers, so
    /// even the old blocking-on-the-pool code completes here. The real deadlock
    /// built up over ~2 days under the @MainActor refresh loop and is confirmed
    /// by the live `sample`, not by this test. Kept as a guard that the
    /// off-pool wait + timeout path stays correct under concurrency.
    func testConcurrentTimedOutProcessesAllComplete() {
        let count = ProcessInfo.processInfo.activeProcessorCount * 2 + 4
        let done = DispatchSemaphore(value: 0)

        Task {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<count {
                    group.addTask {
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
                        process.arguments = ["30"]
                        _ = try? await DataClient.runProcess(process, timeoutSeconds: 1, label: "sleep 30")
                    }
                }
            }
            done.signal()
        }

        // Wait on the XCTest thread (a real thread, not the cooperative pool) so
        // the deadlock is detectable even when the pool is fully starved.
        let outcome = done.wait(timeout: .now() + 15)
        XCTAssertEqual(outcome, .success,
                       "runProcess deadlocked: \(count) concurrent CLIs starved the cooperative pool")
    }

    /// A normally-exiting process returns its real output and exit code through
    /// the off-pool wait path.
    func testProcessReturnsOutputAndExitCode() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/echo")
        process.arguments = ["hello"]
        let result = try await DataClient.runProcess(process, timeoutSeconds: 5, label: "echo hello")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "hello\n")
    }
}
