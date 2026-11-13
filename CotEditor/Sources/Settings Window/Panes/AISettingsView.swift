//
//  AISettingsView.swift
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

import SwiftUI

/// The AI pane of the settings window.
///
/// The pane stays deliberately short: pick the service, paste its API key, fetch the model
/// list and choose a model. The protocol and the base URL live in the advanced section,
/// because the service preset already decides them. Every AI feature shares this one
/// configuration, so a feature added later shows up here as nothing at all.
///
/// The rows themselves carry the structure, so the pane has no captions underneath them:
/// what is not obvious from a label (keychain storage, protocol choice, base URL shape)
/// is a tooltip instead. Every row, the advanced ones included, shares one label column and
/// one leading edge for its control, so the pane reads as a table of settings.
struct AISettingsView: View {
    
    // MARK: Private Properties
    
    /// The width of the control column: the text fields and the status lines under them.
    private static let controlWidth: CGFloat = 460
    
    @State private var endpoint: AIEndpoint = AIConfiguration.current.endpoint
    @State private var baseURL: String = AIConfiguration.current.baseURL
    @State private var model: String = AIConfiguration.current.model
    @State private var apiKey: String = AIConfiguration.current.apiKey
    
    @State private var provider: AIProvider = AIConfiguration.current.provider
    @State private var models: [AIModel] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    
    @State private var isAdvancedExpanded = false
    
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    
    
    // MARK: View Methods
    
    var body: some View {
        
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Text("ai.settings.service.label", tableName: "AI")
                    .gridColumnAlignment(.trailing)
                    .frame(minWidth: 80, alignment: .trailing)
                
                Picker(selection: self.providerSelection) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(verbatim: provider.label).tag(provider)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
            }
            
            GridRow {
                Text("ai.settings.apiKey.label", tableName: "AI")
                    .gridColumnAlignment(.trailing)
                    .frame(minWidth: 80, alignment: .trailing)
                
                SecureField(text: $apiKey, prompt: Text(verbatim: self.apiKeyPrompt)) {
                    Text("ai.settings.apiKey.label", tableName: "AI")
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: Self.controlWidth)
                .disabled(!self.endpoint.requiresAPIKey)
                .help(Text("ai.settings.apiKey.caption", tableName: "AI"))
            }
            
