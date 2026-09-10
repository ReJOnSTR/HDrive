//
//  NativeExplorerView.swift
//  HDriveMac - Gerçek Klasör ve Dosya Yöneticisi Görünümü
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import QuickLookUI


public struct ExplorerTab: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var path: String
    public var history: [String]
    public var historyIndex: Int
    public var selectedFileID: String?
    
    public init(id: UUID = UUID(), title: String = "Cloudreve", path: String = "", history: [String] = [""], historyIndex: Int = 0, selectedFileID: String? = nil) {
        self.id = id
        self.title = title
        self.path = path
        self.history = history
        self.historyIndex = historyIndex
        self.selectedFileID = selectedFileID
    }
}

public struct NativeExplorerView: View {
    @ObservedObject var manager = CloudreveManager.shared
    @ObservedObject var mounter = DriveMounter.shared
    @ObservedObject var opener = FileOpener.shared
    @ObservedObject var syncEngine = FolderSyncEngine.shared
    @ObservedObject var previewManager = FilePreviewManager.shared
    
    // Sekmeler (Tabs)
    private static let initialTab = ExplorerTab(title: "Cloudreve", path: "")
    @State private var tabs: [ExplorerTab] = [initialTab]
    @State private var activeTabID: UUID = initialTab.id
    
    // Sıralama (Sort)
    @State private var sortField: FileSortField = .name
    @State private var sortAscending: Bool = true
    @State private var foldersFirst: Bool = true
    
    // Klasör Gezintisi
    @State private var currentPath: String = ""
    @State private var pathHistory: [String] = [""]
    @State private var historyIndex: Int = 0
    @State private var files: [RemoteFileItem] = []
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var isGridView: Bool = true
    @State private var showPreviewPane: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Seçili ve Vurgulanan Dosya
    @State private var selectedFileID: String? = nil
    @State private var hoveredFileID: String? = nil
    @State private var quickLookURL: URL? = nil
    
