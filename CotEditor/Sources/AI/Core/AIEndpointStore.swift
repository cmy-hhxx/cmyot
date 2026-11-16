//
//  AIEndpointStore.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-16.
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

import Defaults
import Foundation

/// The list of configured AI services and which one is in use.
///
/// The profiles are stored as one JSON blob in the preferences file, because only the non-secret
/// half is in them: every API key is read and written through ``AIKeychain`` under its profile id.
/// A configuration saved by the version that supported a single endpoint is imported once by
/// ``migrateLegacyConfigurationIfNeeded()``, so upgrading keeps what was already set up.
nonisolated enum AIEndpointStore {
    
    // MARK: Public Computed Properties
    
    /// Every configured service, in the order the settings pane shows them.
    static var profiles: [AIEndpointProfile] {
        
        get {
            guard let data = UserDefaults.standard[.aiProfiles] else { return [] }
            
            return (try? JSONDecoder().decode([AIEndpointProfile].self, from: data)) ?? []
        }
        
        set {
            UserDefaults.standard[.aiProfiles] = try? JSONEncoder().encode(newValue)
        }
    }
    
    
    /// The id of the service in use.
    static var activeID: UUID? {
        
        get { UserDefaults.standard[.aiActiveProfileID].flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard[.aiActiveProfileID] = newValue?.uuidString }
    }
    
    
    /// The service in use, falling back to the first one when the stored id is stale.
    static var activeProfile: AIEndpointProfile? {
        
        self.profiles.first { $0.id == self.activeID } ?? self.profiles.first
    }
    
    
    /// The configuration every AI feature uses.
    static var activeConfiguration: AIConfiguration {
        
        self.migrateLegacyConfigurationIfNeeded()
        
        guard let profile = self.activeProfile else { return .empty }
        
        return profile.configuration(apiKey: AIKeychain.apiKey(for: profile.id))
    }
    
    
    // MARK: Public Methods
    
    /// The key stored for one profile.
    ///
    /// - Parameter profile: The profile to read the secret of.
    /// - Returns: The key, or an empty string when none is stored.
    static func apiKey(for profile: AIEndpointProfile) -> String {
        
        AIKeychain.apiKey(for: profile.id)
    }
    
    
    /// Adds or updates one service, storing its secret alongside.
    ///
    /// A profile that is the first of the list becomes the one in use, so adding an endpoint is
    /// enough to start using it.
    ///
    /// - Parameters:
    ///   - profile: The profile to store.
    ///   - apiKey: The key to store for it.
    static func save(_ profile: AIEndpointProfile, apiKey: String) {
        
        var profiles = self.profiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        self.profiles = profiles
        AIKeychain.setAPIKey(apiKey, for: profile.id)
        
        if self.activeID == nil {
            self.activeID = profile.id
        }
    }
    
    
    /// Removes one service together with its secret.
    ///
    /// - Parameter id: The id of the profile to remove.
    static func delete(id: UUID) {
        
        var profiles = self.profiles
        profiles.removeAll { $0.id == id }
        self.profiles = profiles
        AIKeychain.removeAPIKey(for: id)
        
        if self.activeID == id {
            self.activeID = profiles.first?.id
        }
    }
    
    
    /// Imports the single configuration stored before services became a list.
    ///
    /// Runs on every read and does nothing once the list has an entry, so it is safe to call
    /// from the places that only need the configuration.
    static func migrateLegacyConfigurationIfNeeded() {
        
        guard self.profiles.isEmpty else { return }
        
        let defaults = UserDefaults.standard
        let endpoint = defaults[.aiEndpoint] ?? .openAIChatCompletions
        let baseURL = defaults[.aiBaseURL]
        let model = defaults[.aiModel]
        let apiKey = AIKeychain.legacyAPIKey
        
        guard !baseURL.isEmpty || !model.isEmpty || !apiKey.isEmpty else { return }
        
        // The name stays empty: the profile falls back to the service or the host, which reads
        // better than the "custom" preset label the old configuration cannot distinguish from.
        let profile = AIEndpointProfile(endpoint: endpoint,
                                        baseURL: baseURL,
                                        model: model)
        self.profiles = [profile]
        AIKeychain.setAPIKey(apiKey, for: profile.id)
        self.activeID = profile.id
    }
}
