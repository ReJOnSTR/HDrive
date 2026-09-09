//
//  WebDAVHandler.swift
//  HDrive
//

import Foundation
import UniformTypeIdentifiers

public struct HTTPRequest {
    public var method: String
    public var uri: String
    public var path: String
    public var queryParams: [String: String] = [:]
    public var headers: [String: String] = [:]
    public var body: Data = Data()
    
    public init(rawText: String, bodyData: Data = Data()) {
        self.body = bodyData
        let lines = rawText.components(separatedBy: "\r\n")
        let firstLine = lines.first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        self.method = parts.count > 0 ? parts[0].uppercased() : "GET"
        self.uri = parts.count > 1 ? parts[1] : "/"
        
        // Path ve Query Parse
        if let urlComponents = URLComponents(string: self.uri) {
            self.path = urlComponents.path
            if let items = urlComponents.queryItems {
                for item in items {
                    self.queryParams[item.name] = item.value ?? ""
                }
            }
        } else {
            self.path = self.uri
        }
        
        // Headers Parse (küçük harfe normalize ederek)
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
                self.headers[key] = value
            }
        }
    }
}

public struct HTTPResponse {
    public var statusCode: Int
    public var statusMessage: String
    public var headers: [String: String] = [:]
    public var body: Data = Data()
    
    public init(statusCode: Int = 200, statusMessage: String = "OK", headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.headers = headers
        self.body = body
    }
    
    public func toData() -> Data {
        var headerString = "HTTP/1.1 \(statusCode) \(statusMessage)\r\n"
        var finalHeaders = headers
        if finalHeaders["Content-Length"] == nil && !body.isEmpty {
            finalHeaders["Content-Length"] = "\(body.count)"
        }
        finalHeaders["Server"] = "HDrive-WebDAV/1.0 (iOS)"
        finalHeaders["Connection"] = "keep-alive"
        
        for (key, value) in finalHeaders {
            headerString += "\(key): \(value)\r\n"
        }
        headerString += "\r\n"
        
        var fullData = headerString.data(using: .utf8) ?? Data()
        fullData.append(body)
        return fullData
    }
}

public final class WebDAVHandler {
    public let rootDirectoryURL: URL
    private let rfc1123DateFormatter: DateFormatter
    private let iso8601DateFormatter: ISO8601DateFormatter
    
    public init(rootDirectoryURL: URL? = nil) {
        if let root = rootDirectoryURL {
            self.rootDirectoryURL = root
        } else {
            let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let hdriveDir = docDir.appendingPathComponent("HDriveFiles", isDirectory: true)
            try? FileManager.default.createDirectory(at: hdriveDir, withIntermediateDirectories: true)
            self.rootDirectoryURL = hdriveDir
        }
        
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        self.rfc1123DateFormatter = df
        
        self.iso8601DateFormatter = ISO8601DateFormatter()
    }
    
    // MARK: - İstek Yönlendirme (Dispatch)
    public func handle(request: HTTPRequest) -> HTTPResponse {
        let method = request.method
        
        // Kimlik doğrulama kontrolü (Aktif ise)
        if ServerConfig.shared.requiresAuth {
            if !authenticate(request: request) {
                return HTTPResponse(
                    statusCode: 401,
                    statusMessage: "Unauthorized",
                    headers: [
                        "WWW-Authenticate": "Basic realm=\"HDrive\"",
                        "Content-Type": "text/plain; charset=utf-8"
                    ],
                    body: "401 Yetkisiz Erişim. Lütfen kullanıcı adı ve şifrenizi girin.".data(using: .utf8)!
                )
            }
        }
        
        switch method {
        case "OPTIONS":
            return handleOptions(request: request)
        case "PROPFIND":
            return handlePropfind(request: request)
        case "PROPPATCH":
            return handleProppatch(request: request)
        case "GET", "HEAD":
            return handleGetOrHead(request: request)
        case "PUT":
            return handlePut(request: request)
        case "MKCOL":
            return handleMkcol(request: request)
        case "DELETE":
            return handleDelete(request: request)
        case "MOVE":
            return handleMove(request: request)
        case "COPY":
            return handleCopy(request: request)
        case "LOCK":
            return handleLock(request: request)
        case "UNLOCK":
            return handleUnlock(request: request)
        default:
            return HTTPResponse(statusCode: 405, statusMessage: "Method Not Allowed")
        }
    }
    
