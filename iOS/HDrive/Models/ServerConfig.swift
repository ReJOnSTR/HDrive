//
//  ServerConfig.swift
//  HDrive
//

import Foundation
import Combine

public final class ServerConfig: ObservableObject {
    public static let shared = ServerConfig()
    
    @Published public var isRunning: Bool = false
    @Published public var port: UInt16 = 8080
    @Published public var requiresAuth: Bool = false
    @Published public var username: String = "admin"
    @Published public var password: String = "hdrive"
    @Published public var allowWrite: Bool = true
    @Published public var keepScreenOn: Bool = true
    
    // Canlı İstatistikler
    @Published public var activeConnectionsCount: Int = 0
    @Published public var totalBytesReceived: Int64 = 0
    @Published public var totalBytesSent: Int64 = 0
    @Published public var serverAddress: String = ""
    @Published public var localIPAddress: String = "127.0.0.1"
    
    // Cihaz Depolama Bilgileri
    @Published public var totalDiskSpace: Int64 = 0
    @Published public var freeDiskSpace: Int64 = 0
    @Published public var usedDiskSpace: Int64 = 0
    
    private init() {
        updateDiskSpace()
        refreshIPAddress()
    }
    
    public func refreshIPAddress() {
        self.localIPAddress = NetworkUtils.getLocalIPAddress() ?? "127.0.0.1"
        self.serverAddress = "http://\(localIPAddress):\(port)"
    }
    
    public func updateDiskSpace() {
        do {
            let docURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
            let values = try docURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            self.totalDiskSpace = Int64(values.volumeTotalCapacity ?? 0)
            self.freeDiskSpace = values.volumeAvailableCapacityForImportantUsage ?? 0
            self.usedDiskSpace = max(0, totalDiskSpace - freeDiskSpace)
        } catch {
            self.totalDiskSpace = 0
            self.freeDiskSpace = 0
            self.usedDiskSpace = 0
        }
    }
    
    public var diskUsagePercentage: Double {
        guard totalDiskSpace > 0 else { return 0 }
        return Double(usedDiskSpace) / Double(totalDiskSpace)
    }
}
