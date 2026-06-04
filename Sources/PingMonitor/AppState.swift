import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var hosts: [PingHost] {
        didSet {
            scheduleSave()
            if started { rebuildHostTasks() }
        }
    }

    let statusStore: StatusStore
    let statsStore: StatsStore

    private var hostTasks: [UUID: Task<Void, Never>] = [:]
    private var saveTask: Task<Void, Never>?
    private weak var preferences: Preferences?
    private var started = false

    // Poll-result coalescing: per-host writes from the polling tasks land here
    // and are flushed into the stores in one batch per ~150ms window. This
    // collapses dozens of `@Published` writes per second into one or two, and
    // the async-flush hop ensures the publish lands between SwiftUI render
    // passes rather than mid-layout (which was producing
    // "Publishing changes from within view updates" warnings and the
    // occasional NSTableView constraint crash).
    private var pendingResults: [(id: UUID, status: HostStatus, slowThresholdMs: Double)] = []
    private var flushScheduled = false
    private let flushDelayNs: UInt64 = 150_000_000  // 150 ms

    init() {
        let status = StatusStore()
        let stats = StatsStore()
        self.statusStore = status
        self.statsStore = stats
        self.hosts = HostStore.load()

        // Seed status from persisted stats so view-time grouping (e.g. push-down-to-bottom)
        // reflects last-known state immediately instead of waiting for the first ping cycle.
        status.seedUnknown(hosts.map(\.id))
        for host in hosts {
            guard let s = stats.stats[host.id] else { continue }
            if let ms = s.currentMs {
                status.set(.up(latencyMs: ms), for: host.id)
            } else if s.lastError != nil {
                status.set(.down, for: host.id)
            }
        }

        stats.pruneToHostIDs(Set(hosts.map(\.id)))
    }

    func start(preferences: Preferences) {
        self.preferences = preferences
        guard !started else { return }
        started = true
        rebuildHostTasks()
    }

    func stop() {
        for (_, task) in hostTasks { task.cancel() }
        hostTasks.removeAll()
        started = false
    }

    private func rebuildHostTasks() {
        // Hidden hosts are excluded from view and aren't worth pinging; their
        // tasks are torn down here and re-spawned if the host is restored.
        let activeIDs = Set(hosts.filter { !$0.hidden }.map(\.id))
        // Cancel tasks for removed or now-hidden hosts
        for (id, task) in hostTasks where !activeIDs.contains(id) {
            task.cancel()
            hostTasks.removeValue(forKey: id)
        }
        // Spawn a task for each new visible host
        for host in hosts where !host.hidden && hostTasks[host.id] == nil {
            hostTasks[host.id] = makePollingTask(for: host.id)
        }
    }

    private func makePollingTask(for hostID: UUID) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                let cycleStart = Date()

                // Snapshot the current address (may have been edited) and interval.
                let snapshot: (address: String, interval: Int)? = await MainActor.run {
                    guard let addr = self.hosts.first(where: { $0.id == hostID })?.address else { return nil }
                    let secs = self.preferences?.pingIntervalSeconds ?? 5
                    return (addr, secs)
                }
                guard let snap = snapshot else { return } // host removed

                let intervalMs = Double(max(1, snap.interval)) * 1000.0
                let status = await Pinger.ping(snap.address)

                await MainActor.run {
                    self.queueResult(id: hostID, status: status, slowThresholdMs: intervalMs)
                }

                let target = TimeInterval(max(1, snap.interval))
                let remaining = max(0.05, target - Date().timeIntervalSince(cycleStart))
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
        }
    }

    private func queueResult(id: UUID, status: HostStatus, slowThresholdMs: Double) {
        pendingResults.append((id: id, status: status, slowThresholdMs: slowThresholdMs))
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.flushDelayNs ?? 150_000_000)
            self?.flushPending()
        }
    }

    private func flushPending() {
        flushScheduled = false
        guard !pendingResults.isEmpty else { return }
        let batch = pendingResults
        pendingResults.removeAll(keepingCapacity: true)

        // Status display: latest per host wins.
        var latestStatus: [UUID: HostStatus] = [:]
        for r in batch { latestStatus[r.id] = r.status }
        statusStore.merge(latestStatus)

        // Stats counters: apply every result in order so we never undercount.
        statsStore.applyBatch(batch)
    }

    @discardableResult
    func addHost(address: String, label: String) -> Bool {
        let result = addHosts(entries: [(address, label)])
        return result.added > 0
    }

    @discardableResult
    func addHosts(entries: [(address: String, label: String)]) -> (added: Int, skipped: Int) {
        var working = hosts
        var added = 0
        var skipped = 0
        var newlyAdded: [PingHost] = []

        for entry in entries {
            let address = entry.address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { skipped += 1; continue }
            if working.contains(where: { $0.address.caseInsensitiveCompare(address) == .orderedSame }) {
                skipped += 1
                continue
            }
            let host = PingHost(address: address, label: entry.label.trimmingCharacters(in: .whitespacesAndNewlines))
            working.append(host)
            newlyAdded.append(host)
            added += 1
        }

        if added > 0 {
            hosts = working  // didSet triggers rebuildHostTasks → polling task per new host
            statusStore.seedUnknown(newlyAdded.map(\.id))
        }
        return (added, skipped)
    }

    @discardableResult
    func addHosts(rawLines: [String]) -> (added: Int, skipped: Int) {
        let entries: [(String, String)] = rawLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            if let commaIdx = trimmed.firstIndex(of: ",") {
                let addr = trimmed[..<commaIdx].trimmingCharacters(in: .whitespaces)
                let lbl = trimmed[trimmed.index(after: commaIdx)...].trimmingCharacters(in: .whitespaces)
                return (addr, lbl)
            }
            if let spaceIdx = trimmed.firstIndex(where: { $0.isWhitespace }) {
                let addr = String(trimmed[..<spaceIdx])
                let lbl = trimmed[trimmed.index(after: spaceIdx)...].trimmingCharacters(in: .whitespaces)
                return (addr, lbl)
            }
            return (trimmed, "")
        }
        return addHosts(entries: entries)
    }

    func removeHost(_ host: PingHost) {
        hosts.removeAll { $0.id == host.id }
        statusStore.remove(host.id)
        statsStore.remove(host.id)
    }

    var hasHiddenHosts: Bool { hosts.contains { $0.hidden } }

    var hiddenHostCount: Int { hosts.lazy.filter { $0.hidden }.count }

    /// Hide or unhide the given hosts. Hidden hosts drop out of the list and
    /// stop being pinged until restored. Assigns `hosts` once so the didSet
    /// fires a single save/rebuild.
    func setHidden(_ hidden: Bool, ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var working = hosts
        var changed = false
        for i in working.indices where ids.contains(working[i].id) && working[i].hidden != hidden {
            working[i].hidden = hidden
            changed = true
        }
        if changed { hosts = working }
    }

    /// Unhide every hidden host.
    func restoreAllHidden() {
        guard hasHiddenHosts else { return }
        var working = hosts
        for i in working.indices where working[i].hidden {
            working[i].hidden = false
        }
        hosts = working
    }

    func removeHosts(at offsets: IndexSet) {
        let ids = offsets.map { hosts[$0].id }
        hosts.remove(atOffsets: offsets)
        statusStore.remove(ids)
        statsStore.remove(ids)
    }

    func moveHost(id: UUID, relativeTo targetID: UUID) {
        guard id != targetID,
              let src = hosts.firstIndex(where: { $0.id == id }),
              let dst = hosts.firstIndex(where: { $0.id == targetID }) else { return }
        let item = hosts.remove(at: src)
        hosts.insert(item, at: dst)
    }

    /// Replace the full host list from free-text input (one entry per line,
    /// `address`, `address, label`, or `address label`). Matches existing
    /// hosts by address (case-insensitive) to preserve their UUID, status,
    /// and stats — addresses absent from the new text are removed.
    func replaceHosts(rawLines: [String]) {
        let parsed: [(address: String, label: String)] = rawLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            if let commaIdx = trimmed.firstIndex(of: ",") {
                let addr = trimmed[..<commaIdx].trimmingCharacters(in: .whitespaces)
                let lbl = trimmed[trimmed.index(after: commaIdx)...].trimmingCharacters(in: .whitespaces)
                return (addr, lbl)
            }
            if let spaceIdx = trimmed.firstIndex(where: { $0.isWhitespace }) {
                let addr = String(trimmed[..<spaceIdx])
                let lbl = trimmed[trimmed.index(after: spaceIdx)...].trimmingCharacters(in: .whitespaces)
                return (addr, lbl)
            }
            return (trimmed, "")
        }

        let existingByAddress = Dictionary(grouping: hosts, by: { $0.address.lowercased() })
            .compactMapValues { $0.first }

        var newHosts: [PingHost] = []
        var newlyAdded: [PingHost] = []
        var seen: Set<String> = []

        for entry in parsed {
            let address = entry.address
            guard !address.isEmpty else { continue }
            let key = address.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)

            if let existing = existingByAddress[key] {
                newHosts.append(PingHost(id: existing.id, address: address, label: entry.label, hidden: existing.hidden))
            } else {
                let host = PingHost(address: address, label: entry.label)
                newHosts.append(host)
                newlyAdded.append(host)
            }
        }

        let keptIDs = Set(newHosts.map(\.id))
        let removedIDs = hosts.map(\.id).filter { !keptIDs.contains($0) }

        hosts = newHosts  // didSet triggers rebuildHostTasks
        statusStore.seedUnknown(newlyAdded.map(\.id))
        statusStore.remove(removedIDs)
        statsStore.remove(removedIDs)
    }

    func hostsAsBulkText() -> String {
        hosts.map { host in
            host.label.isEmpty ? host.address : "\(host.address), \(host.label)"
        }.joined(separator: "\n")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = hosts
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            HostStore.save(snapshot)
            self?.saveTask = nil
        }
    }
}
