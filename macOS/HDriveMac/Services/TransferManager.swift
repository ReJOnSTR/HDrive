//
//  TransferManager.swift
//  HDriveMac - Merkezi Transfer ve Kuyruk Yöneticisi
//

import Foundation
import Combine
import SwiftUI

public enum TransferDirection: String, Codable {
    case download = "İndirme"
    case upload = "Yükleme"
}

public enum TransferStatus: String, Codable {
    case queued = "Kuyrukta"
    case running = "Aktarılıyor"
    case paused = "Duraklatıldı"
    case completed = "Tamamlandı"
    case failed = "Hata"
    case cancelled = "İptal Edildi"
}

public final class TransferItem: ObservableObject, Identifiable {
    public let id: UUID
    public let fileName: String
    public let remotePath: String
    public let localURL: URL
    public let direction: TransferDirection
    
    @Published public var status: TransferStatus = .queued
    @Published public var transferredBytes: Int64 = 0
    @Published public var totalBytes: Int64 = 0
    @Published public var progress: Double = 0.0
    @Published public var speedBytesPerSec: Double = 0.0
    @Published public var errorMessage: String? = nil
    
    public var resumeData: Data? = nil
    public weak var urlSessionTask: URLSessionTask? = nil
    
    var lastSampleBytes: Int64 = 0
    var lastSampleTime: Date = Date()
    var client: WebDAVClient?
    
    public init(
        id: UUID = UUID(),
        fileName: String,
        remotePath: String,
        localURL: URL,
        direction: TransferDirection,
        totalBytes: Int64 = 0,
        client: WebDAVClient? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.remotePath = remotePath
        self.localURL = localURL
        self.direction = direction
        self.totalBytes = totalBytes
        self.client = client
    }
    
    public var formattedSize: String {
        if totalBytes > 0 {
            let tr = ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
            let tot = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(tr) / \(tot)"
        } else if transferredBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: transferredBytes, countStyle: .file)
        } else {
            return "Hesaplanıyor..."
        }
    }
    
    public var formattedSpeed: String {
        guard status == .running, speedBytesPerSec > 1024 else { return "" }
        let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSec), countStyle: .file)
        return "\(speedStr)/s"
    }
}

