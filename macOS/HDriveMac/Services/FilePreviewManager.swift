//
//  FilePreviewManager.swift
//  HDriveMac - Önizleme ve Hızlı Bakış (Quick Look) Yöneticisi
//

import Foundation
import AppKit
import SwiftUI
import QuickLookUI

public extension RemoteFileItem {
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
    
    var isImage: Bool {
        let ext = fileExtension
        return ["jpg", "jpeg", "png", "heic", "webp", "gif", "svg", "bmp", "tiff", "ico"].contains(ext)
    }
    
    var isMedia: Bool {
        let ext = fileExtension
        return ["mp4", "mov", "mkv", "avi", "m4v", "mp3", "m4a", "wav", "flac"].contains(ext)
    }
    
    var isPDF: Bool {
        fileExtension == "pdf"
    }
    
    var isTextOrCode: Bool {
        let ext = fileExtension
        return ["txt", "md", "json", "py", "swift", "js", "ts", "html", "css", "log", "sh", "yaml", "yml", "xml", "csv"].contains(ext)
    }
    
    var kindDescription: String {
        if isDirectory { return "Klasör" }
        let ext = fileExtension.uppercased()
        switch fileExtension {
        case "jpg", "jpeg", "png", "heic", "webp", "gif", "bmp", "tiff":
            return "\(ext) Görüntüsü"
        case "mp4", "mov", "mkv", "avi", "m4v":
            return "\(ext) Video Dosyası"
        case "mp3", "m4a", "wav", "flac", "aac":
            return "\(ext) Ses Dosyası"
        case "pdf":
            return "PDF Belgesi"
        case "zip", "rar", "7z", "tar", "gz":
            return "\(ext) Arşivi"
        case "doc", "docx":
            return "Microsoft Word Belgesi"
        case "xls", "xlsx", "csv":
            return "Microsoft Excel Çalışma Tablosu"
        case "ppt", "pptx":
            return "Microsoft PowerPoint Sunusu"
        case "txt":
            return "Düz Metin Belgesi"
        case "md":
            return "Markdown Belgesi"
        case "swift":
            return "Swift Kaynak Kodu"
        case "py":
            return "Python Kaynak Kodu"
        case "json":
            return "JSON Veri Dosyası"
        case "html", "htm":
            return "HTML Web Belgesi"
        case "dmg":
            return "Apple Disk Görüntüsü"
        case "pkg":
            return "macOS Yükleyici Paketi"
        default:
            return ext.isEmpty ? "Belge" : "\(ext) Dosyası"
        }
    }
}

public final class FilePreviewManager: ObservableObject {
    public static let shared = FilePreviewManager()
    
    @Published public var cachedImages: [String: NSImage] = [:]
    @Published public var loadingPreviewIDs: Set<String> = []
    
    public let previewCacheDir: URL = {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("HDrivePreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private init() {}
    
    /// Belirtilen dosya için yerel bir dosya URL'i arar (Disk, Eşitleme veya Cache)
    public func resolvedLocalURL(for file: RemoteFileItem) -> URL? {
        let rel = file.href.hasPrefix("/") ? String(file.href.dropFirst()) : file.href
        
        // 1. Ağ Sürücüsü (Mount)
        if DriveMounter.shared.isMounted, let mountPoint = DriveMounter.shared.mountPoint {
            let candidate = mountPoint.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        
        // 2. Senkronize Edilen Klasör
        let syncFile = FolderSyncEngine.shared.localFolderURL.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: syncFile.path) {
            return syncFile
        }
        
        // 3. HDriveFiles Cache (FileOpener)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let openerCache = caches.appendingPathComponent("HDriveFiles", isDirectory: true).appendingPathComponent(file.name)
            if FileManager.default.fileExists(atPath: openerCache.path) {
                return openerCache
            }
        }
        
        // 4. Özel Önizleme Cache
        let previewTarget = previewCacheDir.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: previewTarget.path) {
            return previewTarget
        }
        
        return nil
    }
    
    /// Görsel dosyasının küçük resmini (thumbnail) yükler veya indirir
    public func loadThumbnail(for file: RemoteFileItem, client: WebDAVClient?) {
        guard file.isImage else { return }
        
        // Zaten bellekte varsa tekrar uğraşma
        if cachedImages[file.id] != nil { return }
        
        // Yerel dosyadan yükle
        if let localURL = resolvedLocalURL(for: file),
           let img = NSImage(contentsOf: localURL) {
            DispatchQueue.main.async {
                self.cachedImages[file.id] = img
            }
            return
        }
        
        // Sunucudan indir (30MB altı dosyalar için otomatik)
        guard let client = client, !loadingPreviewIDs.contains(file.id) else { return }
        if file.size > 30 * 1024 * 1024 { return }
        
        loadingPreviewIDs.insert(file.id)
        let destURL = previewCacheDir.appendingPathComponent(file.name)
        
        client.downloadFile(href: file.href, to: destURL, progress: { _ in }) { [weak self] error in
            DispatchQueue.main.async {
                self?.loadingPreviewIDs.remove(file.id)
                if error == nil, let img = NSImage(contentsOf: destURL) {
                    self?.cachedImages[file.id] = img
                }
            }
        }
    }
    
    /// Hızlı Bakış (Quick Look) veya doğrudan inceleme için dosyanın yerel kopyasını garanti eder
    public func ensureLocalFile(file: RemoteFileItem, client: WebDAVClient, completion: @escaping (URL?) -> Void) {
        if let local = resolvedLocalURL(for: file) {
            completion(local)
            return
        }
        
        let destURL = previewCacheDir.appendingPathComponent(file.name)
        loadingPreviewIDs.insert(file.id)
        
        client.downloadFile(href: file.href, to: destURL, progress: { _ in }) { [weak self] error in
            DispatchQueue.main.async {
                self?.loadingPreviewIDs.remove(file.id)
                if error == nil {
                    if file.isImage, let img = NSImage(contentsOf: destURL) {
                        self?.cachedImages[file.id] = img
                    }
                    completion(destURL)
                } else {
                    completion(nil)
                }
            }
        }
    }
}

/// macOS Yerleşik Quick Look Önizleme Görünümü
public struct QuickLookRepresentable: NSViewRepresentable {
    public let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as NSURL
        view.autoresizingMask = [.width, .height]
        return view
    }
    
    public func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? NSURL) != (url as NSURL) {
            nsView.previewItem = url as NSURL
        }
    }
}
