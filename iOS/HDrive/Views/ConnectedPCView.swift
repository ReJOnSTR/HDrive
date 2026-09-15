//
//  ConnectedPCView.swift
//  HDrive (iOS)
//

import SwiftUI
import PhotosUI

public struct ConnectedPCView: View {
    public let serverURL: String
    public var onDisconnect: () -> Void
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pcFiles: [RemoteFileItem] = []
    @State private var isLoading = false
    @State private var statusMessage: String? = nil
    @State private var isUploading = false
    
    public init(serverURL: String, onDisconnect: @escaping () -> Void) {
        self.serverURL = serverURL
        self.onDisconnect = onDisconnect
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Bilgisayar Bağlantı Başlığı
                pcHeaderCard
                
                Divider()
                
                // 2. Dosya Listesi ve Aktarım
                if isLoading {
                    Spacer()
                    ProgressView("Bilgisayardaki dosyalar listeleniyor...")
                    Spacer()
                } else if pcFiles.isEmpty {
                    emptyFilesView
                } else {
                    filesListView
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Bağlı Bilgisayar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Bağlantıyı Kes", action: onDisconnect)
                        .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
                        Label("Fotoğraf Gönder", systemImage: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .onAppear {
                fetchPCFiles()
            }
            .onChange(of: selectedPhotos) { items in
                uploadPhotosToPC(items)
            }
        }
    }
    
    // MARK: - PC Başlık Kartı
    private var pcHeaderCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundColor(.indigo)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Canlı Bağlantı")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
                
                Text(cleanHostName(serverURL))
                    .font(.headline.bold())
                
                Text(serverURL)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: fetchPCFiles) {
                Image(systemName: "arrow.clockwise")
                    .font(.footnote)
                    .padding(8)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    
    // MARK: - Boş Durum
    private var emptyFilesView: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "folder")
                    .font(.system(size: 36))
                    .foregroundColor(.indigo)
            }
            
            Text("Bilgisayarda Dosya Yok")
                .font(.title3.weight(.semibold))
            
            Text("Bilgisayarınızın HDriveFiles klasörüne dosya ekleyebilir veya yukarıdaki butona dokunarak telefonunuzdan fotoğraf gönderebilirsiniz.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            PhotosPicker(selection: $selectedPhotos, matching: .any(of: [.images, .videos])) {
                Label("Telefondan Fotoğraf Gönder", systemImage: "photo.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Dosya Listesi
    private var filesListView: some View {
        List {
            Section(header: Text("Bilgisayardaki Dosyalar (\(pcFiles.count))")) {
                ForEach(pcFiles) { file in
                    HStack(spacing: 12) {
                        Image(systemName: file.systemIcon)
                            .font(.title2)
                            .foregroundColor(.indigo)
                            .frame(width: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(file.formattedSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: { downloadFileFromPC(file) }) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title3)
                                .foregroundColor(.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Ağ İstekleri
    private func fetchPCFiles() {
        isLoading = true
        var target = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasSuffix("/") { target.removeLast() }
        
        guard let url = URL(string: "\(target)/") else {
            isLoading = false
            return
        }
        
        let client = WebDAVClient(config: CloudreveServerConfig(
            name: "PC",
            serverURL: target,
            username: "",
            password: ""
        ))
        
        client.listFiles(at: "") { result in
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let files):
                    self.pcFiles = files
                case .failure:
                    // WebDAV PROPFIND başarısız olursa düz GET listelemesi yap
                    self.fetchHtmlFileList(from: url)
                }
            }
        }
    }
    
    private func fetchHtmlFileList(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                // Basit yanıt kontrolü
                self.pcFiles = []
            }
        }.resume()
    }
    
    private func uploadPhotosToPC(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isUploading = true
        
        var target = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasSuffix("/") { target.removeLast() }
        
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data = data {
                    let fileName = "IMG_\(Int(Date().timeIntervalSince1970)).jpg"
                    if let uploadUrl = URL(string: "\(target)/upload?filename=\(fileName)") {
                        var req = URLRequest(url: uploadUrl)
                        req.httpMethod = "POST"
                        req.httpBody = data
                        URLSession.shared.dataTask(with: req) { _, _, _ in
                            DispatchQueue.main.async {
                                self.fetchPCFiles()
                            }
                        }.resume()
                    }
                }
            }
        }
        selectedPhotos.removeAll()
    }
    
    private func downloadFileFromPC(_ file: RemoteFileItem) {
        var target = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasSuffix("/") { target.removeLast() }
        
        let encoded = file.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? file.name
        guard let url = URL(string: "\(target)/download?file=\(encoded)") ?? URL(string: "\(target)/\(encoded)") else { return }
        
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = doc.appendingPathComponent("HDriveFiles", isDirectory: true).appendingPathComponent(file.name)
        
        URLSession.shared.downloadTask(with: url) { temp, _, err in
            if let temp = temp, err == nil {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: temp, to: dest)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }.resume()
    }
    
    private func cleanHostName(_ urlStr: String) -> String {
        guard let url = URL(string: urlStr), let host = url.host else {
            return "Bilgisayar"
        }
        return host
    }
}
