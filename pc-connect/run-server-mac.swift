//
//  run-server-mac.swift
//  HDrive PC / Mac Yerel Sunucu Başlatıcı
//

import Foundation

@main
struct HDriveMacApp {
    static func main() {
        print("\n" + String(repeating: "=", count: 64))
        print("          🚀 HDRIVE PC / MAC YEREL SUNUCUSU BAŞLATILIYOR        ")
        print(String(repeating: "=", count: 64))
        
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let hdriveDir = homeDir.appendingPathComponent("Documents/HDriveFiles", isDirectory: true)
        try? fileManager.createDirectory(at: hdriveDir, withIntermediateDirectories: true)
        
        print("\n📂 Depolama Klasörü: \(hdriveDir.path)")
        
        // Sunucuyu başlat
        let server = WebDAVServer.shared
        server.start()
        
        let ip = ServerConfig.shared.localIPAddress
        let port = ServerConfig.shared.port
        let localURL = "http://localhost:\(port)"
        let networkURL = "http://\(ip):\(port)"
        
        print("\n✅ WebDAV & Web Sunucusu Başarıyla Çalışıyor!")
        print("🌐 Yerel Web Arayüzü:  \(localURL)")
        print("📡 Ağ Bağlantı Adresi: \(networkURL)")
        print("\n💻 MAC FINDER İLE DOĞRUDAN DİSK OLARAK BAĞLANMAK İÇİN:")
        print("   1. Finder'ı açın ve Cmd + K tuşlarına basın")
        print("   2. Sunucu adresi olarak şunu yazın: \(localURL)")
        print("   3. 'Bağlan'a tıklayın. Finder yan menüsünde HDrive harici disk olarak açılacaktır!")
        print(String(repeating: "-", count: 64))
        print("💡 Çıkmak için Ctrl + C tuşlarına basın.\n")
        
        // Tarayıcıyı ve Finder'ı otomatik aç
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [localURL]
            try? process.run()
        }
        
        RunLoop.main.run()
    }
}
