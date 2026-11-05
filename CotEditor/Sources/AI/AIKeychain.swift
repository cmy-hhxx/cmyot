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
/// API keys are secrets, so they live in the keychain rather than in the preferences file,
/// where they would end up in plain text and in every settings export.
nonisolated enum AIKeychain {
    
    private static let service = (Bundle.main.bundleIdentifier ?? "local.cmy.Cot") + ".ai"
    private static let account = "api-key"
    
    
    /// The stored API key, or an empty string when none is stored.
    static var apiKey: String {
        
        get {
            var query = self.baseQuery
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
        
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !value.isEmpty else {
                SecItemDelete(self.baseQuery as CFDictionary)
                return
            }
            
            let data = Data(value.utf8)
            let attributes: [String: Any] = [kSecValueData as String: data]
            
            let status = SecItemUpdate(self.baseQuery as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var query = self.baseQuery
                query[kSecValueData as String] = data
                query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                SecItemAdd(query as CFDictionary, nil)
            }
        }
    }
    
    
    private static var baseQuery: [String: Any] {
        
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: self.account,
        ]
    }
}
