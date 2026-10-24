import Foundation
import AppKit

enum ParityRegression {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "HDrive.ParityTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor static func run(root: URL) async throws {
        let account = CloudreveServerConfig(serverURL: "https://storage.example/dav", storageProtocol: .webdav)
        func entry(_ name: String, _ href: String, directory: Bool = false, size: Int64 = 1024, date: Date? = Date(timeIntervalSince1970: 100)) -> RemoteFileItem {
            RemoteFileItem(id: href, name: name, href: href, isDirectory: directory, size: size, modificationDate: date, contentType: nil)
        }
        let filter = ExplorerSearchFilter(query: "cagri", fileExtension: ".PDF", minimumBytes: 1024, modifiedAfter: Date(timeIntervalSince1970: 100))
        try check(filter.matches(entry("ÇAĞRI.pdf", "/dav/a")), "Turkish search/filter boundary rejected")
        for file in [entry("Çağrı.txt", "/dav/b"), entry("Çağrı.pdf", "/dav/c", size: 1023), entry("Çağrı.pdf", "/dav/d", date: nil), entry("Çağrı.pdf", "/dav/e", date: Date(timeIntervalSince1970: 99)), entry("Çağrı.pdf", "/dav/f", directory: true)] {
            try check(!filter.matches(file), "Extension, size, date or directory filter leaked")
        }
        var visited: [String] = []
        let scan = try await ExplorerSearch.scan(start: "", config: account, list: { path in
            visited.append(path)
            if path == "blocked" { throw URLError(.noPermissionsToReadFile) }
            let level = Int(path) ?? 0
            if level == 7 { return [entry("Deep.pdf", "/dav/deep"), entry("Loop", "/dav/1/", directory: true)] }
            var children = [entry("Display name \(level)", "/dav/\(level + 1)/", directory: true)]
            if path.isEmpty { children.append(entry("Blocked", "/dav/blocked/", directory: true)) }
            return children
        })
        try check(scan.files.contains { $0.name == "Deep.pdf" } && scan.errors.count == 1 && visited.filter { $0 == "1" }.count == 1, "Deep traversal, resource paths, failures or cycle handling failed")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ExplorerSearch.scan(start: "", config: account, list: { _ in throw URLError(.badURL) })
        }
        do { _ = try await cancelled.value; throw URLError(.unknown) } catch is CancellationError { }
        print("PASS: advanced Turkish search, depth > 4, actual hrefs, cycles, partial errors and cancellation")

        let folder = entry("Personel", "/dav/personel/", directory: true)
        let extra = entry("Rapor.txt", "/dav/report")
        let duplicate = entry("RAPOR.txt", "/dav/report2")
        let batchRoot = root.appendingPathComponent("batch")
        let files = try await FileExportService.prepare([folder, extra, duplicate], config: account, root: batchRoot,
            list: { path in
                if path == "personel" { return [entry("İşe Giriş", "/dav/personel/giris/", directory: true)] }
                return [entry("Sağlık.txt", "/dav/personel/giris/saglik")]
            }, download: { href, url in try Data(href.utf8).write(to: url) })
        try check(files.count == 3 && files[1].lastPathComponent != files[2].lastPathComponent, "Batch name collision")
        try check(try String(contentsOf: files[0].appendingPathComponent("İşe Giriş/Sağlık.txt"), encoding: .utf8) == "/dav/personel/giris/saglik", "Clipboard folder snapshot lost descendants")
        let before = try FileManager.default.contentsOfDirectory(at: batchRoot.appendingPathComponent(OfflineStore.identity(account)), includingPropertiesForKeys: nil)
        do {
            _ = try await FileExportService.prepare([extra, duplicate], config: account, root: batchRoot, list: { _ in [] }, download: { href, url in
                if href == duplicate.href { throw URLError(.noPermissionsToReadFile) }
                try Data(href.utf8).write(to: url)
            })
            throw URLError(.unknown)
        } catch let error as URLError { try check(error.code == .noPermissionsToReadFile, "Batch failure swallowed") }
        let after = try FileManager.default.contentsOfDirectory(at: batchRoot.appendingPathComponent(OfflineStore.identity(account)), includingPropertiesForKeys: nil)
        try check(Set(before) == Set(after), "Failed clipboard batch left partial output")
        var preparations = 0
        let providers = FileDragPromise.providers(for: FileDragSelection(files: [folder, extra, duplicate], client: WebDAVClient(config: account)), prepare: { preparations += 1; return files }, onError: { _ in })
        try check(providers.count == 3 && preparations == 0, "Drag did not lazily promise every selected item")
        let target = root.appendingPathComponent("drag")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for (index, provider) in providers.enumerated() {
            let delegate = provider.delegate!
            let name = delegate.filePromiseProvider(provider, fileNameForType: provider.fileType)
            try check(name == files[index].lastPathComponent, "Promised filename differs from prepared output")
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.filePromiseProvider(provider, writePromiseTo: target.appendingPathComponent(name)) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
        }
        try check(preparations == 1 && FileManager.default.fileExists(atPath: target.appendingPathComponent("Personel/İşe Giriş/Sağlık.txt").path), "Multi-item promises duplicated downloads or lost folders")
        print("PASS: complete recursive clipboard batches, unique names, rollback and lazy multi-item native file promises")
        try await downloads(root: root)
    }

    static func downloads(root: URL) async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RangeFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        #if HDRIVE_MAC_CLIENT
        var google = CloudreveServerConfig(serverURL: "https://www.googleapis.com", password: "memory-only", storageProtocol: .googleDrive)
        RangeFixture.handler = { _ in
            let json = Data("{\"mimeType\":\"application/vnd.google-apps.spreadsheet\"}".utf8)
            return (200, ["Content-Length": String(json.count)], json)
        }
        let exported = try await WebDAVClient(config: google, session: session).resumableDownloadRequest(href: "native-id", fileName: "Budget.xlsx", headers: ["Range": "bytes=128-", "If-Range": "\"v1\""])
        try check(exported.url!.path.hasSuffix("/native-id/export") && exported.url!.query!.contains("spreadsheetml") && exported.value(forHTTPHeaderField: "Range") == "bytes=128-", "Native Google resume request lost export MIME or range")
        google.storageProtocol = .oneDrive
        let graph = try await WebDAVClient(config: google, session: session).resumableDownloadRequest(href: "item-id", fileName: "Report.pdf", headers: [:])
        try check(graph.url!.host == "graph.microsoft.com" && graph.url!.path.hasSuffix("/item-id/content") && graph.value(forHTTPHeaderField: "Authorization") == "Bearer memory-only", "OneDrive resume used a WebDAV URL or lost current credentials")
        var s3 = CloudreveServerConfig(serverURL: "https://s3.example", username: "access", password: "secret", storageProtocol: .s3)
        s3.bucketName = "bucket"; s3.region = "us-east-1"
        let signed = try await WebDAVClient(config: s3).resumableDownloadRequest(href: "key", fileName: "file", headers: ["Range": "bytes=128-", "If-Range": "\"v1\""])
        try check(signed.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 ") == true && signed.value(forHTTPHeaderField: "Range") == "bytes=128-" && signed.value(forHTTPHeaderField: "If-Range") == "\"v1\"", "S3 resume request lost its signature or conditional headers")
        print("PASS: queued Google exports, OneDrive content endpoints and signed S3 resume requests")
        #endif
        let destination = root.appendingPathComponent("resumed.bin")
        let content = Data(repeating: 65, count: 262144)
        let half = content.count / 2
        var calls = 0
        func download(progress: @escaping (Int64, Int64) async -> Void = { _, _ in }) async throws {
            try await ResumableDownload.download(destination: destination, identity: "account-one", remotePath: "opaque-id", session: session, request: { headers in
                var request = URLRequest(url: URL(string: "https://storage.example/download")!)
                request.setValue("Bearer secret-token", forHTTPHeaderField: "Authorization")
                for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
                return request
            }, progress: progress)
        }
        let staging = ResumableDownload.staging(destination: destination, identity: "account-one", remotePath: "opaque-id")
        try Data("original".utf8).write(to: destination)
        RangeFixture.handler = { request in
            calls += 1
            if calls == 1 { return (200, ["ETag": "\"v1\"", "Content-Length": String(content.count)], content.prefix(half)) }
            try check(request.value(forHTTPHeaderField: "Range") == "bytes=\(half)-" && request.value(forHTTPHeaderField: "If-Range") == "\"v1\"", "Fresh invocation lost persisted range/validator")
            return (206, ["ETag": "\"v1\"", "Content-Range": "bytes \(half)-\(content.count - 1)/\(content.count)", "Content-Length": String(half)], content.suffix(half))
        }
        do { try await download(); throw URLError(.unknown) } catch let error as URLError { try check(error.code == .networkConnectionLost, "Truncated response accepted") }
        try check(try String(contentsOf: destination, encoding: .utf8) == "original", "Interrupted download replaced existing destination")
        let metadata = try String(contentsOf: staging.metadata, encoding: .utf8)
        try check(!metadata.contains("secret") && !metadata.contains("https"), "Credentials or endpoints persisted")
        try await download()
        try check(try Data(contentsOf: destination) == content, "Restarted range download corrupted data")
        try check(!FileManager.default.fileExists(atPath: staging.partial.path), "Successful range left partial data")

        // A cancelled task must leave only validated bytes and be resumable by a new task.
        RangeFixture.handler = { _ in (200, ["ETag": "\"v1\"", "Content-Length": String(content.count)], content) }
        let cancelled = Task {
            try await download(progress: { done, _ in if done >= 65536 { withUnsafeCurrentTask { $0?.cancel() } } })
        }
        do { try await cancelled.value; throw URLError(.unknown) } catch is CancellationError { }
        let persisted = try Data(contentsOf: staging.partial).count
        try check(persisted > 0 && persisted < content.count, "Cancellation did not preserve a partial file")
        let replacement = Data("changed-on-server".utf8)
        RangeFixture.handler = { request in
            try check(request.value(forHTTPHeaderField: "Range") != nil, "Paused transfer did not attempt resume")
            return (200, ["ETag": "\"v2\"", "Content-Length": String(replacement.count)], replacement)
        }
        try await download()
        try check(try Data(contentsOf: destination) == replacement, "Changed server representation was appended to old data")

        try content.prefix(half).write(to: staging.partial)
        try JSONEncoder().encode(ResumableDownload.Metadata(validator: "\"v1\"", total: Int64(content.count))).write(to: staging.metadata)
        calls = 0
        RangeFixture.handler = { request in
            calls += 1
            if calls == 1 { return (206, ["ETag": "\"v1\"", "Content-Range": "bytes 0-\(half - 1)/\(content.count)", "Content-Length": String(half)], content.prefix(half)) }
            try check(request.value(forHTTPHeaderField: "Range") == nil, "Invalid Content-Range was not retried from zero")
            return (200, ["Content-Length": String(content.count)], content)
        }
        try await download()
        try check(try Data(contentsOf: destination) == content && calls == 2, "Malformed range corrupted output")
        RangeFixture.handler = { _ in (200, ["Content-Length": String(content.count)], content.prefix(half)) }
        do { try await download(); throw URLError(.unknown) } catch let error as URLError { try check(error.code == .networkConnectionLost, "Unvalidated truncation accepted") }
        try check(!FileManager.default.fileExists(atPath: staging.partial.path), "Partial without validator retained")
        try content.prefix(half).write(to: staging.partial)
        try JSONEncoder().encode(ResumableDownload.Metadata(validator: "\"v1\"", total: Int64(content.count))).write(to: staging.metadata)
        calls = 0
        RangeFixture.handler = { request in
            calls += 1
            if calls == 1 { return (416, [:], Data()) }
            try check(request.value(forHTTPHeaderField: "Range") == nil, "Unsatisfiable range was not reset")
            return (200, ["Content-Length": String(replacement.count)], replacement)
        }
        try await download()
        RangeFixture.handler = { _ in (403, [:], Data("forbidden".utf8)) }
        do { try await download(); throw URLError(.unknown) } catch { try check((error as NSError).code == 403, "HTTP error not reported") }
        try check(try Data(contentsOf: destination) == replacement, "HTTP error replaced completed destination")
        try check(ResumableDownload.staging(destination: destination, identity: "other-account", remotePath: "opaque-id").partial != staging.partial, "Partial files cross account boundaries")
        print("PASS: persistent byte-range restart, cancellation, changed files, malformed ranges, credential isolation and atomic installation")
    }
}

private final class RangeFixture: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: String], Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
