import Foundation

struct DiscoveredServer: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let hostname: String
    let port: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(hostname)
    }

    static func == (lhs: DiscoveredServer, rhs: DiscoveredServer) -> Bool {
        lhs.name == rhs.name && lhs.hostname == rhs.hostname
    }
}

class SMBNetworkScanner: NSObject, ObservableObject {
    @Published var discoveredServers: [DiscoveredServer] = []
    @Published var isScanning = false
    @Published var scanError: String?

    private var netServiceBrowser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolvedCount = 0
    private var totalToResolve = 0

    func startScan() {
        stopScan()

        discoveredServers = []
        services = []
        isScanning = true
        scanError = nil
        resolvedCount = 0
        totalToResolve = 0

        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self

        // Search for SMB services via Bonjour
        netServiceBrowser?.searchForServices(ofType: "_smb._tcp.", inDomain: "local.")

        // Stop scanning after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finishScan()
        }
    }

    func stopScan() {
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        services.forEach { $0.stop() }
        services = []
        isScanning = false
    }

    private func finishScan() {
        netServiceBrowser?.stop()
        isScanning = false

        if discoveredServers.isEmpty && scanError == nil {
            scanError = "Geen servers gevonden"
        }
    }

    private func resolveService(_ service: NetService) {
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
}

// MARK: - NetServiceBrowserDelegate
extension SMBNetworkScanner: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("Starting SMB scan...")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("Found service: \(service.name)")
        services.append(service)
        totalToResolve += 1
        resolveService(service)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("Search error: \(errorDict)")
        DispatchQueue.main.async {
            self.scanError = "Scan mislukt"
            self.isScanning = false
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("Search stopped")
    }
}

// MARK: - NetServiceDelegate
extension SMBNetworkScanner: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        resolvedCount += 1

        var hostname: String?

        // Get hostname from addresses
        if let addresses = sender.addresses {
            for addressData in addresses {
                addressData.withUnsafeBytes { pointer in
                    let sockaddrPtr = pointer.bindMemory(to: sockaddr.self)
                    if let baseAddress = sockaddrPtr.baseAddress {
                        if baseAddress.pointee.sa_family == sa_family_t(AF_INET) {
                            // IPv4
                            var addr = baseAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                            inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                            hostname = String(cString: buffer)
                        }
                    }
                }
                if hostname != nil { break }
            }
        }

        // Fallback to hostName property
        if hostname == nil {
            hostname = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        if let host = hostname {
            let server = DiscoveredServer(
                name: sender.name,
                hostname: host,
                port: sender.port
            )

            DispatchQueue.main.async {
                if !self.discoveredServers.contains(server) {
                    self.discoveredServers.append(server)
                }
            }
        }

        checkScanComplete()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Could not resolve: \(sender.name)")
        resolvedCount += 1
        checkScanComplete()
    }

    private func checkScanComplete() {
        if resolvedCount >= totalToResolve && !isScanning {
            // All services resolved
        }
    }
}
