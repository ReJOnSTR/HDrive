//
//  FileBrowserView.swift
//  HDrive
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct FileBrowserView: View {
    public let directoryURL: URL
    public let title: String
    
    @State private var items: [FileItem] = []
    @State private var selectedCategory: FileCategory = .all
    @State private var searchText: String = ""
    @State private var isGridView: Bool = false
    
    // Sıralama Durumları
    @State private var sortField: FileSortField = .name
    @State private var sortAscending: Bool = true
    @State private var foldersFirst: Bool = true
    
    // Eylem Durumları
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showingRenameAlert = false
    @State private var itemToRename: FileItem? = nil
    @State private var renamingName = ""
    @State private var showingDocPicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var activeShareURL: URL?
    @State private var errorMessage: String?
    @State private var selection = Set<URL>()
    @State private var selecting = false
    @State private var pendingDeletion: [URL] = []
    @State private var showDeleteConfirmation = false
    @State private var showTrash = false
    @State private var shareURLs: [URL] = []
    @State private var showBulkShare = false
    @State private var showMove = false
    @State private var importQueue: [URL] = []
    @State private var showCollision = false
    @State private var lastTrashEntries: [LocalFileOperations.TrashEntry] = []
    @State private var loadError: String?
    
    public init(directoryURL: URL? = nil, title: String = "Dosyalar") {
        if let dir = directoryURL {
            self.directoryURL = dir
            self.title = title
        } else {
            let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let hdriveDir = doc.appendingPathComponent("HDriveFiles", isDirectory: true)
            try? FileManager.default.createDirectory(at: hdriveDir, withIntermediateDirectories: true)
            self.directoryURL = hdriveDir
            self.title = "HDrive Dosyaları"
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Dosya Listesi veya Izgara
            if let loadError = loadError {
                ContentUnavailableView {
                    Label(L10n.text("Klasör açılamadı"), systemImage: "exclamationmark.triangle")
                } description: { Text(loadError) } actions: {
                    Button(L10n.text("Yeniden Dene"), action: loadFiles)
                }
            } else if filteredItems.isEmpty {
                emptyFilesView
            } else if isGridView {
                filesGridView
            } else {
                filesListView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Dosya veya klasör ara...")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(selecting ? "Bitti" : "Seç") { selecting.toggle(); selection.removeAll() }
                        .accessibilityHint("Birden çok dosyaya işlem uygulayın")
                    // Sıralama Menüsü
                    Menu {
                        Section(L10n.text("Sıralama Ölçütü")) {
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
                        
                        Section(L10n.text("Sıralama Yönü")) {
                            Button(action: { sortAscending = true }) {
                                HStack {
                                    Text(L10n.text("Artan (A-Z)"))
                                    if sortAscending { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { sortAscending = false }) {
                                HStack {
                                    Text(L10n.text("Azalan (Z-A)"))
                                    if !sortAscending { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.body)
                            .foregroundColor(.indigo)
                    }
                    
                    // Yeni Ekle & Görünüm Menüsü
                    Menu {
                        Button(action: { showingNewFolderAlert = true }) {
                            Label(L10n.text("Yeni Klasör"), systemImage: "folder.badge.plus")
                        }
                        Button(action: { showingDocPicker = true }) {
                            Label(L10n.text("Dosya İçe Aktar..."), systemImage: "doc.badge.plus")
                        }
                        Button(action: { showingPhotoPicker = true }) {
                            Label("Fotoğraf/Video Ekle...", systemImage: "photo.badge.plus")
                        }
                        Button { showTrash = true } label: { Label(L10n.text("Çöp Kutusu"), systemImage: "trash") }
                        Divider()
                        Button(action: { isGridView.toggle() }) {
                            Label(isGridView ? "Liste Görünümü" : "Izgara Görünümü", systemImage: isGridView ? "list.bullet" : "square.grid.2x2")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(.indigo)
                    }
                }
            }
        }
        .onAppear(perform: loadFiles)
        .alert("Yeni Klasör", isPresented: $showingNewFolderAlert) {
            TextField(L10n.text("Klasör Adı"), text: $newFolderName)
            Button(L10n.text("Oluştur"), action: createFolder)
            Button(L10n.text("Vazgeç"), role: .cancel) { newFolderName = "" }
        }
        .alert("Yeniden Adlandır", isPresented: $showingRenameAlert) {
            TextField(L10n.text("Yeni İsim"), text: $renamingName)
            Button(L10n.text("Tamam"), action: commitRename)
            Button(L10n.text("İptal"), role: .cancel) { renamingName = ""; itemToRename = nil }
        }
        .sheet(isPresented: $showingDocPicker) {
            DocumentPicker { urls in
                importQueue = urls
                processNextImport()
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotos, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotos) { newItems in
            importPhotos(newItems)
        }
        .sheet(item: $activeShareURL) { url in
            ShareSheet(activityItems: [url])
        }
        .sheet(isPresented: $showMove) {
            LocalFolderPicker { target in
                var errors: [String] = []
                for url in selection {
                    do { try LocalFileOperations.moveFile(url, into: target) }
                    catch { errors.append(url.lastPathComponent + ": " + error.localizedDescription) }
                }
                selection.removeAll(); loadFiles()
                if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
            }
        }
        .sheet(isPresented: $showBulkShare) { ShareSheet(activityItems: shareURLs) }
        .sheet(isPresented: $showTrash, onDismiss: loadFiles) { LocalTrashView() }
        .alert("İşlem tamamlanamadı", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L10n.text("Tamam")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .confirmationDialog("Seçili \(pendingDeletion.count) öğe çöp kutusuna taşınsın mı?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(L10n.text("Çöp Kutusuna Taşı"), role: .destructive, action: trashPending)
            Button(L10n.text("Vazgeç"), role: .cancel) { pendingDeletion = [] }
        }
        .confirmationDialog("Aynı adlı bir öğe var: \(importQueue.first?.lastPathComponent ?? "")", isPresented: $showCollision, titleVisibility: .visible) {
            Button(L10n.text("Değiştir")) { importNext(policy: .replace) }
            Button(L10n.text("İkisini Tut")) { importNext(policy: .keepBoth) }
            Button(L10n.text("Atla")) { importNext(policy: .skip) }
            Button("İçe Aktarmayı İptal Et", role: .cancel) { importQueue = [] }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack {
                    Text("\(selection.count) seçili").font(.caption)
                    Spacer()
                    Button("Taşı") { showMove = true }.disabled(selection.isEmpty)
                    Button { shareURLs = Array(selection); showBulkShare = true } label: { Label(L10n.text("Paylaş"), systemImage: "square.and.arrow.up") }.disabled(selection.isEmpty)
                    Button(role: .destructive) { pendingDeletion = Array(selection); showDeleteConfirmation = true } label: { Label(L10n.text("Sil"), systemImage: "trash") }.disabled(selection.isEmpty)
                }.padding().background(.regularMaterial)
            } else if !lastTrashEntries.isEmpty {
                HStack {
                    Text("Çöp kutusuna taşındı").font(.caption)
                    Spacer()
                    Button(L10n.text("Geri Al"), action: undoTrash)
                }.padding().background(.regularMaterial)
            }
        }
    }
    
    // MARK: - Filtrelenmiş ve Sıralanmış Dosyalar
    private var filteredItems: [FileItem] {
        let list = items.filter { item in
            let matchesCategory = (selectedCategory == .all) || item.isDirectory || (item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
        
        return list.sorted(by: { (item1: FileItem, item2: FileItem) -> Bool in
            if foldersFirst {
                if item1.isDirectory && !item2.isDirectory { return true }
                if !item1.isDirectory && item2.isDirectory { return false }
            }
            
            let comparison: ComparisonResult
            switch sortField {
            case .name:
                comparison = item1.name.localizedStandardCompare(item2.name)
            case .date:
                comparison = item1.modificationDate.compare(item2.modificationDate)
            case .size:
                if item1.size == item2.size {
                    comparison = item1.name.localizedStandardCompare(item2.name)
                } else if item1.size < item2.size {
                    comparison = .orderedAscending
                } else {
                    comparison = .orderedDescending
                }
            case .kind:
                let ext1 = item1.isDirectory ? "" : item1.url.pathExtension.lowercased()
                let ext2 = item2.isDirectory ? "" : item2.url.pathExtension.lowercased()
                if ext1 == ext2 {
                    comparison = item1.name.localizedStandardCompare(item2.name)
                } else {
                    comparison = ext1.localizedStandardCompare(ext2)
                }
            }
            return sortAscending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        })
    }
    
    // MARK: - Kategori Filtreleme
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FileCategory.allCases) { category in
                    Button(action: { selectedCategory = category }) {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.caption2)
                            Text(category.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(selectedCategory == category ? Color.indigo : Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundColor(selectedCategory == category ? .white : .primary)
                        .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - Liste Görünümü
    private var filesListView: some View {
        List {
            ForEach(filteredItems) { item in
                itemLink(item, grid: false)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { deleteButton(for: item); shareButton(for: item) }
                    .swipeActions(edge: .leading) { renameButton(for: item) }
            }
        }.listStyle(.plain)
    }

    private var filesGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 14)], spacing: 14) {
                ForEach(filteredItems) { item in itemLink(item, grid: true) }
            }.padding(16)
        }
    }

    @ViewBuilder private func itemLink(_ item: FileItem, grid: Bool) -> some View {
        Group {
            if selecting {
                Button {
                    if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
                } label: {
                    HStack {
                        Image(systemName: selection.contains(item.url) ? "checkmark.circle.fill" : "circle")
                        if grid { fileGridCell(item) } else { fileRow(item) }
                    }
                }.accessibilityLabel(item.name).accessibilityValue(selection.contains(item.url) ? "Seçili" : "Seçili değil")
            } else if item.isDirectory {
                NavigationLink(destination: FileBrowserView(directoryURL: item.url, title: item.name)) {
                    if grid { fileGridCell(item) } else { fileRow(item) }
                }
            } else {
                NavigationLink(destination: FileDetailView(file: item)) {
                    if grid { fileGridCell(item) } else { fileRow(item) }
                }
            }
        }.contextMenu {
            renameButton(for: item)
            shareButton(for: item)
            deleteButton(for: item)
        }
    }

    private func fileRow(_ item: FileItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.systemIcon)
                .font(.title2)
                .foregroundColor(item.iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                HStack(spacing: 6) {
                    Text(item.formattedSize)
                    Text("•")
                    Text(item.formattedDate)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func fileGridCell(_ item: FileItem) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(item.iconColor.opacity(0.12))
                    .frame(width: 68, height: 68)
                
                Image(systemName: item.systemIcon)
                    .font(.system(size: 30))
                    .foregroundColor(item.iconColor)
            }
            
            Text(item.name)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            Text(item.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(14)
    }
    
    private func deleteButton(for item: FileItem) -> some View {
        Button(role: .destructive) {
            pendingDeletion = [item.url]
            showDeleteConfirmation = true
        } label: {
            Label(L10n.text("Sil"), systemImage: "trash")
        }
    }
    
    private func shareButton(for item: FileItem) -> some View {
        Button {
            activeShareURL = item.url
        } label: {
            Label(L10n.text("Paylaş"), systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
    }
    
    private func renameButton(for item: FileItem) -> some View {
        Button {
            itemToRename = item
            renamingName = item.name
            showingRenameAlert = true
        } label: {
            Label(L10n.text("Yeniden Adlandır"), systemImage: "pencil")
        }
        .tint(.orange)
    }
    
    // MARK: - Boş Durum
    private var emptyFilesView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text(items.isEmpty ? "Bu Klasör Boş" : "Sonuç Bulunamadı")
                .font(.headline)
            Text(items.isEmpty ? "+ menüsünden dosya içe aktarabilir veya klasör oluşturabilirsiniz." : "Aramanızı değiştirin.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
    
    // MARK: - Veri İşlemleri
    private func loadFiles() {
        loadError = nil
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey
            ], options: [.skipsHiddenFiles])
            
            self.items = urls.map { FileItem(url: $0) }.sorted {
                if $0.isDirectory && !$1.isDirectory { return true }
                if !$0.isDirectory && $1.isDirectory { return false }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
    
    private func createFolder() {
        do {
            let name = try LocalFileOperations.validName(newFolderName)
            let newDir = directoryURL.appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: newDir.path) else { throw CocoaError(.fileWriteFileExists) }
            try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: false)
            newFolderName = ""
            loadFiles()
        } catch { errorMessage = error.localizedDescription }
    }
    
    private func commitRename() {
        guard let item = itemToRename else { return }
        let newName = renamingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != item.name else {
            itemToRename = nil
            renamingName = ""
            return
        }
        do {
            let name = try LocalFileOperations.validName(newName)
            let dest = item.url.deletingLastPathComponent().appendingPathComponent(name)
            try FileManager.default.moveItem(at: item.url, to: dest)
        } catch { errorMessage = error.localizedDescription }
        itemToRename = nil
        renamingName = ""
        loadFiles()
    }
    
    private func trashPending() {
        var moved: [LocalFileOperations.TrashEntry] = []
        var errors: [String] = []
        for url in pendingDeletion {
            do { moved.append(try LocalFileOperations.trash(url)) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        lastTrashEntries = moved
        pendingDeletion = []; selection.removeAll(); loadFiles()
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
    }
    private func undoTrash() {
        var remaining: [LocalFileOperations.TrashEntry] = []
        for entry in lastTrashEntries {
            do { try LocalFileOperations.restore(entry) }
            catch { remaining.append(entry); errorMessage = error.localizedDescription }
        }
        lastTrashEntries = remaining; loadFiles()
    }
    private func processNextImport() {
        guard let source = importQueue.first else { loadFiles(); return }
        if FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(source.lastPathComponent).path) { showCollision = true }
        else { importNext(policy: .fail) }
    }
    private func importNext(policy: FileCollisionPolicy) {
        guard let source = importQueue.first else { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do { try LocalFileOperations.importFile(source, into: directoryURL, policy: policy) }
        catch { errorMessage = "\(source.lastPathComponent): \(error.localizedDescription)" }
        importQueue.removeFirst()
        DispatchQueue.main.async { processNextImport() }
    }

    private func importPhotos(_ photoItems: [PhotosPickerItem]) {
        for photoItem in photoItems {
            photoItem.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    guard let data = data else { return }
                    let filename = "IMG_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).jpg"
                    let target = self.directoryURL.appendingPathComponent(filename)
                    do {
                        try data.write(to: target, options: .atomic)
                        DispatchQueue.main.async { self.loadFiles() }
                    } catch { DispatchQueue.main.async { self.errorMessage = error.localizedDescription } }
                case .failure(let error):
                    DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                }
            }
        }
        self.selectedPhotos.removeAll()
    }
}

// MARK: - Paylaşım Sayfası (UIActivityViewController)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { self.path }
}

// MARK: - Belge Seçici (UIDocumentPickerViewController)
struct DocumentPicker: UIViewControllerRepresentable {
    let onSelect: ([URL]) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onSelect(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onSelect([])
        }
    }
}

struct LocalTrashView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LocalFileOperations.TrashEntry] = []
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty { Text(L10n.text("Çöp kutusu boş")).foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.name)
                        Text(entry.deletedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        Button(L10n.text("Geri Yükle")) {
                            do { try LocalFileOperations.restore(entry); reload() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }.navigationTitle("Çöp Kutusu")
                .toolbar { Button(L10n.text("Bitti")) { dismiss() } }
                .onAppear(perform: reload)
                .alert("Geri yüklenemedi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button(L10n.text("Tamam")) { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
        }
    }
    private func reload() {
        do { entries = try LocalFileOperations.trashEntries() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct LocalFolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("HDriveFiles")
    @State private var folders: [URL] = []
    @State private var errorMessage: String?
    let onSelect: (URL) -> Void
    var body: some View {
        NavigationStack {
            List {
                Text(current.lastPathComponent).font(.headline)
                if current.standardizedFileURL != FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("HDriveFiles").standardizedFileURL {
                    Button(L10n.text("Geri")) { current.deleteLastPathComponent(); load() }
                }
                ForEach(folders, id: \.self) { folder in Button { current = folder; load() } label: { Label(folder.lastPathComponent, systemImage: "folder") } }
                if let errorMessage = errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button("Seçili Öğeleri Buraya Taşı") { onSelect(current); dismiss() }
                Text("Aynı adlı öğeler varsa her iki kopya korunur.").font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("Hedef Klasör").onAppear(perform: load)
                .toolbar { Button(L10n.text("İptal")) { dismiss() } }
        }
    }
    private func load() {
        do {
            folders = try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]).filter {
                let values = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]); return values.isDirectory == true && values.isSymbolicLink != true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch { errorMessage = error.localizedDescription }
    }
}
