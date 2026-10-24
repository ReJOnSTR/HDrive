import Foundation
import UniformTypeIdentifiers

/// Materialize a complete, isolated snapshot before handing it to another app.
enum FileExportService {
    typealias Listing = (String) async throws -> [RemoteFileItem]
    typealias Download = (String, URL) async throws -> Void

    static func prepare(_ file: RemoteFileItem, client: WebDAVClient) async throws -> URL {
        try await prepare([file], client: client)[0]
    }

    static func prepare(_ files: [RemoteFileItem], client: WebDAVClient) async throws -> [URL] {
        try await prepare(files, config: client.config, root: FileOpener.shared.cacheDir,
            list: { path in
                try await withCheckedThrowingContinuation { continuation in
                    client.listFiles(at: path) { continuation.resume(with: $0) }
                }
            }, download: { href, destination in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    client.downloadFile(href: href, to: destination, progress: { _ in }) { error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume() }
                    }
                }
            })
    }

    static func prepare(_ file: RemoteFileItem, config: CloudreveServerConfig, root: URL,
                        list: Listing, download: Download) async throws -> URL {
        try await prepare([file], config: config, root: root, list: list, download: download)[0]
    }

    static func prepare(_ files: [RemoteFileItem], config: CloudreveServerConfig, root: URL,
                        list: Listing, download: Download) async throws -> [URL] {
        guard !files.isEmpty else { return [] }
        let manager = FileManager.default
        let staging = root.appendingPathComponent(OfflineStore.identity(config))
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try WorkingCache.protect(staging.appendingPathComponent("snapshot"))
            var results: [URL] = []
            for (file, name) in zip(files, exportNames(files, config: config)) {
                let destination = staging.appendingPathComponent(name, isDirectory: file.isDirectory)
                try await materialize(file, to: destination, config: config, ancestors: [], list: list, download: download)
                results.append(destination)
            }
            return results
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    static func localName(_ file: RemoteFileItem, config: CloudreveServerConfig) -> String {
        if !file.isDirectory { return FileOpener.localFileName(for: file, storageProtocol: config.storageProtocol) }
        let name = file.name.components(separatedBy: CharacterSet(charactersIn: "/\\:\0")).joined(separator: "_")
        return name.isEmpty || name == "." || name == ".." ? "folder" : name
    }

    static func exportNames(_ files: [RemoteFileItem], config: CloudreveServerConfig) -> [String] {
        var used: Set<String> = []
        return files.map { file in
            let name = localName(file, config: config)
            let ext = file.isDirectory ? "" : (name as NSString).pathExtension
            let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
            var result = name, counter = 2
            while !used.insert(result.precomposedStringWithCanonicalMapping.lowercased()).inserted {
                result = "\(stem) (\(counter))" + (ext.isEmpty ? "" : "." + ext)
                counter += 1
            }
            return result
        }
    }

    private static func materialize(_ file: RemoteFileItem, to destination: URL, config: CloudreveServerConfig,
                                    ancestors: Set<String>, list: Listing, download: Download) async throws {
        try Task.checkCancellation()
        if file.isDirectory {
            let path = file.navigationPath(relativeTo: config)
            guard ancestors.count < 128, !ancestors.contains(path) else {
                throw NSError(domain: "HDrive.Export", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Klasör listesinde döngü veya aşırı derinlik var."])
            }
            let children = try await list(path)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in children {
                let target = LocalFileOperations.availableURL(destination.appendingPathComponent(localName(child, config: config)))
                try await materialize(child, to: target, config: config, ancestors: ancestors.union([path]), list: list, download: download)
            }
        } else {
            try await download(file.href, destination)
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        try Task.checkCancellation()
    }

    static func itemProvider(for file: RemoteFileItem, client: WebDAVClient,
                             onError: @escaping (Error) -> Void) -> NSItemProvider {
        let name = localName(file, config: client.config)
        let type = file.isDirectory ? UTType.folder : (UTType(filenameExtension: (name as NSString).pathExtension) ?? .data)
        return itemProvider(name: name, type: type, prepare: { try await prepare(file, client: client) }, onError: onError)
    }

    static func itemProvider(name: String, type: UTType, prepare: @escaping () async throws -> URL,
                             onError: @escaping (Error) -> Void) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        let preparation = ExportPreparation(operation: prepare)
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            let task = Task {
                do {
                    let url = try await preparation.value()
                    try Task.checkCancellation()
                    progress.completedUnitCount = 1
                    completion(url, false, nil)
                } catch { onError(error); completion(nil, false, error) }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        // Some desktop targets ask for a file URL rather than a typed representation.
        // The URL is also provided lazily, after the same complete download.
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            let task = Task {
                do {
                    let url = try await preparation.value()
                    try Task.checkCancellation()
                    progress.completedUnitCount = 1
                    completion(Data(url.absoluteString.utf8), nil)
                } catch { onError(error); completion(nil, error) }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        return provider
    }
}

private actor ExportPreparation {
    private var task: Task<URL, Error>?
    private let operation: () async throws -> URL

    init(operation: @escaping () async throws -> URL) { self.operation = operation }

    func value() async throws -> URL {
        if let task { return try await task.value }
        let task = Task { try await operation() }
        self.task = task
        return try await task.value
    }
}
