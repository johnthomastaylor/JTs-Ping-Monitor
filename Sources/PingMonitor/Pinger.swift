import Foundation

enum Pinger {
    static func ping(_ host: String, timeoutMs: Int = 2000) async -> HostStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runPing(host: host, timeoutMs: timeoutMs))
            }
        }
    }

    private static func runPing(host: String, timeoutMs: Int) -> HostStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-W", String(timeoutMs), "-n", "-q", host]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return .down
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return .down }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        if let latency = parseLatency(from: output) {
            return .up(latencyMs: latency)
        }
        return .up(latencyMs: 0)
    }

    /// Opens a new Terminal window running a continuous `ping` against the host.
    ///
    /// We write a tiny self-deleting `.command` script and hand it to `open`, which
    /// launches it via LaunchServices. This deliberately avoids AppleScript / Apple
    /// Events so the notarized, hardened-runtime app needs no automation entitlement
    /// and triggers no "wants to control Terminal" permission prompt.
    static func openInTerminal(host: String) {
        let script = """
        #!/bin/bash
        rm -f "$0"
        exec ping \(shellQuote(host))

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("JTPing-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        } catch {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", url.path]
        try? process.run()
    }

    /// Wraps a string in single quotes so the shell treats it as one literal argument.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func parseLatency(from output: String) -> Double? {
        // /sbin/ping -q summary line: "round-trip min/avg/max/stddev = 12.345/12.345/12.345/0.000 ms"
        if let range = output.range(of: #"=\s*[0-9.]+/([0-9.]+)/"#, options: .regularExpression) {
            let segment = output[range]
            let parts = segment.split(separator: "/")
            if parts.count >= 2, let value = Double(parts[1]) {
                return value
            }
        }
        // Fallback for non-quiet output: "time=12.345 ms"
        if let range = output.range(of: #"time=([0-9.]+)"#, options: .regularExpression) {
            let segment = output[range].replacingOccurrences(of: "time=", with: "")
            return Double(segment)
        }
        return nil
    }
}
