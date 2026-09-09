//
//  MacDashboardView.swift
//  HDriveMac
//

import SwiftUI
import AppKit

public struct MacDashboardView: View {
    @ObservedObject var mounter = DriveMounter.shared
    @ObservedObject var bonjour = BonjourBrowser.shared
    @ObservedObject var serverConfig = ServerConfig.shared
    
    @State private var targetURL: String = "http://localhost:8080"
    @State private var isMounting: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var isSuccessFeedback: Bool = true
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. Üst Bar
            topBarView
            
            Divider()
            
            // 2. Ana İçerik
            ScrollView {
                VStack(spacing: 20) {
                    // Sürücü Durumu & Doğrudan Finder Bağlantı Kartı
                    mountControlCard
                    
                    // Keşfedilen Cihazlar (iPhone vb.)
                    discoveredDevicesCard
                    
                    // Mac Yerel WebDAV Paylaşım Sunucusu
                    localServerCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            bonjour.startSearching()
            mounter.checkMountStatus()
        }
    }
    
    // MARK: - Üst Bar
    private var topBarView: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.indigo, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                Image(systemName: "externaldrive.fill.badge.wifi")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("HDrive Desktop")
                    .font(.headline.bold())
                Text("macOS Doğrudan Ağ Sürücüsü ve WebDAV Merkezi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Finder Durum Hapı
            HStack(spacing: 6) {
                Circle()
                    .fill(mounter.isMounted ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(mounter.isMounted ? "Finder'a Bağlı" : "Bağlantı Yok")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }
    
    // MARK: - Finder Sürücü Bağlama Kartı
    private var mountControlCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Finder Doğrudan Disk Entegrasyonu", systemImage: "internaldrive.fill")
                    .font(.headline)
                    .foregroundColor(.indigo)
                
                Spacer()
                
                if mounter.isMounted {
                    Text("Z: / Volumes")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }
            }
            
            Text("WebDAV protokolü sayesinde telefonunuz veya sunucunuz Mac Finder'a harici bir USB/Sabit disk gibi bağlanır. Dosyaları doğrudan Mac Finder içinden açabilir, kopyalayabilir ve silebilirsiniz.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Adres Giriş Alanı
            VStack(alignment: .leading, spacing: 6) {
                Text("Bağlanılacak WebDAV Adresi:")
                    .font(.caption.bold())
                
                HStack {
                    TextField("http://192.168.1.x:8080", text: $targetURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    
                    Button("Varsayılan") {
                        targetURL = "http://localhost:8080"
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Eylem Butonları
            HStack(spacing: 12) {
                if !mounter.isMounted {
                    Button(action: mountDrive) {
                        HStack {
                            if isMounting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "link.circle.fill")
                            }
                            Text(isMounting ? "Bağlanıyor..." : "Finder'da Disk Olarak Bağla")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(isMounting || targetURL.isEmpty)
                } else {
                    Button(action: openInFinder) {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("Finder'da Aç")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    Button(action: unmountDrive) {
                        HStack {
                            Image(systemName: "eject.fill")
                            Text("Sürücüyü Çıkar")
                        }
                        .frame(width: 140)
                        .frame(height: 38)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Durum / Geri Bildirim Mesajı
            if let msg = feedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: isSuccessFeedback ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isSuccessFeedback ? .green : .red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSuccessFeedback ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.indigo.opacity(0.25), lineWidth: 1.5)
        )
    }
    
    // MARK: - Keşfedilen Cihazlar (Bonjour)
    private var discoveredDevicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Ağdaki HDrive Cihazları (Bonjour)", systemImage: "bonjour")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { bonjour.startSearching() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Cihazları Yeniden Tara")
            }
            
            if bonjour.discoveredDevices.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    Text("Wi-Fi ağında HDrive açılmış bir telefon veya cihaz aranıyor...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(bonjour.discoveredDevices) { device in
                    HStack {
                        Image(systemName: "iphone.gen3")
                            .font(.title3)
                            .foregroundColor(.indigo)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                                .font(.body.weight(.medium))
                            Text(device.connectionURL)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Seç ve Bağla") {
                            targetURL = device.connectionURL
                            mountDrive()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
    }
    
    // MARK: - Mac Yerel Sunucu Kartı
    private var localServerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Mac Yerel Paylaşım Sunucusu", systemImage: "server.rack")
                    .font(.headline)
                
                Spacer()
                
                Button(action: toggleLocalServer) {
                    Text(serverConfig.isRunning ? "Durdur" : "Başlat")
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Belgeleri Klasörü: ~/Documents/HDriveFiles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Durum: \(serverConfig.isRunning ? "Port \(serverConfig.port) üzerinde aktif" : "Kapalı")")
                        .font(.caption.weight(.medium))
                        .foregroundColor(serverConfig.isRunning ? .green : .secondary)
                }
                
                Spacer()
                
                Button("Klasörü Aç") {
                    let homeDir = FileManager.default.homeDirectoryForCurrentUser
                    let hdriveDir = homeDir.appendingPathComponent("Documents/HDriveFiles")
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: hdriveDir.path)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
    }
    
    // MARK: - Eylemler
    private func mountDrive() {
        isMounting = true
        feedbackMessage = nil
        
        mounter.mount(url: targetURL) { success, error in
            isMounting = false
            if success {
                isSuccessFeedback = true
                feedbackMessage = "Başarılı! HDrive Mac Finder'a bir disk olarak bağlandı."
                mounter.openInFinder()
            } else {
                isSuccessFeedback = false
                feedbackMessage = "Bağlantı hatası: \(error ?? "Bilinmeyen hata")"
            }
        }
    }
    
    private func unmountDrive() {
        mounter.unmount { _ in
            isSuccessFeedback = true
            feedbackMessage = "Sürücü güvenle çıkarıldı."
        }
    }
    
    private func openInFinder() {
        mounter.openInFinder()
    }
    
    private func toggleLocalServer() {
        if serverConfig.isRunning {
            WebDAVServer.shared.stop()
        } else {
            WebDAVServer.shared.start()
        }
    }
}
