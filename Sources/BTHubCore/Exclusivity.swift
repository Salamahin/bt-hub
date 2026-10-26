import Foundation

/// Settings every peer shares; the copy with the latest `updatedAt` wins.
public struct SharedSettings: Codable, Equatable, Sendable {
    /// Devices allowed on several peers at once. Every other device is exclusive: one peer at a time.
    public var multipoint: Set<String>
    /// Device address → the peer that should keep it when several hold it.
    public var owners: [String: String]
    public var updatedAt: Double

    public init(multipoint: Set<String> = [], owners: [String: String] = [:], updatedAt: Double = 0) {
        self.multipoint = multipoint
        self.owners = owners
        self.updatedAt = updatedAt
    }

    public func isExclusive(_ address: String) -> Bool {
        !multipoint.contains(address)
    }

    /// The newer of the two copies.
    public func merged(with other: SharedSettings) -> SharedSettings {
        other.updatedAt > updatedAt ? other : self
    }
}

public enum Exclusivity {
    /// The peer that keeps an exclusive device: its owner if the owner holds it, otherwise a stable pick.
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
