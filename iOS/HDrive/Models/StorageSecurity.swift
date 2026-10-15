import Foundation
import CryptoKit

public struct OAuthSession {
    public let state: String
    public let verifier: String
    public var challenge: String { Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    public var query: String { "state=\(state)&code_challenge=\(challenge)&code_challenge_method=S256" }
    public init() {
        state = Self.base64URL(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
        verifier = Self.base64URL(Data((0..<64).map { _ in UInt8.random(in: 0...255) }))
    }
    public func matches(_ candidate: String?) -> Bool {
        guard let candidate = candidate else { return false }
        let expected = Array(state.utf8), actual = Array(candidate.utf8)
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? ""
    }
}

public enum SafeFileStorage {
    public static func resolve(root: URL, path: String) -> URL? {
        guard let decoded = path.removingPercentEncoding,
              !decoded.contains("\0"), !decoded.contains("\\") else { return nil }
        let parts = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.contains("..") else { return nil }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = parts.reduce(canonicalRoot) { $0.appendingPathComponent(String($1)) }
            .standardizedFileURL.resolvingSymlinksInPath()
        return result.path == canonicalRoot.path || result.path.hasPrefix(canonicalRoot.path + "/") ? result : nil
    }

    public static func install(download: URL, destination: URL, response: URLResponse?) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "HDrive.Transfer", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: "İndirme tamamlanmadı; mevcut dosya korundu."])
        }
        try installFile(source: download, destination: destination)
    }

    public static func installFile(source: URL, destination: URL) throws {
        let manager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".hdrive-" + UUID().uuidString)
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: source, to: staging)
        if manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
    }
}

