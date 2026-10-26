import BTHubCore
import Foundation
import Security

/// Keeps the network key in a file only this user can read.
///
/// It used to live in the keychain, but the app is signed ad hoc on every build, so after each upgrade macOS took it
/// for a different app and asked for the login password before letting it read its own item.
enum KeyStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BT Hub", isDirectory: true)
    }

    private static var file: URL { directory.appendingPathComponent("network-key") }

    static func load() -> String? {
        if let stored = try? String(contentsOf: file, encoding: .utf8) {
            return NetworkKey.normalize(stored)
        }
        // One last keychain read to move a key saved by an older version.
        guard let legacy = LegacyKeychain.load().flatMap(NetworkKey.normalize) else { return nil }
        save(legacy)
        LegacyKeychain.delete()
        return legacy
    }

    static func save(_ key: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.removeItem(at: file)
        manager.createFile(atPath: file.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
    }
}

private enum LegacyKeychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.salamahin.bthub",
        kSecAttrAccount as String: "network-key",
    ]

    static func load() -> String? {
        var item: CFTypeRef?
        var lookup = query
        lookup[kSecReturnData as String] = true
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
