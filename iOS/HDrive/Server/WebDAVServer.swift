//
//  WebDAVServer.swift
//  HDrive
//

import Foundation
import Network
#if canImport(UIKit)
import UIKit
#endif

public final class WebDAVServer: ObservableObject {
    public static let shared = WebDAVServer()
    
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.hdrive.webdav.server", qos: .userInitiated)
    private let handler = WebDAVHandler()
    private let bonjour = BonjourPublisher()
    
    private init() {}
    
    public func start() {
        guard !ServerConfig.shared.isRunning else { return }
        
        let portVal = ServerConfig.shared.port
        guard let nwPort = NWEndpoint.Port(rawValue: portVal) else {
            print("[Server] Geçersiz port: \(portVal)")
            return
        }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            let newListener = try NWListener(using: parameters, on: nwPort)
            self.listener = newListener
            
            newListener.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        print("[Server] WebDAV Sunucusu Port \(portVal) üzerinde çalışıyor!")
                        ServerConfig.shared.isRunning = true
                        ServerConfig.shared.refreshIPAddress()
                        self?.bonjour.startPublishing(port: Int(portVal))
                        #if canImport(UIKit)
                        if ServerConfig.shared.keepScreenOn {
                            UIApplication.shared.isIdleTimerDisabled = true
                        }
                        #endif
                    case .failed(let error):
                        print("[Server] Hata: \(error.localizedDescription)")
                        self?.stop()
                    case .cancelled:
                        print("[Server] Sunucu durduruldu.")
                        ServerConfig.shared.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            newListener.start(queue: queue)
            
        } catch {
            print("[Server] Listener başlatılamadı: \(error)")
        }
    }
    
    public func stop() {
        bonjour.stopPublishing()
        
        queue.async { [weak self] in
            guard let self = self else { return }
            for (_, conn) in self.connections {
                conn.cancel()
            }
            self.connections.removeAll()
            
            self.listener?.cancel()
            self.listener = nil
            
            DispatchQueue.main.async {
                ServerConfig.shared.isRunning = false
                ServerConfig.shared.activeConnectionsCount = 0
                #if canImport(UIKit)
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
            }
        }
    }
    
    public func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.start()
        }
    }
    
    // MARK: - Bağlantı Yönetimi
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = UUID()
        
        queue.async {
            self.connections[connectionId] = connection
            DispatchQueue.main.async {
                ServerConfig.shared.activeConnectionsCount = self.connections.count
            }
        }
        
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.receiveNextChunk(from: connection, connectionId: connectionId, accumulatedData: Data())
            case .failed, .cancelled:
                self.removeConnection(connectionId)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    private func removeConnection(_ connectionId: UUID) {
        queue.async {
            self.connections.removeValue(forKey: connectionId)
            DispatchQueue.main.async {
                ServerConfig.shared.activeConnectionsCount = self.connections.count
            }
        }
    }
    
    // MARK: - HTTP & WebDAV Veri Okuma ve İşleme
    private func receiveNextChunk(from connection: NWConnection?, connectionId: UUID, accumulatedData: Data) {
        guard let conn = connection else { return }
        
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("[Server] Okuma hatası: \(error)")
                conn.cancel()
                self.removeConnection(connectionId)
                return
            }
            
            var buffer = accumulatedData
            if let incoming = data, !incoming.isEmpty {
                buffer.append(incoming)
            }
            
            // HTTP Header sonunu (\r\n\r\n) bul
            if let headerEndRange = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
                let bodyData = buffer.subdata(in: headerEndRange.upperBound..<buffer.count)
                
                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    conn.cancel()
                    self.removeConnection(connectionId)
                    return
                }
                
                // Content-Length kontrolü
                let contentLength = self.extractContentLength(from: headerString)
                
                if bodyData.count < contentLength {
                    // Body'nin tamamı henüz gelmedi, okumaya devam et
                    self.receiveNextChunk(from: conn, connectionId: connectionId, accumulatedData: buffer)
                    return
                }
                
                // Tam istek hazır -> İşleyiciye gönder
                let request = HTTPRequest(rawText: headerString, bodyData: bodyData)
                let response = self.handler.handle(request: request)
                let responseData = response.toData()
                
                conn.send(content: responseData, completion: .contentProcessed { sendError in
                    if sendError == nil {
                        DispatchQueue.main.async {
                            ServerConfig.shared.totalBytesSent += Int64(responseData.count)
                        }
                    }
                    
                    // HTTP Keep-Alive / Bağlantı sonlandırma kontrolü
                    let connectionHeader = request.headers["connection"]?.lowercased()
                    if connectionHeader == "close" {
                        conn.cancel()
                        self.removeConnection(connectionId)
                    } else {
                        // Kalan veri varsa bir sonraki istek için bekle
                        let remaining = bodyData.count > contentLength ? bodyData.subdata(in: contentLength..<bodyData.count) : Data()
                        self.receiveNextChunk(from: conn, connectionId: connectionId, accumulatedData: remaining)
                    }
                })
                
            } else if isComplete {
                conn.cancel()
                self.removeConnection(connectionId)
            } else {
                // Header henüz bitmedi, okumaya devam et
                self.receiveNextChunk(from: conn, connectionId: connectionId, accumulatedData: buffer)
            }
        }
    }
    
    private func extractContentLength(from headerString: String) -> Int {
        for line in headerString.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2, let len = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    return len
                }
            }
        }
        return 0
    }
}
