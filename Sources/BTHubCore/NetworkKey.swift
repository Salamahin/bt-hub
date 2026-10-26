import CryptoKit
import Foundation
import Network
import Security

/// The shared secret every BT Hub on the user's network knows.
///
/// Peers authenticate and encrypt with TLS 1.2 pre-shared-key: a peer without the key cannot finish the
/// handshake, so it can neither read the traffic nor send commands.
public enum NetworkKey {
    // Crockford-like alphabet: no 0/O or 1/I, so the key survives being read aloud or retyped.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    /// 20 symbols × 5 bits = 100 bits of entropy.
    public static let length = 20

    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return format(String(bytes.map { alphabet[Int($0 & 31)] }))
    }

    /// Accepts the key with any case, spacing or dashes; returns the canonical grouped form, or nil if it is not a key.
    public static func normalize(_ input: String) -> String? {
        let symbols = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard symbols.count == length, symbols.allSatisfy(alphabet.contains) else { return nil }
        return format(symbols)
    }

    /// A link that hands the key to another Mac: `bthub://key?k=…`, opened by BT Hub there.
    public static func shareURL(for key: String) -> URL {
        var components = URLComponents()
        components.scheme = "bthub"
        components.host = "key"
        components.queryItems = [URLQueryItem(name: "k", value: key)]
        return components.url!
    }

    public static func key(from url: URL) -> String? {
        guard url.scheme == "bthub", url.host == "key",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "k" })?.value
        else { return nil }
        return normalize(value)
    }

    /// Accepts either the key itself or a pasted key link.
    public static func parse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "bthub" { return key(from: url) }
        return normalize(trimmed)
    }

    /// Fresh parameters for one listener or connection; NWParameters must not be shared between them.
    public static func parameters(key: String) -> NWParameters {
        let symbols = Data(key.filter { $0 != "-" }.utf8)
        let psk = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: symbols),
            info: Data("bthub/psk/v1".utf8),
            outputByteCount: 32
        )

        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let pskData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("bthub".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, pskData as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        // PSK cipher suites exist only in TLS 1.2.
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 5
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        return parameters
    }

    private static func format(_ symbols: String) -> String {
        stride(from: 0, to: symbols.count, by: 5).map { offset -> String in
            let start = symbols.index(symbols.startIndex, offsetBy: offset)
            return String(symbols[start..<symbols.index(start, offsetBy: 5)])
        }.joined(separator: "-")
    }
}
