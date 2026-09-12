//
//  CloudreveView.swift
//  HDriveMac
//

import SwiftUI
import AppKit

public struct CloudreveView: View {
    @ObservedObject var manager = CloudreveManager.shared
    @ObservedObject var mounter = DriveMounter.shared
    
    @State private var serverName: String = "Cloudreve Sunucum"
    @State private var serverURL: String = "https://your-cloudreve.com/dav"
    @State private var username: String = ""
    @State private var password: String = ""
    
    // Test ve Bağlantı Durumları
    @State private var isTesting = false
    @State private var testResult: String? = nil
    @State private var isTestSuccess = false
    @State private var isMounting = false
    
    // Uzak Dosya Gezgini Durumları
    @State private var currentRemotePath: String = ""
    @State private var remoteFiles: [RemoteFileItem] = []
    @State private var isLoadingFiles = false
    @State private var showingNewFolderPrompt = false
    @State private var newFolderName = ""
    
    public init() {}
    
    public var body: some View {
        HSplitView {
            // Sol Bölüm: Sunucu Bilgileri & Finder Sürücü Bağlama
            VStack(alignment: .leading, spacing: 18) {
                serverConfigCard
                
                finderMountActionCard
                
                windowsScriptCard
                
                Spacer()
            }
            .padding(18)
            .frame(minWidth: 320, maxWidth: 380)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Sağ Bölüm: Cloudreve Uzak Dosya Gezgini
            VStack(spacing: 0) {
                remoteToolbarView
                
                Divider()
                
                remoteFilesListView
            }
            .frame(minWidth: 420)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            loadActiveConfig()
        }
    }
    
    // MARK: - 1. Sunucu Yapılandırma Kartı
    private var serverConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Cloudreve Sunucu Ayarları", systemImage: "cloud.fill")
                    .font(.headline)
                    .foregroundColor(.indigo)
                
                Spacer()
                
                Button("Kaydet", action: saveConfig)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Sunucu Adı")
                    .font(.caption.bold())
                TextField("Cloudreve", text: $serverName)
                    .textFieldStyle(.roundedBorder)
                
