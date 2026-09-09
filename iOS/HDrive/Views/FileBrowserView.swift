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
    
    // Eylem Durumları
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showingDocPicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var activeShareURL: URL?
    
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
            // 1. Kategori Filtreleme Çubuğu
            categoryFilterBar
            
            // 2. Dosya Listesi veya Izgara
            if filteredItems.isEmpty {
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
                Menu {
                    Button(action: { showingNewFolderAlert = true }) {
                        Label("Yeni Klasör", systemImage: "folder.badge.plus")
                    }
                    Button(action: { showingDocPicker = true }) {
                        Label("Dosya İçe Aktar...", systemImage: "doc.badge.plus")
                    }
                    Button(action: { showingPhotoPicker = true }) {
                        Label("Fotoğraf/Video Ekle...", systemImage: "photo.badge.plus")
                    }
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
        .onAppear(perform: loadFiles)
        .alert("Yeni Klasör", isPresented: $showingNewFolderAlert) {
            TextField("Klasör Adı", text: $newFolderName)
            Button("Oluştur", action: createFolder)
            Button("Vazgeç", role: .cancel) { newFolderName = "" }
        }
        .sheet(isPresented: $showingDocPicker) {
            DocumentPicker(targetDirectory: directoryURL) {
                loadFiles()
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotos, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotos) { newItems in
            importPhotos(newItems)
        }
        .sheet(item: $activeShareURL) { url in
            ShareSheet(activityItems: [url])
        }
    }
    
    // MARK: - Filtrelenmiş Dosyalar
    private var filteredItems: [FileItem] {
        items.filter { item in
            let matchesCategory = (selectedCategory == .all) || item.isDirectory || (item.category == selectedCategory)
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
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
                if item.isDirectory {
                    NavigationLink(destination: FileBrowserView(directoryURL: item.url, title: item.name)) {
                        fileRow(item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        deleteButton(for: item)
                    }
                } else {
                    NavigationLink(destination: FileDetailView(file: item)) {
                        fileRow(item)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        deleteButton(for: item)
                        shareButton(for: item)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - Izgara Görünümü
    private var filesGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 14)], spacing: 14) {
                ForEach(filteredItems) { item in
                    if item.isDirectory {
                        NavigationLink(destination: FileBrowserView(directoryURL: item.url, title: item.name)) {
                            fileGridCell(item)
                        }
                    } else {
                        NavigationLink(destination: FileDetailView(file: item)) {
                            fileGridCell(item)
                        }
                    }
                }
            }
            .padding(16)
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
            try? FileManager.default.removeItem(at: item.url)
            loadFiles()
        } label: {
            Label("Sil", systemImage: "trash")
        }
    }
    
    private func shareButton(for item: FileItem) -> some View {
        Button {
            activeShareURL = item.url
        } label: {
            Label("Paylaş", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
    }
    
    // MARK: - Boş Durum
    private var emptyFilesView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("Dosya Bulunmuyor")
                .font(.headline)
            Text("Yukarıdaki + butonunu kullanarak veya bilgisayarınızdan ağ sürücüsü ile dosya aktarabilirsiniz.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
    
    // MARK: - Veri İşlemleri
    private func loadFiles() {
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
            self.items = []
        }
    }
    
    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let newDir = directoryURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        newFolderName = ""
        loadFiles()
    }
    
    private func importPhotos(_ photoItems: [PhotosPickerItem]) {
        for photoItem in photoItems {
            photoItem.loadTransferable(type: Data.self) { result in
                switch result {
                case .success(let data):
                    guard let data = data else { return }
                    let filename = "IMG_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4)).jpg"
                    let target = self.directoryURL.appendingPathComponent(filename)
                    try? data.write(to: target)
                    DispatchQueue.main.async {
                        self.loadFiles()
                    }
                case .failure(let error):
                    print("Fotoğraf aktarılamadı: \(error)")
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
    let targetDirectory: URL
    let onDismiss: () -> Void
    
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
            for sourceURL in urls {
                let dest = parent.targetDirectory.appendingPathComponent(sourceURL.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: sourceURL, to: dest)
            }
            parent.onDismiss()
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onDismiss()
        }
    }
}
