//
//  AIEndpointEditorView.swift
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

import SwiftUI

/// The sheet that creates or edits one AI endpoint.
///
/// Adding and editing share it, so there is one place where an endpoint is described. The model
/// is a text field with the fetched list next to it rather than a picker: a service that does
/// not answer the model list (or answers it badly) can still be used by typing the id, which
/// was a dead end while the field could only be filled by a successful fetch.
///
/// Testing talks to the values on screen, not to the stored ones, so an endpoint can prove
/// itself before it replaces the one in use.
struct AIEndpointEditorView: View {
    
    // MARK: Private Properties
    
    private static let controlWidth: CGFloat = 360
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var draft: AIEndpointProfile
    @State private var apiKey: String
    @State private var models: [AIModel] = []
    @State private var isFetchingModels = false
    @State private var fetchError: String?
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    
    private let isNew: Bool
    private let onSave: (AIEndpointProfile, String) -> Void
    
    
    // MARK: Lifecycle
    
    init(profile: AIEndpointProfile, apiKey: String, isNew: Bool, onSave: @escaping (AIEndpointProfile, String) -> Void) {
        
        self._draft = State(initialValue: profile)
        self._apiKey = State(initialValue: apiKey)
        self.isNew = isNew
        self.onSave = onSave
    }
    
    
    // MARK: View Methods
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 14) {
            self.title
                .font(.headline)
            
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("ai.settings.endpoint.name.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    TextField(text: self.$draft.name, prompt: Text(verbatim: self.namePlaceholder)) {
                        Text("ai.settings.endpoint.name.label", tableName: "AI")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlWidth)
                }
                
                GridRow {
                    Text("ai.settings.service.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
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
                    Text("ai.settings.protocol.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    Picker(selection: self.$draft.endpoint) {
                        ForEach(AIEndpoint.allCases, id: \.self) { endpoint in
                            Text(verbatim: endpoint.label).tag(endpoint)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help(Text(verbatim: self.draft.endpoint.hint))
                    .onChange(of: self.draft.endpoint) { _, _ in
                        self.models = []
                        self.fetchError = nil
                    }
                }
                
                GridRow {
                    Text("ai.settings.baseURL.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    TextField(text: self.$draft.baseURL, prompt: Text(verbatim: self.draft.endpoint.defaultBaseURL)) {
                        Text("ai.settings.baseURL.label", tableName: "AI")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlWidth)
                    .help(Text("ai.settings.baseURL.caption", tableName: "AI"))
                }
                
                GridRow {
                    Text("ai.settings.apiKey.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    SecureField(text: self.$apiKey, prompt: Text(verbatim: self.apiKeyPrompt)) {
                        Text("ai.settings.apiKey.label", tableName: "AI")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Self.controlWidth)
                    .disabled(!self.draft.endpoint.requiresAPIKey)
                    .help(Text("ai.settings.apiKey.caption", tableName: "AI"))
                }
                
                GridRow {
                    Text("ai.settings.model.label", tableName: "AI")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    HStack(spacing: 6) {
                        TextField(text: self.$draft.model, prompt: Text("ai.settings.model.custom", tableName: "AI")) {
                            Text("ai.settings.model.label", tableName: "AI")
                        }
                        .textFieldStyle(.roundedBorder)
                        
                        Menu {
                            ForEach(self.models) { model in
                                Button(model.name) { self.draft.model = model.id }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .disabled(self.models.isEmpty)
                        .help(Text("ai.settings.model.pick", tableName: "AI"))
                        
                        Button {
                            Task { await self.fetchModels() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .help(Text("ai.settings.model.fetch", tableName: "AI"))
                        .disabled(self.isFetchingModels || !self.canFetchModels)
                        
                        if self.isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: Self.controlWidth)
                }
                
                if let fetchError {
                    GridRow {
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                        
                        Text(fetchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: Self.controlWidth, alignment: .leading)
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 10) {
                Button {
                    Task { await self.testConnection() }
                } label: {
                    Text("ai.settings.test", tableName: "AI")
                }
                .disabled(self.isTesting || !self.canTest)
                
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
                
                Spacer()
                
                Button {
                    self.dismiss()
                } label: {
                    Text("ai.result.cancel", tableName: "AI")
                }
                .keyboardShortcut(.cancelAction)
                
                Button {
                    self.onSave(self.draft, self.apiKey)
                    self.dismiss()
                } label: {
                    Text("ai.settings.endpoint.save", tableName: "AI")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .task { await self.autoFetchModels() }
    }
    
    
    // MARK: Private Computed Properties
    
    /// Whether this sheet creates an endpoint or edits one.
    private var title: Text {
        
        self.isNew
            ? Text("ai.settings.endpoint.title.new", tableName: "AI")
            : Text("ai.settings.endpoint.title.edit", tableName: "AI")
    }
    
    
    /// The configuration the fields describe.
    private var configuration: AIConfiguration {
        
        self.draft.configuration(apiKey: self.apiKey)
    }
    
    
    /// The service picker's binding, so picking one also fills in what it decides.
    private var providerSelection: Binding<AIProvider> {
        
        Binding(get: { self.draft.provider }, set: { provider in
            guard provider != .custom else { return }
            
            self.draft.endpoint = provider.endpoint
            self.draft.baseURL = (provider.defaultBaseURL == provider.endpoint.defaultBaseURL) ? "" : provider.defaultBaseURL
            self.draft.model = ""
            self.models = []
            self.fetchError = nil
            self.testMessage = nil
        })
    }
    
    
    /// The placeholder for the name, which is optional.
    private var namePlaceholder: String {
        
        self.draft.provider.label
    }
    
    
    /// The placeholder for the key, since only hosted services need one.
    private var apiKeyPrompt: String {
        
        if self.draft.endpoint.requiresAPIKey {
            String(localized: "ai.settings.apiKey.prompt",
                   defaultValue: "sk-…",
                   table: "AI")
        } else {
            String(localized: "ai.settings.apiKey.prompt.local",
                   defaultValue: "Leave empty for local services",
                   table: "AI")
        }
    }
    
    
    /// Whether the service can be asked for its model list with the current input.
    private var canFetchModels: Bool {
        
        !self.draft.endpoint.requiresAPIKey
            || !self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
    /// Whether a connection can be tested, which needs a model to ask for.
    private var canTest: Bool {
        
        self.configuration.isUsable
    }
    
    
    // MARK: Private Methods
    
    /// Asks for the model list on open, when the endpoint is already complete enough to answer.
    private func autoFetchModels() async {
        
        guard self.canFetchModels, self.isNew || self.models.isEmpty else { return }
        
        await self.fetchModels()
    }
    
    
    /// Fetches the model list the endpoint offers.
    private func fetchModels() async {
        
        self.isFetchingModels = true
        self.fetchError = nil
        defer { self.isFetchingModels = false }
        
        do {
            self.models = try await AIService.shared.fetchModels(configuration: self.configuration)
        } catch {
            self.models = []
            self.fetchError = error.localizedDescription
        }
    }
    
    
    /// Asks the endpoint for a one-word reply to prove the values on screen work.
    private func testConnection() async {
        
        self.isTesting = true
        self.testMessage = nil
        defer { self.isTesting = false }
        
        do {
            let reply = try await AIService.shared.testConnection(configuration: self.configuration)
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
    AIEndpointEditorView(profile: AIEndpointProfile(), apiKey: "", isNew: true) { _, _ in }
}