    // Modallar ve Diyaloglar
    @State private var showingSettingsSheet: Bool = false
    @State private var showingNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    @State private var statusAlertMessage: String? = nil
    
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "tr_TR")
        return f
    }()
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SOL MENÜ (Sidebar)
            sidebarView
        } detail: {
            // SAĞ ANA BÖLÜM (Klasör Dosya Gezgini)
            VStack(spacing: 0) {
                // Sekmeler Çubuğu (Tabs Bar)
                tabBarView
                
                Divider()
                
                // Klasör Yolu Çubuğu (Finder Path Bar & Arama)
                pathBarView
                
                Divider()
                
                // Dosya Listesi ve Önizleme Bölmesi
                HStack(spacing: 0) {
                    mainFilesAreaView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if showPreviewPane {
                        Divider()
                        previewPaneSideView
                            .frame(width: 250)
                            .frame(maxHeight: .infinity)
                            .background(Color(NSColor.controlBackgroundColor))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Alt Durum Çubuğu
                bottomStatusBarView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
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
                    
                    // Sıralama Menüsü
                    Menu {
                        Section("Sıralama Ölçütü") {
                            ForEach(FileSortField.allCases) { field in
                                Button(action: { sortField = field }) {
                                    HStack {
                                        Text(field.rawValue)
                                        if sortField == field {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                        
                        Section("Sıralama Yönü") {
                            Button(action: { sortAscending = true }) {
                                HStack {
                                    Text("Artan (A-Z, Eski-Yeni)")
                                    if sortAscending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            Button(action: { sortAscending = false }) {
                                HStack {
                                    Text("Azalan (Z-A, Yeni-Eski)")
                                    if !sortAscending {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Section {
                            Toggle("Klasörleri Üstte Tut", isOn: $foldersFirst)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .help("Sırala")
                    
                    // Önizleme Bölmesi Butonu
                    Button(action: togglePreviewPane) {
                        Image(systemName: "sidebar.right")
                            .foregroundColor(showPreviewPane ? .accentColor : .primary)
                    }
                    .help("Önizleme Bölmesini Göster / Gizle")
                    
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
            .quickLookPreview($quickLookURL)
            .background(
                Group {
                    Button(action: { addNewTab() }) { EmptyView() }
                        .keyboardShortcut("t", modifiers: .command)
                    
                    Button(action: { closeTab(activeTabID) }) { EmptyView() }
                        .keyboardShortcut("w", modifiers: .command)
                    
                    Button(action: {
                        if let selID = selectedFileID, let file = files.first(where: { $0.id == selID }) {
                            triggerQuickLook(for: file)
                        }
                    }) {
                        EmptyView()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            )
        }
        .background(ToolbarCustomizer())
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            if let first = tabs.first {
                activeTabID = first.id
            }
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
    
    // MARK: - 0. Sekmeler Çubuğu (Tabs Bar)
    private func tabItemView(tab: ExplorerTab) -> some View {
        let isActive = (tab.id == activeTabID)
        return HStack(spacing: 7) {
            Image(systemName: tab.path.isEmpty ? "cloud.fill" : "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .accentColor : .secondary)
            
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isActive ? .primary : .secondary)
            
            if tabs.count > 1 {
                Button(action: { closeTab(tab.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(isActive ? Color.primary.opacity(0.7) : Color.secondary)
                        .padding(3)
                        .background(Circle().fill(Color.primary.opacity(isActive ? 0.12 : 0.06)))
                }
                .buttonStyle(.plain)
                .help("Sekmeyi Kapat (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            switchToTab(tab.id)
        }
    }

    private var tabBarView: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        tabItemView(tab: tab)
                    }
                    
                    // Yeni Sekme (+) Butonu
                    Button(action: { addNewTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .help("Yeni Sekme Aç (⌘T)")
                    .padding(.leading, 2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }
    
    // MARK: - Liste Sütun Başlıkları (Click-to-Sort Headers)
    private var listHeaderView: some View {
        HStack(spacing: 12) {
            Button(action: { toggleSort(field: FileSortField.name) }) {
                HStack(spacing: 4) {
                    Text("Ad")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(sortField == .name ? .accentColor : .secondary)
                    if sortField == .name {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 38)
            
            Spacer()
            
            Button(action: { toggleSort(field: FileSortField.kind) }) {
                HStack(spacing: 4) {
                    Text("Tür")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(sortField == .kind ? .accentColor : .secondary)
                    if sortField == .kind {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 140, alignment: .trailing)
            
            Button(action: { toggleSort(field: FileSortField.size) }) {
                HStack(spacing: 4) {
                    Text("Boyut")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(sortField == .size ? .accentColor : .secondary)
                    if sortField == .size {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 16)], alignment: .leading, spacing: 18) {
                        ForEach(filteredFiles) { file in
                            fileGridItem(file)
                        }
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFileID = nil
                        }
                )
            } else {
                // LİSTE GÖRÜNÜMÜ (Finder List View Gibi)
                VStack(spacing: 0) {
                    listHeaderView
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredFiles) { file in
                                fileRowItem(file)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFileID = nil
                        }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedFiles(providers)
            return true
        }
    }
    
    // MARK: - Dosya Izgara Kartı (Finder Görünümü)
    private func fileGridItem(_ file: RemoteFileItem) -> some View {
        let isHovered = hoveredFileID == file.id
        let isSelected = selectedFileID == file.id
        
        return VStack(spacing: 6) {
            ZStack {
                if file.isImage, let img = previewManager.cachedImages[file.id] {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 50)
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                } else {
                    Image(systemName: file.systemIcon)
                        .font(.system(size: 42))
                        .foregroundColor(fileIconColor(file))
                        .frame(width: 60, height: 50)
                }
            }
            .onAppear {
                if file.isImage, let server = manager.activeServer {
                    let client = WebDAVClient(config: server)
                    previewManager.loadThumbnail(for: file, client: client)
                }
            }
            
            Text(file.name)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 92)
            
            Text(file.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredFileID = file.id
            } else if hoveredFileID == file.id {
                hoveredFileID = nil
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedFileID = file.id
                if file.isImage, let server = manager.activeServer {
                    let client = WebDAVClient(config: server)
                    previewManager.loadThumbnail(for: file, client: client)
                }
            }
        )
        .onTapGesture(count: 2) {
            handleDoubleClick(file)
        }
        .onDrag {
            exportFileForDrag(file)
        }
        .contextMenu {
            fileContextMenu(file)
        }
    }
    
    // MARK: - Dosya Liste Satırı
    private func fileRowItem(_ file: RemoteFileItem) -> some View {
        let isHovered = hoveredFileID == file.id
        let isSelected = selectedFileID == file.id
        
        return HStack(spacing: 12) {
            if file.isImage, let img = previewManager.cachedImages[file.id] {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .cornerRadius(3)
            } else {
                Image(systemName: file.systemIcon)
                    .font(.title3)
                    .foregroundColor(fileIconColor(file))
                    .frame(width: 24)
            }
            
            Text(file.name)
                .font(.body)
                .foregroundColor(isSelected ? Color.accentColor : .primary)
                .fontWeight(isSelected ? .medium : .regular)
                .lineLimit(1)
            
            Spacer()
            
            Text(file.kindDescription)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .trailing)
            
            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredFileID = file.id
            } else if hoveredFileID == file.id {
                hoveredFileID = nil
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedFileID = file.id
                if file.isImage, let server = manager.activeServer {
                    let client = WebDAVClient(config: server)
                    previewManager.loadThumbnail(for: file, client: client)
                }
            }
        )
        .onTapGesture(count: 2) {
            handleDoubleClick(file)
        }
        .onDrag {
            exportFileForDrag(file)
        }
        .contextMenu {
            fileContextMenu(file)
        }
        .onAppear {
            if file.isImage, let server = manager.activeServer {
                let client = WebDAVClient(config: server)
                previewManager.loadThumbnail(for: file, client: client)
            }
        }
    }
    
    // MARK: - Sağ Tık Menüsü (Context Menu)
    @ViewBuilder
    private func fileContextMenu(_ file: RemoteFileItem) -> some View {
        if !file.isDirectory {
            Button(action: { triggerQuickLook(for: file) }) {
                Label("Hızlı Bakış (Boşluk)", systemImage: "eye")
            }
        }
        
        Button(action: { handleDoubleClick(file) }) {
            Label(file.isDirectory ? "Klasörü Aç" : "Varsayılan Uygulamayla Aç", systemImage: "arrow.up.forward.app")
        }
        
        Button(action: {
            DriveMounter.shared.openMountedVolumeInFinder()
        }) {
            Label("Finder'da Göster", systemImage: "folder")
        }
        
        Divider()
        
        if !file.isDirectory {
            Button(action: { downloadFile(file) }) {
                Label("İndir (İndirilenler Klasörüne)", systemImage: "arrow.down.circle")
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
    
    // MARK: - Gezinti ve Sıralama
    private var filteredFiles: [RemoteFileItem] {
        var result = files
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        return result.sorted(by: { (item1: RemoteFileItem, item2: RemoteFileItem) -> Bool in
            if foldersFirst {
                if item1.isDirectory && !item2.isDirectory { return true }
                if !item1.isDirectory && item2.isDirectory { return false }
            }
            
            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = item1.name.localizedStandardCompare(item2.name)
            case .date:
                let d1 = item1.modificationDate ?? Date.distantPast
                let d2 = item2.modificationDate ?? Date.distantPast
                if d1 == d2 {
                    comparison = item1.name.localizedStandardCompare(item2.name)
                } else {
                    comparison = d1.compare(d2)
                }
            case .size:
                let s1 = item1.size
                let s2 = item2.size
                if s1 == s2 {
                    comparison = item1.name.localizedStandardCompare(item2.name)
                } else if s1 < s2 {
                    comparison = .orderedAscending
                } else {
                    comparison = .orderedDescending
                }
            case .kind:
                let ext1 = item1.isDirectory ? "" : (item1.name as NSString).pathExtension.lowercased()
                let ext2 = item2.isDirectory ? "" : (item2.name as NSString).pathExtension.lowercased()
                if ext1 == ext2 {
                    comparison = item1.name.localizedStandardCompare(item2.name)
                } else {
                    comparison = ext1.localizedStandardCompare(ext2)
                }
            }
            
            return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        })
    }
    
    private func toggleSort(field: FileSortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
    }
    
    private func togglePreviewPane() {
        showPreviewPane.toggle()
        if showPreviewPane && selectedFileID == nil {
            selectedFileID = filteredFiles.first?.id
            if let first = filteredFiles.first, first.isImage, let server = manager.activeServer {
                let client = WebDAVClient(config: server)
                previewManager.loadThumbnail(for: first, client: client)
            }
        }
    }
    
    private func triggerQuickLook(for file: RemoteFileItem) {
        if file.isDirectory { return }
        
        // 1. Yerel dosya zaten var mı?
        if let local = previewManager.resolvedLocalURL(for: file) {
            self.quickLookURL = local
            return
        }
        
        // 2. Yoksa önizleme için indirip Quick Look aç
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        
        previewManager.ensureLocalFile(file: file, client: client) { localURL in
            if let url = localURL {
                DispatchQueue.main.async {
                    self.quickLookURL = url
                }
            }
        }
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
                if self.showPreviewPane {
                    if let sel = self.selectedFileID, self.files.contains(where: { $0.id == sel }) {
                        // Mevcut seçim korunuyor
                    } else {
                        self.selectedFileID = self.files.first?.id
                    }
                    if let selID = self.selectedFileID, let file = self.files.first(where: { $0.id == selID }), file.isImage {
                        self.previewManager.loadThumbnail(for: file, client: client)
                    }
                }
            case .failure(let error):
                print("Listeleme hatası: \(error)")
            }
        }
    }
    
    // MARK: - Sekme Yönetimi
    private func saveCurrentTabState() {
        if let idx = tabs.firstIndex(where: { $0.id == activeTabID }) {
            let tabTitle = currentPath.isEmpty ? (manager.activeServer?.name ?? "Cloudreve") : (currentPath as NSString).lastPathComponent
            tabs[idx].title = tabTitle
            tabs[idx].path = currentPath
            tabs[idx].history = pathHistory
            tabs[idx].historyIndex = historyIndex
            tabs[idx].selectedFileID = selectedFileID
        }
    }
    
    private func addNewTab(path: String = "") {
        saveCurrentTabState()
        let tabTitle = path.isEmpty ? (manager.activeServer?.name ?? "Cloudreve") : (path as NSString).lastPathComponent
        let newTab = ExplorerTab(
            title: tabTitle,
            path: path,
            history: [path],
            historyIndex: 0,
            selectedFileID: nil
        )
        tabs.append(newTab)
        activeTabID = newTab.id
        
        currentPath = path
        pathHistory = [path]
        historyIndex = 0
        selectedFileID = nil
        loadDirectory(at: path)
    }
    
    private func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        let closingActive = (id == activeTabID)
        tabs.remove(at: index)
        
        if closingActive {
            let newIndex = min(index, tabs.count - 1)
            let nextTab = tabs[newIndex]
            switchToTab(nextTab.id)
        }
    }
    
    private func switchToTab(_ id: UUID) {
        guard id != activeTabID, let targetTab = tabs.first(where: { $0.id == id }) else { return }
        saveCurrentTabState()
        
        activeTabID = targetTab.id
        currentPath = targetTab.path
        pathHistory = targetTab.history
        historyIndex = targetTab.historyIndex
        selectedFileID = targetTab.selectedFileID
        loadDirectory(at: targetTab.path)
    }

    private func navigateTo(_ path: String) {
        currentPath = path
        if historyIndex < pathHistory.count - 1 {
            pathHistory = Array(pathHistory.prefix(historyIndex + 1))
        }
        pathHistory.append(path)
        historyIndex = pathHistory.count - 1
        saveCurrentTabState()
        loadDirectory(at: path)
    }
    
    private func navigateToRoot() {
        navigateTo("")
    }
    
    private func goBack() {
        if historyIndex > 0 {
            historyIndex -= 1
            currentPath = pathHistory[historyIndex]
            saveCurrentTabState()
            loadDirectory(at: currentPath)
        }
    }
    
    private func goForward() {
        if historyIndex < pathHistory.count - 1 {
            historyIndex += 1
            currentPath = pathHistory[historyIndex]
            saveCurrentTabState()
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
    
    // MARK: - Sürükle ve Bırak (Drag & Drop) Desteği
    private func exportFileForDrag(_ file: RemoteFileItem) -> NSItemProvider {
        // 1. Yerel eşitleme klasöründe (HDrive - Cloudreve) var mı?
        let syncDir = FolderSyncEngine.shared.localFolderURL
        let relPath = file.href.hasPrefix("/") ? String(file.href.dropFirst()) : file.href
        let syncFile = syncDir.appendingPathComponent(relPath)
        
        if FileManager.default.fileExists(atPath: syncFile.path) {
            return NSItemProvider(item: syncFile as NSURL, typeIdentifier: UTType.fileURL.identifier)
        }
        
        // 2. Cache klasöründe var mı?
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("HDriveFiles", isDirectory: true)
        let cachedFile = cacheDir.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            return NSItemProvider(item: cachedFile as NSURL, typeIdentifier: UTType.fileURL.identifier)
        }
        
        // 3. Önceden indirilmemişse bile dosya URL'i dön
        return NSItemProvider(item: syncFile as NSURL, typeIdentifier: UTType.fileURL.identifier)
    }
    
    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let localURL = url, let server = manager.activeServer else { return }
                let client = WebDAVClient(config: server)
                let dest = (currentPath.isEmpty ? "" : currentPath + "/") + localURL.lastPathComponent
                client.uploadFile(localFileURL: localURL, toRemotePath: dest) { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            loadDirectory(at: currentPath)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Önizleme Bölmesi (Finder Inspector / Quick Look)
    @ViewBuilder
    private var previewPaneSideView: some View {
        if let selID = selectedFileID, let selected = files.first(where: { $0.id == selID }) {
            previewPaneView(selected)
        } else {
            emptyPreviewPaneView
        }
    }
    
    private func previewPaneView(_ file: RemoteFileItem) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Üst Başlık ve Kapat Butonu
                HStack {
                    Text("Ayrıntılar ve Önizleme")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: togglePreviewPane) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Önizleme Bölmesini Kapat")
                }
                .padding(.horizontal, 4)
                
                // Büyük Önizleme Kutusu / Kartı
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    
                    if file.isDirectory {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.blue)
                            Text("Klasör")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                    } else if file.isImage {
                        if let img = previewManager.cachedImages[file.id] {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 190)
                                .cornerRadius(8)
                                .padding(6)
                        } else if previewManager.loadingPreviewIDs.contains(file.id) {
                            VStack(spacing: 10) {
                                ProgressView()
                                    .scaleEffect(0.9)
                                Text("Görsel yükleniyor...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(24)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: file.systemIcon)
                                    .font(.system(size: 56))
                                    .foregroundColor(fileIconColor(file))
                                Button("Önizlemeyi Yükle") {
                                    if let server = manager.activeServer {
                                        let client = WebDAVClient(config: server)
                                        previewManager.loadThumbnail(for: file, client: client)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(20)
                        }
                    } else if let localURL = previewManager.resolvedLocalURL(for: file) {
                        // Yerel kopya varsa gömülü Quick Look görünümü
                        QuickLookRepresentable(url: localURL)
                            .frame(height: 190)
                            .cornerRadius(8)
                            .padding(4)
                    } else {
                        // Diğer dosyalar
                        VStack(spacing: 12) {
                            Image(systemName: file.systemIcon)
                                .font(.system(size: 58))
                                .foregroundColor(fileIconColor(file))
                            
                            if previewManager.loadingPreviewIDs.contains(file.id) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Önizleme indiriliyor...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Button("Önizlemeyi Yükle") {
                                    triggerQuickLook(for: file)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(24)
                    }
                }
                .frame(minHeight: 180, maxHeight: 210)
                .onAppear {
                    if file.isImage, let server = manager.activeServer {
                        let client = WebDAVClient(config: server)
                        previewManager.loadThumbnail(for: file, client: client)
                    }
                }
                
                // Dosya Adı ve Tür Rozeti
                VStack(spacing: 6) {
                    Text(file.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    
                    Text(file.kindDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
                
                // Hızlı Eylem Butonları
                VStack(spacing: 8) {
                    if !file.isDirectory {
                        Button(action: { triggerQuickLook(for: file) }) {
                            Label("Hızlı Bakış (Boşluk)", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    
                    HStack(spacing: 8) {
                        Button(action: { handleDoubleClick(file) }) {
                            Label(file.isDirectory ? "Aç" : "Uygulamayla Aç", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        if !file.isDirectory {
                            Button(action: { downloadFile(file) }) {
                                Label("İndir", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                            .help("İndirilenler klasörüne kaydet")
                        }
                    }
                }
                
                Divider()
                
                // Finder Tarzı Ayrıntılar Tablosu
                VStack(alignment: .leading, spacing: 10) {
                    Text("BİLGİLER")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 2)
                    
                    inspectorRow(title: "Boyut", value: file.formattedSize)
                    
                    if let date = file.modificationDate {
                        inspectorRow(title: "Değiştirilme", value: dateFormatter.string(from: date))
                    }
                    
                    inspectorRow(title: "Uzak Yol", value: file.href)
                    
                    if let ct = file.contentType, !ct.isEmpty {
                        inspectorRow(title: "İçerik Türü", value: ct)
                    }
                    
                    // Yerel Durum Bilgisi
                    HStack(alignment: .top) {
                        Text("Durum:")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .frame(width: 85, alignment: .leading)
                        
                        if previewManager.resolvedLocalURL(for: file) != nil {
                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("Yerelde Hazır")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Circle().fill(Color.blue).frame(width: 6, height: 6)
                                Text("Yalnızca Bulutta")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            }
            .padding(14)
        }
    }
    
    // MARK: - Önizleme Boş Durumu (Öğe Seçilmediğinde)
    private var emptyPreviewPaneView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Ayrıntılar ve Önizleme")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: togglePreviewPane) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help("Önizleme Bölmesini Kapat")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            
            Spacer()
            
            VStack(spacing: 12) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 46))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("Öğe Seçilmedi")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Önizleme ve ayrıntılarını görüntülemek için listeden bir dosya veya klasör seçin.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
    }
    
    private func inspectorRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(title):")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 85, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
    
    // MARK: - Mac Finder Renk Paleti
    private func fileIconColor(_ file: RemoteFileItem) -> Color {
        if file.isDirectory { return .blue }
        let ext = file.fileExtension
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif": return .purple
        case "mp4", "mov", "mkv", "avi": return .indigo
        case "mp3", "m4a", "wav", "flac": return .pink
        case "pdf": return .red
        case "zip", "rar", "7z", "tar", "gz": return .orange
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "ppt", "pptx": return .orange
        case "txt", "md", "json", "py", "swift", "js", "html": return .teal
        default: return .secondary
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

