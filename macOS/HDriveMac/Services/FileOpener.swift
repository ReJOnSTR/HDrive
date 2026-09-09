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
    
    /// Uzak Cloudreve dosyasını Mac'in varsayılan uygulamasıyla (Word, VLC, Preview, Acrobat vb.) açar
    public func openFileNatively(file: RemoteFileItem, client: WebDAVClient, completion: @escaping (Bool, String?) -> Void) {
        // 1. Önce Finder'da bağlı bir disk var mı kontrol et
        if DriveMounter.shared.isMounted, let mountPoint = DriveMounter.shared.mountPoint {
            let relativeClean = file.href.hasPrefix("/") ? String(file.href.dropFirst()) : file.href
            let candidateURL = mountPoint.appendingPathComponent(relativeClean)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                // Doğrudan disk üzerinden yerel aç
                NSWorkspace.shared.open(candidateURL)
                completion(true, nil)
                return
            }
        }
        
        // 2. Eğer disk bağlı değilse veya dosya bulunamazsa: Dosyayı önbelleğe indirip yerel programla aç
        let localFile = cacheDir.appendingPathComponent(file.name)
        
        DispatchQueue.main.async {
            self.openingFile = file.name
            self.downloadProgress = 0.1
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
                
                // Mac'in varsayılan yerel programıyla aç (Preview, Word, VLC, QuickTime vb.)
                let success = NSWorkspace.shared.open(localFile)
                if success {
                    completion(true, nil)
                } else {
                    completion(false, "Bu dosya formatını açabilecek uygun bir Mac uygulaması bulunamadı.")
                }
            }
        }
    }
}
