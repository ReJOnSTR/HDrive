//
//  CloudreveMobileView.swift
//  HDrive (iOS)
//

import SwiftUI
import PhotosUI

public struct CloudreveMobileView: View {
    @ObservedObject var manager = CloudreveManager.shared
    
    @State private var serverName: String = "Cloudreve Sunucum"
    @State private var serverURL: String = "https://your-cloudreve.com/dav"
    @State private var username: String = ""
    @State private var password: String = ""
    
    @State private var isConfiguring = false
    @State private var isTesting = false
    @State private var testMessage: String? = nil
    
    // Uzak Dosya Gezgini Durumları
    @State private var currentPath: String = ""
    @State private var remoteFiles: [RemoteFileItem] = []
    @State private var isLoading = false
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var showingRenameAlert = false
    @State private var itemToRename: RemoteFileItem? = nil
    @State private var renamingName = ""
    
    // Sıralama Durumları
    @State private var sortField: FileSortField = .name
    @State private var sortAscending: Bool = true
    @State private var foldersFirst: Bool = true
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Group {
                if isConfiguring || manager.activeServer?.serverURL.isEmpty == true {
                    serverSettingsForm
                } else {
                    remoteFilesView
                }
            }
            .navigationTitle(currentPath.isEmpty ? "Cloudreve" : (currentPath as NSString).lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isConfiguring.toggle() }) {
                        Image(systemName: isConfiguring ? "checkmark.circle.fill" : "gearshape")
                    }
                }
                
                if !isConfiguring {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 8) {
                            Menu {
                                Button(action: { showingNewFolderAlert = true }) {
                                    Label("Yeni Klasör", systemImage: "folder.badge.plus")
                                }
                                PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
                                    Label("Fotoğraf Yükle", systemImage: "photo.badge.plus")
                                }
                            } label: {
                                Image(systemName: "plus")
                            }
                            
                            Menu {
                                Section("Sıralama Ölçütü") {
                                    ForEach(FileSortField.allCases) { field in
                                        Button(action: { sortField = field }) {
                                            HStack {
                                                Text(field.rawValue)
                                                if sortField == field { Image(systemName: "checkmark") }
                                            }
                                        }
                                    }
                                }
                                Section("Sıralama Yönü") {
                                    Button(action: { sortAscending = true }) {
                                        HStack {
                                            Text("Artan (A-Z)")
                                            if sortAscending { Image(systemName: "checkmark") }
                                        }
                                    }
                                    Button(action: { sortAscending = false }) {
                                        HStack {
                                            Text("Azalan (Z-A)")
                                            if !sortAscending { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                    }
                }
            }
            .onAppear {
                loadConfig()
                if !(manager.activeServer?.serverURL.isEmpty ?? true) {
                    refreshFiles()
                }
            }
            .alert("Yeni Klasör", isPresented: $showingNewFolderAlert) {
                TextField("Klasör Adı", text: $newFolderName)
                Button("Oluştur", action: createFolder)
                Button("İptal", role: .cancel) { newFolderName = "" }
            }
            .alert("Yeniden Adlandır", isPresented: $showingRenameAlert) {
                TextField("Yeni İsim", text: $renamingName)
                Button("Tamam", action: commitRename)
                Button("İptal", role: .cancel) { renamingName = ""; itemToRename = nil }
            }
            .onChange(of: selectedPhotos) { items in
                uploadSelectedPhotos(items)
            }
        }
    }
    
    // MARK: - Sunucu Yapılandırma Formu
    private var serverSettingsForm: some View {
        Form {
            Section(header: Text("Cloudreve WebDAV Bağlantısı"), footer: Text("Cloudreve hesabınızdan WebDAV adresini (genellikle https://alanadi.com/dav) ve şifrenizi girin.")) {
                TextField("Sunucu Adı", text: $serverName)
                TextField("https://alanadi.com/dav", text: $serverURL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                TextField("Kullanıcı Adı / E-posta", text: $username)
                    .autocapitalization(.none)
                SecureField("WebDAV Şifresi", text: $password)
            }
            
            Section {
                Button(action: testAndSave) {
                    HStack {
                        if isTesting {
                            ProgressView()
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isTesting ? "Test Ediliyor..." : "Kaydet ve Bağlan")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isTesting || serverURL.isEmpty)
                
                if let msg = testMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Uzak Dosya Listesi ve Sıralama
    private var sortedRemoteFiles: [RemoteFileItem] {
        return remoteFiles.sorted(by: { (item1: RemoteFileItem, item2: RemoteFileItem) -> Bool in
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
                } else if item1.size < item2.size {
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

    private var remoteFilesView: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Cloudreve sunucusundan yükleniyor...")
                Spacer()
            } else if remoteFiles.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cloud")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Bu klasör boş")
                        .font(.headline)
                    Text("Yukarıdaki + butonuna basarak fotoğraf veya dosya yükleyebilirsiniz.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(sortedRemoteFiles) { file in
                        HStack(spacing: 14) {
                            Image(systemName: file.systemIcon)
                                .font(.title2)
                                .foregroundColor(file.isDirectory ? .blue : .purple)
                                .frame(width: 30)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(file.formattedSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if file.isDirectory {
                                navigateTo(file.name)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteFile(file)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                startRenaming(file)
                            } label: {
                                Label("Yeniden Adlandır", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                startRenaming(file)
                            } label: {
                                Label("Yeniden Adlandır", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteFile(file)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    refreshFiles()
                }
            }
        }
    }
    
    // MARK: - İşlemler
    private func loadConfig() {
        if let current = manager.activeServer {
            self.serverName = current.name
            self.serverURL = current.serverURL
            self.username = current.username
            self.password = current.password
        }
    }
    
    private func testAndSave() {
        isTesting = true
        testMessage = nil
        
        var config = manager.activeServer ?? CloudreveServerConfig()
        config.name = serverName
        config.serverURL = serverURL
        config.username = username
        config.password = password
        
        let client = WebDAVClient(config: config)
        client.testConnection { success, message in
            isTesting = false
            testMessage = message
            if success {
                manager.saveServer(config)
                isConfiguring = false
                refreshFiles()
            }
        }
    }
    
    private func refreshFiles() {
        guard let server = manager.activeServer else { return }
        isLoading = true
        let client = WebDAVClient(config: server)
        client.listFiles(at: currentPath) { result in
            isLoading = false
            switch result {
            case .success(let files):
                self.remoteFiles = files
            case .failure(let error):
                self.testMessage = error.localizedDescription
            }
        }
    }
    
    private func navigateTo(_ folder: String) {
        currentPath = (currentPath.isEmpty ? "" : currentPath + "/") + folder
        refreshFiles()
    }
    
    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        let target = (currentPath.isEmpty ? "" : currentPath + "/") + name
        client.createFolder(at: target) { error in
            if error == nil {
                newFolderName = ""
                refreshFiles()
            }
        }
    }
    
    private func deleteFile(_ file: RemoteFileItem) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        client.delete(at: file.href, isDirectory: file.isDirectory) { error in
            if error == nil {
                refreshFiles()
            }
        }
    }
    
    private func startRenaming(_ file: RemoteFileItem) {
        itemToRename = file
        renamingName = file.name
        showingRenameAlert = true
    }
    
    private func commitRename() {
        guard let file = itemToRename, let server = manager.activeServer else { return }
        let newName = renamingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != file.name else {
            itemToRename = nil
            renamingName = ""
            return
        }
        
        let client = WebDAVClient(config: server)
        let basePath = currentPath.isEmpty ? "" : currentPath + "/"
        let sourcePath = basePath + file.name
        let destPath = basePath + newName
        
        client.move(from: sourcePath, to: destPath, overwrite: false) { error in
            itemToRename = nil
            renamingName = ""
            if error == nil {
                refreshFiles()
            }
        }
    }
    
    private func uploadSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("IMG_\(Int(Date().timeIntervalSince1970)).jpg")
                    try? data.write(to: tempURL)
                    let remoteDest = (currentPath.isEmpty ? "" : currentPath + "/") + tempURL.lastPathComponent
                    client.uploadFile(localFileURL: tempURL, toRemotePath: remoteDest) { error in
                        try? FileManager.default.removeItem(at: tempURL)
                        DispatchQueue.main.async {
                            self.refreshFiles()
                        }
                    }
                }
            }
        }
        self.selectedPhotos.removeAll()
    }
}
