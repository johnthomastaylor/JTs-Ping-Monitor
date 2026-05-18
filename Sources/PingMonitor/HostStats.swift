import Foundation

struct HostStats: Equatable, Codable {
    var sentCount: Int = 0
    var okCount: Int = 0
    var minMs: Double? = nil
    var maxMs: Double? = nil
    var sumMs: Double = 0
    var currentMs: Double? = nil
    var lastError: String? = nil

    var successRate: Double {
        guard sentCount > 0 else { return 0 }
        return Double(okCount) / Double(sentCount) * 100.0
    }

    var avgMs: Double? {
        guard okCount > 0 else { return nil }
        return sumMs / Double(okCount)
    }

    // Sortable variants (timeouts/unknown sort to the bottom for ascending).
    var currentMsSortable: Double { currentMs ?? .greatestFiniteMagnitude }
    var avgMsSortable: Double { avgMs ?? .greatestFiniteMagnitude }
    var minMsSortable: Double { minMs ?? .greatestFiniteMagnitude }
    var maxMsSortable: Double { maxMs ?? .greatestFiniteMagnitude }

    mutating func record(_ status: HostStatus, slowThresholdMs: Double? = nil) {
        switch status {
        case .up(let ms):
            sentCount += 1
            okCount += 1
            sumMs += ms
            currentMs = ms
            minMs = min(minMs ?? ms, ms)
            maxMs = max(maxMs ?? ms, ms)
            if let threshold = slowThresholdMs, ms > threshold {
                lastError = "slow"
            } else {
                lastError = nil
            }
        case .down:
            sentCount += 1
            currentMs = nil
            lastError = "timeout"
        case .unknown:
            break
        }
    }
}

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var stats: [UUID: HostStats] {
        didSet { StatsPersistence.save(stats) }
    }

    init() {
        self.stats = StatsPersistence.load()
    }

    func pruneToHostIDs(_ ids: Set<UUID>) {
        let filtered = stats.filter { ids.contains($0.key) }
        if filtered.count != stats.count {
            stats = filtered
        }
    }

    func record(_ status: HostStatus, for id: UUID, slowThresholdMs: Double? = nil) {
        var entry = stats[id] ?? HostStats()
        entry.record(status, slowThresholdMs: slowThresholdMs)
        stats[id] = entry
    }

    func record(_ updates: [UUID: HostStatus]) {
        var working = stats
        for (id, status) in updates {
            var entry = working[id] ?? HostStats()
            entry.record(status)
            working[id] = entry
        }
        stats = working
    }

    /// Apply a sequence of poll results in order, with one publish at the end.
    /// Each entry increments its host's counters (so we never undercount when
    /// the same host has multiple results in one batch window).
    func applyBatch(_ entries: [(id: UUID, status: HostStatus, slowThresholdMs: Double)]) {
        guard !entries.isEmpty else { return }
        var working = stats
        for entry in entries {
            var s = working[entry.id] ?? HostStats()
            s.record(entry.status, slowThresholdMs: entry.slowThresholdMs)
            working[entry.id] = s
        }
        stats = working
    }

    func remove(_ id: UUID) {
        stats.removeValue(forKey: id)
    }

    func remove(_ ids: [UUID]) {
        var working = stats
        for id in ids { working.removeValue(forKey: id) }
        stats = working
    }

    func resetAll() {
        stats = [:]
    }

    func reset(_ ids: any Sequence<UUID>) {
        var working = stats
        for id in ids { working[id] = HostStats() }
        stats = working
    }
}

enum StatsPersistence {
    private static let fileName = "stats.json"
    private static let directoryName = "JTsPingMonitor"

    private static var fileURL: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(directoryName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> [UUID: HostStats] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: HostStats].self, from: data) else {
            return [:]
        }
        var result: [UUID: HostStats] = [:]
        for (key, value) in decoded {
            if let id = UUID(uuidString: key) { result[id] = value }
        }
        return result
    }

    static func save(_ stats: [UUID: HostStats]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: stats.map { ($0.key.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(stringKeyed) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
