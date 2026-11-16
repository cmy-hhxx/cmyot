//
//  AIKeychain.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Security

/// The API key store.
///
/// API keys are secrets, so they live in the keychain rather than in the preferences file, where
/// they would end up in plain text and in every settings export.
///
/// Every configured endpoint owns one item, keyed by its profile id, so switching endpoints
/// switches keys and removing an endpoint removes its secret. The single account the earlier
/// version used is still readable, because that key is imported once when the endpoint list is
/// built.
nonisolated enum AIKeychain {
    
    private static let service = (Bundle.main.bundleIdentifier ?? "local.cmy.Cot") + ".ai"
    
    /// The account that held the only key before endpoints became a list.
    private static let legacyAccount = "api-key"
    
    
    // MARK: Public Computed Properties
    
    /// The key stored by the version that supported a single endpoint.
    static var legacyAPIKey: String {
        
        self.value(account: self.legacyAccount)
    }
    
    
    // MARK: Public Methods
    
    /// The stored key of one endpoint.
    ///
    /// - Parameter id: The id of the profile.
    /// - Returns: The key, or an empty string when none is stored.
    static func apiKey(for id: UUID) -> String {
        
        self.value(account: id.uuidString)
    }
    
    
    /// Stores the key of one endpoint.
    ///
    /// - Parameters:
    ///   - key: The key; an empty string removes the item.
    ///   - id: The id of the profile.
    static func setAPIKey(_ key: String, for id: UUID) {
        
        self.set(key, account: id.uuidString)
    }
    
    
    /// Removes the stored key of one endpoint.
    ///
    /// - Parameter id: The id of the profile.
    static func removeAPIKey(for id: UUID) {
        
        SecItemDelete(self.query(account: id.uuidString) as CFDictionary)
    }
    
    
    // MARK: Private Methods
    
    /// Reads one stored key.
    ///
    /// - Parameter account: The keychain account to read.
    /// - Returns: The key, or an empty string when none is stored.
    private static func value(account: String) -> String {
        
        var query = self.query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let key = String(data: data, encoding: .utf8)
        else { return "" }
        
        return key
    }
    
    
    /// Writes one key, updating the item in place when it exists.
    ///
    /// - Parameters:
    ///   - key: The key; an empty string removes the item.
    ///   - account: The keychain account to write.
    private static func set(_ key: String, account: String) {
        
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !value.isEmpty else {
            SecItemDelete(self.query(account: account) as CFDictionary)
            return
        }
        
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        
        let status = SecItemUpdate(self.query(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = self.query(account: account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    
    
    /// The query that identifies one item.
    ///
    /// - Parameter account: The keychain account.
    /// - Returns: The query dictionary.
    private static func query(account: String) -> [String: Any] {
        
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: account,
        ]
    }
}
