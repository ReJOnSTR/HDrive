//
//  FileItem.swift
//  HDrive
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

public enum FileCategory: String, CaseIterable, Identifiable {
    case all = "Tümü"
    case document = "Belgeler"
    case image = "Fotoğraflar"
    case video = "Videolar"
    case audio = "Müzikler"
    case archive = "Arşivler"
    case other = "Diğer"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "folder.fill"
        case .document: return "doc.text.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .other: return "doc.fill"
        }
    }
}

public struct FileItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date
    public let creationDate: Date
    
    public init(url: URL) {
        self.id = url.path
        self.name = url.lastPathComponent
        self.url = url
        
        let resourceValues = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ])
        
        self.isDirectory = resourceValues?.isDirectory ?? false
        self.size = Int64(resourceValues?.fileSize ?? 0)
        self.modificationDate = resourceValues?.contentModificationDate ?? Date()
        self.creationDate = resourceValues?.creationDate ?? Date()
    }
    
    public var formattedSize: String {
        if isDirectory {
            return "--"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: modificationDate)
    }
    
    public var category: FileCategory {
        if isDirectory { return .all }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "svg", "bmp", "tiff":
            return .image
        case "mp4", "mov", "m4v", "mkv", "avi", "webm":
            return .video
        case "mp3", "wav", "m4a", "flac", "aac", "ogg":
            return .audio
        case "pdf", "txt", "md", "json", "docx", "doc", "xlsx", "xls", "pptx", "csv", "xml", "html", "swift", "py", "js":
            return .document
        case "zip", "tar", "gz", "7z", "rar":
            return .archive
        default:
            return .other
        }
    }
    
    public var systemIcon: String {
        if isDirectory {
            return "folder.fill"
        }
        switch category {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document:
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" { return "doc.richtext" }
            if ["swift", "js", "json", "py", "html", "css"].contains(ext) { return "curlybraces" }
            return "doc.text"
        case .archive: return "archivebox"
        case .all, .other: return "doc"
        }
    }
    
    public var iconColor: Color {
        if isDirectory { return .blue }
        switch category {
        case .image: return .purple
        case .video: return .orange
        case .audio: return .pink
        case .document: return .cyan
        case .archive: return .indigo
        case .all, .other: return .gray
        }
    }
    
    public var mimeType: String {
        if isDirectory { return "httpd/unix-directory" }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