public enum CloudPageLoader {
    public enum Provider { case google, oneDrive }
    public static func fetch(initial: URL, provider: Provider,
                             requestData: (URLRequest) async throws -> (Data, URLResponse)) async throws -> [[String: Any]] {
        var page: URL? = initial
        var seen = Set<String>()
        var result: [[String: Any]] = []
        while let url = page {
            guard url.scheme == "https", url.host == initial.host, url.port == initial.port,
                  seen.insert(url.absoluteString).inserted else {
                throw NSError(domain: "HDrive.Pagination", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçersiz sayfalama bağlantısı."])
            }
            let (data, response) = try await requestData(URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "HDrive.Pagination", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                              userInfo: [NSLocalizedDescriptionKey: "Bulut klasörü alınamadı."])
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = json[provider == .google ? "files" : "value"] as? [[String: Any]] else {
                throw NSError(domain: "HDrive.Pagination", code: 500, userInfo: [NSLocalizedDescriptionKey: "Geçersiz bulut yanıtı."])
            }
            result.append(contentsOf: rows)
            if provider == .google, let token = json["nextPageToken"] as? String, !token.isEmpty {
                var components = URLComponents(url: initial, resolvingAgainstBaseURL: false)!
                components.queryItems = (components.queryItems ?? []).filter { $0.name != "pageToken" } + [URLQueryItem(name: "pageToken", value: token)]
                page = components.url
            } else if provider == .oneDrive, let link = json["@odata.nextLink"] as? String, !link.isEmpty {
                guard let next = URL(string: link) else { throw URLError(.badURL) }
                page = next
            } else { page = nil }
        }
        return result
    }
}

public enum S3Signing {
    public static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func hmac(_ key: Data, _ text: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key)))
    }
    public static func sign(_ input: URLRequest, accessKey: String, secretKey: String,
                            region: String, now: Date = Date()) throws -> URLRequest {
        guard let url = input.url, let host = url.host, !accessKey.isEmpty, !secretKey.isEmpty else {
            throw NSError(domain: "HDrive.S3", code: 400, userInfo: [NSLocalizedDescriptionKey: "S3 Access Key ve Secret Key gereklidir."])
        }
        var request = input
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = formatter.string(from: now), date = String(stamp.prefix(8))
        let payload = request.httpBody == nil && request.httpMethod != "PUT" ? hash("") : "UNSIGNED-PAYLOAD"
        request.setValue(url.port.map { "\(host):\($0)" } ?? host, forHTTPHeaderField: "Host")
        request.setValue(stamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(payload, forHTTPHeaderField: "x-amz-content-sha256")
        let headers = (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.0 == "host" || $0.0.hasPrefix("x-amz-") }.sorted { $0.0 < $1.0 }
        let signed = headers.map { $0.0 }.joined(separator: ";")
        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = (components.queryItems ?? []).map { OAuthSession.encode($0.name) + "=" + OAuthSession.encode($0.value ?? "") }.sorted().joined(separator: "&")
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        let canonical = "\(request.httpMethod ?? "GET")\n\(path)\n\(query)\n\(canonicalHeaders)\n\(signed)\n\(payload)"
        let scope = "\(date)/\(region.isEmpty ? "us-east-1" : region)/s3/aws4_request"
        let toSign = "AWS4-HMAC-SHA256\n\(stamp)\n\(scope)\n\(hash(canonical))"
        let key = hmac(hmac(hmac(hmac(Data(("AWS4" + secretKey).utf8), date), region.isEmpty ? "us-east-1" : region), "s3"), "aws4_request")
        let signature = hmac(key, toSign).map { String(format: "%02x", $0) }.joined()
        request.setValue("AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signed), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        return request
    }
}

public enum FileCollisionPolicy { case fail, replace, keepBoth, skip }

public enum LocalFileOperations {
    public struct TrashEntry: Codable, Identifiable {
        public var id: UUID
        public var originalPath: String
        public var deletedAt: Date
        public var name: String { URL(fileURLWithPath: originalPath).lastPathComponent }
    }
    public static func validName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
            throw NSError(domain: "HDrive.Files", code: 400, userInfo: [NSLocalizedDescriptionKey: "Geçerli bir dosya veya klasör adı girin."])
        }
        return name
    }
    public static func availableURL(_ target: URL) -> URL {
        let manager = FileManager.default
        if !manager.fileExists(atPath: target.path) { return target }
        let ext = target.pathExtension
        let stem = ext.isEmpty ? target.lastPathComponent : target.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = "\(stem) (\(number))" + (ext.isEmpty ? "" : "." + ext)
            let candidate = target.deletingLastPathComponent().appendingPathComponent(name)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
    @discardableResult public static func importFile(_ source: URL, into directory: URL, policy: FileCollisionPolicy = .fail) throws -> URL? {
        let manager = FileManager.default
        let name = try validName(source.lastPathComponent)
        var target = directory.appendingPathComponent(name)
        if source.standardizedFileURL == target.standardizedFileURL { return target }
        if manager.fileExists(atPath: target.path) {
            switch policy {
            case .skip: return nil
            case .keepBoth: target = availableURL(target)
            case .fail: throw CocoaError(.fileWriteFileExists)
            case .replace: break
            }
        }
        try SafeFileStorage.installFile(source: source, destination: target)
        return target
    }
    public static var trashRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HDrive/Trash", isDirectory: true)
    }
    @discardableResult public static func trash(_ source: URL, root: URL = trashRoot) throws -> TrashEntry {
        let manager = FileManager.default
        let entry = TrashEntry(id: UUID(), originalPath: source.path, deletedAt: Date())
        let directory = root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent("entry.json"), options: .atomic)
            try manager.moveItem(at: source, to: directory.appendingPathComponent("content"))
        } catch { try? manager.removeItem(at: directory); throw error }
        return entry
    }
    public static func trashEntries(root: URL = trashRoot) throws -> [TrashEntry] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { directory in
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("content").path) else { return nil }
            return try JSONDecoder().decode(TrashEntry.self, from: Data(contentsOf: directory.appendingPathComponent("entry.json")))
        }.sorted { $0.deletedAt > $1.deletedAt }
    }
    @discardableResult public static func restore(_ entry: TrashEntry, root: URL = trashRoot) throws -> URL {
        let directory = root.appendingPathComponent(entry.id.uuidString)
        let destination = availableURL(URL(fileURLWithPath: entry.originalPath))
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory.appendingPathComponent("content"), to: destination)
        try FileManager.default.removeItem(at: directory)
        return destination
    }
}

