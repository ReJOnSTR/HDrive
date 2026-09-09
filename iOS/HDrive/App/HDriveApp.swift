//
//  HDriveApp.swift
//  HDrive
//

import SwiftUI

@main
struct HDriveApp: App {
    @StateObject private var config = ServerConfig.shared
    @StateObject private var server = WebDAVServer.shared
    
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
                        Label("Cloudreve", systemImage: "cloud.fill")
                    }
                
                MainDashboardView()
                    .tabItem {
                        Label("Yerel Paylaşım", systemImage: "antenna.radiowaves.left.and.right")
                    }
                
                NavigationStack {
                    FileBrowserView()
                }
                .tabItem {
                    Label("Dosyalar", systemImage: "folder.fill")
                }
                
                QuickConnectGuideView()
                    .tabItem {
                        Label("PC Rehberi", systemImage: "display")
                    }
                
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
