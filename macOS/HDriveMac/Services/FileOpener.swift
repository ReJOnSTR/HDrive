//
//  FileOpener.swift
//  HDriveMac - Dosyaları Mac'in Yerel Programlarıyla Açıcı
//

import Foundation
import AppKit

public final class FileOpener: ObservableObject {
    public static let shared = FileOpener()
    
    @Published public var openingFile: String? = nil
    @Published public var downloadProgress: Double = 0.0
    
    public let cacheDir: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("HDriveFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private init() {}
    
    /// Google Docs, Sheets vb. için uygun yerel dosya adını (Word, Excel, PowerPoint) belirler
    public func resolveLocalFileName(for file: RemoteFileItem, client: WebDAVClient) -> String {
        var baseName = file.name
        let ext = (baseName as NSString).pathExtension.lowercased()
        
        if client.config.storageProtocol == .googleDrive && ext.isEmpty {
            let mime = file.contentType ?? ""
            if mime == "application/vnd.google-apps.document" {
                baseName += ".docx"
            } else if mime == "application/vnd.google-apps.spreadsheet" {
                baseName += ".xlsx"
            } else if mime == "application/vnd.google-apps.presentation" {
                baseName += ".pptx"
            } else if mime == "application/vnd.google-apps.drawing" {
                baseName += ".png"
            } else if mime.hasPrefix("application/vnd.google-apps.") {
                baseName += ".pdf"
            }
        }
        return baseName
    }
    
    public func openFileNatively(file: RemoteFileItem, client: WebDAVClient, completion: @escaping (Bool, String?) -> Void) {
        let localFileName = resolveLocalFileName(for: file, client: client)
        
        let localFile: URL
        do {
            _ = try WorkingCache.trim(to: Int64(UserDefaults.standard.object(forKey: "HDriveCacheLimitMB") == nil ? 1024 : max(256, UserDefaults.standard.integer(forKey: "HDriveCacheLimitMB"))) * 1024 * 1024)
            let directory = cacheDir.appendingPathComponent(OfflineStore.identity(client.config)).appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            localFile = directory.appendingPathComponent(try LocalFileOperations.validName(localFileName))
            try WorkingCache.protect(localFile)
        } catch { completion(false, error.localizedDescription); return }

        // 5. Yerel kopya yoksa arka planda hızlıca indir ve varsayılan Mac uygulamasıyla aç
        DispatchQueue.main.async {
            self.openingFile = file.name
            self.downloadProgress = 0.05
        }
        
        let activeClient = client
        activeClient.downloadFile(href: file.href, to: localFile, progress: { progress in
            DispatchQueue.main.async {
                self.downloadProgress = progress
            }
        }) { [activeClient] error in
            DispatchQueue.main.async {
                self.openingFile = nil
                self.downloadProgress = 0.0
                
                if let error = error {
                    completion(false, "Dosya açılamadı: \(error.localizedDescription)")
                    return
                }
                
                // Mac'in varsayılan yerel programıyla aç (Excel, Word, Preview, VLC vb.)
                let success = NSWorkspace.shared.open(localFile)
                if success {
                    self.watchForLiveEdits(localFile: localFile, remoteHref: file.href, client: activeClient)
                    completion(true, nil)
                } else {
                    // Özel bir varsayılan program tanımlı değilse Finder'da dosyayı seçerek göster
                    NSWorkspace.shared.activateFileViewerSelecting([localFile])
                    self.watchForLiveEdits(localFile: localFile, remoteHref: file.href, client: activeClient)
                    completion(true, nil)
                }
            }
        }
    }

    // MARK: - Canlı Dosya İzleyici (In-Place Edit Auto-Sync)

    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var lastModifiedDates: [String: Date] = [:]

    private func watchForLiveEdits(localFile: URL, remoteHref: String, client: WebDAVClient) {
        let path = localFile.path
        if let existing = fileWatchers[path] {
            existing.cancel()
        }
        
        lastModifiedDates[path] = (try? localFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: [.write, .extend, .attrib], queue: DispatchQueue.global(qos: .utility))
        
        var debounceWorkItem: DispatchWorkItem?
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                let currentModDate = (try? localFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if let lastDate = self.lastModifiedDates[path], currentModDate <= lastDate {
                    return
                }
                guard let owner = CloudreveManager.shared.servers.first(where: { $0.id == client.config.id && $0.isConnected }), OfflineStore.identity(owner) == OfflineStore.identity(client.config) else {
                    SyncLogManager.shared.log("Düzenleme yüklenemedi: hesabın bağlantısı kesildi.", isError: true); return
                }
                let uploadClient = WebDAVClient(config: owner)
                uploadClient.replaceFile(href: remoteHref, localURL: localFile) { err in
                    DispatchQueue.main.async {
                        if let err = err { SyncLogManager.shared.log("Düzenleme yüklenemedi: " + err.localizedDescription, isError: true) }
                        else { self.lastModifiedDates[path] = currentModDate; SyncLogManager.shared.log("Düzenleme kaydedildi: " + localFile.lastPathComponent) }
                    }
                }
            }
            debounceWorkItem = workItem
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2, execute: workItem)
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        fileWatchers[path] = source
        source.resume()
    }
}
