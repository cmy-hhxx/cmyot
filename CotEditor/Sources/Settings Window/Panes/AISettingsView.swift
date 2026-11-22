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

import AppKit
import SwiftUI

/// The AI pane of the settings window.
///
/// Renders endpoints directly inside the grouped `Form` (no nested `List` scroll view)
/// so trackpad and mouse-wheel scrolling across the whole Settings window never traps or stalls.
struct AISettingsView: View {
    
    // MARK: Private Properties
    
    private static let quickProviders: [AIProvider] = [
        .openAI, .anthropic, .deepSeek, .qwen, .moonshot, .openRouter, .google, .ollama,
    ]
    
    private static let nextTokenModelPresets: [String] = [
        "deepseek-chat",
        "qwen-turbo",
        "gpt-4o-mini",
        "gemini-2.5-flash",
        "claude-3-5-haiku-latest",
    ]
    
    @State private var profiles: [AIEndpointProfile] = []
    @State private var activeID: UUID?
    @State private var editingTarget: EditingTarget?
    @State private var pendingDeletion: AIEndpointProfile?
    @State private var status: [UUID: EndpointStatus] = [:]
    @State private var fetchedModels: [UUID: [AIModel]] = [:]
    @State private var fetchingModelsIDs: Set<UUID> = []
    
    @State private var inlineCompletionEnabled: Bool = true
    @State private var aiNextTokenEnabled: Bool = true
    @State private var aiNextTokenStrategy: AINextTokenStrategy = .smart
    @State private var aiNextTokenModelOverride: String = ""
    @State private var aiNextTokenDebounceMs: Int = 420
    @State private var aiNextTokenDailyCap: Int = 300
    @State private var todayStats: AINextTokenDailyStats = AINextTokenPredictor.shared.todayStats
    
    @State private var dbStatusMessage: String?
    @State private var isShowingStoredDocs = false
    
    
    // MARK: View Methods
    
