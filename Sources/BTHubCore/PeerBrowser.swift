import Foundation
import Network

/// Finds other BT Hub instances on the local network over Bonjour.
public final class PeerBrowser: @unchecked Sendable {
    public struct Found: Hashable, Sendable {
        public let id: String
        public let name: String
        public let endpoint: NWEndpoint
    }

    private let browser: NWBrowser
    private let queue = DispatchQueue(label: "bthub.browser")

    /// `onChange` runs on the main queue with every peer except `ownID`.
    public init(ownID: String, onChange: @escaping @MainActor ([Found]) -> Void) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { results, _ in
            var byID: [String: Found] = [:]
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint,
                      case let .bonjour(txt) = result.metadata,
                      let id = txt["id"], id != ownID
                else { continue }
                // The same peer shows up once per interface; any of them will do.
                byID[id] = Found(id: id, name: name, endpoint: result.endpoint)
            }
            let found = byID.values.sorted { $0.name < $1.name }
            DispatchQueue.main.async { MainActor.assumeIsolated { onChange(found) } }
        }
    }

    public func start() {
        browser.start(queue: queue)
    }

    public func stop() {
        browser.cancel()
    }
}
