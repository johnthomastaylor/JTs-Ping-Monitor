import Foundation

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var statuses: [UUID: HostStatus] = [:]

    func set(_ status: HostStatus, for id: UUID) {
        statuses[id] = status
    }

    func merge(_ updates: [UUID: HostStatus]) {
        var working = statuses
        for (id, status) in updates { working[id] = status }
        statuses = working
    }

    func remove(_ id: UUID) {
        statuses.removeValue(forKey: id)
    }

    func remove(_ ids: [UUID]) {
        var working = statuses
        for id in ids { working.removeValue(forKey: id) }
        statuses = working
    }

    func seedUnknown(_ ids: [UUID]) {
        var working = statuses
        var changed = false
        for id in ids where working[id] == nil {
            working[id] = .unknown
            changed = true
        }
        if changed { statuses = working }
    }
}
