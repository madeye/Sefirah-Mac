import Foundation
import Network

public final class BonjourDiscovery: @unchecked Sendable {
    public static let serviceType = "_sefirah._udp"

    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue: DispatchQueue
    private let localDeviceId: String

    public var onResolved: ((String, String, String, Int) -> Void)?

    public init(localDeviceId: String, queue: DispatchQueue) {
        self.localDeviceId = localDeviceId
        self.queue = queue
    }

    public func advertise(deviceId: String, deviceName: String, serverPort: Int) throws {
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        var txt = NWTXTRecord()
        txt["deviceName"] = deviceName
        txt["serverPort"] = String(serverPort)
        // Ephemeral UDP port: SRV is ignored when TXT `serverPort` is present.
        let listener = try NWListener(using: parameters)
        listener.service = NWListener.Service(
            name: deviceId,
            type: Self.serviceType,
            domain: "local.",
            txtRecord: txt
        )
        listener.stateUpdateHandler = { _ in }
        listener.newConnectionHandler = { connection in
            connection.cancel()
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func startBrowsing() {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: "local."),
            using: .udp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                self.resolve(result)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
    }

    private func resolve(_ result: NWBrowser.Result) {
        let txt: NWTXTRecord? = {
            if case .bonjour(let record) = result.metadata { return record }
            return nil
        }()
        let deviceName = txt?["deviceName"] ?? ""
        let advertisedPort = txt?["serverPort"].flatMap(Int.init)

        let deviceId: String
        if case .service(let name, _, _, _) = result.endpoint {
            deviceId = name
        } else {
            return
        }
        guard deviceId != localDeviceId else { return }

        let connection = NWConnection(to: result.endpoint, using: .udp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .ready = state {
                if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                    let finalPort = advertisedPort ?? Int(port.rawValue)
                    self.onResolved?(deviceId, deviceName, canonicalHost("\(host)"), finalPort)
                }
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }
}
