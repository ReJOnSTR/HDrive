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
        MenuBarExtra("HDrive", systemImage: "cloud.fill") {
            if let active = cloudreveManager.activeServer {
                Text("Bulut: \(active.name)")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("HDrive Bulut Gezgini")
            }
            
            Divider()
            
            Button("HDrive'dan Çık") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
