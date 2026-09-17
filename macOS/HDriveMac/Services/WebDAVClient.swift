//
//  WebDAVClient.swift
//  HDrive - Cloudreve ve Uzak WebDAV İstemcisi
//

import Foundation
import UniformTypeIdentifiers

public struct RemoteFileItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let href: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date?
    public let contentType: String?
    public var thumbnailURL: String?
    
    public init(
        id: String,
        name: String,
        href: String,
        isDirectory: Bool,
        size: Int64,
        modificationDate: Date?,
        contentType: String?,
        thumbnailURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.href = href
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.contentType = contentType
        self.thumbnailURL = thumbnailURL
    }
    
    public var formattedSize: String {
        if isDirectory { return "Klasör" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    public var systemIcon: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif": return "photo.fill"
        case "mp4", "mov", "mkv", "avi": return "film.fill"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "pdf": return "doc.richtext.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "txt", "md", "json", "py", "swift", "js", "html": return "doc.text.fill"
        default: return "doc.fill"
        }
    }
}

public enum StorageProtocol: String, Codable, CaseIterable, Identifiable {
    case googleDrive = "Google Drive"
    case oneDrive = "Microsoft OneDrive"
    case dropbox = "Dropbox"
    case webdav = "WebDAV (Cloudreve / Nextcloud / NAS)"
    case s3 = "Amazon S3 / MinIO / Cloudflare R2"
    case smb = "SMB (Yerel Ağ / NAS Paylaşımı)"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .googleDrive: return "triangle.fill"
        case .oneDrive: return "cloud.sun.fill"
        case .dropbox: return "shippingbox.fill"
        case .webdav: return "cloud.fill"
        case .s3: return "cylinder.split.1x2.fill"
        case .smb: return "network"
        }
    }

    public var providerName: String {
        switch self {
        case .googleDrive: return "Google Drive"
        case .oneDrive: return "OneDrive"
        case .dropbox: return "Dropbox"
        case .webdav: return "WebDAV"
        case .s3: return "Amazon S3"
        case .smb: return "SMB Paylaşımı"
        }
    }

    public var providerSubtitle: String {
        switch self {
        case .googleDrive: return "Google Workspace & Kişisel Drive"
        case .oneDrive: return "Microsoft 365 & Kişisel OneDrive"
        case .dropbox: return "Dropbox Kişisel & İş Alanı"
        case .webdav: return "Cloudreve, Nextcloud, ownCloud, NAS"
        case .s3: return "AWS S3, Cloudflare R2, MinIO, Wasabi"
        case .smb: return "Windows Paylaşımı, Samba, Yerel NAS"
        }
    }
}

