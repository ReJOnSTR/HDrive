//
//  CloudreveMobileView.swift
//  HDrive (iOS)
//

import SwiftUI
import PhotosUI

public struct CloudreveMobileView: View {
    @ObservedObject var manager = CloudreveManager.shared
    
    @State private var serverName: String = "Bulut Hesabım"
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    
    @State private var isConfiguring = false
    @State private var showFolderSync = false
    @State private var showMove = false
    @State private var shareLinks: [URL] = []
    @State private var showBulkShare = false
    @State private var showCloudManagement = false
    @State private var cloudActionConfig: CloudreveServerConfig?
    @State private var cloudActionFile: RemoteFileItem?
    @State private var cloudActionMode: CloudManagementView.Mode = .sharing

    @State private var isTesting = false
    @State private var testMessage: String? = nil
    
    // Uzak Dosya Gezgini Durumları
    @State private var currentPath: String = ""
    @State private var pathHistory: [String] = []
    @State private var pathTitles: [String] = []
    @State private var operationError: String?
    @State private var listingError: String?
    @State private var selecting = false
    @State private var selectedIDs = Set<String>()
    @State private var pendingDeletion: [RemoteFileItem] = []
    @State private var showDeleteConfirmation = false
    @State private var showDocumentPicker = false
    @State private var loadGeneration = UUID()
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
        NavigationStack { browserDialogs }
    }
    private var browserMain: some View {
            Group {
                if isConfiguring || manager.activeServer == nil {
                    serverSettingsForm
                } else {
                    remoteFilesView
                }
            }
            .navigationTitle(pathTitles.last ?? manager.activeServer?.name ?? "Bulut")
            .navigationBarTitleDisplayMode(currentPath.isEmpty ? .large : .inline)
            .toolbar { browserToolbar }
    }
    private var browserDialogs: some View {
        browserMain
            .onAppear {
                loadConfig()
                if !(manager.activeServer?.serverURL.isEmpty ?? true) {
                    refreshFiles()
                }
            }
            .alert("Yeni Klasör", isPresented: $showingNewFolderAlert) {
                TextField(L10n.text("Klasör Adı"), text: $newFolderName)
                Button(L10n.text("Oluştur"), action: createFolder)
                Button(L10n.text("İptal"), role: .cancel) { newFolderName = "" }
            }
            .alert("Yeniden Adlandır", isPresented: $showingRenameAlert) {
                TextField(L10n.text("Yeni İsim"), text: $renamingName)
                Button(L10n.text("Tamam"), action: commitRename)
                Button(L10n.text("İptal"), role: .cancel) { renamingName = ""; itemToRename = nil }
            }
            .onChange(of: selectedPhotos) { items in
                uploadSelectedPhotos(items)
            }
            .alert("İşlem tamamlanamadı", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
                Button(L10n.text("Tamam")) { operationError = nil }
            } message: { Text(operationError ?? "") }
            .confirmationDialog("Seçili \(pendingDeletion.count) öğe silinsin mi? Bu işlem sağlayıcıya bağlı olarak kalıcı olabilir.", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button(L10n.text("Sil"), role: .destructive) { deletePending() }
                Button(L10n.text("Vazgeç"), role: .cancel) { pendingDeletion = [] }
            }

        .sheet(isPresented: $showMove) {
            if let account = manager.activeServer { CloudFolderPicker(config: account) { target in moveSelected(to: target, account: account) } }
        }
        .sheet(isPresented: $showBulkShare) { ShareSheet(activityItems: shareLinks) }
        .sheet(isPresented: $showFolderSync) {
            if let account = manager.activeServer { FolderSyncView(config: account, remoteRoot: currentPath) }
        }
        .sheet(isPresented: $showCloudManagement) {
            if let account = cloudActionConfig {
                CloudManagementView(config: account, href: cloudActionFile?.href ?? "", name: cloudActionFile?.name ?? "", mode: cloudActionMode)
            }
        }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker { urls in uploadDocuments(urls) }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Text("\(selectedIDs.count) seçili").font(.caption)
                        Spacer()
                        Button("Taşı") { showMove = true }
                        if manager.activeServer?.storageProtocol == .googleDrive || manager.activeServer?.storageProtocol == .oneDrive {
                            Button(L10n.text("Paylaş")) { shareSelected() }
                        }
                        Button { downloadSelected() } label: { Label("İndir", systemImage: "arrow.down.circle") }
                        Button(role: .destructive) {
                            pendingDeletion = remoteFiles.filter { selectedIDs.contains($0.id) }; showDeleteConfirmation = true
                        } label: { Label(L10n.text("Sil"), systemImage: "trash") }
                    }.padding().background(.regularMaterial).disabled(selectedIDs.isEmpty)
                }
            }
    }

    @ToolbarContentBuilder private var browserToolbar: some ToolbarContent {

                if !currentPath.isEmpty && !isConfiguring {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: goBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.backward")
                                Text(L10n.text("Geri"))
                            }
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !isConfiguring {
                        Button(selecting ? "Bitti" : "Seç") { selecting.toggle(); selectedIDs.removeAll() }
                        Menu {
                            Button { showDocumentPicker = true } label: { Label(L10n.text("Dosya Yükle"), systemImage: "doc.badge.plus") }
                            Button(action: { showingNewFolderAlert = true }) {
                                Label(L10n.text("Yeni Klasör"), systemImage: "folder.badge.plus")
                            }
                            PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
                                Label("Fotoğraf Yükle", systemImage: "photo.badge.plus")
                            }
                        } label: { Label(L10n.text("Dosya Ekle"), systemImage: "plus") }
                        
                        Menu {
                            Section(L10n.text("Sıralama Ölçütü")) {
                                ForEach(FileSortField.allCases) { field in
                                    Button(action: { sortField = field }) {
                                        HStack {
                                            Text(field.rawValue)
                                            if sortField == field { Image(systemName: "checkmark") }
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
                        }
                    }
                    
                    Menu {
                        Button("Bu Klasörü Eşitle") { showFolderSync = true }
                        if manager.activeServer?.storageProtocol == .googleDrive {
                            Button(L10n.text("Google Drive Çöp Kutusu")) { presentCloudAction(nil, mode: .trash) }
                        }
                        ForEach(manager.servers.filter { $0.isConnected }) { account in
                            Button(account.name) {
                                manager.setActiveServer(account)
                                currentPath = ""; pathHistory = []; pathTitles = []; selectedIDs = []
                                loadConfig(); refreshFiles()
                            }
                        }
                    } label: { Label(L10n.text("Hesap Seç"), systemImage: "person.crop.circle") }
                    Button(action: { isConfiguring.toggle() }) {
                        Image(systemName: isConfiguring ? "checkmark.circle.fill" : "gearshape")
                    }
                }

    }

    // MARK: - Sunucu Yapılandırma Formu
    private var serverSettingsForm: some View {
        Form {
            Section(header: Text(L10n.text("WebDAV Bağlantısı")), footer: Text("Sağlayıcınızın WebDAV adresini ve uygulama parolasını girin.")) {
                TextField(L10n.text("Sunucu Adı"), text: $serverName)
                TextField("https://alanadi.com/dav", text: $serverURL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                TextField(L10n.text("Kullanıcı Adı / E-posta"), text: $username)
                    .autocapitalization(.none)
                SecureField(L10n.text("WebDAV Şifresi"), text: $password)
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
                ProgressView("Dosyalar yükleniyor...")
                Spacer()
            } else if let listingError = listingError {
                ContentUnavailableView {
                    Label(L10n.text("Klasör açılamadı"), systemImage: "exclamationmark.triangle")
                } description: { Text(listingError) } actions: {
                    Button(L10n.text("Yeniden Dene"), action: refreshFiles)
                }
            } else if remoteFiles.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.08))
                            .frame(width: 84, height: 84)
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.indigo)
                    }
                    
                    Text(L10n.text("Bu Klasör Boş"))
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                    
                    Text("Dosya eklemek için yukarıdaki + simgesine dokunabilir veya aşağıdaki butonları kullanabilirsiniz.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                    
                    HStack(spacing: 12) {
                        Button(action: { showingNewFolderAlert = true }) {
                            Label(L10n.text("Yeni Klasör"), systemImage: "folder.badge.plus")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        
                        PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
                            Label("Fotoğraf", systemImage: "photo.badge.plus")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(sortedRemoteFiles) { file in
                        HStack(spacing: 14) {
                            if selecting {
                                Image(systemName: selectedIDs.contains(file.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.indigo)
                            }
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
                        .onTapGesture { activate(file) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { activate(file) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeletion = [file]; showDeleteConfirmation = true
                            } label: {
                                Label(L10n.text("Sil"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                startRenaming(file)
                            } label: {
                                Label(L10n.text("Yeniden Adlandır"), systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            if let account = manager.activeServer, account.storageProtocol == .googleDrive || account.storageProtocol == .oneDrive {
                                Button(L10n.text("Paylaşım Bağlantısı...")) { presentCloudAction(file, mode: .sharing) }
                                if !file.isDirectory { Button(L10n.text("Sürüm Geçmişi...")) { presentCloudAction(file, mode: .versions) } }
                            }
                            if !file.isDirectory {
                                Button { downloadFiles([file]) } label: { Label(L10n.text("Çevrimdışı Kaydet"), systemImage: "arrow.down.circle") }
                            }
                            Button {
                                startRenaming(file)
                            } label: {
                                Label(L10n.text("Yeniden Adlandır"), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                pendingDeletion = [file]; showDeleteConfirmation = true
                            } label: {
                                Label(L10n.text("Sil"), systemImage: "trash")
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
    private func shareSelected() {
        guard let account = manager.activeServer else { return }
        let files = remoteFiles.filter { selectedIDs.contains($0.id) }
        Task {
            var links: [URL] = [], errors: [String] = []
            let client = WebDAVClient(config: account)
            for file in files {
                do { links.append(try await client.readOnlyLink(href: file.href)) }
                catch { errors.append(file.name + ": " + error.localizedDescription) }
            }
            let values = links, message = errors.joined(separator: "\n")
            await MainActor.run {
                if !message.isEmpty { operationError = message }
                else { shareLinks = values; showBulkShare = !values.isEmpty }
            }
        }
    }
    private func moveSelected(to target: String, account: CloudreveServerConfig) {
        let files = remoteFiles.filter { selectedIDs.contains($0.id) }
        Task {
            var errors: [String] = []
            let client = WebDAVClient(config: account)
            do {
                let destinations: [RemoteFileItem] = try await withCheckedThrowingContinuation { continuation in client.listFiles(at: target) { continuation.resume(with: $0) } }
                for file in files {
                    if destinations.contains(where: { $0.name == file.name }) { errors.append(file.name + ": Hedefte aynı adlı öğe var."); continue }
                    do { try await client.moveItem(href: file.href, name: file.name, toFolder: target) }
                    catch { errors.append(file.name + ": " + error.localizedDescription) }
                }
            } catch { errors.append(error.localizedDescription) }
            let message = errors.joined(separator: "\n")
            await MainActor.run { if !message.isEmpty { operationError = message }; if manager.activeServer?.id == account.id { refreshFiles() } }
        }
    }

    private func activate(_ file: RemoteFileItem) {
        if selecting {
            if selectedIDs.contains(file.id) { selectedIDs.remove(file.id) } else { selectedIDs.insert(file.id) }
        } else if file.isDirectory {
            pathHistory.append(currentPath); pathTitles.append(file.name)
            currentPath = file.href; refreshFiles()
        } else { downloadFiles([file]) }
    }

    private func presentCloudAction(_ file: RemoteFileItem?, mode: CloudManagementView.Mode) {
        cloudActionConfig = manager.activeServer; cloudActionFile = file; cloudActionMode = mode; showCloudManagement = true
    }

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
                guard manager.saveServer(config) else {
                    testMessage = manager.lastError ?? "Hesap kaydedilemedi."
                    return
                }
                isConfiguring = false
                refreshFiles()
            }
        }
    }
    
    private func refreshFiles() {
        guard let server = manager.activeServer else { return }
        isLoading = true
        listingError = nil
        selectedIDs.removeAll()
        let generation = UUID(); loadGeneration = generation
        let client = WebDAVClient(config: server)
        client.listFiles(at: currentPath) { result in
            guard loadGeneration == generation, manager.activeServer?.id == server.id else { return }
            isLoading = false
            switch result {
            case .success(let files):
                self.remoteFiles = files
            case .failure(let error):
                self.listingError = error.localizedDescription
            }
        }
    }
    
    private func navigateTo(_ folder: String) {
        currentPath = (currentPath.isEmpty ? "" : currentPath + "/") + folder
        refreshFiles()
    }
    
    private func goBack() {
        currentPath = pathHistory.popLast() ?? ""
        if !pathTitles.isEmpty { pathTitles.removeLast() }
        refreshFiles()
    }

    private func createFolder() {
        guard let server = manager.activeServer else { return }
        let name: String
        do { name = try LocalFileOperations.validName(newFolderName) }
        catch { operationError = error.localizedDescription; return }
        let client = WebDAVClient(config: server)
        let target = (currentPath.isEmpty ? "" : currentPath + "/") + name
        client.createFolder(at: target) { error in
            if error == nil {
                newFolderName = ""
                refreshFiles()
            } else { operationError = error?.localizedDescription }
        }
    }
    
    private func deletePending() {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        let files = pendingDeletion
        pendingDeletion = []
        Task {
            var errors: [String] = []
            for file in files {
                let error: Error? = await withCheckedContinuation { continuation in
                    client.moveToTrash(href: file.href, isDirectory: file.isDirectory) { continuation.resume(returning: $0) }
                }
                if let error = error { errors.append("\(file.name): \(error.localizedDescription)") }
            }
            let message = errors.joined(separator: "\n")
            await MainActor.run {
                if !message.isEmpty { operationError = message }
                if manager.activeServer?.id == server.id { refreshFiles() }
            }
        }
    }

    private func downloadSelected() { downloadFiles(remoteFiles.filter { selectedIDs.contains($0.id) }) }
    private func downloadFiles(_ files: [RemoteFileItem]) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        for file in files {
            guard !file.isDirectory else { operationError = "Klasör indirmek için içindeki dosyaları seçin."; continue }
            do {
                let target = try OfflineStore.destination(config: server, remotePath: file.href, name: file.name)
                TransferManager.shared.enqueueDownload(fileName: file.name, remoteHref: file.href, localTargetURL: target, client: client, expectedSize: file.size)
            } catch { operationError = error.localizedDescription }
        }
    }
    private func uploadDocuments(_ urls: [URL]) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        for source in urls {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HDrive/Uploads/" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if let copy = try LocalFileOperations.importFile(source, into: directory) {
                    TransferManager.shared.enqueueUpload(fileURL: copy, remoteFolder: currentPath, client: client)
                }
            } catch { operationError = error.localizedDescription }
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
        
        client.renameItem(href: file.href, newName: newName, parentPath: currentPath) { error in
            itemToRename = nil
            renamingName = ""
            if error == nil {
                refreshFiles()
            } else { operationError = error?.localizedDescription }
        }
    }
    
    private func uploadSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard let server = manager.activeServer else { return }
        let client = WebDAVClient(config: server)
        
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("IMG_\(UUID().uuidString).jpg")
                    do { try data.write(to: tempURL, options: .atomic) }
                    catch { DispatchQueue.main.async { operationError = error.localizedDescription }; return }
                    let remoteDest = (currentPath.isEmpty ? "" : currentPath + "/") + tempURL.lastPathComponent
                    client.uploadFile(localFileURL: tempURL, toRemotePath: remoteDest) { error in
                        try? FileManager.default.removeItem(at: tempURL)
                        DispatchQueue.main.async {
                            if let error = error { operationError = error.localizedDescription }
                            self.refreshFiles()
                        }
                    }
                }
            }
        }
        self.selectedPhotos.removeAll()
    }
}
