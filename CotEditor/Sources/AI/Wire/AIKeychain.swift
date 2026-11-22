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

/// Local file-backed API key store for configured AI endpoints.
///
/// Stores secrets in a private JSON dictionary (`0o600`) inside the app's Application Support
/// directory rather than the macOS Keychain, preventing password prompts and ACL invalidation
/// across ad-hoc rebuilds while keeping reads non-blocking and lock-synchronized.
nonisolated enum AIKeychain {
    
    /// The account name used before endpoints became a list.
    private static let legacyAccount = "api-key"
    
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedSecrets: [String: String]?
    private nonisolated(unsafe) static var customStoreURL: URL?
    
    
    // MARK: Public Computed Properties
    
    /// The key stored under the legacy single-endpoint account if present locally.
    static var legacyAPIKey: String {
        
        self.value(account: self.legacyAccount)
    }
    
    
    /// Stores the legacy single-endpoint API key when migrating/restoring old configurations.
    static func setLegacyAPIKey(_ key: String) {
        
        self.set(key, account: self.legacyAccount)
    }
    
    
    // MARK: Public Methods
    
    /// Returns the stored API key for one endpoint profile.
    static func apiKey(for id: UUID) -> String {
        
        self.value(account: id.uuidString)
    }
    
    
    /// Stores or clears the API key for one endpoint profile.
    static func setAPIKey(_ key: String, for id: UUID) {
        
        self.set(key, account: id.uuidString)
    }
    
    
    /// Removes the stored API key for one endpoint profile.
    static func removeAPIKey(for id: UUID) {
        
        self.set("", account: id.uuidString)
    }
    
    
    /// Returns a snapshot of all non-empty stored API keys keyed by account identifier.
    static func allAPIKeys() -> [String: String] {
        
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.loadSecretsLocked()
    }
    
    
    /// Merges a dictionary of account -> API key entries into the local secret store.
    static func mergeAPIKeys(_ keys: [String: String], overwriteExisting: Bool = true) {
        
        guard !keys.isEmpty else { return }
        self.lock.lock()
        defer { self.lock.unlock() }
        
        var map = self.loadSecretsLocked()
        var didChange = false
        for (account, rawValue) in keys {
            let trimmedKey = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanAccount.isEmpty, !trimmedKey.isEmpty else { continue }
            if overwriteExisting || (map[cleanAccount]?.isEmpty ?? true) {
                map[cleanAccount] = trimmedKey
                didChange = true
            }
        }
        if didChange {
            self.saveSecretsLocked(map)
        }
    }
    
    
    /// Overrides the backing store file URL (intended for unit tests).
    static func setStoreURLForTesting(_ url: URL?) {
        
        self.lock.lock()
        defer { self.lock.unlock() }
        self.customStoreURL = url
        self.cachedSecrets = nil
    }
    
    
    /// Returns the active local secrets file URL.
    static var storeURL: URL {
        
        self.lock.lock()
        let custom = self.customStoreURL
        self.lock.unlock()
        if let custom {
            return custom
        }
        
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("CotTests-ai_secrets-\(ProcessInfo.processInfo.processIdentifier).json", isDirectory: false)
        }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Cot", isDirectory: true)
            .appendingPathComponent("ai_secrets.json", isDirectory: false)
    }
    
    
    // MARK: Private Methods
    
    private static func value(account: String) -> String {
        
        self.lock.lock()
        defer { self.lock.unlock() }
        let map = self.loadSecretsLocked()
        return map[account] ?? ""
    }
    
    
    private static func set(_ key: String, account: String) {
        
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lock.lock()
        defer { self.lock.unlock() }
        
        var map = self.loadSecretsLocked()
        if trimmed.isEmpty {
            map.removeValue(forKey: account)
        } else {
            map[account] = trimmed
        }
        self.saveSecretsLocked(map)
    }
    
    
    private static func loadSecretsLocked() -> [String: String] {
        
        if let cached = self.cachedSecrets {
            return cached
        }
        
        let url = self.currentStoreURLLocked()
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            self.cachedSecrets = [:]
            return [:]
        }
        
        self.cachedSecrets = decoded
        return decoded
    }
    
    
    private static func saveSecretsLocked(_ secrets: [String: String]) {
        
        self.cachedSecrets = secrets
        let url = self.currentStoreURLLocked()
        let dirURL = url.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(secrets)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            CotLogger.shared.error(category: .ai, "Failed persisting AI API key store", error: error)
        }
    }
    
    
    private static func currentStoreURLLocked() -> URL {
        
        if let custom = self.customStoreURL {
            return custom
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("CotTests-ai_secrets-\(ProcessInfo.processInfo.processIdentifier).json", isDirectory: false)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Cot", isDirectory: true)
            .appendingPathComponent("ai_secrets.json", isDirectory: false)
    }
}
