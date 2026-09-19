//
//  HDriveApp.swift
//  HDrive
//

import SwiftUI

@main
struct HDriveApp: App {
    @StateObject private var config = ServerConfig.shared
    @StateObject private var server = WebDAVServer.shared
    @StateObject private var transferManager = TransferManager.shared
    
    init() {
        // Gerekli başlangıç dizinlerini hazırla
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let hdriveDir = doc.appendingPathComponent("HDriveFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: hdriveDir, withIntermediateDirectories: true)
    }
    
    var body: some Scene {
        WindowGroup {
            TabView {
                CloudreveMobileView()
                    .tabItem {
                        Label("Bulut", systemImage: "cloud.fill")
                    }
                
                NavigationStack {
                    FileBrowserView()
                }
                .tabItem {
                    Label("Dosyalar", systemImage: "folder.fill")
                }
                
                TransferSheetView()
                    .tabItem {
                        Label("Transferler", systemImage: "tray.and.arrow.down.fill")
                    }
                    .badge(transferManager.activeTransfersCount)
                
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Ayarlar", systemImage: "gearshape.fill")
                }
            }
            .tint(.indigo)
            .onAppear {
                // IP adresini ve depolama alanını yenile
                config.refreshIPAddress()
                config.updateDiskSpace()
            }
        }
    }
}
