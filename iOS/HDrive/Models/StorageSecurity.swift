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
