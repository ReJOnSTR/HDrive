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
    
    // Seçili ve Vurgulanan Dosya (Çoklu Seçim & İsim Değiştirme)
    @State private var selectedFileID: String? = nil
    @State private var selectedFileIDs: Set<String> = []
    @State private var hoveredFileID: String? = nil
    @State private var quickLookURL: URL? = nil
    @State private var renamingFileID: String? = nil
    @State private var renamingText: String = ""
    
    // Depolama Kotası & Derin Arama (Deep Search)
    @State private var storageQuota: StorageQuota? = nil
    @State private var isDeepSearchEnabled: Bool = false
    @State private var deepSearchResults: [RemoteFileItem] = []
    @State private var isDeepSearching: Bool = false
    
    // Sekme Hover Durumları
    @State private var hoveredTabID: UUID? = nil
    @State private var hoveredCloseTabID: UUID? = nil
    @State private var isPlusHovered: Bool = false
    
    // Modallar ve Diyaloglar
    @State private var showingSettingsSheet: Bool = false
    @State private var showingDiagnosticsSheet: Bool = false
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
                // Sekmeler Çubuğu (Finder Birebir Sekmeler)
                tabBarView
                
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
                explorerToolbar
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Ara...")
            .focusEffectDisabled()
            .quickLookPreview($quickLookURL)
            .background(keyboardShortcutsOverlay)
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
        .sheet(isPresented: $showingDiagnosticsSheet) {
            DiagnosticsSheetView(isPresented: $showingDiagnosticsSheet)
        }
        .alert("Yeni Klasör Oluştur", isPresented: $showingNewFolderAlert) {
            TextField("Klasör Adı", text: $newFolderName)
            Button("Oluştur", action: createFolder)
            Button("İptal", role: .cancel) { newFolderName = "" }
        }
    }
    
    // MARK: - Araç Çubuğu ve Kısayollar (Toolbar & Shortcuts)
    @ToolbarContentBuilder
    private var explorerToolbar: some ToolbarContent {
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
        
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Görünüm", selection: $isGridView) {
                Image(systemName: "square.grid.2x2").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .help("Görünüm Biçimi")
            
            sortMenu
            
            Button(action: togglePreviewPane) {
                Image(systemName: "sidebar.right")
                    .foregroundColor(showPreviewPane ? .accentColor : .primary)
            }
            .help("Önizleme Bölmesini Göster / Gizle")
            
            Button(action: { showingNewFolderAlert = true }) {
                Label("Yeni Klasör", systemImage: "folder.badge.plus")
            }
            .help("Yeni Klasör Oluştur")
            
            Button(action: uploadFile) {
                Label("Yükle", systemImage: "arrow.up.circle.fill")
            }
            .help("Dosya Yükle")
            
            Button(action: { loadDirectory(at: currentPath) }) {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
            .help("Yenile")
            
            Button(action: { showingSettingsSheet = true }) {
                Label("Ayarlar", systemImage: "gearshape")
            }
            .help("Cloudreve Ayarları")
        }
    }
    
    private var sortMenu: some View {
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
    }
    
    private var keyboardShortcutsOverlay: some View {
        Group {
            Button(action: { addNewTab() }) { EmptyView() }
                .keyboardShortcut("t", modifiers: .command)
            
            Button(action: { closeTab(activeTabID) }) { EmptyView() }
                .keyboardShortcut("w", modifiers: .command)
            
            Button(action: selectAllFiles) { EmptyView() }
                .keyboardShortcut("a", modifiers: .command)
            
            Button(action: deleteSelectedFiles) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: .command)
            
            Button(action: {
                if let sel = selectedFileID, let file = files.first(where: { $0.id == sel }) {
                    startRenaming(file)
                }
            }) { EmptyView() }
            .keyboardShortcut(.return, modifiers: [])
            
            Button(action: clearSelection) { EmptyView() }
                .keyboardShortcut(.escape, modifiers: [])
            
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
    }
    private func tabItemView(tab: ExplorerTab, isFirst: Bool, isLast: Bool) -> some View {
        let isActive = (tab.id == activeTabID)
        let isTabHovered = (hoveredTabID == tab.id)
        let isCloseHovered = (hoveredCloseTabID == tab.id)
        
        return ZStack {
            // Arka Plan Dolgusu (Finder Mantığı: Aktif sekme alttaki pencereyle tek parça birleşir)
            if isActive {
                Color(NSColor.windowBackgroundColor)
            } else if isTabHovered {
                Color.primary.opacity(0.04)
            } else {
                Color.clear
            }
            
            HStack(spacing: 6) {
                Spacer(minLength: 4)
                
                Image(systemName: tab.path.isEmpty ? "cloud.fill" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? Color(nsColor: .systemBlue) : .secondary.opacity(0.75))
                
                Text(tab.title)
                    .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(isActive ? .primary : .secondary)
                
                Spacer(minLength: 4)
                
                // Kapatma Butonu (xmark) - Finder tarzı hover veya aktifken görünür
                if tabs.count > 1 {
                    Button(action: { closeTab(tab.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(isCloseHovered ? .primary : ((isActive || isTabHovered) ? Color.secondary : Color.clear))
                            .frame(width: 15, height: 15)
                            .background(
                                Circle()
                                    .fill(isCloseHovered ? Color.primary.opacity(0.14) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Sekmeyi Kapat (⌘W)")
                    .onHover { hovering in
                        hoveredCloseTabID = hovering ? tab.id : nil
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(
            // Aktif sekmenin altındaki çizgiyi gizleyip alttaki içeriğe bağlayan Finder katmanı
            Group {
                if isActive {
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .frame(height: 1)
                    }
                }
            }
        )
        .overlay(
            // Aktif sekmenin sol/sağ sınır çizgileri
            Group {
                if isActive {
                    HStack {
                        if !isFirst {
                            Rectangle()
                                .fill(Color(NSColor.separatorColor).opacity(0.55))
                                .frame(width: 0.5)
                        }
                        Spacer()
                        Rectangle()
                            .fill(Color(NSColor.separatorColor).opacity(0.55))
                            .frame(width: 0.5)
                    }
                }
            }
        )
        .onTapGesture {
            switchToTab(tab.id)
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
        .contextMenu {
            Button(action: { addNewTab() }) {
                Label("Yeni Sekme", systemImage: "plus")
            }
            if tabs.count > 1 {
                Button(action: { closeTab(tab.id) }) {
                    Label("Sekmeyi Kapat", systemImage: "xmark")
                }
                Button(action: { closeOtherTabs(except: tab.id) }) {
                    Label("Diğer Sekmeleri Kapat", systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - 0. Sekmeler Çubuğu (Finder Birebir Sekme Tasarımı)
    private var tabBarView: some View {
        HStack(spacing: 0) {
            // Sekmeler (Eşit Genişlikte Finder Segmentleri)
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    tabItemView(tab: tab, isFirst: index == 0, isLast: index == tabs.count - 1)
                    
                    // İki inaktif sekme arasındaki dikey ince ayırıcı
                    if index < tabs.count - 1 && activeTabID != tab.id && activeTabID != tabs[index + 1].id {
                        Rectangle()
                            .fill(Color(NSColor.separatorColor).opacity(0.45))
                            .frame(width: 0.5, height: 16)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            // Yeni Sekme Ekle (+) Butonu (Finder tarzı sağa sabitlenmiş)
            Button(action: { addNewTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isPlusHovered ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Yeni Sekme Aç (⌘T)")
            .background(isPlusHovered ? Color.primary.opacity(0.05) : Color.clear)
            .overlay(
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.45))
                    .frame(width: 0.5, height: 18),
                alignment: .leading
            )
            .onHover { hovering in
                isPlusHovered = hovering
            }
        }
        .frame(height: 28)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.85))
        .overlay(
            // Alt yatay sınır çizgisi
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.55))
                .frame(height: 0.5),
            alignment: .bottom
        )
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
            if manager.servers.count > 1 {
                Section("Hesaplar") {
                    ForEach(manager.servers) { server in
                        let isActive = manager.activeServer?.id == server.id
                        Button(action: {
                            if manager.activeServer?.id != server.id {
                                manager.setActiveServer(server)
                                navigateToRoot()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: isActive ? "cloud.fill" : "cloud")
                                    .foregroundColor(isActive ? .indigo : .secondary)
                                Text(server.name)
                                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                                    .foregroundColor(isActive ? .primary : .secondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.indigo)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Section("Konumlar") {
                Button(action: { navigateToRoot() }) {
                    Label(manager.servers.count > 1 ? "Tüm Dosyalar" : (manager.activeServer?.name ?? "Cloudreve"), systemImage: "tray.full.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            
            Section("Araçlar") {
                Button(action: { showingSettingsSheet = true }) {
                    Label("Ayarlar...", systemImage: "gearshape")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let quota = storageQuota {
                Section("Depolama") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Kullanılan:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(quota.formattedUsed) / \(quota.formattedTotal)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        
                        ProgressView(value: quota.usedPercentage)
                            .progressViewStyle(.linear)
                            .accentColor(quota.usedPercentage > 0.9 ? .red : (quota.usedPercentage > 0.75 ? .orange : .blue))
                        
                        Text("%\(Int(quota.usedPercentage * 100)) dolu")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
    }
    
    // MARK: - 2. Klasör Yolu Çubuğu (Path Bar)
    private var pathBarView: some View {
        HStack(spacing: 8) {
            // Ekmek Kırıntısı (Breadcrumbs)
            breadcrumbsView
            
            Spacer()
            
            if !searchText.isEmpty {
                HStack(spacing: 6) {
                    Text("Kapsam:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        isDeepSearchEnabled = false
                    }) {
                        Text("Bu Klasör")
                            .font(.system(size: 11, weight: !isDeepSearchEnabled ? .semibold : .regular))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(!isDeepSearchEnabled ? Color.secondary.opacity(0.2) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        isDeepSearchEnabled = true
                        performDeepSearch(query: searchText)
                    }) {
                        HStack(spacing: 3) {
                            Text("Tüm Sürücü")
                                .font(.system(size: 11, weight: isDeepSearchEnabled ? .semibold : .regular))
                            if isDeepSearching {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isDeepSearchEnabled ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
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
                            clearSelection()
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
                            clearSelection()
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
        let isSelected = selectedFileIDs.contains(file.id) || selectedFileID == file.id
        let isRenaming = renamingFileID == file.id
        
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
            
            if isRenaming {
                TextField("Dosya Adı", text: $renamingText, onCommit: {
                    commitRename(file)
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.caption)
                .frame(width: 100)
            } else {
                Text(file.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 92)
            }
            
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
                handleFileTap(file)
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
        let isSelected = selectedFileIDs.contains(file.id) || selectedFileID == file.id
        let isRenaming = renamingFileID == file.id
        
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
            
            if isRenaming {
                TextField("Dosya Adı", text: $renamingText, onCommit: {
                    commitRename(file)
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.body)
                .frame(maxWidth: 240)
            } else {
                Text(file.name)
                    .font(.body)
                    .foregroundColor(isSelected ? Color.accentColor : .primary)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
            }
            
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
                handleFileTap(file)
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
                Label("Görüntüle (Hızlı Bakış)", systemImage: "eye")
            }
        } else {
            Button(action: { handleDoubleClick(file) }) {
                Label("Klasörü Aç", systemImage: "folder")
            }
        }
        
        Divider()
        
        Button(action: { startRenaming(file) }) {
            Label("Yeniden Adlandır (Enter)", systemImage: "pencil")
        }
        
        if !file.isDirectory {
            Button(action: { downloadFile(file) }) {
                Label("İndirilenlere Kaydet...", systemImage: "arrow.down.circle")
            }
        }
        
        if selectedFileIDs.count > 1 {
            Divider()
            Button(action: { downloadSelectedFiles() }) {
                Label("\(selectedFileIDs.count) Ögeyi İndirilenlere Kaydet...", systemImage: "square.and.arrow.down.on.square")
            }
            Button(role: .destructive, action: { deleteSelectedFiles() }) {
                Label("\(selectedFileIDs.count) Ögeyi Sil", systemImage: "trash")
            }
        } else {
            Button(role: .destructive, action: { deleteFile(file) }) {
                Label("Sil (⌘⌫)", systemImage: "trash")
            }
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
                HStack(spacing: 6) {
                    Text("\(filteredFiles.count) öge")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if !selectedFileIDs.isEmpty {
                        Text("• \(selectedFileIDs.count) seçili")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            if selectedFileIDs.count > 1 {
                Button(action: { downloadSelectedFiles() }) {
                    Label("Seçilenleri İndir", systemImage: "arrow.down.circle")
                        .font(.caption2)
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.horizontal, 4)
                
                Button(action: { deleteSelectedFiles() }) {
                    Label("Seçilenleri Sil", systemImage: "trash")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            Spacer()
            
            // Eşitleme, Ağ ve Finder Durumu
            HStack(spacing: 14) {
                // Ağ Bağlantı Durumu
                HStack(spacing: 4) {
                    Circle()
                        .fill(NetworkMonitor.shared.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(NetworkMonitor.shared.isConnected ? "Çevrimiçi" : "Çevrimdışı")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                    Text("Canlı Bulut Modu (İndirmesiz)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Dosyaya Çift Tıklama Mantığı (Doğrudan Quick Look ile Görüntüle - Dosya İndirilmez)
    private func handleDoubleClick(_ file: RemoteFileItem) {
        if file.isDirectory {
            // Klasör ise içine gir
            let newPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            navigateTo(newPath)
        } else {
            // DOSYA İSE: ASLA YERELE İNDİRME! DOĞRUDAN ANLIK QUICK LOOK İLE GÖRÜNTÜLE!
            triggerQuickLook(for: file)
        }
    }
    
    // MARK: - Gezinti ve Sıralama
    private var filteredFiles: [RemoteFileItem] {
        var result = (isDeepSearchEnabled && !searchText.isEmpty) ? deepSearchResults : files
        if !searchText.isEmpty && !isDeepSearchEnabled {
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
                if item1.size == item2.size {
                    comparison = item1.name.localizedStandardCompare(item2.name)
                } else {
                    comparison = item1.size < item2.size ? .orderedAscending : .orderedDescending
                }
            case .kind:
                let ext1 = (item1.name as NSString).pathExtension
                let ext2 = (item2.name as NSString).pathExtension
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
        loadStorageQuota()
        
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
    
    private func loadStorageQuota() {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        client.fetchQuota { result in
            switch result {
            case .success(let q):
                self.storageQuota = q
            case .failure:
                break
            }
        }
    }
    
    private func performDeepSearch(query: String) {
        guard !query.isEmpty, let server = manager.activeServer else {
            deepSearchResults = []
            return
        }
        isDeepSearching = true
        let client = WebDAVClient(config: server)
        var foundItems: [RemoteFileItem] = []
        
        func searchDirectory(path: String, depth: Int, completion: @escaping () -> Void) {
            if depth > 4 { completion(); return }
            client.listFiles(at: path) { result in
                switch result {
                case .success(let items):
                    let matching = items.filter { $0.name.localizedCaseInsensitiveContains(query) }
                    foundItems.append(contentsOf: matching)
                    
                    let subDirs = items.filter { $0.isDirectory }
                    guard !subDirs.isEmpty else { completion(); return }
                    
                    let group = DispatchGroup()
                    for dir in subDirs {
                        group.enter()
                        let subPath = path.isEmpty ? dir.name : "\(path)/\(dir.name)"
                        searchDirectory(path: subPath, depth: depth + 1) {
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        completion()
                    }
                case .failure:
                    completion()
                }
            }
        }
        
        searchDirectory(path: "", depth: 0) {
            DispatchQueue.main.async {
                self.deepSearchResults = foundItems
                self.isDeepSearching = false
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
    
    private func closeOtherTabs(except id: UUID) {
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id != id }
        if activeTabID != id {
            switchToTab(id)
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
                SyncLogManager.shared.log("Silindi: \(file.name)")
                loadDirectory(at: currentPath)
            } else {
                SyncLogManager.shared.log("Silme hatası: \(file.name) - \(error?.localizedDescription ?? "")", isError: true)
            }
        }
    }
    
    // MARK: - Çoklu Seçim ve İşlemler
    private func handleFileTap(_ file: RemoteFileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selectedFileIDs.contains(file.id) {
                selectedFileIDs.remove(file.id)
                if selectedFileID == file.id {
                    selectedFileID = selectedFileIDs.first
                }
            } else {
                selectedFileIDs.insert(file.id)
                selectedFileID = file.id
            }
        } else if flags.contains(.shift), let anchorID = selectedFileID,
                  let anchorIdx = filteredFiles.firstIndex(where: { $0.id == anchorID }),
                  let targetIdx = filteredFiles.firstIndex(where: { $0.id == file.id }) {
            let start = min(anchorIdx, targetIdx)
            let end = max(anchorIdx, targetIdx)
            for idx in start...end {
                selectedFileIDs.insert(filteredFiles[idx].id)
            }
            selectedFileID = file.id
        } else {
            selectedFileIDs = [file.id]
            selectedFileID = file.id
        }
    }
    
    private func selectAllFiles() {
        selectedFileIDs = Set(filteredFiles.map { $0.id })
        if selectedFileID == nil {
            selectedFileID = filteredFiles.first?.id
        }
    }
    
    private func clearSelection() {
        selectedFileIDs.removeAll()
        selectedFileID = nil
        renamingFileID = nil
    }
    
    private func startRenaming(_ file: RemoteFileItem) {
        renamingFileID = file.id
        renamingText = file.name
    }
    
    private func commitRename(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else {
            renamingFileID = nil
            return
        }
        let newName = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != file.name else {
            renamingFileID = nil
            return
        }
        
        let client = WebDAVClient(config: server)
        let basePath = currentPath.isEmpty ? "" : currentPath + "/"
        let sourcePath = basePath + file.name
        let destPath = basePath + newName
        
        client.move(from: sourcePath, to: destPath, overwrite: false) { error in
            renamingFileID = nil
            if error == nil {
                SyncLogManager.shared.log("Yeniden adlandırıldı: \(file.name) -> \(newName)")
                loadDirectory(at: currentPath)
            } else {
                SyncLogManager.shared.log("Yeniden adlandırma hatası: \(error?.localizedDescription ?? "")", isError: true)
            }
        }
    }
    
    private func deleteSelectedFiles() {
        let targets = filteredFiles.filter { selectedFileIDs.contains($0.id) }
        guard !targets.isEmpty, let server = manager.activeServer else { return }
        
        let client = WebDAVClient(config: server)
        let group = DispatchGroup()
        for file in targets {
            group.enter()
            client.delete(at: file.href) { error in
                if error == nil {
                    SyncLogManager.shared.log("Silindi: \(file.name)")
                } else {
                    SyncLogManager.shared.log("Silme hatası: \(file.name) - \(error?.localizedDescription ?? "")", isError: true)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            clearSelection()
            loadDirectory(at: currentPath)
        }
    }
    
    private func downloadSelectedFiles() {
        let targets = filteredFiles.filter { selectedFileIDs.contains($0.id) && !$0.isDirectory }
        guard !targets.isEmpty, let server = manager.activeServer else { return }
        
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let client = WebDAVClient(config: server)
        for file in targets {
            let dest = downloads.appendingPathComponent(file.name)
            client.downloadFile(href: file.href, to: dest, progress: { _ in }, completion: { error in
                if error == nil {
                    SyncLogManager.shared.log("İndirildi: \(file.name)")
                } else {
                    SyncLogManager.shared.log("İndirme hatası: \(file.name) - \(error?.localizedDescription ?? "")", isError: true)
                }
            })
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
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        let targetDir = currentPath
        
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let localURL = url else { return }
                self.uploadLocalItemRecursively(localURL: localURL, remoteBaseDir: targetDir, client: client) {
                    DispatchQueue.main.async {
                        self.loadDirectory(at: self.currentPath)
                    }
                }
            }
        }
    }
    
    private func uploadLocalItemRecursively(localURL: URL, remoteBaseDir: String, client: WebDAVClient, completion: @escaping () -> Void) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            completion()
            return
        }
        
        let itemName = localURL.lastPathComponent
        let targetRemote = remoteBaseDir.isEmpty ? itemName : "\(remoteBaseDir)/\(itemName)"
        
        if isDir.boolValue {
            client.createFolder(at: targetRemote) { _ in
                guard let subItems = try? FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                    completion()
                    return
                }
                guard !subItems.isEmpty else {
                    completion()
                    return
                }
                
                let dispatchGroup = DispatchGroup()
                for subItem in subItems {
                    dispatchGroup.enter()
                    self.uploadLocalItemRecursively(localURL: subItem, remoteBaseDir: targetRemote, client: client) {
                        dispatchGroup.leave()
                    }
                }
                dispatchGroup.notify(queue: .main) {
                    completion()
                }
            }
        } else {
            client.uploadFile(localFileURL: localURL, toRemotePath: targetRemote) { _ in
                completion()
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
                                Text("Görüntü hazırlanıyor...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Button("Görüntüle (Hızlı Bakış)") {
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
    
    @State private var selectedServerID: UUID? = nil
    @State private var serverName: String = "Cloudreve"
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    
    @State private var isTesting: Bool = false
    @State private var testResult: String? = nil
    @State private var isTestSuccess: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Üst Başlık Çubuğu
            HStack {
                Label("Hesaplar ve Eşitleme Ayarları", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Spacer()
                Button("Kapat") {
                    saveCurrentAccount()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // 2 Sütunlu Ana Gövde
            HStack(spacing: 0) {
                // SOL SÜTUN: Kayıtlı Hesaplar Listesi
                VStack(spacing: 0) {
                    // Liste Başlığı
                    HStack {
                        Text("Kayıtlı Hesaplar")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(manager.servers.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    
                    Divider()
                    
                    // Hesap Öğeleri (ScrollView)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(manager.servers) { server in
                                let isSelected = (selectedServerID == server.id)
                                let isActive = (manager.activeServer?.id == server.id)
                                
                                Button(action: {
                                    selectServer(server)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: isActive ? "cloud.fill" : "cloud")
                                            .font(.system(size: 16))
                                            .foregroundColor(isSelected ? .white : (isActive ? .accentColor : .secondary))
                                            .frame(width: 22)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(server.name.isEmpty ? "Yeni Hesap" : server.name)
                                                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                                    .foregroundColor(isSelected ? .white : .primary)
                                                    .lineLimit(1)
                                                
                                                if isActive {
                                                    Circle()
                                                        .fill(isSelected ? Color.white : Color.green)
                                                        .frame(width: 6, height: 6)
                                                }
                                            }
                                            
                                            Text(serverSubtitle(server))
                                                .font(.system(size: 10))
                                                .foregroundColor(isSelected ? Color.white.opacity(0.85) : .secondary)
                                                .lineLimit(1)
                                        }
                                        
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color.accentColor : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
                    
                    Divider()
                    
                    // Alt Butonlar: [+] Ekle, [-] Sil
                    HStack(spacing: 0) {
                        Button(action: createNewAccount) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Yeni Hesap Ekle")
                        
                        Divider().frame(height: 14)
                        
                        Button(action: deleteSelectedAccount) {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(manager.servers.count > 1 ? .primary : .secondary.opacity(0.3))
                                .frame(width: 32, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.servers.count <= 1)
                        .help("Seçili Hesabı Sil")
                        
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                }
                .frame(width: 220)
                
                Divider()
                
                // SAĞ SÜTUN: Hesap Detayları ve Senkronizasyon
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Üst Başlık ve Aktif Durumu
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(serverName.isEmpty ? "Hesap Detayları" : serverName)
                                    .font(.title3.bold())
                                Text(serverSubtitleFromFields())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if let curID = selectedServerID, manager.activeServer?.id == curID {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Aktif Sürücü")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.12))
                                .cornerRadius(6)
                            } else {
                                Button("Aktif Hesap Olarak Ayarla") {
                                    makeCurrentActive()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Divider()
                        
                        // Sunucu ve Kimlik Bilgileri
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Hesap Adı:")
                                    .font(.caption.bold())
                                TextField("Örn: Kişisel Drive, Şirket Bulutu", text: $serverName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Cloudreve WebDAV Adresi:")
                                    .font(.caption.bold())
                                TextField("https://alanadi.com/dav", text: $serverURL)
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
                                Text("WebDAV Şifresi (Keychain Korumalı):")
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
                        
                        HStack(spacing: 12) {
                            Button("Bağlantıyı Test Et") {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTesting || serverURL.isEmpty)
                            
                            Spacer()
                            
                            Button("Değişiklikleri Kaydet") {
                                saveCurrentAccount()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        Divider()
                        
                        // Finder & Yerel Klasör Entegrasyonu
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Finder Entegrasyonu & Yerel Eşitleme", systemImage: "folder.badge.gearshape")
                                    .font(.subheadline.bold())
                                Spacer()
                                Toggle("", isOn: $syncEngine.isSyncEnabled)
                                    .toggleStyle(.switch)
                            }
                            
                            Text("Dosyalarınızı Mac'inizde '~/HDrive - Cloudreve' klasöründe normal bir klasör gibi tutar. Finder'da doğrudan görebilir ve düzenleyebilirsiniz.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 10) {
                                Button(action: { syncEngine.openLocalFolderInFinder() }) {
                                    Label("Finder'da Aç", systemImage: "arrow.up.forward.app")
                                }
                                .buttonStyle(.bordered)
                                
                                if syncEngine.isSyncEnabled {
                                    Button(action: { syncEngine.syncNow() }) {
                                        Label("Şimdi Eşitle", systemImage: "arrow.clockwise")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(syncEngine.isSyncing)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(syncEngine.isSyncEnabled ? (syncEngine.isSyncing ? Color.orange : Color.green) : Color.gray)
                                        .frame(width: 8, height: 8)
                                    Text(syncEngine.syncStatus)
                                        .font(.caption)
                                        .foregroundColor(syncEngine.isSyncing ? .orange : .secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding(18)
                }
            }
        }
        .frame(width: 680, height: 500)
        .onAppear {
            if let active = manager.activeServer {
                selectServer(active)
            } else if let first = manager.servers.first {
                selectServer(first)
            }
        }
    }
    
    private func serverSubtitle(_ server: CloudreveServerConfig) -> String {
        if !server.username.isEmpty {
            return server.username
        }
        if let host = URL(string: server.serverURL)?.host, !host.isEmpty {
            return host
        }
        return "Yapılandırılmamış"
    }
    
    private func serverSubtitleFromFields() -> String {
        if !username.isEmpty {
            return username
        }
        if let host = URL(string: serverURL)?.host, !host.isEmpty {
            return host
        }
        return serverURL.isEmpty ? "Sunucu adresi belirtilmemiş" : serverURL
    }
    
    private func selectServer(_ server: CloudreveServerConfig) {
        if selectedServerID != nil {
            saveCurrentAccount()
        }
        selectedServerID = server.id
        serverName = server.name
        serverURL = server.serverURL
        username = server.username
        password = server.password
        testResult = nil
    }
    
    private func createNewAccount() {
        saveCurrentAccount()
        let newServer = CloudreveServerConfig(
            name: "Yeni Hesap \(manager.servers.count + 1)",
            serverURL: "https://",
            username: "",
            password: ""
        )
        manager.servers.append(newServer)
        selectedServerID = newServer.id
        serverName = newServer.name
        serverURL = newServer.serverURL
        username = newServer.username
        password = newServer.password
        testResult = nil
    }
    
    private func deleteSelectedAccount() {
        guard manager.servers.count > 1, let curID = selectedServerID,
              let target = manager.servers.first(where: { $0.id == curID }) else { return }
        manager.deleteServer(target)
        if let next = manager.servers.first {
            selectedServerID = next.id
            serverName = next.name
            serverURL = next.serverURL
            username = next.username
            password = next.password
            testResult = nil
        }
        onSave()
    }
    
    private func makeCurrentActive() {
        saveCurrentAccount()
        if let curID = selectedServerID, let target = manager.servers.first(where: { $0.id == curID }) {
            manager.setActiveServer(target)
            onSave()
        }
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        var cfg = CloudreveServerConfig()
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
    
    private func saveCurrentAccount() {
        guard let curID = selectedServerID else { return }
        var cfg = manager.servers.first(where: { $0.id == curID }) ?? CloudreveServerConfig()
        cfg.name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.password = password
        manager.saveServer(cfg)
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

// MARK: - Eşitleme ve Sistem Tanılama Sayfası (Diagnostics Sheet)
struct DiagnosticsSheetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var logManager = SyncLogManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Eşitleme ve Sistem Tanılama Günlüğü", systemImage: "stethoscope")
                    .font(.headline)
                
                Spacer()
                
                Button("Temizle") {
                    logManager.clear()
                }
                .font(.caption)
                
                Button("Kapat") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            
            Divider()
            
            if logManager.logs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Henüz bir işlem günlüğü kaydı yok.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logManager.logs) { (entry: SyncLogEntry) in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(statusColor(for: entry.isError))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                
                                Text(entry.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                Text(entry.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(entry.isError ? .red : .primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding(20)
        .frame(width: 620, height: 440)
    }
    
    private func statusColor(for isError: Bool) -> Color {
        return isError ? .red : .green
    }
}

