import Foundation

public struct S3Entry {
    public var key: String
    public var size: Int64 = 0
    public var modified: Date? = nil
    public var isDirectory: Bool = false
}

public final class S3Storage {
    private let config: CloudreveServerConfig
    private let session: URLSession
    public init(config: CloudreveServerConfig, session: URLSession = .shared) { self.config = config; self.session = session }

    private func bucketURL() throws -> URL {
        guard var parts = URLComponents(string: config.serverURL), let host = parts.host,
              parts.scheme == "https" || parts.scheme == "http", !config.bucketName.isEmpty else { throw URLError(.badURL) }
        if !host.hasPrefix(config.bucketName + ".") && parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").last != config.bucketName {
            parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + config.bucketName
        }
        if !parts.path.hasPrefix("/") { parts.path = "/" + parts.path }
        if !parts.path.hasSuffix("/") { parts.path += "/" }
        parts.query = nil
        guard let url = parts.url else { throw URLError(.badURL) }
        return url
    }

    public func request(method: String, key: String = "", query: [URLQueryItem] = [], headers: [String: String] = [:]) throws -> URLRequest {
        let bucket = try bucketURL()
        var parts = URLComponents(url: bucket, resolvingAgainstBaseURL: false)!
        parts.percentEncodedPath += key.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/", omittingEmptySubsequences: false).map { OAuthSession.encode(String($0)) }.joined(separator: "/")
        if key.hasSuffix("/") && !parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath += "/" }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return try S3Signing.sign(request, accessKey: config.username, secretKey: config.password, region: config.region)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "HDrive.S3", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: "S3 erişimi başarısız: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"])
        }
    }

    private func entries(prefix: String, delimiter: String?) async throws -> [S3Entry] {
        var token: String?
        var seen = Set<String>()
        var result: [S3Entry] = []
        repeat {
            var query = [URLQueryItem(name: "list-type", value: "2"), URLQueryItem(name: "prefix", value: prefix)]
            if let delimiter = delimiter { query.append(URLQueryItem(name: "delimiter", value: delimiter)) }
            if let token = token { query.append(URLQueryItem(name: "continuation-token", value: token)) }
            let (data, response) = try await session.data(for: request(method: "GET", query: query))
            try check(response)
            let parser = S3ListParser()
            try parser.parse(data)
            result.append(contentsOf: parser.entries)
            token = parser.nextToken
            if let token = token, !seen.insert(token).inserted { throw URLError(.cannotParseResponse) }
        } while token != nil
        return result
    }

    public func list(_ path: String) async throws -> [S3Entry] {
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = path.isEmpty ? "" : path + "/"
        return try await entries(prefix: prefix, delimiter: "/").filter { $0.key != prefix }
    }

    public func download(_ key: String, to destination: URL) async throws {
        let (temporary, response) = try await session.download(for: request(method: "GET", key: key))
        try SafeFileStorage.install(download: temporary, destination: destination, response: response)
    }

    public func upload(_ source: URL, key: String) async throws {
        let (_, response) = try await session.upload(for: request(method: "PUT", key: key), fromFile: source)
        try check(response)
    }

    public func createFolder(_ path: String) async throws {
        var request = try request(method: "PUT", key: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/")
        request.httpBody = Data()
        let (_, response) = try await session.data(for: request)
        try check(response)
    }

    public func delete(_ path: String, isDirectory: Bool) async throws {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty else { throw URLError(.noPermissionsToReadFile) }
        let keys = isDirectory ? try await entries(prefix: clean + "/", delimiter: nil).map { $0.key } + [clean + "/"] : [clean]
        for key in Set(keys) {
            let (_, response) = try await session.data(for: request(method: "DELETE", key: key))
            if (response as? HTTPURLResponse)?.statusCode != 404 { try check(response) }
        }
    }

    public func copy(_ source: String, to destination: String, overwrite: Bool) async throws {
        if source.hasSuffix("/") {
            let target = destination.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
            guard target != source, !target.hasPrefix(source) else { throw URLError(.noPermissionsToReadFile) }
            if !overwrite, !(try await list(target)).isEmpty { throw CocoaError(.fileWriteFileExists) }
            let objects = try await entries(prefix: source, delimiter: nil)
            try await createFolder(target)
            for object in objects {
                let newKey = target + String(object.key.dropFirst(source.count))
                if object.isDirectory { try await createFolder(newKey) }
                else { try await copy(object.key, to: newKey, overwrite: overwrite) }
            }
            return
        }
        if !overwrite {
            let (_, response) = try await session.data(for: request(method: "HEAD", key: destination))
            guard (response as? HTTPURLResponse)?.statusCode == 404 else {
                try check(response)
                throw CocoaError(.fileWriteFileExists)
            }
        }
        let copySource = "/" + OAuthSession.encode(config.bucketName) + "/" + source.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").map { OAuthSession.encode(String($0)) }.joined(separator: "/")
        let (data, response) = try await session.data(for: request(method: "PUT", key: destination, headers: ["x-amz-copy-source": copySource]))
        try check(response)
        if String(data: data, encoding: .utf8)?.contains("<Error") == true { throw URLError(.cannotWriteToFile) }
    }

    public func move(_ source: String, to destination: String, overwrite: Bool) async throws {
        if source.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == destination.trimmingCharacters(in: CharacterSet(charactersIn: "/")) { return }
        try await copy(source, to: destination, overwrite: overwrite)
        try await delete(source, isDirectory: source.hasSuffix("/"))
    }

}

private final class S3ListParser: NSObject, XMLParserDelegate {
    var entries: [S3Entry] = []
    var nextToken: String?
    private var stack: [String] = []
    private var text = ""
    private var entry: S3Entry?
    func parse(_ data: Data) throws {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(name); text = ""
        if name == "Contents" || name == "CommonPrefixes" { entry = S3Entry(key: "", isDirectory: name == "CommonPrefixes") }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if entry != nil {
            if name == "Key" || (name == "Prefix" && stack.dropLast().last == "CommonPrefixes") { entry?.key = text }
            if name == "Size" { entry?.size = Int64(text) ?? 0 }
            if name == "LastModified" { entry?.modified = ISO8601DateFormatter().date(from: text) }
            if name == "Contents" || name == "CommonPrefixes" {
                if var entry = entry, !entry.key.isEmpty { entry.isDirectory = entry.isDirectory || entry.key.hasSuffix("/"); entries.append(entry) }
                entry = nil
            }
        }
        if name == "NextContinuationToken", !text.isEmpty { nextToken = text }
        _ = stack.popLast(); text = ""
    }
}