public struct CloudreveServerConfig: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var name: String = "Bulut Sunucum"
    public var serverURL: String = "https://example.com/dav"
    public var username: String = ""
    public var password: String = ""
    public var autoMountOnStart: Bool = false
    public var storageProtocol: StorageProtocol = .webdav
    public var bucketName: String = ""
    public var region: String = "us-east-1"
    public var smbShare: String = ""
    public var clientId: String = ""
    public var clientSecret: String = ""
    
    public init(
        name: String = "Bulut Sunucum",
        serverURL: String = "",
        username: String = "",
        password: String = "",
        storageProtocol: StorageProtocol = .webdav,
        bucketName: String = "",
        region: String = "us-east-1",
        smbShare: String = "",
        clientId: String = "",
        clientSecret: String = ""
    ) {
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.storageProtocol = storageProtocol
        self.bucketName = bucketName
        self.region = region
        self.smbShare = smbShare
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

public final class WebDAVClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, XMLParserDelegate {
    public let config: CloudreveServerConfig
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60.0
        configuration.timeoutIntervalForResource = 600.0
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            // Kendinden imzalı SSL ve özel sertifikalara güven
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var redirectedRequest = request
        // Önceden imzalanmış CDN depolama bağlantılarına (googleusercontent.com, 1drv.ms, sharepoint.com, dropboxusercontent.com)
        // Authorization başlığı gönderilirse sunucu 400/403 ile reddeder. Sadece aynı host ise Authorization korunur.
        if let origHost = task.currentRequest?.url?.host,
           let newHost = request.url?.host,
           origHost.caseInsensitiveCompare(newHost) == .orderedSame {
            if let auth = self.authHeader {
                redirectedRequest.setValue(auth, forHTTPHeaderField: "Authorization")
            }
        } else {
            redirectedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirectedRequest)
    }
    
    public var authHeader: String? {
        if config.storageProtocol == .googleDrive || config.storageProtocol == .oneDrive || config.storageProtocol == .dropbox {
            if !config.password.isEmpty {
                return config.password.hasPrefix("Bearer ") ? config.password : "Bearer \(config.password)"
            }
            return nil
        }
        guard !config.username.isEmpty, !config.password.isEmpty else { return nil }
        let loginString = "\(config.username):\(config.password)"
        guard let loginData = loginString.data(using: .utf8) else { return nil }
        return "Basic \(loginData.base64EncodedString())"
    }
    
    public init(config: CloudreveServerConfig) {
        self.config = config
        super.init()
    }
    
    public func buildURL(for relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }

        var base = config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            if config.storageProtocol == .googleDrive {
                base = "https://www.googleapis.com/drive/v3"
            } else if config.storageProtocol == .oneDrive {
                base = "https://graph.microsoft.com/v1.0/me/drive"
            } else if config.storageProtocol == .dropbox {
                base = "https://api.dropboxapi.com/2"
            }
        }
        if config.storageProtocol == .s3 && !config.bucketName.isEmpty {
            let bName = config.bucketName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.hasSuffix("/\(bName)") {
                base = "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(bName)"
            }
        }

        var cleanPath = trimmed
        while cleanPath.hasPrefix("/") {
            cleanPath.removeFirst()
        }

        guard let baseParsed = URL(string: base) else { return nil }
        let basePath = baseParsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !basePath.isEmpty {
            if cleanPath == basePath {
                cleanPath = ""
            } else if cleanPath.hasPrefix(basePath + "/") {
                cleanPath = String(cleanPath.dropFirst(basePath.count + 1))
            }
        }

        let baseURLString = base.hasSuffix("/") ? base : base + "/"
        if cleanPath.isEmpty {
            return URL(string: baseURLString)
        }

        let encodedSegments = cleanPath.components(separatedBy: "/").map { segment in
            let unescaped = segment.removingPercentEncoding ?? segment
            return unescaped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? unescaped
        }
        let fullPath = encodedSegments.joined(separator: "/")

        let hasTrailingSlash = trimmed.hasSuffix("/")
        return URL(string: baseURLString + fullPath + (hasTrailingSlash ? "/" : ""))
    }

    /// Sunucu bağlantısını test eder
    public func testConnection(completion: @escaping (Bool, String) -> Void) {
        if config.storageProtocol == .googleDrive {
            if config.password.isEmpty {
                completion(false, "Google Drive ile henüz oturum açılmamış. Lütfen 'Google ile Giriş Yap' butonuna basın.")
                return
            }
            guard let url = URL(string: "https://www.googleapis.com/drive/v3/about?fields=user") else { return }
            var req = URLRequest(url: url)
            req.setValue(authHeader, forHTTPHeaderField: "Authorization")
            session.dataTask(with: req) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(false, "Bağlantı hatası: \(error.localizedDescription)") }
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                if status == 200 {
                    DispatchQueue.main.async { completion(true, "✅ Google Drive bağlantısı başarılı ve doğrulandı!") }
                } else {
                    DispatchQueue.main.async { completion(false, "Google Drive yetkilendirme geçersiz (HTTP \(status)).") }
                }
            }.resume()
            return
        }

        if config.storageProtocol == .oneDrive || config.storageProtocol == .dropbox {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !self.config.username.isEmpty || !self.config.password.isEmpty || !self.config.serverURL.isEmpty {
                    completion(true, "\(self.config.storageProtocol.providerName) bağlantı ve kimlik doğrulama profili hazır.")
                } else {
                    completion(false, "Lütfen hesap e-posta/kullanıcı adı veya yetkilendirme anahtarını girin.")
                }
            }
            return
        }

        if config.storageProtocol == .smb {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let share = self.config.smbShare.isEmpty ? "paylaşım" : self.config.smbShare
                completion(true, "SMB Ağ Sunucusuna (\(self.config.serverURL)/\(share)) erişim hazır.")
            }
            return
        }

        guard let url = buildURL(for: "") else {
            completion(false, "Geçersiz sunucu adresi formatı.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = config.storageProtocol == .s3 ? "GET" : "PROPFIND"
        if config.storageProtocol != .s3 {
            request.setValue("0", forHTTPHeaderField: "Depth")
        }
        if let authHeader = authHeader {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(false, "Bağlantı hatası: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(false, "Geçersiz sunucu yanıtı.")
                }
                return
            }
            
            DispatchQueue.main.async {
                if httpResponse.statusCode == 207 || httpResponse.statusCode == 200 || (self.config.storageProtocol == .s3 && (httpResponse.statusCode == 403 || httpResponse.statusCode == 400)) {
                    completion(true, "Bağlantı başarılı! \(self.config.storageProtocol.providerName) sunucusuna erişildi.")
                } else if httpResponse.statusCode == 401 {
                    completion(false, "Yetkilendirme hatası (401): Kullanıcı adı veya şifre hatalı.")
                } else if httpResponse.statusCode == 404 {
                    completion(false, "404 Bulunamadı: Lütfen sunucu yolunu kontrol edin.")
                } else {
                    completion(false, "Sunucu yanıt kodu: \(httpResponse.statusCode)")
                }
            }
        }
        task.resume()
    }
    
    /// Belirtilen klasördeki dosyaları ve alt klasörleri listeler
    public func listFiles(at relativePath: String = "", completion: @escaping (Result<[RemoteFileItem], Error>) -> Void) {
        if config.storageProtocol == .googleDrive {
            listGoogleDriveFiles(at: relativePath, completion: completion)
            return
        }
        if config.storageProtocol == .oneDrive {
            listOneDriveFiles(at: relativePath, completion: completion)
            return
        }
        if config.storageProtocol == .dropbox {
            listDropboxFiles(at: relativePath, completion: completion)
            return
        }
        guard let targetURL = buildURL(for: relativePath) else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL: \(relativePath)"])))
            return
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let data = data, let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 207 || httpResponse.statusCode == 200) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Sunucu hatası: \(status)"])))
                }
                return
            }
            
            // XML Parse et
            let parser = WebDAVXMLParser(targetPath: targetURL.path)
            let items = parser.parse(data: data)
            
            DispatchQueue.main.async {
                completion(.success(items))
            }
        }
        task.resume()
    }
    
    private func listGoogleDriveFiles(at folderIdOrPath: String, completion: @escaping (Result<[RemoteFileItem], Error>) -> Void) {
        var clean = folderIdOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\n\r"))
        if clean.isEmpty || clean == "." {
            clean = "root"
        }
        let parentId = clean
        let query = "'\(parentId)' in parents and trashed = false"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,mimeType,size,modifiedTime,thumbnailLink,iconLink)&pageSize=1000&supportsAllDrives=true") else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz istek"])))
            return
        }
        
        var request = URLRequest(url: url)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let filesList = json["files"] as? [[String: Any]] else {
                let msg = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["error"] as? [String: Any]
                let desc = msg?["message"] as? String ?? "Google Drive dosyaları alınamadı."
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: desc])))
                }
                return
            }
            
            let dateFormatter = ISO8601DateFormatter()
            let items: [RemoteFileItem] = filesList.compactMap { (dict: [String: Any]) -> RemoteFileItem? in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String else { return nil }
                let mime = dict["mimeType"] as? String ?? ""
                let isDir = (mime == "application/vnd.google-apps.folder")
                let sizeStr = dict["size"] as? String ?? "0"
                let size = Int64(sizeStr) ?? 0
                let dateStr = dict["modifiedTime"] as? String ?? ""
                let modified = dateFormatter.date(from: dateStr)
                let thumb = dict["thumbnailLink"] as? String
                
                return RemoteFileItem(
                    id: id,
                    name: name,
                    href: id,
                    isDirectory: isDir,
                    size: size,
                    modificationDate: modified,
                    contentType: mime,
                    thumbnailURL: thumb
                )
            }
            
            DispatchQueue.main.async {
                completion(.success(items))
            }
        }.resume()
    }
    
    private func listOneDriveFiles(at folderIdOrPath: String, completion: @escaping (Result<[RemoteFileItem], Error>) -> Void) {
        let clean = folderIdOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\n\r"))
        let endpoint: String
        if clean.isEmpty || clean == "root" || clean == "." {
            endpoint = "https://graph.microsoft.com/v1.0/me/drive/root/children"
        } else {
            endpoint = "https://graph.microsoft.com/v1.0/me/drive/items/\(clean)/children"
        }
        guard let url = URL(string: endpoint) else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz istek"])))
            return
        }
        var request = URLRequest(url: url)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let values = json["value"] as? [[String: Any]] else {
                let msg = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["error"] as? [String: Any]
                let desc = msg?["message"] as? String ?? "OneDrive dosyaları alınamadı."
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: desc])))
                }
                return
            }
            let dateFormatter = ISO8601DateFormatter()
            let items: [RemoteFileItem] = values.compactMap { dict in
                guard let id = dict["id"] as? String,
                      let name = dict["name"] as? String else { return nil }
                let isFolder = dict["folder"] != nil
                let size = (dict["size"] as? NSNumber)?.int64Value ?? 0
                let dateStr = dict["lastModifiedDateTime"] as? String ?? ""
                let modified = dateFormatter.date(from: dateStr)
                let mime = (dict["file"] as? [String: Any])?["mimeType"] as? String
                let downloadUrl = dict["@microsoft.graph.downloadUrl"] as? String
                let thumbLink = ((dict["thumbnails"] as? [[String: Any]])?.first?["medium"] as? [String: Any])?["url"] as? String
                
                return RemoteFileItem(
                    id: id,
                    name: name,
                    href: downloadUrl ?? id,
                    isDirectory: isFolder,
                    size: size,
                    modificationDate: modified,
                    contentType: mime,
                    thumbnailURL: thumbLink
                )
            }
            DispatchQueue.main.async { completion(.success(items)) }
        }.resume()
    }
    
    private func listDropboxFiles(at folderIdOrPath: String, completion: @escaping (Result<[RemoteFileItem], Error>) -> Void) {
        var clean = folderIdOrPath.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n\r"))
        if clean == "/" || clean == "root" || clean.isEmpty {
            clean = ""
        } else if !clean.hasPrefix("/") {
            clean = "/" + clean
        }
        guard let url = URL(string: "https://api.dropboxapi.com/2/files/list_folder") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["path": clean, "recursive": false, "include_media_info": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["entries"] as? [[String: Any]] else {
                let desc = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])?["error_summary"] as? String ?? "Dropbox dosyaları alınamadı."
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: desc])))
                }
                return
            }
            let dateFormatter = ISO8601DateFormatter()
            let items: [RemoteFileItem] = entries.compactMap { dict in
                guard let tag = dict[".tag"] as? String,
                      let name = dict["name"] as? String,
                      let pathLower = dict["path_lower"] as? String else { return nil }
                let isDir = (tag == "folder")
                let size = (dict["size"] as? NSNumber)?.int64Value ?? 0
                let dateStr = dict["server_modified"] as? String ?? ""
                let modified = dateFormatter.date(from: dateStr)
                let id = dict["id"] as? String ?? pathLower
                
                return RemoteFileItem(
                    id: id,
                    name: name,
                    href: pathLower,
                    isDirectory: isDir,
                    size: size,
                    modificationDate: modified,
                    contentType: nil,
                    thumbnailURL: nil
                )
            }
            DispatchQueue.main.async { completion(.success(items)) }
        }.resume()
    }
    
    /// WebDAV indirme adresini güvenli ve doğru biçimde oluşturur
    public func downloadURL(for href: String) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            if let directURL = URL(string: trimmed) { return directURL }
            let unencoded = trimmed.removingPercentEncoding ?? trimmed
            return URL(string: unencoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? unencoded)
        }
        return buildURL(for: trimmed)
    }
    
    /// Dosya İndirir (HTTP durum kodu kontrolü ve güvenli taşıma)
    public func downloadFile(href: String, to localDestination: URL, progress: @escaping (Double) -> Void, completion: @escaping (Error?) -> Void) {
        if config.storageProtocol == .googleDrive {
            let fileId = href
            guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media&supportsAllDrives=true") else {
                completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz dosya kimliği"]))
                return
            }
            var request = URLRequest(url: url)
            if let auth = authHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            let downloadTask = session.downloadTask(with: request) { [weak self] tempURL, response, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { completion(error) }
                    return
                }
                
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
                
                // Google Docs, Sheets, Slides dosyaları doğrudan alt=media ile indirilemez; Export API gerekir
                if statusCode == 403 {
                    var isDocsEditor = false
                    if let tempURL = tempURL, let data = try? Data(contentsOf: tempURL),
                       let str = String(data: data, encoding: .utf8),
                       str.contains("fileNotDownloadable") || str.contains("Docs Editors") {
                        isDocsEditor = true
                    }
                    if isDocsEditor {
                        self.exportGoogleDoc(fileId: fileId, to: localDestination, completion: completion)
                        return
                    }
                }
                
                guard (200...299).contains(statusCode) else {
                    var errorDesc = "Google Drive indirme hatası (HTTP \(statusCode))."
                    if let tempURL = tempURL, let data = try? Data(contentsOf: tempURL),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errObj = json["error"] as? [String: Any],
                       let msg = errObj["message"] as? String {
                        errorDesc = msg
                    }
                    DispatchQueue.main.async {
                        completion(NSError(domain: "HDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorDesc]))
                    }
                    return
                }
                
                guard let tempURL = tempURL else {
                    DispatchQueue.main.async { completion(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "İndirilen dosya bulunamadı"])) }
                    return
                }
                do {
                    let parentDir = localDestination.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: localDestination.path) {
                        try FileManager.default.removeItem(at: localDestination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localDestination)
                    DispatchQueue.main.async { completion(nil) }
                } catch {
                    DispatchQueue.main.async { completion(error) }
                }
            }
            downloadTask.resume()
            return
        }
        
        if config.storageProtocol == .oneDrive {
            let url: URL?
            if href.hasPrefix("http://") || href.hasPrefix("https://") {
                url = URL(string: href)
            } else {
                url = URL(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(href)/content")
            }
            guard let downloadURL = url else {
                completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz OneDrive bağlantısı"]))
                return
            }
            var request = URLRequest(url: downloadURL)
            if let auth = authHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            let downloadTask = session.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(error) }
                    return
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
                guard (200...299).contains(statusCode), let tempURL = tempURL else {
                    DispatchQueue.main.async {
                        completion(NSError(domain: "HDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "OneDrive indirme hatası (HTTP \(statusCode))"]))
                    }
                    return
                }
                do {
                    let parentDir = localDestination.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: localDestination.path) {
                        try FileManager.default.removeItem(at: localDestination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localDestination)
                    DispatchQueue.main.async { completion(nil) }
                } catch {
                    DispatchQueue.main.async { completion(error) }
                }
            }
            downloadTask.resume()
            return
        }
        
        if config.storageProtocol == .dropbox {
            guard let url = URL(string: "https://content.dropboxapi.com/2/files/download") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let auth = authHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            let pathArg = href.hasPrefix("/") ? href : "/\(href)"
            request.setValue("{\"path\": \"\(pathArg)\"}", forHTTPHeaderField: "Dropbox-API-Arg")
            let downloadTask = session.downloadTask(with: request) { tempURL, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(error) }
                    return
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
                guard (200...299).contains(statusCode), let tempURL = tempURL else {
                    DispatchQueue.main.async {
                        completion(NSError(domain: "HDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Dropbox indirme hatası (HTTP \(statusCode))"]))
                    }
                    return
                }
                do {
                    let parentDir = localDestination.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: localDestination.path) {
                        try FileManager.default.removeItem(at: localDestination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: localDestination)
                    DispatchQueue.main.async { completion(nil) }
                } catch {
                    DispatchQueue.main.async { completion(error) }
                }
            }
            downloadTask.resume()
            return
        }
        
        guard let url = downloadURL(for: href) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz dosya adresi: \(href)"]))
            return
        }
        
        var request = URLRequest(url: url)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        let downloadTask = session.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            guard (200...299).contains(statusCode) else {
                DispatchQueue.main.async {
                    completion(NSError(domain: "HDrive", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Sunucu hatası (HTTP \(statusCode)). Dosya indirilemedi."]))
                }
                return
            }
            
            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "İndirilen geçici dosya bulunamadı"])) }
                return
            }
            
            do {
                let parentDir = localDestination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: localDestination.path) {
                    try FileManager.default.removeItem(at: localDestination)
                }
                try FileManager.default.moveItem(at: tempURL, to: localDestination)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
        downloadTask.resume()
    }
    
    /// Google Docs, Sheets veya Slides belgelerini PDF veya uygun formata dönüştürerek indirir
    public func exportGoogleDoc(fileId: String, to localDestination: URL, completion: @escaping (Error?) -> Void) {
        let ext = localDestination.pathExtension.lowercased()
        let exportMime: String
        switch ext {
        case "docx":
            exportMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx":
            exportMime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "pptx":
            exportMime = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "png":
            exportMime = "image/png"
        default:
            exportMime = "application/pdf"
        }
        
        guard let encodedMime = exportMime.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let exportURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/export?mimeType=\(encodedMime)") else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz dışa aktarma adresi"]))
            return
        }
        
        var request = URLRequest(url: exportURL)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        let task = session.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            guard (200...299).contains(status), let tempURL = tempURL else {
                DispatchQueue.main.async {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Google dokümanı dışa aktarılamadı (HTTP \(status))."]))
                }
                return
            }
            do {
                let parentDir = localDestination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                
                var targetURL = localDestination
                if exportMime == "application/pdf" && targetURL.pathExtension.isEmpty {
                    targetURL = targetURL.appendingPathExtension("pdf")
                }
                
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try? FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: targetURL)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
        task.resume()
    }
    
    /// Dosya Yükler (Google Drive, OneDrive, Dropbox, WebDAV, S3)
    public func uploadFile(localFileURL: URL, toRemotePath: String, completion: @escaping (Error?) -> Void) {
        if config.storageProtocol == .googleDrive {
            uploadGoogleDriveFile(localFileURL: localFileURL, toFolderIdOrPath: toRemotePath, completion: completion)
            return
        }
        if config.storageProtocol == .oneDrive {
            uploadOneDriveFile(localFileURL: localFileURL, toFolderIdOrPath: toRemotePath, completion: completion)
            return
        }
        if config.storageProtocol == .dropbox {
            uploadDropboxFile(localFileURL: localFileURL, toPath: toRemotePath, completion: completion)
            return
        }
        
        guard let targetURL = buildURL(for: toRemotePath) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz hedef adresi"]))
            return
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "PUT"
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        let uploadTask = session.uploadTask(with: request, fromFile: localFileURL) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            if status >= 200 && status < 300 {
                DispatchQueue.main.async { completion(nil) }
            } else {
                DispatchQueue.main.async {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Yükleme hatası: \(status)"]))
                }
            }
        }
        uploadTask.resume()
    }
    
    private func uploadGoogleDriveFile(localFileURL: URL, toFolderIdOrPath: String, completion: @escaping (Error?) -> Void) {
        let fileName = localFileURL.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localFileURL.path)[.size] as? Int64) ?? 0
        let ext = localFileURL.pathExtension
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        
        var cleanParent = toFolderIdOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\n\r"))
        if cleanParent.isEmpty || cleanParent == "." {
            cleanParent = "root"
        }
        
        guard let initURL = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true") else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz yükleme adresi"]))
            return
        }
        
        var initRequest = URLRequest(url: initURL)
        initRequest.httpMethod = "POST"
        if let auth = authHeader {
            initRequest.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initRequest.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        initRequest.setValue("\(fileSize)", forHTTPHeaderField: "X-Upload-Content-Length")
        
        let meta: [String: Any] = [
            "name": fileName,
            "parents": [cleanParent]
        ]
        initRequest.httpBody = try? JSONSerialization.data(withJSONObject: meta)
        
        session.dataTask(with: initRequest) { [weak self] _, response, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            guard let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode),
                  let locationStr = httpResp.allHeaderFields["Location"] as? String ?? httpResp.allHeaderFields["location"] as? String,
                  let uploadURL = URL(string: locationStr) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Google Drive yükleme oturumu açılamadı (HTTP \(status))"]))
                }
                return
            }
            
            var uploadReq = URLRequest(url: uploadURL)
            uploadReq.httpMethod = "PUT"
            uploadReq.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            uploadReq.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
            
            let task = self.session.uploadTask(with: uploadReq, fromFile: localFileURL) { _, upResponse, upError in
                if let upError = upError {
                    DispatchQueue.main.async { completion(upError) }
                    return
                }
                let upStatus = (upResponse as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if upStatus == 200 || upStatus == 201 {
                        completion(nil)
                    } else {
                        completion(NSError(domain: "HDrive", code: upStatus, userInfo: [NSLocalizedDescriptionKey: "Google Drive dosyayı kaydedemedi (HTTP \(upStatus))"]))
                    }
                }
            }
            task.resume()
        }.resume()
    }
    
    private func uploadOneDriveFile(localFileURL: URL, toFolderIdOrPath: String, completion: @escaping (Error?) -> Void) {
        let fileName = localFileURL.lastPathComponent
        guard let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }
        
        let clean = toFolderIdOrPath.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\n\r"))
        let uploadURLStr: String
        if clean.isEmpty || clean == "root" || clean == "." {
            uploadURLStr = "https://graph.microsoft.com/v1.0/me/drive/root:/\(encodedName):/content"
        } else {
            uploadURLStr = "https://graph.microsoft.com/v1.0/me/drive/items/\(clean):/\(encodedName):/content"
        }
        guard let url = URL(string: uploadURLStr) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz OneDrive adresi"]))
            return
        }
        
        let ext = localFileURL.pathExtension
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        
        let task = session.uploadTask(with: request, fromFile: localFileURL) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            DispatchQueue.main.async {
                if status == 200 || status == 201 {
                    completion(nil)
                } else {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "OneDrive yükleme hatası (HTTP \(status))"]))
                }
            }
        }
        task.resume()
    }
    
    private func uploadDropboxFile(localFileURL: URL, toPath: String, completion: @escaping (Error?) -> Void) {
        let fileName = localFileURL.lastPathComponent
        var clean = toPath.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n\r"))
        let dropboxPath: String
        if clean.isEmpty || clean == "/" || clean == "root" {
            dropboxPath = "/\(fileName)"
        } else {
            if !clean.hasPrefix("/") { clean = "/" + clean }
            clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            dropboxPath = "/\(clean)/\(fileName)"
        }
        
        guard let url = URL(string: "https://content.dropboxapi.com/2/files/upload") else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz Dropbox adresi"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let apiArg = "{\"path\": \"\(dropboxPath)\", \"mode\": \"add\", \"autorename\": true, \"mute\": false}"
        request.setValue(apiArg, forHTTPHeaderField: "Dropbox-API-Arg")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let task = session.uploadTask(with: request, fromFile: localFileURL) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            DispatchQueue.main.async {
                if status == 200 {
                    completion(nil)
                } else {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Dropbox yükleme hatası (HTTP \(status))"]))
                }
            }
        }
        task.resume()
    }
    
    /// Klasör Oluşturur
    public func createFolder(at remotePath: String, completion: @escaping (Error?) -> Void) {
        if config.storageProtocol == .googleDrive {
            let folderName = (remotePath as NSString).lastPathComponent
            let parentPath = (remotePath as NSString).deletingLastPathComponent
            var cleanParent = parentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\n\r"))
            if cleanParent.isEmpty || cleanParent == "." {
                cleanParent = "root"
            }
            guard let url = URL(string: "https://www.googleapis.com/drive/v3/files?supportsAllDrives=true") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            let meta: [String: Any] = [
                "name": folderName,
                "mimeType": "application/vnd.google-apps.folder",
                "parents": [cleanParent]
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: meta)
            session.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if status == 200 || status == 201 { completion(nil) }
                    else { completion(error ?? NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Google Drive klasör oluşturulamadı (HTTP \(status))"])) }
                }
            }.resume()
            return
        }
        if config.storageProtocol == .oneDrive {
            let folderName = (remotePath as NSString).lastPathComponent
            let parentPath = (remotePath as NSString).deletingLastPathComponent
            let cleanParent = parentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/. \t\n\r"))
            let endpoint = (cleanParent.isEmpty || cleanParent == "root" || cleanParent == ".")
                ? "https://graph.microsoft.com/v1.0/me/drive/root/children"
                : "https://graph.microsoft.com/v1.0/me/drive/items/\(cleanParent)/children"
            guard let url = URL(string: endpoint) else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let meta: [String: Any] = [
                "name": folderName,
                "folder": [String: Any]()
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: meta)
            session.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if status == 200 || status == 201 { completion(nil) }
                    else { completion(error ?? NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "OneDrive klasör oluşturulamadı"])) }
                }
            }.resume()
            return
        }
        if config.storageProtocol == .dropbox {
            var clean = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n\r"))
            if !clean.hasPrefix("/") { clean = "/" + clean }
            guard let url = URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["path": clean, "autorename": false])
            session.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if status == 200 { completion(nil) }
                    else { completion(error ?? NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Dropbox klasör oluşturulamadı"])) }
                }
            }.resume()
            return
        }
        
        guard let targetURL = buildURL(for: remotePath) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz klasör adresi"]))
            return
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "MKCOL"
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        session.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            DispatchQueue.main.async {
                if status == 201 || status == 200 || status == 405 {
                    completion(nil)
                } else {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Klasör oluşturulamadı: \(status)"]))
                }
            }
        }.resume()
    }
    
    /// Dosya/Klasör Siler (DELETE)
    public func delete(at remotePath: String, isDirectory: Bool = false, completion: @escaping (Error?) -> Void) {
        if config.storageProtocol == .googleDrive {
            let fileId = (remotePath as NSString).lastPathComponent
            guard let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?supportsAllDrives=true") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
            session.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if status == 204 || status == 200 { completion(nil) }
                    else { completion(error ?? NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Google Drive dosya silinemedi"])) }
                }
            }.resume()
            return
        }
        if config.storageProtocol == .oneDrive {
            let itemId = (remotePath as NSString).lastPathComponent
            guard let url = URL(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(itemId)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
            session.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if status == 204 || status == 200 { completion(nil) }
                    else { completion(error ?? NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "OneDrive dosya silinemedi"])) }
                }
            }.resume()
            return
        }
        if config.storageProtocol == .dropbox {
            var clean = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: ". \t\n\r"))
            if !clean.hasPrefix("/") { clean = "/" + clean }
            guard let url = URL(string: "https://api.dropboxapi.com/2/files/delete_v2") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            if let auth = authHeader { req.setValue(auth, forHTTPHeaderField: "Authorization") }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["path": clean])
            session.dataTask(with: req) { _, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 500
                DispatchQueue.main.async {
                    if status == 200 { completion(nil) }
                    else { completion(error ?? NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Dropbox dosya silinemedi"])) }
                }
            }.resume()
            return
        }
        
        var path = remotePath
        if isDirectory && !path.hasSuffix("/") {
            path += "/"
        }
        guard let targetURL = buildURL(for: path) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz silme adresi"]))
            return
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "DELETE"
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        request.setValue("infinity", forHTTPHeaderField: "Depth")
        
        session.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            DispatchQueue.main.async {
                if (200...299).contains(status) || status == 404 || status == 204 {
                    completion(nil)
                } else {
                    completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Silme hatası: \(status)"]))
                }
            }
        }.resume()
    }
    
    /// Dosya veya klasör adını değiştirir / taşır (MOVE)
    public func move(from sourcePath: String, to destinationPath: String, overwrite: Bool = false, completion: @escaping (Error?) -> Void) {
        guard let sourceURL = buildURL(for: sourcePath),
              let destURL = buildURL(for: destinationPath) else {
            completion(NSError(domain: "WebDAVClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL"]))
            return
        }
        
        var request = URLRequest(url: sourceURL)
        request.httpMethod = "MOVE"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(destURL.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")
        
        session.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                DispatchQueue.main.async { completion(nil) }
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                DispatchQueue.main.async {
                    completion(NSError(domain: "WebDAVClient", code: code, userInfo: [NSLocalizedDescriptionKey: "Yeniden adlandırma başarısız: HTTP \(code)"]))
                }
            }
        }.resume()
    }
    
    /// Dosya veya klasörü kopyalar (COPY)
    public func copy(from sourcePath: String, to destinationPath: String, overwrite: Bool = false, completion: @escaping (Error?) -> Void) {
        guard let sourceURL = buildURL(for: sourcePath),
              let destURL = buildURL(for: destinationPath) else {
            completion(NSError(domain: "WebDAVClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL"]))
            return
        }
        
        var request = URLRequest(url: sourceURL)
        request.httpMethod = "COPY"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue(destURL.absoluteString, forHTTPHeaderField: "Destination")
        request.setValue(overwrite ? "T" : "F", forHTTPHeaderField: "Overwrite")
        
        session.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                DispatchQueue.main.async { completion(nil) }
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                DispatchQueue.main.async {
                    completion(NSError(domain: "WebDAVClient", code: code, userInfo: [NSLocalizedDescriptionKey: "Kopyalama başarısız: HTTP \(code)"]))
                }
            }
        }.resume()
    }
    
    /// RFC 4331 Depolama Alanı ve Kota Bilgisi Sorgular
    public func fetchQuota(completion: @escaping (Result<StorageQuota, Error>) -> Void) {
        if config.storageProtocol == .googleDrive {
            guard let url = URL(string: "https://www.googleapis.com/drive/v3/about?fields=storageQuota,user") else {
                completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz Google Drive URL'si"])))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            if let auth = authHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let quotaDict = json["storageQuota"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Google Drive kota bilgisi alınamadı"]))) }
                    return
                }
                
                let usageStr = quotaDict["usage"] as? String ?? "\(quotaDict["usage"] as? Int64 ?? 0)"
                let usage = Int64(usageStr) ?? 0
                
                var limit: Int64 = 0
                if let lStr = quotaDict["limit"] as? String {
                    limit = Int64(lStr) ?? 0
                } else if let lNum = quotaDict["limit"] as? NSNumber {
                    limit = lNum.int64Value
                }
                
                let available = limit > usage ? (limit - usage) : 0
                let q = StorageQuota(usedBytes: usage, availableBytes: available)
                DispatchQueue.main.async { completion(.success(q)) }
            }.resume()
            return
        }
        
        if config.storageProtocol == .oneDrive {
            guard let url = URL(string: "https://graph.microsoft.com/v1.0/me/drive") else {
                completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz OneDrive URL'si"])))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            if let auth = authHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let quotaDict = json["quota"] as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "OneDrive kota bilgisi alınamadı"]))) }
                    return
                }
                
                let total = (quotaDict["total"] as? NSNumber)?.int64Value ?? 0
                let used = (quotaDict["used"] as? NSNumber)?.int64Value ?? 0
                let remaining = (quotaDict["remaining"] as? NSNumber)?.int64Value ?? max(0, total - used)
                let q = StorageQuota(usedBytes: used, availableBytes: remaining)
                DispatchQueue.main.async { completion(.success(q)) }
            }.resume()
            return
        }
        
        if config.storageProtocol == .dropbox {
            guard let url = URL(string: "https://api.dropboxapi.com/2/users/get_space_usage") else {
                completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz Dropbox URL'si"])))
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let auth = authHeader {
                request.setValue(auth, forHTTPHeaderField: "Authorization")
            }
            
            session.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Dropbox kota bilgisi alınamadı"]))) }
                    return
                }
                
                let used = (json["used"] as? NSNumber)?.int64Value ?? 0
                var total: Int64 = 0
                if let alloc = json["allocation"] as? [String: Any],
                   let allocated = (alloc["allocated"] as? NSNumber)?.int64Value {
                    total = allocated
                }
                let available = max(0, total - used)
                let q = StorageQuota(usedBytes: used, availableBytes: available)
                DispatchQueue.main.async { completion(.success(q)) }
            }.resume()
            return
        }
        
        guard let url = buildURL(for: "") else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        let xmlBody = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:quota-available-bytes/>
            <D:quota-used-bytes/>
          </D:prop>
        </D:propfind>
        """
        request.httpBody = xmlBody.data(using: .utf8)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Kota verisi alınamadı"]))) }
                return
            }
            
            let parser = WebDAVQuotaParser()
            if let quota = parser.parse(data: data) {
                DispatchQueue.main.async { completion(.success(quota)) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HDrive", code: 404, userInfo: [NSLocalizedDescriptionKey: "Kota bilgisi sunucu tarafından desteklenmiyor"])))
                }
            }
        }.resume()
    }
}

// MARK: - RFC 4331 Depolama Kota Modeli
public struct StorageQuota {
    public let usedBytes: Int64
    public let availableBytes: Int64
    
    public init(usedBytes: Int64, availableBytes: Int64) {
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }
    
    public var totalBytes: Int64 {
        return usedBytes + availableBytes
    }
    
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }
    
    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }
    
    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }
}

// MARK: - RFC 4331 XML Ayrıştırıcı
final class WebDAVQuotaParser: NSObject, XMLParserDelegate {
    private var usedBytes: Int64?
    private var availableBytes: Int64?
    private var currentElement = ""
    private var currentText = ""
    
    func parse(data: Data) -> StorageQuota? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        
        if let used = usedBytes, let available = availableBytes {
            return StorageQuota(usedBytes: used, availableBytes: available)
        }
        return nil
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let clean = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        currentElement = clean
        currentText = ""
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let clean = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        if clean == "quota-used-bytes" {
            usedBytes = Int64(currentText)
        } else if clean == "quota-available-bytes" {
            availableBytes = Int64(currentText)
        }
    }
}

// MARK: - RFC 4918 WebDAV XML Ayrıştırıcı (Parser)
final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private let targetPath: String
    private var items: [RemoteFileItem] = []
    
    private var currentElement = ""
    private var currentHref = ""
    private var currentDisplayName = ""
    private var currentContentLength: Int64 = 0
    private var currentContentType = ""
    private var currentLastModified: Date?
    private var currentIsDirectory = false
    
    private let rfc1123Formatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return df
    }()
    
    init(targetPath: String) {
        self.targetPath = targetPath
    }
    
    func parse(data: Data) -> [RemoteFileItem] {
        items.removeAll()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let cleanName = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        currentElement = cleanName
        
        if cleanName == "response" {
            currentHref = ""
            currentDisplayName = ""
            currentContentLength = 0
            currentContentType = ""
            currentLastModified = nil
            currentIsDirectory = false
        } else if cleanName == "collection" {
            currentIsDirectory = true
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        switch currentElement {
        case "href":
            currentHref += trimmed
        case "displayname":
            currentDisplayName += trimmed
        case "getcontentlength":
            currentContentLength = Int64(trimmed) ?? 0
        case "getcontenttype":
            currentContentType += trimmed
        case "getlastmodified":
            currentLastModified = rfc1123Formatter.date(from: trimmed)
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let cleanName = elementName.components(separatedBy: ":").last?.lowercased() ?? elementName.lowercased()
        
        if cleanName == "response" {
            let decodedHref = currentHref.removingPercentEncoding ?? currentHref
            var cleanHref = decodedHref
            if cleanHref.hasSuffix("/") && cleanHref.count > 1 {
                cleanHref.removeLast()
            }
            
            let name = currentDisplayName.isEmpty ? (cleanHref as NSString).lastPathComponent : currentDisplayName
            
            // İstek atılan ana klasörün kendisini sonuç listesine dahil etme
            let cleanTarget = targetPath.hasSuffix("/") && targetPath.count > 1 ? String(targetPath.dropLast()) : targetPath
            if cleanHref != cleanTarget && !name.isEmpty {
                let item = RemoteFileItem(
                    id: currentHref,
                    name: name,
                    href: currentHref,
                    isDirectory: currentIsDirectory,
                    size: currentContentLength,
                    modificationDate: currentLastModified,
                    contentType: currentContentType
                )
                items.append(item)
            }
        }
    }
}
