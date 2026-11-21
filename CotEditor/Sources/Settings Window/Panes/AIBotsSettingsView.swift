//
//  AIBotsSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  ---------------------------------------------------------------------------
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

// MARK: - 模型 (API 端点 & 全局人设)

struct AIModelsSettingsView: View {
    
    private static let quickProviders: [AIProvider] = [
        .openAI, .anthropic, .deepSeek, .qwen, .moonshot, .openRouter, .google, .ollama,
    ]
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var globalPersona: String = ""
    @State private var isEditingGlobalPersona = false
    
    @State private var profiles: [AIEndpointProfile] = []
    @State private var activeID: UUID?
    @State private var editingEndpointTarget: EndpointEditTarget?
    @State private var pendingDeletion: AIEndpointProfile?
    @State private var endpointStatus: [UUID: EndpointProbeStatus] = [:]
    @State private var fetchedModels: [UUID: [AIModel]] = [:]
    @State private var fetchingModelsIDs: Set<UUID> = []
    
    
    private struct EndpointEditTarget: Identifiable {
        var profile: AIEndpointProfile
        var apiKey: String
        var isNew: Bool
        var id: UUID { self.profile.id }
    }
    
    private enum EndpointProbeStatus: Equatable {
        case running
        case succeeded(String, latencyMs: Int)
        case failed(String)
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section 1: 服务端点
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("服务端点")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                    
                    Spacer()
                    
                    self.activeEnginePill
                }
                
