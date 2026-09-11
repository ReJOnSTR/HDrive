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
    
    private let cacheDir: URL = {
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
        
        // 2. Senkronize klasörde var mı kontrol et
        let syncCandidate = FolderSyncEngine.shared.localFolderURL.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: syncCandidate.path) {
            if NSWorkspace.shared.open(syncCandidate) {
                completion(true, nil)
                return
            }
        }
        
        // 3. Önizleme önbelleğinde zaten mevcut ve boyutu geçerli mi?
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
                    completion(true, nil)
                } else {
                    // Özel bir varsayılan program tanımlı değilse Finder'da dosyayı seçerek göster
                    NSWorkspace.shared.activateFileViewerSelecting([localFile])
                    completion(true, nil)
                }
            }
        }
    }
}
