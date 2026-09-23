//
//  NativeExplorerView.swift
//  HDriveMac - Gerçek Klasör ve Dosya Yöneticisi Görünümü
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLook
import QuickLookUI
import Network
import PDFKit
import ObjectiveC



public struct ExplorerTab: Identifiable, Equatable {
    public let id: UUID
    public var serverId: UUID?
    public var title: String
    public var path: String
    public var history: [String]
    public var historyIndex: Int
    public var selectedFileID: String?
    
    public init(id: UUID = UUID(), serverId: UUID? = nil, title: String = "Bulut Sürücüsü", path: String = "", history: [String] = [""], historyIndex: Int = 0, selectedFileID: String? = nil) {
        self.id = id
        self.serverId = serverId
        self.title = title
        self.path = path
        self.history = history
        self.historyIndex = historyIndex
        self.selectedFileID = selectedFileID
    }
}

public struct PinnedFolder: Identifiable, Codable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    
    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum ExplorerColumnId: String, CaseIterable, Codable, Identifiable {
    case name = "name"
    case date = "date"
    case kind = "kind"
    case size = "size"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .name: return "Ad"
        case .date: return "Değiştirilme Tarihi"
        case .kind: return "Tür"
        case .size: return "Boyut"
        }
    }
    
    public var defaultWidth: Double {
        switch self {
        case .name: return 220.0
        case .date: return 140.0
        case .kind: return 95.0
        case .size: return 80.0
        }
    }
    
    public var minWidth: Double {
        switch self {
        case .name: return 140.0
        case .date: return 90.0
        case .kind: return 70.0
        case .size: return 60.0
        }
    }
}

struct ColumnHeaderDropDelegate: DropDelegate {
    let targetCol: ExplorerColumnId
    @Binding var draggedCol: ExplorerColumnId?
    @Binding var targetHighlight: ExplorerColumnId?
    @Binding var columnOrderRaw: String
    
    func dropEntered(info: DropInfo) {
        if draggedCol != targetCol {
            targetHighlight = targetCol
        }
    }
    
