import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct WorkspaceSettingsView: View {
    @State private var entries: [OfflineStore.Entry] = []
    @State private var trash: [LocalFileOperations.TrashEntry] = []
    @State private var cacheBytes: Int64 = 0
    @State private var protectedBytes: Int64 = 0
    @State private var errorMessage: String?
    @AppStorage("HDriveCacheLimitMB") private var cacheLimitMB = 1024
    public init() {}
    public var body: some View {
        NavigationStack {
            List {
                Section(L10n.text("Çevrimdışı Dosyalar")) {
                    if entries.isEmpty { Text("Bulut dosyasının menüsünden Çevrimdışı Kaydet'i seçin.").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        HStack {
                            #if os(iOS)
                            NavigationLink(destination: FileDetailView(file: FileItem(url: entry.localURL))) {
                                VStack(alignment: .leading) { Text(entry.name); Text(entry.accountName).font(.caption).foregroundStyle(.secondary) }
                            }
                            #else
                            Button(entry.name) { NSWorkspace.shared.open(entry.localURL) }
                            Text(entry.accountName).font(.caption).foregroundStyle(.secondary)
                            #endif
                            ShareLink(item: entry.localURL) { Label(L10n.text("Paylaş"), systemImage: "square.and.arrow.up") }.labelStyle(.iconOnly)
                        }
                    }
                }
                Section(L10n.text("Önbellek")) {
                    Text("Kullanılan: \(format(cacheBytes)) · Korunan çalışma kopyaları: \(format(protectedBytes))")
                    Picker("Boyut sınırı", selection: $cacheLimitMB) {
                        Text("256 MB").tag(256); Text("1 GB").tag(1024); Text("5 GB").tag(5120)
                    }
                    Button(L10n.text("Sınıra Göre Temizle")) { trim(Int64(cacheLimitMB) * 1024 * 1024) }
                    Button(L10n.text("Temizlenebilir Önbelleği Sil")) { trim(0) }
                    Text("Harici uygulamada açılan çalışma kopyaları ve çevrimdışı dosyalar korunur.").font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("Yerel Çöp Kutusu")) {
                    if trash.isEmpty { Text(L10n.text("Çöp kutusu boş")).foregroundStyle(.secondary) }
                    ForEach(trash) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Button(L10n.text("Geri Yükle")) {
                                do { try LocalFileOperations.restore(item); reload() }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
            }.navigationTitle("Dosyalar ve Depolama").onAppear(perform: reload)
                .alert("İşlem tamamlanamadı", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button(L10n.text("Tamam")) { errorMessage = nil }
                } message: { Text(errorMessage ?? "") }
        }
    }
    private func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func reload() {
        do {
            entries = try OfflineStore.entries(); trash = try LocalFileOperations.trashEntries()
            let cache = try WorkingCache.entries()
            cacheBytes = cache.reduce(0) { $0 + $1.bytes }; protectedBytes = cache.filter { $0.protected }.reduce(0) { $0 + $1.bytes }
        } catch { errorMessage = error.localizedDescription }
    }
    private func trim(_ limit: Int64) {
        do { try WorkingCache.trim(to: limit); reload() }
        catch { errorMessage = error.localizedDescription }
    }
}

public struct CloudManagementView: View {
    public enum Mode { case sharing, versions, trash }
    let config: CloudreveServerConfig
    let href: String
    let name: String
    let mode: Mode
    @State private var versions: [CloudFileVersion] = []
    @State private var trash: [CloudTrashItem] = []
    @State private var link: URL?
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var confirmPublic = false
    @State private var pendingVersion: String?
    @State private var confirmRestore = false
    @Environment(\.dismiss) private var dismiss
    public init(config: CloudreveServerConfig, href: String = "", name: String = "", mode: Mode) {
        self.config = config; self.href = href; self.name = name; self.mode = mode
    }
    public var body: some View {
        NavigationStack {
            List {
                if busy { ProgressView("Yükleniyor...") }
                if let errorMessage = errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
                if mode == .sharing {
                    Text(name).font(.headline)
                    Text("Mevcut bağlantı erişim izinlerini değiştirmez. Herkese açık bağlantıyı açmak, bağlantıya sahip herkesin dosyayı görüntülemesine izin verir.").font(.callout)
                    Button(L10n.text("Mevcut Erişim Bağlantısını Al")) { perform { link = try await WebDAVClient(config: config).readOnlyLink(href: href) } }
                    Button(L10n.text("Herkese Açık Görüntüleme Bağlantısı Aç")) { confirmPublic = true }
                    Button(L10n.text("Herkese Açık Bağlantıları Kaldır"), role: .destructive) { perform { try await WebDAVClient(config: config).revokePublicLinks(href: href); link = nil } }
                    if let link = link { Text(link.absoluteString).textSelection(.enabled); ShareLink(item: link) { Label(L10n.text("Bağlantıyı Paylaş"), systemImage: "square.and.arrow.up") } }
                } else if mode == .versions {
                    if !busy && versions.isEmpty { Text("Sağlayıcı bu dosya için sürüm döndürmedi.") }
                    ForEach(versions) { version in
                        VStack(alignment: .leading) {
                            Text(version.modified.isEmpty ? version.id : version.modified)
                            Text("Sürüm: \(version.id)").font(.caption).foregroundStyle(.secondary)
                            if version.canRestore { Button(L10n.text("Bu Sürümü Geri Yükle")) { pendingVersion = version.id; confirmRestore = true } }
                        }
                    }
                    if config.storageProtocol == .googleDrive { Text("Google Drive sürümleri burada listelenir; geri yükleme Google Drive üzerinden yapılır.").font(.caption).foregroundStyle(.secondary) }
                } else {
                    if !busy && trash.isEmpty { Text(L10n.text("Çöp kutusu boş")) }
                    ForEach(trash) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Button(L10n.text("Geri Yükle")) { perform { try await WebDAVClient(config: config).restoreTrash(href: item.id); trash.removeAll { $0.id == item.id } } }
                        }
                    }
                }
            }.disabled(busy)
                .navigationTitle(mode == .sharing ? "Paylaşım" : mode == .versions ? "Sürüm Geçmişi" : "Google Drive Çöp Kutusu")
                .toolbar { Button(L10n.text("Bitti")) { dismiss() } }
                .task { await load() }
                .confirmationDialog("Bağlantıya sahip herkes bu dosyayı görüntüleyebilsin mi?", isPresented: $confirmPublic, titleVisibility: .visible) {
                    Button(L10n.text("Herkese Açık Bağlantı Oluştur")) { perform { link = try await WebDAVClient(config: config).readOnlyLink(href: href, allowPublicAccess: true) } }
                    Button(L10n.text("Vazgeç"), role: .cancel) {}
                }
                .confirmationDialog("Seçilen sürüm güncel dosyanın yerine geri yüklensin mi?", isPresented: $confirmRestore, titleVisibility: .visible) {
                    Button(L10n.text("Geri Yükle")) { if let version = pendingVersion { perform { try await WebDAVClient(config: config).restoreVersion(href: href, version: version) } } }
                    Button(L10n.text("Vazgeç"), role: .cancel) {}
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }
    @MainActor private func load() async {
        busy = true; defer { busy = false }
        do {
            let client = WebDAVClient(config: config)
            if mode == .versions { versions = try await client.versions(href: href) }
            else if mode == .trash { trash = try await client.trashedFiles() }
        } catch { errorMessage = error.localizedDescription }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await action() } catch { errorMessage = error.localizedDescription }
        }
    }
}

