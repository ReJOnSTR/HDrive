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
            } else {
                UserDefaults.standard.removeObject(forKey: "HDrive_ActiveServerID")
            }
        }
    }
    
    private init() {
        loadServers()
        if let activeIDStr = UserDefaults.standard.string(forKey: "HDrive_ActiveServerID"),
           let uuid = UUID(uuidString: activeIDStr),
           let found = servers.first(where: { $0.id == uuid && $0.isConnected }) {
            activeServer = found
        } else {
            activeServer = servers.first(where: { $0.isConnected }) ?? servers.first
        }
    }
    
    public func saveServer(_ server: CloudreveServerConfig) {
        var s = server
        s.isConnected = true
        if !s.password.isEmpty {
            KeychainHelper.shared.save(password: s.password, for: s.id.uuidString)
        }
        if !s.refreshToken.isEmpty {
            KeychainHelper.shared.save(password: s.refreshToken, for: "\(s.id.uuidString)_rt")
        }
        
        if let index = servers.firstIndex(where: { $0.id == s.id }) {
            servers[index] = s
        } else {
            servers.append(s)
        }
        activeServer = s
        persist()
    }
    
    public func deleteServer(_ server: CloudreveServerConfig) {
        KeychainHelper.shared.delete(account: server.id.uuidString)
        KeychainHelper.shared.delete(account: "\(server.id.uuidString)_rt")
        servers.removeAll { $0.id == server.id }
        if activeServer?.id == server.id {
            activeServer = servers.first(where: { $0.isConnected })
        }
        persist()
    }
    
    public func setActiveServer(_ server: CloudreveServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].isConnected = true
            activeServer = servers[index]
            persist()
        } else {
            activeServer = server
        }
    }
    
    public func connectServer(_ server: CloudreveServerConfig) {
        setActiveServer(server)
    }
    
    public func disconnectServer(_ server: CloudreveServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].isConnected = false
            if activeServer?.id == server.id {
                activeServer = servers.first(where: { $0.isConnected && $0.id != server.id })
            }
            persist()
        }
    }
    
    public func disconnectActiveServer() {
        if let act = activeServer {
            disconnectServer(act)
        } else {
            activeServer = nil
        }
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
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let saved = try? JSONDecoder().decode([CloudreveServerConfig].self, from: data) else {
            return
        }
        
        var valid: [CloudreveServerConfig] = []
        for server in saved {
            if server.serverURL.contains("your-cloudreve-domain.com") {
                continue
            }
            let trimmed = server.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let proto = server.storageProtocol
            if !trimmed.isEmpty || proto == .googleDrive || proto == .oneDrive {
                valid.append(server)
            }
        }

        self.servers = valid.map { server in
            var s = server
            // Keychain'den güvenli parolayı / tokenı çek
            if let pass = KeychainHelper.shared.get(account: server.id.uuidString) {
                s.password = pass
            } else if !server.password.isEmpty {
                KeychainHelper.shared.save(password: server.password, for: server.id.uuidString)
                s.password = server.password
            }
            
            // Refresh token'ı Keychain'den yükle
            if let rt = KeychainHelper.shared.get(account: "\(server.id.uuidString)_rt") {
                s.refreshToken = rt
            }
            return s
        }
    }
}
