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

        let imports = root.appendingPathComponent("imports")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let existing = imports.appendingPathComponent("response.txt")
        try Data("original-import".utf8).write(to: existing)
        let kept = try LocalFileOperations.importFile(temporary, into: imports, policy: .keepBoth)!
        try require(kept != existing && (try String(contentsOf: existing, encoding: .utf8)) == "original-import", "Keep-both replaced original")
        var importFailed = false
        do { try LocalFileOperations.importFile(root.appendingPathComponent("missing/response.txt"), into: imports, policy: .replace) }
        catch { importFailed = true }
        try require(importFailed && (try String(contentsOf: existing, encoding: .utf8)) == "original-import", "Failed import deleted existing file")
        let trashRoot = root.appendingPathComponent("trash")
        let trashed = try LocalFileOperations.trash(existing, root: trashRoot)
        try Data("new-local-file".utf8).write(to: existing)
        let recovered = try LocalFileOperations.restore(trashed, root: trashRoot)
        try require(recovered != existing && (try String(contentsOf: recovered, encoding: .utf8)) == "original-import", "Trash recovery overwrote a new file")
        print("PASS: import collision policies and trash restore preserve both file versions")
        let cacheRoot = root.appendingPathComponent("cache")
        let protectedDirectory = cacheRoot.appendingPathComponent("protected")
        try FileManager.default.createDirectory(at: protectedDirectory, withIntermediateDirectories: true)
        let protectedFile = protectedDirectory.appendingPathComponent("edit.txt")
        try Data("edited".utf8).write(to: protectedFile)
        try WorkingCache.protect(protectedFile)
        let preview = cacheRoot.appendingPathComponent("preview.txt")
        try Data("preview".utf8).write(to: preview)
        try WorkingCache.trim(to: 0, roots: [cacheRoot])
        try require(FileManager.default.fileExists(atPath: protectedFile.path) && !FileManager.default.fileExists(atPath: preview.path), "Cache trim removed protected edits")
        print("PASS: cache limits preserve protected working copies")
        let journalURL = root.appendingPathComponent("transfers.json")
        let journal = TransferJournal(url: journalURL)
        let queueRecord = TransferRecord(id: UUID(), accountID: account.id, identity: "identity-hash", fileName: "file", remotePath: "id", localPath: existing.path, direction: "download", status: "running", totalBytes: 100)
        _ = try journal.load()
        try journal.save([queueRecord])
        try Data("broken".utf8).write(to: journalURL)
        let recoveredQueue = try TransferJournal(url: journalURL).load()
        try require(recoveredQueue.count == 1 && recoveredQueue[0].id == queueRecord.id, "Transfer journal backup failed")
        print("PASS: credential-free transfer journal recovers its atomic backup")
        var actions = 0
        FixtureURLProtocol.handler = { request in
            actions += 1
            guard request.httpMethod == "GET" else { throw URLError(.noPermissionsToReadFile) }
            return (200, Data("{\"webViewLink\":\"https://drive.google.com/file/d/id/view\"}".utf8))
        }
        var googleConfig = account; googleConfig.storageProtocol = .googleDrive
        _ = try await WebDAVClient(config: googleConfig, session: http).readOnlyLink(href: "id")
        try require(actions == 1, "Reading a link modified public permissions")
        print("PASS: reading a cloud sharing link does not grant public access")

        let baseline = FolderSyncBaseline(localHash: "local", remoteStamp: "remote")
        try require(FolderSynchronizer.decide(local: "local", remote: "remote", previous: baseline) == .none, "Unchanged files transferred")
        try require(FolderSynchronizer.decide(local: "changed", remote: "remote", previous: baseline) == .upload, "Local change lost")
        try require(FolderSynchronizer.decide(local: "local", remote: "changed", previous: baseline) == .download, "Remote change lost")
        try require(FolderSynchronizer.decide(local: "changed", remote: "changed", previous: baseline) == .conflict, "Two-side changes overwritten")
        try require(FolderSynchronizer.decide(local: nil, remote: "remote", previous: baseline) == .conflict, "Deletion silently propagated")
        print("PASS: two-way sync planning preserves concurrent edits and requires deletion decisions")

        try require(CloudFileNaming.exportName("Budget", mime: "application/vnd.google-apps.spreadsheet") == "Budget.xlsx", "Offline native document name lost its export extension")
        try require(CloudFileNaming.exportName("Report.docx", mime: "application/vnd.google-apps.document") == "Report.docx", "Native export extension duplicated")
        func openingName(_ name: String, _ href: String, _ mime: String?, _ provider: StorageProtocol = .webdav) -> String {
            FileOpener.localFileName(for: RemoteFileItem(id: href, name: name, href: href, isDirectory: false,
                size: 0, modificationDate: nil, contentType: mime), storageProtocol: provider)
        }
        try require(openingName("Rapor", "/dav/Rapor%20son.pdf", nil) == "Rapor.pdf", "WebDAV display name lost its resource extension")
        try require(openingName("Rapor", "opaque-id", "application/pdf; charset=binary", .oneDrive) == "Rapor.pdf", "MIME extension was not restored")
        try require(openingName("Bütçe.2026", "id", "application/vnd.google-apps.spreadsheet", .googleDrive) == "Bütçe.2026.xlsx", "Dotted Google document title kept an unusable extension")
        try require(openingName("Rapor.pdf", "id", "application/vnd.google-apps.document", .googleDrive) == "Rapor.pdf", "Explicit PDF export changed")
        try require(openingName("Plan/2026\\Q1", "id", "application/vnd.google-apps.document", .googleDrive) == "Plan_2026_Q1.docx", "Cloud title escaped the local directory")
        try require(openingName("photo.JPG", "/photo.JPG", "image/jpeg") == "photo.JPG", "Existing extension was changed")
        try require(openingName("..", "id", nil, .oneDrive) == "download", "Invalid local filename was accepted")
        print("PASS: native opening preserves export types and repairs missing/unsafe filenames")
        let davConfig = CloudreveServerConfig(serverURL: "https://storage.example/dav", storageProtocol: .webdav)
        let davClient = WebDAVClient(config: davConfig, session: http)
        for (xmlTitle, expectedName, isFolder) in [
            ("FAZLA ÇALIŞMA", "FAZLA ÇALIŞMA", true),
            ("AD &#214;ZEL", "AD ÖZEL", true),
            ("İşe Giriş &amp; Sağlık.pdf", "İşe Giriş & Sağlık.pdf", false),
            ("<![CDATA[ÇAĞRI ÖZTÜRK]]>", "ÇAĞRI ÖZTÜRK", true),
            ("  İK  ÇALIŞMA  ", "  İK  ÇALIŞMA  ", true),
            ("İK %20 #1.pdf", "İK %20 #1.pdf", false)
        ] {
            let relative = "PERSONEL%20EVRAK/" + OAuthSession.encode(expectedName)
            let href = "https://storage.example/dav/" + relative + (isFolder ? "/" : "")
            let xml = """
            <d:multistatus xmlns:d="DAV:">
              <d:response><d:href>https://storage.example/dav/PERSONEL%20EVRAK/</d:href>
                <d:propstat><d:prop><d:displayname>PERSONEL EVRAK</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
              </d:response>
              <d:response><d:href>\(href)</d:href><d:propstat><d:prop>
                <d:displayname>\(xmlTitle)</d:displayname>
                <d:getcontentlength>12&#51;4</d:getcontentlength>
                <d:getcontenttype>application/pdf</d:getcontenttype>
                <d:resourcetype>\(isFolder ? "<d:collection/>" : "")</d:resourcetype>
              </d:prop></d:propstat></d:response>
            </d:multistatus>
            """
            let parsed = WebDAVXMLParser(targetPath: "/dav/PERSONEL EVRAK/").parse(data: Data(xml.utf8))
            try require(parsed.count == 1, "Absolute self href was shown as a child")
            let item = parsed[0]
            try require(item.name == expectedName && item.href == href && item.isDirectory == isFolder, "XML split/whitespace changed a Turkish resource name")
            try require(item.size == 1234 && item.contentType == "application/pdf", "Split metadata was lost")
            try require(item.navigationPath(relativeTo: davConfig) == relative, "Navigation did not preserve the resource href")
            let requestURL = davClient.buildURL(for: item.navigationPath(relativeTo: davConfig))
            try require(requestURL?.path == "/dav/PERSONEL EVRAK/" + expectedName && requestURL?.query == nil && requestURL?.fragment == nil, "Navigation changed resource identity: \(expectedName)")
        }
        try require(davClient.buildURL(for: "/dav/PERSONEL%20EVRAK/")?.absoluteString == "https://storage.example/dav/PERSONEL%20EVRAK/", "Folder URL acquired a duplicate trailing slash")
        let actualFolder = RemoteFileItem(id: "person", name: "ADÖZEL", href: "/dav/PERSONEL%20EVRAK/AD%20%C3%96ZEL/",
            isDirectory: true, size: 0, modificationDate: nil, contentType: nil)
        FixtureURLProtocol.handler = { request in
            guard request.httpMethod == "PROPFIND", request.url?.absoluteString == "https://storage.example/dav/PERSONEL%20EVRAK/AD%20%C3%96ZEL" else { return (404, Data()) }
            return (207, Data("<d:multistatus xmlns:d=\"DAV:\"><d:response><d:href>/dav/PERSONEL%20EVRAK/AD%20%C3%96ZEL/belge.pdf</d:href><d:propstat><d:prop><d:displayname>İşe Giriş.pdf</d:displayname></d:prop></d:propstat></d:response></d:multistatus>".utf8))
        }
        let personnelFiles: [RemoteFileItem] = try await withCheckedThrowingContinuation { continuation in
            davClient.listFiles(at: actualFolder.navigationPath(relativeTo: davConfig)) { continuation.resume(with: $0) }
        }
        try require(personnelFiles.first?.name == "İşe Giriş.pdf", "Nested personnel folder was requested using its display name instead of href")
        print("PASS: Turkish personnel folders and filenames preserve whitespace and navigate using exact server hrefs")
        print("PASS: native cloud document exports retain the destination registered by offline storage")

        try require(CloudDate.parse("2026-01-01T01:02:03.456Z") != nil && CloudDate.parse("2026-01-01T01:02:03Z") != nil, "Cloud modification timestamp was lost")
        print("PASS: fractional cloud timestamps remain available for conflict detection")

        let moveDestination = root.appendingPathComponent("moved")
        try FileManager.default.createDirectory(at: moveDestination, withIntermediateDirectories: true)
        try Data("existing-target".utf8).write(to: moveDestination.appendingPathComponent(recovered.lastPathComponent))
        let moved = try LocalFileOperations.moveFile(recovered, into: moveDestination)
        try require(moved.lastPathComponent != recovered.lastPathComponent && !FileManager.default.fileExists(atPath: recovered.path), "Local move overwrote a collision or left the source behind")
        var refusedDescendant = false
        do { try LocalFileOperations.moveFile(moveDestination, into: moveDestination.appendingPathComponent("child")) } catch { refusedDescendant = true }
        try require(refusedDescendant, "Folder move into its own descendant was allowed")
        print("PASS: batch move preserves name collisions and rejects descendant destinations")
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