    func dropExited(info: DropInfo) {
        if targetHighlight == targetCol {
            targetHighlight = nil
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        targetHighlight = nil
        let movingCol = draggedCol
        draggedCol = nil
        
        if let source = movingCol, source != targetCol {
            applyMove(source: source, target: targetCol)
            return true
        } else if let provider = info.itemProviders(for: [.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                if let str = string as? String, let source = ExplorerColumnId(rawValue: str), source != targetCol {
                    DispatchQueue.main.async {
                        self.applyMove(source: source, target: targetCol)
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func applyMove(source: ExplorerColumnId, target: ExplorerColumnId) {
        var cols = columnOrderRaw.components(separatedBy: ",").compactMap { ExplorerColumnId(rawValue: $0) }
        guard let fromIdx = cols.firstIndex(of: source),
              let toIdx = cols.firstIndex(of: target) else { return }
        cols.remove(at: fromIdx)
        cols.insert(source, at: toIdx)
        columnOrderRaw = cols.map { $0.rawValue }.joined(separator: ",")
    }
}

// MARK: - Araç Çubuğu Öğeleri ve Görünüm Modları (Toolbar Customization Models)
public enum ToolbarDisplayMode: String, CaseIterable, Identifiable, Codable {
    case iconOnly = "iconOnly"
    case iconAndText = "iconAndText"
    
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .iconOnly: return "Yalnızca Simge"
        case .iconAndText: return "Simge ve Metin"
        }
    }
}
public struct ToolbarLabelStyleModifier: ViewModifier {
    public let mode: ToolbarDisplayMode
    
    @ViewBuilder
    public func body(content: Content) -> some View {
        if mode == .iconAndText {
            content.labelStyle(.titleAndIcon)
        } else {
            content.labelStyle(.iconOnly)
        }
    }
}
public enum ExplorerToolbarItemId: String, CaseIterable, Identifiable, Codable {
    case navigation = "navigation"           // Geri / İleri
    case viewMode = "viewMode"               // Görünüm (Izgara / Liste)
    case sort = "sort"                       // Sıralama
    case previewPane = "previewPane"         // Önizleme Bölmesi
    case newFolder = "newFolder"             // Yeni Klasör
    case upload = "upload"                   // Dosya Yükle
    case download = "download"               // Dosya İndir
    case refresh = "refresh"                 // Yenile
    case quickLook = "quickLook"             // Hızlı Bakış
    case getInfo = "getInfo"                 // Bilgi Ver
    case delete = "delete"                   // Sil
    case transferQueue = "transferQueue"     // Transferler
    case settings = "settings"               // Ayarlar
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .navigation: return "Geri / İleri"
        case .viewMode: return "Görünüm"
        case .sort: return "Sırala"
        case .previewPane: return "Önizleme"
        case .newFolder: return "Yeni Klasör"
        case .upload: return "Yükle"
        case .download: return "İndir"
        case .refresh: return "Yenile"
        case .quickLook: return "Hızlı Bakış"
        case .getInfo: return "Bilgi Ver"
        case .delete: return "Sil"
        case .transferQueue: return "Transferler"
        case .settings: return "Ayarlar"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .navigation: return "Klasör geçmişinde geri ve ileri gezin"
        case .viewMode: return "Izgara ve liste görünüm biçimi arasında geçiş yap"
        case .sort: return "Ada, tarihe, türe veya boyuta göre sırala"
        case .previewPane: return "Sağ taraftaki önizleme ve detay panelini göster/gizle"
        case .newFolder: return "Geçerli dizinde yeni bir klasör oluştur"
        case .upload: return "Bilgisayarınızdan buluta yeni dosya yükle"
        case .download: return "Seçili dosyayı bilgisayarınıza indir"
        case .refresh: return "Mevcut dizindeki dosya listesini yeniden yükle"
        case .quickLook: return "Seçili dosyayı Hızlı Bakış ile önizle"
        case .getInfo: return "Seçili dosyanın boyut ve konum özelliklerini göster"
        case .delete: return "Seçili dosya veya klasörleri sil"
        case .transferQueue: return "Aktif yükleme ve indirme kuyruğunu göster"
        case .settings: return "HDrive sunucu ve uygulama tercihlerini aç"
        }
    }
    
    public var icon: String {
        switch self {
        case .navigation: return "chevron.left.chevron.right"
        case .viewMode: return "square.grid.2x2"
        case .sort: return "arrow.up.arrow.down"
        case .previewPane: return "sidebar.right"
        case .newFolder: return "folder.badge.plus"
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle"
        case .refresh: return "arrow.clockwise"
        case .quickLook: return "eye"
        case .getInfo: return "info.circle"
        case .delete: return "trash"
        case .transferQueue: return "tray.and.arrow.down"
        case .settings: return "gearshape"
        }
    }
}

public struct NativeExplorerView: View {
    public static var isSearchActiveGlobal: Bool = false
    @ObservedObject var manager = CloudreveManager.shared
    @ObservedObject var opener = FileOpener.shared
    @ObservedObject var previewManager = FilePreviewManager.shared
    @ObservedObject var transferManager = TransferManager.shared
    
    // Sekmeler (Tabs)
    private static let initialTab = ExplorerTab(title: "Bulut Sürücüsü", path: "")
    @State private var tabs: [ExplorerTab] = [initialTab]
    @State private var activeTabID: UUID = initialTab.id
    
    // Sıralama (Sort)
    @AppStorage("hdrive_sortField") private var sortField: FileSortField = .name
    @AppStorage("hdrive_sortAscending") private var sortAscending: Bool = true
    @AppStorage("hdrive_foldersFirst") private var foldersFirst: Bool = true
    
    // Sütun Genişlikleri & Sıralaması (Kalıcı - AppStorage)
    @AppStorage("hdrive_colNameWidth") private var colNameWidth: Double = 220.0
    @AppStorage("hdrive_colDateWidth") private var colDateWidth: Double = 140.0
    @AppStorage("hdrive_colKindWidth") private var colKindWidth: Double = 95.0
    @AppStorage("hdrive_colSizeWidth") private var colSizeWidth: Double = 80.0
    
    @AppStorage("hdrive_columnOrder") private var columnOrderRaw: String = "name,date,kind,size"
    
    @AppStorage("hdrive_showColDate") private var showColDate: Bool = true
    @AppStorage("hdrive_showColKind") private var showColKind: Bool = true
    @AppStorage("hdrive_showColSize") private var showColSize: Bool = true
    
    // Araç Çubuğu Özelleştirmesi (Toolbar Customization)
    public static let defaultToolbarItems = "navigation,viewMode,sort,previewPane,newFolder,upload,refresh,transferQueue,settings"
    @AppStorage("hdrive_toolbar_items") private var toolbarItemsRaw: String = NativeExplorerView.defaultToolbarItems
    @AppStorage("hdrive_toolbar_display_mode") private var toolbarDisplayModeRaw: String = ToolbarDisplayMode.iconOnly.rawValue
    @State private var showingToolbarCustomizer: Bool = false
    
    private var toolbarDisplayMode: ToolbarDisplayMode {
        ToolbarDisplayMode(rawValue: toolbarDisplayModeRaw) ?? .iconOnly
    }
    
    private var enabledToolbarItemIDs: Set<ExplorerToolbarItemId> {
        let items = toolbarItemsRaw.components(separatedBy: ",").compactMap { ExplorerToolbarItemId(rawValue: $0) }
        return Set(items)
    }
    
    private func isToolbarItemEnabled(_ id: ExplorerToolbarItemId) -> Bool {
        return enabledToolbarItemIDs.contains(id)
    }
    
    private func toggleToolbarItem(_ id: ExplorerToolbarItemId) {
        var current = toolbarItemsRaw.components(separatedBy: ",").filter { !$0.isEmpty }
        if current.contains(id.rawValue) {
            current.removeAll { $0 == id.rawValue }
        } else {
            current.append(id.rawValue)
        }
        toolbarItemsRaw = current.joined(separator: ",")
    }
    
    private func resetToolbarItemsToDefault() {
        toolbarItemsRaw = Self.defaultToolbarItems
        toolbarDisplayModeRaw = ToolbarDisplayMode.iconOnly.rawValue
    }
    
    // Sütun Canlı Boyutlandırma & Taşıma Durumu
    @State private var liveResizingCol: ExplorerColumnId? = nil
    @State private var liveDragBaseWidth: Double = 0
    @State private var liveWidthDelta: Double = 0
    @State private var draggedColumn: ExplorerColumnId? = nil
    @State private var dropTargetColumn: ExplorerColumnId? = nil
    
    private var columnOrder: [ExplorerColumnId] {
        get {
            let ids = columnOrderRaw.components(separatedBy: ",").compactMap { ExplorerColumnId(rawValue: $0) }
            let all = ExplorerColumnId.allCases
            var result = ids.filter { all.contains($0) }
            for col in all where !result.contains(col) {
                result.append(col)
            }
            return result
        }
        nonmutating set {
            columnOrderRaw = newValue.map { $0.rawValue }.joined(separator: ",")
        }
    }
    
    private func isColumnVisible(_ col: ExplorerColumnId) -> Bool {
        switch col {
        case .name: return true
        case .date: return showColDate
        case .kind: return showColKind
        case .size: return showColSize
        }
    }
    
    private func columnWidth(for col: ExplorerColumnId) -> Double {
        if col == liveResizingCol {
            return max(col.minWidth, liveDragBaseWidth + liveWidthDelta)
        }
        switch col {
        case .name: return max(ExplorerColumnId.name.minWidth, colNameWidth)
        case .date: return max(ExplorerColumnId.date.minWidth, colDateWidth)
        case .kind: return max(ExplorerColumnId.kind.minWidth, colKindWidth)
        case .size: return max(ExplorerColumnId.size.minWidth, colSizeWidth)
        }
    }
    
    private func setColumnWidth(_ width: Double, for col: ExplorerColumnId) {
        let clamped = max(col.minWidth, width)
        switch col {
        case .name: colNameWidth = clamped
        case .date: colDateWidth = clamped
        case .kind: colKindWidth = clamped
        case .size: colSizeWidth = clamped
        }
    }
    
    private func isColumnSorted(_ col: ExplorerColumnId) -> Bool {
        switch col {
        case .name: return sortField == .name
        case .date: return sortField == .date
        case .kind: return sortField == .kind
        case .size: return sortField == .size
        }
    }
    
    private var totalColumnsWidth: Double {
        let visibleCols = columnOrder.filter { isColumnVisible($0) }
        let colsWidth = visibleCols.reduce(0.0) { $0 + columnWidth(for: $1) }
        let splittersWidth = Double(visibleCols.count) * 10.0
        let paddingWidth = 28.0 // 14 leading + 14 trailing
        return colsWidth + splittersWidth + paddingWidth
    }
    
    // Klavyeden Harfle Arama (Type-to-Select)
    @State private var typeToSelectQuery: String = ""
    @State private var typeToSelectWorkItem: DispatchWorkItem? = nil
    @State private var keyMonitor: Any? = nil
    
    // Klasör Gezintisi
    @State private var currentPath: String = ""
    @State private var pathHistory: [String] = [""]
    @State private var historyIndex: Int = 0
    @State private var files: [RemoteFileItem] = []
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var isSearchPresented: Bool = false
    @State private var mouseMonitor: Any? = nil
    @State private var rightClickMonitor: Any? = nil
    @AppStorage("hdrive_isGridView") private var isGridView: Bool = true
    @AppStorage("hdrive_showPreviewPane") private var showPreviewPane: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Seçili ve Vurgulanan Dosya (Çoklu Seçim & İsim Değiştirme)
    @State private var selectedFileID: String? = nil
    @State private var selectedFileIDs: Set<String> = []
    @State private var hoveredFileID: String? = nil
    @State private var quickLookURL: URL? = nil
    @State private var renamingFileID: String? = nil
    @State private var renamingText: String = ""
    @State private var lastClickTime: Date = Date.distantPast
    @State private var lastClickedFileID: String? = nil
    
    // Sabitlenen Favori Klasörler & Kenar Çubuğu
    @State private var pinnedFolders: [PinnedFolder] = []
    @State private var isSidebarDropTargeted: Bool = false
    @State private var isLoadingQuota: Bool = false
    
    // Sistem Panosu (Kopyala / Kes / Yapıştır)
    @State private var copiedRemoteItems: [RemoteFileItem] = []
    @State private var isClipboardCut: Bool = false
    
    // Depolama Kotası & Derin Arama (Deep Search)
    @State private var storageQuotas: [UUID: StorageQuota] = [:]
    @State private var isDeepSearchEnabled: Bool = false
    @State private var deepSearchResults: [RemoteFileItem] = []
    @State private var isDeepSearching: Bool = false
    
    private var activeTabServer: CloudreveServerConfig? {
        if let curTab = tabs.first(where: { $0.id == activeTabID }),
           let sId = curTab.serverId,
           let found = manager.servers.first(where: { $0.id == sId }) {
            return found
        }
        return manager.activeServer
    }
    
    private var currentStorageQuota: StorageQuota? {
        guard let server = activeTabServer else { return nil }
        return storageQuotas[server.id]
    }
    
    // Sekme Hover Durumları
    @State private var hoveredTabID: UUID? = nil
    @State private var hoveredCloseTabID: UUID? = nil
    @State private var isPlusHovered: Bool = false
    
    // Modallar ve Diyaloglar
    @State private var showingSettingsSheet: Bool = false
    @State private var showingDiagnosticsSheet: Bool = false
    @State private var showingTransferPopover: Bool = false
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
            mainDetailView
        }
        .frame(minWidth: showPreviewPane ? 960 : 750, minHeight: 520)
        .onAppear {
            loadPinnedFolders()
            if let first = tabs.first {
                activeTabID = first.id
            }
            if manager.activeServer == nil || manager.activeServer?.serverURL.isEmpty == true {
                self.files = []
            } else {
                loadDirectory(at: currentPath)
            }
            loadStorageQuota()
            setupEventMonitors()
        }
        .onChange(of: manager.activeServer?.id) { _, newServerID in
            guard newServerID != nil else {
                self.files = []
                return
            }
            // Yeni sunucu aktif olduğunda (bağlantı kaydedilince) dosyaları yükle
            currentPath = ""
            pathHistory = [""]
            historyIndex = 0
            selectedFileID = nil
            loadDirectory(at: "")
            loadStorageQuota()
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
            if let monitor = rightClickMonitor {
                NSEvent.removeMonitor(monitor)
                rightClickMonitor = nil
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
        .alert("Uyarı", isPresented: Binding(
            get: { statusAlertMessage != nil },
            set: { if !$0 { statusAlertMessage = nil } }
        )) {
            Button("Tamam", role: .cancel) {
                statusAlertMessage = nil
            }
        } message: {
            Text(statusAlertMessage ?? "")
        }
    }
    
    @ViewBuilder
    private var mainDetailView: some View {
        VStack(spacing: 0) {
            // Sekmeler Çubuğu (Finder Birebir Sekmeler)
            tabBarView
            
            // Klasör Yolu Çubuğu (Finder Path Bar & Arama)
            pathBarView
            
            Divider()
            
            // Dosya Listesi ve Önizleme Bölmesi
            HStack(spacing: 0) {
                mainFilesAreaView
                    .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                
                if showPreviewPane {
                    Divider()
                    previewPaneSideView
                        .frame(width: 320)
                        .frame(maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                        .layoutPriority(1)
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
        .modifier(ToolbarLabelStyleModifier(mode: toolbarDisplayMode))
        .sheet(isPresented: $showingToolbarCustomizer) {
            ToolbarCustomizationSheet(
                isPresented: $showingToolbarCustomizer,
                toolbarItemsRaw: $toolbarItemsRaw,
                toolbarDisplayModeRaw: $toolbarDisplayModeRaw
            )
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Ara...")
        .quickLookPreview($quickLookURL)
        .background(keyboardShortcutsOverlay)
        .onReceive(NotificationCenter.default.publisher(for: .exitSearchRequested)) { _ in
            exitSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openToolbarCustomizer)) { _ in
            showingToolbarCustomizer = true
        }
        .onChange(of: isSearchPresented) { _, isPresented in
            NativeExplorerView.isSearchActiveGlobal = isPresented
            if !isPresented {
                NativeExplorerView.collapseSearch(in: NSApp.keyWindow)
            }
        }
        .onChange(of: searchText) { _, newQuery in
            handleSearchTextChange(newQuery)
        }
    }
    
    private func handleSearchTextChange(_ newQuery: String) {
        if isDeepSearchEnabled && !newQuery.isEmpty {
            performDeepSearch(query: newQuery)
        }
    }
    
    // MARK: - Araç Çubuğu ve Kısayollar (Toolbar & Shortcuts)
    @ToolbarContentBuilder
    private var explorerToolbar: some ToolbarContent {
        if isToolbarItemEnabled(.navigation) {
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
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            if isToolbarItemEnabled(.viewMode) {
                Picker("Görünüm", selection: $isGridView) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented)
                .help("Görünüm Biçimi")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.sort) {
                sortMenu
            }
            
            if isToolbarItemEnabled(.previewPane) {
                Button(action: togglePreviewPane) {
                    Label("Önizleme", systemImage: "sidebar.right")
                        .foregroundColor(showPreviewPane ? .accentColor : .primary)
                }
                .help("Önizleme Bölmesini Göster / Gizle")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.newFolder) {
                Button(action: { showingNewFolderAlert = true }) {
                    Label("Yeni Klasör", systemImage: "folder.badge.plus")
                }
                .help("Yeni Klasör Oluştur")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.upload) {
                Button(action: uploadFile) {
                    Label("Yükle", systemImage: "arrow.up.circle.fill")
                }
                .help("Dosya Yükle")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.download) {
                Button(action: downloadSelectedFiles) {
                    Label("İndir", systemImage: "arrow.down.circle")
                }
                .disabled(selectedFileID == nil && selectedFileIDs.isEmpty)
                .help("Seçili Dosyaları İndir")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.quickLook) {
                Button(action: {
                    if let selID = selectedFileID, let file = files.first(where: { $0.id == selID }), !file.isDirectory {
                        triggerQuickLook(for: file)
                    }
                }) {
                    Label("Hızlı Bakış", systemImage: "eye")
                }
                .disabled(selectedFileID == nil)
                .help("Hızlı Bakış (Boşluk)")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.getInfo) {
                Button(action: {
                    if !showPreviewPane {
                        showPreviewPane = true
                    }
                }) {
                    Label("Bilgi Ver", systemImage: "info.circle")
                }
                .help("Detay ve Bilgi Bölmesi")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.delete) {
                Button(action: deleteSelectedFiles) {
                    Label("Sil", systemImage: "trash")
                }
                .disabled(selectedFileID == nil && selectedFileIDs.isEmpty)
                .help("Seçili Öğeleri Sil (⌘⌫)")
                .contextMenu { toolbarContextMenu }
            }

            
            if isToolbarItemEnabled(.refresh) {
                Button(action: { loadDirectory(at: currentPath) }) {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                .help("Yenile")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.transferQueue) {
                Button(action: { showingTransferPopover.toggle() }) {
                    HStack(spacing: 3) {
                        Image(systemName: transferManager.isTransferring ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .foregroundColor(transferManager.isTransferring ? .accentColor : .primary)
                        if transferManager.activeTransfersCount > 0 {
                            Text("\(transferManager.activeTransfersCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .popover(isPresented: $showingTransferPopover, arrowEdge: .bottom) {
                    TransferPopoverView()
                }
                .help("Transfer Kuyruğu (İndirme / Yükleme)")
                .contextMenu { toolbarContextMenu }
            }
            
            if isToolbarItemEnabled(.settings) {
                Button(action: {
                    SettingsWindowManager.shared.showSettings {
                        loadDirectory(at: currentPath)
                    }
                }) {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .help("HDrive Ayarları (⌘,)")
                .contextMenu { toolbarContextMenu }
            }
        }
    }
    
    @ViewBuilder
    private var toolbarContextMenu: some View {
        Button(action: { showingToolbarCustomizer = true }) {
            Label("Araç Çubuğunu Özelleştir...", systemImage: "slider.horizontal.3")
        }
        Divider()
        Picker("Görünüm", selection: $toolbarDisplayModeRaw) {
            Text("Yalnızca Simge").tag(ToolbarDisplayMode.iconOnly.rawValue)
            Text("Simge ve Metin").tag(ToolbarDisplayMode.iconAndText.rawValue)
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
            
            Button(action: selectPreviousFile) { EmptyView() }
                .keyboardShortcut(.upArrow, modifiers: [])
            
            Button(action: selectNextFile) { EmptyView() }
                .keyboardShortcut(.downArrow, modifiers: [])
            
            Button(action: expandSelectionUp) { EmptyView() }
                .keyboardShortcut(.upArrow, modifiers: .shift)
            
            Button(action: expandSelectionDown) { EmptyView() }
                .keyboardShortcut(.downArrow, modifiers: .shift)
            
            Button(action: { isSearchPresented = true }) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
            
            Button(action: deleteSelectedFiles) { EmptyView() }
                .keyboardShortcut(.delete, modifiers: .command)
            
            Button(action: {
                if let firstResponder = NSApp.keyWindow?.firstResponder, (firstResponder is NSText || firstResponder is NSTextView || firstResponder is NSTextField) {
                    return
                }
                if let sel = selectedFileID, let file = files.first(where: { $0.id == sel }) {
                    startRenaming(file)
                }
            }) { EmptyView() }
            .keyboardShortcut(.return, modifiers: [])
            
            Button(action: {
                if isSearchPresented || !searchText.isEmpty {
                    exitSearch()
                } else {
                    clearSelection()
                }
            }) { EmptyView() }
            .keyboardShortcut(.escape, modifiers: [])
            
            Button(action: togglePreviewPane) { EmptyView() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            
            Button(action: copySelectedFiles) { EmptyView() }
                .keyboardShortcut("c", modifiers: .command)
            
            Button(action: cutSelectedFiles) { EmptyView() }
                .keyboardShortcut("x", modifiers: .command)
            
            Button(action: pasteFiles) { EmptyView() }
                .keyboardShortcut("v", modifiers: .command)
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
                
                let tabServer = manager.servers.first(where: { $0.id == tab.serverId }) ?? manager.activeServer
                if tab.path.isEmpty, let s = tabServer {
                    ProviderLogoBadge(storageProtocol: s.storageProtocol, size: 16)
                } else {
                    Image(systemName: tab.path.isEmpty ? "cloud.fill" : "folder.fill")
                        .font(.system(size: 12))
                        .foregroundColor(isActive ? Color(nsColor: .systemBlue) : .secondary.opacity(0.75))
                }
                
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
            
            // Yeni Sekme Ekle (+) Butonu (Doğrudan yeni sekme açar, aşağı ok / menü açılmaz)
            Button(action: {
                addNewTab()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(isPlusHovered ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
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
    
    // MARK: - Liste Sütun Başlıkları (Click-to-Sort, Drag-to-Reorder & Resizable Splitters)
    private var listHeaderView: some View {
        let visibleCols = columnOrder.filter { isColumnVisible($0) }
        
        return HStack(spacing: 0) {
            ForEach(Array(visibleCols.enumerated()), id: \.element.id) { index, col in
                HStack(spacing: 0) {
                    columnHeaderView(col: col)
                    
                    // Finder tarzı: Her sütunun SAĞ kenarında boyutlandırma ayracı
                    columnSplitter(for: col)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .contextMenu {
            headerContextMenu
        }
    }
    
    private func columnHeaderView(col: ExplorerColumnId) -> some View {
        let isDragged = (draggedColumn == col)
        let isTarget = (dropTargetColumn == col && draggedColumn != col)
        let isSorted = isColumnSorted(col)
        let w = columnWidth(for: col)
        
        return HStack(spacing: 4) {
            if col == .name {
                Spacer().frame(width: 24)
            }
            
            if col == .size {
                Spacer(minLength: 0)
            }
            
            Text(col.title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSorted ? .accentColor : .secondary)
                .lineLimit(1)
            
            if isSorted {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            
            if col != .size {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: w, height: 22, alignment: col == .size ? .trailing : .leading)
        .contentShape(Rectangle())
        .opacity(isDragged ? 0.45 : 1.0)
        .background(
            isTarget ? Color.accentColor.opacity(0.16) : Color.clear
        )
        .overlay(
            // Sütun taşınırken bırakılacak hedefi gösteren Finder mavi çizgisi
            Group {
                if isTarget {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2.5)
                }
            },
            alignment: .leading
        )
        .onTapGesture {
            switch col {
            case .name: toggleSort(field: .name)
            case .date: toggleSort(field: .date)
            case .kind: toggleSort(field: .kind)
            case .size: toggleSort(field: .size)
            }
        }
        .onDrag {
            self.draggedColumn = col
            return NSItemProvider(object: col.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: ColumnHeaderDropDelegate(
            targetCol: col,
            draggedCol: $draggedColumn,
            targetHighlight: $dropTargetColumn,
            columnOrderRaw: $columnOrderRaw
        ))
    }
    
    // Sütun Ayraç Çizgisi ve Boyutlandırma (Finder Birebir)
    private func columnSplitter(for col: ExplorerColumnId) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor).opacity(0.85))
                .frame(width: 1, height: 16)
            
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10, height: 24)
                .contentShape(Rectangle())
        }
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if liveResizingCol != col {
                        liveResizingCol = col
                        switch col {
                        case .name: liveDragBaseWidth = max(col.minWidth, colNameWidth)
                        case .date: liveDragBaseWidth = max(col.minWidth, colDateWidth)
                        case .kind: liveDragBaseWidth = max(col.minWidth, colKindWidth)
                        case .size: liveDragBaseWidth = max(col.minWidth, colSizeWidth)
                        }
                    }
                    liveWidthDelta = Double(value.translation.width)
                }
                .onEnded { value in
                    let finalWidth = max(col.minWidth, liveDragBaseWidth + Double(value.translation.width))
                    setColumnWidth(finalWidth, for: col)
                    liveResizingCol = nil
                    liveWidthDelta = 0
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                setColumnWidth(col.defaultWidth, for: col)
            }
        )
    }

    private func resetColumnWidths() {
        colNameWidth = ExplorerColumnId.name.defaultWidth
        colDateWidth = ExplorerColumnId.date.defaultWidth
        colKindWidth = ExplorerColumnId.kind.defaultWidth
        colSizeWidth = ExplorerColumnId.size.defaultWidth
        columnOrderRaw = "name,date,kind,size"
        showColDate = true
        showColKind = true
        showColSize = true
    }

    @ViewBuilder
    private var headerContextMenu: some View {
        Toggle("Değiştirilme Tarihi", isOn: $showColDate)
        Toggle("Tür", isOn: $showColKind)
        Toggle("Boyut", isOn: $showColSize)
        Divider()
        Button("Sütunları ve Sıralamayı Sıfırla") {
            resetColumnWidths()
        }
    }

    private func setupEventMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Arama açıksa veya arama metni girilmişse tuşları yakalama, doğrudan arama alanına ilet
                if isSearchPresented || !searchText.isEmpty {
                    return event
                }
                
                // Kullanıcı herhangi bir metin kutusunda (Arama, Yeniden adlandırma vb.) yazı yazıyorsa araya girme!
                if let firstResponder = NSApp.keyWindow?.firstResponder {
                    let className = String(describing: type(of: firstResponder))
                    if firstResponder is NSText || firstResponder is NSTextField || firstResponder is NSTextView || className.contains("Text") || className.contains("Search") {
                        return event
                    }
                }
                guard renamingFileID == nil else { return event }
                
                // Escape tuşu (53): Arama aktifse aramayı tamamen kapat ve çubuğu eski boyutuna küçült
                if event.keyCode == 53 {
                    let firstResp = NSApp.keyWindow?.firstResponder
                    let firstRespName = firstResp != nil ? String(describing: type(of: firstResp!)) : ""
                    let inSearch = NativeExplorerView.isSearchActiveGlobal || firstResp is NSSearchField || firstRespName.contains("Search") || !searchText.isEmpty
                    if inSearch {
                        DispatchQueue.main.async {
                            NativeExplorerView.collapseSearch(in: NSApp.keyWindow)
                            NotificationCenter.default.post(name: .exitSearchRequested, object: nil)
                        }
                        return nil
                    }
                }
                
                // Boşluk tuşu: Metin düzenlenmiyorken Hızlı Bakış (QuickLook) aç / kapat
                if event.keyCode == 49 {
                    if quickLookURL != nil {
                        quickLookURL = nil
                    } else if let selID = selectedFileID, let file = files.first(where: { $0.id == selID }), !file.isDirectory {
                        triggerQuickLook(for: file)
                    }
                    return nil
                }
                
                let flags = event.modifierFlags
                if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
                    return event
                }
                if let chars = event.charactersIgnoringModifiers, chars.count == 1, let char = chars.first, (char.isLetter || char.isNumber) {
                    handleTypeToSelect(char: String(char))
                    return nil
                }
                return event
            }
        }
        
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard let win = event.window ?? NSApp.keyWindow else { return event }
                
                // Penceredeki arama kutusunu (NSSearchField) bul
                func findSearchField(in view: NSView) -> NSSearchField? {
                    if let sf = view as? NSSearchField { return sf }
                    for sub in view.subviews {
                        if let found = findSearchField(in: sub) { return found }
                    }
                    return nil
                }
                
                let sf = win.contentView?.superview.flatMap(findSearchField)
                let firstResp = win.firstResponder
                let firstRespName = firstResp != nil ? String(describing: type(of: firstResp!)) : ""
                let isSearchFocused = firstResp is NSSearchField || firstRespName.contains("Search") || firstRespName.contains("search") || (sf?.currentEditor() != nil)
                let hasSearchText = !(sf?.stringValue.isEmpty ?? true)
                
                var toolbarIsEditingSearch = false
                if let toolbar = win.toolbar {
                    for item in toolbar.items {
                        if let searchItem = item as? NSSearchToolbarItem {
                            if (searchItem.value(forKey: "isEditing") as? Bool) == true {
                                toolbarIsEditingSearch = true
                            }
                            if !searchItem.searchField.stringValue.isEmpty {
                                toolbarIsEditingSearch = true
                            }
                        }
                    }
                }
                
                let isSearchActive = NativeExplorerView.isSearchActiveGlobal || isSearchFocused || hasSearchText || toolbarIsEditingSearch
                
                if isSearchActive {
                    let hitView = win.contentView?.superview?.hitTest(event.locationInWindow)
                    var clickInSearch = false
                    var cur = hitView
                    while let v = cur {
                        let name = String(describing: type(of: v))
                        if v is NSSearchField || name.contains("Search") || name.contains("search") {
                            clickInSearch = true
                            break
                        }
                        if let sf = sf, (v === sf || v.isDescendant(of: sf)) {
                            clickInSearch = true
                            break
                        }
                        cur = v.superview
                    }
                    
                    // Arama alanının dışına tıklandıysa aramadan çık, çubuğu eski boyutuna küçült ve odağı kaldır
                    if !clickInSearch {
                        NativeExplorerView.isSearchActiveGlobal = false
                        DispatchQueue.main.async {
                            NativeExplorerView.collapseSearch(in: win)
                            NotificationCenter.default.post(name: .exitSearchRequested, object: nil)
                        }
                    }
                }
                return event
            }
        }
        
        if rightClickMonitor == nil {
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                guard let win = event.window ?? NSApp.keyWindow else { return event }
                let loc = event.locationInWindow
                let contentMaxY = win.contentLayoutRect.maxY
                
                // 1. Arama alanına tıklandıysa normal sağ tık metin menüsünü göster
                if let hitView = win.contentView?.superview?.hitTest(loc) {
                    if hitView is NSTextView || hitView is NSSearchField || hitView.superview is NSSearchField {
                        return event
                    }
                }
                
                // 2. Sol üst pencere kapatma/küçültme/büyütme (trafik ışıkları) hariç
                if loc.x < 80 && loc.y > (win.frame.height - 35) {
                    return event
                }
                
                // 3. Pencere içeriğinin üstünde mi (Toolbar / Titlebar bölgesinde mi?)
                let isAboveContent = loc.y >= (contentMaxY - 2)
                
                // 4. Tıklanan görünüm bir Toolbar bileşeni mi?
                var isToolbarView = false
                if let hitView = win.contentView?.superview?.hitTest(loc) {
                    var cur: NSView? = hitView
                    while let v = cur {
                        let name = NSStringFromClass(type(of: v))
                        if name.contains("Toolbar") || name.contains("Titlebar") {
                            isToolbarView = true
                            break
                        }
                        cur = v.superview
                    }
                }
                
                if isAboveContent || isToolbarView {
                    DispatchQueue.main.async {
                        self.showToolbarContextMenu(for: event, in: win)
                    }
                    return nil
                }
                
                return event
            }
        }
    }
    
    private func showToolbarContextMenu(for event: NSEvent, in window: NSWindow) {
        ToolbarMenuBridge.shared.onSelectMode = { mode in
            toolbarDisplayModeRaw = mode.rawValue
        }
        ToolbarMenuBridge.shared.onOpenCustomizer = {
            showingToolbarCustomizer = true
        }
        
        let menu = NSMenu(title: "ToolbarMenu")
        
        let iconAndText = NSMenuItem(title: "Simge ve Metin", action: #selector(ToolbarMenuBridge.shared.setIconAndText), keyEquivalent: "")
        iconAndText.target = ToolbarMenuBridge.shared
        iconAndText.state = (toolbarDisplayMode == .iconAndText) ? .on : .off
        menu.addItem(iconAndText)
        
        let iconOnly = NSMenuItem(title: "Yalnızca Simge", action: #selector(ToolbarMenuBridge.shared.setIconOnly), keyEquivalent: "")
        iconOnly.target = ToolbarMenuBridge.shared
        iconOnly.state = (toolbarDisplayMode == .iconOnly) ? .on : .off
        menu.addItem(iconOnly)
        
        menu.addItem(NSMenuItem.separator())
        
        let customize = NSMenuItem(title: "Araç Çubuğunu Özelleştir...", action: #selector(ToolbarMenuBridge.shared.openCustomizer), keyEquivalent: "")
        customize.target = ToolbarMenuBridge.shared
        menu.addItem(customize)
        
        if let hitView = window.contentView?.superview?.hitTest(event.locationInWindow) {
            NSMenu.popUpContextMenu(menu, with: event, for: hitView)
        } else if let contentView = window.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        }
    }

    public static func collapseSearch(in targetWindow: NSWindow? = nil) {
        let windows: [NSWindow]
        if let target = targetWindow {
            windows = [target]
        } else {
            windows = NSApp.windows
        }
        
        for win in windows {
            win.makeFirstResponder(nil)
            
            if let toolbar = win.toolbar {
                for item in toolbar.items {
                    if let searchItem = item as? NSSearchToolbarItem {
                        searchItem.searchField.stringValue = ""
                        searchItem.searchField.abortEditing()
                        
                        if let cell = searchItem.searchField.cell as? NSSearchFieldCell,
                           let cancelBtn = cell.cancelButtonCell,
                           let action = cancelBtn.action,
                           let target = cancelBtn.target {
                            _ = (target as AnyObject).perform(action, with: searchItem.searchField)
                        }
                        
                        searchItem.endSearchInteraction()
                        
                        let cancelSel = NSSelectorFromString("_searchToolbarItemSearchCancelled:")
                        if searchItem.responds(to: cancelSel) {
                            searchItem.perform(cancelSel, with: searchItem.searchField)
                        }
                        
                        searchItem.setValue(false, forKey: "isEditing")
                        
                        typealias SetExpandedFn = @convention(c) (AnyObject, Selector, Bool, Bool) -> Void
                        let sel = NSSelectorFromString("_setExpanded:animated:")
                        if let method = class_getInstanceMethod(NSSearchToolbarItem.self, sel) {
                            let imp = method_getImplementation(method)
                            let fn = unsafeBitCast(imp, to: SetExpandedFn.self)
                            fn(searchItem, sel, false, true)
                        }
                    } else if String(describing: type(of: item)).contains("Search") {
                        let endSel = NSSelectorFromString("endSearchInteraction")
                        if item.responds(to: endSel) {
                            item.perform(endSel)
                        }
                        let cancelSel = NSSelectorFromString("cancel")
                        if item.responds(to: cancelSel) {
                            item.perform(cancelSel)
                        }
                    }
                }
            }
            
            func clearSearchFields(in view: NSView) {
                if let sf = view as? NSSearchField {
                    sf.stringValue = ""
                    sf.abortEditing()
                    if let cell = sf.cell as? NSSearchFieldCell,
                       let cancelBtn = cell.cancelButtonCell,
                       let action = cancelBtn.action,
                       let target = cancelBtn.target {
                        _ = (target as AnyObject).perform(action, with: sf)
                    }
                }
                for sub in view.subviews {
                    clearSearchFields(in: sub)
                }
            }
            if let root = win.contentView?.superview {
                clearSearchFields(in: root)
            }
        }
    }

    private func exitSearch() {
        NativeExplorerView.isSearchActiveGlobal = false
        isSearchPresented = false
        searchText = ""
        isDeepSearchEnabled = false
        deepSearchResults = []
        NativeExplorerView.collapseSearch(in: NSApp.keyWindow)
    }

    private func handleTypeToSelect(char: String) {
        typeToSelectWorkItem?.cancel()
        typeToSelectQuery += char.lowercased(with: Locale(identifier: "tr_TR"))
        
        let query = typeToSelectQuery
        if let match = filteredFiles.first(where: { $0.name.matchesSearchQuery(query) }) {
            selectedFileIDs = [match.id]
            selectedFileID = match.id
        }
        
        let work = DispatchWorkItem { [self] in
            typeToSelectQuery = ""
        }
        typeToSelectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    
    // MARK: - 1. Sol Menü (Sidebar)
    private var sidebarView: some View {
        VStack(spacing: 0) {
            List {
                // HESAPLAR (Sadece Bağlantısı Açık Olanlar Yan Menüde Görünür)
                let connectedServers = manager.servers.filter { $0.isConnected }
                if !connectedServers.isEmpty {
                    Section(header: Text("Hesaplar")) {
                        ForEach(connectedServers) { server in
                            let isServerActive = (manager.activeServer?.id == server.id)
                            Button(action: {
                                if NSEvent.modifierFlags.contains(.command) {
                                    addNewTab(server: server)
                                } else {
                                    openServerInTab(server)
                                }
                            }) {
                                HStack(spacing: 8) {
                                    ProviderLogoBadge(storageProtocol: server.storageProtocol, size: 20)
                                    Text(server.name)
                                        .font(.system(size: 13, weight: isServerActive ? .semibold : .regular))
                                        .foregroundColor(isServerActive ? .primary : .secondary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if isServerActive {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.indigo)
                                    }
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(action: { addNewTab(server: server) }) {
                                    Label("Yeni Sekmede Aç", systemImage: "plus.rectangle.on.rectangle")
                                }
                            }
                        }
                    }
                }
                
                // FAVORİLER (Sabitlenen Kısayol Klasörler)
                Section("Favoriler") {
                    if pinnedFolders.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "pin")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Klasör sabitlemek için sürükleyin veya sağ tıklayın")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(pinnedFolders) { folder in
                            let isCurrent = currentPath == folder.path
                            Button(action: { navigateTo(folder.path) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: isCurrent ? "folder.fill" : "folder")
                                        .foregroundColor(isCurrent ? .accentColor : .secondary)
                                        .font(.system(size: 13))
                                    
                                    Text(folder.name)
                                        .font(.system(size: 13))
                                        .foregroundColor(isCurrent ? .primary : .primary.opacity(0.85))
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(action: { navigateTo(folder.path) }) {
                                    Label("Klasöre Git", systemImage: "folder")
                                }
                                Divider()
                                Button(role: .destructive, action: { unpinFolder(path: folder.path) }) {
                                    Label("Kenar Çubuğundan Kaldır", systemImage: "pin.slash")
                                }
                            }
                        }
                    }
                }
                .onDrop(of: [.plainText, .utf8PlainText, .fileURL], isTargeted: $isSidebarDropTargeted) { providers in
                    handleSidebarFolderDrop(providers)
                }
            }
            .listStyle(.sidebar)
            
            // SABİT ALT KULLANIM / DEPOLAMA ALANI (Floating Sidebar Storage Card)
            sidebarStorageFooterView
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }
    
    // MARK: - Yerel Mac Depolama Boyutu
    private var localDiskQuota: StorageQuota {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let total = attrs[.systemSize] as? Int64,
           let free = attrs[.systemFreeSize] as? Int64 {
            let used = max(0, total - free)
            return StorageQuota(usedBytes: used, availableBytes: free)
        }
        return StorageQuota(usedBytes: 0, availableBytes: 0)
    }

    // MARK: - Sabit Alt Kullanım / Depolama Bölümü (Modern Sidebar Card)
    private var sidebarStorageFooterView: some View {
        let server = activeTabServer
        let quota = currentStorageQuota
        let local = localDiskQuota
        let isLocalOrSmb = server == nil || server?.storageProtocol == .smb

        // Gösterilecek depolama verileri:
        let (displayTitle, displayUsed, displayTotal, displayPct, hasValidQuota): (String, String, String, Double, Bool) = {
            if let server = server {
                if let q = quota, q.totalBytes > 0 {
                    return (server.name, q.formattedUsed, q.formattedTotal, q.usedPercentage, true)
                } else if let q = quota, q.usedBytes > 0 {
                    return (server.name, q.formattedUsed, "Bulut", 0.0, false)
                } else if isLocalOrSmb {
                    return (server.name, local.formattedUsed, local.formattedTotal, local.usedPercentage, true)
                } else if isLoadingQuota {
                    return (server.name, "Yükleniyor...", "--", 0.0, false)
                } else {
                    // Uzak bulut sürücüsü (Google Drive, OneDrive vb.) ve API kotası yoksa
                    // ASLA yerel Mac diskini gösterme! Klasördeki dosyaların gerçek boyutunu hesapla:
                    let filesBytes = files.reduce(Int64(0)) { $0 + $1.size }
                    if files.isEmpty {
                        return (server.name, "0 B", "0 Öge", 0.0, false)
                    } else {
                        let formattedFilesSize = ByteCountFormatter.string(fromByteCount: filesBytes, countStyle: .file)
                        return (server.name, formattedFilesSize, "\(files.count) Öge", 0.0, false)
                    }
                }
            } else {
                return ("Macintosh HD", local.formattedUsed, local.formattedTotal, local.usedPercentage, true)
            }
        }()

        let pctInt = Int(round(displayPct * 100))
        let barColor: Color = {
            if !hasValidQuota && displayPct == 0 {
                return Color.secondary
            }
            if displayPct > 0.90 { return Color(red: 0.95, green: 0.30, blue: 0.25) }
            if displayPct > 0.75 { return Color(red: 0.98, green: 0.60, blue: 0.15) }
            return Color(red: 0.0, green: 0.48, blue: 1.0)
        }()

        return VStack(spacing: 8) {
            // 1. Satır: İkon + İsim + Yüzdelik Canlı Rozet
            HStack(spacing: 7) {
                if let server = server {
                    ProviderLogoBadge(storageProtocol: server.storageProtocol, size: 18)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 18, height: 18)
                        Image(systemName: "internaldrive.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Text(displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Canlı Yüzdelik Rozeti (Working Percentage Capsule)
                if hasValidQuota {
                    Text("%\(pctInt)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(barColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(barColor.opacity(0.12))
                        .clipShape(Capsule())
                } else if isLoadingQuota {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Text("%0")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            // 2. Satır: Özel Degrade İlerleme Çubuğu (Custom Sleek Progress Capsule)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 5)

                    if hasValidQuota && displayPct > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [barColor, barColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(5, geo.size.width * CGFloat(min(1.0, max(0.02, displayPct)))), height: 5)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayPct)
                    }
                }
            }
            .frame(height: 5)

            // 3. Satır: Kullanım Metni + Yenile Butonu
            HStack(spacing: 4) {
                Text("\(displayUsed) / \(displayTotal)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    if let server = server {
                        loadStorageQuota(for: server)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(isLoadingQuota ? Color.accentColor : Color.secondary)
                        .rotationEffect(.degrees(isLoadingQuota ? 360 : 0))
                        .animation(isLoadingQuota ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: isLoadingQuota)
                }
                .buttonStyle(.plain)
                .help("Depolama bilgisini yenile")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.separatorColor).opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .onAppear {
            if let server = server {
                loadStorageQuota(for: server)
            }
        }
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
                .accessibilityIdentifier("searchScope")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor))
        .contextMenu {
            Button(action: { showingToolbarCustomizer = true }) {
                Label("Araç Çubuğunu Özelleştir...", systemImage: "slider.horizontal.3")
            }
        }
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
                            .font(.subheadline)
                            .foregroundColor(idx == segments.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if isFolderPinned(path: subPath) {
                            Button(action: { unpinFolder(path: subPath) }) {
                                Label("Kenar Çubuğundan Kaldır", systemImage: "pin.slash")
                            }
                        } else {
                            Button(action: { pinFolder(name: segments[idx], path: subPath) }) {
                                Label("Kenar Çubuğuna Sabitle", systemImage: "pin")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 3. Dosyalar Alanı (Izgara / Liste)
    private var mainFilesAreaView: some View {
        Group {
            if manager.activeServer == nil || manager.activeServer?.serverURL.isEmpty == true {
                VStack(spacing: 16) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.indigo.opacity(0.15), .blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.indigo)
                    }
                    
                    Text("Bağlı Bulut Sürücüsü Yok")
                        .font(.title3.bold())
                    
                    Text("Dosyalarınıza erişmek için Google Drive, OneDrive, WebDAV veya S3 hesabınızı ekleyin.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    
                    Button(action: {
                        SettingsWindowManager.shared.showSettings {
                            loadDirectory(at: currentPath)
                        }
                    }) {
                        Label("Bulut Sürücüsü Ekle", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .padding(.top, 6)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
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
                if let s = manager.activeServer, (s.storageProtocol == .googleDrive || s.storageProtocol == .oneDrive) && s.password.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        ProviderLogoBadge(storageProtocol: s.storageProtocol, size: 56)
                        Text("\(s.storageProtocol.providerName) Oturumu Açılmamış")
                            .font(.headline)
                        Text("Bu sürücüdeki dosyalarınıza erişmek için Ayarlar ekranından hesabınıza giriş yapmanız gerekmektedir.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                        Button(action: {
                            SettingsWindowManager.shared.showSettings()
                        }) {
                            Text("\(s.storageProtocol.providerName) Hesabına Giriş Yap")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .padding(.top, 4)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
                }
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
                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: totalColumnsWidth > geo.size.width) {
                        VStack(spacing: 0) {
                            listHeaderView
                            Divider()
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 2) {
                                    ForEach(Array(filteredFiles.enumerated()), id: \.element.id) { index, file in
                                        fileRowItem(file, isEven: index % 2 == 0)
                                    }
                                }
                                .padding(10)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minWidth: max(geo.size.width, totalColumnsWidth), maxWidth: .infinity, maxHeight: geo.size.height, alignment: .topLeading)
                    }
                }
                .frame(minWidth: 150, maxWidth: .infinity, maxHeight: .infinity)
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
                if let img = previewManager.cachedImages[file.id] {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 50)
                        .cornerRadius(4)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                } else {
                    Image(nsImage: FileIconProvider.shared.icon(for: file.name, isDirectory: file.isDirectory, size: 64, contentType: file.contentType))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 50)
                        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                }
            }
            .onAppear {
                if (file.isImage || file.thumbnailURL != nil), let server = manager.activeServer {
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
                    .font(.caption)
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
        ._onButtonGesture(
            pressing: { isPressed in
                if isPressed {
                    handleFilePress(file)
                }
            },
            perform: {}
        )
        .onDrag({
            exportFileForDrag(file)
        }, preview: {
            dragPreview(for: file)
        })
        .contextMenu {
            fileContextMenu(file)
        }
    }
    
    // MARK: - Dosya Liste Satırı (Finder Standart Hizalama & Zebra Striping)
    private func fileRowItem(_ file: RemoteFileItem, isEven: Bool = false) -> some View {
        let isHovered = hoveredFileID == file.id
        let isSelected = selectedFileIDs.contains(file.id) || selectedFileID == file.id
        let isRenaming = renamingFileID == file.id
        let visibleCols = columnOrder.filter { isColumnVisible($0) }
        
        return HStack(spacing: 0) {
            ForEach(visibleCols, id: \.id) { col in
                fileCellView(file: file, col: col, isSelected: isSelected, isRenaming: isRenaming)
                
                // Header ile birebir aynı hizalama (splitter payı: 10 pt)
                Spacer().frame(width: 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? Color.primary.opacity(0.06) : (isEven ? Color(NSColor.controlBackgroundColor).opacity(0.25) : Color.clear)))
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
        ._onButtonGesture(
            pressing: { isPressed in
                if isPressed {
                    handleFilePress(file)
                }
            },
            perform: {}
        )
        .onDrag({
            exportFileForDrag(file)
        }, preview: {
            dragPreview(for: file)
        })
        .contextMenu {
            fileContextMenu(file)
        }
        .onAppear {
            if (file.isImage || file.thumbnailURL != nil), let server = manager.activeServer {
                let client = WebDAVClient(config: server)
                previewManager.loadThumbnail(for: file, client: client)
            }
        }
    }
    
    // MARK: - Sürükleme Önizleme Rozeti (Finder Standart Rozet)
    private func dragPreview(for file: RemoteFileItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: FileIconProvider.shared.icon(for: file.name, isDirectory: file.isDirectory, size: 28, contentType: file.contentType))
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            
            Text(file.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
    
    @ViewBuilder
    private func fileCellView(file: RemoteFileItem, col: ExplorerColumnId, isSelected: Bool, isRenaming: Bool) -> some View {
        let w = columnWidth(for: col)
        
        switch col {
        case .name:
            HStack(spacing: 8) {
                if let img = previewManager.cachedImages[file.id] {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .cornerRadius(3)
                } else {
                    Image(nsImage: FileIconProvider.shared.icon(for: file.name, isDirectory: file.isDirectory, size: 20, contentType: file.contentType))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                }
                
                if isRenaming {
                    TextField("Dosya Adı", text: $renamingText, onCommit: {
                        commitRename(file)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.body)
                    .frame(maxWidth: .infinity)
                } else {
                    Text(file.name)
                        .font(.body)
                        .foregroundColor(isSelected ? Color.accentColor : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: w, alignment: .leading)
            
        case .date:
            Text(file.modificationDate.map { dateFormatter.string(from: $0) } ?? "--")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(width: w, alignment: .leading)
                
        case .kind:
            Text(file.kindDescription)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(width: w, alignment: .leading)
                
        case .size:
            Text(file.formattedSize)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(width: w, alignment: .trailing)
        }
    }
    
    // MARK: - Sağ Tık Menüsü (Context Menu)
    @ViewBuilder
    private func fileContextMenu(_ file: RemoteFileItem) -> some View {
        if !file.isDirectory {
            Button(action: { openFileDirectly(file) }) {
                Label("Mac Uygulamasıyla Aç", systemImage: "arrow.up.forward.app")
            }
            if manager.activeServer?.storageProtocol == .googleDrive,
               let mime = file.contentType, mime.hasPrefix("application/vnd.google-apps.") {
                Button(action: {
                    if let url = URL(string: "https://drive.google.com/open?id=\(file.id)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Google Web Editöründe Aç", systemImage: "globe")
                }
            }
            Button(action: { triggerQuickLook(for: file) }) {
                Label("Görüntüle (Hızlı Bakış)", systemImage: "eye")
            }
        } else {
            Button(action: { handleDoubleClick(file) }) {
                Label("Klasörü Aç", systemImage: "folder")
            }
            
            let folderPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            if isFolderPinned(path: folderPath) {
                Button(action: { unpinFolder(path: folderPath) }) {
                    Label("Kenar Çubuğundan Kaldır", systemImage: "pin.slash")
                }
            } else {
                Button(action: { pinFolder(name: file.name, path: folderPath) }) {
                    Label("Kenar Çubuğuna Sabitle", systemImage: "pin")
                }
            }
        }
        
        Divider()
        
        Button(action: { copySelectedFiles() }) {
            Label("Kopyala (⌘C)", systemImage: "doc.on.doc")
        }
        
        Button(action: { cutSelectedFiles() }) {
            Label("Kes (⌘X)", systemImage: "scissors")
        }
        
        Button(action: { pasteFiles() }) {
            Label("Yapıştır (⌘V)", systemImage: "doc.on.clipboard")
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
    
    // MARK: - 4. Alt Durum Çubuğu (Yerel macOS Finder Görünümü)
    private var bottomStatusBarView: some View {
        HStack {
            if let opening = opener.openingFile {
                ProgressView()
                    .scaleEffect(0.6)
                Text("'\(opening)' açılıyor...")
                    .font(.caption2)
                    .foregroundColor(.indigo)
            } else {
                HStack(spacing: 6) {
                    Text("\(filteredFiles.count) öge")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    let selCount = selectedFileIDs.count > 0 ? selectedFileIDs.count : (selectedFileID != nil ? 1 : 0)
                    if selCount > 0 {
                        Text("• \(selCount) seçili")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            let selCount = selectedFileIDs.count > 0 ? selectedFileIDs.count : (selectedFileID != nil ? 1 : 0)
            if selCount > 0 {
                Button(action: { downloadSelectedFiles() }) {
                    Label(selCount > 1 ? "\(selCount) Ögeyi İndir" : "İndir", systemImage: "arrow.down.circle")
                        .font(.caption2)
                }
                .buttonStyle(BorderlessButtonStyle())
                .padding(.horizontal, 4)
                
                Button(action: { deleteSelectedFiles() }) {
                    Label(selCount > 1 ? "\(selCount) Ögeyi Sil" : "Sil", systemImage: "trash")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            
            Spacer()
            
            // Yerel Finder Hissiyatı: Kullanılabilir Depolama Alanı veya Sunucu Adı
            if let server = activeTabServer, let quota = currentStorageQuota {
                if quota.totalBytes > 0 {
                    Text("\(server.name): \(quota.formattedAvailable) kullanılabilir / \(quota.formattedTotal)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(server.name): \(quota.formattedUsed) kullanılıyor")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if let server = activeTabServer {
                let isLocalOrSmb = server.storageProtocol == .smb
                if isLocalOrSmb {
                    let local = localDiskQuota
                    Text("\(server.name): \(local.formattedAvailable) kullanılabilir")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if !files.isEmpty {
                    let totalSize = files.reduce(Int64(0)) { $0 + $1.size }
                    Text("\(server.name): \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text(server.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Dosyaya Çift Tıklama Mantığı (Mac'in Yerel Programıyla Doğrudan Açar)
    private func handleDoubleClick(_ file: RemoteFileItem) {
        if file.isDirectory {
            // Klasör ise içine gir
            let isGDrive = (manager.activeServer?.storageProtocol == .googleDrive)
            let newPath = isGDrive ? file.id : (currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)")
            navigateTo(newPath)
        } else {
            // Dosya ise Mac'in varsayılan uygulamasıyla (Excel, Word, Preview, VLC vb.) doğrudan aç
            openFileDirectly(file)
        }
    }
    
    private func openFileDirectly(_ file: RemoteFileItem) {
        guard let server = manager.activeServer, !server.serverURL.isEmpty else {
            statusAlertMessage = "Lütfen önce bir sunucu seçin veya yapılandırın."
            return
        }
        let client = WebDAVClient(config: server)
        opener.openFileNatively(file: file, client: client) { success, errorMsg in
            if !success, let msg = errorMsg {
                self.statusAlertMessage = msg
            }
        }
    }
    
    // MARK: - Gezinti ve Sıralama
    private var filteredFiles: [RemoteFileItem] {
        var result = (isDeepSearchEnabled && !searchText.isEmpty) ? deepSearchResults : files
        if !searchText.isEmpty && !isDeepSearchEnabled {
            result = result.filter { $0.name.matchesSearchQuery(searchText) }
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
        withAnimation(.easeInOut(duration: 0.2)) {
            showPreviewPane.toggle()
        }
        if showPreviewPane && selectedFileID == nil {
            selectedFileID = filteredFiles.first?.id
            if let first = filteredFiles.first, (first.isImage || first.thumbnailURL != nil), let server = manager.activeServer {
                let client = WebDAVClient(config: server)
                previewManager.loadThumbnail(for: first, client: client)
            }
        }
        if showPreviewPane {
            ensureWindowWidthForPreview()
        }
    }
    
    private func ensureWindowWidthForPreview() {
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                if window.frame.width < 960 {
                    var frame = window.frame
                    let diff = 960 - frame.width
                    frame.size.width = 960
                    frame.origin.x = max(0, frame.origin.x - diff / 2)
                    window.setFrame(frame, display: true, animate: true)
                }
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
        self.files = []
        self.selectedFileID = nil
        self.selectedFileIDs = []
        
        guard var server = manager.activeServer, !server.serverURL.isEmpty else {
            self.isLoading = false
            return
        }
        
        // OAuth sunucular için: password boşsa Keychain'den token'ı çek
        if (server.storageProtocol == .googleDrive || server.storageProtocol == .oneDrive) && server.password.isEmpty {
            if let savedToken = KeychainHelper.shared.get(account: server.id.uuidString), !savedToken.isEmpty {
                server.password = savedToken
                // Manager'daki in-memory kopyayı da güncelle
                if let idx = manager.servers.firstIndex(where: { $0.id == server.id }) {
                    manager.servers[idx].password = savedToken
                }
                if manager.activeServer?.id == server.id {
                    manager.activeServer?.password = savedToken
                }
            } else {
                self.isLoading = false
                return
            }
        }
        
        isLoading = true
        let client = WebDAVClient(config: server)
        loadStorageQuota(for: server)
        
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
                    if let selID = self.selectedFileID, let file = self.files.first(where: { $0.id == selID }), (file.isImage || file.thumbnailURL != nil) {
                        self.previewManager.loadThumbnail(for: file, client: client)
                    }
                }
            case .failure(let error):
                self.files = []
                print("Listeleme hatası: \(error)")
            }
        }
    }
    
    private func loadStorageQuota(for targetServer: CloudreveServerConfig? = nil) {
        guard var server = targetServer ?? activeTabServer else { return }
        
        // OAuth sağlayıcıları için token Keychain'deyse al
        if (server.storageProtocol == .googleDrive || server.storageProtocol == .oneDrive) && server.password.isEmpty {
            if let saved = KeychainHelper.shared.get(account: server.id.uuidString), !saved.isEmpty {
                server.password = saved
            }
        }
        
        isLoadingQuota = true
        let client = WebDAVClient(config: server)
        client.fetchQuota { result in
            DispatchQueue.main.async {
                self.isLoadingQuota = false
                switch result {
                case .success(let q):
                    self.storageQuotas[server.id] = q
                case .failure(let err):
                    print("[HDrive] Kota sorgulanamadı (\(server.name)): \(err.localizedDescription)")
                }
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
                    let matching = items.filter { $0.name.matchesSearchQuery(query) }
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
            let active = manager.activeServer
            let tabTitle = currentPath.isEmpty ? (active?.name ?? "Bulut Sürücüsü") : (currentPath as NSString).lastPathComponent
            tabs[idx].serverId = active?.id
            tabs[idx].title = tabTitle
            tabs[idx].path = currentPath
            tabs[idx].history = pathHistory
            tabs[idx].historyIndex = historyIndex
            tabs[idx].selectedFileID = selectedFileID
        }
    }
    
    private func addNewTab(server: CloudreveServerConfig? = nil, path: String = "") {
        saveCurrentTabState()
        let targetServer = server ?? manager.activeServer
        if let ts = targetServer, manager.activeServer?.id != ts.id {
            manager.setActiveServer(ts)
            loadPinnedFolders()
        }
        let tabTitle = path.isEmpty ? (targetServer?.name ?? "Bulut Sürücüsü") : (path as NSString).lastPathComponent
        let newTab = ExplorerTab(
            serverId: targetServer?.id,
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
    
    private func openServerInTab(_ server: CloudreveServerConfig) {
        if let currentTab = tabs.first(where: { $0.id == activeTabID }),
           currentTab.serverId == server.id && currentPath.isEmpty {
            return
        }
        
        saveCurrentTabState()
        if manager.activeServer?.id != server.id {
            manager.setActiveServer(server)
            loadPinnedFolders()
        }
        
        // Aktif sekmenin hesabını ve başlığını doğrudan seçilen hesaba geçir
        if let idx = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[idx].serverId = server.id
            tabs[idx].title = server.name
            tabs[idx].path = ""
            tabs[idx].history = [""]
            tabs[idx].historyIndex = 0
            tabs[idx].selectedFileID = nil
        }
        
        currentPath = ""
        pathHistory = [""]
        historyIndex = 0
        selectedFileID = nil
        loadDirectory(at: "")
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
        
        // Bu sekmeye ait farklı bir hesap varsa aktif hesabı o yap
        if let sId = targetTab.serverId, let tabServer = manager.servers.first(where: { $0.id == sId }) {
            if manager.activeServer?.id != tabServer.id {
                manager.setActiveServer(tabServer)
                loadPinnedFolders()
            }
        }
        
        currentPath = targetTab.path
        pathHistory = targetTab.history
        historyIndex = targetTab.historyIndex
        selectedFileID = targetTab.selectedFileID
        loadDirectory(at: targetTab.path)
    }

    private func navigateTo(_ path: String) {
        exitSearch()
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
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK, let server = manager.activeServer {
            let client = WebDAVClient(config: server)
            for selectedURL in panel.urls {
                TransferManager.shared.enqueueUpload(fileURL: selectedURL, remoteFolder: currentPath, client: client)
            }
            showingTransferPopover = true
        }
    }
    
    private func downloadFile(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else { return }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Dosyayı Kaydet"
        savePanel.prompt = "Kaydet"
        savePanel.nameFieldStringValue = file.name
        savePanel.canCreateDirectories = true
        
        if savePanel.runModal() != .OK {
            return
        }
        guard let target = savePanel.url else { return }
        
        let client = WebDAVClient(config: server)
        let relPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
        TransferManager.shared.enqueueDownload(fileName: file.name, remoteHref: relPath, localTargetURL: target, client: client, expectedSize: file.size)
        showingTransferPopover = true
    }
    
    private func deleteFile(_ file: RemoteFileItem) {
        let alert = NSAlert()
        alert.messageText = "'\(file.name)' Silinsin mi?"
        alert.informativeText = "Bu \(file.isDirectory ? "klasörü ve içindeki tüm dosyaları" : "dosyayı") kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sil")
        alert.addButton(withTitle: "Vazgeç")
        
        if alert.runModal() != .alertFirstButtonReturn {
            return
        }
        
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        let relPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
        isLoading = true
        client.delete(at: relPath, isDirectory: file.isDirectory) { error in
            if error != nil {
                client.delete(at: file.href, isDirectory: file.isDirectory) { err2 in
                    isLoading = false
                    if err2 == nil {
                        SyncLogManager.shared.log("Silindi: \(file.name)")
                        clearSelection()
                        loadDirectory(at: currentPath)
                    } else {
                        SyncLogManager.shared.log("Silme hatası: \(file.name) - \(err2?.localizedDescription ?? "")", isError: true)
                    }
                }
            } else {
                isLoading = false
                SyncLogManager.shared.log("Silindi: \(file.name)")
                clearSelection()
                loadDirectory(at: currentPath)
            }
        }
    }
    
    // MARK: - Çoklu Seçim ve Anında Tıklama / Çift Tıklama İşlemleri (0ms mouseDown)
    private func handleFilePress(_ file: RemoteFileItem) {
        let now = Date()
        let isDoubleClick = (lastClickedFileID == file.id) && (now.timeIntervalSince(lastClickTime) < 0.35)
        
        // İlk tıklamada anında (0ms) seçimi güncelle, çerçeve/vurgu anında gelsin
        handleFileTap(file)
        
        if isDoubleClick {
            lastClickTime = Date.distantPast
            lastClickedFileID = nil
            handleDoubleClick(file)
        } else {
            lastClickTime = now
            lastClickedFileID = file.id
            if (file.isImage || file.thumbnailURL != nil), let server = manager.activeServer {
                let client = WebDAVClient(config: server)
                previewManager.loadThumbnail(for: file, client: client)
            }
        }
    }

    private func handleFileTap(_ file: RemoteFileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.control) {
            if selectedFileIDs.contains(file.id) {
                selectedFileIDs.remove(file.id)
                if selectedFileID == file.id {
                    selectedFileID = selectedFileIDs.first
                }
            } else {
                selectedFileIDs.insert(file.id)
                selectedFileID = file.id
            }
        } else if flags.contains(.shift) {
            let anchorIdx = (selectedFileID.flatMap { id in filteredFiles.firstIndex(where: { $0.id == id }) }) ?? 0
            if let targetIdx = filteredFiles.firstIndex(where: { $0.id == file.id }) {
                let start = min(anchorIdx, targetIdx)
                let end = max(anchorIdx, targetIdx)
                selectedFileIDs = Set(filteredFiles[start...end].map { $0.id })
            }
        } else {
            selectedFileIDs = [file.id]
            selectedFileID = file.id
        }
    }

    private func selectPreviousFile() {
        guard !filteredFiles.isEmpty else { return }
        let currentIdx = selectedFileID.flatMap { id in filteredFiles.firstIndex(where: { $0.id == id }) } ?? 0
        let newIdx = max(0, currentIdx - 1)
        let file = filteredFiles[newIdx]
        selectedFileIDs = [file.id]
        selectedFileID = file.id
        if quickLookURL != nil && !file.isDirectory {
            triggerQuickLook(for: file)
        }
    }

    private func selectNextFile() {
        guard !filteredFiles.isEmpty else { return }
        let currentIdx = selectedFileID.flatMap { id in filteredFiles.firstIndex(where: { $0.id == id }) } ?? -1
        let newIdx = min(filteredFiles.count - 1, currentIdx + 1)
        let file = filteredFiles[newIdx]
        selectedFileIDs = [file.id]
        selectedFileID = file.id
        if quickLookURL != nil && !file.isDirectory {
            triggerQuickLook(for: file)
        }
    }

    private func expandSelectionUp() {
        guard !filteredFiles.isEmpty else { return }
        let anchorIdx = (selectedFileID.flatMap { id in filteredFiles.firstIndex(where: { $0.id == id }) }) ?? 0
        let currentIdx = selectedFileIDs.compactMap { id in filteredFiles.firstIndex(where: { $0.id == id }) }.min() ?? anchorIdx
        let newIdx = max(0, currentIdx - 1)
        let start = min(anchorIdx, newIdx)
        let end = max(anchorIdx, newIdx)
        selectedFileIDs = Set(filteredFiles[start...end].map { $0.id })
    }

    private func expandSelectionDown() {
        guard !filteredFiles.isEmpty else { return }
        let anchorIdx = (selectedFileID.flatMap { id in filteredFiles.firstIndex(where: { $0.id == id }) }) ?? 0
        let currentIdx = selectedFileIDs.compactMap { id in filteredFiles.firstIndex(where: { $0.id == id }) }.max() ?? anchorIdx
        let newIdx = min(filteredFiles.count - 1, currentIdx + 1)
        let start = min(anchorIdx, newIdx)
        let end = max(anchorIdx, newIdx)
        selectedFileIDs = Set(filteredFiles[start...end].map { $0.id })
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
        let targets = filteredFiles.filter { selectedFileIDs.contains($0.id) || selectedFileID == $0.id }
        guard !targets.isEmpty, let server = manager.activeServer else { return }
        
        if targets.count == 1 {
            deleteFile(targets[0])
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Seçili \(targets.count) Öğe Silinsin mi?"
        alert.informativeText = "Seçilen \(targets.count) öğeyi buluttan kalıcı olarak silmek istediğinizden emin misiniz? Bu işlem geri alınamaz."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Sil")
        alert.addButton(withTitle: "Vazgeç")
        
        if alert.runModal() != .alertFirstButtonReturn {
            return
        }
        
        isLoading = true
        let client = WebDAVClient(config: server)
        let group = DispatchGroup()
        for file in targets {
            group.enter()
            let relPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            client.delete(at: relPath, isDirectory: file.isDirectory) { error in
                if error != nil {
                    // Fallback olarak file.href dene
                    client.delete(at: file.href, isDirectory: file.isDirectory) { _ in
                        group.leave()
                    }
                } else {
                    SyncLogManager.shared.log("Silindi: \(file.name)")
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            isLoading = false
            clearSelection()
            loadDirectory(at: currentPath)
        }
    }
    
    private func downloadSelectedFiles() {
        let targets = filteredFiles.filter { selectedFileIDs.contains($0.id) || selectedFileID == $0.id }
        guard !targets.isEmpty, let server = manager.activeServer else { return }
        
        let fileTargets = targets.filter { !$0.isDirectory }
        guard !fileTargets.isEmpty else { return }
        
        if fileTargets.count == 1 {
            downloadFile(fileTargets[0])
            return
        }
        
        let openPanel = NSOpenPanel()
        openPanel.title = "İndirme Konumunu Seçin"
        openPanel.prompt = "Bu Klasöre İndir"
        openPanel.message = "Seçilen \(fileTargets.count) dosyanın kaydedileceği klasörü seçin:"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        
        if openPanel.runModal() != .OK {
            return
        }
        guard let destinationFolder = openPanel.url else { return }
        
        let client = WebDAVClient(config: server)
        isLoading = true
        let group = DispatchGroup()
        var downloadedURLs: [URL] = []
        let lock = NSLock()
        
        for file in fileTargets {
            group.enter()
            let dest = destinationFolder.appendingPathComponent(file.name)
            let relPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            client.downloadFile(href: relPath, to: dest, progress: { _ in }, completion: { error in
                if error == nil && FileManager.default.fileExists(atPath: dest.path) {
                    lock.lock()
                    downloadedURLs.append(dest)
                    lock.unlock()
                    SyncLogManager.shared.log("İndirildi: \(file.name)")
                    group.leave()
                } else {
                    client.downloadFile(href: file.href, to: dest, progress: { _ in }, completion: { err2 in
                        if err2 == nil && FileManager.default.fileExists(atPath: dest.path) {
                            lock.lock()
                            downloadedURLs.append(dest)
                            lock.unlock()
                            SyncLogManager.shared.log("İndirildi: \(file.name)")
                        } else {
                            SyncLogManager.shared.log("İndirme hatası: \(file.name) - \(err2?.localizedDescription ?? "")", isError: true)
                        }
                        group.leave()
                    })
                }
            })
        }
        
        group.notify(queue: .main) {
            isLoading = false
            if !downloadedURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(downloadedURLs)
            }
        }
    }

    
    // MARK: - Sistem Panosu (Kopyala, Kes, Yapıştır)
    private func copySelectedFiles() {
        let targets = filteredFiles.filter { selectedFileIDs.contains($0.id) || selectedFileID == $0.id }
        guard !targets.isEmpty, let server = manager.activeServer else { return }
        
        isClipboardCut = false
        copiedRemoteItems = targets
        
        let client = WebDAVClient(config: server)
        let cacheDir = FileOpener.shared.cacheDir
        
        Task {
            var localURLs: [URL] = []
            for item in targets {
                if item.isDirectory {
                    let folderURL = cacheDir.appendingPathComponent(item.name, isDirectory: true)
                    try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    localURLs.append(folderURL)
                } else {
                    let cacheCandidate = cacheDir.appendingPathComponent(item.name)
                    let previewCandidate = FilePreviewManager.shared.previewCacheDir.appendingPathComponent(item.name)
                    
                    if FileManager.default.fileExists(atPath: cacheCandidate.path) {
                        localURLs.append(cacheCandidate)
                    } else if FileManager.default.fileExists(atPath: previewCandidate.path) {
                        localURLs.append(previewCandidate)
                    } else {
                        let dest = cacheCandidate
                        let relPath = currentPath.isEmpty ? item.name : "\(currentPath)/\(item.name)"
                        await withCheckedContinuation { continuation in
                            client.downloadFile(href: relPath, to: dest, progress: { _ in }) { err in
                                if err == nil && FileManager.default.fileExists(atPath: dest.path) {
                                    localURLs.append(dest)
                                    continuation.resume()
                                } else {
                                    client.downloadFile(href: item.href, to: dest, progress: { _ in }) { err2 in
                                        if err2 == nil && FileManager.default.fileExists(atPath: dest.path) {
                                            localURLs.append(dest)
                                        }
                                        continuation.resume()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            await MainActor.run {
                if !localURLs.isEmpty {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.writeObjects(localURLs as [NSURL])
                    
                    SyncLogManager.shared.log("\(localURLs.count) dosya panoya kopyalandı. Finder veya Masaüstüne yapıştırabilirsiniz.")
                }
            }
        }
    }
    
    private func cutSelectedFiles() {
        let targets = filteredFiles.filter { selectedFileIDs.contains($0.id) || selectedFileID == $0.id }
        guard !targets.isEmpty else { return }
        isClipboardCut = true
        copiedRemoteItems = targets
        copySelectedFiles()
    }
    
    private func pasteFiles() {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        
        // 1. Finder / Masaüstü vb. dışarıdan panoya kopyalanan dosyaları kontrol et
        if let fileURLs = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            isLoading = true
            let group = DispatchGroup()
            for url in fileURLs {
                group.enter()
                uploadLocalItemRecursively(localURL: url, remoteBaseDir: currentPath, client: client) {
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                isLoading = false
                loadDirectory(at: currentPath)
                SyncLogManager.shared.log("\(fileURLs.count) öge panodan başarıyla yüklendi.")
            }
            return
        }
        
        // 2. HDrive içi kesme / kopyalama
        if !copiedRemoteItems.isEmpty {
            isLoading = true
            let group = DispatchGroup()
            for item in copiedRemoteItems {
                group.enter()
                let dest = currentPath.isEmpty ? item.name : "\(currentPath)/\(item.name)"
                if isClipboardCut {
                    client.move(from: item.href, to: dest) { _ in
                        group.leave()
                    }
                } else {
                    client.copy(from: item.href, to: dest) { _ in
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                isLoading = false
                if isClipboardCut {
                    copiedRemoteItems.removeAll()
                    isClipboardCut = false
                }
                loadDirectory(at: currentPath)
                SyncLogManager.shared.log("Ögeler panodan başarıyla yapıştırıldı.")
            }
        }
    }
    
    // MARK: - Sürükle ve Bırak (Drag & Drop) Desteği
    private func exportFileForDrag(_ file: RemoteFileItem) -> NSItemProvider {
        let cacheDir = FileOpener.shared.cacheDir
        if file.isDirectory {
            let folderURL = cacheDir.appendingPathComponent(file.name, isDirectory: true)
            try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            return NSItemProvider(item: folderURL as NSURL, typeIdentifier: UTType.fileURL.identifier)
        }
        
        let cachedFile = cacheDir.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            return NSItemProvider(item: cachedFile as NSURL, typeIdentifier: UTType.fileURL.identifier)
        }
        
        let previewTarget = FilePreviewManager.shared.previewCacheDir.appendingPathComponent(file.name)
        if FileManager.default.fileExists(atPath: previewTarget.path) {
            return NSItemProvider(item: previewTarget as NSURL, typeIdentifier: UTType.fileURL.identifier)
        }
        
        // Arka planda indirmeyi tetikle
        if let server = manager.activeServer {
            let client = WebDAVClient(config: server)
            let relPath = currentPath.isEmpty ? file.name : "\(currentPath)/\(file.name)"
            client.downloadFile(href: relPath, to: cachedFile, progress: { _ in }) { _ in }
        }
        
        return NSItemProvider(item: cachedFile as NSURL, typeIdentifier: UTType.fileURL.identifier)
    }
    
    // MARK: - Favori Klasörleri Yönetme (Pinned Shortcuts)
    private var pinnedFoldersKey: String {
        let serverID = manager.activeServer?.id.uuidString ?? "global"
        return "HDrive_PinnedFolders_\(serverID)"
    }
    
    private func loadPinnedFolders() {
        if let data = UserDefaults.standard.data(forKey: pinnedFoldersKey),
           let items = try? JSONDecoder().decode([PinnedFolder].self, from: data) {
            self.pinnedFolders = items
        } else {
            self.pinnedFolders = []
        }
    }
    
    private func savePinnedFolders() {
        if let data = try? JSONEncoder().encode(pinnedFolders) {
            UserDefaults.standard.set(data, forKey: pinnedFoldersKey)
        }
    }
    
    private func pinFolder(name: String, path: String) {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanPath.isEmpty else { return }
        if !pinnedFolders.contains(where: { $0.path == cleanPath }) {
            pinnedFolders.append(PinnedFolder(name: name, path: cleanPath))
            savePinnedFolders()
        }
    }
    
    private func unpinFolder(path: String) {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        pinnedFolders.removeAll(where: { $0.path == cleanPath })
        savePinnedFolders()
    }
    
    private func isFolderPinned(path: String) -> Bool {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return pinnedFolders.contains(where: { $0.path == cleanPath })
    }
    
    private func handleSidebarFolderDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                if let str = item as? String, str.hasPrefix("hdrv-folder:") {
                    let payload = String(str.dropFirst("hdrv-folder:".count))
                    let parts = payload.components(separatedBy: "|")
                    if parts.count >= 2 {
                        let name = parts[0]
                        let path = parts[1]
                        DispatchQueue.main.async {
                            self.pinFolder(name: name, path: path)
                        }
                    }
                }
            }
            
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let localURL = url else { return }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir), isDir.boolValue {
                    let folderName = localURL.lastPathComponent
                    DispatchQueue.main.async {
                        self.pinFolder(name: folderName, path: folderName)
                    }
                }
            }
        }
        return true
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
    
    private var previewPaneSideView: some View {
        Group {
            if let selID = selectedFileID, let selected = files.first(where: { $0.id == selID }) {
                previewPaneView(selected)
                    .id(selID)
            } else {
                emptyPreviewPaneView
            }
        }
    }
    
    private func loadPreviewIfNeeded(for file: RemoteFileItem) {
        guard let server = manager.activeServer, !file.isDirectory else { return }
        let client = WebDAVClient(config: server)
        if file.isImage || file.thumbnailURL != nil {
            previewManager.loadThumbnail(for: file, client: client)
        }
        if !file.isImage && file.size < 25 * 1024 * 1024 && previewManager.resolvedLocalURL(for: file) == nil {
            previewManager.ensureLocalFile(file: file, client: client) { _ in }
        }
    }

    // MARK: - Canlı ve Çok Sayfalı Önizleme Bölmesi (Full Preview Pane)
    private func previewPaneView(_ file: RemoteFileItem) -> some View {
        VStack(spacing: 0) {
            // Üst Başlık Çubuğu: Sade Dosya Adı ve Sayfa Sayısı
            HStack(spacing: 8) {
                Image(nsImage: FileIconProvider.shared.icon(for: file.name, isDirectory: file.isDirectory, size: 16, contentType: file.contentType))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                
                Text(file.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                
                Spacer()
                
                if file.isPDF, let localURL = previewManager.resolvedLocalURL(for: file),
                   let doc = PDFDocument(url: localURL) {
                    Text("\(doc.pageCount) sayfa")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Tam Tuval İçerik Önizlemesi (Çok Sayfalı PDF / Görsel / QuickLook / Kod)
            ZStack {
                if file.isDirectory {
                    VStack(spacing: 12) {
                        Image(nsImage: FileIconProvider.shared.icon(for: file.name, isDirectory: true, size: 128))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .shadow(color: Color.black.opacity(0.10), radius: 6, y: 3)
                        Text(file.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if file.isPDF, let localURL = previewManager.resolvedLocalURL(for: file) {
                    // PDFKit: Çok sayfalı kesintisiz dikey kaydırmalı tam PDF önizlemesi
                    PDFRepresentableView(url: localURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if file.isImage, let img = previewManager.cachedImages[file.id] {
                    // Tam boyutlu görsel önizleme (Kaydırılabilir)
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .shadow(color: Color.black.opacity(0.10), radius: 6, y: 3)
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let localURL = previewManager.resolvedLocalURL(for: file) {
                    // Diğer tüm belgeler için QuickLook (Word, Excel, Metin vs. çok sayfalı kaydırma)
                    QuickLookRepresentable(url: localURL)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let img = previewManager.cachedImages[file.id] {
                    // Bulut küçük resmi hazırsa, arka planda tam dosya inerken göster
                    VStack(spacing: 8) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                            .cornerRadius(6)
                            .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
                            .padding(12)
                        
                        if previewManager.loadingPreviewIDs.contains(file.id) {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Tüm sayfalar yükleniyor...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if previewManager.loadingPreviewIDs.contains(file.id) {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Önizleme hazırlanıyor...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(nsImage: FileIconProvider.shared.icon(for: file.name, isDirectory: false, size: 128, contentType: file.contentType))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .shadow(color: Color.black.opacity(0.10), radius: 6, y: 3)
                        
                        Button("Önizlemeyi Yükle") {
                            guard let server = manager.activeServer else { return }
                            let client = WebDAVClient(config: server)
                            previewManager.ensureLocalFile(file: file, client: client) { _ in }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadPreviewIfNeeded(for: file)
        }
    }
    
    // MARK: - Önizleme Boş Durumu (Öğe Seçilmediğinde)
    private var emptyPreviewPaneView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(.secondary.opacity(0.35))
            
            Text("Seçili Öğe Yok")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text("Önizlemek için bir dosya seçin.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Cloudreve Ayarlar Modalı (macOS Sonoma / Sequoia Sistem Ayarları Standardı)
enum SettingsTab: String, CaseIterable, Identifiable {
    case account = "Hesap & Sunucu"
    case appearance = "Görünüm & Gezgin"
    case about = "Hakkında"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .account: return "cloud.fill"
        case .appearance: return "macwindow"
        case .about: return "info.circle.fill"
        }
    }
    
    var colors: [Color] {
        switch self {
        case .account: return [.blue, .cyan]
        case .appearance: return [.purple, .indigo]
        case .about: return [.gray, .secondary]
        }
    }
}

// MARK: - Orijinal Marka Logoları (Authentic Brand Logos)

// MARK: - Resmi Vektör Logo Motoru (Sıfır Bağımlılık, Sıfır Gecikme, Sonsuz Netlik)
/// Bulut depolama sağlayıcılarının en güncel ve resmi marka logolarını vektör SVG olarak
/// doğrudan bellekten 0 ms gecikmeyle sunar. Ağ bağlantısına bağımlı değildir,
/// gecikme ve yükleme aşaması oluşturmaz, tüm çözünürlüklerde (Retina/5K) mükemmel netliktedir.
final class ProviderLogoCache: NSObject {
    static let shared = ProviderLogoCache()
    let mem = NSCache<NSString, NSImage>()

    /// Sağlayıcıların güncel ve resmi vektör SVG tanımları
    private static let officialSVGs: [StorageProtocol: String] = [
        // 1. Google Drive (Resmi 4 renkli Workspace logosu - en güncel)
        .googleDrive: """
        <svg viewBox="-4.35 -9 96 96" xmlns="http://www.w3.org/2000/svg">
          <path d="m6.6 66.85 3.85 6.65c.8 1.4 1.95 2.5 3.3 3.3l13.75-23.8h-27.5c0 1.55.4 3.1 1.2 4.5z" fill="#0066da"/>
          <path d="m43.65 25-13.75-23.8c-1.35.8-2.5 1.9-3.3 3.3l-25.4 44a9.06 9.06 0 0 0 -1.2 4.5h27.5z" fill="#00ac47"/>
          <path d="m73.55 76.8c1.35-.8 2.5-1.9 3.3-3.3l1.6-2.75 7.65-13.25c.8-1.4 1.2-2.95 1.2-4.5h-27.502l5.852 11.5z" fill="#ea4335"/>
          <path d="m43.65 25 13.75-23.8c-1.35-.8-2.9-1.2-4.5-1.2h-18.5c-1.6 0-3.15.45-4.5 1.2z" fill="#00832d"/>
          <path d="m59.8 53h-32.3l-13.75 23.8c1.35.8 2.9 1.2 4.5 1.2h50.8c1.6 0 3.15-.45 4.5-1.2z" fill="#2684fc"/>
          <path d="m73.4 26.5-12.7-22c-.8-1.4-1.95-2.5-3.3-3.3l-13.75 23.8 16.15 28h27.45c0-1.55-.4-3.1-1.2-4.5z" fill="#ffba00"/>
        </svg>
        """,

        // 2. Microsoft OneDrive (Resmi Microsoft 365 Fluent Design Cloud - en güncel)
        .oneDrive: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -0.25 32 32">
          <path d="M12.20245,11.19292l.00031-.0011,6.71765,4.02379,4.00293-1.68451.00018.00068A6.4768,6.4768,0,0,1,25.5,13c.14764,0,.29358.0067.43878.01639a10.00075,10.00075,0,0,0-18.041-3.01381C7.932,10.00215,7.9657,10,8,10A7.96073,7.96073,0,0,1,12.20245,11.19292Z" fill="#0364b8"/>
          <path d="M12.20276,11.19182l-.00031.0011A7.96073,7.96073,0,0,0,8,10c-.0343,0-.06805.00215-.10223.00258A7.99676,7.99676,0,0,0,1.43732,22.57277l5.924-2.49292,2.63342-1.10819,5.86353-2.46746,3.06213-1.28859Z" fill="#0078d4"/>
          <path d="M25.93878,13.01639C25.79358,13.0067,25.64764,13,25.5,13a6.4768,6.4768,0,0,0-2.57648.53178l-.00018-.00068-4.00293,1.68451,1.16077.69528L23.88611,18.19l1.66009.99438,5.67633,3.40007a6.5002,6.5002,0,0,0-5.28375-9.56805Z" fill="#1490df"/>
          <path d="M25.5462,19.18437,23.88611,18.19l-3.80493-2.2791-1.16077-.69528L15.85828,16.5042,9.99475,18.97166,7.36133,20.07985l-5.924,2.49292A7.98889,7.98889,0,0,0,8,26H25.5a6.49837,6.49837,0,0,0,5.72253-3.41556Z" fill="#28a8ea"/>
        </svg>
        """,

        // 3. WebDAV / Nextcloud (Resmi Nextcloud Hub bağlı bulut halkaları)
        .webdav: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <path fill="#0082c9" d="M12.018 6.537c-2.5 0-4.6 1.712-5.241 4.015-.56-1.232-1.793-2.105-3.225-2.105A3.569 3.569 0 0 0 0 12a3.569 3.569 0 0 0 3.552 3.553c1.432 0 2.664-.874 3.224-2.106.641 2.304 2.742 4.016 5.242 4.016 2.487 0 4.576-1.693 5.231-3.977.569 1.21 1.783 2.067 3.198 2.067A3.568 3.568 0 0 0 24 12a3.569 3.569 0 0 0-3.553-3.553c-1.416 0-2.63.858-3.199 2.067-.654-2.284-2.743-3.978-5.23-3.977zm0 2.085c1.878 0 3.378 1.5 3.378 3.378 0 1.878-1.5 3.378-3.378 3.378A3.362 3.362 0 0 1 8.641 12c0-1.878 1.5-3.378 3.377-3.378zm-8.466 1.91c.822 0 1.467.645 1.467 1.468s-.644 1.467-1.467 1.468A1.452 1.452 0 0 1 2.085 12c0-.823.644-1.467 1.467-1.467zm16.895 0c.823 0 1.468.645 1.468 1.468s-.645 1.468-1.468 1.468A1.452 1.452 0 0 1 18.98 12c0-.823.644-1.467 1.467-1.467z"/>
        </svg>
        """,

        // 4. Amazon S3 (Resmi AWS Simple Storage Service S3 izometrik küp logosu - en güncel)
        .s3: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="-42 0 512 512">
          <path fill="#e25444" fill-rule="evenodd" d="M378,99L295,257l83,158,34-19V118Z"/>
          <path fill="#7b1d13" fill-rule="evenodd" d="M378,99L212,118,127.5,257,212,396l166,19V99Z"/>
          <path fill="#58150d" fill-rule="evenodd" d="M43,99L16,111V403l27,12L212,257Z"/>
          <path fill="#e25444" fill-rule="evenodd" d="M42.637,98.667l169.587,47.111V372.444L42.637,415.111V98.667Z"/>
          <path fill="#58150d" fill-rule="evenodd" d="M212.313,170.667l-72.008-11.556,72.008-81.778,71.83,81.778Z"/>
          <path fill="#58150d" fill-rule="evenodd" d="M284.143,159.111l-71.919,11.733-71.919-11.733V77.333"/>
          <path fill="#58150d" fill-rule="evenodd" d="M212.313,342.222l-72.008,13.334,72.008,70.222,71.83-70.222Z"/>
          <path fill="#7b1d13" fill-rule="evenodd" d="M212,16L140,54V159l72.224-20.333Z"/>
          <path fill="#7b1d13" fill-rule="evenodd" d="M212.224,196.444l-71.919,7.823V309.105l71.919,8.228V196.444Z"/>
          <path fill="#7b1d13" fill-rule="evenodd" d="M212.224,373.333L140.305,355.3V458.363L212.224,496V373.333Z"/>
          <path fill="#e25444" fill-rule="evenodd" d="M284.143,355.3l-71.919,18.038V496l71.919-37.637V355.3Z"/>
          <path fill="#e25444" fill-rule="evenodd" d="M212.224,196.444l71.919,7.823V309.105l-71.919,8.228V196.444Z"/>
          <path fill="#e25444" fill-rule="evenodd" d="M212,16l72,38V159l-72-20V16Z"/>
        </svg>
        """,

        // 5. Windows SMB (Resmi Windows 11 Fluent 4'lü pencere logosu)
        .smb: """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4875 4875">
          <path fill="#0078d4" d="M0 0h2311v2310H0zm2564 0h2311v2310H2564zM0 2564h2311v2311H0zm2564 0h2311v2311H2564"/>
        </svg>
        """
    ]

    private override init() {
        super.init()
        mem.countLimit = 60
        mem.totalCostLimit = 16 * 1024 * 1024
        preloadVectors()
    }

    private func preloadVectors() {
        for (proto, svgStr) in Self.officialSVGs {
            if let data = svgStr.data(using: .utf8), let img = NSImage(data: data) {
                mem.setObject(img, forKey: proto.rawValue as NSString)
            }
        }
    }

    /// Marka logosunu bellekten anında (0 ms) döndürür
    func image(for proto: StorageProtocol) -> NSImage? {
        let key = proto.rawValue as NSString
        if let cached = mem.object(forKey: key) {
            return cached
        }
        if let svgStr = Self.officialSVGs[proto],
           let data = svgStr.data(using: .utf8),
           let img = NSImage(data: data) {
            mem.setObject(img, forKey: key)
            return img
        }
        return nil
    }

    /// Geriye dönük uyumluluk için asenkron yükleme arayüzü
    func load(for proto: StorageProtocol, completion: @escaping (NSImage?) -> Void) {
        completion(image(for: proto))
    }
}

// MARK: - Gerçek Marka Logosu Görünümü
/// Herhangi bir ağ gecikmesi olmadan, doğrudan yerel vektörden çizilen marka logosu.
struct ProviderLogoView: View {
    let proto: StorageProtocol
    let size: CGFloat

    var body: some View {
        if let img = ProviderLogoCache.shared.image(for: proto) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            ProviderFallbackIcon(proto: proto, size: size)
        }
    }
}

/// Beklenmedik durumda gösterilen yedek ikon
private struct ProviderFallbackIcon: View {
    let proto: StorageProtocol
    let size: CGFloat

    var sfSymbol: String {
        switch proto {
        case .googleDrive: return "triangle.fill"
        case .oneDrive: return "cloud.sun.fill"
        case .s3: return "cylinder.split.1x2.fill"
        case .webdav: return "server.rack"
        case .smb: return "network"
        }
    }

    var brandColor: Color {
        switch proto {
        case .googleDrive: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .oneDrive: return Color(red: 0.0, green: 0.47, blue: 0.83)
        case .s3: return Color(red: 0.89, green: 0.32, blue: 0.25)
        case .webdav: return Color(red: 0.0, green: 0.51, blue: 0.79)
        case .smb: return Color(red: 0.0, green: 0.47, blue: 0.84)
        }
    }

    var body: some View {
        Image(systemName: sfSymbol)
            .font(.system(size: size * 0.65, weight: .medium))
            .foregroundColor(brandColor)
            .frame(width: size, height: size)
    }
}

// MARK: - Geriye Dönük Uyumluluk Yardımcıları
struct GoogleDriveLogo: View {
    var size: CGFloat = 36
    var body: some View { ProviderLogoView(proto: .googleDrive, size: size) }
}
struct OneDriveLogo: View {
    var size: CGFloat = 36
    var body: some View { ProviderLogoView(proto: .oneDrive, size: size) }
}

// MARK: - Sağlayıcı Logo ve Rozet Bileşeni
struct ProviderLogoBadge: View {
    let storageProtocol: StorageProtocol
    var size: CGFloat = 36

    var body: some View {
        if size <= 22 {
            // Kenar çubuğu ve tablo listesinde net, sınırsız vektör
            ProviderLogoView(proto: storageProtocol, size: size)
        } else {
            // Kart, diyalog ve ayarlarda şık zeminli rozet
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)

                ProviderLogoView(proto: storageProtocol, size: size * 0.74)
            }
        }
    }
}

enum ConnectionViewMode {
    case list
    case selectProvider
    case edit(isNew: Bool)
}

public class GoogleOAuthHelper {
    public static var defaultClientId: String {
        let path = ("~/.config/HDrive/google_credentials.json" as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let val = json["client_id"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: "GoogleOAuthClientId") ?? ""
    }
    
    public static var defaultClientSecret: String {
        let path = ("~/.config/HDrive/google_credentials.json" as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let val = json["client_secret"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: "GoogleOAuthClientSecret") ?? ""
    }
    
    public static let redirectUri = "http://127.0.0.1:8080/oauth/callback"
    
    public static let shared = GoogleOAuthHelper()
    private var listener: NWListener?
    
    public func startListener(onCodeReceived: @escaping (String) -> Void) {
        stopListener()
        do {
            let params = NWParameters.tcp
            guard let port = NWEndpoint.Port(rawValue: 8080) else { return }
            listener = try NWListener(using: params, on: port)
            listener?.newConnectionHandler = { connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    if let data = data, let req = String(data: data, encoding: .utf8) {
                        if let range = req.range(of: "code=") {
                            let sub = req[range.upperBound...]
                            let rawCode = sub.prefix { $0 != "&" && $0 != " " && $0 != "\r" && $0 != "\n" }
                            // HTTP path'teki kod URL-encoded gelir; decode et
                            let codeStr = (String(rawCode).removingPercentEncoding ?? String(rawCode))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>HDrive</title></head><body style=\"font-family:system-ui,-apple-system;text-align:center;padding:60px 20px;background:#f8fafc;\"><div style=\"max-width:440px;margin:auto;background:white;padding:40px;border-radius:16px;box-shadow:0 10px 25px rgba(0,0,0,0.06);\"><h2 style=\"color:#10b981;margin-bottom:8px;\">✅ Giriş Başarılı!</h2><p style=\"color:#64748b;font-size:15px;line-height:1.5;\">HDrive bulut oturumunuzu başarıyla doğruladı.<br>Bu sekmeyi kapatıp uygulamaya dönebilirsiniz.</p></div></body></html>"
                            connection.send(content: html.data(using: .utf8), completion: .contentProcessed({ _ in
                                connection.cancel()
                            }))
                            
                            DispatchQueue.main.async {
                                onCodeReceived(codeStr)
                                self.stopListener()
                            }
                            return
                        }
                    }
                    connection.cancel()
                }
            }
            listener?.start(queue: .main)
        } catch {
            print("OAuth Listener başlatılamadı: \(error)")
        }
    }
    
    public func stopListener() {
        listener?.cancel()
        listener = nil
    }
    
    public func exchangeCodeForToken(code: String, clientId: String, clientSecret: String, completion: @escaping (Result<(accessToken: String, refreshToken: String), Error>) -> Void) {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz token URL'si"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let cId = clientId.isEmpty ? GoogleOAuthHelper.defaultClientId : clientId
        let cSec = clientSecret.isEmpty ? GoogleOAuthHelper.defaultClientSecret : clientSecret
        
        let body = "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)&client_id=\(cId)&client_secret=\(cSec)&redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Foauth%2Fcallback&grant_type=authorization_code"
        req.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Geçersiz token yanıtı"])))
                }
                return
            }
            if let token = json["access_token"] as? String {
                let rt = (json["refresh_token"] as? String) ?? ""
                DispatchQueue.main.async { completion(.success((token, rt))) }
            } else {
                let err = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "Token alınamadı"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: err])))
                }
            }
        }.resume()
    }
    
    public static func refreshToken(refreshToken: String, clientId: String, clientSecret: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let cId = clientId.isEmpty ? GoogleOAuthHelper.defaultClientId : clientId
        let cSec = clientSecret.isEmpty ? GoogleOAuthHelper.defaultClientSecret : clientSecret
        let body = "client_id=\(cId)&client_secret=\(cSec)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String else {
                completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Token yenilenemedi"])))
                return
            }
            completion(.success(token))
        }.resume()
    }
}

// MARK: - Standalone Settings Window Manager (macOS HIG Uyumlu Harici Pencere)
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    
    private var window: NSWindow?
    private var onSaveCallback: (() -> Void)?
    
    public func showSettings(onSave: (() -> Void)? = nil) {
        // Her çağrıda callback güncelle (pencere açık olsa bile)
        if let callback = onSave {
            self.onSaveCallback = callback
        }
        
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = HDriveSettingsView(onClose: { [weak self] in
            self?.closeSettings()
        }, onSave: { [weak self] in
            self?.onSaveCallback?()
        })
        
        let hostingController = NSHostingController(rootView: settingsView)
        let win = NSWindow(contentViewController: hostingController)
        win.title = "Ayarlar"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.center()
        win.minSize = NSSize(width: 740, height: 500)
        win.setContentSize(NSSize(width: 780, height: 560))
        win.setFrameAutosaveName("HDriveSettingsWindow")
        win.delegate = self
        
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closeSettings() {
        window?.close()
    }
    
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

public struct HDriveSettingsView: View {
    @Binding var isPresented: Bool
    var onClose: (() -> Void)?
    var onSave: (() -> Void)?
    
    public init(isPresented: Binding<Bool> = .constant(true), onClose: (() -> Void)? = nil, onSave: (() -> Void)? = nil) {
        self._isPresented = isPresented
        self.onClose = onClose
        self.onSave = onSave
    }
    
    @ObservedObject var manager = CloudreveManager.shared
    
    @State private var currentTab: SettingsTab = .account
    @State private var connectionMode: ConnectionViewMode = .list
    
    @State private var selectedServerID: UUID? = nil
    @State private var serverName: String = "Bulut Sürücüm"
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var storageProtocol: StorageProtocol = .webdav
    @State private var bucketName: String = ""
    @State private var region: String = "us-east-1"
    @State private var smbShare: String = ""
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var refreshToken: String = ""
    @State private var manualCodeInput: String = ""
    @State private var showAdvancedApiSettings: Bool = false
    
    public static let defaultOneDriveClientId = "232843cb-b028-4bbf-97d4-039b8a611dbd"
    
    @State private var isTesting: Bool = false
    @State private var testResult: String? = nil
    @State private var isTestSuccess: Bool = true
    @State private var hoveredProvider: StorageProtocol? = nil
    
    public var body: some View {
        HStack(spacing: 0) {
            // SOL KENAR ÇUBUĞU (macOS Sistem Ayarları Tarzı)
            VStack(spacing: 0) {
                // Üst Başlık (Pencere kontrol butonları için pay bırakıldı)
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 28, height: 28)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Text("Ayarlar")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 38)
                .padding(.bottom, 12)
                
                Divider()
                
                // Kategori Butonları
                VStack(spacing: 4) {
                    ForEach(SettingsTab.allCases) { tab in
                        let isSelected = (currentTab == tab)
                        Button(action: {
                            currentTab = tab
                            if tab == .account { connectionMode = .list }
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: tab.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 22, height: 22)
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .foregroundColor(isSelected ? .white : .primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                
                Spacer()
            }
            .frame(width: 215)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // SAĞ İÇERİK ALANI
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch currentTab {
                    case .account:
                        switch connectionMode {
                        case .list:
                            connectionsListView
                        case .selectProvider:
                            providerSelectionView
                        case .edit(let isNew):
                            serverEditView(isNew: isNew)
                        }
                    case .appearance:
                        appearanceSettingsSection
                    case .about:
                        aboutSection
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 520, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
        }
        .frame(minWidth: 740, minHeight: 520)
        .onAppear {
            if let active = manager.activeServer {
                selectServer(active)
            } else if let first = manager.servers.first {
                selectServer(first)
            } else {
                connectionMode = .selectProvider
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboardForOneDriveCode()
        }
    }
    
    // MARK: - 1. SEKME A: BAĞLANTILARIM LİSTESİ
    private var connectionsListView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Başlık ve Ekle Butonu
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bağlantılarım & Bulut Depolama")
                        .font(.title2.bold())
                    Text("Tüm bulut hesaplarınızı ve ağ paylaşımlarınızı buradan yönetin.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: {
                    connectionMode = .selectProvider
                }) {
                    Label("Yeni Bağlantı Ekle", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            
            // Kart Listesi
            if manager.servers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Kayıtlı Bağlantı Yok")
                        .font(.headline)
                    Text("Yukarıdaki 'Yeni Bağlantı Ekle' butonuna basarak ilk bulut sürücünüzü bağlayın.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(10)
            } else {
                VStack(spacing: 10) {
                    ForEach(manager.servers) { server in
                        let isConnected = server.isConnected
                        
                        HStack(spacing: 14) {
                            ProviderLogoBadge(storageProtocol: server.storageProtocol, size: 42)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(server.name.isEmpty ? server.storageProtocol.providerName : server.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    
                                    if isConnected {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 6, height: 6)
                                            Text("Bağlı")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.green)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(6)
                                    } else {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.secondary.opacity(0.6))
                                                .frame(width: 6, height: 6)
                                            Text("Bağlı Değil")
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(6)
                                    }
                                }
                                
                                Text("\(server.storageProtocol.providerName) • \(server.serverURL.isEmpty ? "Yerel / Bulut Hesabı" : server.serverURL)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                if isConnected {
                                    Button("Bağlantıyı Kes") {
                                        manager.disconnectServer(server)
                                        onSave?()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                } else {
                                    Button("Bağlan") {
                                        manager.connectServer(server)
                                        onSave?()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                                }
                                
                                Button(action: {
                                    selectServer(server)
                                    connectionMode = .edit(isNew: false)
                                }) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .help("Bağlantıyı Düzenle")
                                
                                Button(action: {
                                    manager.deleteServer(server)
                                    if manager.servers.isEmpty {
                                        connectionMode = .selectProvider
                                    }
                                    onSave?()
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .help("Bağlantıyı Sil")
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isConnected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: isConnected ? 1.5 : 1)
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - 1. SEKME B: SAĞLAYICI SEÇİM GALERİSİ (GRID)
    private var providerSelectionView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button(action: { connectionMode = .list }) {
                    Label("Bağlantılarıma Dön", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Bulut Depolama Servisi Seçin")
                    .font(.title2.bold())
                Text("Bağlanmak istediğiniz servise tıklayarak bilgilerinizi yapılandırın.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(StorageProtocol.allCases) { proto in
                    Button(action: {
                        startNewServer(for: proto)
                    }) {
                        HStack(spacing: 14) {
                            ProviderLogoBadge(storageProtocol: proto, size: 44)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(proto.providerName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(proto.providerSubtitle)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(hoveredProvider == proto ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(hoveredProvider == proto ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredProvider = hovering ? proto : nil
                    }
                }
            }
        }
    }
    
    // MARK: - 1. SEKME C: DÜZENLEME & DETAY FORMU
    private func serverEditView(isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(action: {
                    connectionMode = isNew ? .selectProvider : .list
                }) {
                    Label(isNew ? "Sağlayıcılar" : "Geri", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Spacer()
                
                ProviderLogoBadge(storageProtocol: storageProtocol, size: 28)
                Text(storageProtocol.providerName)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(isNew ? "Yeni Bağlantı Yapılandırması" : "Bağlantı Ayarlarını Düzenle")
                    .font(.title2.bold())
                Text("Gerekli sunucu ve kimlik doğrulama parametrelerini eksiksiz girin.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Inset Grouped Form
            VStack(spacing: 12) {
                HStack {
                    Text("Hesap Adı")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 140, alignment: .leading)
                    TextField("Örn: Kişisel Drive", text: $serverName)
                        .textFieldStyle(.roundedBorder)
                }
                
                if storageProtocol == .googleDrive || storageProtocol == .oneDrive {
                    // Temiz ve Şık Doğrudan Giriş Kartı (Teknik OAuth Detayları Gizlendi)
                    VStack(spacing: 20) {
                        ProviderLogoBadge(storageProtocol: storageProtocol, size: 64)
                            .padding(.top, 8)
                        
                        VStack(spacing: 6) {
                            Text("\(storageProtocol.providerName) Hesabınızı Bağlayın")
                                .font(.system(size: 16, weight: .bold))
                            
                            Text("Resmi \(storageProtocol.providerName) giriş ekranını kullanarak hesabınızı tek tıkla yetkilendirin. Tüm dosyalarınıza doğrudan HDrive üzerinden erişebilirsiniz.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }
                        
                        // Bağlantı / Oturum Durumu
                        if !password.isEmpty {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Oturum Açık & Bağlantı Hazır")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            startOAuthLogin()
                        }) {
                            HStack(spacing: 10) {
                                if storageProtocol == .googleDrive {
                                    GoogleDriveLogo(size: 20)
                                    Text(password.isEmpty ? "Google ile Giriş Yap" : "Google Hesabını Yeniden Bağla")
                                } else {
                                    OneDriveLogo(size: 20)
                                    Text(password.isEmpty ? "Microsoft ile Giriş Yap" : "Microsoft Hesabını Yeniden Bağla")
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    
                } else if storageProtocol == .webdav {
                    HStack {
                        Text("Sunucu Adresi")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("https://bulut.alanadi.com/dav", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Kullanıcı Adı / E-posta")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("admin@example.com", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("WebDAV Şifresi")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        SecureField("WebDAV şifreniz", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                } else if storageProtocol == .s3 {
                    HStack {
                        Text("S3 Uç Noktası (Endpoint)")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("https://s3.amazonaws.com veya MinIO URL", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Bucket Adı")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("depo-bucket-adi", text: $bucketName)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Bölge (Region)")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("us-east-1, eu-central-1, auto", text: $region)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Access Key ID")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("AKIAIOSFODNN7EXAMPLE", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Secret Access Key")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        SecureField("Secret Key", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                } else if storageProtocol == .smb {
                    HStack {
                        Text("Sunucu Adresi / IP")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("smb://192.168.1.100 veya nas.local", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Text("Paylaşım Adı (Share)")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("Public, Data vb.", text: $smbShare)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Kullanıcı Adı (Opsiyonel)")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        TextField("Kullanıcı Adı", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Şifre (Opsiyonel)")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 140, alignment: .leading)
                        SecureField("Şifre", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Test Sonucu Banner
            if let result = testResult {
                HStack(spacing: 8) {
                    Image(systemName: isTestSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isTestSuccess ? .green : .red)
                    Text(result)
                        .font(.caption)
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isTestSuccess ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                )
            }
            
            // Eylem Butonları
            HStack(spacing: 12) {
                Button(action: testConnection) {
                    if isTesting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Test Ediliyor...")
                        }
                    } else {
                        Label("Bağlantıyı Test Et", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isTesting)
                
                Spacer()
                
                Button("İptal") {
                    connectionMode = .list
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button("Kaydet ve Bağlan") {
                    saveAndConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
    }
    
    // MARK: - 2. SEKME: GÖRÜNÜM & GEZGİN
    private var appearanceSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Görünüm & Davranış")
                    .font(.title2.bold())
                Text("Finder stili gezinme ve önizleme tercihlerini özelleştirin.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("macOS Finder Standartları")
                        .font(.system(size: 13, weight: .semibold))
                    Text("• Çift tıklanan dosyalar varsayılan macOS uygulamasıyla yerinde açılır.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Cmd+S ile kaydedilen tüm değişiklikler arka planda anında buluta eşitlenir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Cmd+C / Cmd+V Finder ve Masaüstü arasında gerçek dosya kopyalamayı destekler.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Arama alanının dışına tıklandığında aramadan otomatik çıkılır.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("• Sütun ayraçları sürüklenerek boyutlandırılabilir.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

        }
    }
    
    // MARK: - 3. SEKME: HAKKINDA
    private var aboutSection: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 10)
            
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                Image(systemName: "folder.fill.badge.gearshape")
                    .font(.system(size: 34))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 4) {
                Text("HDrive for Mac")
                    .font(.title.bold())
                Text("Sürüm 1.2.9 (Universal Binary)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text("Google Drive, OneDrive, WebDAV, Amazon S3 ve SMB Depolama için Apple HIG Standartlarında Masaüstü İstemcisi.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            
            Text("© 2026 HDrive Team. Tüm hakları saklıdır.")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 8)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Yardımcı Metotlar
    private func selectServer(_ server: CloudreveServerConfig) {
        selectedServerID = server.id
        serverName = server.name
        serverURL = server.serverURL
        username = server.username
        password = server.password
        storageProtocol = server.storageProtocol
        bucketName = server.bucketName
        region = server.region
        smbShare = server.smbShare
        clientId = server.clientId
        clientSecret = server.clientSecret
        refreshToken = server.refreshToken
        
        if storageProtocol == .googleDrive && clientId.isEmpty {
            clientId = GoogleOAuthHelper.defaultClientId
            clientSecret = GoogleOAuthHelper.defaultClientSecret
        } else if storageProtocol == .oneDrive && clientId.isEmpty {
            clientId = HDriveSettingsView.defaultOneDriveClientId
        }
        testResult = nil
    }
    
    private func startNewServer(for proto: StorageProtocol) {
        let newID = UUID()
        selectedServerID = newID
        serverName = "\(proto.providerName)"
        storageProtocol = proto
        bucketName = ""
        region = "us-east-1"
        smbShare = ""
        username = ""
        password = ""
        clientId = ""
        clientSecret = ""
        refreshToken = ""
        
        switch proto {
        case .googleDrive:
            serverURL = "https://www.googleapis.com/drive/v3"
            clientId = GoogleOAuthHelper.defaultClientId
            clientSecret = GoogleOAuthHelper.defaultClientSecret
        case .oneDrive:
            serverURL = "https://graph.microsoft.com/v1.0/me/drive"
            clientId = HDriveSettingsView.defaultOneDriveClientId
        case .webdav:
            serverURL = "https://"
        case .s3:
            serverURL = "https://s3.amazonaws.com"
        case .smb:
            serverURL = "smb://"
        }
        testResult = nil
        connectionMode = .edit(isNew: true)
    }
    
    private func openConsoleForProvider() {
        let urlStr: String
        switch storageProtocol {
        case .googleDrive:
            urlStr = "https://console.cloud.google.com/apis/credentials"
        case .oneDrive:
            urlStr = "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
        default:
            urlStr = ""
        }
        if let u = URL(string: urlStr) {
            NSWorkspace.shared.open(u)
        }
    }

    private func exchangeManualCode() {
        var raw = manualCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = raw.range(of: "code=") {
            let sub = raw[range.upperBound...]
            let c = sub.prefix { $0 != "&" && $0 != " " && $0 != "\r" && $0 != "\n" }
            raw = String(c)
        }
        guard !raw.isEmpty else { return }
        
        let cId = clientId.isEmpty ? GoogleOAuthHelper.defaultClientId : clientId
        let cSec = clientSecret.isEmpty ? GoogleOAuthHelper.defaultClientSecret : clientSecret
        
        isTesting = true
        testResult = "⏳ Yetki kodu doğrulanıyor ve token alınıyor..."
        GoogleOAuthHelper.shared.exchangeCodeForToken(code: raw, clientId: cId, clientSecret: cSec) { result in
            self.isTesting = false
            switch result {
            case .success(let tokens):
                self.password = tokens.accessToken
                if !tokens.refreshToken.isEmpty {
                    self.refreshToken = tokens.refreshToken
                }
                self.isTestSuccess = true
                self.testResult = "✅ Google Drive oturumu başarıyla açıldı ve bağlandı!"
                self.saveAndConnect()
            case .failure(let error):
                self.isTestSuccess = false
                self.testResult = "❌ Doğrulama hatası: \(error.localizedDescription)"
            }
        }
    }

    private func startOAuthLogin() {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientName = storageProtocol.providerName
        
        let effClientId: String
        let effClientSecret: String
        
        switch storageProtocol {
        case .googleDrive:
            effClientId = trimmedClientId.isEmpty ? GoogleOAuthHelper.defaultClientId : trimmedClientId
            effClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? GoogleOAuthHelper.defaultClientSecret : clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        case .oneDrive:
            effClientId = trimmedClientId.isEmpty ? HDriveSettingsView.defaultOneDriveClientId : trimmedClientId
            effClientSecret = ""
        default:
            effClientId = trimmedClientId
            effClientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        clientId = effClientId
        clientSecret = effClientSecret
        
        guard !effClientId.isEmpty else {
            isTestSuccess = false
            testResult = "⚠️ '\(clientName)' resmi girişi için 'OAuth Client ID' zorunludur."
            return
        }
        
        guard let encodedClientId = effClientId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }
        
        isTesting = true
        testResult = nil
        
        if storageProtocol == .googleDrive {
            testResult = "⏳ Tarayıcıda Google giriş ekranı açıldı. İzni onayladığınızda HDrive otomatik olarak bağlanacaktır..."
            
            GoogleOAuthHelper.shared.startListener { code in
                self.testResult = "⏳ Google yetkilendirme kodu alındı, erişim tokenı talep ediliyor..."
                GoogleOAuthHelper.shared.exchangeCodeForToken(code: code, clientId: effClientId, clientSecret: effClientSecret) { result in
                    self.isTesting = false
                    switch result {
                    case .success(let tokens):
                        self.password = tokens.accessToken
                        if !tokens.refreshToken.isEmpty {
                            self.refreshToken = tokens.refreshToken
                        }
                        self.isTestSuccess = true
                        self.testResult = "✅ Google Drive oturumu başarıyla açıldı ve bağlandı!"
                        self.saveAndConnect()
                    case .failure(let error):
                        self.isTestSuccess = false
                        self.testResult = "❌ Google yetkilendirme hatası: \(error.localizedDescription)"
                    }
                }
            }
            
            let authUrlStr = "https://accounts.google.com/o/oauth2/v2/auth?client_id=\(encodedClientId)&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A8080%2Foauth%2Fcallback&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fdrive&access_type=offline&prompt=consent"
            if let url = URL(string: authUrlStr) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        
        if storageProtocol == .oneDrive {
            testResult = "⏳ Tarayıcıda Microsoft giriş ekranı açıldı. Hesabınızı onayladığınızda HDrive otomatik olarak bağlanacaktır..."
            isTesting = true
            isTestSuccess = true
            
            GoogleOAuthHelper.shared.startListener { code in
                DispatchQueue.main.async {
                    self.testResult = "⏳ Microsoft yetkilendirme kodu alındı, erişim tokenı talep ediliyor..."
                    self.exchangeOneDriveCode(raw: code) { result in
                        self.isTesting = false
                        switch result {
                        case .success(let tokens):
                            self.password = tokens.accessToken
                            if !tokens.refreshToken.isEmpty {
                                self.refreshToken = tokens.refreshToken
                            }
                            self.isTestSuccess = true
                            self.testResult = "✅ Microsoft OneDrive oturumu başarıyla açıldı ve bağlandı!"
                            self.saveAndConnect()
                        case .failure(let error):
                            self.isTestSuccess = false
                            self.testResult = "❌ Microsoft yetkilendirme hatası: \(error.localizedDescription)"
                        }
                    }
                }
            }
            
            let authEndpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=\(encodedClientId)&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A8080&scope=offline_access%20Files.ReadWrite%20User.Read"
            if let url = URL(string: authEndpoint) {
                NSWorkspace.shared.open(url)
            }
            return
        }
    }
    
    private func checkClipboardForOneDriveCode() {
        guard storageProtocol == .oneDrive, password.isEmpty else { return }
        if let pb = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pb.isEmpty && (pb.contains("nativeclient?code=") || pb.hasPrefix("M.")) {
            manualCodeInput = pb
            pasteAndConnectOneDrive()
        }
    }
    
    private func pasteAndConnectOneDrive() {
        if let pb = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !pb.isEmpty {
            if pb.contains("code=") || pb.contains("nativeclient") || pb.hasPrefix("M.") {
                manualCodeInput = pb
            }
        }
        let codeOrUrl = manualCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codeOrUrl.isEmpty else {
            testResult = "⚠️ Panoda veya metin kutusunda geçerli bir bağlantı veya yetkilendirme kodu bulunamadı."
            isTestSuccess = false
            return
        }
        isTesting = true
        testResult = "⏳ Microsoft yetkilendirme kodu doğrulanıyor..."
        exchangeOneDriveCode(raw: codeOrUrl) { result in
            self.isTesting = false
            switch result {
            case .success(let tokens):
                self.password = tokens.accessToken
                if !tokens.refreshToken.isEmpty {
                    self.refreshToken = tokens.refreshToken
                }
                self.isTestSuccess = true
                self.testResult = "✅ Microsoft OneDrive oturumu başarıyla açıldı ve bağlandı!"
                self.saveAndConnect()
            case .failure(let error):
                self.isTestSuccess = false
                self.testResult = "❌ Microsoft yetkilendirme hatası: \(error.localizedDescription)"
            }
        }
    }
    
    private func exchangeOneDriveCode(raw: String, completion: @escaping (Result<(accessToken: String, refreshToken: String), Error>) -> Void) {
        var code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNativeClient = code.contains("nativeclient")
        if let range = code.range(of: "code=") {
            let sub = code[range.upperBound...]
            code = String(sub.prefix { $0 != "&" && $0 != " " && $0 != "\r" && $0 != "\n" })
        }
        guard !code.isEmpty, let url = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token") else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz yetki kodu"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let cId = clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? HDriveSettingsView.defaultOneDriveClientId : clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        // Form-body için katı encoding: + → %2B (urlQueryAllowed + karakterini encode etmez)
        var strictChars = CharacterSet.alphanumerics
        strictChars.insert(charactersIn: "-._~")
        let encCode = code.addingPercentEncoding(withAllowedCharacters: strictChars) ?? code
        let redirectUri = isNativeClient ? "https%3A%2F%2Flogin.microsoftonline.com%2Fcommon%2Foauth2%2Fnativeclient" : "http%3A%2F%2Flocalhost%3A8080"
        let body = "client_id=\(cId)&grant_type=authorization_code&code=\(encCode)&redirect_uri=\(redirectUri)"
        req.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Microsoft sunucusundan geçersiz yanıt alındı"])))
                }
                return
            }
            if let token = json["access_token"] as? String {
                let rt = (json["refresh_token"] as? String) ?? ""
                DispatchQueue.main.async { completion(.success((token, rt))) }
            } else {
                let err = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "OneDrive tokenı alınamadı"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: err])))
                }
            }
        }.resume()
    }
    
    private func saveAndConnect() {
        if storageProtocol == .oneDrive && (password.contains("code=") || password.hasPrefix("https://") || password.hasPrefix("M.")) {
            isTesting = true
            exchangeOneDriveCode(raw: password) { result in
                self.isTesting = false
                switch result {
                case .success(let tokens):
                    self.password = tokens.accessToken
                    if !tokens.refreshToken.isEmpty {
                        self.refreshToken = tokens.refreshToken
                    }
                    self.performSaveAndConnect()
                case .failure(let err):
                    self.isTestSuccess = false
                    self.testResult = "❌ Microsoft yetkilendirme kodu doğrulanamadı: \(err.localizedDescription)"
                }
            }
            return
        }
        if (storageProtocol == .googleDrive || storageProtocol == .oneDrive) && password.isEmpty {
            isTestSuccess = false
            testResult = "⚠️ Lütfen önce yukarıdaki '\(storageProtocol.providerName) ile Giriş Yap' butonuna basarak hesabınızı yetkilendirin."
            return
        }
        performSaveAndConnect()
    }

    private func performSaveAndConnect() {
        guard let curID = selectedServerID else { return }
        var cfg = manager.servers.first(where: { $0.id == curID }) ?? CloudreveServerConfig()
        cfg.id = curID
        cfg.name = serverName.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.password = password
        cfg.storageProtocol = storageProtocol
        cfg.bucketName = bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.smbShare = smbShare.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.refreshToken = refreshToken
        
        manager.saveServer(cfg)
        manager.setActiveServer(cfg)
        onSave?()
        connectionMode = .list
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        if storageProtocol == .oneDrive && (password.contains("code=") || password.hasPrefix("https://") || password.hasPrefix("M.")) {
            exchangeOneDriveCode(raw: password) { result in
                switch result {
                case .success(let tokens):
                    self.password = tokens.accessToken
                    if !tokens.refreshToken.isEmpty {
                        self.refreshToken = tokens.refreshToken
                    }
                    self.performTestConnection()
                case .failure(let err):
                    self.isTesting = false
                    self.isTestSuccess = false
                    self.testResult = "❌ Microsoft yetkilendirme kodu doğrulanamadı: \(err.localizedDescription)"
                }
            }
            return
        }
        performTestConnection()
    }

    private func performTestConnection() {
        var cfg = CloudreveServerConfig()
        cfg.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.password = password
        cfg.storageProtocol = storageProtocol
        cfg.bucketName = bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.smbShare = smbShare.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        cfg.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let client = WebDAVClient(config: cfg)
        client.testConnection { success, message in
            isTesting = false
            isTestSuccess = success
            testResult = message
        }
    }
}

public typealias CloudreveSettingsSheet = HDriveSettingsView



// MARK: - İşlem ve Sistem Tanılama Sayfası (Diagnostics Sheet)
struct DiagnosticsSheetView: View {
    @Binding var isPresented: Bool
    @ObservedObject var logManager = SyncLogManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("İşlem ve Sistem Tanılama Günlüğü", systemImage: "stethoscope")
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

// MARK: - Türkçe Karakter Uyumlu Arama Genişletmesi
extension String {
    /// Türkçe karakter uyumlu (büyük/küçük harf, İ-i, I-ı, ç-c, ğ-g, ö-o, ş-s, ü-u toleranslı) arama karşılaştırması
    func matchesSearchQuery(_ query: String) -> Bool {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return true }
        
        // 1. Standart hızlı arama
        if self.localizedCaseInsensitiveContains(cleanQuery) { return true }
        
        // 2. Türkçe normalize vaka (İ -> i, I -> ı, kombine işaretlerin temizlenmesi)
        let normSelf = self.turkishNormalized()
        let normQuery = cleanQuery.turkishNormalized()
        if normSelf.contains(normQuery) { return true }
        
        // 3. Toleranslı vaka (kullanıcı klavyeden "c" yazsa da "ç", "s" yazsa da "ş", "g" yazsa da "ğ" eşleşir)
        let fuzzySelf = normSelf.turkishFuzzyNormalized()
        let fuzzyQuery = normQuery.turkishFuzzyNormalized()
        if fuzzySelf.contains(fuzzyQuery) { return true }
        
        return false
    }
    
    private func turkishNormalized() -> String {
        var s = self.replacingOccurrences(of: "İ", with: "i")
        s = s.replacingOccurrences(of: "I", with: "ı")
        s = s.lowercased(with: Locale(identifier: "tr_TR"))
        s = s.precomposedStringWithCanonicalMapping
        s = s.replacingOccurrences(of: "\u{0307}", with: "") // Combining dot above
        return s
    }
    
    private func turkishFuzzyNormalized() -> String {
        let map: [Character: Character] = [
            "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"
        ]
        return String(self.map { map[$0] ?? $0 })
    }
}

// MARK: - Bildirim İsimleri
extension Notification.Name {
    static let exitSearchRequested = Notification.Name("HDriveExitSearchRequested")
    static let openToolbarCustomizer = Notification.Name("HDriveOpenToolbarCustomizer")
}

// MARK: - AppKit Toolbar Menü Köprüsü (Right-Click Context Menu Bridge)
final class ToolbarMenuBridge: NSObject {
    static let shared = ToolbarMenuBridge()
    var onSelectMode: ((ToolbarDisplayMode) -> Void)?
    var onOpenCustomizer: (() -> Void)?
    
    @objc func setIconAndText() {
        onSelectMode?(.iconAndText)
    }
    
    @objc func setIconOnly() {
        onSelectMode?(.iconOnly)
    }
    
    @objc func openCustomizer() {
        onOpenCustomizer?()
    }
}

// MARK: - Finder Tarzı Araç Çubuğu Özelleştirme Penceresi (Toolbar Customizer)
struct ToolbarCustomizationSheet: View {
    @Binding var isPresented: Bool
    @Binding var toolbarItemsRaw: String
    @Binding var toolbarDisplayModeRaw: String
    
    private var enabledItems: Set<ExplorerToolbarItemId> {
        let items = toolbarItemsRaw.components(separatedBy: ",").compactMap { ExplorerToolbarItemId(rawValue: $0) }
        return Set(items)
    }
    
    private func toggleItem(_ item: ExplorerToolbarItemId) {
        var current = toolbarItemsRaw.components(separatedBy: ",").filter { !$0.isEmpty }
        if current.contains(item.rawValue) {
            current.removeAll { $0 == item.rawValue }
        } else {
            current.append(item.rawValue)
        }
        toolbarItemsRaw = current.joined(separator: ",")
    }
    
    private func restoreDefaults() {
        withAnimation(.easeInOut(duration: 0.2)) {
            toolbarItemsRaw = NativeExplorerView.defaultToolbarItems
            toolbarDisplayModeRaw = ToolbarDisplayMode.iconOnly.rawValue
        }
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 155, maximum: 180), spacing: 14)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Başlık Bölümü (Header)
            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Araç Çubuğunu Özelleştir")
                            .font(.system(size: 17, weight: .bold))
                        Text("Sık kullandığınız araçları araç çubuğuna ekleyin veya kaldırın. Kartlara tıklayarak durumunu değiştirebilirsiniz.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider()
            
            // Araçlar Izgarası (Interactive Tool Cards Grid)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 20) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(ExplorerToolbarItemId.allCases) { item in
                            let isEnabled = enabledItems.contains(item)
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    toggleItem(item)
                                }
                            }) {
                                VStack(spacing: 8) {
                                    HStack {
                                        Spacer()
                                        // Durum Rozeti (Badge)
                                        HStack(spacing: 3) {
                                            Image(systemName: isEnabled ? "checkmark.circle.fill" : "plus.circle")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(isEnabled ? "Eklendi" : "Ekle")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundColor(isEnabled ? .white : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isEnabled ? Color.accentColor : Color.secondary.opacity(0.15))
                                        .clipShape(Capsule())
                                    }
                                    
                                    // Simge Kutusu
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isEnabled ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: item.icon)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(isEnabled ? .accentColor : .primary.opacity(0.7))
                                    }
                                    
                                    // Başlık & Açıklama
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    Text(item.subtitle)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .frame(height: 26)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(isEnabled ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: isEnabled ? 1.5 : 1)
                                        )
                                        .shadow(color: isEnabled ? Color.accentColor.opacity(0.08) : Color.clear, radius: 4, y: 2)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Saptanmış Takım Kutusu (Finder Default Set Bar)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Saptanmış Araç Takımı", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Saptanmış Takımı Geri Yükle", action: restoreDefaults)
                                .font(.system(size: 11, weight: .medium))
                                .buttonStyle(.bordered)
                        }
                        
                        // Saptanmış takım önizleme şeridi
                        HStack(spacing: 12) {
                            ForEach(["chevron.left.chevron.right", "square.grid.2x2", "arrow.up.arrow.down", "sidebar.right", "folder.badge.plus", "arrow.up.circle.fill", "arrow.clockwise", "tray.and.arrow.down", "gearshape"], id: \.self) { iconName in
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.05))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: iconName)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(Color.primary.opacity(0.15))
                        )
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.6))
                    )
                }
                .padding(20)
            }
            
            Divider()
            
            // Alt Menü / Footer (Display Mode & Done Button)
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text("Göster:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $toolbarDisplayModeRaw) {
                        Text("Yalnızca Simge").tag(ToolbarDisplayMode.iconOnly.rawValue)
                        Text("Simge ve Metin").tag(ToolbarDisplayMode.iconAndText.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                
                Spacer()
                
                Button("Bitti") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 720, idealWidth: 760, maxWidth: 840, minHeight: 520, idealHeight: 560, maxHeight: 680)
    }
}



