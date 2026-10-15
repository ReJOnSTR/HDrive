import Foundation
import CryptoKit

public enum FolderSyncAction: String { case none, upload, download, conflict }
public enum FolderSyncPolicy: String, CaseIterable { case skip = "Çakışmaları Atla", local = "Yereli Kullan", remote = "Bulutu Kullan", both = "İkisini Koru" }
public struct FolderSyncBaseline: Codable { public var localHash: String; public var remoteStamp: String }
public struct FolderSyncRow: Identifiable {
    public var relativePath: String
    public var localURL: URL
    public var remotePath: String?
    public var localHash: String?
    public var remoteStamp: String?
    public var action: FolderSyncAction
    public var id: String { relativePath }
}
public final class FolderSynchronizer {
    private let client: WebDAVClient
    private let localRoot: URL
    private let remoteRoot: String
    private let manifest: URL
    private let exclusions: [String]
    private var baseline: [String: FolderSyncBaseline] = [:]
    private var remoteDirectories: [String: String] = [:]
    public init(client: WebDAVClient, localRoot: URL, remoteRoot: String, exclusions: String = ".git/**;node_modules/**;*.tmp;*.part") {
        self.client = client; self.localRoot = localRoot; self.remoteRoot = remoteRoot
        self.exclusions = exclusions.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }
        manifest = localRoot.appendingPathComponent(".hdrive-sync-" + S3Signing.hash(OfflineStore.identity(client.config) + "|" + remoteRoot) + ".json")
    }
    public static func decide(local: String?, remote: String?, previous: FolderSyncBaseline?) -> FolderSyncAction {
        if local == nil && remote == nil { return .none }
        guard let previous = previous else { return local == nil ? .download : remote == nil ? .upload : .conflict }
        guard let local = local, let remote = remote else { return .conflict }
        let localChanged = local != previous.localHash, remoteChanged = remote != previous.remoteStamp
        return localChanged && remoteChanged ? .conflict : localChanged ? .upload : remoteChanged ? .download : .none
    }
    private func excluded(_ path: String) -> Bool {
        if path.split(separator: "/").contains(where: { $0.hasPrefix(".hdrive-") }) { return true }
        return exclusions.contains { pattern in
            let expression = "^" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*\\*", with: ".*").replacingOccurrences(of: "\\*", with: "[^/]*").replacingOccurrences(of: "\\?", with: ".") + "$"
            return path.range(of: expression, options: .regularExpression) != nil || (!pattern.contains("/") && path.split(separator: "/").contains { String($0).range(of: expression, options: .regularExpression) != nil })
        }
    }
    private func stamp(_ file: RemoteFileItem) -> String { "\(file.href)|\(file.size)|\(file.modificationDate?.timeIntervalSince1970 ?? -1)" }
    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }; digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func list(_ path: String) async throws -> [RemoteFileItem] {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in client.listFiles(at: path) { continuation.resume(with: $0) } }
    }
    private func scanLocalFiles() throws -> [String: String] {
        var local: [String: String] = [:]
        guard let iterator = FileManager.default.enumerator(at: localRoot, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else { throw CocoaError(.fileReadNoSuchFile) }
        for case let url as URL in iterator {
            try Task.checkCancellation()
            let relative = String(url.path.dropFirst(localRoot.path.count + 1))
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if excluded(relative) || values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            if values.isRegularFile == true { local[relative] = try hash(url) }
        }
        return local
    }
    public func preview() async throws -> [FolderSyncRow] {
        if FileManager.default.fileExists(atPath: manifest.path) { baseline = try JSONDecoder().decode([String: FolderSyncBaseline].self, from: Data(contentsOf: manifest)) }
        let local = try scanLocalFiles()
        var remote: [String: RemoteFileItem] = [:]
        remoteDirectories = ["": remoteRoot]
        var pending: [(String, String)] = [("", remoteRoot)], visited = Set<String>()
        while !pending.isEmpty {
            try Task.checkCancellation(); let (relativeFolder, remoteFolder) = pending.removeFirst()
            if !visited.insert(remoteFolder).inserted { continue }
            for file in try await list(remoteFolder) {
                let name = try LocalFileOperations.validName(file.name)
                let relative = relativeFolder.isEmpty ? name : relativeFolder + "/" + name
                if excluded(relative) { continue }
                if file.isDirectory { remoteDirectories[relative] = file.href; pending.append((relative, file.href)) }
                else {
                    guard remote[relative] == nil else { throw CocoaError(.fileReadCorruptFile) }
                    remote[relative] = file
                }
            }
        }
        return Set(local.keys).union(remote.keys).sorted().map { path in
            let file = remote[path], remoteStamp = file.map(stamp)
            return FolderSyncRow(relativePath: path, localURL: localRoot.appendingPathComponent(path), remotePath: file?.href, localHash: local[path], remoteStamp: remoteStamp,
                action: Self.decide(local: local[path], remote: remoteStamp, previous: baseline[path]))
        }
    }
    private func ensureDirectory(_ relative: String) async throws -> String {
        if let remote = remoteDirectories[relative] { return remote }
        let parent = (relative as NSString).deletingLastPathComponent
        let name = (relative as NSString).lastPathComponent
        let remoteParent = try await ensureDirectory(parent)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.createFolder(at: remoteParent.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + name) { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let files = try await list(remoteParent)
        guard let folder = files.first(where: { $0.isDirectory && $0.name == name }) else { throw CocoaError(.fileReadNoSuchFile) }
        remoteDirectories[relative] = folder.href
        return folder.href
    }
    private func upload(_ url: URL, folder: String, existing: String?) async throws {
        let destination = existing ?? folder.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + url.lastPathComponent
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion: (Error?) -> Void = { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            if let existing = existing { client.replaceFile(href: existing, localURL: url, completion: completion) }
            else { client.uploadFile(localFileURL: url, toRemotePath: destination, completion: completion) }
        }
    }
    private func download(_ path: String, destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.downloadFile(href: path, to: destination, progress: { _ in }) { error in
                if let error = error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
    public func apply(_ rows: [FolderSyncRow], policy: FolderSyncPolicy = .skip) async throws -> [String] {
        var errors: [String] = []
        for row in rows where row.action != .none {
            try Task.checkCancellation()
            if row.action == .conflict && policy == .skip { continue }
            do {
                let localHash = FileManager.default.fileExists(atPath: row.localURL.path) ? try hash(row.localURL) : nil
                guard localHash == row.localHash else { throw error("Yerel dosya önizlemeden sonra değişti; tekrar tarayın.") }
                let parent = (row.relativePath as NSString).deletingLastPathComponent
                let remoteParent = try await ensureDirectory(parent)
                let name = row.localURL.lastPathComponent
                let before = try await list(remoteParent).filter { !$0.isDirectory && $0.name == name }
                guard before.count <= 1, before.first.map(stamp) == row.remoteStamp else { throw error("Uzak dosya önizlemeden sonra değişti; tekrar tarayın.") }
                var action = row.action
                if action == .conflict {
                    if policy == .both && row.localHash != nil && row.remotePath != nil {
                        let suffix = row.localURL.pathExtension
                        let name = row.localURL.deletingPathExtension().lastPathComponent + " (yerel " + UUID().uuidString.prefix(8) + ")" + (suffix.isEmpty ? "" : "." + suffix)
                        let copy = row.localURL.deletingLastPathComponent().appendingPathComponent(name)
                        try FileManager.default.copyItem(at: row.localURL, to: copy)
                        try await upload(copy, folder: remoteParent, existing: nil)
                        let copies = try await list(remoteParent)
                        guard let copied = copies.first(where: { !$0.isDirectory && $0.name == copy.lastPathComponent }) else { throw CocoaError(.fileReadNoSuchFile) }
                        let copyPath = parent.isEmpty ? copy.lastPathComponent : parent + "/" + copy.lastPathComponent
                        baseline[copyPath] = FolderSyncBaseline(localHash: try hash(copy), remoteStamp: stamp(copied))
                        try JSONEncoder().encode(baseline).write(to: manifest, options: .atomic)
                        action = .download
                    } else { action = policy == .local ? .upload : .download }
                }
                if action == .upload {
                    guard row.localHash != nil else { throw error("Yerel dosya yok; silmeler otomatik eşitlenmez.") }
                    try await upload(row.localURL, folder: remoteParent, existing: row.remotePath)
                } else {
                    guard let path = row.remotePath else { throw error("Uzak dosya yok; silmeler otomatik eşitlenmez.") }
                    try await download(path, destination: row.localURL)
                }
                let after = try await list(remoteParent)
                guard let file = after.first(where: { !$0.isDirectory && $0.name == name }) else { throw CocoaError(.fileReadNoSuchFile) }
                baseline[row.relativePath] = FolderSyncBaseline(localHash: try hash(row.localURL), remoteStamp: stamp(file))
                try JSONEncoder().encode(baseline).write(to: manifest, options: .atomic)
            } catch is CancellationError { throw CancellationError() }
            catch { errors.append(row.relativePath + ": " + error.localizedDescription) }
        }
        return errors
    }
    private func error(_ message: String) -> NSError { NSError(domain: "HDrive.Sync", code: 409, userInfo: [NSLocalizedDescriptionKey: message]) }
}