                VStack(spacing: 0) {
                    if self.profiles.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "network.slash")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("尚未配置 AI 服务端点")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                    } else {
                        ForEach(Array(self.profiles.enumerated()), id: \.element.id) { idx, profile in
                            if idx > 0 {
                                self.rowDivider
                            }
                            self.endpointRow(profile)
                        }
                    }
                    
                    self.rowDivider
                    
                    HStack(spacing: 10) {
                        Button {
                            self.beginAddingEndpoint()
                        } label: {
                            Label("添加自定义端点", systemImage: "plus")
                        }
                        .controlSize(.small)
                        
                        Menu {
                            ForEach(Self.quickProviders, id: \.self) { provider in
                                Button(provider.label) {
                                    self.beginAddingEndpoint(preset: provider)
                                }
                            }
                        } label: {
                            Text("从预设模板新建")
                        }
                        .controlSize(.small)
                        .fixedSize()
                        
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                }
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            }
            
            // Section 2: 全局人设
            VStack(alignment: .leading, spacing: 7) {
                Text("全局人设")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Text("全局共享人设")
                            .font(.system(size: 13))
                        Spacer()
                        Button(self.isEditingGlobalPersona ? "收起" : "编辑") {
                            withAnimation(.easeOut(duration: 0.16)) {
                                self.isEditingGlobalPersona.toggle()
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    
                    if self.isEditingGlobalPersona {
                        self.rowDivider
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(AIBotStore.personaPresets) { preset in
                                        let selected = self.globalPersona.trimmingCharacters(in: .whitespacesAndNewlines) == preset.prompt
                                        Button(preset.title) {
                                            self.globalPersona = preset.prompt
                                            CotLocalDatabase.shared.aiPersona = preset.prompt
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(selected ? .accentColor : nil)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                            
                            TextEditor(text: self.$globalPersona)
                                .font(.system(size: 12))
                                .frame(height: 62)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(self.cardBorder, lineWidth: 1)
                                )
                                .onChange(of: self.globalPersona) { _, val in
                                    if val != CotLocalDatabase.shared.aiPersona {
                                        CotLocalDatabase.shared.aiPersona = val
                                    }
                                }
                        }
                        .padding(14)
                    }
                }
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            }
        }
        .onAppear {
            self.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
        .sheet(item: self.$editingEndpointTarget) { target in
            AIEndpointEditorView(profile: target.profile, apiKey: target.apiKey, isNew: target.isNew) { profile, apiKey in
                self.saveEndpoint(profile, apiKey: apiKey)
            }
        }
        .alert("删除 AI 端点？", isPresented: Binding(
            get: { self.pendingDeletion != nil },
            set: { if !$0 { self.pendingDeletion = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let target = self.pendingDeletion {
                    self.deleteEndpoint(target)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除该端点的接口地址及本地 API Key。")
        }
    }
    
    
    private var rowDivider: some View {
        Rectangle()
            .fill(self.colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
    
    
    private var activeEnginePill: some View {
        let activeProfile = self.profiles.first(where: { $0.id == self.activeID })
        let isUsable = activeProfile.map { $0.configuration(apiKey: AIEndpointStore.apiKey(for: $0)).isUsable } ?? false
        
        return HStack(spacing: 5) {
            Circle()
                .fill(isUsable ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(activeProfile?.displayName ?? "未配置端点")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(activeProfile != nil ? Color.secondary : Color.orange)
                .lineLimit(1)
        }
        .padding(.trailing, 3)
    }
    
    
    @ViewBuilder
    private func endpointRow(_ profile: AIEndpointProfile) -> some View {
        let isActive = (profile.id == self.activeID)
        let probe = self.endpointStatus[profile.id]
        let fetched = self.fetchedModels[profile.id] ?? []
        let isFetching = self.fetchingModelsIDs.contains(profile.id)
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    self.activateEndpoint(profile)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14.5))
                            .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                            .frame(width: 18)
                        
                        Text(profile.displayName)
                            .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                            .lineLimit(1)
                        
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Menu {
                    if !fetched.isEmpty {
                        Section("接口实时返回") {
                            ForEach(fetched) { model in
                                Button(model.name) {
                                    self.switchModel(model.id, on: profile)
                                }
                            }
                        }
                    }
                    let saved = profile.availableModelIDs
                    if !saved.isEmpty {
                        Section("已保存模型") {
                            ForEach(saved, id: \.self) { modelID in
                                Button(modelID) {
                                    self.switchModel(modelID, on: profile)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("刷新模型列表", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await self.fetchModels(for: profile) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isFetching {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "cpu").font(.system(size: 10))
                        }
                        Text(profile.displayModel ?? "未选模型")
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: 136)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                
                HStack(spacing: 7) {
                    Button {
                        Task { await self.testEndpoint(profile) }
                    } label: {
                        if case .running = probe {
                            ProgressView().controlSize(.small).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "play.circle")
                        }
                    }
                    .help("测试连通性")
                    
                    Button {
                        var copy = profile
                        copy.id = UUID()
                        copy.name = "\(profile.displayName) 副本"
                        self.editingEndpointTarget = EndpointEditTarget(
                            profile: copy,
                            apiKey: AIEndpointStore.apiKey(for: profile),
                            isNew: true
                        )
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("复制端点")
                    
                    Button {
                        self.editingEndpointTarget = EndpointEditTarget(
                            profile: profile,
                            apiKey: AIEndpointStore.apiKey(for: profile),
                            isNew: false
                        )
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("编辑")
                    
                    Button {
                        self.pendingDeletion = profile
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("删除")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            
            if let probe {
                HStack(spacing: 6) {
                    switch probe {
                        case .running:
                            Text("正在测速")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .succeeded(let reply, let latencyMs):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("连通 · \(latencyMs) ms · \(reply)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        case .failed(let msg):
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
    
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    private func reload() {
        AIEndpointStore.migrateLegacyConfigurationIfNeeded()
        self.profiles = AIEndpointStore.profiles
        let active = AIEndpointStore.activeID ?? self.profiles.first?.id
        self.activeID = active
        if let active, AIEndpointStore.activeID != active {
            AIEndpointStore.activeID = active
        }
        self.globalPersona = CotLocalDatabase.shared.aiPersona
    }
    
    
    private func activateEndpoint(_ profile: AIEndpointProfile) {
        self.activeID = profile.id
        AIEndpointStore.activeID = profile.id
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
    }
    
    
    private func beginAddingEndpoint(preset provider: AIProvider? = nil) {
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
        self.editingEndpointTarget = EndpointEditTarget(profile: profile, apiKey: "", isNew: true)
    }
    
    
    private func saveEndpoint(_ profile: AIEndpointProfile, apiKey: String) {
        AIEndpointStore.save(profile, apiKey: apiKey)
        if self.activeID == nil {
            self.activeID = profile.id
            AIEndpointStore.activeID = profile.id
        }
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        self.endpointStatus[profile.id] = nil
        self.reload()
    }
    
    
    private func switchModel(_ modelID: String, on profile: AIEndpointProfile) {
        var updated = profile
        updated.model = modelID
        updated.rememberModels([modelID])
        AIEndpointStore.save(updated, apiKey: AIEndpointStore.apiKey(for: profile))
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        self.endpointStatus[profile.id] = nil
        self.reload()
    }
    
    
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
            self.endpointStatus[profile.id] = .failed("拉取失败：\(error.localizedDescription)")
        }
    }
    
    
    private func deleteEndpoint(_ profile: AIEndpointProfile) {
        AIEndpointStore.delete(id: profile.id)
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        self.endpointStatus[profile.id] = nil
        self.fetchedModels[profile.id] = nil
        self.pendingDeletion = nil
        self.reload()
    }
    
    
    private func testEndpoint(_ profile: AIEndpointProfile) async {
        self.endpointStatus[profile.id] = .running
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let reply = try await AIService.shared.testConnection(
                configuration: profile.configuration(apiKey: AIEndpointStore.apiKey(for: profile))
            )
            let elapsed = start.duration(to: clock.now)
            let ms = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            self.endpointStatus[profile.id] = .succeeded(reply, latencyMs: ms)
        } catch {
            self.endpointStatus[profile.id] = .failed(error.localizedDescription)
        }
    }
}


// MARK: - 智能体 (Builtin Specialized AI Bots)

struct AIBotsSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var botStore = AIBotStore.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var inspectingBot: AIBotID?
    @State private var activeEndpoint: AIEndpointProfile?
    @State private var globalPersona: String = ""
    
    
    var body: some View {
        let featureCounts = Dictionary(
            self.analytics.featureDistribution(days: 30).map { ($0.feature, $0.requests) },
            uniquingKeysWith: { first, _ in first }
        )
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("内置智能体")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
                
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(AIBotID.allCases) { botID in
                        let cfg = self.botStore.config(for: botID)
                        let calls = featureCounts[botID.analyticsFeatureKey] ?? 0
                        BotCardView(
                            botID: botID,
                            config: cfg,
                            recentCalls: calls,
                            defaultModelLabel: self.activeEndpoint?.displayModel ?? "跟随默认",
                            cardSurface: self.cardSurface,
                            cardBorder: self.cardBorder,
                            onToggle: { enabled in
                                var updated = cfg
                                updated.isEnabled = enabled
                                self.botStore.updateConfig(updated, for: botID)
                            },
                            onInspect: {
                                self.inspectingBot = botID
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            self.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
        .sheet(item: self.$inspectingBot) { botID in
            AIBotInspectorSheet(
                botID: botID,
                activeEndpoint: self.activeEndpoint,
                globalPersona: self.globalPersona
            )
        }
    }
    
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    private func reload() {
        let profiles = AIEndpointStore.profiles
        let activeID = AIEndpointStore.activeID ?? profiles.first?.id
        self.activeEndpoint = profiles.first(where: { $0.id == activeID })
        self.globalPersona = CotLocalDatabase.shared.aiPersona
        self.botStore.reloadFromDatabase()
    }
}


// MARK: - Bot Card

private struct BotCardView: View {
    
    let botID: AIBotID
    let config: AIBotConfig
    let recentCalls: Int
    let defaultModelLabel: String
    let cardSurface: Color
    let cardBorder: Color
    let onToggle: (Bool) -> Void
    let onInspect: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        let accent = Color(hexString: self.botID.accentHex)
        
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(self.config.isEnabled ? 1.0 : 0.35))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: self.botID.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                )
            
            Text(self.botID.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(self.config.isEnabled ? .primary : .secondary)
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            Toggle("", isOn: Binding(
                get: { self.config.isEnabled },
                set: { self.onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(self.isHovered ? accent : Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(self.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(self.isHovered ? accent.opacity(0.45) : self.cardBorder, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture {
            self.onInspect()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                self.isHovered = hovering
            }
        }
        .pointerStyle(.link)
    }
}


// MARK: - Bot Inspector Sheet

private struct AIBotInspectorSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    
    let botID: AIBotID
    let activeEndpoint: AIEndpointProfile?
    let globalPersona: String
    
    @State private var botStore = AIBotStore.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var config: AIBotConfig = AIBotConfig()
    @State private var promptText: String = ""
    
    @State private var inlineCompletionEnabled: Bool = true
    @State private var nextTokenStrategy: AINextTokenStrategy = .smart
    @State private var nextTokenDebounceMs: Int = 420
    @State private var nextTokenDailyCap: Int = 300
    
    @State private var sampleInput: String = ""
    @State private var sampleOutput: String = ""
    @State private var testError: String?
    @State private var isTesting = false
    
    
    var body: some View {
        let accent = Color(hexString: self.botID.accentHex)
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: self.botID.symbolName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                
                Text(self.botID.displayName)
                    .font(.headline)
                
                Spacer()
                
                Toggle("启用", isOn: self.$config.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.config.isEnabled) { _, _ in
                        self.saveBotConfig()
                    }
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Text("专属模型")
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        
                        TextField(
                            self.activeEndpoint?.displayModel ?? "默认",
                            text: self.$config.modelOverride
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: self.config.modelOverride) { _, _ in
                            self.saveBotConfig()
                        }
                        
                        if let endpoint = self.activeEndpoint, !endpoint.availableModelIDs.isEmpty {
                            Menu {
                                Button("默认") {
                                    self.config.modelOverride = ""
                                    self.saveBotConfig()
                                }
                                Divider()
                                ForEach(endpoint.availableModelIDs, id: \.self) { id in
                                    Button(id) {
                                        self.config.modelOverride = id
                                        self.saveBotConfig()
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    
                    HStack(spacing: 10) {
                        Text("专属人设")
                            .font(.system(size: 12.5, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        
                        TextField(
                            "默认",
                            text: self.$config.customPersona
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: self.config.customPersona) { _, _ in
                            self.saveBotConfig()
                        }
                        
                        if !self.config.customPersona.isEmpty {
                            Button("重置") {
                                self.config.customPersona = ""
                                self.saveBotConfig()
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    if self.botID == .ghost {
                        self.ghostControls
                    }
                    
                    if self.botID == .persona {
                        self.personaControls
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Bot 核心指令 (Prompt)")
                                .font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Button("恢复默认指令") {
                                self.promptText = self.botID.defaultSystemPrompt
                                self.botStore.setSystemPrompt(self.promptText, for: self.botID)
                            }
                            .controlSize(.mini)
                            .disabled(self.promptText == self.botID.defaultSystemPrompt)
                        }
                        
                        TextEditor(text: self.$promptText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(height: 120)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                            )
                            .onChange(of: self.promptText) { _, newValue in
                                self.botStore.setSystemPrompt(newValue, for: self.botID)
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Bot 实时试聊测试", systemImage: "play.circle.fill")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(accent)
                            Spacer()
                            Button {
                                Task { await self.runSandboxTest() }
                            } label: {
                                if self.isTesting {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Text("试跑一次")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .controlSize(.small)
                            .disabled(self.isTesting)
                        }
                        
                        TextField("输入测试内容", text: self.$sampleInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                        
                        if let testError = self.testError {
                            Text(testError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if !self.sampleOutput.isEmpty {
                            ScrollView {
                                Text(self.sampleOutput)
                                    .font(.system(size: 11.5))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)
                            .padding(8)
                            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .padding(.trailing, 4)
            }
            
            HStack {
                Button("全部恢复默认", role: .destructive) {
                    self.botStore.resetBotToDefaults(self.botID)
                    self.loadInitialState()
                }
                .controlSize(.small)
                
                Spacer()
                
                Button("完成") {
                    self.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 590)
        .onAppear {
            self.loadInitialState()
        }
    }
    
    
    private var ghostControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("启用行内幽灵续写 (按 Tab 接纳)", isOn: self.$inlineCompletionEnabled)
                .onChange(of: self.inlineCompletionEnabled) { _, val in
                    CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled)
                    UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled)
                }
            
            HStack(spacing: 12) {
                Picker("策略", selection: self.$nextTokenStrategy) {
                    Text("智能省流").tag(AINextTokenStrategy.smart)
                    Text("积极伴写").tag(AINextTokenStrategy.proactive)
                }
                .pickerStyle(.segmented)
                .onChange(of: self.nextTokenStrategy) { _, strategy in
                    CotLocalDatabase.shared.set(strategy.rawValue, forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
                    UserDefaults.standard.set(strategy.rawValue, forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy)
                }
                
                Picker("触发", selection: self.$nextTokenDebounceMs) {
                    Text("280ms").tag(280)
                    Text("420ms").tag(420)
                    Text("680ms").tag(680)
                }
                .pickerStyle(.segmented)
                .onChange(of: self.nextTokenDebounceMs) { _, val in
                    CotLocalDatabase.shared.set("\(val)", forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs)
                    UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs)
                }
            }
            
            Picker("每日预算上限", selection: self.$nextTokenDailyCap) {
                Text("100 次/天").tag(100)
                Text("300 次/天").tag(300)
                Text("800 次/天").tag(800)
                Text("不限").tag(0)
            }
            .onChange(of: self.nextTokenDailyCap) { _, val in
                CotLocalDatabase.shared.set("\(val)", forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap)
                UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    
    private var personaControls: some View {
        HStack {
            if let profile = self.analytics.personalityProfile {
                Text(profile.conceptTitle)
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer()
            Button(self.analytics.isAnalyzingPersonality ? "分析中" : "立即分析") {
                Task {
                    await self.analytics.refreshPersonalityProfile(force: true)
                }
            }
            .controlSize(.small)
            .disabled(self.analytics.isAnalyzingPersonality)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    
    private func loadInitialState() {
        self.config = self.botStore.config(for: self.botID)
        self.promptText = self.botStore.systemPrompt(for: self.botID)
        self.sampleInput = self.botID.defaultSampleInput
        
        let db = CotLocalDatabase.shared
        self.inlineCompletionEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled, default: true)
        let rawStrategy = db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenStrategy, default: AINextTokenStrategy.smart.rawValue)
        self.nextTokenStrategy = AINextTokenStrategy(rawValue: rawStrategy) ?? .smart
        let rawDebounce = Int(db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs, default: "420")) ?? 420
        self.nextTokenDebounceMs = [280, 420, 680].contains(rawDebounce) ? rawDebounce : 420
        let rawCap = Int(db.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDailyCap, default: "300")) ?? 300
        self.nextTokenDailyCap = [0, 100, 300, 800].contains(rawCap) ? rawCap : 300
    }
    
    
    private func saveBotConfig() {
        self.botStore.updateConfig(self.config, for: self.botID)
    }
    
    
    private func runSandboxTest() async {
        self.isTesting = true
        self.testError = nil
        defer { self.isTesting = false }
        do {
            let reply = try await AIService.shared.testBot(self.botID, sampleInput: self.sampleInput)
            self.sampleOutput = reply
        } catch {
            self.testError = error.localizedDescription
        }
    }
}
