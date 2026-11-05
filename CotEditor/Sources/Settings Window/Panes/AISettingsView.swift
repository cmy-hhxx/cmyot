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
struct AISettingsView: View {
    
    // MARK: Private Properties
    
    @State private var endpoint: AIEndpoint = AIConfiguration.current.endpoint
    @State private var baseURL: String = AIConfiguration.current.baseURL
    @State private var model: String = AIConfiguration.current.model
    @State private var apiKey: String = AIConfiguration.current.apiKey
    
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false
    
    
    // MARK: View Methods
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow(alignment: .lastTextBaseline) {
                    Text("协议：")
                        .gridColumnAlignment(.trailing)
                    
                    Picker(selection: $endpoint) {
                        ForEach(AIEndpoint.allCases, id: \.self) { endpoint in
                            Text(endpoint.label).tag(endpoint)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    
                    Text(self.endpoint.hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                GridRow {
                    Text("接口地址：")
                        .gridColumnAlignment(.trailing)
                    
                    TextField(text: $baseURL, prompt: Text(self.endpoint.defaultBaseURL)) {
                        Text("接口地址")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                }
                
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    
                    Text("填到版本号为止（例如 \(self.endpoint.defaultBaseURL)）；粘贴完整接口地址也可以。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                GridRow {
                    Text("模型：")
                        .gridColumnAlignment(.trailing)
                    
                    TextField(text: $model, prompt: Text(self.modelPlaceholder)) {
                        Text("模型")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                }
                
                GridRow {
                    Text("API Key：")
                        .gridColumnAlignment(.trailing)
                    
                    SecureField(text: $apiKey, prompt: Text(self.endpoint.requiresAPIKey ? "sk-…" : "本地服务可留空")) {
                        Text("API Key")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                    .disabled(!self.endpoint.requiresAPIKey)
                }
                
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    
                    Text("密钥保存在系统钥匙串，不写进偏好文件，也不会随设置一起导出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(spacing: 10) {
                Button("测试连接") {
                    Task { await self.testConnection() }
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
            
            Divider()
            
            Text("配好之后，右键菜单里的「翻译 / 总结 / 说人话」就会直接使用这里的模型。后续的截图总结、补全、checklist 等功能也共用同一份配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: self.endpoint) { _, _ in self.save() }
        .onChange(of: self.baseURL) { _, _ in self.save() }
        .onChange(of: self.model) { _, _ in self.save() }
        .onChange(of: self.apiKey) { _, _ in self.save() }
        .scenePadding()
        .frame(width: 620)
    }
    
    
    // MARK: Private Computed Properties
    
    /// A hint for the model field, since the right name depends on the service.
    private var modelPlaceholder: String {
        
        switch self.endpoint {
            case .openAIResponses, .openAIChatCompletions: "例如 gpt-4o-mini、deepseek-chat"
            case .anthropicMessages: "例如 claude-sonnet-4-5"
            case .googleGemini: "例如 gemini-2.5-flash"
            case .ollama: "例如 qwen3:8b"
        }
    }
    
    
    // MARK: Private Methods
    
    /// Stores the configuration and clears the previous test result.
    private func save() {
        
        AIConfiguration(endpoint: self.endpoint,
                        baseURL: self.baseURL,
                        model: self.model,
                        apiKey: self.apiKey).save()
        
        self.testMessage = nil
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
            self.testMessage = "连接成功：\(reply)"
        } catch {
            self.testSucceeded = false
            self.testMessage = error.localizedDescription
        }
    }
}
