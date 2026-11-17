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
/// The pane is a list of configured services rather than one form, because a single
/// configuration forced every service to be retyped when switching between them: a hosted
/// endpoint, a gateway on the local network and a fallback can now sit side by side, and the one
/// in use is picked by selecting its row.
///
/// Editing happens in a sheet, so the list stays a list and the pane keeps its size however much
/// an endpoint needs. Every AI feature shares the service marked as in use, which is why this
/// pane is the one place AI is configured.
struct AISettingsView: View {
    
    // MARK: Private Properties
    
    private static let listHeight: CGFloat = 170
    
    @State private var profiles: [AIEndpointProfile] = []
    @State private var activeID: UUID?
    @State private var editingTarget: EditingTarget?
    @State private var pendingDeletion: AIEndpointProfile?
    @State private var status: [UUID: EndpointStatus] = [:]
    
    @State private var personaText: String = ""
    @State private var selectedStageAction: AIAction = .weeklyReport
    @State private var stagePromptText: String = ""
    @State private var typewriterEnabled: Bool = false
    @State private var vimCursorTrailEnabled: Bool = true
    @State private var plainTextImagesEnabled: Bool = true
    @State private var dbStatusMessage: String?
    @State private var isShowingStoredDocs = false
    
    
    // MARK: View Methods
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 14) {
            if self.profiles.isEmpty {
                self.emptyState
            } else {
                List(selection: self.activeSelection) {
                    ForEach(self.profiles) { profile in
                        AIEndpointRow(profile: profile,
                                      isActive: profile.id == self.activeID,
                                      status: self.status[profile.id],
                                      onTest: { Task { await self.test(profile) } },
                                      onEdit: { self.beginEditing(profile) },
                                      onDelete: { self.pendingDeletion = profile })
                            .tag(profile.id)
                    }
                }
                .frame(height: Self.listHeight)
                .listStyle(.inset)
            }
            
            HStack(spacing: 12) {
                Button {
                    self.beginAdding()
                } label: {
                    Label {
                        Text("ai.settings.endpoint.add", tableName: "AI")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                
                Spacer()
                
                if !self.profiles.isEmpty {
                    Text("ai.settings.endpoint.hint", tableName: "AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            self.databaseAndPersonaSection
        }
        .frame(width: 620)
        .scenePadding()
        .task { self.reload() }
        .sheet(item: self.$editingTarget) { target in
            AIEndpointEditorView(profile: target.profile, apiKey: target.apiKey, isNew: target.isNew) { profile, apiKey in
                self.save(profile, apiKey: apiKey)
            }
        }
        .sheet(isPresented: self.$isShowingStoredDocs) {
            StoredDocumentsSheetView()
        }
        .alert(Text("ai.settings.endpoint.delete.confirm", tableName: "AI"),
               isPresented: self.isDeleteAlertPresented) {
            Button(role: .destructive) {
                guard let profile = self.pendingDeletion else { return }
                self.delete(profile)
            } label: {
                Text("ai.settings.endpoint.delete", tableName: "AI")
            }
            Button(role: .cancel) {} label: {
                Text("ai.result.cancel", tableName: "AI")
            }
        } message: {
            Text("ai.settings.endpoint.delete.caption", tableName: "AI")
        }
    }
    
    
    // MARK: Database, Persona & Stage Prompts Section
    
    private var databaseAndPersonaSection: some View {
        
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("AI Persona:")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 90, alignment: .trailing)
                    
                    TextField("自定义 AI 角色人设（如：严谨资深架构师 / 简练周报秘书）", text: self.$personaText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: self.personaText) { _, newValue in
                            CotLocalDatabase.shared.aiPersona = newValue
                        }
                }
                
                GridRow {
                    Text("阶段提示词:")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 90, alignment: .trailing)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Picker("", selection: self.$selectedStageAction) {
                                ForEach(AIAction.allCases, id: \.self) { action in
                                    Text(action.title).tag(action)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: self.selectedStageAction) { _, newAction in
                                self.loadStagePrompt(for: newAction)
                            }
                            
                            Button("恢复默认") {
                                let defaultPrompt = self.selectedStageAction.defaultSystemPrompt
                                self.stagePromptText = defaultPrompt
                                CotLocalDatabase.shared.set(defaultPrompt, forKey: self.selectedStageAction.databaseConfigKey)
                            }
                            .controlSize(.small)
                            
                            Spacer()
                        }
                        
                        TextEditor(text: self.$stagePromptText)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 68)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                            .onChange(of: self.stagePromptText) { _, newValue in
                                CotLocalDatabase.shared.set(newValue, forKey: self.selectedStageAction.databaseConfigKey)
                            }
                    }
                }
                
                GridRow {
                    Text("趣味与扩展:")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 90, alignment: .trailing)
                    
                    HStack(spacing: 16) {
                        Toggle("打字机效果 (音效+粒子)", isOn: self.$typewriterEnabled)
                            .onChange(of: self.typewriterEnabled) { _, val in
                                CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                                UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                            }
                        Toggle("Vim 炫酷光标拖尾", isOn: self.$vimCursorTrailEnabled)
                            .onChange(of: self.vimCursorTrailEnabled) { _, val in
                                CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                                UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                            }
                        Toggle("纯文本内嵌图片预览", isOn: self.$plainTextImagesEnabled)
                            .onChange(of: self.plainTextImagesEnabled) { _, val in
                                CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                                UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                            }
                    }
                    .controlSize(.small)
                }
                
                GridRow {
                    Text("本地数据库:")
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 90, alignment: .trailing)
                    
                    HStack(spacing: 8) {
                        Button {
                            self.isShowingStoredDocs = true
                        } label: {
                            Label("文档与配置库 (\(CotLocalDatabase.shared.documents.count))", systemImage: "cylinder.split.1x2")
                        }
                        
                        Button {
                            self.exportLocalDatabase()
                        } label: {
                            Label("导出 DB…", systemImage: "square.and.arrow.up")
                        }
                        
                        Button {
                            self.importLocalDatabase()
                        } label: {
                            Label("导入 DB…", systemImage: "square.and.arrow.down")
                        }
                        
                        if let dbStatusMessage {
                            Text(dbStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
    
    
    // MARK: Private Computed Properties
    
    /// What is shown before any endpoint exists.
    private var emptyState: some View {
        
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("ai.settings.endpoint.empty", tableName: "AI")
                .foregroundStyle(.secondary)
            Text("ai.settings.endpoint.empty.caption", tableName: "AI")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.listHeight)
    }
    
    
    /// The list selection, which is the endpoint in use.
    ///
    /// A deselection is ignored: the list always has one row selected while it has any, so the
    /// AI features never lose the service they are pointed at.
    private var activeSelection: Binding<UUID?> {
        
        Binding(get: { self.activeID }, set: { newValue in
            guard let newValue, newValue != self.activeID else { return }
            
            self.activeID = newValue
            AIEndpointStore.activeID = newValue
        })
    }
    
    
    /// Whether the delete alert is up.
    private var isDeleteAlertPresented: Binding<Bool> {
        
        Binding(get: { self.pendingDeletion != nil },
                set: { if !$0 { self.pendingDeletion = nil } })
    }
    
    
    // MARK: Private Methods
    
    /// Reads the stored list, importing a configuration saved before the list existed.
    private func reload() {
        
        AIEndpointStore.migrateLegacyConfigurationIfNeeded()
        self.profiles = AIEndpointStore.profiles
        
        let activeID = AIEndpointStore.activeID ?? self.profiles.first?.id
        self.activeID = activeID
        if let activeID, AIEndpointStore.activeID != activeID {
            AIEndpointStore.activeID = activeID
        }
        
        let db = CotLocalDatabase.shared
        self.personaText = db.aiPersona
        self.loadStagePrompt(for: self.selectedStageAction)
        self.typewriterEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled, default: false)
        self.vimCursorTrailEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled, default: true)
        self.plainTextImagesEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled, default: true)
    }
    
    
    private func loadStagePrompt(for action: AIAction) {
        
        self.stagePromptText = CotLocalDatabase.shared.customStagePrompt(forKey: action.databaseConfigKey)
            ?? action.defaultSystemPrompt
    }
    
    
    private func exportLocalDatabase() {
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "cot-backup.sqlite3"
        savePanel.canCreateDirectories = true
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task { @MainActor in
                do {
                    try CotLocalDatabase.shared.exportDatabase(to: url)
                    self.dbStatusMessage = "✓ 已导出到 \(url.lastPathComponent)"
                } catch {
                    self.dbStatusMessage = "导出失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    
    private func importLocalDatabase() {
        
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                do {
                    try CotLocalDatabase.shared.importDatabase(from: url)
                    self.reload()
                    self.dbStatusMessage = "✓ 已从 \(url.lastPathComponent) 同步配置与文档"
                } catch {
                    self.dbStatusMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    
    /// Opens the sheet on a new endpoint.
    private func beginAdding() {
        
        self.editingTarget = EditingTarget(profile: AIEndpointProfile(), apiKey: "", isNew: true)
    }
    
    
    /// Opens the sheet on an existing endpoint.
    ///
    /// - Parameter profile: The profile to edit.
    private func beginEditing(_ profile: AIEndpointProfile) {
        
        self.editingTarget = EditingTarget(profile: profile,
                                           apiKey: AIEndpointStore.apiKey(for: profile),
                                           isNew: false)
    }
    
    
    /// Stores the endpoint the sheet returned.
    ///
    /// - Parameters:
    ///   - profile: The edited profile.
    ///   - apiKey: Its key.
    private func save(_ profile: AIEndpointProfile, apiKey: String) {
        
        AIEndpointStore.save(profile, apiKey: apiKey)
        
        if self.activeID == nil {
            self.activeID = profile.id
            AIEndpointStore.activeID = profile.id
        }
        
        self.status[profile.id] = nil
        self.reload()
    }
    
    
    /// Removes an endpoint and forgets its test result.
    ///
    /// - Parameter profile: The profile to remove.
    private func delete(_ profile: AIEndpointProfile) {
        
        AIEndpointStore.delete(id: profile.id)
        self.status[profile.id] = nil
        self.pendingDeletion = nil
        self.reload()
    }
    
    
    /// Tests one endpoint, without making it the one in use.
    ///
    /// - Parameter profile: The profile to try.
    private func test(_ profile: AIEndpointProfile) async {
        
        self.status[profile.id] = .running
        
        do {
            let reply = try await AIService.shared.testConnection(
                configuration: profile.configuration(apiKey: AIEndpointStore.apiKey(for: profile))
            )
            self.status[profile.id] = .succeeded(reply)
        } catch {
            self.status[profile.id] = .failed(error.localizedDescription)
        }
    }
}


// MARK: -

/// The result of testing one endpoint.
private enum EndpointStatus: Equatable {
    
    case running
    case succeeded(String)
    case failed(String)
}


// MARK: -

/// What the sheet is open on.
private struct EditingTarget: Identifiable {
    
    var profile: AIEndpointProfile
    var apiKey: String
    var isNew: Bool
    
    var id: UUID { self.profile.id }
}


// MARK: -

/// One row of the endpoint list.
private struct AIEndpointRow: View {
    
    let profile: AIEndpointProfile
    let isActive: Bool
    let status: EndpointStatus?
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    
    var body: some View {
        
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(self.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(self.profile.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    if self.isActive {
                        Text("ai.settings.endpoint.inUse", tableName: "AI")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.tint.opacity(0.15)))
                    }
                }
                
                Text(self.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer(minLength: 8)
            
            self.statusView
            
            HStack(spacing: 4) {
                Button(action: self.onTest) {
                    Image(systemName: "play.circle")
                }
                .help(Text("ai.settings.endpoint.test", tableName: "AI"))
                
                Button(action: self.onEdit) {
                    Image(systemName: "pencil")
                }
                .help(Text("ai.settings.endpoint.edit", tableName: "AI"))
                
                Button(action: self.onDelete) {
                    Image(systemName: "trash")
                }
                .help(Text("ai.settings.endpoint.delete", tableName: "AI"))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
    
    
    /// The address and the model, which is what tells two endpoints on the same service apart.
    private var detail: String {
        
        let address = self.profile.resolvedBaseURL
        guard let model = self.profile.displayModel else {
            let missing = String(localized: "ai.settings.model.missing",
                                 defaultValue: "No model selected",
                                 table: "AI")
            
            return "\(address) · \(missing)"
        }
        
        return "\(address) · \(model)"
    }
    
    
    @ViewBuilder private var statusView: some View {
        
        switch self.status {
            case .running:
                ProgressView()
                    .controlSize(.small)
            case .succeeded(let reply):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(reply)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(message)
            case .none:
                EmptyView()
        }
    }
}


// MARK: - Stored Documents & Custom Config Sheet

private struct StoredDocumentsSheetView: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var newConfigKey = ""
    @State private var newConfigValue = ""
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本地 SQLite 数据库管理")
                    .font(.headline)
                Spacer()
                Picker("", selection: self.$selectedTab) {
                    Text("已存文档 (\(CotLocalDatabase.shared.documents.count))").tag(0)
                    Text("键值配置接口 (\(CotLocalDatabase.shared.configEntries.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            
            if self.selectedTab == 0 {
                List {
                    ForEach(CotLocalDatabase.shared.documents) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .fontWeight(.medium)
                                Text("\(record.syntax) · \(record.content.count) 字 · \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("打开为新标签") {
                                _ = try? (NSDocumentController.shared as? DocumentController)?
                                    .openUntitledDocument(content: record.content, title: record.title, display: true)
                                self.dismiss()
                            }
                            .controlSize(.small)
                            
                            Button(role: .destructive) {
                                CotLocalDatabase.shared.deleteDocument(id: record.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(height: 280)
            } else {
                List {
                    ForEach(CotLocalDatabase.shared.configEntries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .frame(width: 180, alignment: .leading)
                            Text(entry.value)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                CotLocalDatabase.shared.removeConfig(forKey: entry.key)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(height: 240)
                
                HStack(spacing: 8) {
                    TextField("配置 Key (如 custom.signature)", text: self.$newConfigKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                    TextField("配置 Value", text: self.$newConfigValue)
                        .textFieldStyle(.roundedBorder)
                    Button("写入 DB") {
                        let key = self.newConfigKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        CotLocalDatabase.shared.set(self.newConfigValue, forKey: key)
                        self.newConfigKey = ""
                        self.newConfigValue = ""
                    }
                    .disabled(self.newConfigKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            HStack {
                Text(CotLocalDatabase.shared.databaseURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("完成") {
                    self.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}


// MARK: - Preview

#Preview {
    AISettingsView()
}
