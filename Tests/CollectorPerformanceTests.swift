import Foundation

@main
struct CollectorPerformanceTests {
    static func main() {
        let memoryCollector = MemoryCollector()
        let powerCollector = PowerCollector()
        let diagnosticsCollector = SystemDiagnosticsCollector()

        let memoryElapsed = measure(iterations: 200) {
            _ = memoryCollector.collect()
        }
        require(memoryElapsed < 5.0, "200 memory polls exceeded 5s budget: \(format(memoryElapsed))s")

        let powerElapsed = measure(iterations: 100) {
            _ = powerCollector.collect()
        }
        require(powerElapsed < 5.0, "100 power polls exceeded 5s budget: \(format(powerElapsed))s")

        // Prime Mach CPU counters before timing the lightweight diagnostics path.
        _ = diagnosticsCollector.collect(includeProcesses: false)
        let diagnosticsElapsed = measure(iterations: 100) {
            _ = diagnosticsCollector.collect(includeProcesses: false)
        }
        require(diagnosticsElapsed < 5.0, "100 lightweight diagnostics polls exceeded 5s budget: \(format(diagnosticsElapsed))s")

        let processElapsed = measure(iterations: 1) {
            _ = diagnosticsCollector.collect(includeProcesses: true)
        }
        require(processElapsed < 3.0, "Process snapshot exceeded 3s budget: \(format(processElapsed))s")

        let compositeElapsed = measure(iterations: 50) {
            _ = memoryCollector.collect()
            _ = powerCollector.collect()
            _ = diagnosticsCollector.collect(includeProcesses: false)
        }
        require(compositeElapsed < 5.0, "50 normal monitoring cycles exceeded 5s CPU-time budget: \(format(compositeElapsed))s")

        print("PASS Collector performance budgets")
        print("  memory 200x: \(format(memoryElapsed))s")
        print("  power 100x: \(format(powerElapsed))s")
        print("  diagnostics light 100x: \(format(diagnosticsElapsed))s")
        print("  process snapshot 1x: \(format(processElapsed))s")
        print("  composite 50x: \(format(compositeElapsed))s")
    }

    private static func measure(iterations: Int, operation: () -> Void) -> TimeInterval {
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations {
            operation()
        }
        return ProcessInfo.processInfo.systemUptime - start
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func format(_ value: TimeInterval) -> String {
        String(format: "%.3f", value)
    }
}
