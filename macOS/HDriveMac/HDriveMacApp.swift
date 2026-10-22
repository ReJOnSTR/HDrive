//
//  HDriveMacApp.swift
//  HDriveMac - Yerel Klasör ve Dosya Yöneticisi
//

import SwiftUI
import AppKit

@main
struct HDriveMacApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var cloudreveManager = CloudreveManager.shared
    
    var body: some Scene {
        // 1. Ana Dosya Gezgini Penceresi (Finder / Explorer Görünümü)
        WindowGroup("HDrive") {
            NativeExplorerView()
                .alert("Hesap kaydı", isPresented: Binding(
                    get: { cloudreveManager.lastError != nil },
                    set: { if !$0 { cloudreveManager.lastError = nil } })) {
                    Button("Tamam") { cloudreveManager.lastError = nil }
                } message: { Text(cloudreveManager.lastError ?? "") }
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
                Button("Çevrimdışı Dosyalar ve Önbellek...") { openWindow(id: "workspace") }
            }
            CommandGroup(after: .appInfo) {
                Button("Güncellemeleri kontrol et…") {
                    openWindow(id: "updates")
                    AppUpdateModel.shared.check()
                }
            }
            CommandMenu("Görüntü") {
                Button("Araç Çubuğunu Özelleştir...") {
                    NotificationCenter.default.post(name: .openToolbarCustomizer, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
        
        // Keep auxiliary windows after the main scene so launch opens the file explorer.
        Window("Dosyalar ve Depolama", id: "workspace") { WorkspaceSettingsView().frame(minWidth: 520, minHeight: 500) }

        Window("HDrive Güncellemeleri", id: "updates") {
            ScrollView { AppUpdatesView().padding(24) }.frame(minWidth: 580, minHeight: 360)
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
