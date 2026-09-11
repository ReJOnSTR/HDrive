//
//  KeychainHelper.swift
//  HDrive
//

import Foundation
import Security

public final class KeychainHelper {
    public static let shared = KeychainHelper()
    private let defaultService = "com.hdrive.cloudreve"
    
    private init() {}
    
    @discardableResult
    public func save(password: String, for account: String, service: String? = nil) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let svc = service ?? defaultService
        
        // Önce mevcut anahtarı sil
        delete(account: account, service: svc)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    public func get(account: String, service: String? = nil) -> String? {
        let svc = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    @discardableResult
    public func delete(account: String, service: String? = nil) -> Bool {
        let svc = service ?? defaultService
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: svc,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