                Text("WebDAV Adresi (Cloudreve /dav yolu)")
                    .font(.caption.bold())
                TextField("https://cloudreve.domain.com/dav", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                
                Text("Kullanıcı Adı / E-posta")
                    .font(.caption.bold())
                TextField("admin@example.com", text: $username)
                    .textFieldStyle(.roundedBorder)
                
                Text("WebDAV Şifresi")
                    .font(.caption.bold())
                SecureField("WebDAV Şifreniz", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Bağlantıyı Test Et Butonu
            Button(action: testConnection) {
                HStack {
                    if isTesting {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                    }
                    Text(isTesting ? "Test Ediliyor..." : "Bağlantıyı Test Et")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isTesting || serverURL.isEmpty)
            
            if let res = testResult {
                HStack(spacing: 6) {
                    Image(systemName: isTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isTestSuccess ? .green : .red)
                    Text(res)
                        .font(.caption2)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .background(isTestSuccess ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                .cornerRadius(6)
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 2. Finder'a Disk Olarak Bağlama Kartı
    private var finderMountActionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Finder Disk Entegrasyonu", systemImage: "internaldrive.fill")
                    .font(.headline)
                    .foregroundColor(.indigo)
                
                Spacer()
                
                Circle()
                    .fill(mounter.isMounted ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            
            Text("Cloudreve sunucunuzdaki verileri Mac Finder'a harici bir sabit disk (/Volumes) gibi bağlayın.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 10) {
                if !mounter.isMounted {
                    Button(action: mountInFinder) {
                        HStack {
                            if isMounting {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Image(systemName: "link.circle.fill")
                            }
                            Text(isMounting ? "Bağlanıyor..." : "Finder'a Disk Olarak Bağla")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(isMounting || serverURL.isEmpty)
                } else {
                    Button(action: { mounter.openInFinder() }) {
                        Label("Finder'da Aç", systemImage: "folder.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    Button("Çıkar", action: { mounter.unmount { _ in } })
                        .buttonStyle(.bordered)
                        .frame(height: 34)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 3. Windows PC Bağlantı Komutu Kartı
    private var windowsScriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Windows PC İçin Bağlantı", systemImage: "display")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            Text("Windows'ta tek komutla Z: sürücüsü yapmak için:")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack {
                Text("net use Z: \(serverURL)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.indigo)
                    .lineLimit(1)
                
                Spacer()
                
                Button("Kopyala") {
                    let cmd = "net use Z: \(serverURL) /user:\(username) \(password)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                }
                .controlSize(.mini)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - 4. Sağ Taraf: Uzak Dosya Gezgini Araç Çubuğu
    private var remoteToolbarView: some View {
        HStack {
            // Ekmek Kırıntısı (Breadcrumbs)
            Button(action: { navigateTo("") }) {
                Image(systemName: "house.fill")
            }
            .buttonStyle(.borderless)
            
            Text("Cloudreve / " + currentRemotePath)
                .font(.subheadline.bold())
                .lineLimit(1)
            
            Spacer()
            
            Button(action: refreshFiles) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Yenile")
            
            Button(action: { showingNewFolderPrompt = true }) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Yeni Klasör")
            
            Button(action: uploadFileToCloudreve) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.doc.fill")
                    Text("Dosya Yükle")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - 5. Uzak Dosya Listesi
    private var remoteFilesListView: some View {
        Group {
            if isLoadingFiles {
                VStack {
                    Spacer()
                    ProgressView("Cloudreve sunucusundan dosyalar yükleniyor...")
                    Spacer()
                }
            } else if remoteFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cloud")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bu klasör boş veya henüz bağlanılmadı")
                        .font(.headline)
                    Text("Yukarıdaki 'Yenile' butonuna basarak dosyaları çekebilir veya sol menüden 'Finder'da Disk Olarak Bağla' diyebilirsiniz.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
            } else {
                List {
                    ForEach(remoteFiles) { file in
                        HStack(spacing: 12) {
                            Image(systemName: file.systemIcon)
                                .font(.title3)
                                .foregroundColor(file.isDirectory ? .blue : .purple)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.body.weight(.medium))
                                Text(file.formattedSize)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if !file.isDirectory {
                                Button(action: { downloadFile(file) }) {
                                    Image(systemName: "arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Mac'e İndir")
                            }
                            
                            Button(action: { deleteFile(file) }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                            .help("Sil")
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if file.isDirectory {
                                navigateTo(file.name)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .alert("Yeni Klasör Oluştur", isPresented: $showingNewFolderPrompt) {
            TextField("Klasör Adı", text: $newFolderName)
            Button("Oluştur", action: createRemoteFolder)
            Button("İptal", role: .cancel) { newFolderName = "" }
        }
    }
    
    // MARK: - Eylemler
    private func loadActiveConfig() {
        if let current = manager.activeServer {
            self.serverName = current.name
            self.serverURL = current.serverURL
            self.username = current.username
            self.password = current.password
        }
    }
    
    private func saveConfig() {
        var current = manager.activeServer ?? CloudreveServerConfig()
        current.name = serverName
        current.serverURL = serverURL
        current.username = username
        current.password = password
        manager.saveServer(current)
        testResult = "Ayarlar kaydedildi."
        isTestSuccess = true
    }
    
    private func testConnection() {
        saveConfig()
        isTesting = true
        testResult = nil
        
        let client = WebDAVClient(config: manager.activeServer!)
        client.testConnection { success, message in
            isTesting = false
            isTestSuccess = success
            testResult = message
            if success {
                refreshFiles()
            }
        }
    }
    
    private func mountInFinder() {
        saveConfig()
        isMounting = true
        
        mounter.mount(url: serverURL, username: username, password: password) { success, error in
            isMounting = false
            if success {
                testResult = "Başarılı! Cloudreve Finder'a harici bir disk olarak bağlandı."
                isTestSuccess = true
                mounter.openInFinder()
            } else {
                testResult = "Finder bağlantı hatası: \(error ?? "Bilinmeyen hata")"
                isTestSuccess = false
            }
        }
    }
    
    private func refreshFiles() {
        guard let server = manager.activeServer else { return }
        isLoadingFiles = true
        let client = WebDAVClient(config: server)
        client.listFiles(at: currentRemotePath) { result in
            isLoadingFiles = false
            switch result {
            case .success(let files):
                self.remoteFiles = files
            case .failure(let error):
                self.testResult = "Dosyalar çekilemedi: \(error.localizedDescription)"
                self.isTestSuccess = false
            }
        }
    }
    
    private func navigateTo(_ folderName: String) {
        if folderName.isEmpty {
            currentRemotePath = ""
        } else {
            currentRemotePath = (currentRemotePath.isEmpty ? "" : currentRemotePath + "/") + folderName
        }
        refreshFiles()
    }
    
    private func createRemoteFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        let target = (currentRemotePath.isEmpty ? "" : currentRemotePath + "/") + name
        client.createFolder(at: target) { error in
            if error == nil {
                self.newFolderName = ""
                self.refreshFiles()
            }
        }
    }
    
    private func uploadFileToCloudreve() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let selectedURL = panel.url, let server = manager.activeServer {
            let client = WebDAVClient(config: server)
            let dest = (currentRemotePath.isEmpty ? "" : currentRemotePath + "/") + selectedURL.lastPathComponent
            client.uploadFile(localFileURL: selectedURL, toRemotePath: dest) { error in
                if error == nil {
                    self.refreshFiles()
                } else {
                    self.testResult = "Yükleme hatası: \(error?.localizedDescription ?? "")"
                    self.isTestSuccess = false
                }
            }
        }
    }
    
    private func downloadFile(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else { return }
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let target = downloadsURL.appendingPathComponent(file.name)
        
        let client = WebDAVClient(config: server)
        client.downloadFile(href: file.href, to: target, progress: { _ in }) { error in
            if error == nil {
                NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: downloadsURL.path)
            }
        }
    }
    
    private func deleteFile(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        client.delete(at: file.href, isDirectory: file.isDirectory) { error in
            if error == nil {
                self.refreshFiles()
            }
        }
    }
}