public enum AppVersion {
    public static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Geliştirme"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

public enum OfflineStore {
    public struct Entry: Codable, Identifiable {
        public var id: String
        public var accountID: UUID
        public var accountName: String
        public var identity: String
        public var remotePath: String
        public var name: String
        public var savedAt: Date
        public var localPath: String
        public var localURL: URL { URL(fileURLWithPath: localPath) }
    }
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("HDrive/Offline", isDirectory: true)
    }
    public static func identity(_ config: CloudreveServerConfig) -> String {
        S3Signing.hash("\(config.id)|\(config.storageProtocol.rawValue)|\(config.serverURL)|\(config.username)|\(config.bucketName)|\(config.smbShare)")
    }
    public static func destination(config: CloudreveServerConfig, remotePath: String, name: String, root: URL = root) throws -> URL {
        let id = S3Signing.hash(identity(config) + "|" + remotePath)
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(try LocalFileOperations.validName(name))
        let entry = Entry(id: id, accountID: config.id, accountName: config.name, identity: identity(config), remotePath: remotePath, name: name, savedAt: Date(), localPath: destination.path)
        try JSONEncoder().encode(entry).write(to: directory.appendingPathComponent("entry.json"), options: .atomic)
        return destination
    }
    public static func entries(root: URL = root) throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { directory in
            let entry = try JSONDecoder().decode(Entry.self, from: Data(contentsOf: directory.appendingPathComponent("entry.json")))
            return FileManager.default.fileExists(atPath: entry.localPath) ? entry : nil
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public struct CloudFileVersion: Identifiable {
    public var id: String
    public var modified: String
    public var canRestore: Bool
}
public struct CloudTrashItem: Identifiable {
    public var id: String
    public var name: String
}

public struct TransferRecord: Codable {
    public var id: UUID
    public var accountID: UUID
    public var identity: String
    public var fileName: String
    public var remotePath: String
    public var localPath: String
    public var direction: String
    public var status: String
    public var totalBytes: Int64
}
public final class TransferJournal {
    private let url: URL
    private var failed = false
    private var previous: Data?
    public init(url: URL) { self.url = url }
    public func load() throws -> [TransferRecord] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) || manager.fileExists(atPath: url.path + ".bak") else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([TransferRecord].self, from: data)
        } catch {
            do { return try JSONDecoder().decode([TransferRecord].self, from: Data(contentsOf: URL(fileURLWithPath: url.path + ".bak"))) }
            catch { failed = true; throw error }
        }
    }
    public func save(_ records: [TransferRecord]) throws {
        guard !failed else { throw CocoaError(.fileReadCorruptFile) }
        let data = try JSONEncoder().encode(records)
        guard data != previous else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try data.write(to: URL(fileURLWithPath: url.path + ".bak"), options: .atomic)
        previous = data
    }
}

public enum WorkingCache {
    public struct Entry: Identifiable {
        public var url: URL
        public var bytes: Int64
        public var modified: Date
        public var protected: Bool
        public var id: String { url.path }
    }
    public static var roots: [URL] {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return [caches.appendingPathComponent("HDriveFiles"), caches.appendingPathComponent("HDrivePreviews"), FileManager.default.temporaryDirectory.appendingPathComponent("HDriveCache")]
    }
    public static func protect(_ url: URL) throws {
        try Data().write(to: url.deletingLastPathComponent().appendingPathComponent(".hdrive-protected"), options: .atomic)
    }
    public static func entries(roots: [URL] = roots) throws -> [Entry] {
        let manager = FileManager.default
        var result: [Entry] = []
        for originalRoot in roots {
            let root = originalRoot.standardizedFileURL.resolvingSymlinksInPath()
            guard let iterator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in iterator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, !url.lastPathComponent.hasSuffix(".part") else { continue }
                var parent = url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent(), protected = false
                while parent.path.hasPrefix(root.path) {
                    if manager.fileExists(atPath: parent.appendingPathComponent(".hdrive-protected").path) { protected = true; break }
                    if parent == root { break }; parent.deleteLastPathComponent()
                }
                result.append(Entry(url: url, bytes: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast, protected: protected))
            }
        }
        return result
    }
    @discardableResult public static func trim(to limit: Int64, roots: [URL] = roots) throws -> Int64 {
        let files = try entries(roots: roots)
        var total = files.reduce(Int64(0)) { $0 + $1.bytes }, removed: Int64 = 0
        for file in files.filter({ !$0.protected }).sorted(by: { $0.modified < $1.modified }) where total > limit {
            try FileManager.default.removeItem(at: file.url)
            total -= file.bytes; removed += file.bytes
        }
        return removed
    }
}

public enum L10n {
    private static let translations: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in ["tr", "en"] {
            if let url = Bundle.main.url(forResource: language, withExtension: "json", subdirectory: "Localization"),
               let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([String: String].self, from: data) { result[language] = entries }
        }
        return result
    }()
    public static func text(_ key: String) -> String {
        let preferred = UserDefaults.standard.string(forKey: "HDriveLanguage") ?? "system"
        let language = preferred == "system" ? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en") : preferred
        return translations[language]?[key] ?? key
    }
}
