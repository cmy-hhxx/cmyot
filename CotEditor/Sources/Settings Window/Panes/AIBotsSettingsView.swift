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

// MARK: - 模型 (API 端点 & 全局人设 · 零弹窗全内联)

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
    @State private var confirmDeleteID: UUID?
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
            if let target = self.editingEndpointTarget {
                self.inlineEndpointEditor(target)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                self.mainModelsContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onAppear {
            self.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
    }
    
    
    @ViewBuilder
    private func inlineEndpointEditor(_ target: EndpointEditTarget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.editingEndpointTarget = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(AppLanguage.text("返回模型端点", en: "Back to Endpoints"))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(self.cardSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(self.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 0) {
                AIEndpointEditorView(
                    profile: target.profile,
                    apiKey: target.apiKey,
                    isNew: target.isNew,
                    isEmbeddedInline: true,
                    onCancel: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.editingEndpointTarget = nil
                        }
                    },
                    onSave: { profile, apiKey in
                        self.saveEndpoint(profile, apiKey: apiKey)
                    }
                )
            }
            .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
        }
    }
    
    
    private var mainModelsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section 1: 服务端点
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(AppLanguage.text("服务端点", en: "Endpoints"))
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
                            Text(AppLanguage.text("尚未配置 AI 服务端点", en: "No Endpoints Configured"))
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
                            Label(AppLanguage.text("添加自定义端点", en: "Add Endpoint"), systemImage: "plus")
                        }
                        .controlSize(.small)
                        
                        Menu {
                            ForEach(Self.quickProviders, id: \.self) { provider in
                                Button(provider.label) {
                                    self.beginAddingEndpoint(preset: provider)
                                }
                            }
                        } label: {
                            Text(AppLanguage.text("从预设模板新建", en: "From Preset"))
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
                Text(AppLanguage.text("全局人设", en: "Global Persona"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Text(AppLanguage.text("全局共享人设", en: "Shared System Persona"))
                            .font(.system(size: 13))
                        Spacer()
                        Button(self.isEditingGlobalPersona ? AppLanguage.text("收起", en: "Collapse") : AppLanguage.text("编辑", en: "Edit")) {
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
            Text(activeProfile?.displayName ?? AppLanguage.text("未配置端点", en: "Unconfigured"))
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
        let isConfirmingDelete = (self.confirmDeleteID == profile.id)
        
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
                        Section(AppLanguage.text("接口实时返回", en: "Fetched Models")) {
                            ForEach(fetched) { model in
                                Button(model.name) {
                                    self.switchModel(model.id, on: profile)
                                }
                            }
                        }
                    }
                    let saved = profile.availableModelIDs
                    if !saved.isEmpty {
                        Section(AppLanguage.text("已保存模型", en: "Saved Models")) {
                            ForEach(saved, id: \.self) { modelID in
                                Button(modelID) {
                                    self.switchModel(modelID, on: profile)
                                }
                            }
                        }
                    }
                    Divider()
                    Button(AppLanguage.text("刷新模型列表", en: "Refresh Models"), systemImage: "arrow.triangle.2.circlepath") {
                        Task { await self.fetchModels(for: profile) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isFetching {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "cpu").font(.system(size: 10))
                        }
                        Text(profile.displayModel ?? AppLanguage.text("未选模型", en: "No Model"))
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
                    .frame(maxWidth: 132)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                
                if isConfirmingDelete {
                    HStack(spacing: 5) {
                        Button(AppLanguage.text("确认删除", en: "Delete"), role: .destructive) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                self.deleteEndpoint(profile)
                            }
                        }
                        .controlSize(.mini)
                        Button(AppLanguage.text("取消", en: "Cancel")) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                self.confirmDeleteID = nil
                            }
                        }
                        .controlSize(.mini)
                    }
                } else {
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
                        .help(AppLanguage.text("测试连通性", en: "Test Connection"))
                        
                        Button {
                            var copy = profile
                            copy.id = UUID()
                            copy.name = "\(profile.displayName) 副本"
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.editingEndpointTarget = EndpointEditTarget(
                                    profile: copy,
                                    apiKey: AIEndpointStore.apiKey(for: profile),
                                    isNew: true
                                )
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help(AppLanguage.text("复制端点", en: "Duplicate"))
                        
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.editingEndpointTarget = EndpointEditTarget(
                                    profile: profile,
                                    apiKey: AIEndpointStore.apiKey(for: profile),
                                    isNew: false
                                )
                            }
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help(AppLanguage.text("编辑", en: "Edit"))
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                self.confirmDeleteID = profile.id
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help(AppLanguage.text("删除", en: "Delete"))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            
            if let probe {
                HStack(spacing: 6) {
                    switch probe {
                        case .running:
                            Text(AppLanguage.text("正在测速", en: "Testing"))
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            self.editingEndpointTarget = EndpointEditTarget(profile: profile, apiKey: "", isNew: true)
        }
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
        self.confirmDeleteID = nil
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


// MARK: - 智能体 (Collection Layout Morph: List / Card / Pack + Inline Inspector)

enum BotCollectionLayoutMode: String, CaseIterable, Identifiable {
    case list
    case card
    case pack
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .list: AppLanguage.text("列表视图", en: "List view")
            case .card: AppLanguage.text("卡片视图", en: "Card view")
            case .pack: AppLanguage.text("叠放视图", en: "Pack view")
        }
    }
    
    var icon: String {
        switch self {
            case .list: "list.bullet"
            case .card: "square.grid.2x2"
            case .pack: "square.stack.3d.up"
        }
    }
}


struct AIBotsSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var botStore = AIBotStore.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var layoutMode: BotCollectionLayoutMode = .list
    @State private var inspectingBot: AIBotID?
    @State private var activeEndpoint: AIEndpointProfile?
    @State private var globalPersona: String = ""
    @State private var stageWidth: CGFloat = 439
    @State private var hoveredBotID: AIBotID?
    
    @Namespace private var modePillNamespace
    
    
    var body: some View {
        let featureCounts = Dictionary(
            self.analytics.featureDistribution(days: 30).map { ($0.feature, $0.requests) },
            uniquingKeysWith: { first, _ in first }
        )
        
        VStack(alignment: .leading, spacing: 14) {
            if let botID = self.inspectingBot {
                self.inlineInspector(for: botID)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                self.morphingCollectionView(featureCounts: featureCounts)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
            if abs(w - self.stageWidth) > 2 && w > 120 {
                self.stageWidth = w
            }
        }
        .onAppear {
            self.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
    }
    
    
    // MARK: Morphing List / Card / Pack Collection Stage
    
    @ViewBuilder
    private func morphingCollectionView(featureCounts: [String: Int]) -> some View {
        let bots = AIBotID.allCases
        let cols = 3
        let rowsCount = Int(ceil(Double(bots.count) / Double(cols)))
        let cardGap: CGFloat = 14
        let cardSize = max(92, floor((self.stageWidth - cardGap * CGFloat(cols - 1)) / CGFloat(cols)))
        let stageHeight: CGFloat = switch self.layoutMode {
            case .list: CGFloat(bots.count) * 64.0
            case .card: CGFloat(rowsCount) * (cardSize + 44.0)
            case .pack: 214.0
        }
        let enabledCount = bots.filter { self.botStore.config(for: $0).isEnabled }.count
        
        VStack(alignment: .leading, spacing: 14) {
            // Segmented Layout Switcher with a SINGLE shared sliding capsule
            HStack(spacing: 6) {
                ForEach(BotCollectionLayoutMode.allCases) { mode in
                    let isSelected = (self.layoutMode == mode)
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)) {
                            self.layoutMode = mode
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(mode.title)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.085))
                                    .matchedGeometryEffect(id: "botLayoutPill", in: self.modePillNamespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Spacer()
                
                Text("\(enabledCount)/\(bots.count) 已启用")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            // Divider hairline fades in card view just like collection-layout-morph
            Rectangle()
                .fill(self.cardBorder)
                .frame(height: 1)
                .opacity(self.layoutMode == .card ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.22), value: self.layoutMode)
            
            // Unified Identity-Preserving Morph Stage
            ZStack(alignment: .topLeading) {
                ForEach(Array(bots.enumerated()), id: \.element) { index, botID in
                    let cfg = self.botStore.config(for: botID)
                    let calls = featureCounts[botID.analyticsFeatureKey] ?? 0
                    self.morphingBotNode(
                        botID: botID,
                        index: index,
                        total: bots.count,
                        config: cfg,
                        recentCalls: calls,
                        cardSize: cardSize,
                        cardGap: cardGap
                    )
                }
                
                // Pack summary label beneath stacked cards
                if self.layoutMode == .pack {
                    VStack(spacing: 4) {
                        Text(AppLanguage.text("内置智能体卡组（共 \(bots.count) 位）", en: "\(bots.count) Built-in Agents"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(AppLanguage.text("点击任一张卡牌即可进入人设与指令调教", en: "Click any card to configure"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .offset(y: 136)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(width: self.stageWidth, height: stageHeight, alignment: .topLeading)
        }
    }
    
    
    @ViewBuilder
    private func morphingBotNode(
        botID: AIBotID,
        index: Int,
        total: Int,
        config: AIBotConfig,
        recentCalls: Int,
        cardSize: CGFloat,
        cardGap: CGFloat
    ) -> some View {
        let accent = Color(hexString: botID.accentHex)
        let isHovered = (self.hoveredBotID == botID)
        
        let itemWidth: CGFloat
        let badgeSize: CGFloat
        let badgeCorner: CGFloat
        let posX: CGFloat
        let posY: CGFloat
        let rotation: Double
        
        switch self.layoutMode {
            case .list:
                badgeSize = 48
                badgeCorner = 10
                itemWidth = self.stageWidth
                posX = 0
                posY = CGFloat(index) * 64.0
                rotation = 0
            case .card:
                badgeSize = cardSize
                badgeCorner = 14
                itemWidth = cardSize
                let col = index % 3
                let row = index / 3
                posX = CGFloat(col) * (cardSize + cardGap)
                posY = CGFloat(row) * (cardSize + 44.0)
                rotation = 0
            case .pack:
                badgeSize = 84
                badgeCorner = 16
                itemWidth = badgeSize
                let spread: CGFloat = 24.0
                let mid = Double(total - 1) * 0.5
                let offsetIndex = Double(index) - mid
                posX = (self.stageWidth - badgeSize) * 0.5 + CGFloat(offsetIndex) * spread
                posY = 16 + abs(CGFloat(offsetIndex)) * 4.5 - (isHovered ? 12 : 0)
                rotation = offsetIndex * 5.2
        }
        
        return ZStack(alignment: .topLeading) {
            // Persistent Bot Artwork Tile (never swapped across modes!)
            RoundedRectangle(cornerRadius: badgeCorner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(config.isEnabled ? 0.95 : 0.42),
                            accent.opacity(config.isEnabled ? 0.72 : 0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: badgeSize, height: badgeSize)
                .overlay {
                    Image(systemName: botID.symbolName)
                        .font(.system(size: badgeSize * 0.40, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: badgeCorner, style: .continuous)
                        .strokeBorder(Color.white.opacity(self.colorScheme == .dark ? 0.20 : 0.42), lineWidth: 1)
                )
                .shadow(
                    color: (self.layoutMode == .pack ? accent.opacity(0.24) : Color.black.opacity(0.10)),
                    radius: self.layoutMode == .pack ? 10 : 4,
                    y: self.layoutMode == .pack ? 5 : 2
                )
                .rotationEffect(.degrees(rotation))
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        self.inspectingBot = botID
                    }
                }
            
            // List view metadata right of tile
            if self.layoutMode == .list {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(botID.displayName)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(config.isEnabled ? .primary : .secondary)
                        
                        HStack(spacing: 6) {
                            Text(config.modelOverride.isEmpty ? (self.activeEndpoint?.displayModel ?? "默认模型") : config.modelOverride)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if recentCalls > 0 {
                                Text("· \(recentCalls) 次")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: Binding(
                        get: { config.isEnabled },
                        set: { enabled in
                            var updated = config
                            updated.isEnabled = enabled
                            self.botStore.updateConfig(updated, for: botID)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                            self.inspectingBot = botID
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isHovered ? accent : Color(nsColor: .tertiaryLabelColor))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, badgeSize + 14)
                .frame(width: itemWidth, height: badgeSize, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        self.inspectingBot = botID
                    }
                }
            }
            
            // Card view compact caption under tile
            if self.layoutMode == .card {
                HStack(spacing: 4) {
                    Text(botID.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(config.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 2)
                    
                    Circle()
                        .fill(config.isEnabled ? accent : Color.primary.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
                .frame(width: cardSize)
                .offset(y: cardSize + 8)
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        self.inspectingBot = botID
                    }
                }
            }
        }
        .frame(width: itemWidth, alignment: .topLeading)
        .offset(x: posX, y: posY)
        .zIndex(Double(index) + (isHovered && self.layoutMode == .pack ? 20 : 0))
        .onHover { hovering in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.80)) {
                self.hoveredBotID = hovering ? botID : (self.hoveredBotID == botID ? nil : self.hoveredBotID)
            }
        }
        .pointerStyle(.link)
        .help(botID.displayName)
    }
    
    
    // MARK: Inline Bot Inspector (Zero Modal Sheets)
    
    @ViewBuilder
    private func inlineInspector(for botID: AIBotID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.inspectingBot = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(AppLanguage.text("返回智能体", en: "Back to Agents"))
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(self.cardSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(self.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Spacer()
            }
            
            AIBotInlineInspectorView(
                botID: botID,
                activeEndpoint: self.activeEndpoint,
                globalPersona: self.globalPersona,
                cardSurface: self.cardSurface,
                cardBorder: self.cardBorder
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


// MARK: - Inline Bot Inspector

private struct AIBotInlineInspectorView: View {
    
    let botID: AIBotID
    let activeEndpoint: AIEndpointProfile?
    let globalPersona: String
    let cardSurface: Color
    let cardBorder: Color
    
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
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: self.botID.symbolName)
                            .font(.system(size: 16, weight: .semibold))
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
            
            HStack(spacing: 10) {
                Text("专属模型")
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 66, alignment: .leading)
                
                TextField(self.activeEndpoint?.displayModel ?? "默认", text: self.$config.modelOverride)
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
                    .frame(width: 66, alignment: .leading)
                
                TextField("默认", text: self.$config.customPersona)
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
                    Text("核心指令 (Prompt)")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button("恢复默认") {
                        self.promptText = self.botID.defaultSystemPrompt
                        self.botStore.setSystemPrompt(self.promptText, for: self.botID)
                    }
                    .controlSize(.mini)
                    .disabled(self.promptText == self.botID.defaultSystemPrompt)
                }
                
                TextEditor(text: self.$promptText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .frame(height: 106)
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
                    Label("实时试聊测试", systemImage: "play.circle.fill")
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
                    .lineLimit(2...3)
                
                if let testError = self.testError {
                    Text(testError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !self.sampleOutput.isEmpty {
                    Text(self.sampleOutput)
                        .font(.system(size: 11.5))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            
            HStack {
                Button("全部恢复默认", role: .destructive) {
                    self.botStore.resetBotToDefaults(self.botID)
                    self.loadInitialState()
                }
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(14)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
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
            
            HStack(spacing: 10) {
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
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