    var body: some View {
        
        SettingsFormPane {
            Section {
                if self.profiles.isEmpty {
                    self.emptyState
                } else {
                    ForEach(self.profiles) { profile in
                        AIEndpointRow(
                            profile: profile,
                            isActive: profile.id == self.activeID,
                            status: self.status[profile.id],
                            fetchedModels: self.fetchedModels[profile.id] ?? [],
                            isFetchingModels: self.fetchingModelsIDs.contains(profile.id),
                            onActivate: { self.activate(profile) },
                            onSelectModel: { modelID in self.switchModel(modelID, on: profile) },
                            onFetchModels: { Task { await self.fetchModels(for: profile) } },
                            onTest: { Task { await self.test(profile) } },
                            onDuplicate: { self.duplicate(profile) },
                            onEdit: { self.beginEditing(profile) },
                            onDelete: { self.pendingDeletion = profile }
                        )
                    }
                }
                
                HStack(spacing: 10) {
                    Button {
                        self.beginAdding()
                    } label: {
                        Label("添加端点", systemImage: "plus")
                    }
                    
                    Menu {
                        ForEach(Self.quickProviders, id: \.self) { provider in
                            Button(provider.label) {
                                self.beginAdding(preset: provider)
                            }
                        }
                    } label: {
                        Text("从模板新建")
                    }
                    .fixedSize()
                    
                    Spacer()
                    
                    if let active = self.profiles.first(where: { $0.id == self.activeID }) {
                        Text("当前生效：\(active.displayName) · \(active.displayModel ?? "未选模型")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } header: {
                Label("AI 服务端点", systemImage: "sparkles")
            }
            
            Section {
                Toggle("启用行内智能续写 (Ghost Text)", isOn: self.$inlineCompletionEnabled)
                    .lineLimit(1)
                    .onChange(of: self.inlineCompletionEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled)
                    }
                
                Toggle("接入 AI 大模型深度预测", isOn: self.$aiNextTokenEnabled)
                    .lineLimit(1)
                    .disabled(!self.inlineCompletionEnabled)
                    .onChange(of: self.aiNextTokenEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled)
                    }
                
                Picker("续写省流策略:", selection: self.$aiNextTokenStrategy) {
                    Text("智能省流 (推荐)").tag(AINextTokenStrategy.smart)
                    Text("积极伴写").tag(AINextTokenStrategy.proactive)
                }
                .pickerStyle(.segmented)
                .disabled(!self.inlineCompletionEnabled || !self.aiNextTokenEnabled)
                .onChange(of: self.aiNextTokenStrategy) { _, strategy in
                    CotLocalDatabase.shared.set(strategy.rawValue, forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
                    UserDefaults.standard.set(strategy.rawValue, forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
                }
                
                LabeledContent {
                    HStack(spacing: 6) {
                        TextField(text: self.$aiNextTokenModelOverride, prompt: Text("留空则自动路由轻量省流模型"), label: EmptyView.init)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .onChange(of: self.aiNextTokenModelOverride) { _, val in
                                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                                CotLocalDatabase.shared.set(trimmed, forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
                                UserDefaults.standard.set(trimmed, forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
                            }
                        
                        if !self.aiNextTokenModelOverride.isEmpty {
                            Button {
                                self.aiNextTokenModelOverride = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("恢复智能自动省流路由")
                        }
                        
                        Menu {
                            Button("智能自动省流路由（推荐）") {
                                self.aiNextTokenModelOverride = ""
                            }
                            if let active = self.profiles.first(where: { $0.id == self.activeID }) {
                                let discovered = active.savedModels.filter { AINextTokenPredictor.isLightweightModel($0) }
                                if !discovered.isEmpty {
                                    Divider()
                                    Section("当前端点可用轻量模型") {
                                        ForEach(discovered, id: \.self) { modelID in
                                            Button(modelID) {
                                                self.aiNextTokenModelOverride = modelID
                                            }
                                        }
                                    }
                                }
                            }
                            Divider()
                            ForEach(Self.nextTokenModelPresets, id: \.self) { modelID in
                                Button(modelID) {
                                    self.aiNextTokenModelOverride = modelID
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("快速选择轻量极速模型")
                    }
                    .frame(width: 360)
                    .disabled(!self.inlineCompletionEnabled || !self.aiNextTokenEnabled)
                } label: {
                    Text("续写专用模型:")
                        .lineLimit(1)
                }
                
                Picker("AI 触发节奏:", selection: self.$aiNextTokenDebounceMs) {
                    Text("灵敏 (280ms)").tag(280)
                    Text("均衡 (420ms)").tag(420)
                    Text("沉稳 (680ms)").tag(680)
                }
                .pickerStyle(.segmented)
                .disabled(!self.inlineCompletionEnabled || !self.aiNextTokenEnabled)
                .onChange(of: self.aiNextTokenDebounceMs) { _, val in
                    CotLocalDatabase.shared.set("\(val)", forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs)
                    UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs)
                }
                
                Picker("每日 AI 预算上限:", selection: self.$aiNextTokenDailyCap) {
                    Text("100 次/天 (极省)").tag(100)
                    Text("300 次/天 (推荐)").tag(300)
                    Text("800 次/天").tag(800)
                    Text("不限次数").tag(0)
                }
                .disabled(!self.inlineCompletionEnabled || !self.aiNextTokenEnabled)
                .onChange(of: self.aiNextTokenDailyCap) { _, val in
                    CotLocalDatabase.shared.set("\(val)", forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap)
                    UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    let activeResolution = self.nextTokenRoutingResolution
                    let statusDesc = self.nextTokenStatusDescription(resolution: activeResolution)
                    HStack(spacing: 6) {
                        Image(systemName: self.nextTokenStatusSymbol(resolution: activeResolution))
                            .foregroundStyle(self.nextTokenStatusColor(resolution: activeResolution))
                            .font(.caption)
                        Text(statusDesc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(statusDesc)
                    }
                    
                    HStack(spacing: 8) {
                        let capText = self.aiNextTokenDailyCap > 0 ? "/\(self.aiNextTokenDailyCap)" : ""
                        Text("今日账本：AI 请求 \(self.todayStats.aiRequests)\(capText) 次（约 \(self.todayStats.totalEstimatedTokens) Tokens） · 本地 0 成本命中 \(self.todayStats.localHits) 次")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        if self.todayStats.aiRequests > 0 || self.todayStats.localHits > 0 {
                            Button("重置") {
                                AINextTokenPredictor.shared.resetTodayStats()
                                self.todayStats = AINextTokenPredictor.shared.todayStats
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2)
                        }
                        
                        Spacer(minLength: 4)
                        
                        Text("按 Tab 采纳 · Esc 隐藏")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } header: {
                Label("AI 智能续写 (Next Token 预测)", systemImage: "wand.and.stars.inverse")
            }
            
            Section {
                LabeledContent {
                    Button("查看管理…") {
                        self.isShowingStoredDocs = true
                    }
                } label: {
                    Label("文档与配置 (\(CotLocalDatabase.shared.documents.count))", systemImage: "cylinder.split.1x2")
                }
                
                LabeledContent {
                    Button("打开周报库…") {
                        WeeklyReportWindowController.shared.showWindow(mode: .history)
                    }
                } label: {
                    Label("历史周报库 (\(CotLocalDatabase.shared.weeklyReports.count))", systemImage: "calendar.badge.clock")
                }
                
                LabeledContent {
                    HStack(spacing: 8) {
                        Button("导出 DB…") {
                            self.exportLocalDatabase()
                        }
                        Button("导入 DB…") {
                            self.importLocalDatabase()
                        }
                    }
                } label: {
                    Label("数据备份与迁移", systemImage: "externaldrive")
                }
                
                if let dbStatusMessage {
                    Text(dbStatusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("本地数据库", systemImage: "internaldrive")
            }
        }
        .task { self.reload() }
        .onReceive(NotificationCenter.default.publisher(for: AINextTokenPredictor.statsDidChangeNotification)) { _ in
            self.todayStats = AINextTokenPredictor.shared.todayStats
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
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
    
    
    // MARK: Private Computed Properties
    
    /// What is shown before any endpoint exists.
    private var emptyState: some View {
        
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text("暂未配置 AI 服务端点")
                .font(.callout.weight(.medium))
            Text("点击下方按钮快速接入 OpenAI、Claude、DeepSeek、通义千问或本地 Ollama。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    
    private var nextTokenRoutingResolution: (config: AIConfiguration, routing: ModelRoutingResolution) {
        
        let activeProfile = self.profiles.first(where: { $0.id == self.activeID })
        let baseConfig = activeProfile.map { $0.configuration(apiKey: AIEndpointStore.apiKey(for: $0)) }
            ?? AIConfiguration.current
        let routing = AINextTokenPredictor.shared.resolveModelRouting(
            profile: activeProfile,
            baseConfig: baseConfig,
            explicitOverride: self.aiNextTokenModelOverride
        )
        var effectiveConfig = baseConfig
        if !routing.effectiveModel.isEmpty {
            effectiveConfig.model = routing.effectiveModel
        }
        return (effectiveConfig, routing)
    }
    
    
    private func nextTokenStatusSymbol(resolution: (config: AIConfiguration, routing: ModelRoutingResolution)) -> String {
        
        guard self.inlineCompletionEnabled, self.aiNextTokenEnabled else { return "bolt.slash.circle" }
        if resolution.routing.isReasoningBlocked { return "bolt.badge.clock.fill" }
        return resolution.config.isUsable ? "checkmark.circle.fill" : "bolt.slash.circle"
    }
    
    
    private func nextTokenStatusColor(resolution: (config: AIConfiguration, routing: ModelRoutingResolution)) -> Color {
        
        guard self.inlineCompletionEnabled, self.aiNextTokenEnabled else { return .secondary }
        if resolution.routing.isReasoningBlocked { return .orange }
        return resolution.config.isUsable ? .green : .secondary
    }
    
    
    private func nextTokenStatusDescription(resolution: (config: AIConfiguration, routing: ModelRoutingResolution)) -> String {
        
        guard self.inlineCompletionEnabled else { return "行内智能续写已关闭" }
        guard self.aiNextTokenEnabled else { return "仅使用本地习惯与跨标签上下文零延迟续写（0 Token）" }
        
        if let note = resolution.routing.statusNote, resolution.routing.isReasoningBlocked {
            return note
        }
        if !resolution.config.isUsable {
            return "尚未配置可用端点，自动回退为本地上下文续写"
        }
        if self.aiNextTokenDailyCap > 0, self.todayStats.aiRequests >= self.aiNextTokenDailyCap {
            return "已达今日 \(self.aiNextTokenDailyCap) 次 AI 预算上限，已自动转为本地 0 成本续写"
        }
        if resolution.routing.isAutoRouted {
            return "智能省流就绪：\(resolution.routing.effectiveModel)（已从 \(resolution.routing.baseModel) 自动降本路由）"
        }
        if let note = resolution.routing.statusNote {
            return "\(resolution.routing.effectiveModel)：\(note)"
        }
        return "深度续写就绪：\(resolution.routing.effectiveModel)"
    }
    
    
    /// Whether the delete alert is up.
    private var isDeleteAlertPresented: Binding<Bool> {
        
        Binding(get: { self.pendingDeletion != nil },
                set: { if !$0 { self.pendingDeletion = nil } })
    }
    
    
    // MARK: Private Methods
    
    /// Reads the stored list and Next Token settings.
    private func reload() {
        
        AIEndpointStore.migrateLegacyConfigurationIfNeeded()
        self.profiles = AIEndpointStore.profiles
        
        let activeID = AIEndpointStore.activeID ?? self.profiles.first?.id
        self.activeID = activeID
        if let activeID, AIEndpointStore.activeID != activeID {
            AIEndpointStore.activeID = activeID
        }
        
        let db = CotLocalDatabase.shared
        self.inlineCompletionEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled, default: true)
        self.aiNextTokenEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled, default: true)
        let rawStrategy = db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy, default: AINextTokenStrategy.smart.rawValue)
        self.aiNextTokenStrategy = AINextTokenStrategy(rawValue: rawStrategy) ?? .smart
        self.aiNextTokenModelOverride = db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride, default: "")
        let rawDebounce = db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs, default: "420")
        let parsedDebounce = Int(rawDebounce) ?? 420
        self.aiNextTokenDebounceMs = [280, 420, 680].contains(parsedDebounce) ? parsedDebounce : 420
        let rawCap = db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap, default: "300")
        let parsedCap = Int(rawCap) ?? 300
        self.aiNextTokenDailyCap = [0, 100, 300, 800].contains(parsedCap) ? parsedCap : 300
        self.todayStats = AINextTokenPredictor.shared.todayStats
    }
    
    
    private func activate(_ profile: AIEndpointProfile) {
        
        self.activeID = profile.id
        AIEndpointStore.activeID = profile.id
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
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
    
    
    /// Opens the sheet on a new endpoint, optionally seeded from a provider template.
    private func beginAdding(preset provider: AIProvider? = nil) {
        
        let profile: AIEndpointProfile
        if let provider, provider != .custom {
            profile = AIEndpointProfile(
                name: provider.label,
                endpoint: provider.endpoint,
                baseURL: provider.defaultBaseURL,
                model: provider.defaultModel
            )
        } else {
            profile = AIEndpointProfile()
        }
        self.editingTarget = EditingTarget(profile: profile, apiKey: "", isNew: true)
    }
    
    
    /// Opens the sheet on an existing endpoint.
    private func beginEditing(_ profile: AIEndpointProfile) {
        
        self.editingTarget = EditingTarget(
            profile: profile,
            apiKey: AIEndpointStore.apiKey(for: profile),
            isNew: false
        )
    }
    
    
    /// Duplicates an existing endpoint (including its API key and headers) and opens the editor sheet.
    private func duplicate(_ profile: AIEndpointProfile) {
        
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.displayName) 副本"
        let apiKey = AIEndpointStore.apiKey(for: profile)
        self.editingTarget = EditingTarget(profile: copy, apiKey: apiKey, isNew: true)
    }
    
    
    /// Stores the endpoint the sheet returned.
    private func save(_ profile: AIEndpointProfile, apiKey: String) {
        
        AIEndpointStore.save(profile, apiKey: apiKey)
        
        if self.activeID == nil {
            self.activeID = profile.id
            AIEndpointStore.activeID = profile.id
        }
        
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        self.status[profile.id] = nil
        self.reload()
    }
    
    
    /// Switches the model ID on one saved endpoint without re-entering its key.
    private func switchModel(_ modelID: String, on profile: AIEndpointProfile) {
        
        var updated = profile
        updated.model = modelID
        updated.rememberModels([modelID])
        let apiKey = AIEndpointStore.apiKey(for: profile)
        AIEndpointStore.save(updated, apiKey: apiKey)
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        self.status[profile.id] = nil
        self.reload()
    }
    
    
    /// Fetches available models directly from the endpoint row.
    private func fetchModels(for profile: AIEndpointProfile) async {
        
        self.fetchingModelsIDs.insert(profile.id)
        defer { self.fetchingModelsIDs.remove(profile.id) }
        
        let config = profile.configuration(apiKey: AIEndpointStore.apiKey(for: profile))
        do {
            let models = try await AIService.shared.fetchModels(configuration: config)
            self.fetchedModels[profile.id] = models
            var updated = profile
            updated.rememberModels(models.prefix(12).map(\.id))
            AIEndpointStore.save(updated, apiKey: AIEndpointStore.apiKey(for: profile))
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
            self.reload()
        } catch {
            self.status[profile.id] = .failed("拉取模型列表失败：\(error.localizedDescription)")
        }
    }
    
    
    /// Removes an endpoint and forgets its test result.
    private func delete(_ profile: AIEndpointProfile) {
        
        AIEndpointStore.delete(id: profile.id)
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        self.status[profile.id] = nil
        self.fetchedModels[profile.id] = nil
        self.pendingDeletion = nil
        self.reload()
    }
    
    
    /// Tests one endpoint and records response latency + inline diagnostic status.
    private func test(_ profile: AIEndpointProfile) async {
        
        self.status[profile.id] = .running
        let clock = ContinuousClock()
        let start = clock.now
        
        do {
            let reply = try await AIService.shared.testConnection(
                configuration: profile.configuration(apiKey: AIEndpointStore.apiKey(for: profile))
            )
            let elapsed = start.duration(to: clock.now)
            let ms = Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            self.status[profile.id] = .succeeded(reply, latencyMs: max(1, ms))
        } catch {
            self.status[profile.id] = .failed(error.localizedDescription)
        }
    }
}


// MARK: -

/// The result of testing one endpoint.
private enum EndpointStatus: Equatable {
    
    case running
    case succeeded(String, latencyMs: Int)
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

/// One row of the endpoint section (non-scrollable container row so outer Form scrolls seamlessly).
private struct AIEndpointRow: View {
    
    private static let alternativeModels: [String] = [
        "claude-haiku-5-5",
        "claude-sonnet-5-5",
        "deepseek-v4.1-flash",
        "deepseek/deepseek-v4.1-flash",
        "deepseek/deepseek-v4.1-flash-fast",
        "qwen4-max",
        "glm-5.3",
    ]
    
    let profile: AIEndpointProfile
    let isActive: Bool
    let status: EndpointStatus?
    let fetchedModels: [AIModel]
    let isFetchingModels: Bool
    let onActivate: () -> Void
    let onSelectModel: (String) -> Void
    let onFetchModels: () -> Void
    let onTest: () -> Void
    let onDuplicate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: self.onActivate) {
                    HStack(spacing: 10) {
                        Image(systemName: self.isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(self.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .frame(width: 18)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(self.profile.displayName)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                
                                if self.isActive {
                                    Text("使用中")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.tint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(.tint.opacity(0.14)))
                                }
                                
                                Text(self.profile.endpoint.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)))
                            }
                            
                            Text(self.profile.resolvedBaseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("点击切换为当前使用的 AI 端点")
                
                Menu {
                    if !self.fetchedModels.isEmpty {
                        Section("接口实时返回") {
                            ForEach(self.fetchedModels) { model in
                                Button {
                                    self.onSelectModel(model.id)
                                } label: {
                                    if model.id == self.profile.model {
                                        Label(model.name, systemImage: "checkmark")
                                    } else {
                                        Text(model.name)
                                    }
                                }
                            }
                        }
                    }
                    let saved = self.profile.availableModelIDs
                    if !saved.isEmpty {
                        Section("已保存模型") {
                            ForEach(saved, id: \.self) { modelID in
                                Button {
                                    self.onSelectModel(modelID)
                                } label: {
                                    if modelID == self.profile.model {
                                        Label(modelID, systemImage: "checkmark")
                                    } else {
                                        Text(modelID)
                                    }
                                }
                            }
                        }
                    }
                    let extras = Self.alternativeModels.filter { !saved.contains($0) }
                    if !extras.isEmpty {
                        Section("快捷切换模型") {
                            ForEach(extras, id: \.self) { modelID in
                                Button(modelID) {
                                    self.onSelectModel(modelID)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("从接口刷新模型列表", systemImage: "arrow.triangle.2.circlepath") {
                        self.onFetchModels()
                    }
                    Button("编辑完整配置…", systemImage: "pencil") {
                        self.onEdit()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if self.isFetchingModels {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "cpu")
                                .font(.caption2)
                        }
                        Text(self.profile.displayModel ?? "未选模型")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.11))
                    )
                    .frame(maxWidth: 165)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("快速切换模型或从端点拉取模型列表")
                
                HStack(spacing: 5) {
                    Button(action: self.onTest) {
                        if case .running = self.status {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "play.circle")
                        }
                    }
                    .help("测试端点连通性与响应延迟")
                    
                    Button(action: self.onDuplicate) {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("复制端点配置")
                    
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
            
            if let status = self.status {
                self.inlineStatusBanner(status)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(self.isActive ? Color.accentColor.opacity(0.06) : Color.clear)
        )
    }
    
    
    @ViewBuilder private func inlineStatusBanner(_ status: EndpointStatus) -> some View {
        
        switch status {
            case .running:
                Text("正在测速与校验响应…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            case .succeeded(let reply, let latencyMs):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("连通 · \(latencyMs) ms · 返回：\(reply)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                
            case .failed(let message):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("调整配置") {
                        self.onEdit()
                    }
                    .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.09))
                )
        }
    }
}


// MARK: - Stored Documents & Custom Config Sheet

struct StoredDocumentsSheetView: View {
    
    var isEmbeddedInline: Bool = false
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var newConfigKey = ""
    @State private var newConfigValue = ""
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本地 SQLite 数据库管理")
                    .font(self.isEmbeddedInline ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Picker("", selection: self.$selectedTab) {
                    Text("已存文档 (\(CotLocalDatabase.shared.documents.count))").tag(0)
                    Text("键值配置 (\(CotLocalDatabase.shared.configEntries.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: self.isEmbeddedInline ? 210 : 280)
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
                                if let onDone = self.onDone {
                                    onDone()
                                } else {
                                    self.dismiss()
                                }
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
                .frame(height: 260)
            } else {
                List {
                    ForEach(CotLocalDatabase.shared.configEntries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .frame(width: 150, alignment: .leading)
                            Text(entry.value)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.tail)
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
                .frame(height: 220)
                
                HStack(spacing: 8) {
                    TextField(text: self.$newConfigKey, prompt: Text("配置 Key (如 custom.signature)"), label: EmptyView.init)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .frame(maxWidth: 168)
                    TextField(text: self.$newConfigValue, prompt: Text("配置 Value"), label: EmptyView.init)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
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
                    if let onDone = self.onDone {
                        onDone()
                    } else {
                        self.dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(self.isEmbeddedInline ? 14 : 20)
        .frame(width: self.isEmbeddedInline ? nil : 600)
        .frame(maxWidth: self.isEmbeddedInline ? .infinity : nil)
        .environment(\.locale, AppLanguage.current.locale)
    }
}


// MARK: - Scroll-Passthrough Text Editor for Grouped Settings Forms

private final class PassthroughTextScrollView: NSScrollView {
    
    override func scrollWheel(with event: NSEvent) {
        
        guard let documentView = self.documentView else {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        let contentHeight = documentView.bounds.height
        let visibleHeight = self.contentView.bounds.height
        if contentHeight <= visibleHeight + 1 {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        let currentY = self.contentView.bounds.origin.y
        let maxY = max(0, contentHeight - visibleHeight)
        let atTop = currentY <= 0.5 && event.scrollingDeltaY > 0
        let atBottom = currentY >= maxY - 0.5 && event.scrollingDeltaY < 0
        if atTop || atBottom {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}


private struct ScrollPassthroughTextEditor: NSViewRepresentable {
    
    @Binding var text: String
    var font: NSFont
    
    
    func makeCoordinator() -> Coordinator {
        
        Coordinator(self)
    }
    
    
    func makeNSView(context: Context) -> NSScrollView {
        
        let scrollView = PassthroughTextScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.font = self.font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = self.text
        
        scrollView.documentView = textView
        return scrollView
    }
    
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != self.text {
            let selected = textView.selectedRange()
            textView.string = self.text
            let clampedLoc = min(selected.location, (self.text as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
        }
        if textView.font != self.font {
            textView.font = self.font
        }
    }
    
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        
        var parent: ScrollPassthroughTextEditor
        
        init(_ parent: ScrollPassthroughTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
}


// MARK: - AI Persona & Stage Prompts Settings View

struct AIPersonaSettingsView: View {
    
    private struct PersonaPreset: Identifiable {
        let id: String
        let title: String
        let prompt: String
    }
    
    private static let personaPresets: [PersonaPreset] = [
        .init(id: "expert",
              title: "精炼技术专家",
              prompt: "严谨资深的系统工程师，回答直击本质、注重准确性与高信噪比，避免空话和冗余铺垫。"),
        .init(id: "weekly",
              title: "直白周报搭档",
              prompt: "高效务实的研发协作伙伴，善于把零散工作记录提炼为清晰、实在、不堆砌套话的周报总结。"),
        .init(id: "architect",
              title: "深度架构顾问",
              prompt: "擅长从边界设计、并发安全、可维护性与性能权衡角度审视方案的架构顾问，兼顾落地成本与长期演进。"),
        .init(id: "editor",
              title: "双语润色编辑",
              prompt: "兼具中文书面表达功底与英文技术术语准确性的编辑，善于梳理文档结构、消除翻译腔并提升可读性。"),
    ]
    
    @State private var personaText: String = ""
    @State private var selectedStageAction: AIAction = .weeklyReport
    @State private var stagePromptText: String = ""
    @State private var typewriterEnabled: Bool = true
    @State private var typewriterStyle: TypingEffectPreset = .powerMode
    @State private var vimCursorTrailEnabled: Bool = true
    @State private var plainTextImagesEnabled: Bool = true
    
    
    var body: some View {
        
        SettingsFormPane {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("快捷人设:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        ForEach(Self.personaPresets) { preset in
                            let isSelected = self.personaText.trimmingCharacters(in: .whitespacesAndNewlines) == preset.prompt
                            Button(preset.title) {
                                self.personaText = preset.prompt
                                CotLocalDatabase.shared.aiPersona = preset.prompt
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? .accentColor : nil)
                            .controlSize(.small)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer()
                        if !self.personaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("清空") {
                                self.personaText = ""
                                CotLocalDatabase.shared.aiPersona = ""
                            }
                            .controlSize(.small)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        ScrollPassthroughTextEditor(
                            text: self.$personaText,
                            font: .systemFont(ofSize: 12)
                        )
                        .frame(height: 76)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                        )
                        .onChange(of: self.personaText) { _, newValue in
                            guard newValue != CotLocalDatabase.shared.aiPersona else { return }
                            CotLocalDatabase.shared.aiPersona = newValue
                        }
                        
                        if self.personaText.isEmpty {
                            Text("输入自定义 AI 人设，例如：严谨架构师，所有输出保持分点简洁，优先给出可执行结论…")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } header: {
                Label("AI 角色人设 (Persona)", systemImage: "person.text.rectangle")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
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
                        
                        let isCustomized = self.stagePromptText != self.selectedStageAction.defaultSystemPrompt
                        Text(isCustomized ? "已自定义" : "默认")
                            .font(.caption2)
                            .foregroundStyle(isCustomized ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill((isCustomized ? Color.accentColor : Color.secondary).opacity(0.12))
                            )
                        
                        Spacer()
                        
                        Button("恢复默认") {
                            let defaultPrompt = self.selectedStageAction.defaultSystemPrompt
                            self.stagePromptText = defaultPrompt
                            CotLocalDatabase.shared.set(defaultPrompt, forKey: self.selectedStageAction.databaseConfigKey)
                        }
                        .controlSize(.small)
                        .disabled(self.stagePromptText == self.selectedStageAction.defaultSystemPrompt)
                    }
                    
                    ScrollPassthroughTextEditor(
                        text: self.$stagePromptText,
                        font: .monospacedSystemFont(ofSize: 11.5, weight: .regular)
                    )
                    .frame(height: 168)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    )
                    .onChange(of: self.stagePromptText) { _, newValue in
                        let storedOrDefault = CotLocalDatabase.shared.customStagePrompt(forKey: self.selectedStageAction.databaseConfigKey)
                            ?? self.selectedStageAction.defaultSystemPrompt
                        guard newValue != storedOrDefault else { return }
                        CotLocalDatabase.shared.set(newValue, forKey: self.selectedStageAction.databaseConfigKey)
                    }
                }
            } header: {
                Label("阶段提示词 (Stage Prompt)", systemImage: "text.bubble")
            }
            
            Section {
                Toggle("动感打字特效", isOn: self.$typewriterEnabled)
                    .lineLimit(1)
                    .onChange(of: self.typewriterEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                    }
                
                Picker("特效风格", selection: self.$typewriterStyle) {
                    ForEach(TypingEffectPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(!self.typewriterEnabled)
                .onChange(of: self.typewriterStyle) { _, val in
                    CotLocalDatabase.shared.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                    UserDefaults.standard.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                }
                
                Toggle("Vim 流体光标特效", isOn: self.$vimCursorTrailEnabled)
                    .lineLimit(1)
                    .onChange(of: self.vimCursorTrailEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                    }
                
                Toggle("纯文本内嵌图片预览", isOn: self.$plainTextImagesEnabled)
                    .lineLimit(1)
                    .onChange(of: self.plainTextImagesEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                    }
                
                LabeledContent("光标颜色") {
                    CustomCursorColorControl()
                }
            } header: {
                Label("沉浸交互与视觉反馈", systemImage: "wand.and.stars")
            }
        }
        .task { self.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
    }
    
    
    private func reload() {
        
        let db = CotLocalDatabase.shared
        self.personaText = db.aiPersona
        self.loadStagePrompt(for: self.selectedStageAction)
        self.typewriterEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled, default: true)
        let styleRaw = db.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: TypingEffectPreset.powerMode.rawValue)
        self.typewriterStyle = TypingEffectPreset.resolve(styleRaw)
        self.vimCursorTrailEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled, default: true)
        self.plainTextImagesEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled, default: true)
    }
    
    
    private func loadStagePrompt(for action: AIAction) {
        
        self.stagePromptText = CotLocalDatabase.shared.customStagePrompt(forKey: action.databaseConfigKey)
            ?? action.defaultSystemPrompt
    }
}


// MARK: - Preview

#Preview {
    AISettingsView()
}

#Preview("AI Persona") {
    AIPersonaSettingsView()
}