public struct FolderSyncView: View {
    let config: CloudreveServerConfig
    let remoteRoot: String
    @State private var localRoot: URL?
    @State private var exclusions = ".git/**;node_modules/**;*.tmp;*.part"
    @State private var rows: [FolderSyncRow] = []
    @State private var policy: FolderSyncPolicy = .skip
    @State private var engine: FolderSynchronizer?
    @State private var busy = false
    @State private var message = "Önce değişiklikleri tarayın. Yeni iki kopya ve iki tarafta değişen dosyalar çakışma olarak gösterilir."
    @State private var automatic = false
    @Environment(\.dismiss) private var dismiss
    public init(config: CloudreveServerConfig, remoteRoot: String) { self.config = config; self.remoteRoot = remoteRoot }
    public var body: some View {
        NavigationStack {
            List {
                Section(L10n.text("Eşitleme Klasörleri")) {
                    Text("Bulut: " + config.name + " · seçili klasör")
                    Text(localRoot?.path ?? "Yerel klasör seçilmedi").font(.caption).textSelection(.enabled)
                    #if os(macOS)
                    Button(L10n.text("Yerel Klasör Seç")) {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            localRoot = url; engine = nil; rows = []
                            UserDefaults.standard.set(url.path, forKey: preferenceKey)
                        }
                    }
                    #else
                    Text("Yerel kopyalar HDrive Dosyaları / Eşitleme altında tutulur.").font(.caption).foregroundStyle(.secondary)
                    #endif
                    TextField("Hariç tutulanlar (; ile ayırın)", text: $exclusions)
                        .onChange(of: exclusions) { _ in engine = nil; rows = [] }
                    Picker("Çakışma kararı", selection: $policy) { ForEach(FolderSyncPolicy.allCases, id: \.self) { Text($0.rawValue) } }
                    Toggle("Bu ekran açıkken her dakika eşitle", isOn: $automatic)
                    Text("Otomatik turda çakışmalar atlanır. Silmeler otomatik yayılmaz. Ekranı kapatmak otomatik eşitlemeyi durdurur.").font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("İşlemler")) {
                    HStack {
                        Button(L10n.text("Değişiklikleri Tara")) { Task { await scan() } }.disabled(busy || localRoot == nil)
                        Button(L10n.text("Seçilen Kararla Eşitle")) { Task { await apply(policy) } }.disabled(busy || engine == nil || rows.isEmpty)
                    }
                    if busy { ProgressView() }
                    Text(message).font(.callout).textSelection(.enabled)
                }
                Section(L10n.text("Değişiklikler")) {
                    ForEach(rows.filter { $0.action != .none }) { row in
                        VStack(alignment: .leading) {
                            Text(row.relativePath)
                            Text(row.action == .conflict ? "Çakışma · karar gerekiyor" : row.action == .upload ? "Buluta yüklenecek" : "Yerel klasöre indirilecek")
                                .font(.caption).foregroundStyle(row.action == .conflict ? .orange : .secondary)
                        }
                    }
                }
            }.navigationTitle("Klasör Eşitleme")
                .toolbar { Button(L10n.text("Bitti")) { dismiss() } }
                .onAppear(perform: setup)
                .task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                        if automatic && !busy { await scan(); if engine != nil { await apply(.skip) } }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }
    private var preferenceKey: String { "HDrive.Sync." + OfflineStore.identity(config) + S3Signing.hash(remoteRoot) }
    private func setup() {
        #if os(macOS)
        if let path = UserDefaults.standard.string(forKey: preferenceKey) { localRoot = URL(fileURLWithPath: path) }
        #else
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("HDriveFiles/Eşitleme/" + S3Signing.hash(preferenceKey).prefix(12))
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); localRoot = root }
        catch { message = error.localizedDescription }
        #endif
    }
    @MainActor private func scan() async {
        guard let localRoot = localRoot, !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard CloudreveManager.shared.servers.contains(where: { $0.isConnected && OfflineStore.identity($0) == OfflineStore.identity(config) }) else { throw URLError(.userAuthenticationRequired) }
            let synchronizer = FolderSynchronizer(client: WebDAVClient(config: config), localRoot: localRoot, remoteRoot: remoteRoot, exclusions: exclusions)
            rows = try await synchronizer.preview(); engine = synchronizer
            message = "\(rows.filter { $0.action != .none }.count) değişiklik · \(rows.filter { $0.action == .conflict }.count) çakışma"
        } catch { engine = nil; rows = []; message = error.localizedDescription }
    }
    @MainActor private func apply(_ decision: FolderSyncPolicy) async {
        guard let engine = engine, !busy else { return }
        busy = true
        do {
            let errors = try await engine.apply(rows, policy: decision)
            message = errors.isEmpty ? "Eşitleme tamamlandı. Atlanan çakışmalar sonraki taramada gösterilir." : errors.joined(separator: "\n")
            rows = try await engine.preview()
        } catch { message = error.localizedDescription }
        busy = false
    }
}

