//
//  NetworkUtils.swift
//  HDrive
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
import CoreImage.CIFilterBuiltins

public struct NetworkUtils {
    
    /// Cihazın Wi-Fi veya yerel ağdaki gerçek IPv4 adresini (en0 arayüzü) getirir
    public static func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) { // IPv4
                let name = String(cString: interface.ifa_name)
                // en0: Wi-Fi, en1/en2: Ethernet, pdp_ip0: Hücresel
                if name == "en0" || name == "en1" || name == "lo0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    let ip = String(cString: hostname)
                    if name == "en0" {
                        // Wi-Fi önceliklidir
                        address = ip
                        break
                    } else if address == nil {
                        address = ip
                    }
                }
            }
        }
        
        freeifaddrs(ifaddr)
        return address
    }
    
    #if canImport(UIKit)
    /// Verilen metinden (URL vb.) yüksek kaliteli QR Kod görseli üretir (iOS)
    public static func generateQRCode(from string: String, size: CGFloat = 200) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
    #elseif canImport(AppKit)
    /// Verilen metinden (URL vb.) yüksek kaliteli QR Kod görseli üretir (macOS)
    public static func generateQRCode(from string: String, size: CGFloat = 200) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        }
        
        return nil
    }
    #endif
}
