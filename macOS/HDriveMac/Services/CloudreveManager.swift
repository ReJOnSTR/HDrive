import Foundation
import Combine

public final class CloudreveManager: ObservableObject {
    public static let shared = CloudreveManager()
    private let defaults: UserDefaults
    private let saveSecret: (String, String) -> Bool
    private let readSecret: (String) -> String?
    private let deleteSecret: (String) -> Bool
    private var loadFailed = false
    private let userDefaultsKey = "HDrive_SavedCloudreveServers"
    @Published public var servers: [CloudreveServerConfig] = []
    @Published public var lastError: String?
    @Published public var activeServer: CloudreveServerConfig? {
        didSet {
            if let server = activeServer, server.isConnected {
                defaults.set(server.id.uuidString, forKey: "HDrive_ActiveServerID")
            } else {
                defaults.removeObject(forKey: "HDrive_ActiveServerID")
            }
        }
    }

    internal init(defaults: UserDefaults = .standard,
                  saveSecret: @escaping (String, String) -> Bool = { KeychainHelper.shared.save(password: $1, for: $0) },
                  readSecret: @escaping (String) -> String? = { KeychainHelper.shared.get(account: $0) },
                  deleteSecret: @escaping (String) -> Bool = { KeychainHelper.shared.delete(account: $0) }) {
        self.defaults = defaults
        self.saveSecret = saveSecret
        self.readSecret = readSecret
        self.deleteSecret = deleteSecret
        let activeID = defaults.string(forKey: "HDrive_ActiveServerID")
        loadServers()
        activeServer = servers.first { $0.id.uuidString == activeID && $0.isConnected }
            ?? servers.first { $0.isConnected }
    }

    private func storeSecrets(_ server: CloudreveServerConfig) -> Bool {
        for (suffix, value) in [("", server.password), ("_rt", server.refreshToken), ("_cs", server.clientSecret)] {
            if !value.isEmpty && readSecret(server.id.uuidString + suffix) != value && !saveSecret(server.id.uuidString + suffix, value) {
                lastError = "Kimlik bilgileri güvenli kasaya kaydedilemedi. Mevcut hesap kaydı korundu."
                return false
            }
        }
        return true
    }

    @discardableResult public func saveServer(_ server: CloudreveServerConfig) -> Bool {
        guard storeSecrets(server) else { return false }
        let oldServers = servers, oldActive = activeServer
        var connected = server
        connected.isConnected = true
        if let index = servers.firstIndex(where: { $0.id == server.id }) { servers[index] = connected }
        else { servers.append(connected) }
        activeServer = connected
        guard persist() else { servers = oldServers; activeServer = oldActive; return false }
        return true
    }

    @discardableResult public func updateCredentials(_ server: CloudreveServerConfig) -> Bool {
        guard let index = servers.firstIndex(where: { $0.id == server.id }), servers[index].isConnected,
              servers[index].serverURL == server.serverURL,
              servers[index].storageProtocol == server.storageProtocol,
              servers[index].username == server.username,
              servers[index].bucketName == server.bucketName,
              servers[index].smbShare == server.smbShare else { return false }
        guard storeSecrets(server) else { return false }
        let old = servers[index]
        servers[index].password = server.password
        servers[index].refreshToken = server.refreshToken
        servers[index].clientSecret = server.clientSecret
        if !persist() { servers[index] = old; return false }
        if activeServer?.id == server.id { activeServer = servers[index] }
        return true
    }

    public func deleteServer(_ server: CloudreveServerConfig) {
        let oldServers = servers, oldActive = activeServer
        servers.removeAll { $0.id == server.id }
        if activeServer?.id == server.id { activeServer = servers.first { $0.isConnected } }
        guard persist() else { servers = oldServers; activeServer = oldActive; return }
        for suffix in ["", "_rt", "_cs"] {
            if !deleteSecret(server.id.uuidString + suffix) { lastError = "Hesap silindi ancak güvenli kasa temizlenemedi." }
        }
    }

    public func setActiveServer(_ server: CloudreveServerConfig) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        let oldServers = servers, oldActive = activeServer
        servers[index].isConnected = true
        activeServer = servers[index]
        if !persist() { servers = oldServers; activeServer = oldActive }
    }

    public func connectServer(_ server: CloudreveServerConfig) { setActiveServer(server) }

    public func disconnectServer(_ server: CloudreveServerConfig) {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        let oldServers = servers, oldActive = activeServer
        servers[index].isConnected = false
        if activeServer?.id == server.id { activeServer = servers.first { $0.isConnected } }
        if !persist() { servers = oldServers; activeServer = oldActive }
    }

    public func disconnectActiveServer() {
        if let active = activeServer { disconnectServer(active) }
    }

    @discardableResult private func persist() -> Bool {
        guard !loadFailed else { lastError = "Hesap kaydı okunamadığı için üzerine yazılmadı. Kaydı veya yedeğini kurtarın."; return false }
        guard servers.allSatisfy({ storeSecrets($0) }) else { return false }
        let sanitized = servers.map { server -> CloudreveServerConfig in
            var safe = server
            safe.password = ""
            safe.refreshToken = ""
            safe.clientSecret = ""
            return safe
        }
        do {
            let data = try JSONEncoder().encode(sanitized)
            defaults.set(data, forKey: userDefaultsKey)
            defaults.set(data, forKey: userDefaultsKey + "_backup")
            return true
        } catch {
            lastError = "Hesaplar kaydedilemedi: " + error.localizedDescription
            return false
        }
    }

    private func loadServers() {
        guard let data = defaults.data(forKey: userDefaultsKey) else { return }
        do {
            let saved: [CloudreveServerConfig]
            do { saved = try JSONDecoder().decode([CloudreveServerConfig].self, from: data) }
            catch {
                guard let backup = defaults.data(forKey: userDefaultsKey + "_backup") else { throw error }
                saved = try JSONDecoder().decode([CloudreveServerConfig].self, from: backup)
                lastError = "Hesap kaydı yedekten kurtarıldı."
            }
            servers = saved.map { server in
                var restored = server
                restored.password = readSecret(server.id.uuidString) ?? server.password
                restored.refreshToken = readSecret(server.id.uuidString + "_rt") ?? server.refreshToken
                restored.clientSecret = readSecret(server.id.uuidString + "_cs") ?? server.clientSecret
                return restored
            }
            persist() // Migrate old plaintext values only after secure storage succeeds.
        } catch {
            loadFailed = true
            lastError = "Hesap kaydı okunamadı; dosya korundu: " + error.localizedDescription
        }
    }
}
