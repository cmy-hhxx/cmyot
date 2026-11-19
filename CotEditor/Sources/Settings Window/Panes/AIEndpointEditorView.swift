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
    @State private var isAPIKeyVisible = false
    @State private var customHeadersText: String
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
        let formattedHeaders = profile.customHeaders
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let value = profile.customHeaders[key], !value.isEmpty else { return nil }
                return "\(key): \(value)"
            }
            .joined(separator: "\n")
        self._customHeadersText = State(initialValue: formattedHeaders)
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
                    
                    HStack(spacing: 6) {
                        Group {
                            if self.isAPIKeyVisible {
                                TextField(text: self.$apiKey, prompt: Text(verbatim: self.apiKeyPrompt)) {
                                    Text("ai.settings.apiKey.label", tableName: "AI")
                                }
                            } else {
                                SecureField(text: self.$apiKey, prompt: Text(verbatim: self.apiKeyPrompt)) {
                                    Text("ai.settings.apiKey.label", tableName: "AI")
                                }
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .disabled(!self.draft.endpoint.requiresAPIKey)
                        .help(Text("ai.settings.apiKey.caption", tableName: "AI"))
                        
                        Button {
                            self.isAPIKeyVisible.toggle()
                        } label: {
                            Image(systemName: self.isAPIKeyVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!self.draft.endpoint.requiresAPIKey)
                        .help(self.isAPIKeyVisible ? "隐藏 API Key" : "显示 API Key")
                    }
                    .frame(width: Self.controlWidth)
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
                            if !self.models.isEmpty {
                                Section("已从接口获取") {
                                    ForEach(self.models) { model in
                                        Button(model.name) {
                                            self.draft.model = model.id
                                            self.draft.rememberModels([model.id])
                                        }
                                    }
                                }
                            }
                            if !self.draft.availableModelIDs.isEmpty {
                                Section("常用 / 已保存模型") {
                                    ForEach(self.draft.availableModelIDs, id: \.self) { id in
                                        Button(id) { self.draft.model = id }
                                    }
                                }
                            }
                            Section("推荐快捷模型") {
                                ForEach(Self.quickPresetModels, id: \.self) { id in
                                    Button(id) {
                                        self.draft.model = id
                                        self.draft.rememberModels([id])
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
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
                
                GridRow {
                    Text("推理深度")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    Picker(selection: Binding(
                        get: { self.draft.reasoningEffort ?? "low" },
                        set: { self.draft.reasoningEffort = $0 }
                    )) {
                        Text("极速 (low)").tag("low")
                        Text("关闭 (none)").tag("none")
                        Text("均衡 (medium)").tag("medium")
                        Text("深度 (high)").tag("high")
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                
                GridRow {
                    Text("自定义请求头")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 76, alignment: .trailing)
                    
                    TextEditor(text: self.$customHeadersText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: Self.controlWidth, height: 48)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                        .help("每行一个请求头，例如：x-opencode-session: omp-opencode-go-1")
                }
                
                if let fetchError {
                    GridRow {
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                        
                        Text(fetchError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(fetchError)
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(testMessage)
                }
                
                Spacer()
                
                Button {
                    self.dismiss()
                } label: {
                    Text("ai.result.cancel", tableName: "AI")
                }
                .keyboardShortcut(.cancelAction)
                
                Button {
                    self.onSave(self.preparedDraft(), self.apiKey)
                    self.dismiss()
                } label: {
                    Text("ai.settings.endpoint.save", tableName: "AI")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .environment(\.locale, AppLanguage.current.locale)
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
        
        self.preparedDraft().configuration(apiKey: self.apiKey)
    }
    
    
    private static let quickPresetModels: [String] = [
        "claude-haiku-5-5",
        "claude-sonnet-5-5",
        "deepseek-v4.1-flash",
        "deepseek/deepseek-v4.1-flash",
        "deepseek/deepseek-v4.1-flash-fast",
        "qwen4-max",
        "glm-5.3",
    ]
    
    
    private func preparedDraft() -> AIEndpointProfile {
        
        var copy = self.draft
        copy.customHeaders = Self.parseHeaders(self.customHeadersText)
        let currentModel = copy.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentModel.isEmpty {
            copy.model = currentModel
            copy.rememberModels([currentModel])
        }
        return copy
    }
    
    
    private static func parseHeaders(_ raw: String) -> [String: String] {
        
        var result: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
    
    
    /// The service picker's binding, so picking one also fills in what it decides.
    private var providerSelection: Binding<AIProvider> {
        
        Binding(get: { self.draft.provider }, set: { provider in
            guard provider != .custom else { return }
            
            self.draft.endpoint = provider.endpoint
            self.draft.baseURL = (provider.defaultBaseURL == provider.endpoint.defaultBaseURL) ? "" : provider.defaultBaseURL
            self.draft.model = provider.defaultModel
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
            let fetched = try await AIService.shared.fetchModels(configuration: self.configuration)
            self.models = fetched
            self.draft.rememberModels(fetched.prefix(12).map(\.id))
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
