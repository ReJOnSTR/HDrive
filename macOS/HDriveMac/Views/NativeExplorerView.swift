//
//  NativeExplorerView.swift
//  HDriveMac - Gerçek Klasör ve Dosya Yöneticisi Görünümü
//

import SwiftUI
import AppKit

public struct NativeExplorerView: View {
    @ObservedObject var manager = CloudreveManager.shared
    @ObservedObject var mounter = DriveMounter.shared
    @ObservedObject var opener = FileOpener.shared
    @ObservedObject var syncEngine = FolderSyncEngine.shared
    
    // Klasör Gezintisi
    @State private var currentPath: String = ""
    @State private var pathHistory: [String] = [""]
    @State private var historyIndex: Int = 0
    @State private var files: [RemoteFileItem] = []
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var isGridView: Bool = true
    
    // Seçili ve Vurgulanan Dosya
    @State private var selectedFileID: String? = nil
    @State private var hoveredFileID: String? = nil
    
    // Modallar ve Diyaloglar
    @State private var showingSettingsSheet: Bool = false
    @State private var showingNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    @State private var statusAlertMessage: String? = nil
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            // SOL MENÜ (Sidebar)
            sidebarView
        } detail: {
            // SAĞ ANA BÖLÜM (Klasör Dosya Gezgini)
            VStack(spacing: 0) {
                // Klasör Yolu Çubuğu (Finder Path Bar & Arama)
                pathBarView
                
                Divider()
                
                // Dosya Listesi (Izgara veya Liste Görünümü)
                mainFilesAreaView
                
                // Alt Durum Çubuğu
                bottomStatusBarView
            }
            .navigationTitle(currentPath.isEmpty ? (manager.activeServer?.name ?? "Cloudreve") : (currentPath as NSString).lastPathComponent)
            .toolbar {
                // SOL: Geri & İleri Butonları (Yerleşik Sidebar Aç/Kapa simgesinin hemen yanında sabit)
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(historyIndex <= 0)
                    .help("Geri")
                    
                    Button(action: goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(historyIndex >= pathHistory.count - 1)
                    .help("İleri")
                }
                
                // SAĞ: Klasör İşlemleri, Görünüm ve Ayarlar (Sağ üste kilitli)
                ToolbarItemGroup(placement: .primaryAction) {
                    // Görünüm Değiştirici (Izgara / Liste)
                    Picker("Görünüm", selection: $isGridView) {
                        Image(systemName: "square.grid.2x2").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .help("Görünüm Biçimi")
                    
                    // Yeni Klasör Butonu
                    Button(action: { showingNewFolderAlert = true }) {
                        Label("Yeni Klasör", systemImage: "folder.badge.plus")
                    }
                    .help("Yeni Klasör Oluştur")
                    
                    // Dosya Yükle Butonu
                    Button(action: uploadFile) {
                        Label("Yükle", systemImage: "arrow.up.circle.fill")
                    }
                    .help("Dosya Yükle")
                    
                    // Yenile Butonu
                    Button(action: { loadDirectory(at: currentPath) }) {
                        Label("Yenile", systemImage: "arrow.clockwise")
                    }
                    .help("Yenile")
                    
                    // Ayarlar Dişli Çarkı
                    Button(action: { showingSettingsSheet = true }) {
                        Label("Ayarlar", systemImage: "gearshape")
                    }
                    .help("Cloudreve Ayarları")
                }
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Ara...")
            .focusEffectDisabled()
        }
        .background(ToolbarCustomizer())
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            if manager.activeServer?.serverURL.isEmpty == true {
                showingSettingsSheet = true
            } else {
                loadDirectory(at: currentPath)
            }
        }
        .sheet(isPresented: $showingSettingsSheet) {
            CloudreveSettingsSheet(isPresented: $showingSettingsSheet) {
                loadDirectory(at: currentPath)
            }
        }
        .alert("Yeni Klasör Oluştur", isPresented: $showingNewFolderAlert) {
            TextField("Klasör Adı", text: $newFolderName)
            Button("Oluştur", action: createFolder)
            Button("İptal", role: .cancel) { newFolderName = "" }
        }
    }
    
    // MARK: - 1. Sol Menü (Sidebar)
    private var sidebarView: some View {
        List {
            Section("Konumlar") {
                Button(action: { navigateToRoot() }) {
                    Label(manager.activeServer?.name ?? "Cloudreve", systemImage: "cloud.fill")
                        .foregroundColor(.indigo)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    }
    
    // MARK: - 2. Klasör Yolu Çubuğu (Path Bar)
    private var pathBarView: some View {
        HStack(spacing: 8) {
            // Ekmek Kırıntısı (Breadcrumbs)
            breadcrumbsView
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
    }
    
    // MARK: - Ekmek Kırıntısı (Breadcrumbs)
    private var breadcrumbsView: some View {
        HStack(spacing: 4) {
            Button(action: { navigateToRoot() }) {
                Image(systemName: "house.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            if !currentPath.isEmpty {
                let segments = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
                ForEach(0..<segments.count, id: \.self) { idx in
                    Text("/")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                    
                    let subPath = segments[0...idx].joined(separator: "/")
                    Button(action: { navigateTo(subPath) }) {
                        Text(segments[idx])
                            .font(.subheadline.weight(idx == segments.count - 1 ? .bold : .regular))
                            .foregroundColor(idx == segments.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 3. Dosyalar Alanı (Izgara / Liste)
    private var mainFilesAreaView: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Dosyalar yükleniyor...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 54))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Bu Klasör Boş")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Yukarıdaki 'Yükle' butonuna basarak dosya ekleyebilirsiniz.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isGridView {
                // IZGARA GÖRÜNÜMÜ (Finder Icon View Gibi)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 16)], spacing: 18) {
                        ForEach(filteredFiles) { file in
                            fileGridItem(file)
                        }
                    }
                    .padding(20)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedFileID = nil
                }
            } else {
                // LİSTE GÖRÜNÜMÜ (Finder List View Gibi)
                List(filteredFiles) { file in
                    fileRowItem(file)
                }
                .listStyle(.inset)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Dosya Izgara Kartı (Finder Görünümü)
    private func fileGridItem(_ file: RemoteFileItem) -> some View {
        let isHovered = hoveredFileID == file.id
        let isSelected = selectedFileID == file.id
        
        return VStack(spacing: 6) {
            Image(systemName: file.systemIcon)
                .font(.system(size: 42))
                .foregroundColor(file.isDirectory ? .blue : .secondary)
                .frame(width: 60, height: 50)
            
            Text(file.name)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)
            
            Text(file.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredFileID = file.id
            } else if hoveredFileID == file.id {
                hoveredFileID = nil
            }
        }
        .onTapGesture(count: 2) {
            // ÇİFT TIKLANDIĞINDA:
            handleDoubleClick(file)
        }
        .onTapGesture {
            selectedFileID = file.id
        }
        .contextMenu {
            fileContextMenu(file)
        }
    }
    
    // MARK: - Dosya Liste Satırı
    private func fileRowItem(_ file: RemoteFileItem) -> some View {
        let isHovered = hoveredFileID == file.id
        
        return HStack(spacing: 12) {
            Image(systemName: file.systemIcon)
                .font(.title3)
                .foregroundColor(file.isDirectory ? .blue : .secondary)
                .frame(width: 24)
            
            Text(file.name)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredFileID = file.id
            } else if hoveredFileID == file.id {
                hoveredFileID = nil
            }
        }
        .onTapGesture(count: 2) {
            handleDoubleClick(file)
        }
        .onTapGesture {
            selectedFileID = file.id
        }
        .contextMenu {
            fileContextMenu(file)
        }
    }
    
    // MARK: - Sağ Tık Menüsü (Context Menu)
    @ViewBuilder
    private func fileContextMenu(_ file: RemoteFileItem) -> some View {
        Button("Aç (Varsayılan Programla)") {
            handleDoubleClick(file)
        }
        
        Button("Finder'da Göster") {
            DriveMounter.shared.openMountedVolumeInFinder()
        }
        
        Divider()
        
        if !file.isDirectory {
            Button("İndir (İndirilenler Klasörüne)") {
                downloadFile(file)
            }
        }
        
        Button(role: .destructive, action: { deleteFile(file) }) {
            Label("Sil", systemImage: "trash")
        }
    }
    
    // MARK: - 4. Alt Durum Çubuğu
    private var bottomStatusBarView: some View {
        HStack {
            if let opening = opener.openingFile {
                ProgressView()
                    .scaleEffect(0.6)
                Text("'\(opening)' yerel programla açılıyor...")
                    .font(.caption2)
                    .foregroundColor(.indigo)
            } else {
                Text("\(filteredFiles.count) öge")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Eşitleme ve Finder Durumu
            HStack(spacing: 14) {
                if syncEngine.isSyncEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(syncEngine.isSyncing ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(syncEngine.syncStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(mounter.isMounted ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(mounter.isMounted ? "Ağ Sürücüsü Bağlı" : "Uzak Mod")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Dosyaya Çift Tıklama Mantığı (KEY FEATURE)
    private func handleDoubleClick(_ file: RemoteFileItem) {
        if file.isDirectory {
            // Klasör ise içine gir
            let newPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            navigateTo(newPath)
        } else {
            // DOSYA İSE: BİLGİSAYARIN KENDİ PROGRAMIYLA (Word, VLC, Preview, Acrobat) AÇ!
            guard let server = manager.activeServer else { return }
            let client = WebDAVClient(config: server)
            
            FileOpener.shared.openFileNatively(file: file, client: client) { success, error in
                if !success {
                    print("Açma hatası: \(error ?? "")")
                }
            }
        }
    }
    
    // MARK: - Gezinti ve İşlemler
    private var filteredFiles: [RemoteFileItem] {
        if searchText.isEmpty { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private func loadDirectory(at path: String) {
        guard let server = manager.activeServer, !server.serverURL.isEmpty else { return }
        isLoading = true
        let client = WebDAVClient(config: server)
        
        client.listFiles(at: path) { result in
            isLoading = false
            switch result {
            case .success(let items):
                self.files = items.sorted {
                    if $0.isDirectory && !$1.isDirectory { return true }
                    if !$0.isDirectory && $1.isDirectory { return false }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            case .failure(let error):
                print("Listeleme hatası: \(error)")
            }
        }
    }
    
    private func navigateTo(_ path: String) {
        currentPath = path
        if historyIndex < pathHistory.count - 1 {
            pathHistory = Array(pathHistory.prefix(historyIndex + 1))
        }
        pathHistory.append(path)
        historyIndex = pathHistory.count - 1
        loadDirectory(at: path)
    }
    
    private func navigateToRoot() {
        navigateTo("")
    }
    
    private func goBack() {
        if historyIndex > 0 {
            historyIndex -= 1
            currentPath = pathHistory[historyIndex]
            loadDirectory(at: currentPath)
        }
    }
    
    private func goForward() {
        if historyIndex < pathHistory.count - 1 {
            historyIndex += 1
            currentPath = pathHistory[historyIndex]
            loadDirectory(at: currentPath)
        }
    }
    
    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        let target = (currentPath.isEmpty ? "" : currentPath + "/") + name
        client.createFolder(at: target) { error in
            newFolderName = ""
            if error == nil {
                loadDirectory(at: currentPath)
            }
        }
    }
    
    private func uploadFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let selectedURL = panel.url, let server = manager.activeServer {
            let client = WebDAVClient(config: server)
            let dest = (currentPath.isEmpty ? "" : currentPath + "/") + selectedURL.lastPathComponent
            client.uploadFile(localFileURL: selectedURL, toRemotePath: dest) { error in
                if error == nil {
                    loadDirectory(at: currentPath)
                }
            }
        }
    }
    
    private func downloadFile(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let target = downloads.appendingPathComponent(file.name)
        let client = WebDAVClient(config: server)
        client.downloadFile(href: file.href, to: target, progress: { _ in }) { error in
            if error == nil {
                NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: downloads.path)
            }
        }
    }
    
    private func deleteFile(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        client.delete(at: file.href) { error in
            if error == nil {
                loadDirectory(at: currentPath)
            }
        }
    }
    
    private func openInFinder() {
        if let server = manager.activeServer {
            DriveMounter.shared.connectAndOpenInFinder(config: server) { _, _ in }
        }
    }
}

// MARK: - Cloudreve Ayarlar Modalı (Sheet)
struct CloudreveSettingsSheet: View {
    @Binding var isPresented: Bool
    let onSave: () -> Void
    
    @ObservedObject var manager = CloudreveManager.shared
    @ObservedObject var syncEngine = FolderSyncEngine.shared
    
    @State private var serverName: String = "Cloudreve"
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isTesting: Bool = false
    @State private var testResult: String? = nil
    @State private var isTestSuccess: Bool = true
    
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Cloudreve Bağlantı & Eşitleme Ayarları", systemImage: "cloud.fill")
                    .font(.headline)
                    .foregroundColor(.indigo)
                Spacer()
                Button("Kapat") { isPresented = false }
            }
            
            Divider()
            
            // 1. WebDAV Sunucu Bilgileri
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cloudreve WebDAV Adresi:")
                        .font(.caption.bold())
                    TextField("http://SUNUCU:5212/dav veya https://alanadi.com/dav", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kullanıcı Adı / E-posta:")
                        .font(.caption.bold())
                    TextField("admin@example.com", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("WebDAV Şifresi:")
                        .font(.caption.bold())
                    SecureField("WebDAV şifreniz", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            if let result = testResult {
                HStack(spacing: 6) {
                    Image(systemName: isTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isTestSuccess ? .green : .red)
                    Text(result)
                        .font(.caption2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isTestSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            Divider()
            
            // 2. Finder & Yerel Klasör Entegrasyonu (OneDrive / Google Drive Modu)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Finder Entegrasyonu & Yerel Eşitleme", systemImage: "folder.badge.gearshape")
                        .font(.subheadline.bold())
                    Spacer()
                    Toggle("", isOn: $syncEngine.isSyncEnabled)
                        .toggleStyle(.switch)
                }
                
                Text("Dosyalarınızı Mac'inizde '~/HDrive - Cloudreve' klasöründe normal bir klasör gibi tutar. Finder'da doğrudan görebilir, Word/Excel/PDF olarak açabilir ve düzenleyebilirsiniz.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 10) {
                    Button(action: { syncEngine.openLocalFolderInFinder() }) {
                        Label("Finder'da Aç", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    
                    if syncEngine.isSyncEnabled {
                        Button(action: { syncEngine.syncNow() }) {
                            Label("Şimdi Eşitle", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(syncEngine.isSyncing)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(syncEngine.isSyncEnabled ? (syncEngine.isSyncing ? Color.orange : Color.green) : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(syncEngine.syncStatus)
                            .font(.caption.bold())
                            .foregroundColor(syncEngine.isSyncing ? .orange : .secondary)
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            
            Divider()
            
            // 3. Alt Butonlar
            HStack(spacing: 12) {
                Button("Bağlantıyı Test Et") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || serverURL.isEmpty)
                
                Spacer()
                
                Button("Kaydet ve Bağlan") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if let current = manager.activeServer {
                self.serverName = current.name
                self.serverURL = current.serverURL
                self.username = current.username
                self.password = current.password
            }
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        var cfg = manager.activeServer ?? CloudreveServerConfig()
        cfg.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.password = password
        
        let client = WebDAVClient(config: cfg)
        client.testConnection { success, message in
            isTesting = false
            isTestSuccess = success
            testResult = message
        }
    }
    
    private func saveSettings() {
        var cfg = manager.activeServer ?? CloudreveServerConfig()
        cfg.name = serverName
        cfg.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.password = password
        manager.saveServer(cfg)
        isPresented = false
        onSave()
    }
}

// MARK: - Yerel Toolbar ve Sidebar Butonu Özelleştirici
struct ToolbarCustomizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            customize(view: view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            customize(view: nsView)
        }
    }
    
    private func customize(view: NSView) {
        guard let window = view.window else { return }
        
        if let contentView = window.contentView {
            removeFocusRings(from: contentView)
        }
        
        guard let toolbar = window.toolbar else { return }
        for item in toolbar.items {
            let id = item.itemIdentifier.rawValue.lowercased()
            if id.contains("sidebar") {
                if let btn = item.view as? NSButton {
                    btn.showsBorderOnlyWhileMouseInside = true
                }
            }
            if let itemView = item.view {
                removeFocusRings(from: itemView)
            }
        }
    }
    
    private func removeFocusRings(from view: NSView) {
        if let control = view as? NSControl {
            control.focusRingType = .none
        }
        for subview in view.subviews {
            removeFocusRings(from: subview)
        }
    }
}

