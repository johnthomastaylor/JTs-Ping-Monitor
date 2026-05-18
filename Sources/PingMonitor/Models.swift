import Foundation

struct PingHost: Identifiable, Codable, Hashable {
    let id: UUID
    var address: String
    var label: String

    init(id: UUID = UUID(), address: String, label: String = "") {
        self.id = id
        self.address = address
        self.label = label
    }

    var displayName: String {
        label.isEmpty ? address : label
    }
}

enum HostStatus: Equatable {
    case unknown
    case up(latencyMs: Double)
    case down

    var isUp: Bool {
        if case .up = self { return true }
        return false
    }
}
