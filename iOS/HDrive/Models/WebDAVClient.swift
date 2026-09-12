//
//  WebDAVClient.swift
//  HDrive - Cloudreve ve Uzak WebDAV İstemcisi
//

import Foundation

public struct RemoteFileItem: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let href: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date?
    public let contentType: String?
    
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

public struct CloudreveServerConfig: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var name: String = "Cloudreve Sunucum"
    public var serverURL: String = "https://example.com/dav"
    public var username: String = ""
    public var password: String = ""
    public var autoMountOnStart: Bool = false
    
    public init(name: String = "Cloudreve Sunucum", serverURL: String = "", username: String = "", password: String = "") {
        self.name = name
        self.serverURL = serverURL
        self.username = username
        self.password = password
    }
}

public final class WebDAVClient: NSObject, URLSessionDelegate, XMLParserDelegate {
    public let config: CloudreveServerConfig
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
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
    
    public init(config: CloudreveServerConfig) {
        self.config = config
    }
    
    private var authHeader: String {
        let loginString = "\(config.username):\(config.password)"
        guard let loginData = loginString.data(using: .utf8) else { return "" }
        return "Basic " + loginData.base64EncodedString()
    }
    
    /// Sunucu bağlantısını test eder
    public func testConnection(completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: config.serverURL) else {
            completion(false, "Geçersiz sunucu adresi formatı.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
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
                if httpResponse.statusCode == 207 || httpResponse.statusCode == 200 {
                    completion(true, "Bağlantı başarılı! Cloudreve WebDAV sunucusuna erişildi.")
                } else if httpResponse.statusCode == 401 {
                    completion(false, "Yetkilendirme hatası (401): Kullanıcı adı veya WebDAV şifresi hatalı.")
                } else if httpResponse.statusCode == 404 {
                    completion(false, "404 Bulunamadı: Lütfen WebDAV yolunu kontrol edin (Cloudreve için genellikle /dav eklenmelidir).")
                } else {
                    completion(false, "Sunucu yanıt kodu: \(httpResponse.statusCode)")
                }
            }
        }
        task.resume()
    }
    
    /// Belirtilen klasördeki dosyaları ve alt klasörleri listeler
    public func listFiles(at relativePath: String = "", completion: @escaping (Result<[RemoteFileItem], Error>) -> Void) {
        var baseURLString = config.serverURL
        if !baseURLString.hasSuffix("/") { baseURLString += "/" }
        
        var cleanPath = relativePath
        if cleanPath.hasPrefix("/") { cleanPath = String(cleanPath.dropFirst()) }
        
        guard let targetURL = URL(string: baseURLString + cleanPath) else {
            completion(.failure(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz URL"])))
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
    
    /// Dosya İndirir
    public func downloadFile(href: String, to localDestination: URL, progress: @escaping (Double) -> Void, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: href, relativeTo: URL(string: config.serverURL))?.absoluteURL else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz dosya adresi"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        let downloadTask = session.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(NSError(domain: "HDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "İndirme dosyası bulunamadı"])) }
                return
            }
            
            do {
                try? FileManager.default.removeItem(at: localDestination)
                try FileManager.default.moveItem(at: tempURL, to: localDestination)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
        downloadTask.resume()
    }
    
    /// Dosya Yükler (PUT)
    public func uploadFile(localFileURL: URL, toRemotePath: String, completion: @escaping (Error?) -> Void) {
        var baseURLString = config.serverURL
        if !baseURLString.hasSuffix("/") { baseURLString += "/" }
        
        var cleanPath = toRemotePath
        if cleanPath.hasPrefix("/") { cleanPath = String(cleanPath.dropFirst()) }
        
        guard let targetURL = URL(string: baseURLString + cleanPath) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz hedef adresi"]))
            return
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "PUT"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
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
    
    /// Klasör Oluşturur (MKCOL)
    public func createFolder(at remotePath: String, completion: @escaping (Error?) -> Void) {
        var baseURLString = config.serverURL
        if !baseURLString.hasSuffix("/") { baseURLString += "/" }
        let cleanPath = remotePath.hasPrefix("/") ? String(remotePath.dropFirst()) : remotePath
        
        guard let targetURL = URL(string: baseURLString + cleanPath) else { return }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "MKCOL"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        
        session.dataTask(with: request) { _, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(error) }
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            DispatchQueue.main.async {
                if status == 201 || status == 200 { completion(nil) }
                else { completion(NSError(domain: "HDrive", code: status, userInfo: [NSLocalizedDescriptionKey: "Klasör oluşturulamadı: \(status)"])) }
            }
        }.resume()
    }
    
    /// Dosya/Klasör Siler (DELETE)
    public func delete(at remotePath: String, isDirectory: Bool = false, completion: @escaping (Error?) -> Void) {
        var path = remotePath
        if isDirectory && !path.hasSuffix("/") {
            path += "/"
        }
        
        var cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let baseURL = URL(string: config.serverURL) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz sunucu adresi"]))
            return
        }
        
        let basePath = (baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        if !basePath.isEmpty {
            if cleanPath == basePath {
                cleanPath = ""
            } else if cleanPath.hasPrefix(basePath + "/") {
                cleanPath = String(cleanPath.dropFirst(basePath.count + 1))
            }
        }
        
        var baseURLString = config.serverURL
        if !baseURLString.hasSuffix("/") { baseURLString += "/" }
        
        let encodedSegments = cleanPath.components(separatedBy: "/").map { segment in
            let unescaped = segment.removingPercentEncoding ?? segment
            return unescaped.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? unescaped
        }
        let fullPath = encodedSegments.joined(separator: "/")
        let hasTrailingSlash = path.hasSuffix("/")
        
        guard let targetURL = URL(string: baseURLString + fullPath + (hasTrailingSlash ? "/" : "")) else {
            completion(NSError(domain: "HDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz silme adresi"]))
            return
        }
        
        var request = URLRequest(url: targetURL)
        request.httpMethod = "DELETE"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
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
        var baseURLString = config.serverURL
        if !baseURLString.hasSuffix("/") { baseURLString += "/" }
        let cleanSource = sourcePath.hasPrefix("/") ? String(sourcePath.dropFirst()) : sourcePath
        let cleanDest = destinationPath.hasPrefix("/") ? String(destinationPath.dropFirst()) : destinationPath
        
        let encSource = cleanSource.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanSource
        let encDest = cleanDest.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanDest
        
        guard let sourceURL = URL(string: baseURLString + encSource),
              let destURL = URL(string: baseURLString + encDest) else {
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
