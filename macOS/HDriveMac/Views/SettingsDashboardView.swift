//
//  SettingsDashboardView.swift
//  HDriveMac - Cloudreve Finder Sürücü Ayarları & Bağlantı Merkezi
//

import SwiftUI
import AppKit

public struct SettingsDashboardView: View {
    @ObservedObject var manager = CloudreveManager.shared
    @ObservedObject var mounter = DriveMounter.shared
    
    @State private var serverName: String = "Cloudreve"
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var autoMount: Bool = true
    
    @State private var isConnecting = false
    @State private var isTesting = false
    @State private var feedbackMessage: String? = nil
    @State private var isSuccessFeedback = true
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. Üst Başlık & Durum Çubuğu
            headerView
            
            Divider()
            
            // 2. Ana Ayarlar ve Bağlantı Formu
            ScrollView {
                VStack(spacing: 20) {
                    // Ana Eylem ve Durum Kartı
                    mainActionCard
                    
                    // Bağlantı Bilgileri Ayar Kartı
                    connectionSettingsCard
                    
                    // Windows PC Entegrasyon Bilgisi
                    windowsHelperCard
                }
                .padding(24)
            }
        }
        .frame(width: 580, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadConfig()
            mounter.checkMountStatus()
        }
    }
    
    // MARK: - 1. Üst Başlık
    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color.indigo, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                Image(systemName: "folder.fill.badge.gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("HDrive - Sürücü & Klasör Ayarları")
                    .font(.headline.bold())
                Text("Cloudreve sunucunuzu Finder'da doğrudan bir klasör/disk gibi açın")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Durum Göstergesi
            HStack(spacing: 6) {
                Circle()
                    .fill(mounter.isMounted ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(mounter.isMounted ? "Finder'a Bağlı" : "Bağlantı Yok")
                    .font(.caption.weight(.semibold))
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
    
    // MARK: - 2. Ana Eylem Kartı (Finder'da Klasör Olarak Aç)
    private var mainActionCard: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mounter.isMounted ? "Cloudreve Diski Kullanıma Hazır" : "Finder Entegrasyonu")
                        .font(.title3.bold())
                    Text(mounter.isMounted ? "Dosyalarınızı Mac Finder'da normal bir klasör gibi açabilir, doğrudan çift tıklayarak çalıştırabilirsiniz." : "Aşağıdaki bilgileri kaydedin ve tek tıkla Finder'a yerel disk gibi bağlayın.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            // Büyük Eylem Butonları
            HStack(spacing: 14) {
                if !mounter.isMounted {
                    Button(action: connectAndOpenInFinder) {
                        HStack(spacing: 8) {
                            if isConnecting {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "folder.fill")
                                    .font(.title3)
                            }
                            Text(isConnecting ? "Finder'a Bağlanıyor..." : "Finder'da Klasör Olarak Aç")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            LinearGradient(colors: [Color.indigo, Color.blue], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.indigo.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(isConnecting || serverURL.isEmpty)
                } else {
                    Button(action: { mounter.openMountedVolumeInFinder() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                            Text("Finder Penceresini Aç")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: disconnectDrive) {
                        HStack {
                            Image(systemName: "eject.fill")
                            Text("Sürücüyü Çıkar")
                        }
                        .frame(width: 140)
                        .frame(height: 46)
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            // Geri Bildirim
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
                .background(isSuccessFeedback ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
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
    
    // MARK: - 3. Sunucu Bağlantı Ayarları Kartı
    private var connectionSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Cloudreve Bağlantı Bilgileri", systemImage: "slider.horizontal.3")
                    .font(.headline)
                
                Spacer()
                
                Button(action: testConnection) {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isTesting ? "Test..." : "Bağlantıyı Sına")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isTesting || serverURL.isEmpty)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloudreve WebDAV Adresi")
                        .font(.caption.bold())
                    TextField("http://sunucu-ip:5212/dav veya https://alanadi.com/dav", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("Cloudreve profilinizdeki WebDAV URL'si (genellikle sonu /dav ile biter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kullanıcı Adı / E-Posta")
                        .font(.caption.bold())
                    TextField("ornek@mail.com veya WebDAV hesabı", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("WebDAV Şifresi")
                        .font(.caption.bold())
                    SecureField("WebDAV şifreniz", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finder Sürücü Adı")
                        .font(.caption.bold())
                    TextField("Cloudreve", text: $serverName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Toggle("Bilgisayar Açıldığında Otomatik Bağla", isOn: $autoMount)
                    .font(.subheadline)
                    .padding(.top, 4)
            }
            
            HStack {
                Spacer()
                Button("Ayarları Kaydet") {
                    saveConfig()
                    feedbackMessage = "Bağlantı ayarları başarıyla kaydedildi."
                    isSuccessFeedback = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
    }
    
    // MARK: - 4. Windows PC Sürücü Eşleme Kartı
    private var windowsHelperCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Windows PC'de Z: Sürücüsü Yapmak İsterseniz", systemImage: "display")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            
            Text("Windows Dosya Gezgini'nde sanki bir harddiskmiş gibi açmak için komut satırında şunu çalıştırabilirsiniz:")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack {
                Text(windowsCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.indigo)
                    .lineLimit(1)
                
                Spacer()
                
                Button("Komutu Kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(windowsCommand, forType: .string)
                    feedbackMessage = "Windows bağlantı komutu panoya kopyalandı!"
                    isSuccessFeedback = true
                }
                .controlSize(.small)
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(14)
    }
    
    private var windowsCommand: String {
        let url = serverURL.isEmpty ? "http://SUNUCU:5212/dav" : serverURL
        let user = username.isEmpty ? "KULLANICI" : username
        let pass = password.isEmpty ? "SIFRE" : password
        return "net use Z: \(url) /user:\(user) \(pass) /persistent:yes"
    }
    
    // MARK: - Eylemler
    private func loadConfig() {
        if let current = manager.activeServer {
            self.serverName = current.name
            self.serverURL = current.serverURL
            self.username = current.username
            self.password = current.password
            self.autoMount = current.autoMountOnStart
        }
    }
    
    private func saveConfig() {
        var current = manager.activeServer ?? CloudreveServerConfig()
        current.name = serverName
        current.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        current.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        current.password = password
        current.autoMountOnStart = autoMount
        manager.saveServer(current)
    }
    
    private func connectAndOpenInFinder() {
        saveConfig()
        guard let config = manager.activeServer else { return }
        
        isConnecting = true
        feedbackMessage = "Cloudreve sunucusuna bağlanılıyor..."
        isSuccessFeedback = true
        
        mounter.connectAndOpenInFinder(config: config) { success, error in
            isConnecting = false
            if success {
                isSuccessFeedback = true
                feedbackMessage = "Bağlantı başarılı! Cloudreve klasörünüz Finder'da açıldı."
            } else {
                isSuccessFeedback = false
                feedbackMessage = "Bağlantı hatası: \(error ?? "Sunucuya ulaşılamadı")"
            }
        }
    }
    
    private func disconnectDrive() {
        mounter.disconnect { _ in
            isSuccessFeedback = true
            feedbackMessage = "Sürücü güvenle çıkarıldı."
        }
    }
    
    private func testConnection() {
        saveConfig()
        guard let config = manager.activeServer else { return }
        
        isTesting = true
        feedbackMessage = nil
        
        let client = WebDAVClient(config: config)
        client.testConnection { success, message in
            isTesting = false
            isSuccessFeedback = success
            feedbackMessage = message
        }
    }
}
