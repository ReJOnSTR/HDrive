//
//  CloudreveManager.swift
//  HDriveMac
//

import Foundation

public final class CloudreveManager: ObservableObject {
    public static let shared = CloudreveManager()
    
    private let userDefaultsKey = "HDrive_SavedCloudreveServers"
    
    @Published public var servers: [CloudreveServerConfig] = []
    @Published public var activeServer: CloudreveServerConfig?
    
    private init() {
        loadServers()
        if servers.isEmpty {
            // Varsayılan Cloudreve şablonu
            let defaultServer = CloudreveServerConfig(
                name: "Cloudreve Sunucum",
                serverURL: "https://your-cloudreve-domain.com/dav",
                username: "admin@example.com",
                password: ""
            )
            servers.append(defaultServer)
            activeServer = defaultServer
        } else {
            activeServer = servers.first
        }
    }
    
    public func saveServer(_ server: CloudreveServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        activeServer = server
        persist()
    }
    
    public func deleteServer(_ server: CloudreveServerConfig) {
        servers.removeAll { $0.id == server.id }
        if activeServer?.id == server.id {
            activeServer = servers.first
        }
        persist()
    }
    
    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([CloudreveServerConfig].self, from: data) {
            self.servers = saved
        }
    }
}
