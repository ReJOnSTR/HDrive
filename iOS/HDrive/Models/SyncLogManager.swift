//
//  SyncLogManager.swift
//  HDrive
//

import Foundation
import Combine

public struct SyncLogEntry: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let isError: Bool
    
    public init(message: String, isError: Bool = false) {
        self.timestamp = Date()
        self.message = message
        self.isError = isError
    }
    
    public var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

public final class SyncLogManager: ObservableObject {
    public static let shared = SyncLogManager()
    
    @Published public var logs: [SyncLogEntry] = []
    private let maxLogs = 150
    
    private init() {}
    
    public func log(_ message: String, isError: Bool = false) {
        DispatchQueue.main.async {
            let entry = SyncLogEntry(message: message, isError: isError)
            self.logs.insert(entry, at: 0)
            if self.logs.count > self.maxLogs {
                self.logs.removeLast()
            }
        }
    }
    
    public func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
}
