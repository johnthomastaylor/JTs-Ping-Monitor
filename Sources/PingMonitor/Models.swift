import Foundation

struct PingHost: Identifiable, Codable, Hashable {
    let id: UUID
    var address: String
    var label: String
    var hidden: Bool

    init(id: UUID = UUID(), address: String, label: String = "", hidden: Bool = false) {
        self.id = id
        self.address = address
        self.label = label
        self.hidden = hidden
    }

    // Custom decode so host files written before `hidden` existed still load
    // (missing key → visible). Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        address = try c.decode(String.self, forKey: .address)
        label = try c.decode(String.self, forKey: .label)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
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
