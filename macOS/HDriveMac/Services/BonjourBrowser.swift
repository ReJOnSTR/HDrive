//
//  BonjourBrowser.swift
//  HDriveMac
//

import Foundation

public struct DiscoveredDevice: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let hostName: String
    public let port: Int
    public let addresses: [String]
    
    public var connectionURL: String {
        if let firstIP = addresses.first {
            return "http://\(firstIP):\(port)"
        }
        return "http://\(hostName):\(port)"
    }
}

public final class BonjourBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    public static let shared = BonjourBrowser()
    
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var isSearching: Bool = false
    
    private var browser: NetServiceBrowser?
    private var resolvingServices: [NetService] = []
    
    private override init() {
        super.init()
    }
    
    public func startSearching() {
        stopSearching()
        discoveredDevices.removeAll()
        resolvingServices.removeAll()
        
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_webdav._tcp.", inDomain: "local.")
        isSearching = true
        print("[BonjourBrowser] Yerel ağdaki WebDAV cihazları aranıyor...")
    }
    
    public func stopSearching() {
        browser?.stop()
        browser = nil
        isSearching = false
    }
    
    // MARK: - NetServiceBrowserDelegate
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolvingServices.append(service)
        service.resolve(withTimeout: 5.0)
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        DispatchQueue.main.async {
            self.discoveredDevices.removeAll { $0.name == service.name }
        }
    }
    
    // MARK: - NetServiceDelegate
    public func netServiceDidResolveAddress(_ sender: NetService) {
        var ipAddresses: [String] = []
        
        if let addresses = sender.addresses {
            for data in addresses {
                data.withUnsafeBytes { ptr in
                    let sockaddrPtr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self)
                    if let family = sockaddrPtr?.pointee.sa_family, family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            sockaddrPtr,
                            socklen_t(data.count),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST
                        )
                        let ip = String(cString: hostname)
                        if !ip.isEmpty && ip != "127.0.0.1" {
                            ipAddresses.append(ip)
                        }
                    }
                }
            }
        }
        
        let device = DiscoveredDevice(
            id: sender.name,
            name: sender.name,
            hostName: sender.hostName ?? "\(sender.name).local",
            port: sender.port,
            addresses: ipAddresses
        )
        
        DispatchQueue.main.async {
            if !self.discoveredDevices.contains(where: { $0.id == device.id }) {
                self.discoveredDevices.append(device)
            }
        }
    }
}
