import Foundation

/// Settings every peer shares; the copy with the latest `updatedAt` wins.
public struct SharedSettings: Codable, Equatable, Sendable {
    /// Device address → the peer that should keep it when several hold it.
    public var owners: [String: String]
    public var updatedAt: Double

    public init(owners: [String: String] = [:], updatedAt: Double = 0) {
        self.owners = owners
        self.updatedAt = updatedAt
    }

    /// The newer of the two copies.
    public func merged(with other: SharedSettings) -> SharedSettings {
        other.updatedAt > updatedAt ? other : self
    }
}

/// A device stays on one peer at a time; these pick which peer keeps it.
public enum Exclusivity {
    /// The peer that keeps the device: its owner if the owner holds it, otherwise a stable pick.
    public static func winner(holders: [String], owner: String?) -> String? {
        if let owner, holders.contains(owner) { return owner }
        return holders.min()
    }

    /// The peers that must let go so only the winner keeps the device.
    public static func losers(holders: [String], owner: String?) -> [String] {
        guard let winner = winner(holders: holders, owner: owner) else { return [] }
        return holders.filter { $0 != winner }
    }
}
