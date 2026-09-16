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
    
    var body: some Scene {
        // 1. Ana Dosya Gezgini Penceresi (Finder / Explorer Görünümü)
        WindowGroup("HDrive") {
            NativeExplorerView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1040, height: 660)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Ayarlar...") {
                    SettingsWindowManager.shared.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        // 2. macOS Menü Çubuğu Simgesi (Menu Bar Extra)
        MenuBarExtra("HDrive", systemImage: "cloud.fill") {
            if let active = cloudreveManager.activeServer {
                Text("Bulut: \(active.name)")
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("HDrive Bulut Gezgini")
            }
            
            Divider()
            
            Button("Ayarlar...") {
                SettingsWindowManager.shared.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("HDrive'dan Çık") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
