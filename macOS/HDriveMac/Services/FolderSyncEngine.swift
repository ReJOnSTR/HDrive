//
//  FolderSyncEngine.swift
//  HDriveMac - OneDrive & Google Drive Tarzı Yerel Klasör Senkronizasyonu
//

import Foundation
import AppKit

public final class FolderSyncEngine: ObservableObject {
    public static let shared = FolderSyncEngine()
    
    @Published public var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: "HDrive_isSyncEnabled")
            if isSyncEnabled {
                startSyncTimer()
                syncNow()
            } else {
                stopSyncTimer()
                syncStatus = "Eşitleme Duraklatıldı"
            }
        }
    }
    
    @Published public var isSyncing: Bool = false
    @Published public var syncStatus: String = "Hazır"
    @Published public var lastSyncDate: Date? = nil
    
    /// Mac üzerindeki yerel eşitleme klasörü: ~/HDrive - Cloudreve
    public let localFolderURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home.appendingPathComponent("HDrive - Cloudreve", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }()
    
    private var syncTimer: Timer?
    
    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: "HDrive_isSyncEnabled")
        if isSyncEnabled {
            startSyncTimer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.syncNow()
            }
        } else {
            self.syncStatus = "Eşitleme Kapalı"
        }
    }
    
    public func startSyncTimer() {
        stopSyncTimer()
        // Her 60 saniyede bir arka planda otomatik kontrol et
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.syncNow()
        }
    }
    
    public func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    /// Klasörü doğrudan macOS Finder'da açar
    public func openLocalFolderInFinder() {
        if !FileManager.default.fileExists(atPath: localFolderURL.path) {
            try? FileManager.default.createDirectory(at: localFolderURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(localFolderURL)
    }
    
    /// Manuel veya otomatik olarak eşitlemeyi tetikler
    public func syncNow() {
        guard isSyncEnabled, !isSyncing else { return }
        guard let config = CloudreveManager.shared.activeServer, !config.serverURL.isEmpty else {
            syncStatus = "Sunucu yapılandırılmadı"
            return
        }
        
        isSyncing = true
        syncStatus = "Klasör yapısı kontrol ediliyor..."
        
        let client = WebDAVClient(config: config)
        syncDirectory(remotePath: "", localDirURL: localFolderURL, client: client) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let error = error {
                    self?.syncStatus = "Eşitleme Uyarısı: \(error.localizedDescription)"
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    let timeStr = formatter.string(from: Date())
                    self?.lastSyncDate = Date()
                    self?.syncStatus = "Eşitlendi (\(timeStr))"
                }
            }
        }
    }
    
    /// Belirtilen klasörü uzaktan yerele sıralı ve güvenli şekilde senkronize eder
    private func syncDirectory(remotePath: String, localDirURL: URL, client: WebDAVClient, completion: @escaping (Error?) -> Void) {
        if !FileManager.default.fileExists(atPath: localDirURL.path) {
            try? FileManager.default.createDirectory(at: localDirURL, withIntermediateDirectories: true)
        }
        
        client.listFiles(at: remotePath) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let items):
                self.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: 0, completion: completion)
            }
        }
    }
    
    /// Ögeleri sırayla (tek tek) indirerek ağ tıkanıklığını ve zaman aşımını önler
    private func syncItemsSequentially(items: [RemoteFileItem], remotePath: String, localDirURL: URL, client: WebDAVClient, index: Int, completion: @escaping (Error?) -> Void) {
        guard index < items.count else {
            completion(nil)
            return
        }
        
        let item = items[index]
        let localTargetURL = localDirURL.appendingPathComponent(item.name)
        
        if item.isDirectory {
            let subRemote = remotePath.isEmpty ? item.name : "\(remotePath)/\(item.name)"
            self.syncDirectory(remotePath: subRemote, localDirURL: localTargetURL, client: client) { [weak self] _ in
                // Bir sonraki ögeye geç
                self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
            }
        } else {
            // Dosya yerelde yoksa veya boyutu farklıysa indir
            let shouldDownload: Bool
            if let attr = try? FileManager.default.attributesOfItem(atPath: localTargetURL.path),
               let localSize = attr[.size] as? Int64 {
                shouldDownload = (localSize != item.size)
            } else {
                shouldDownload = true
            }
            
            if shouldDownload {
                DispatchQueue.main.async {
                    self.syncStatus = "İndiriliyor: \(item.name)"
                }
                client.downloadFile(href: item.href, to: localTargetURL, progress: { _ in }) { [weak self] _ in
                    // İndirme bittiğinde bir sonrakine geç
                    self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
                }
            } else {
                // Dosya zaten güncel, hemen bir sonrakine geç
                self.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
            }
        }
    }
}
