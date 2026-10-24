import Foundation
import CryptoKit

/// Only a validator and length are persisted; credentials and signed URLs are never journaled.
enum ResumableDownload {
    struct Metadata: Codable { let validator: String; let total: Int64 }
    static func staging(destination: URL, identity: String, remotePath: String) -> (partial: URL, metadata: URL) {
        let key = SHA256.hash(data: Data((identity + "|" + remotePath + "|" + destination.standardizedFileURL.path).utf8)).map { String(format: "%02x", $0) }.joined()
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".hdrive-" + key + ".part")
        return (partial, partial.appendingPathExtension("json"))
    }
    static func download(destination: URL, identity: String, remotePath: String,
                         session suppliedSession: URLSession? = nil,
                         request: ([String: String]) async throws -> URLRequest,
                         progress: (Int64, Int64) async -> Void = { _, _ in }) async throws {
        let files = staging(destination: destination, identity: identity, remotePath: remotePath)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 86400
        let session = suppliedSession ?? URLSession(configuration: configuration)
        defer { if suppliedSession == nil { session.invalidateAndCancel() } }
        var saved = (try? Data(contentsOf: files.metadata)).flatMap { try? JSONDecoder().decode(Metadata.self, from: $0) }
        var offset = ((try? fm.attributesOfItem(atPath: files.partial.path)[.size]) as? NSNumber)?.int64Value ?? 0
        if saved == nil || offset <= 0 || (saved!.total >= 0 && offset > saved!.total) {
            saved = nil; offset = 0
        }
        func reset() throws {
            if fm.fileExists(atPath: files.metadata.path) { try fm.removeItem(at: files.metadata) }
            if fm.fileExists(atPath: files.partial.path) { try fm.removeItem(at: files.partial) }
        }
        // One retry without a range handles servers that no longer have the saved representation.
        for attempt in 0..<2 {
            try Task.checkCancellation()
            var headers = ["Accept-Encoding": "identity"]
            if offset > 0, let saved {
                headers["Range"] = "bytes=\(offset)-"; headers["If-Range"] = saved.validator
            }
            let input = try await request(headers)
            let (bytes, response) = try await session.bytes(for: input, delegate: DownloadRedirectDelegate(request: input))
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { bytes.task.cancel(); throw URLError(.badServerResponse) }
            let tag = http.value(forHTTPHeaderField: "ETag")
            let validator = tag?.hasPrefix("\"") == true ? tag : http.value(forHTTPHeaderField: "Last-Modified")
            var total = http.expectedContentLength
            if http.statusCode == 416 && attempt == 0 {
                bytes.task.cancel(); try reset(); saved = nil; offset = 0; continue
            }
            guard http.statusCode == 200 || http.statusCode == 206 else {
                bytes.task.cancel()
                throw NSError(domain: "HDrive.Download", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "İndirme hatası (HTTP \(http.statusCode))"])
            }
            if http.statusCode == 206 {
                let range = parseRange(http.value(forHTTPHeaderField: "Content-Range"))
                guard let range, range.start == offset,
                      total < 0 || total == range.end - range.start + 1,
                      saved == nil || (saved!.total == range.total && (validator == nil || validator == saved!.validator)) else {
                    bytes.task.cancel()
                    if attempt == 0 { try reset(); saved = nil; offset = 0; continue }
                    throw URLError(.badServerResponse)
                }
                total = range.total
            } else { offset = 0; saved = nil }
            if offset == 0 {
                try reset()
                guard fm.createFile(atPath: files.partial.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { bytes.task.cancel(); throw CocoaError(.fileWriteUnknown) }
            }
            let retainedValidator = validator ?? saved?.validator
            if let retainedValidator, !retainedValidator.isEmpty {
                try JSONEncoder().encode(Metadata(validator: retainedValidator, total: total)).write(to: files.metadata, options: .atomic)
            }
            do {
                let output = try FileHandle(forWritingTo: files.partial)
                defer { try? output.close(); bytes.task.cancel() }
                try output.seekToEnd()
                var count = offset, buffer = Data()
                buffer.reserveCapacity(65536)
                await progress(count, total)
                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count == 65536 {
                        try Task.checkCancellation()
                        try output.write(contentsOf: buffer); count += Int64(buffer.count); buffer.removeAll(keepingCapacity: true)
                        guard total < 0 || count <= total else { try reset(); throw URLError(.badServerResponse) }
                        await progress(count, total)
                    }
                }
                try Task.checkCancellation()
                try output.write(contentsOf: buffer); count += Int64(buffer.count)
                guard total < 0 || count == total else { throw URLError(.networkConnectionLost) }
                try output.synchronize()
                try Task.checkCancellation()
                try SafeFileStorage.installFile(source: files.partial, destination: destination)
                try reset()
                await progress(count, total)
                return
            } catch {
                if retainedValidator == nil { try? reset() }
                throw error
            }
        }
    }
    private static func parseRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64)? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let parts = value.dropFirst(6).split(separator: "/")
        guard parts.count == 2, let total = Int64(parts[1]), total > 0 else { return nil }
        let interval = parts[0].split(separator: "-")
        guard interval.count == 2, let start = Int64(interval[0]), let end = Int64(interval[1]), start >= 0, end >= start, end < total else { return nil }
        return (start, end, total)
    }
}

private final class DownloadRedirectDelegate: NSObject, URLSessionTaskDelegate {
    let original: URLRequest
    init(request: URLRequest) { original = request }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let target = request.url, ["https", "http"].contains(target.scheme),
              original.url?.scheme != "https" || target.scheme == "https" else { completionHandler(nil); return }
        var next = request
        let source = original.url
        let sameOrigin = source?.scheme == target.scheme && source?.host == target.host && source?.port == target.port
        next.setValue(sameOrigin ? original.value(forHTTPHeaderField: "Authorization") : nil, forHTTPHeaderField: "Authorization")
        if !sameOrigin {
            for header in (next.allHTTPHeaderFields ?? [:]).keys where header.lowercased().hasPrefix("x-amz-") || ["cookie", "proxy-authorization"].contains(header.lowercased()) {
                next.setValue(nil, forHTTPHeaderField: header)
            }
        }
        for header in ["Range", "If-Range", "Accept-Encoding"] { next.setValue(original.value(forHTTPHeaderField: header), forHTTPHeaderField: header) }
        completionHandler(next)
    }
}
