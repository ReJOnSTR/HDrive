import Foundation
import AppKit

// MARK: - Senkronizasyon Durum Kütüğü (Manifest) Modelleri
public struct SyncFileRecord: Codable {
    public let relativePath: String
    public let size: Int64
    public let modificationTime: Double
}

public struct SyncManifest: Codable {
    public var records: [String: SyncFileRecord] = [:]
}

public final class FolderSyncEngine: ObservableObject {
    public static let shared = FolderSyncEngine()
    
    @Published public var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: "HDrive_isSyncEnabled")
            if isSyncEnabled {
                startSyncTimer()
                startLocalWatcher()
                syncNow()
            } else {
                stopSyncTimer()
                stopLocalWatcher()
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
    private var localWatcherSource: DispatchSourceFileSystemObject?
    private var debounceTimer: Timer?
    private var isWatcherSuppressed = false
    
    private var manifestURL: URL {
        return localFolderURL.appendingPathComponent(".hdrive_sync.json")
    }
    
    private var manifest: SyncManifest = SyncManifest()
    
    private init() {
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: "HDrive_isSyncEnabled")
        self.manifest = loadManifest()
        
        if isSyncEnabled {
            startSyncTimer()
            startLocalWatcher()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.syncNow()
            }
        } else {
            self.syncStatus = "Eşitleme Kapalı"
        }
        
        // Ağ bağlantısı geri geldiğinde otomatik eşitle
        NetworkMonitor.shared.onConnectionRestored = { [weak self] in
            guard let self = self, self.isSyncEnabled else { return }
            SyncLogManager.shared.log("İnternet bağlantısı yeniden sağlandı, eşitleme başlatılıyor.")
            self.syncNow()
        }
    }
    
    private func loadManifest() -> SyncManifest {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(SyncManifest.self, from: data) else {
            return SyncManifest()
        }
        return decoded
    }
    
    private func saveManifest() {
        isWatcherSuppressed = true
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
        isWatcherSuppressed = false
    }
    
    public func startSyncTimer() {
        stopSyncTimer()
        // Her 45 saniyede bir arka planda periyodik kontrol
        syncTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            self?.syncNow()
        }
    }
    
    public func stopSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    /// Yerel klasördeki değişiklikleri (yeni dosya, silme, güncelleme) canlı izler
    public func startLocalWatcher() {
        stopLocalWatcher()
        let fd = open(localFolderURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .background)
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self, !self.isWatcherSuppressed, self.isSyncEnabled else { return }
            DispatchQueue.main.async {
                self.debounceTimer?.invalidate()
                self.debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    self?.syncNow()
                }
            }
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        source.resume()
        self.localWatcherSource = source
    }
    
    public func stopLocalWatcher() {
        localWatcherSource?.cancel()
        localWatcherSource = nil
        debounceTimer?.invalidate()
        debounceTimer = nil
    }
    
    /// Klasörü doğrudan macOS Finder'da açar
    public func openLocalFolderInFinder() {
        if !FileManager.default.fileExists(atPath: localFolderURL.path) {
            try? FileManager.default.createDirectory(at: localFolderURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(localFolderURL)
    }
    
    /// Çift yönlü eşitlemeyi başlatır
    public func syncNow() {
        guard isSyncEnabled, !isSyncing else { return }
        guard NetworkMonitor.shared.isConnected else {
            syncStatus = "Çevrimdışı (İnternet Yok)"
            SyncLogManager.shared.log("Eşitleme ertelendi: İnternet bağlantısı yok.")
            return
        }
        guard let config = CloudreveManager.shared.activeServer, !config.serverURL.isEmpty else {
            syncStatus = "Sunucu yapılandırılmadı"
            return
        }
        
        isSyncing = true
        syncStatus = "Çift yönlü kontrol ediliyor..."
        SyncLogManager.shared.log("Senkronizasyon başladı: \(config.name)")
        
        let client = WebDAVClient(config: config)
        syncDirectoryTwoWay(remotePath: "", localDirURL: localFolderURL, client: client) { [weak self] error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                self?.saveManifest()
                if let error = error {
                    self?.syncStatus = "Uyarı: \(error.localizedDescription)"
                    SyncLogManager.shared.log("Eşitleme hatası: \(error.localizedDescription)", isError: true)
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    let timeStr = formatter.string(from: Date())
                    self?.lastSyncDate = Date()
                    self?.syncStatus = "Eşitlendi (\(timeStr))"
                    SyncLogManager.shared.log("Eşitleme başarıyla tamamlandı. (\(timeStr))")
                }
            }
        }
    }
    
    /// Belirtilen dizini çift yönlü (Two-Way) senkronize eder
    private func syncDirectoryTwoWay(remotePath: String, localDirURL: URL, client: WebDAVClient, completion: @escaping (Error?) -> Void) {
        if !FileManager.default.fileExists(atPath: localDirURL.path) {
            try? FileManager.default.createDirectory(at: localDirURL, withIntermediateDirectories: true)
        }
        
        client.listFiles(at: remotePath) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let remoteItems):
                // 1. ADIM: Uzaktan Yerele İndirme ve Yerel Silmelerin Sunucuya Gönderilmesi (Downstream & Local Deletions)
                self.syncDownstream(remoteItems: remoteItems, remotePath: remotePath, localDirURL: localDirURL, client: client) { downError in
                    if let downError = downError {
                        completion(downError)
                        return
                    }
                    // 2. ADIM: Yerelden Uzaka Yükleme ve Uzaktaki Silmelerin Yerele Yansıtılması (Upstream & Remote Deletions)
                    self.syncUpstream(remoteItems: remoteItems, remotePath: remotePath, localDirURL: localDirURL, client: client, completion: completion)
                }
            }
        }
    }
    
    /// Uzaktaki yeni veya değişen dosyaları yerele çeker; yerelde silinmişse sunucudan siler
    private func syncDownstream(remoteItems: [RemoteFileItem], remotePath: String, localDirURL: URL, client: WebDAVClient, completion: @escaping (Error?) -> Void) {
        syncItemsSequentially(items: remoteItems, remotePath: remotePath, localDirURL: localDirURL, client: client, index: 0, completion: completion)
    }
    
    private func syncItemsSequentially(items: [RemoteFileItem], remotePath: String, localDirURL: URL, client: WebDAVClient, index: Int, completion: @escaping (Error?) -> Void) {
        guard index < items.count else {
            completion(nil)
            return
        }
        
        let item = items[index]
        let localTargetURL = localDirURL.appendingPathComponent(item.name)
        let relPath = remotePath.isEmpty ? item.name : "\(remotePath)/\(item.name)"
        
        if item.isDirectory {
            self.syncDirectoryTwoWay(remotePath: relPath, localDirURL: localTargetURL, client: client) { [weak self] _ in
                self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
            }
        } else {
            let localExists = FileManager.default.fileExists(atPath: localTargetURL.path)
            
            if !localExists {
                // Yerelde dosya yok! Daha önce eşitlenip yerelde kullanıcı tarafından silindi mi?
                if manifest.records[relPath] != nil {
                    // Kullanıcı dosyayı Mac'inden silmiş! Sunucudan da sil (Tekrar indirme döngüsünü kır)
                    DispatchQueue.main.async {
                        self.syncStatus = "Sunucudan siliniyor: \(item.name)"
                        SyncLogManager.shared.log("Yerelde silinen dosya sunucudan siliniyor: \(relPath)")
                    }
                    client.delete(at: relPath) { [weak self] _ in
                        self?.manifest.records.removeValue(forKey: relPath)
                        self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
                    }
                    return
                } else {
                    // Manifestte hiç yok: Sunucuda yeni oluşturulmuş dosya, indir
                    downloadRemoteFile(item: item, relPath: relPath, localTargetURL: localTargetURL, client: client) { [weak self] in
                        self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
                    }
                    return
                }
            } else {
                // Yerelde dosya var: Boyut ve güncelleme kontrolü
                let attr = try? FileManager.default.attributesOfItem(atPath: localTargetURL.path)
                let localSize = (attr?[.size] as? Int64) ?? 0
                let localModDate = (attr?[.modificationDate] as? Date) ?? Date.distantPast
                let remoteModDate = item.modificationDate ?? Date.distantPast
                
                if localSize != item.size {
                    // Çakışma Kontrolü: Hem yerel hem sunucu son eşitlemeden sonra değişti mi?
                    if let record = manifest.records[relPath],
                       localModDate.timeIntervalSince1970 > record.modificationTime + 2.0,
                       remoteModDate.timeIntervalSince1970 > record.modificationTime + 2.0 {
                        // ÇAKIŞMA TESPİT EDİLDİ! Yerel dosyayı ezme, sunucudakini 'Çakışan Kopya' olarak kaydet
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd_HHmm"
                        let dateStr = formatter.string(from: Date())
                        let ext = (item.name as NSString).pathExtension
                        let base = (item.name as NSString).deletingPathExtension
                        let extSuffix = ext.isEmpty ? "" : ".\(ext)"
                        let conflictName = "\(base) (Çakışan Kopya \(dateStr))\(extSuffix)"
                        let conflictURL = localDirURL.appendingPathComponent(conflictName)
                        
                        DispatchQueue.main.async {
                            self.syncStatus = "Çakışma: \(conflictName)"
                            SyncLogManager.shared.log("Çakışma tespit edildi: \(item.name) için çakışan kopya oluşturuldu.")
                        }
                        
                        self.isWatcherSuppressed = true
                        client.downloadFile(href: item.href, to: conflictURL, progress: { _ in }) { [weak self] _ in
                            self?.isWatcherSuppressed = false
                            self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
                        }
                        return
                    } else if remoteModDate > localModDate.addingTimeInterval(2.0) {
                        // Sunucudaki dosya daha yeni, güncelle
                        downloadRemoteFile(item: item, relPath: relPath, localTargetURL: localTargetURL, client: client) { [weak self] in
                            self?.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
                        }
                        return
                    }
                }
                
                // Güncellemeye gerek yok, manifesti tazele
                manifest.records[relPath] = SyncFileRecord(
                    relativePath: relPath,
                    size: localSize,
                    modificationTime: localModDate.timeIntervalSince1970
                )
                self.syncItemsSequentially(items: items, remotePath: remotePath, localDirURL: localDirURL, client: client, index: index + 1, completion: completion)
            }
        }
    }
    
    private func downloadRemoteFile(item: RemoteFileItem, relPath: String, localTargetURL: URL, client: WebDAVClient, onDone: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.syncStatus = "İndiriliyor: \(item.name)"
            SyncLogManager.shared.log("Sunucudan indiriliyor: \(item.name)")
        }
        self.isWatcherSuppressed = true
        client.downloadFile(href: item.href, to: localTargetURL, progress: { _ in }) { [weak self] error in
            self?.isWatcherSuppressed = false
            if error == nil {
                let attr = try? FileManager.default.attributesOfItem(atPath: localTargetURL.path)
                let localSize = (attr?[.size] as? Int64) ?? item.size
                let modDate = (attr?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                self?.manifest.records[relPath] = SyncFileRecord(relativePath: relPath, size: localSize, modificationTime: modDate)
            }
            onDone()
        }
    }
    
    /// Yerelde oluşturulmuş veya değiştirilmiş dosyaları uzaktaki sunucuya yükler (Upstream)
    private func syncUpstream(remoteItems: [RemoteFileItem], remotePath: String, localDirURL: URL, client: WebDAVClient, completion: @escaping (Error?) -> Void) {
        guard let localFiles = try? FileManager.default.contentsOfDirectory(at: localDirURL, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
            completion(nil)
            return
        }
        
        let remoteMap = Dictionary(uniqueKeysWithValues: remoteItems.map { ($0.name, $0) })
        var toUpload: [URL] = []
        
        for fileURL in localFiles {
            let name = fileURL.lastPathComponent
            // .hdrive_sync.json veya geçici dosyaları atla
            if name.hasPrefix(".") { continue }
            
            if let remoteItem = remoteMap[name] {
                // Çakışma ve güncelleme kontrolü
                if !remoteItem.isDirectory {
                    if let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let localSize = attr[.size] as? Int64,
                       let localDate = attr[.modificationDate] as? Date,
                       let remoteDate = remoteItem.modificationDate {
                        
                        // Yereldeki dosya daha yeniyse ve boyutu farklıysa yükle
                        if localSize != remoteItem.size && localDate > remoteDate.addingTimeInterval(2.0) {
                            toUpload.append(fileURL)
                        }
                    }
                }
            } else {
                // Uzakta hiç yok, yeni yerel dosya
                toUpload.append(fileURL)
            }
        }
        
        uploadLocalFilesSequentially(files: toUpload, remotePath: remotePath, client: client, index: 0, completion: completion)
    }
    
    private func uploadLocalFilesSequentially(files: [URL], remotePath: String, client: WebDAVClient, index: Int, completion: @escaping (Error?) -> Void) {
        guard index < files.count else {
            completion(nil)
            return
        }
        
        let fileURL = files[index]
        let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let folderOrFileName = fileURL.lastPathComponent
        let relPath = remotePath.isEmpty ? folderOrFileName : "\(remotePath)/\(folderOrFileName)"
        
        if isDir {
            client.createFolder(at: relPath) { [weak self] _ in
                self?.uploadLocalFilesSequentially(files: files, remotePath: remotePath, client: client, index: index + 1, completion: completion)
            }
        } else {
            DispatchQueue.main.async {
                self.syncStatus = "Yükleniyor: \(fileURL.lastPathComponent)"
                SyncLogManager.shared.log("Sunucuya yükleniyor: \(fileURL.lastPathComponent)")
            }
            client.uploadFile(localFileURL: fileURL, toRemotePath: relPath) { [weak self] error in
                if let error = error {
                    SyncLogManager.shared.log("Yükleme uyarısı: \(error.localizedDescription)", isError: true)
                } else {
                    let attr = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let localSize = (attr?[.size] as? Int64) ?? 0
                    let modDate = (attr?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                    self?.manifest.records[relPath] = SyncFileRecord(relativePath: relPath, size: localSize, modificationTime: modDate)
                }
                self?.uploadLocalFilesSequentially(files: files, remotePath: remotePath, client: client, index: index + 1, completion: completion)
            }
        }
    }
}

