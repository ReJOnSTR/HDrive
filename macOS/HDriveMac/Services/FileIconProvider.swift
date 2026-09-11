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
    public func icon(for fileName: String, isDirectory: Bool, size: CGFloat = 64) -> NSImage {
        let ext = (fileName as NSString).pathExtension.lowercased()
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
        default: return false
        }
    }
    
    /// Özel profesyonel vektörel marka doküman rozeti çizer
    private func renderBrandIcon(for ext: String, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        
        let rect = NSRect(x: 4, y: 2, width: size - 8, height: size - 4)
        let (brandColor, labelText) = brandMeta(for: ext)
        
        // Sayfa Arka Planı (Hafif gri gölgeli beyaz kağıt)
        let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.12, yRadius: size * 0.12)
        NSColor.white.setFill()
        path.fill()
        
        // Marka Şeridi / Başlığı
        let headerHeight = rect.height * 0.38
        let headerRect = NSRect(x: rect.minX, y: rect.maxY - headerHeight, width: rect.width, height: headerHeight)
        let headerPath = NSBezierPath(roundedRect: headerRect, xRadius: size * 0.12, yRadius: size * 0.12)
        brandColor.setFill()
        headerPath.fill()
        
        // Kenar Çizgisi
        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1.0
        path.stroke()
        
        // Marka Metni / Kısaltması (X, W, P, Fig, Ps, Ai, PDF)
        let font = NSFont.systemFont(ofSize: size * 0.22, weight: .black)
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
        let extFont = NSFont.systemFont(ofSize: size * 0.14, weight: .bold)
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
            return (NSColor(red: 0.95, green: 0.31, blue: 0.12, alpha: 1.0), "FIG") // Figma Turuncu/Mor
        case "psd", "psb":
            return (NSColor(red: 0.19, green: 0.66, blue: 1.0, alpha: 1.0), "Ps") // Photoshop Camgöbeği
        case "ai", "eps":
            return (NSColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1.0), "Ai") // Illustrator Sarı/Turuncu
        case "pdf":
            return (NSColor(red: 1.0, green: 0.13, blue: 0.09, alpha: 1.0), "PDF") // Adobe PDF Kırmızı
        case "sketch":
            return (NSColor(red: 0.99, green: 0.64, blue: 0.0, alpha: 1.0), "💎") // Sketch Elmas
        case "ae", "aep":
            return (NSColor(red: 0.58, green: 0.58, blue: 1.0, alpha: 1.0), "Ae") // After Effects Mor
        case "pr", "prproj":
            return (NSColor(red: 0.90, green: 0.45, blue: 0.95, alpha: 1.0), "Pr") // Premiere Magenta
        case "indd":
            return (NSColor(red: 1.0, green: 0.20, blue: 0.40, alpha: 1.0), "Id") // InDesign Pembe/Kırmızı
        default:
            return (NSColor.gray, String(ext.prefix(3)).uppercased())
        }
    }
}
