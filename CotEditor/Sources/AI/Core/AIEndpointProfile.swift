//
//  AIEndpointProfile.swift
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

import Foundation

/// One configured AI service.
///
/// The app keeps several of these and talks to exactly one at a time, so a hosted service, a
/// gateway on the local network and a fallback endpoint can sit side by side and the one in use
/// is a click instead of a retyped configuration.
///
/// The value holds no secret: the API key lives in the keychain under ``id``, which is why that
/// id is assigned once and never changes afterwards.
nonisolated struct AIEndpointProfile: Identifiable, Sendable, Codable, Equatable {
    
    // MARK: Public Properties
    
    /// The identity of the profile, also the account of its keychain item.
    var id: UUID
    
    /// A label the user chose; empty when the service name should be shown instead.
    var name: String
    
    /// The wire protocol.
    var endpoint: AIEndpoint
    
    /// The base URL as typed; an empty string means the protocol default.
    var baseURL: String
    
    /// The model id as typed.
    var model: String
    
    
    // MARK: Lifecycle
    
    init(id: UUID = UUID(),
         name: String = "",
         endpoint: AIEndpoint = .openAIChatCompletions,
         baseURL: String = "",
         model: String = "") {
        
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.baseURL = baseURL
        self.model = model
    }
    
    
    // MARK: Public Computed Properties
    
    /// The name to show, falling back to the service the address belongs to.
    var displayName: String {
        
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty else { return name }
        
        let provider = self.provider
        if provider != .custom { return provider.label }
        
        return self.host ?? self.endpoint.label
    }
    
    
    /// The host and port of the address, without the scheme.
    ///
    /// Used as the fallback name of a service that matches no preset, where the host tells two
    /// gateways apart and the protocol name does not.
    var host: String? {
        
        guard let url = URL(string: self.resolvedBaseURL), let host = url.host else { return nil }
        
        return url.port.map { "\(host):\($0)" } ?? host
    }
    
    
    /// The service preset the stored protocol and address add up to.
    var provider: AIProvider {
        
        AIProvider.detect(endpoint: self.endpoint, baseURL: self.baseURL)
    }
    
    
    /// The address in effect, falling back to the protocol default.
    var resolvedBaseURL: String {
        
        var url = self.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") {
            url.removeLast()
        }
        
        return url.isEmpty ? self.endpoint.defaultBaseURL : url
    }
    
    
    /// The model to show, falling back to a placeholder marker.
    var displayModel: String? {
        
        let model = self.model.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return model.isEmpty ? nil : model
    }
    
    
    // MARK: Public Methods
    
    /// The configuration this profile describes with the given secret.
    ///
    /// - Parameter apiKey: The key stored for this profile.
    /// - Returns: The configuration to hand to the client.
    func configuration(apiKey: String) -> AIConfiguration {
        
        AIConfiguration(endpoint: self.endpoint, baseURL: self.baseURL, model: self.model, apiKey: apiKey)
    }
}
