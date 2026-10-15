//
//  HDriveApp.swift
//  HDrive
//

import SwiftUI

@main
struct HDriveApp: App {
    @StateObject private var accountManager = CloudreveManager.shared
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
                        Label(L10n.text("Bulut"), systemImage: "cloud.fill")
                    }
                
                NavigationStack {
                    FileBrowserView()
                }
                .tabItem {
                    Label(L10n.text("Dosyalar"), systemImage: "folder.fill")
                }
                
                TransferSheetView()
                    .tabItem {
                        Label(L10n.text("Transferler"), systemImage: "tray.and.arrow.down.fill")
                    }
                    .badge(transferManager.activeTransfersCount)
                
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label(L10n.text("Ayarlar"), systemImage: "gearshape.fill")
                }
            }
            .alert("Hesap kaydı", isPresented: Binding(
                get: { accountManager.lastError != nil },
                set: { if !$0 { accountManager.lastError = nil } })) {
                Button(L10n.text("Tamam")) { accountManager.lastError = nil }
            } message: { Text(accountManager.lastError ?? "") }
            .tint(.indigo)
            .onAppear {
                // IP adresini ve depolama alanını yenile
                config.refreshIPAddress()
                config.updateDiskSpace()
            }
        }
    }
}
