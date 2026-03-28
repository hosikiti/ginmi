import Foundation

enum PerfLogger {
    static let enabled = ProcessInfo.processInfo.environment["GINMI_DEBUG_PERF"] == "1"

    @discardableResult
    static func start(_ stage: String, details: String = "") -> CFAbsoluteTime {
        let start = CFAbsoluteTimeGetCurrent()
        guard enabled else { return start }
        if details.isEmpty {
            print("GINMI_PERF start stage=\(stage)")
        } else {
            print("GINMI_PERF start stage=\(stage) \(details)")
        }
        return start
    }

    static func end(_ stage: String, from start: CFAbsoluteTime, details: String = "") {
        guard enabled else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        if details.isEmpty {
            print(String(format: "GINMI_PERF end stage=%@ elapsed_ms=%.2f", stage, elapsedMs))
        } else {
            print(String(format: "GINMI_PERF end stage=%@ elapsed_ms=%.2f %@", stage, elapsedMs, details))
        }
    }

    @discardableResult
    static func measure<T>(_ stage: String, details: String = "", _ block: () -> T) -> T {
        let start = start(stage, details: details)
        let value = block()
        end(stage, from: start, details: details)
        return value
    }

    static func log(_ message: String) {
        guard enabled else { return }
        print("GINMI_PERF \(message)")
    }

    static func logIfSlow(stage: String, from start: CFAbsoluteTime, thresholdMs: Double, details: String = "") {
        guard enabled else { return }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard elapsedMs >= thresholdMs else { return }
        if details.isEmpty {
            print(String(format: "GINMI_PERF slow stage=%@ elapsed_ms=%.2f", stage, elapsedMs))
        } else {
            print(String(format: "GINMI_PERF slow stage=%@ elapsed_ms=%.2f %@", stage, elapsedMs, details))
        }
    }
}
