//
//  DriveMounter.swift
//  HDriveMac - macOS Finder Yerel Disk ve Klasör Bağlayıcı
//

import Foundation
import AppKit

public final class DriveMounter: ObservableObject {
    public static let shared = DriveMounter()
    
    @Published public var isMounted: Bool = false
    @Published public var mountPoint: URL? = nil
    @Published public var statusMessage: String = "Bağlantı bekleniyor"
    @Published public var lastError: String? = nil
    
    public let defaultMountFolder: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Cloudreve", isDirectory: true)
    }()
    
    private init() {
        checkMountStatus()
    }
    
    /// Cloudreve WebDAV sunucusunu Mac'te yerel bir klasör ve harici disk gibi Finder'a bağlar
    public func connectAndOpenInFinder(config: CloudreveServerConfig, completion: @escaping (Bool, String?) -> Void) {
        lastError = nil
        statusMessage = "Cloudreve sunucusuna bağlanılıyor..."
        
        guard let url = URL(string: config.serverURL), let host = url.host else {
            let err = "Geçersiz sunucu adresi formatı. Lütfen adresi kontrol edin."
            self.lastError = err
            self.statusMessage = err
            completion(false, err)
            return
        }
        
        let scheme = url.scheme ?? "http"
        let port = url.port != nil ? ":\(url.port!)" : ""
        let path = url.path.isEmpty ? "/dav" : url.path
        
        // Kimlik bilgileriyle URL oluştur
        let authURLString: String
        if !config.username.isEmpty && !config.password.isEmpty {
            let encodedUser = config.username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? config.username
            let encodedPass = config.password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? config.password
            authURLString = "\(scheme)://\(encodedUser):\(encodedPass)@\(host)\(port)\(path)"
        } else {
            authURLString = "\(scheme)://\(host)\(port)\(path)"
        }
        
        // 1. AppleScript ile Finder'a disk birimi olarak bağla
        let scriptSource = """
        tell application "Finder"
            try
                mount volume "\(authURLString)"
                return "SUCCESS"
            on error errMsg
                return errMsg
            end try
        end tell
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            let script = NSAppleScript(source: scriptSource)
            let resultDesc = script?.executeAndReturnError(&errorInfo)
            let result = resultDesc?.stringValue ?? ""
            
            DispatchQueue.main.async {
                if result == "SUCCESS" {
                    // Finder'a başarıyla bağlandı
                    self.isMounted = true
                    self.statusMessage = "Bağlandı! Finder açılıyor..."
                    
                    // Bağlanan diski Finder'da aç
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.openMountedVolumeInFinder(host: host)
                    }
                    completion(true, nil)
                } else {
                    // AppleScript başarısız olursa mount_webdav komutunu dene
                    self.mountViaCommand(authURL: authURLString, volumeName: config.name.isEmpty ? "Cloudreve" : config.name) { success, err in
                        if success {
                            self.isMounted = true
                            self.statusMessage = "Bağlandı! Finder açılıyor..."
                            self.openFolderInFinder()
                            completion(true, nil)
                        } else {
                            let rawMsg = errorInfo?[NSAppleScript.errorMessage] as? String ?? err ?? result
                            let friendlyMsg: String
                            if rawMsg.contains("-5014") || rawMsg.contains("22") {
                                friendlyMsg = "macOS, şifrelenmemiş HTTP WebDAV ağ diski bağlantısını kısıtlıyor (-5014). Bunun yerine lütfen üstteki 'Yerel Klasör Eşitleme (OneDrive Modu)'nu kullanın."
                            } else {
                                friendlyMsg = rawMsg
                            }
                            self.lastError = friendlyMsg
                            self.statusMessage = friendlyMsg
                            completion(false, friendlyMsg)
                        }
                    }
                }
            }
        }
    }
    
    /// mount_webdav komutu ile ~/Cloudreve klasörüne doğrudan mount eder
    private func mountViaCommand(authURL: String, volumeName: String, completion: @escaping (Bool, String?) -> Void) {
        let mountDir = self.defaultMountFolder
        try? FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount_webdav")
        process.arguments = ["-v", volumeName, authURL, mountDir.path]
        
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                self.mountPoint = mountDir
                completion(true, nil)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Bilinmeyen hata"
                completion(false, output)
            }
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    /// Finder'da bağlı olan /Volumes diskini açar
    public func openMountedVolumeInFinder(host: String = "") {
        checkMountStatus()
        
        if let point = mountPoint {
            NSWorkspace.shared.open(point)
            return
        }
        
        // /Volumes altındaki diskleri kontrol et
        if let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            for vol in volumes {
                if (!host.isEmpty && vol.localizedCaseInsensitiveContains(host)) ||
                   vol.localizedCaseInsensitiveContains("dav") ||
                   vol.localizedCaseInsensitiveContains("cloudreve") {
                    let volURL = URL(fileURLWithPath: "/Volumes/\(vol)")
                    self.mountPoint = volURL
                    self.isMounted = true
                    NSWorkspace.shared.open(volURL)
                    return
                }
            }
        }
    }
    
    /// Yerel ~/Cloudreve klasörünü Finder'da açar
    public func openFolderInFinder() {
        if FileManager.default.fileExists(atPath: defaultMountFolder.path) {
            NSWorkspace.shared.open(defaultMountFolder)
        }
    }
    
    /// Bağlantıyı Güvenle Keser (Unmount)
    public func disconnect(completion: @escaping (Bool) -> Void) {
        statusMessage = "Bağlantı kesiliyor..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Finder disklerini çıkar
            let scriptSource = """
            tell application "Finder"
                try
                    set diskList to every disk whose name contains "dav" or name contains "Cloudreve" or name contains "localhost"
                    repeat with d in diskList
                        eject d
                    end repeat
                end try
            end tell
            """
            _ = NSAppleScript(source: scriptSource)?.executeAndReturnError(nil)
            
            // 2. ~/Cloudreve unmount et
            let unmountProcess = Process()
            unmountProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            unmountProcess.arguments = ["unmount", "force", self.defaultMountFolder.path]
            try? unmountProcess.run()
            unmountProcess.waitUntilExit()
            
            DispatchQueue.main.async {
                self.isMounted = false
                self.mountPoint = nil
                self.statusMessage = "Bağlantı kesildi."
                completion(true)
            }
        }
    }
    
    /// Sistemin mount tablosunu kontrol eder
    public func checkMountStatus() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/mount")
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if output.contains("webdav") || output.contains("Cloudreve") {
                self.isMounted = true
                self.statusMessage = "Bağlı: Dosyalar Finder'da kullanıma hazır"
                
                // Mount path bul
                for line in output.components(separatedBy: "\n") {
                    if line.contains("webdavfs") {
                        let parts = line.components(separatedBy: " on ")
                        if parts.count >= 2 {
                            let pathPart = parts[1].components(separatedBy: " (")[0]
                            self.mountPoint = URL(fileURLWithPath: pathPart)
                            break
                        }
                    }
                }
            } else {
                self.isMounted = false
                self.mountPoint = nil
                self.statusMessage = "Bağlantı bekleniyor"
            }
        } catch {
            self.isMounted = false
        }
    }
}
