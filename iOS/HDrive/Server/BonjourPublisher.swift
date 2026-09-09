//
//  BonjourPublisher.swift
//  HDrive
//

import Foundation

public final class BonjourPublisher: NSObject, NetServiceDelegate {
    private var netServiceWebDAV: NetService?
    private var netServiceHTTP: NetService?
    
    public func startPublishing(port: Int, name: String = "HDrive on iPhone") {
        stopPublishing()
        
        // 1. WebDAV servisi yayını (macOS Finder ve Windows Gezgini otomatik keşfi)
        netServiceWebDAV = NetService(domain: "local.", type: "_webdav._tcp.", name: name, port: Int32(port))
        netServiceWebDAV?.delegate = self
        let txtRecord: [String: String] = [
            "path": "/",
            "model": "iPhone",
            "version": "1.0.0"
        ]
        let data = NetService.data(fromTXTRecord: txtRecord.mapValues { $0.data(using: .utf8) ?? Data() })
        netServiceWebDAV?.setTXTRecord(data)
        netServiceWebDAV?.publish(options: .listenForConnections)
        
        // 2. Standart HTTP servisi yayını (Tarayıcı ve mDNS araçları için)
        netServiceHTTP = NetService(domain: "local.", type: "_http._tcp.", name: name, port: Int32(port))
        netServiceHTTP?.delegate = self
        netServiceHTTP?.publish(options: .listenForConnections)
        
        print("[Bonjour] '\(name)' servisi port \(port) üzerinde yerel ağda yayınlandı.")
    }
    
    public func stopPublishing() {
        netServiceWebDAV?.stop()
        netServiceWebDAV = nil
        
        netServiceHTTP?.stop()
        netServiceHTTP = nil
        print("[Bonjour] Servis yayını durduruldu.")
    }
    
    // MARK: - NetServiceDelegate
    public func netServiceDidPublish(_ sender: NetService) {
        print("[Bonjour] Servis başarıyla tescil edildi: \(sender.name)")
    }
    
    public func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("[Bonjour] Servis yayınlama hatası: \(errorDict)")
    }
}