public final class TransferManager: NSObject, ObservableObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    public static let shared = TransferManager()
    
    @Published public var items: [TransferItem] = []
    @Published public var activeTransfersCount: Int = 0
    @Published public var isTransferring: Bool = false
    @Published public var overallProgress: Double = 0.0
    
    private let maxConcurrentTransfers = 3
    private var session: URLSession!
    private var taskMap: [Int: TransferItem] = [:] // Task Identifier -> TransferItem
    private let lock = NSLock()
    private var speedTimer: Timer?
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
        
        // Periyodik hız hesaplayıcı (Her 1 saniyede bir)
        self.speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.calculateSpeeds()
        }
    }
    
    deinit {
        speedTimer?.invalidate()
    }
    
    // MARK: - Kuyruk Ekleme (Enqueue)
    
    @discardableResult
    public func enqueueDownload(fileName: String, remoteHref: String, localTargetURL: URL, client: WebDAVClient, expectedSize: Int64 = 0) -> TransferItem {
        lock.lock()
        // Eğer zaten aynı isimde aktif/kuyrukta bir transfer varsa onu dön
        if let existing = items.first(where: { $0.remotePath == remoteHref && ($0.status == .running || $0.status == .queued) }) {
            lock.unlock()
            return existing
        }
        
        let item = TransferItem(
            fileName: fileName,
            remotePath: remoteHref,
            localURL: localTargetURL,
            direction: .download,
            totalBytes: expectedSize,
            client: client
        )
        items.insert(item, at: 0)
        lock.unlock()
        
        updateState()
        processQueue()
        return item
    }
    
    @discardableResult
    public func enqueueUpload(fileURL: URL, remoteFolder: String, client: WebDAVClient) -> TransferItem {
        lock.lock()
        let fileName = fileURL.lastPathComponent
        let targetRemote = remoteFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + fileName
        
        var size: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let fSize = attrs[.size] as? Int64 {
            size = fSize
        }
        
        let item = TransferItem(
            fileName: fileName,
            remotePath: targetRemote,
            localURL: fileURL,
            direction: .upload,
            totalBytes: size,
            client: client
        )
        items.insert(item, at: 0)
        lock.unlock()
        
        updateState()
        processQueue()
        return item
    }
    
    // MARK: - Kuyruk İşleyici
    
    private func processQueue() {
        lock.lock()
        let runningCount = items.filter { $0.status == .running }.count
        let slotsAvailable = max(0, maxConcurrentTransfers - runningCount)
        
        guard slotsAvailable > 0 else {
            lock.unlock()
            updateState()
            return
        }
        
        let queuedItems = items.filter { $0.status == .queued }.prefix(slotsAvailable)
        lock.unlock()
        
        for item in queuedItems {
            startTransfer(item)
        }
        
        updateState()
    }
    
    private func startTransfer(_ item: TransferItem) {
        guard let client = item.client else {
            item.status = .failed
            item.errorMessage = "Sunucu bağlantısı bulunamadı."
            return
        }
        
        item.status = .running
        item.errorMessage = nil
        item.lastSampleTime = Date()
        item.lastSampleBytes = item.transferredBytes
        
        if item.direction == .download {
            startDownloadTask(item, client: client)
        } else {
            startUploadTask(item, client: client)
        }
    }
    
    private func startDownloadTask(_ item: TransferItem, client: WebDAVClient) {
        if client.config.storageProtocol == .googleDrive || client.config.storageProtocol == .oneDrive {
            client.downloadFile(href: item.remotePath, to: item.localURL, progress: { [weak item] prog in
                DispatchQueue.main.async {
                    item?.progress = prog
                    item?.transferredBytes = Int64(Double(item?.totalBytes ?? 0) * prog)
                }
            }) { [weak self, weak item] error in
                DispatchQueue.main.async {
                    guard let self = self, let item = item else { return }
                    if let error = error {
                        item.status = .failed
                        item.errorMessage = error.localizedDescription
                    } else {
                        item.status = .completed
                        item.progress = 1.0
                        item.transferredBytes = item.totalBytes
                        item.speedBytesPerSec = 0
                    }
                    self.processQueue()
                }
            }
            return
        }
        
        if let resumeData = item.resumeData {
            let task = session.downloadTask(withResumeData: resumeData)
            item.urlSessionTask = task
            taskMap[task.taskIdentifier] = item
            task.resume()
            return
        }
        
        guard let url = client.downloadURL(for: item.remotePath) else {
            item.status = .failed
            item.errorMessage = "Geçersiz indirme bağlantısı."
            processQueue()
            return
        }
        
        var request = URLRequest(url: url)
        if let auth = client.authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        let task = session.downloadTask(with: request)
        item.urlSessionTask = task
        taskMap[task.taskIdentifier] = item
        task.resume()
    }
    
    private func startUploadTask(_ item: TransferItem, client: WebDAVClient) {
        if client.config.storageProtocol == .googleDrive || client.config.storageProtocol == .oneDrive {
            client.uploadFile(localFileURL: item.localURL, toRemotePath: item.remotePath) { [weak self, weak item] error in
                DispatchQueue.main.async {
                    guard let self = self, let item = item else { return }
                    if let error = error {
                        item.status = .failed
                        item.errorMessage = error.localizedDescription
                    } else {
                        item.status = .completed
                        item.progress = 1.0
                        item.transferredBytes = item.totalBytes
                        item.speedBytesPerSec = 0
                    }
                    self.processQueue()
                }
            }
            return
        }
        
        guard let url = client.buildURL(for: item.remotePath) else {
            item.status = .failed
            item.errorMessage = "Geçersiz hedef adresi."
            processQueue()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let auth = client.authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        
        let task = session.uploadTask(with: request, fromFile: item.localURL)
        item.urlSessionTask = task
        taskMap[task.taskIdentifier] = item
        task.resume()
    }
    
    // MARK: - Eylemler (Pause, Resume, Cancel, Retry, Clear)
    
    public func pauseTask(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.status == .running else { return }
        
        if let dt = item.urlSessionTask as? URLSessionDownloadTask {
            dt.cancel { [weak self, weak item] data in
                DispatchQueue.main.async {
                    item?.resumeData = data
                    item?.status = .paused
                    item?.speedBytesPerSec = 0
                    self?.processQueue()
                }
            }
        } else {
            item.urlSessionTask?.suspend()
            item.status = .paused
            item.speedBytesPerSec = 0
            processQueue()
        }
    }
    
    public func resumeTask(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        guard item.status == .paused || item.status == .queued else { return }
        
        item.status = .queued
        processQueue()
    }
    
    public func cancelTask(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.urlSessionTask?.cancel()
        item.status = .cancelled
        item.speedBytesPerSec = 0
        processQueue()
    }
    
    public func retryTask(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.status = .queued
        item.transferredBytes = 0
        item.progress = 0
        item.errorMessage = nil
        item.resumeData = nil
        processQueue()
    }
    
    public func clearCompleted() {
        lock.lock()
        items.removeAll { $0.status == .completed || $0.status == .cancelled }
        lock.unlock()
        updateState()
    }
    
    // MARK: - URLSession Delegates
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let item = taskMap[downloadTask.taskIdentifier] else { return }
        DispatchQueue.main.async {
            item.transferredBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                item.totalBytes = totalBytesExpectedToWrite
                item.progress = min(1.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = taskMap[downloadTask.taskIdentifier] else { return }
        
        do {
            let parent = item.localURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: item.localURL)
            try FileManager.default.moveItem(at: location, to: item.localURL)
            
            DispatchQueue.main.async {
                item.status = .completed
                item.progress = 1.0
                item.speedBytesPerSec = 0
                self.taskMap.removeValue(forKey: downloadTask.taskIdentifier)
                self.processQueue()
            }
        } catch {
            DispatchQueue.main.async {
                item.status = .failed
                item.errorMessage = error.localizedDescription
                self.taskMap.removeValue(forKey: downloadTask.taskIdentifier)
                self.processQueue()
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let item = taskMap[task.taskIdentifier] else { return }
        DispatchQueue.main.async {
            item.transferredBytes = totalBytesSent
            if totalBytesExpectedToSend > 0 {
                item.totalBytes = totalBytesExpectedToSend
                item.progress = min(1.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
            }
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = taskMap[task.taskIdentifier] else { return }
        
        DispatchQueue.main.async {
            if let error = error as? URLError, error.code == .cancelled {
                // Manuel duraklatma veya iptal
                return
            }
            
            if let error = error {
                item.status = .failed
                item.errorMessage = error.localizedDescription
            } else if let response = task.response as? HTTPURLResponse {
                if (200...299).contains(response.statusCode) || response.statusCode == 201 || response.statusCode == 204 {
                    item.status = .completed
                    item.progress = 1.0
                } else {
                    item.status = .failed
                    item.errorMessage = "Sunucu yanıtı: HTTP \(response.statusCode)"
                }
            } else {
                item.status = .completed
                item.progress = 1.0
            }
            
            item.speedBytesPerSec = 0
            self.taskMap.removeValue(forKey: task.taskIdentifier)
            self.processQueue()
        }
    }
    
    // MARK: - Yardımcı Hesaplamalar
    
    private func calculateSpeeds() {
        let now = Date()
        for item in items where item.status == .running {
            let dt = now.timeIntervalSince(item.lastSampleTime)
            if dt >= 0.8 {
                let db = item.transferredBytes - item.lastSampleBytes
                if db >= 0 {
                    let currentSpeed = Double(db) / dt
                    // Yumuşatılmış hareketli ortalama (EMA)
                    item.speedBytesPerSec = (item.speedBytesPerSec * 0.4) + (currentSpeed * 0.6)
                }
                item.lastSampleBytes = item.transferredBytes
                item.lastSampleTime = now
            }
        }
        updateState()
    }
    
    private func updateState() {
        let active = items.filter { $0.status == .running || $0.status == .queued }
        self.activeTransfersCount = active.count
        self.isTransferring = !active.isEmpty
        
        let runningItems = items.filter { $0.status == .running }
        if !runningItems.isEmpty {
            let sumProg = runningItems.reduce(0.0) { $0 + $1.progress }
            self.overallProgress = sumProg / Double(runningItems.count)
        } else {
            self.overallProgress = 0.0
        }
    }
}
