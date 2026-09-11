//
//  CloudreveManager.swift
//  HDriveMac
//

import Foundation

public final class CloudreveManager: ObservableObject {
    public static let shared = CloudreveManager()
    
    private let userDefaultsKey = "HDrive_SavedCloudreveServers"
    
    @Published public var servers: [CloudreveServerConfig] = []
    @Published public var activeServer: CloudreveServerConfig? {
        didSet {
            if let id = activeServer?.id {
                UserDefaults.standard.set(id.uuidString, forKey: "HDrive_ActiveServerID")
            }
        }
    }
    
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
            if let activeIDStr = UserDefaults.standard.string(forKey: "HDrive_ActiveServerID"),
               let uuid = UUID(uuidString: activeIDStr),
               let found = servers.first(where: { $0.id == uuid }) {
                activeServer = found
            } else {
                activeServer = servers.first
            }
        }
    }
    
    public func saveServer(_ server: CloudreveServerConfig) {
        if !server.password.isEmpty {
            KeychainHelper.shared.save(password: server.password, for: server.id.uuidString)
        }
        
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        activeServer = server
        persist()
    }
    
    public func deleteServer(_ server: CloudreveServerConfig) {
        KeychainHelper.shared.delete(account: server.id.uuidString)
        servers.removeAll { $0.id == server.id }
        if activeServer?.id == server.id {
            activeServer = servers.first
        }
        persist()
    }
    
    public func setActiveServer(_ server: CloudreveServerConfig) {
        activeServer = server
    }
    
    private func persist() {
        // Düz metin parola asla UserDefaults'a yazılmaz; Keychain kullanılır!
        let sanitized = servers.map { server -> CloudreveServerConfig in
            var s = server
            s.password = ""
            return s
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    private func loadServers() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode([CloudreveServerConfig].self, from: data) {
            self.servers = saved.map { server in
                var s = server
                // Keychain'den güvenli parolayı çek
                if let pass = KeychainHelper.shared.get(account: server.id.uuidString) {
                    s.password = pass
                } else if !server.password.isEmpty {
                    // Eski sürümden kalan şifreyi Keychain'e taşı ve güvenli hale getir
                    KeychainHelper.shared.save(password: server.password, for: server.id.uuidString)
                    s.password = server.password
                }
                return s
            }
        }
    }
}