            GridRow {
                Text("ai.settings.model.label", tableName: "AI")
                    .gridColumnAlignment(.trailing)
                    .frame(minWidth: 80, alignment: .trailing)
                
                HStack(spacing: 8) {
                    Picker(selection: $model) {
                        if self.modelOptions.isEmpty {
                            Text("ai.settings.model.fetchFirst", tableName: "AI")
                                .tag("")
                                .disabled(true)
                        } else if self.model.isEmpty {
                            Text("ai.settings.model.select", tableName: "AI")
                                .tag("")
                                .disabled(true)
                        }
                        
                        ForEach(self.modelOptions) { model in
                            Text(verbatim: model.name).tag(model.id)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                    
                    Button {
                        Task { await self.fetchModels() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help(Text("ai.settings.model.fetch", tableName: "AI"))
                    .accessibilityLabel(Text("ai.settings.model.fetch", tableName: "AI"))
                    .disabled(self.isFetchingModels || !self.canFetchModels)
                    
                    if self.isFetchingModels {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            
            if let modelFetchError {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    
                    Text(modelFetchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Self.controlWidth, alignment: .leading)
                }
            }
            
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                
                HStack(spacing: 12) {
                    Button {
                        Task { await self.testConnection() }
                    } label: {
                        Text("ai.settings.test", tableName: "AI")
                    }
                    .disabled(self.isTesting || self.model.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    if self.isTesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    
                    if let testMessage {
                        Label(testMessage, systemImage: self.testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(self.testSucceeded ? .green : .red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }
            
            GridRow {
                self.advancedDisclosure
                    .gridCellColumns(2)
                    .padding(.top, 12)
            }
            
            if self.advancedExpansion.wrappedValue {
                if self.provider == .custom {
                    GridRow {
                        Text("ai.settings.protocol.label", tableName: "AI")
                            .gridColumnAlignment(.trailing)
                            .frame(minWidth: 80, alignment: .trailing)
                        
                        Picker(selection: $endpoint) {
                            ForEach(AIEndpoint.allCases, id: \.self) { endpoint in
                                Text(verbatim: endpoint.label).tag(endpoint)
                            }
                        } label: {
                            EmptyView()
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help(Text(verbatim: self.endpoint.hint))
                    }
                }
                
                GridRow {
                    Text("ai.settings.baseURL.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 80, alignment: .trailing)
                    
                    TextField(text: $baseURL, prompt: Text(verbatim: self.baseURLPlaceholder)) {
                        Text("ai.settings.baseURL.label", tableName: "AI")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlWidth)
                    .help(Text("ai.settings.baseURL.caption", tableName: "AI"))
                }
            }
        }
        .onChange(of: self.baseURL) { _, _ in
            self.provider = AIProvider.detect(endpoint: self.endpoint, baseURL: self.baseURL)
            self.save()
        }
        .onChange(of: self.endpoint) { _, _ in
            self.provider = AIProvider.detect(endpoint: self.endpoint, baseURL: self.baseURL)
            self.save()
        }
        .onChange(of: self.model) { _, _ in self.save() }
        .onChange(of: self.apiKey) { _, _ in self.save() }
        .task { await self.autoFetchModels() }
        .scenePadding()
        .frame(width: 620)
    }
    
    
    // MARK: Private Computed Properties
    
    /// The service picker's binding, so picking a service also resets what it decides.
    private var providerSelection: Binding<AIProvider> {
        
        Binding(get: { self.provider }, set: { self.selectProvider($0) })
    }
    
    
    /// The models to offer, always including the stored one.
    ///
    /// The stored model is shown even before any list was fetched, so the pane never hides the
    /// configuration that is actually in use.
    private var modelOptions: [AIModel] {
        
        var options = self.models
        
        let stored = self.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty, !options.contains(where: { $0.id == stored }) {
            options.insert(AIModel(id: stored, name: stored), at: 0)
        }
        
        return options
    }
    
    
    /// The Advanced header, which opens the rows that follow it in the same grid.
    ///
    /// A `DisclosureGroup` indents its content, which would place the protocol and the base URL
    /// on a second label column; this header keeps them on the pane's single column.
    private var advancedDisclosure: some View {
        
        Button {
            self.isAdvancedExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(self.advancedExpansion.wrappedValue ? 90 : 0))
                    .cotAnimation(.cotFast, value: self.advancedExpansion.wrappedValue)
                
                Text("ai.settings.advanced", tableName: "AI")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    
    /// The advanced section opens by itself for a custom service, and stays open.
    private var advancedExpansion: Binding<Bool> {
        
        Binding(get: { self.isAdvancedExpanded || self.provider == .custom },
                set: { self.isAdvancedExpanded = $0 })
    }
    
    
    /// Whether the service can be asked for its model list with the current input.
    private var canFetchModels: Bool {
        
        !self.endpoint.requiresAPIKey
            || !self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    /// The placeholder for the API key field, since only hosted services need a key.
    private var apiKeyPrompt: String {
        
        if self.endpoint.requiresAPIKey {
            String(localized: "ai.settings.apiKey.prompt",
                   defaultValue: "sk-…",
                   table: "AI")
        } else {
            String(localized: "ai.settings.apiKey.prompt.local",
                   defaultValue: "Leave empty for local services",
                   table: "AI")
        }
    }
    
    
    /// The base URL to show as a placeholder, taken from the service preset when it has one.
    private var baseURLPlaceholder: String {
        
        let value = self.provider.defaultBaseURL
        
        return value.isEmpty ? self.endpoint.defaultBaseURL : value
    }
    
    
    // MARK: Private Methods
    
    /// Applies a service preset and forgets what belonged to the previous one.
    ///
    /// A preset whose base URL differs from the protocol default stores that URL, because the
    /// stored values are the only thing that is remembered and an empty URL always means "the
    /// protocol default".
    ///
    /// - Parameter provider: The service to switch to.
    private func selectProvider(_ provider: AIProvider) {
        
        guard provider != self.provider else { return }
        
        self.provider = provider
        
        if provider != .custom {
            self.endpoint = provider.endpoint
            self.baseURL = (provider.defaultBaseURL == provider.endpoint.defaultBaseURL) ? "" : provider.defaultBaseURL
        }
        
        self.model = ""
        self.models = []
        self.modelFetchError = nil
        self.testMessage = nil
        
        self.save()
        
        Task { await self.autoFetchModels() }
    }
    
    
    /// Stores the configuration and clears the previous test result.
    private func save() {
        
        AIConfiguration(endpoint: self.endpoint,
                        baseURL: self.baseURL,
                        model: self.model,
                        apiKey: self.apiKey).save()
        
        self.testMessage = nil
    }
    
    
    /// Asks for the model list only when the service has what it needs to answer.
    private func autoFetchModels() async {
        
        guard self.canFetchModels else { return }
        
        await self.fetchModels()
    }
    
    
    /// Fetches the model list and shows why the fetch failed.
    private func fetchModels() async {
        
        self.save()
        self.isFetchingModels = true
        self.modelFetchError = nil
        defer { self.isFetchingModels = false }
        
        do {
            self.models = try await AIService.shared.fetchModels()
        } catch {
            self.models = []
            self.modelFetchError = error.localizedDescription
        }
    }
    
    
    /// Asks the service for a one-word reply, to prove the setup works.
    private func testConnection() async {
        
        self.save()
        self.isTesting = true
        self.testMessage = nil
        defer { self.isTesting = false }
        
        do {
            let reply = try await AIService.shared.testConnection()
            self.testSucceeded = true
            self.testMessage = String(format: String(localized: "ai.settings.test.success",
                                                     defaultValue: "Connection succeeded: %@",
                                                     table: "AI"),
                                      reply)
        } catch {
            self.testSucceeded = false
            self.testMessage = error.localizedDescription
        }
    }
}


// MARK: - Preview

#Preview {
    AISettingsView()
}
