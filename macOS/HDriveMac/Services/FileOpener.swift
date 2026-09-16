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
    
    /// Uzak Cloudreve dosyasını Mac'in varsayılan uygulamasıyla (Excel, Word, Preview, VLC, Figma vb.) açar
    public func openFileNatively(file: RemoteFileItem, client: WebDAVClient, completion: @escaping (Bool, String?) -> Void) {
        // 1. Finder'da bağlı bir ağ diski var mı kontrol et
        if DriveMounter.shared.isMounted, let mountPoint = DriveMounter.shared.mountPoint {
            var subPath = file.href
            if subPath.hasPrefix("/dav") {
                subPath = String(subPath.dropFirst(4))
            }
            subPath = subPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let candidateURL = mountPoint.appendingPathComponent(subPath)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                if NSWorkspace.shared.open(candidateURL) {
                    completion(true, nil)
                    return
                }
            }
        }
        
        // 2. Önizleme önbelleğinde zaten mevcut ve boyutu geçerli mi?
        let previewCandidate = FilePreviewManager.shared.previewCacheDir.appendingPathComponent(file.name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: previewCandidate.path),
           let size = attrs[.size] as? Int64, size > 0 {
            if NSWorkspace.shared.open(previewCandidate) {
                completion(true, nil)
                return
            }
        }
        
        // 4. HDriveFiles önbelleğinde zaten mevcut ve boyutu geçerli mi?
        let localFile = cacheDir.appendingPathComponent(file.name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localFile.path),
           let size = attrs[.size] as? Int64, size > 0 {
            if NSWorkspace.shared.open(localFile) {
                completion(true, nil)
                return
            }
        }
        
        // 5. Yerel kopya yoksa arka planda hızlıca indir ve varsayılan Mac uygulamasıyla aç
        DispatchQueue.main.async {
            self.openingFile = file.name
            self.downloadProgress = 0.05
        }
        
        client.downloadFile(href: file.href, to: localFile, progress: { progress in
            DispatchQueue.main.async {
                self.downloadProgress = progress
            }
        }) { error in
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
                    self.watchForLiveEdits(localFile: localFile, remoteHref: file.href, client: client)
                    completion(true, nil)
                } else {
                    // Özel bir varsayılan program tanımlı değilse Finder'da dosyayı seçerek göster
                    NSWorkspace.shared.activateFileViewerSelecting([localFile])
                    self.watchForLiveEdits(localFile: localFile, remoteHref: file.href, client: client)
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
                self.lastModifiedDates[path] = currentModDate
                
                // Cloudreve'e otomatik geri yükle
                client.uploadFile(localFileURL: localFile, toRemotePath: remoteHref) { err in
                    if err == nil {
                        print("[HDrive LiveEdit] Otomatik eşitlendi: \(localFile.lastPathComponent)")
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
