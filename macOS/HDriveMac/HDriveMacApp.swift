//
//  HDriveMacApp.swift
//  HDriveMac - Yerel Klasör ve Dosya Yöneticisi
//

import SwiftUI
import AppKit

@main
struct HDriveMacApp: App {
    @StateObject private var mounter = DriveMounter.shared
    @StateObject private var cloudreveManager = CloudreveManager.shared
    @StateObject private var syncEngine = FolderSyncEngine.shared
    
    var body: some Scene {
        // 1. Ana Dosya Gezgini Penceresi (Finder / Explorer Görünümü)
        WindowGroup("HDrive") {
            NativeExplorerView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 920, height: 620)
        
        // 2. macOS Menü Çubuğu Simgesi (Menu Bar Extra)
        MenuBarExtra("HDrive", systemImage: "folder.fill") {
            Button("📁 Yerel Eşitleme Klasörünü Aç") {
                syncEngine.openLocalFolderInFinder()
            }
            
            Toggle("Otomatik Eşitleme", isOn: $syncEngine.isSyncEnabled)
            
            if syncEngine.isSyncEnabled {
                Button("Şimdi Eşitle") {
                    syncEngine.syncNow()
                }
            }
            
            Divider()
            
            Text("Durum: \(syncEngine.syncStatus)")
                .font(.caption)
            
            Divider()
            
            Button("HDrive'dan Çık") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