public struct CloudFolderPicker: View {
    let config: CloudreveServerConfig
    let onSelect: (String) -> Void
    @State private var current = ""
    @State private var history: [String] = []
    @State private var folders: [RemoteFileItem] = []
    @State private var errorMessage: String?
    @State private var loading = false
    @Environment(\.dismiss) private var dismiss
    public init(config: CloudreveServerConfig, onSelect: @escaping (String) -> Void) { self.config = config; self.onSelect = onSelect }
    public var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView() }
                if !history.isEmpty { Button(L10n.text("Geri")) { current = history.removeLast(); load() } }
                ForEach(folders) { folder in
                    Button { history.append(current); current = folder.href; load() } label: { Label(folder.name, systemImage: "folder") }
                }
                if let errorMessage = errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button("Buraya Taşı") { onSelect(current); dismiss() }.disabled(loading || errorMessage != nil)
            }.navigationTitle("Hedef Bulut Klasörü").onAppear(perform: load)
                .toolbar { Button(L10n.text("İptal")) { dismiss() } }
        }
    }
    private func load() {
        loading = true; errorMessage = nil
        WebDAVClient(config: config).listFiles(at: current) { result in
            loading = false
            switch result { case .success(let items): folders = items.filter { $0.isDirectory }; case .failure(let error): errorMessage = error.localizedDescription }
        }
    }
}
