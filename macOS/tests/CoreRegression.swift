import Foundation

@main
struct CoreRegression {
    static func main() async {
        do { try await run() }
        catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hdrive-apple-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !condition() { throw NSError(domain: "HDrive.Test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let share = root.appendingPathComponent("share")
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: share.appendingPathComponent("escape"), withDestinationURL: root)
        for path in ["/..", "/../outside.txt", "/%2e%2e/outside.txt", "/escape/outside.txt"] {
            try require(SafeFileStorage.resolve(root: share, path: path) == nil, "Share path escaped: \(path)")
        }
        try require(SafeFileStorage.resolve(root: share, path: "/safe.txt")?.path == share.appendingPathComponent("safe.txt").path, "Valid share path rejected")
        print("PASS: parent traversal, encoded paths and escaping symlinks are rejected")

        let handler = WebDAVHandler(rootDirectoryURL: share)
        ServerConfig.shared.requiresAuth = false
        ServerConfig.shared.allowWrite = false
        let source = share.appendingPathComponent("source.txt"), destination = share.appendingPathComponent("destination.txt")
        try Data("source".utf8).write(to: source); try Data("original".utf8).write(to: destination)
        let copy = handler.handle(request: HTTPRequest(rawText: "COPY /source.txt HTTP/1.1\r\nDestination: /destination.txt\r\n\r\n"))
        try require(copy.statusCode == 403, "COPY bypassed read-only permission")
        try require(try String(contentsOf: destination, encoding: .utf8) == "original", "Read-only COPY changed destination")
        ServerConfig.shared.allowWrite = true
        for method in ["GET", "PUT", "DELETE", "PROPFIND"] {
            let response = handler.handle(request: HTTPRequest(rawText: "\(method) /%252e%252e/outside.txt HTTP/1.1\r\n\r\n"))
            try require(response.statusCode == 403, "HTTP parser traversal bypass: \(method)")
        }
        print("PASS: real WebDAV handler enforces containment and read-only COPY")

        let temporary = root.appendingPathComponent("response.txt")
        try Data("http-error-page".utf8).write(to: temporary)
        let rejected = HTTPURLResponse(url: URL(string: "https://storage.example/file")!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        var refused = false
        do { try SafeFileStorage.install(download: temporary, destination: destination, response: rejected) }
        catch { refused = true }
        try require(refused && (try String(contentsOf: destination, encoding: .utf8)) == "original", "HTTP error replaced a real file")
        let accepted = HTTPURLResponse(url: rejected.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try Data("new-content".utf8).write(to: temporary)
        try SafeFileStorage.install(download: temporary, destination: destination, response: accepted)
        try require(try String(contentsOf: destination, encoding: .utf8) == "new-content", "Successful download was not installed")
        print("PASS: HTTP failures preserve existing files; successful replacement is staged")

        let session = OAuthSession(), other = OAuthSession()
        try require(session.matches(session.state) && !session.matches(other.state) && !session.matches(nil), "OAuth state validation failed")
        try require((43...128).contains(session.verifier.count) && session.challenge.count == 43, "PKCE parameters invalid")
        print("PASS: OAuth state isolation and PKCE generation")

        let suite = "HDrive.Test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var vault = [String: String]()
        var failWrites = false
        func manager() -> CloudreveManager {
            CloudreveManager(defaults: defaults, saveSecret: { key, value in
                if failWrites { return false }; vault[key] = value; return true
            }, readSecret: { vault[$0] }, deleteSecret: { vault.removeValue(forKey: $0); return true })
        }
        var account = CloudreveServerConfig(name: "Fixture", serverURL: "https://storage.example", password: "secret", clientSecret: "client-secret", refreshToken: "refresh-secret")
        let first = manager()
        try require(first.saveServer(account), "Account save failed")
        let bytes = defaults.data(forKey: "HDrive_SavedCloudreveServers")!
        let saved = String(data: bytes, encoding: .utf8)!
        try require(!saved.contains("refresh-secret") && !saved.contains("client-secret") && !saved.contains("\"secret\""), "Secrets persisted in defaults")
        first.disconnectServer(first.servers[0])
        let restored = manager()
        try require(restored.activeServer == nil && !restored.servers[0].isConnected, "Disconnected account was reactivated")
        try require(restored.servers[0].refreshToken == "refresh-secret", "Secure refresh token not restored")
        let previous = defaults.data(forKey: "HDrive_SavedCloudreveServers")
        failWrites = true
        account.password = "new-secret"
        try require(!restored.saveServer(account) && defaults.data(forKey: "HDrive_SavedCloudreveServers") == previous, "Vault failure overwrote account file")
        print("PASS: secure account persistence, restart state and vault failure recovery")
        failWrites = false
        restored.connectServer(restored.servers[0])
        var refreshed = restored.servers[0]
        refreshed.password = "rotated-access"
        var second = account
        second.id = UUID()
        try require(restored.saveServer(second), "Second account save failed")
        try require(restored.updateCredentials(refreshed) && restored.activeServer?.id == second.id, "Token refresh changed active account")
        var edited = refreshed
        edited.serverURL = "https://another-storage.example"
        try require(restored.saveServer(edited), "Edited account save failed")
        refreshed.password = "stale-access"
        try require(!restored.updateCredentials(refreshed) && vault[refreshed.id.uuidString] == "rotated-access", "Stale token overwrote an edited account")
        print("PASS: credential refresh preserves account ownership and rejects stale owners")

        var pageCalls = 0
        let google = URL(string: "https://www.googleapis.com/drive/v3/files?fields=nextPageToken,files(id)")!
        let pages = try await CloudPageLoader.fetch(initial: google, provider: .google) { request in
            pageCalls += 1
            let json = pageCalls == 1 ? "{\"files\":[{\"id\":\"one\"}],\"nextPageToken\":\"next\"}" : "{\"files\":[{\"id\":\"two\"}]}"
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        try require(pages.count == 2 && pageCalls == 2, "Google pagination incomplete")
        pageCalls = 0
        let graph = URL(string: "https://graph.microsoft.com/v1.0/me/drive/root/children")!
        var blocked = false
        do {
            _ = try await CloudPageLoader.fetch(initial: graph, provider: .oneDrive) { request in
                pageCalls += 1
                return (Data("{\"value\":[],\"@odata.nextLink\":\"https://attacker.example/steal\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        } catch { blocked = true }
        try require(blocked && pageCalls == 1, "Foreign pagination URL received credentials")
        print("PASS: paginated cloud listing and foreign-host rejection")

        let stamp = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        var request = URLRequest(url: URL(string: "https://s3.example/bucket/file.txt")!)
        request.httpMethod = "GET"
        let signed = try S3Signing.sign(request, accessKey: "access", secretKey: "secret", region: "us-east-1", now: stamp)
        try require(signed.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 Credential=access/20260101/us-east-1/s3/aws4_request") == true, "S3 signature missing")
        try require(signed.value(forHTTPHeaderField: "x-amz-date") == "20260101T000000Z", "S3 timestamp incorrect")
        print("PASS: deterministic S3 signing")
        var s3Config = CloudreveServerConfig(name: "S3 Fixture", serverURL: "https://s3.example", username: "access", password: "secret", storageProtocol: .s3, bucketName: "bucket")
        s3Config.region = "us-east-1"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let http = URLSession(configuration: configuration)
        defer { http.invalidateAndCancel() }
        var s3Calls = 0
        FixtureURLProtocol.handler = { request in
            s3Calls += 1
            guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256") == true,
                  request.url!.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "bucket", request.url!.query?.contains("list-type=2") == true else { throw URLError(.badURL) }
            let xml = s3Calls == 1
                ? "<ListBucketResult><Contents><Key>a.txt</Key><Size>1</Size></Contents><CommonPrefixes><Prefix>folder/</Prefix></CommonPrefixes><NextContinuationToken>next</NextContinuationToken></ListBucketResult>"
                : "<ListBucketResult><Contents><Key>b.txt</Key><Size>2</Size></Contents></ListBucketResult>"
            return (200, Data(xml.utf8))
        }
        let s3 = S3Storage(config: s3Config, session: http)
        let entries = try await s3.list("")
        try require(entries.count == 3 && entries.contains { $0.key == "folder/" && $0.isDirectory } && s3Calls == 2, "S3 listing or pagination incomplete")
        FixtureURLProtocol.handler = { _ in (403, Data("denied".utf8)) }
        var s3Denied = false
        do { _ = try await s3.list("") } catch { s3Denied = true }
        try require(s3Denied, "S3 access denied reported as success")
        print("PASS: signed S3 XML listing, continuation and access-denied handling")
        print("All Apple core regression checks passed.")
    }
}

private final class FixtureURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(data.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
