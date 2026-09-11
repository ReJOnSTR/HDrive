//
//  NetworkMonitor.swift
//  HDrive
//

import Foundation
import Network
import Combine

public final class NetworkMonitor: ObservableObject {
    public static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.hdrive.networkmonitor")
    
    @Published public var isConnected: Bool = true
    @Published public var isExpensive: Bool = false
    @Published public var connectionType: String = "Wi-Fi / Ethernet"
    
    public var onConnectionRestored: (() -> Void)?
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let previous = self.isConnected
                self.isConnected = (path.status == .satisfied)
                self.isExpensive = path.isExpensive
                
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = "Wi-Fi"
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = "Hücresel"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = "Ethernet"
                } else {
                    self.connectionType = "Bilinmeyen"
                }
                
                // Bağlantı geri geldiğinde tetikle
                if !previous && self.isConnected {
                    self.onConnectionRestored?()
                }
            }
        }
        monitor.start(queue: queue)
    }
}