    // MARK: - Basic Auth
    private func authenticate(request: HTTPRequest) -> Bool {
        guard let authHeader = request.headers["authorization"] else { return false }
        let components = authHeader.components(separatedBy: " ")
        guard components.count == 2, components[0].lowercased() == "basic" else { return false }
        guard let decodedData = Data(base64Encoded: components[1]),
              let decodedString = String(data: decodedData, encoding: .utf8) else { return false }
        let parts = decodedString.components(separatedBy: ":")
        guard parts.count >= 2 else { return false }
        let user = parts[0]
        let pass = parts.dropFirst().joined(separator: ":")
        return user == ServerConfig.shared.username && pass == ServerConfig.shared.password
    }
    
    // MARK: - WebDAV: OPTIONS
    private func handleOptions(request: HTTPRequest) -> HTTPResponse {
        var headers: [String: String] = [:]
        headers["DAV"] = "1, 2"
        headers["MS-Author-Via"] = "DAV"
        headers["Allow"] = "OPTIONS, GET, HEAD, POST, PUT, DELETE, TRACE, PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK"
        headers["Accept-Ranges"] = "bytes"
        headers["Content-Length"] = "0"
        return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: headers)
    }
    
    // MARK: - WebDAV: PROPFIND (Windows & Mac Klasör Listeleme Çekirdeği)
    private func handlePropfind(request: HTTPRequest) -> HTTPResponse {
        let localURL = resolveLocalURL(for: request.path)
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            return HTTPResponse(statusCode: 404, statusMessage: "Not Found")
        }
        
        let depth = request.headers["depth"] ?? "1"
        var items: [URL] = [localURL]
        
        if isDir.boolValue && depth != "0" {
            if let children = try? FileManager.default.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey
            ], options: [.skipsHiddenFiles]) {
                items.append(contentsOf: children)
            }
        }
        
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>\n"
        xml += "<D:multistatus xmlns:D=\"DAV:\">\n"
        
        for item in items {
            let isCurrentItemDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let createDate = (try? item.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            
            // WebDAV href path'i üretme
            let relativePath: String
            if item == rootDirectoryURL {
                relativePath = "/"
            } else {
                let sub = item.path.replacingOccurrences(of: rootDirectoryURL.path, with: "")
                relativePath = sub.hasPrefix("/") ? sub : "/\(sub)"
            }
            
            var encodedHref = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
            if isCurrentItemDir && !encodedHref.hasSuffix("/") {
                encodedHref += "/"
            }
            
            let modDateString = rfc1123DateFormatter.string(from: modDate)
            let createDateString = iso8601DateFormatter.string(from: createDate)
            let mimeType = isCurrentItemDir ? "httpd/unix-directory" : (UTType(filenameExtension: item.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
            
            xml += "  <D:response>\n"
            xml += "    <D:href>\(encodedHref)</D:href>\n"
            xml += "    <D:propstat>\n"
            xml += "      <D:prop>\n"
            if isCurrentItemDir {
                xml += "        <D:resourcetype><D:collection/></D:resourcetype>\n"
            } else {
                xml += "        <D:resourcetype/>\n"
                xml += "        <D:getcontentlength>\(size)</D:getcontentlength>\n"
                xml += "        <D:getcontenttype>\(mimeType)</D:getcontenttype>\n"
            }
            xml += "        <D:getlastmodified>\(modDateString)</D:getlastmodified>\n"
            xml += "        <D:creationdate>\(createDateString)</D:creationdate>\n"
            xml += "        <D:displayname><![CDATA[\(item.lastPathComponent.isEmpty ? "HDrive" : item.lastPathComponent)]]></D:displayname>\n"
            xml += "        <D:supportedlock>\n"
            xml += "          <D:lockentry><D:lockscope><D:exclusive/></D:lockscope><D:locktype><D:write/></D:locktype></D:lockentry>\n"
            xml += "        </D:supportedlock>\n"
            xml += "      </D:prop>\n"
            xml += "      <D:status>HTTP/1.1 200 OK</D:status>\n"
            xml += "    </D:propstat>\n"
            xml += "  </D:response>\n"
        }
        
        xml += "</D:multistatus>\n"
        
        let xmlData = xml.data(using: .utf8) ?? Data()
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/xml; charset=utf-8"
        headers["Content-Length"] = "\(xmlData.count)"
        headers["DAV"] = "1, 2"
        
        return HTTPResponse(statusCode: 207, statusMessage: "Multi-Status", headers: headers, body: xmlData)
    }
    
    // MARK: - GET & HEAD & Web Dashboard
    private func handleGetOrHead(request: HTTPRequest) -> HTTPResponse {
        let path = request.path
        
        // 1. API: Dosya listesi (Web UI için JSON)
        if path == "/api/files" {
            return handleAPIFiles(request: request)
        }
        
        // 2. API: Sunucu ve Depolama İstatistikleri
        if path == "/api/stats" {
            return handleAPIStats(request: request)
        }
        
        // 3. Web Dashboard Statik Kaynakları (index.html, css, js)
        if path == "/" || path == "/index.html" {
            // Eğer tarayıcıdan geldiyse Web UI servis et
            let accept = request.headers["accept"] ?? ""
            if accept.contains("text/html") || request.headers["user-agent"]?.contains("Mozilla") == true {
                return serveEmbeddedWebAsset(path: "index.html", mime: "text/html; charset=utf-8")
            }
        }
        
        if path.hasPrefix("/css/") || path.hasPrefix("/js/") {
            let assetName = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let mime = path.hasSuffix(".css") ? "text/css" : "application/javascript"
            return serveEmbeddedWebAsset(path: assetName, mime: mime)
        }
        
        // 4. Fiziksel Dosya İndirme / Görüntüleme
        let localURL = resolveLocalURL(for: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDir) else {
            return HTTPResponse(statusCode: 404, statusMessage: "Not Found")
        }
        
        if isDir.boolValue {
            // Klasör ise Web Dashboard veya dizin listesi sun
            return serveEmbeddedWebAsset(path: "index.html", mime: "text/html; charset=utf-8")
        }
        
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: localURL.path),
              let fileSize = fileAttributes[.size] as? Int64 else {
            return HTTPResponse(statusCode: 500, statusMessage: "Internal Server Error")
        }
        
        let mimeType = UTType(filenameExtension: localURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        var headers: [String: String] = [
            "Accept-Ranges": "bytes",
            "Content-Type": mimeType
        ]
        
        // HTTP Range Desteği (Video ve ses akışı / kesintisiz indirme için)
        if let rangeHeader = request.headers["range"], rangeHeader.hasPrefix("bytes=") {
            let rangeSpec = String(rangeHeader.dropFirst(6))
            let parts = rangeSpec.components(separatedBy: "-")
            var start: Int64 = 0
            var end: Int64 = fileSize - 1
            
            if parts.count == 2 {
                if let s = Int64(parts[0]) { start = s }
                if let e = Int64(parts[1]), e >= start { end = min(e, fileSize - 1) }
            }
            
            let length = end - start + 1
            guard let fileHandle = try? FileHandle(forReadingFrom: localURL) else {
                return HTTPResponse(statusCode: 500, statusMessage: "File read error")
            }
            
            try? fileHandle.seek(toOffset: UInt64(start))
            let partialData = fileHandle.readData(ofLength: Int(length))
            try? fileHandle.close()
            
            headers["Content-Range"] = "bytes \(start)-\(end)/\(fileSize)"
            headers["Content-Length"] = "\(partialData.count)"
            
            return HTTPResponse(statusCode: 206, statusMessage: "Partial Content", headers: headers, body: request.method == "HEAD" ? Data() : partialData)
        }
        
        // Tam dosya
        headers["Content-Length"] = "\(fileSize)"
        var bodyData = Data()
        if request.method != "HEAD" {
            bodyData = (try? Data(contentsOf: localURL, options: .mappedIfSafe)) ?? Data()
        }
        return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: headers, body: bodyData)
    }
    
    // MARK: - WebDAV: PUT (Dosya Yükleme / Kaydetme)
    private func handlePut(request: HTTPRequest) -> HTTPResponse {
        guard ServerConfig.shared.allowWrite else {
            return HTTPResponse(statusCode: 403, statusMessage: "Forbidden - Read Only")
        }
        
        let localURL = resolveLocalURL(for: request.path)
        let parentURL = localURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        
        let fileExisted = FileManager.default.fileExists(atPath: localURL.path)
        
        do {
            try request.body.write(to: localURL)
            ServerConfig.shared.totalBytesReceived += Int64(request.body.count)
            return HTTPResponse(statusCode: fileExisted ? 204 : 201, statusMessage: fileExisted ? "No Content" : "Created")
        } catch {
            return HTTPResponse(statusCode: 500, statusMessage: "Write Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WebDAV: MKCOL (Klasör Oluşturma)
    private func handleMkcol(request: HTTPRequest) -> HTTPResponse {
        guard ServerConfig.shared.allowWrite else {
            return HTTPResponse(statusCode: 403, statusMessage: "Forbidden")
        }
        let localURL = resolveLocalURL(for: request.path)
        do {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            return HTTPResponse(statusCode: 201, statusMessage: "Created")
        } catch {
            return HTTPResponse(statusCode: 500, statusMessage: "Mkdir Error")
        }
    }
    
    // MARK: - WebDAV: DELETE (Dosya / Klasör Silme)
    private func handleDelete(request: HTTPRequest) -> HTTPResponse {
        guard ServerConfig.shared.allowWrite else {
            return HTTPResponse(statusCode: 403, statusMessage: "Forbidden")
        }
        let localURL = resolveLocalURL(for: request.path)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            return HTTPResponse(statusCode: 404, statusMessage: "Not Found")
        }
        
        do {
            try FileManager.default.removeItem(at: localURL)
            return HTTPResponse(statusCode: 204, statusMessage: "No Content")
        } catch {
            return HTTPResponse(statusCode: 500, statusMessage: "Delete Error")
        }
    }
    
    // MARK: - WebDAV: MOVE / RENAME
    private func handleMove(request: HTTPRequest) -> HTTPResponse {
        guard ServerConfig.shared.allowWrite else {
            return HTTPResponse(statusCode: 403, statusMessage: "Forbidden")
        }
        guard let destHeader = request.headers["destination"] else {
            return HTTPResponse(statusCode: 400, statusMessage: "Missing Destination Header")
        }
        
        let sourceURL = resolveLocalURL(for: request.path)
        guard let destParsed = URL(string: destHeader) else {
            return HTTPResponse(statusCode: 400, statusMessage: "Invalid Destination")
        }
        
        let destURL = resolveLocalURL(for: destParsed.path)
        let existed = FileManager.default.fileExists(atPath: destURL.path)
        
        if existed {
            try? FileManager.default.removeItem(at: destURL)
        }
        
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            return HTTPResponse(statusCode: existed ? 204 : 201, statusMessage: existed ? "No Content" : "Created")
        } catch {
            return HTTPResponse(statusCode: 500, statusMessage: "Move Error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WebDAV: COPY
    private func handleCopy(request: HTTPRequest) -> HTTPResponse {
        guard let destHeader = request.headers["destination"] else {
            return HTTPResponse(statusCode: 400, statusMessage: "Missing Destination Header")
        }
        let sourceURL = resolveLocalURL(for: request.path)
        guard let destParsed = URL(string: destHeader) else {
            return HTTPResponse(statusCode: 400, statusMessage: "Invalid Destination")
        }
        let destURL = resolveLocalURL(for: destParsed.path)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return HTTPResponse(statusCode: 201, statusMessage: "Created")
        } catch {
            return HTTPResponse(statusCode: 500, statusMessage: "Copy Error")
        }
    }
    
    // MARK: - WebDAV: LOCK (Windows Explorer Lock Desteği)
    private func handleLock(request: HTTPRequest) -> HTTPResponse {
        let lockToken = UUID().uuidString
        let xml = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:prop xmlns:D="DAV:">
          <D:lockdiscovery>
            <D:activelock>
              <D:locktype><D:write/></D:locktype>
              <D:lockscope><D:exclusive/></D:lockscope>
              <D:depth>Infinity</D:depth>
              <D:owner><D:href>HDrive</D:href></D:owner>
              <D:timeout>Second-3600</D:timeout>
              <D:locktoken><D:href>opaquelocktoken:\(lockToken)</D:href></D:locktoken>
              <D:lockroot><D:href>\(request.path)</D:href></D:lockroot>
            </D:activelock>
          </D:lockdiscovery>
        </D:prop>
        """
        let data = xml.data(using: .utf8) ?? Data()
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/xml; charset=utf-8"
        headers["Lock-Token"] = "<opaquelocktoken:\(lockToken)>"
        return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: headers, body: data)
    }
    
    private func handleUnlock(request: HTTPRequest) -> HTTPResponse {
        return HTTPResponse(statusCode: 204, statusMessage: "No Content")
    }
    
    private func handleProppatch(request: HTTPRequest) -> HTTPResponse {
        let xml = """
        <?xml version="1.0" encoding="utf-8" ?>
        <D:multistatus xmlns:D=\"DAV:\">
          <D:response>
            <D:href>\(request.path)</D:href>
            <D:propstat>
              <D:status>HTTP/1.1 200 OK</D:status>
            </D:propstat>
          </D:response>
        </D:multistatus>
        """
        let data = xml.data(using: .utf8) ?? Data()
        return HTTPResponse(statusCode: 207, statusMessage: "Multi-Status", headers: ["Content-Type": "application/xml; charset=utf-8"], body: data)
    }
    
    // MARK: - Web Dashboard JSON API'leri
    private func handleAPIFiles(request: HTTPRequest) -> HTTPResponse {
        let subPath = request.queryParams["path"] ?? "/"
        let targetURL = resolveLocalURL(for: subPath)
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
        ], options: [.skipsHiddenFiles]) else {
            return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: ["Content-Type": "application/json"], body: "[]".data(using: .utf8)!)
        }
        
        let fileItems = files.map { url -> [String: Any] in
            let item = FileItem(url: url)
            return [
                "name": item.name,
                "path": (subPath.hasSuffix("/") ? subPath : subPath + "/") + item.name,
                "isDirectory": item.isDirectory,
                "size": item.size,
                "formattedSize": item.formattedSize,
                "modificationDate": item.formattedDate,
                "category": item.category.rawValue,
                "mimeType": item.mimeType
            ]
        }
        
        let jsonData = (try? JSONSerialization.data(withJSONObject: fileItems, options: [.prettyPrinted])) ?? Data()
        return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: ["Content-Type": "application/json"], body: jsonData)
    }
    
    private func handleAPIStats(request: HTTPRequest) -> HTTPResponse {
        ServerConfig.shared.updateDiskSpace()
        let stats: [String: Any] = [
            "totalDiskSpace": ServerConfig.shared.totalDiskSpace,
            "freeDiskSpace": ServerConfig.shared.freeDiskSpace,
            "usedDiskSpace": ServerConfig.shared.usedDiskSpace,
            "port": ServerConfig.shared.port,
            "version": "1.0.0"
        ]
        let data = (try? JSONSerialization.data(withJSONObject: stats)) ?? Data()
        return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: ["Content-Type": "application/json"], body: data)
    }
    
    // MARK: - Dahili Web Kaynakları Servisi
    private func serveEmbeddedWebAsset(path: String, mime: String) -> HTTPResponse {
        // Bundle içindeki WebAssets klasöründen okuma
        let cleanedPath = path.replacingOccurrences(of: "../", with: "")
        
        // Önce Bundle kontrolü
        if let bundlePath = Bundle.main.path(forResource: cleanedPath, ofType: nil, inDirectory: "WebAssets"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundlePath)) {
            return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: ["Content-Type": mime], body: data)
        }
        
        // Geliştirme/Yedek fallback: Dahili statik string üretimi
        let fallbackBody = getEmbeddedDefaultWebUI(for: cleanedPath)
        return HTTPResponse(statusCode: 200, statusMessage: "OK", headers: ["Content-Type": mime], body: fallbackBody)
    }
    
    private func getEmbeddedDefaultWebUI(for path: String) -> Data {
        // Bundle henüz derlenmediyse veya bulunamadıysa çalışan acil durum Web Arayüzü
        if path.hasSuffix(".css") {
            return WebDashboardEmbeddedAssets.css.data(using: .utf8) ?? Data()
        } else if path.hasSuffix(".js") {
            return WebDashboardEmbeddedAssets.js.data(using: .utf8) ?? Data()
        } else {
            return WebDashboardEmbeddedAssets.html.data(using: .utf8) ?? Data()
        }
    }
    
    // MARK: - Güvenli Dosya Yolu Çözümleme (Path Traversal Koruması)
    public func resolveLocalURL(for webPath: String) -> URL {
        var clean = webPath.removingPercentEncoding ?? webPath
        if clean.hasPrefix("/") { clean = String(clean.dropFirst()) }
        
        // Güvenlik: ../ engelleme
        clean = clean.replacingOccurrences(of: "../", with: "")
        
        if clean.isEmpty {
            return rootDirectoryURL
        }
        return rootDirectoryURL.appendingPathComponent(clean)
    }
}
