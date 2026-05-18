import Foundation

enum HostStore {
    private static let fileName = "hosts.json"
    private static let directoryName = "JTsPingMonitor"
    private static let legacyDirectoryName = "PingMonitor"

    private static var appSupportBase: URL {
        let fm = FileManager.default
        return (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    }

    private static var fileURL: URL {
        let dir = appSupportBase.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private static var legacyFileURL: URL {
        appSupportBase
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func load() -> [PingHost] {
        if let data = try? Data(contentsOf: fileURL),
           let hosts = try? JSONDecoder().decode([PingHost].self, from: data) {
            return hosts
        }
        // One-shot migration: pull from the old PingMonitor directory if present.
        if let data = try? Data(contentsOf: legacyFileURL),
           let hosts = try? JSONDecoder().decode([PingHost].self, from: data) {
            save(hosts)
            return hosts
        }
        return defaults()
    }

    static func save(_ hosts: [PingHost]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(hosts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func defaults() -> [PingHost] {
        [
            PingHost(address: "127.0.0.1", label: "localhost"),
            PingHost(address: "1.1.1.1", label: "Cloudflare DNS"),
            PingHost(address: "8.8.8.8", label: "Google DNS"),
        ]
    }
}
