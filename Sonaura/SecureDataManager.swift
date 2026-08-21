//
//  SecureDataManager.swift
//  Sonaura
//
//  Secure data handling and storage following OWASP best practices
//  Provides encryption, secure key management, and data protection
//

import Foundation
import Security

/// Secure data manager for handling sensitive data and API keys
/// OWASP Guidelines: Never hardcode keys, use secure storage, rotate keys
final class SecureDataManager {
    
    // MARK: - Keychain Service
    
    private static let serviceName = "com.sonaura.app"
    
    // MARK: - API Key Management
    
    /// Store an API key securely in the keychain
    /// - Parameters:
    ///   - key: The API key value
    ///   - keyName: Identifier for the key
    /// - Throws: Error if keychain operation fails
    ///
    /// OWASP Guidelines:
    /// - Never store keys in code or config files
    /// - Use secure storage (iOS Keychain)
    /// - Encrypt sensitive data
    static func storeAPIKey(_ key: String, for keyName: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw SecureDataError.invalidData
        }
        
        // Delete existing key if present
        deleteAPIKey(for: keyName)
        
        // Keychain query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureDataError.keychainError(status)
        }
    }
    
    /// Retrieve an API key from secure storage
    /// - Parameter keyName: Identifier for the key
    /// - Returns: The API key, or nil if not found
    /// - Throws: Error if keychain operation fails
    static func retrieveAPIKey(for keyName: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw SecureDataError.keychainError(status)
        }
        
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw SecureDataError.invalidData
        }
        
        return key
    }
    
    /// Delete an API key from secure storage
    /// - Parameter keyName: Identifier for the key
    static func deleteAPIKey(for keyName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: keyName
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - Environment Variable Support
    
    /// Get API key from environment variable (for development/testing)
    /// Falls back to keychain if environment variable not set
    /// - Parameter keyName: Key identifier
    /// - Returns: API key from environment or keychain
    ///
    /// OWASP Guidelines:
    /// - Use environment variables for keys in development
    /// - Never commit keys to version control
    /// - Use secure storage in production
    static func getAPIKey(_ keyName: String) -> String? {
        // First try environment variable (useful for CI/CD and development)
        if let envKey = ProcessInfo.processInfo.environment[keyName] {
            return envKey
        }
        
        // Fall back to keychain (production)
        return try? retrieveAPIKey(for: keyName)
    }
    
    // MARK: - Key Rotation
    
    /// Rotate an API key (store new, optionally delete old)
    /// - Parameters:
    ///   - newKey: New API key value
    ///   - keyName: Key identifier
    ///   - deleteOld: Whether to delete old key immediately
    /// - Throws: Error if rotation fails
    ///
    /// OWASP Guidelines:
    /// - Implement key rotation procedures
    /// - Rotate keys regularly
    /// - Support graceful key rotation
    static func rotateAPIKey(_ newKey: String, for keyName: String, deleteOld: Bool = true) throws {
        // Store new key
        try storeAPIKey(newKey, for: keyName)
        
        // Optionally delete old key (if using versioned keys)
        if deleteOld {
            deleteAPIKey(for: "\(keyName)_old")
        }
    }
}

// MARK: - Secure Data Errors

enum SecureDataError: LocalizedError {
    case invalidData
    case keychainError(OSStatus)
    case keyNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid data format"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .keyNotFound:
            return "API key not found"
        }
    }
}
