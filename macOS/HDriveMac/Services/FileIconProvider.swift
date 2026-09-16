//
//  FileIconProvider.swift
//  HDriveMac - Profesyonel Yerel ve Marka Dosya İkon Sağlayıcısı
//

import Foundation
import AppKit
import UniformTypeIdentifiers

public final class FileIconProvider {
    public static let shared = FileIconProvider()
    
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 300
    }
    
    /// Dosya veya klasör için resmi işletim sistemi ve marka ikonunu döner
    public func icon(for fileName: String, isDirectory: Bool, size: CGFloat = 64, contentType: String? = nil) -> NSImage {
        var ext = (fileName as NSString).pathExtension.lowercased()
        if ext.isEmpty, let mime = contentType {
            if mime == "application/vnd.google-apps.document" { ext = "docx" }
            else if mime == "application/vnd.google-apps.spreadsheet" { ext = "xlsx" }
            else if mime == "application/vnd.google-apps.presentation" { ext = "pptx" }
            else if mime == "application/vnd.google-apps.drawing" { ext = "png" }
            else if mime.hasPrefix("application/vnd.google-apps.") { ext = "pdf" }
        }
        let cacheKey = "\(isDirectory ? "dir" : ext)_\(Int(size))" as NSString
        
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        
        let finalImage: NSImage
        if isDirectory {
            let folderIcon = NSWorkspace.shared.icon(for: .folder)
            folderIcon.size = NSSize(width: size, height: size)
            finalImage = folderIcon
        } else {
            // 1. İşletim sisteminin kayıtlı gerçek uygulamasından ikonu al
            let utType = UTType(filenameExtension: ext) ?? .item
            let sysIcon = NSWorkspace.shared.icon(for: utType)
            let registeredApp = NSWorkspace.shared.urlForApplication(toOpen: utType)?.lastPathComponent
            
            // Eğer Figma, Sketch, Adobe PSD/AI gibi özel programlarsa ve Mac'te özel uygulaması yoksa (veya Preview ise),
            // kusursuz profesyonel marka vektör ikonu çiz.
            let shouldUseBrandIcon: Bool
            if isKnownBrand(ext: ext) {
                if registeredApp == nil {
                    shouldUseBrandIcon = true
                } else if registeredApp == "Preview.app" && ["psd", "psb", "ai", "eps"].contains(ext) {
                    shouldUseBrandIcon = true
                } else {
                    shouldUseBrandIcon = false
                }
            } else {
                shouldUseBrandIcon = false
            }
            
            if shouldUseBrandIcon {
                finalImage = renderBrandIcon(for: ext, size: size)
            } else {
                sysIcon.size = NSSize(width: size, height: size)
                finalImage = sysIcon
            }
        }
        
        cache.setObject(finalImage, forKey: cacheKey)
        return finalImage
    }
    
    private func isKnownBrand(ext: String) -> Bool {
        switch ext {
        case "xlsx", "xls", "csv", "xlsm": return true
        case "docx", "doc", "rtf": return true
        case "pptx", "ppt", "key": return true
        case "fig", "figjam": return true
        case "psd", "psb": return true
        case "ai", "eps": return true
        case "sketch": return true
        case "pdf": return true
        case "ae", "aep": return true
        case "pr", "prproj": return true
        case "indd": return true
        case "mp4", "mov", "mkv", "avi", "m4v": return true
        case "mp3", "wav", "m4a", "flac", "aac": return true
        case "zip", "rar", "7z", "tar", "gz": return true
        case "swift", "py", "js", "ts", "json", "html", "css": return true
        default: return false
        }
    }
    
    /// Özel profesyonel vektörel marka doküman rozeti çizer (Retina @2x Yüksek Kalite)
    private func renderBrandIcon(for ext: String, size: CGFloat) -> NSImage {
        let scale: CGFloat = 2.0
        let pixelWidth = Int(size * scale)
        let pixelHeight = Int(size * scale)
        
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) ?? NSBitmapImageRep()
        
        rep.size = NSSize(width: size, height: size)
        
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.shouldAntialias = true
        
        let rect = NSRect(x: 3, y: 2, width: size - 6, height: size - 4)
        let (brandColor, labelText) = brandMeta(for: ext)
        
        // Sayfa Arka Planı (Hafif yuvarlatılmış modern kart)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.16, yRadius: size * 0.16)
        NSColor.white.setFill()
        path.fill()
        
        // Marka Şeridi / Başlığı
        let headerHeight = rect.height * 0.42
        let headerRect = NSRect(x: rect.minX, y: rect.maxY - headerHeight, width: rect.width, height: headerHeight)
        let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: size * 0.16, yRadius: size * 0.16)
        brandColor.setFill()
        headerPath.fill()
        
        // Kenar Çizgisi
        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        // Marka Metni / Kısaltması (W, X, P, PDF, VID, AUD, vb.)
        let font = NSFont.systemFont(ofSize: size * 0.20, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: labelText, attributes: attrs)
        let strSize = str.size()
        let strPoint = NSPoint(
            x: headerRect.midX - strSize.width / 2,
            y: headerRect.midY - strSize.height / 2
        )
        str.draw(at: strPoint)
        
        // Alt Uzantı Yazısı
        let extFont = NSFont.systemFont(ofSize: max(8, size * 0.15), weight: .bold)
        let extAttrs: [NSAttributedString.Key: Any] = [
            .font: extFont,
            .foregroundColor: brandColor
        ]
        let extStr = NSAttributedString(string: ext.uppercased(), attributes: extAttrs)
        let extSize = extStr.size()
        let extPoint = NSPoint(
            x: rect.midX - extSize.width / 2,
            y: rect.minY + (rect.height - headerHeight) / 2 - extSize.height / 2
        )
        extStr.draw(at: extPoint)
        
        image.unlockFocus()
        return image
    }
    
    private func brandMeta(for ext: String) -> (NSColor, String) {
        switch ext {
        case "xlsx", "xls", "csv", "xlsm":
            return (NSColor(red: 0.06, green: 0.49, blue: 0.25, alpha: 1.0), "X") // Excel Yeşil
        case "docx", "doc", "rtf":
            return (NSColor(red: 0.09, green: 0.35, blue: 0.74, alpha: 1.0), "W") // Word Mavi
        case "pptx", "ppt", "key":
            return (NSColor(red: 0.77, green: 0.24, blue: 0.11, alpha: 1.0), "P") // PowerPoint Turuncu
        case "fig", "figjam":
            return (NSColor(red: 0.95, green: 0.31, blue: 0.12, alpha: 1.0), "FIG") // Figma
        case "psd", "psb":
            return (NSColor(red: 0.19, green: 0.66, blue: 1.0, alpha: 1.0), "Ps") // Photoshop
        case "ai", "eps":
            return (NSColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1.0), "Ai") // Illustrator
        case "pdf":
            return (NSColor(red: 1.0, green: 0.13, blue: 0.09, alpha: 1.0), "PDF") // PDF
        case "sketch":
            return (NSColor(red: 0.99, green: 0.64, blue: 0.0, alpha: 1.0), "💎")
        case "ae", "aep":
            return (NSColor(red: 0.58, green: 0.58, blue: 1.0, alpha: 1.0), "Ae")
        case "pr", "prproj":
            return (NSColor(red: 0.90, green: 0.45, blue: 0.95, alpha: 1.0), "Pr")
        case "indd":
            return (NSColor(red: 1.0, green: 0.20, blue: 0.40, alpha: 1.0), "Id")
        case "mp4", "mov", "mkv", "avi", "m4v":
            return (NSColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1.0), "VID") // Video Mor
        case "mp3", "wav", "m4a", "flac", "aac":
            return (NSColor(red: 0.92, green: 0.28, blue: 0.60, alpha: 1.0), "AUD") // Audio Pembe
        case "zip", "rar", "7z", "tar", "gz":
            return (NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0), "ZIP") // Arşiv Sarı
        case "swift", "py", "js", "ts", "json", "html", "css":
            return (NSColor(red: 0.05, green: 0.65, blue: 0.91, alpha: 1.0), "</>") // Kod Mavi
        default:
            return (NSColor.gray, String(ext.prefix(3)).uppercased())
        }
    }
}
