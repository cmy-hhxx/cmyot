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
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - API 网关 (可折叠 · 可切换 · 可任意删除 · 零掉帧手风琴)

enum GatewayProbeStatus: Equatable {
    case running
    case succeeded(String, latencyMs: Int)
    case failed(String)
}


struct GatewaySlot: Identifiable, Equatable {
    var profile: AIEndpointProfile
    var apiKey: String
    
    var id: UUID { self.profile.id }
    
    var trimmedKey: String {
        self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var isReady: Bool {
        !self.profile.endpoint.requiresAPIKey || !self.trimmedKey.isEmpty
    }
}


/// Isolated Equatable subscription card modeled after cc-switch rows:
/// provider badge + editable custom name + endpoint subtitle + active status / play / edit / more menu.
private struct GatewaySubscriptionCardView: View, Equatable {
    
    let slot: GatewaySlot
    let isSelected: Bool
    let isExpanded: Bool
    let isRenaming: Bool
    let isRevealingKey: Bool
    let isFetchingModels: Bool
    let probe: GatewayProbeStatus?
    let remoteModelIDs: [String]
    let isDark: Bool
    let onSelectActive: () -> Void
    let onToggleExpand: () -> Void
    let onStartRename: () -> Void
    let onFinishRename: (String) -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void
    let onTest: () -> Void
    let onRefreshModels: () -> Void
    let onToggleRevealKey: () -> Void
    let onChangeName: (String) -> Void
    let onChangeKey: (String) -> Void
    let onChangeModel: (String) -> Void
    let onSelectModelPreset: (String) -> Void
    let onChangeBaseURL: (String) -> Void
    let onSwitchProtocol: (AIEndpoint) -> Void
    
    @State private var isRowHovered = false
    @State private var isPlayHovered = false
    @State private var isEditHovered = false
    @State private var isMoreHovered = false
    @State private var draftRename: String = ""
    @FocusState private var isRenameFocused: Bool
    
    private let labelColumnWidth: CGFloat = 64
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.slot == rhs.slot
            && lhs.isSelected == rhs.isSelected
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isRenaming == rhs.isRenaming
            && lhs.isRevealingKey == rhs.isRevealingKey
            && lhs.isFetchingModels == rhs.isFetchingModels
            && lhs.probe == rhs.probe
            && lhs.remoteModelIDs == rhs.remoteModelIDs
            && lhs.isDark == rhs.isDark
    }
    
    private var cardSurface: Color {
        if self.isSelected {
            return self.isDark
                ? Color.accentColor.opacity(0.14)
                : Color.accentColor.opacity(0.065)
        }
        return self.isDark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    private var rowDivider: some View {
        Rectangle()
            .fill(self.isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
            .frame(height: 0.75)
            .padding(.horizontal, 14)
    }
    
    private var cardTitle: String {
        let customName = self.slot.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customName.isEmpty {
            return customName
        }
        return self.slot.profile.provider.subscriptionTitle
    }
    
    private var endpointSubtitle: String {
        let resolved = self.slot.profile.resolvedBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty {
            return resolved
        }
        return self.standardURL.isEmpty ? self.slot.profile.endpoint.defaultBaseURL : self.standardURL
    }
    
    private var currentModelText: String {
        let trimmed = self.slot.profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let fallback = self.slot.profile.provider.defaultModel
        return fallback.isEmpty ? AppLanguage.text("选择模型", en: "Select Model") : fallback
    }
    
    private var standardURL: String {
        let provider = self.slot.profile.provider
        if provider == .openCodeGo {
            return self.slot.profile.endpoint == .anthropicMessages
                ? "https://opencode.ai/zen/go"
                : "https://opencode.ai/zen/go/v1"
        }
        return provider.defaultBaseURL
    }
    
    private var selectableModels: [String] {
        var seen: Set<String> = []
        var list: [String] = []
        let candidates = self.slot.profile.provider.recommendedModels
            + self.slot.profile.availableModelIDs
            + self.remoteModelIDs
        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            list.append(trimmed)
        }
        return list
    }
    
    var body: some View {
        let provider = self.slot.profile.provider
        let accent = Color(hexString: provider.accentHex)
        let isReady = self.slot.isReady
        
        VStack(alignment: .leading, spacing: 0) {
            // Header Row: Provider Icon + Editable Name/URL + Model Status + Active/Play/Edit/More
            HStack(spacing: 11) {
                self.providerBadge(provider: provider, accent: accent)
                
                VStack(alignment: .leading, spacing: 2) {
                    if self.isRenaming {
                        TextField(
                            provider.subscriptionTitle,
                            text: self.$draftRename
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
                        )
                        .focused(self.$isRenameFocused)
                        .onSubmit {
                            self.commitInlineRename()
                        }
                        .onExitCommand {
                            self.onCancelRename()
                        }
                        .onAppear {
                            self.draftRename = self.cardTitle
                            DispatchQueue.main.async {
                                self.isRenameFocused = true
                            }
                        }
                        .onChange(of: self.isRenameFocused) { _, focused in
                            if !focused && self.isRenaming {
                                self.commitInlineRename()
                            }
                        }
                    } else {
                        Text(self.cardTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .highPriorityGesture(
                                TapGesture(count: 2).onEnded {
                                    self.onStartRename()
                                }
                            )
                            .help(AppLanguage.text("双击名称可快速重命名", en: "Double-click to rename"))
                    }
                    
                    Text(self.endpointSubtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !self.isRenaming {
                        self.onToggleExpand()
                    }
                }
                
                if !self.isExpanded && !self.isRenaming {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isReady ? Color.green : Color.orange.opacity(0.85))
                            .frame(width: 5.5, height: 5.5)
                        Text(self.currentModelText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 132, alignment: .trailing)
                    }
                }
                
                // Right action strip: Active pill / Play switch + Edit pencil + More menu
                HStack(spacing: 3) {
                    if self.isSelected {
                        HStack(spacing: 4.5) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 5.5, height: 5.5)
                            Text(AppLanguage.text("使用中", en: "Active"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                    } else {
                        Button(action: self.onSelectActive) {
                            Image(systemName: "play")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(self.isPlayHovered ? Color.accentColor : Color.secondary)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(self.isPlayHovered ? Color.accentColor.opacity(0.10) : Color.clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .onHover { self.isPlayHovered = $0 }
                        .help(AppLanguage.text("切换为当前使用", en: "Set as Active"))
                    }
                    
                    Button(action: self.onToggleExpand) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(self.isExpanded || self.isEditHovered ? Color.primary : Color.secondary)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(self.isExpanded
                                          ? Color.primary.opacity(self.isDark ? 0.12 : 0.08)
                                          : (self.isEditHovered ? Color.primary.opacity(self.isDark ? 0.08 : 0.05) : Color.clear))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { self.isEditHovered = $0 }
                    .help(self.isExpanded
                          ? AppLanguage.text("收起配置", en: "Collapse")
                          : AppLanguage.text("编辑配置", en: "Edit"))
                    
                    Menu {
                        Button {
                            self.onStartRename()
                        } label: {
                            Label(AppLanguage.text("重命名", en: "Rename"), systemImage: "pencil.line")
                        }
                        
                        if !self.isSelected {
                            Button {
                                self.onSelectActive()
                            } label: {
                                Label(AppLanguage.text("切换为使用中", en: "Set as Active"), systemImage: "play")
                            }
                        }
                        
                        if isReady {
                            Button {
                                if !self.isExpanded {
                                    self.onToggleExpand()
                                }
                                self.onTest()
                            } label: {
                                Label(AppLanguage.text("测试连接", en: "Test Connection"), systemImage: "bolt.horizontal")
                            }
                        }
                        
                        Button {
                            self.onDuplicate()
                        } label: {
                            Label(AppLanguage.text("复制配置", en: "Duplicate"), systemImage: "doc.on.doc")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            self.onRemove()
                        } label: {
                            Label(AppLanguage.text("删除此服务", en: "Delete"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(self.isMoreHovered ? Color.primary : Color.secondary)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(self.isMoreHovered ? Color.primary.opacity(self.isDark ? 0.08 : 0.05) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .pointerStyle(.link)
                    .onHover { self.isMoreHovered = $0 }
                    .help(AppLanguage.text("更多操作", en: "More Actions"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            
            if self.isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    self.rowDivider
                    self.expandedFormBody(provider: provider, accent: accent, isReady: isReady)
                }
                // Lock natural vertical height so AppKit NSTextFields never squash/relayout per animation frame
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
        .clipped()
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.isDark ? Color.white.opacity(0.055) : Color.white)
                if self.isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(self.cardSurface)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    self.isSelected ? Color.accentColor.opacity(0.65) : self.cardBorder,
                    lineWidth: self.isSelected ? 1.25 : 0.85
                )
        )
        .onHover { hovering in
            if hovering != self.isRowHovered {
                self.isRowHovered = hovering
            }
        }
        .contextMenu {
            Button(AppLanguage.text("重命名", en: "Rename")) {
                self.onStartRename()
            }
            if !self.isSelected {
                Button(AppLanguage.text("切换为使用中", en: "Set as Active")) {
                    self.onSelectActive()
                }
            }
            Button(self.isExpanded
                   ? AppLanguage.text("收起配置", en: "Collapse")
                   : AppLanguage.text("编辑配置", en: "Edit")) {
                self.onToggleExpand()
            }
            Button(AppLanguage.text("复制配置", en: "Duplicate")) {
                self.onDuplicate()
            }
            Divider()
            Button(AppLanguage.text("删除此服务", en: "Delete"), role: .destructive) {
                self.onRemove()
            }
        }
    }
    
    
    private func commitInlineRename() {
        let trimmed = self.draftRename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self.onFinishRename(trimmed)
        } else {
            self.onCancelRename()
        }
    }
    
    
    @ViewBuilder
    private func providerBadge(provider: AIProvider, accent: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(self.isDark ? Color.white.opacity(0.08) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.cardBorder, lineWidth: 0.75)
                )
            
            if provider == .openCodeGo {
                // Iconic minimalist dark frame emblem matching OpenCode Go
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(self.isDark ? Color.white.opacity(0.88) : Color(red: 0.14, green: 0.15, blue: 0.18), lineWidth: 2.2)
                    .frame(width: 12, height: 15)
                    .overlay(
                        Rectangle()
                            .fill((self.isDark ? Color.white : Color.black).opacity(0.28))
                            .frame(width: 5.5, height: 6)
                            .offset(y: 2)
                    )
            } else {
                Image(systemName: Self.providerSymbol(for: provider))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 30, height: 30)
    }
    
    
    private static func providerSymbol(for provider: AIProvider) -> String {
        switch provider {
            case .openCodeGo: "terminal.fill"
            case .openAI: "sparkle"
            case .anthropic: "sun.max.fill"
            case .deepSeek: "waveform.path.ecg"
            case .google: "diamond.fill"
            case .openRouter: "arrow.triangle.branch"
            case .moonshot: "moon.stars.fill"
            case .zhipu: "cpu.fill"
            case .miniMax: "bolt.fill"
            case .qwen: "cloud.fill"
            case .volcengine: "flame.fill"
            case .siliconFlow: "square.grid.2x2.fill"
            case .aiHubMix: "circle.hexagongrid.fill"
            case .ollama: "desktopcomputer"
            case .custom: "network"
        }
    }
    
    @ViewBuilder
    private func expandedFormBody(provider: AIProvider, accent: Color, isReady: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Editable Name Row — always available for EVERY subscription / official API
            HStack(spacing: 12) {
                Text(AppLanguage.text("名称", en: "Name"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: self.labelColumnWidth, alignment: .leading)
                
                TextField(
                    provider.subscriptionTitle,
                    text: Binding(
                        get: { self.slot.profile.name },
                        set: { self.onChangeName($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.85))
                
                if isReady {
                    Button(action: self.onTest) {
                        HStack(spacing: 4) {
                            if case .running = self.probe {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.7)
                                    .frame(width: 12, height: 12)
                            }
                            Text(AppLanguage.text("测试连接", en: "Test"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Color.primary.opacity(self.isDark ? 0.10 : 0.06),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(self.probe == .running)
                    .pointerStyle(.link)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            self.rowDivider
            
            if self.slot.profile.endpoint.requiresAPIKey {
                HStack(spacing: 12) {
                    Text("API Key")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: self.labelColumnWidth, alignment: .leading)
                    
                    HStack(spacing: 8) {
                        Group {
                            if self.isRevealingKey {
                                TextField(
                                    provider.apiKeyPlaceholder,
                                    text: Binding(
                                        get: { self.slot.apiKey },
                                        set: { self.onChangeKey($0) }
                                    )
                                )
                                .font(.system(size: 12, design: .monospaced))
                            } else {
                                SecureField(
                                    provider.apiKeyPlaceholder,
                                    text: Binding(
                                        get: { self.slot.apiKey },
                                        set: { self.onChangeKey($0) }
                                    )
                                )
                                .font(.system(size: 12))
                            }
                        }
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if isReady {
                                self.onTest()
                            }
                        }
                        
                        if self.slot.trimmedKey.isEmpty {
                            Button(AppLanguage.text("粘贴", en: "Paste")) {
                                if let pasted = NSPasteboard.general.string(forType: .string)?
                                    .trimmingCharacters(in: .whitespacesAndNewlines),
                                   !pasted.isEmpty
                                {
                                    self.onChangeKey(pasted)
                                }
                            }
                            .controlSize(.mini)
                        } else {
                            Button(self.isRevealingKey ? AppLanguage.text("隐藏", en: "Hide") : AppLanguage.text("显示", en: "Show")) {
                                self.onToggleRevealKey()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            
                            Button(AppLanguage.text("清除", en: "Clear")) {
                                self.onChangeKey("")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5.5)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                self.rowDivider
            }
            
            // Model Row
            HStack(spacing: 12) {
                Text(AppLanguage.text("默认模型", en: "Model"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: self.labelColumnWidth, alignment: .leading)
                
                HStack(spacing: 8) {
                    if provider == .custom || provider == .ollama {
                        TextField(
                            provider == .ollama ? "qwen2.5:7b" : "model-id",
                            text: Binding(
                                get: { self.slot.profile.model },
                                set: { self.onChangeModel($0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 9)
                        .frame(minHeight: 28)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.85))
                    }
                    
                    let models = self.selectableModels
                    if provider != .custom || !models.isEmpty {
                        Menu {
                            if provider == .openCodeGo {
                                ForEach(AIProvider.openCodeGoModelGroups) { group in
                                    Section(group.title) {
                                        ForEach(group.models, id: \.self) { modelID in
                                            Button(self.slot.profile.model == modelID ? "✓  \(modelID)" : modelID) {
                                                self.onSelectModelPreset(modelID)
                                            }
                                        }
                                    }
                                }
                                let curatedSet = Set(AIProvider.openCodeGo.recommendedModels)
                                let extras = self.remoteModelIDs.filter { !curatedSet.contains($0) }
                                if !extras.isEmpty {
                                    Section(AppLanguage.text("接口返回模型", en: "Fetched Models")) {
                                        ForEach(extras.prefix(24), id: \.self) { modelID in
                                            Button(self.slot.profile.model == modelID ? "✓  \(modelID)" : modelID) {
                                                self.onSelectModelPreset(modelID)
                                            }
                                        }
                                    }
                                }
                            } else {
                                ForEach(models, id: \.self) { modelID in
                                    Button(self.slot.profile.model == modelID ? "✓  \(modelID)" : modelID) {
                                        self.onSelectModelPreset(modelID)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(provider == .custom || provider == .ollama
                                     ? AppLanguage.text("预设", en: "Presets")
                                     : self.currentModelText)
                                    .font(.system(size: 12, weight: .medium, design: provider == .custom || provider == .ollama ? .default : .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if provider != .custom && provider != .ollama {
                                    Spacer(minLength: 4)
                                }
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .frame(maxWidth: (provider == .custom || provider == .ollama) ? nil : .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.85))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize(horizontal: provider == .custom || provider == .ollama, vertical: false)
                        .pointerStyle(.link)
                    }
                    
                    if isReady {
                        Button(action: self.onRefreshModels) {
                            HStack(spacing: 4) {
                                if self.isFetchingModels {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.68)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                Text(self.isFetchingModels
                                     ? AppLanguage.text("获取中", en: "Fetching")
                                     : AppLanguage.text("刷新", en: "Refresh"))
                                    .font(.system(size: 11))
                            }
                        }
                        .controlSize(.small)
                        .disabled(self.isFetchingModels)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            self.rowDivider
            
            // Endpoint URL Row
            HStack(alignment: .top, spacing: 12) {
                Text(AppLanguage.text("接口地址", en: "Endpoint"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: self.labelColumnWidth, alignment: .leading)
                    .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 7) {
                    let defURL = self.standardURL
                    let isModified = !defURL.isEmpty && self.slot.profile.resolvedBaseURL != defURL
                    
                    HStack(spacing: 8) {
                        TextField(
                            defURL.isEmpty ? self.slot.profile.endpoint.defaultBaseURL : defURL,
                            text: Binding(
                                get: { self.slot.profile.baseURL },
                                set: { self.onChangeBaseURL($0) }
                            )
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5.5)
                        .background(
                            Color.primary.opacity(self.isDark ? 0.05 : 0.03),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.75))
                        
                        if isModified {
                            Button(AppLanguage.text("恢复默认", en: "Reset")) {
                                self.onChangeBaseURL(defURL)
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    if provider == .openCodeGo || provider == .custom {
                        let protocols: [AIEndpoint] = provider == .openCodeGo
                            ? AIEndpoint.subscriptionProtocols
                            : AIEndpoint.allCases
                        HStack(spacing: 6) {
                            ForEach(protocols, id: \.self) { proto in
                                let picked = (self.slot.profile.endpoint == proto)
                                Button {
                                    self.onSwitchProtocol(proto)
                                } label: {
                                    Text(proto.shortProtocolBadge)
                                        .font(.system(size: 11, weight: picked ? .semibold : .medium))
                                        .foregroundStyle(picked ? Color.white : Color.secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(picked ? accent : Color.primary.opacity(self.isDark ? 0.07 : 0.045))
                                        )
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            if let probe = self.probe {
                self.rowDivider
                self.probeBanner(probe)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
        }
    }
    
    @ViewBuilder
    private func probeBanner(_ probe: GatewayProbeStatus) -> some View {
        HStack(alignment: .center, spacing: 8) {
            switch probe {
                case .running:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                    Text(AppLanguage.text("正在测试连接…", en: "Testing connection…"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                case .succeeded(let reply, let latencyMs):
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("连通 · \(latencyMs) ms · \(reply)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                case .failed(let msg):
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text(msg)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }
}


struct AIModelsSettingsView: View {
    
    private static let starterSeededDefaultsKey = "aiGatewayDidSeedStarterListV2"
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var slots: [GatewaySlot]
    @State private var activeID: UUID?
    @State private var expandedID: UUID?
    @State private var renamingID: UUID?
    @State private var revealingKeyIDs: Set<UUID> = []
    @State private var probeStatuses: [UUID: GatewayProbeStatus] = [:]
    @State private var fetchedModelsByID: [UUID: [AIModel]] = [:]
    @State private var fetchingModelIDs: Set<UUID> = []
    @State private var persistTasks: [UUID: Task<Void, Never>] = [:]
    @State private var backendSyncTask: Task<Void, Never>?
    
    @State private var piKernel = PiKernelManager.shared
    @State private var kernelEnabled: Bool = PiKernelManager.shared.isKernelEnabled
    
    init() {
        let initial = Self.loadGatewayState()
        self._slots = State(initialValue: initial.slots)
        self._activeID = State(initialValue: initial.activeID)
        // Start collapsed when active gateway is already configured so the page opens ultra-clean;
        // expand only when the active gateway still needs an API key.
        let initialExpanded: UUID? = {
            if let activeID = initial.activeID,
               let activeSlot = initial.slots.first(where: { $0.id == activeID }),
               !activeSlot.isReady
            {
                return activeID
            }
            return nil
        }()
        self._expandedID = State(initialValue: initialExpanded)
    }
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if self.slots.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(AppLanguage.text("列表已清空，点击下方按钮按需添加订阅或官方 API", en: "No API services configured. Add one below."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.85))
                } else {
                    ForEach(self.slots) { slot in
                        let slotID = slot.id
                        GatewaySubscriptionCardView(
                            slot: slot,
                            isSelected: self.activeID == slotID,
                            isExpanded: self.expandedID == slotID,
                            isRenaming: self.renamingID == slotID,
                            isRevealingKey: self.revealingKeyIDs.contains(slotID),
                            isFetchingModels: self.fetchingModelIDs.contains(slotID),
                            probe: self.probeStatuses[slotID],
                            remoteModelIDs: self.fetchedModelsByID[slotID]?.map(\.id) ?? [],
                            isDark: isDark,
                            onSelectActive: { self.selectActiveSlot(slotID) },
                            onToggleExpand: { self.toggleExpanded(slotID) },
                            onStartRename: {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    self.renamingID = slotID
                                }
                            },
                            onFinishRename: { newName in
                                self.renamingID = nil
                                self.commitNameImmediately(newName, for: slotID)
                            },
                            onCancelRename: {
                                self.renamingID = nil
                            },
                            onDuplicate: { self.duplicateSlot(slotID) },
                            onRemove: { self.removeSlot(slotID) },
                            onTest: { Task { await self.testSlot(slotID) } },
                            onRefreshModels: { Task { await self.fetchRemoteModels(for: slotID, silentError: false) } },
                            onToggleRevealKey: {
                                if self.revealingKeyIDs.contains(slotID) {
                                    self.revealingKeyIDs.remove(slotID)
                                } else {
                                    self.revealingKeyIDs.insert(slotID)
                                }
                            },
                            onChangeName: { self.updateName($0, for: slotID) },
                            onChangeKey: { self.updateAPIKey($0, for: slotID) },
                            onChangeModel: { self.updateModel($0, for: slotID) },
                            onSelectModelPreset: { self.selectModel($0, for: slotID) },
                            onChangeBaseURL: { self.updateBaseURL($0, for: slotID) },
                            onSwitchProtocol: { self.switchProtocol($0, for: slotID) }
                        )
                        .equatable()
                    }
                }
                
                self.addSubscriptionBar
                    .padding(.top, 2)
            }
            
            // Pi Kernel Runtime Toggle
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLanguage.text("Pi 内核底座", en: "Pi Kernel Runtime"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                HStack(spacing: 10) {
                    Circle()
                        .fill(self.piKernel.isAvailable && self.kernelEnabled ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    
                    Text(self.piKernel.statusSummary)
                        .font(.system(size: 13, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    Toggle("", isOn: self.$kernelEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.kernelEnabled) { _, enabled in
                            self.piKernel.isKernelEnabled = enabled
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
        .onDisappear {
            self.flushPendingPersistenceImmediately()
        }
    }
    
    
    // MARK: - Add Subscription / Official API Menu Bar
    
    private var addSubscriptionBar: some View {
        let existingProviders = Set(self.slots.map { $0.profile.provider })
        let unaddedPresets = AIProvider.curatedPresets.filter { !existingProviders.contains($0) }
        let addedPresets = AIProvider.curatedPresets.filter { existingProviders.contains($0) }
        
        return HStack(spacing: 8) {
            Menu {
                if !unaddedPresets.isEmpty {
                    Section(AppLanguage.text("官方 API 与订阅服务", en: "Subscriptions & Official APIs")) {
                        ForEach(unaddedPresets, id: \.self) { provider in
                            Button(provider.subscriptionTitle) {
                                self.addProviderSlot(provider)
                            }
                        }
                    }
                }
                
                if !addedPresets.isEmpty {
                    Section(AppLanguage.text("再添加一个同品牌配置", en: "Additional Instance")) {
                        ForEach(addedPresets, id: \.self) { provider in
                            Button(provider.subscriptionTitle) {
                                self.addProviderSlot(provider)
                            }
                        }
                    }
                }
                
                Divider()
                
                Button(AIProvider.custom.subscriptionTitle) {
                    self.addProviderSlot(.custom)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("添加订阅 / 官方 API", en: "Add Subscription / API"))
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.8))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .pointerStyle(.link)
            
            if self.expandedID != nil {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        self.expandedID = nil
                    }
                } label: {
                    Text(AppLanguage.text("收起面板", en: "Collapse"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            Spacer()
        }
    }
    
    
    // MARK: - Actions & Deferred Persistence (Zero Main-Thread Animation Blocking)
    
    private static let accordionCurve = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
    
    private func toggleExpanded(_ id: UUID) {
        withAnimation(Self.accordionCurve) {
            self.expandedID = (self.expandedID == id) ? nil : id
        }
    }
    
    private func selectActiveSlot(_ id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        let needsKey = !self.slots[idx].isReady
        withAnimation(Self.accordionCurve) {
            self.activeID = id
            if needsKey {
                self.expandedID = id
            }
        }
        AIEndpointStore.activeID = id
        self.schedulePersist(for: id)
    }
    
    private func uniqueSlotName(base: String) -> String {
        let existing = Set(self.slots.map { $0.profile.name.trimmingCharacters(in: .whitespacesAndNewlines) })
        if !existing.contains(base) {
            return base
        }
        var n = 2
        while existing.contains("\(base)-\(n)") {
            n += 1
        }
        return "\(base)-\(n)"
    }
    
    private func addProviderSlot(_ provider: AIProvider) {
        let baseTitle = provider == .custom ? AIProvider.custom.subscriptionTitle : provider.subscriptionTitle
        let uniqueTitle = self.uniqueSlotName(base: baseTitle)
        var created = provider.makeProfile(customName: uniqueTitle)
        if provider == .custom {
            created.baseURL = ""
            created.model = ""
        }
        let newSlot = GatewaySlot(profile: created, apiKey: "")
        withAnimation(Self.accordionCurve) {
            self.slots.append(newSlot)
            self.activeID = newSlot.id
            self.expandedID = newSlot.id
        }
        if let idx = self.slots.firstIndex(where: { $0.id == newSlot.id }) {
            self.persistSlotInMemoryAndStore(at: idx, makeActive: true)
            self.scheduleBackendSync()
        }
    }
    
    private func duplicateSlot(_ id: UUID) {
        guard let source = self.slots.first(where: { $0.id == id }) else { return }
        let baseName = source.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleBase = baseName.isEmpty ? source.profile.provider.subscriptionTitle : baseName
        var cloned = source.profile
        cloned.id = UUID()
        cloned.name = self.uniqueSlotName(base: titleBase)
        let newSlot = GatewaySlot(profile: cloned, apiKey: "")
        withAnimation(Self.accordionCurve) {
            if let srcIdx = self.slots.firstIndex(where: { $0.id == id }) {
                self.slots.insert(newSlot, at: srcIdx + 1)
            } else {
                self.slots.append(newSlot)
            }
            self.expandedID = newSlot.id
            self.renamingID = newSlot.id
        }
        if let idx = self.slots.firstIndex(where: { $0.id == newSlot.id }) {
            self.persistSlotInMemoryAndStore(at: idx, makeActive: false)
            self.scheduleBackendSync()
        }
    }
    
    private func removeSlot(_ id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        self.persistTasks[id]?.cancel()
        self.persistTasks.removeValue(forKey: id)
        self.probeStatuses.removeValue(forKey: id)
        self.revealingKeyIDs.remove(id)
        
        let wasActive = (self.activeID == id)
        withAnimation(Self.accordionCurve) {
            self.slots.remove(at: idx)
            if self.expandedID == id {
                self.expandedID = nil
            }
            if self.renamingID == id {
                self.renamingID = nil
            }
            if wasActive {
                self.activeID = self.slots.first?.id
            }
        }
        
        let nextActive = self.activeID
        Task { @MainActor in
            AIEndpointStore.delete(id: id)
            AIEndpointStore.activeID = nextActive
            self.scheduleBackendSync()
        }
    }
    
    private func updateName(_ newValue: String, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        self.slots[idx].profile.name = newValue
        self.schedulePersist(for: id)
    }
    
    private func commitNameImmediately(_ newValue: String, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.slots[idx].profile.name = trimmed
        self.persistSlotInMemoryAndStore(at: idx, makeActive: self.activeID == id)
        self.scheduleBackendSync()
    }
    
    private func updateAPIKey(_ newKey: String, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        let wasEmpty = self.slots[idx].trimmedKey.isEmpty
        self.slots[idx].apiKey = newKey
        let currentActiveReady = self.activeID
            .flatMap { aid in self.slots.first(where: { $0.id == aid })?.isReady } ?? false
        if wasEmpty && !newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !currentActiveReady {
            self.activeID = id
        }
        self.schedulePersist(for: id)
    }
    
    private func updateBaseURL(_ newURL: String, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        self.slots[idx].profile.baseURL = newURL
        self.schedulePersist(for: id)
    }
    
    private func updateModel(_ newModel: String, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        self.slots[idx].profile.model = newModel
        self.schedulePersist(for: id)
    }
    
    private func selectModel(_ modelID: String, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        self.slots[idx].profile.model = modelID
        self.slots[idx].profile.rememberModels([modelID])
        self.persistSlotInMemoryAndStore(at: idx, makeActive: self.activeID == id)
        self.scheduleBackendSync()
    }
    
    private func switchProtocol(_ newEndpoint: AIEndpoint, for id: UUID) {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }),
              self.slots[idx].profile.endpoint != newEndpoint
        else { return }
        let prevProvider = self.slots[idx].profile.provider
        let oldDefault = prevProvider == .openCodeGo
            ? (self.slots[idx].profile.endpoint == .anthropicMessages ? "https://opencode.ai/zen/go" : "https://opencode.ai/zen/go/v1")
            : prevProvider.defaultBaseURL
        self.slots[idx].profile.endpoint = newEndpoint
        if prevProvider == .openCodeGo {
            let current = self.slots[idx].profile.resolvedBaseURL
            if current == oldDefault || current.isEmpty {
                self.slots[idx].profile.baseURL = (newEndpoint == .anthropicMessages)
                    ? "https://opencode.ai/zen/go"
                    : "https://opencode.ai/zen/go/v1"
            }
        }
        self.persistSlotInMemoryAndStore(at: idx, makeActive: self.activeID == id)
        self.scheduleBackendSync()
    }
    
    private func schedulePersist(for id: UUID) {
        self.persistTasks[id]?.cancel()
        self.persistTasks[id] = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled,
                  let idx = self.slots.firstIndex(where: { $0.id == id })
            else { return }
            self.persistSlotInMemoryAndStore(at: idx, makeActive: self.activeID == id)
            self.scheduleBackendSync()
        }
    }
    
    private func scheduleBackendSync() {
        self.backendSyncTask?.cancel()
        self.backendSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
            _ = try? self.piKernel.syncWorkspace()
        }
    }
    
    private func flushPendingPersistenceImmediately() {
        let pendingIDs = Array(self.persistTasks.keys)
        for id in pendingIDs {
            self.persistTasks[id]?.cancel()
            self.persistTasks.removeValue(forKey: id)
            if let idx = self.slots.firstIndex(where: { $0.id == id }) {
                self.persistSlotInMemoryAndStore(at: idx, makeActive: self.activeID == id)
            }
        }
        if self.backendSyncTask != nil || !pendingIDs.isEmpty {
            self.backendSyncTask?.cancel()
            self.backendSyncTask = nil
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
            _ = try? self.piKernel.syncWorkspace()
        }
    }
    
    private func persistSlotInMemoryAndStore(at index: Int, makeActive: Bool) {
        guard self.slots.indices.contains(index) else { return }
        let id = self.slots[index].id
        self.persistTasks[id]?.cancel()
        self.persistTasks.removeValue(forKey: id)
        
        var updated = self.slots[index].profile
        let provider = updated.provider
        let rawTypedName = updated.name
        if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.name = provider == .custom ? AIProvider.custom.subscriptionTitle : provider.subscriptionTitle
        }
        for (k, v) in provider.defaultCustomHeaders where updated.customHeaders[k] == nil {
            updated.customHeaders[k] = v
        }
        let cleanModel = updated.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanModel.isEmpty {
            updated.rememberModels([cleanModel])
        }
        updated.rememberModels(provider.recommendedModels)
        
        let trimmedKey = self.slots[index].trimmedKey
        var inMemory = updated
        if rawTypedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inMemory.name = rawTypedName
        }
        self.slots[index].profile = inMemory
        self.probeStatuses[id] = nil
        
        AIEndpointStore.save(updated, apiKey: trimmedKey)
        if makeActive || AIEndpointStore.activeID == nil {
            AIEndpointStore.activeID = updated.id
            self.activeID = updated.id
        }
    }
    
    private static func loadGatewayState() -> (slots: [GatewaySlot], activeID: UUID?) {
        AIEndpointStore.migrateLegacyConfigurationIfNeeded()
        var storedProfiles = AIEndpointStore.profiles
        
        // Seed starter presets ONLY ONCE on a brand-new uninitialized store; never resurrect user-deleted items!
        if !UserDefaults.standard.bool(forKey: Self.starterSeededDefaultsKey) {
            UserDefaults.standard.set(true, forKey: Self.starterSeededDefaultsKey)
            if storedProfiles.isEmpty {
                for starter in AIProvider.starterSubscriptions {
                    let prof = starter.makeProfile(customName: starter.subscriptionTitle)
                    AIEndpointStore.save(prof, apiKey: "")
                }
                storedProfiles = AIEndpointStore.profiles
                if let first = storedProfiles.first {
                    AIEndpointStore.activeID = first.id
                }
            }
        }
        
        let builtSlots: [GatewaySlot] = storedProfiles.map { prof in
            var normalized = prof
            let provider = normalized.provider
            for (k, v) in provider.defaultCustomHeaders where normalized.customHeaders[k] == nil {
                normalized.customHeaders[k] = v
            }
            if normalized.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !provider.defaultModel.isEmpty
            {
                normalized.model = provider.defaultModel
            }
            normalized.rememberModels(provider.recommendedModels)
            return GatewaySlot(
                profile: normalized,
                apiKey: AIEndpointStore.apiKey(for: normalized)
            )
        }
        
        let resolvedActiveID: UUID? = {
            if let storedActive = AIEndpointStore.activeID,
               builtSlots.contains(where: { $0.id == storedActive })
            {
                return storedActive
            }
            if let readySlot = builtSlots.first(where: \.isReady) {
                return readySlot.id
            }
            return builtSlots.first?.id
        }()
        return (builtSlots, resolvedActiveID)
    }
    
    private func reload() {
        let loaded = Self.loadGatewayState()
        self.slots = loaded.slots
        self.activeID = loaded.activeID
        if let exp = self.expandedID, !loaded.slots.contains(where: { $0.id == exp }) {
            self.expandedID = nil
        }
        self.kernelEnabled = self.piKernel.isKernelEnabled
    }
    
    private func fetchRemoteModels(for id: UUID, silentError: Bool) async {
        guard let idx = self.slots.firstIndex(where: { $0.id == id }) else { return }
        let slot = self.slots[idx]
        self.fetchingModelIDs.insert(id)
        defer { self.fetchingModelIDs.remove(id) }
        
        let config = slot.profile.configuration(apiKey: slot.trimmedKey)
        do {
            let models = try await AIService.shared.fetchModels(configuration: config)
            self.fetchedModelsByID[id] = models
            if let latestIdx = self.slots.firstIndex(where: { $0.id == id }) {
                self.slots[latestIdx].profile.rememberModels(models.prefix(24).map(\.id))
                self.persistSlotInMemoryAndStore(at: latestIdx, makeActive: self.activeID == id)
                self.scheduleBackendSync()
            }
        } catch {
            if !silentError {
                self.probeStatuses[id] = .failed("拉取模型失败：\(error.localizedDescription)")
            }
        }
    }
    
    private func testSlot(_ id: UUID) async {
        guard let slot = self.slots.first(where: { $0.id == id }) else { return }
        self.probeStatuses[id] = .running
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let reply = try await AIService.shared.testConnection(
                configuration: slot.profile.configuration(apiKey: slot.trimmedKey)
            )
            let elapsed = start.duration(to: clock.now)
            let ms = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            self.probeStatuses[id] = .succeeded(reply, latencyMs: ms)
        } catch {
            self.probeStatuses[id] = .failed(error.localizedDescription)
        }
    }
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
}


// MARK: - Bots (3:4 立绘比例 · 120fps 金字塔叠放扇面 · 异步位图预热)

enum BotCollectionLayoutMode: String, CaseIterable, Identifiable {
    case card
    case list
    case pack
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .card: AppLanguage.text("画廊视图", en: "Gallery")
            case .list: AppLanguage.text("列表视图", en: "List")
            case .pack: AppLanguage.text("叠放视图", en: "Pack")
        }
    }
    
    var icon: String {
        switch self {
            case .card: "square.grid.2x2"
            case .list: "list.bullet"
            case .pack: "square.stack.3d.up"
        }
    }
}


private struct BotCardSnapshot: Identifiable, Equatable {
    
    let botID: AIBotID
    let displayTitle: String
    let shortTitle: String
    let subtitle: String
    let personaBadge: String?
    let modelLabel: String
    let accentHex: String
    let isEnabled: Bool
    let recentCalls: Int
    let portraitImage: NSImage?
    
    var id: AIBotID { self.botID }
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.botID == rhs.botID
            && lhs.displayTitle == rhs.displayTitle
            && lhs.shortTitle == rhs.shortTitle
            && lhs.subtitle == rhs.subtitle
            && lhs.personaBadge == rhs.personaBadge
            && lhs.modelLabel == rhs.modelLabel
            && lhs.accentHex == rhs.accentHex
            && lhs.isEnabled == rhs.isEnabled
            && lhs.recentCalls == rhs.recentCalls
            && lhs.portraitImage === rhs.portraitImage
    }
}


/// Pure Equatable ~3:4 portrait bitmap surface. Isolated from deck index/offset changes so
/// CoreAnimation interpolates scale/rotation/offset transforms at 120fps without re-running `body`.
private struct BotPortraitTileSurface: View, Equatable {
    
    let botID: AIBotID
    let shortTitle: String
    let accentHex: String
    let isEnabled: Bool
    let portraitImage: NSImage?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let showPackOverlay: Bool
    let isPackCenter: Bool
    let isDark: Bool
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.botID == rhs.botID
            && lhs.shortTitle == rhs.shortTitle
            && lhs.accentHex == rhs.accentHex
            && lhs.isEnabled == rhs.isEnabled
            && lhs.portraitImage === rhs.portraitImage
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
            && lhs.showPackOverlay == rhs.showPackOverlay
            && lhs.isPackCenter == rhs.isPackCenter
            && lhs.isDark == rhs.isDark
    }
    
    
    var body: some View {
        let accent = Color(hexString: self.accentHex)
        
        ZStack(alignment: .top) {
            Color(red: 0.965, green: 0.969, blue: 0.980)
            
            if let portrait = self.portraitImage {
                Image(nsImage: portrait)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: self.width, height: self.height, alignment: .center)
                    .opacity(self.isEnabled ? 1.0 : 0.48)
            } else {
                LinearGradient(
                    colors: [
                        accent.opacity(self.isDark ? 0.22 : 0.14),
                        self.isDark
                            ? Color(red: 0.15, green: 0.15, blue: 0.18)
                            : Color(red: 0.95, green: 0.96, blue: 0.98),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(self.shortTitle.prefix(1)))
                    .font(.system(size: min(self.width * 0.34, 28), weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(self.isEnabled ? 1.0 : 0.48)
            }
            
            if self.showPackOverlay {
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(self.isEnabled ? accent : Color.white.opacity(0.45))
                            .frame(width: 5.5, height: 5.5)
                        Text(self.shortTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.68)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: self.width, height: self.height)
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .strokeBorder(
                    self.isPackCenter
                        ? accent.opacity(0.85)
                        : (self.showPackOverlay
                           ? Color.white.opacity(self.isDark ? 0.22 : 0.85)
                           : (self.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))),
                    lineWidth: self.isPackCenter ? 1.5 : 0.85
                )
        )
    }
}


// MARK: - 120Hz Hardware-Clipped CoreAnimation CoverFlow Stage (零 SwiftUI 重绘 · 预烘焙纹理 · 静态 shadowPath)

private final class PackBakedCardTextureCache {
    
    static let shared = PackBakedCardTextureCache()
    private var cache: [String: CGImage] = [:]
    
    func texture(
        for snap: BotCardSnapshot,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        isDark: Bool
    ) -> CGImage? {
        let imgToken = snap.portraitImage.map { String(UInt(bitPattern: ObjectIdentifier($0))) } ?? "nil"
        let key = "\(snap.botID.rawValue)|\(snap.shortTitle)|\(snap.accentHex)|\(snap.isEnabled)|\(isDark)|\(Int(width))x\(Int(height))|\(imgToken)"
        if let hit = self.cache[key] {
            return hit
        }
        guard let baked = Self.renderCardFace(
            snap: snap,
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            isDark: isDark
        ) else {
            return nil
        }
        if self.cache.count > 48 {
            self.cache.removeAll(keepingCapacity: true)
        }
        self.cache[key] = baked
        return baked
    }
    
    private static func renderCardFace(
        snap: BotCardSnapshot,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat,
        isDark: Bool
    ) -> CGImage? {
        let scale: CGFloat = 2.0
        let pxW = max(1, Int((width * scale).rounded()))
        let pxH = max(1, Int((height * scale).rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        defer { NSGraphicsContext.restoreGraphicsState() }
        
        ctx.scaleBy(x: scale, y: scale)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        clipPath.addClip()
        
        let accentNS = NSColor(Color(hexString: snap.accentHex))
        
        // 1. Base surface
        let bg = isDark
            ? NSColor(srgbRed: 0.14, green: 0.145, blue: 0.17, alpha: 1.0)
            : NSColor(srgbRed: 0.965, green: 0.969, blue: 0.980, alpha: 1.0)
        bg.setFill()
        rect.fill()
        
        // 2. Portrait bitmap (or monogram fallback)
        if let portrait = snap.portraitImage {
            portrait.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: snap.isEnabled ? 1.0 : 0.48
            )
        } else {
            let topTint = accentNS.withAlphaComponent(isDark ? 0.24 : 0.16)
            if let grad = NSGradient(starting: bg, ending: topTint) {
                grad.draw(in: rect, angle: 90)
            }
            let initial = String(snap.shortTitle.prefix(1)) as NSString
            let font = NSFont.systemFont(ofSize: 28, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: accentNS.withAlphaComponent(snap.isEnabled ? 1.0 : 0.48),
            ]
            let sz = initial.size(withAttributes: attrs)
            initial.draw(
                at: NSPoint(x: (width - sz.width) * 0.5, y: (height - sz.height) * 0.5),
                withAttributes: attrs
            )
        }
        
        // 3. Bottom scrim gradient (y = 0 is bottom in unflipped NSGraphicsContext)
        let scrimHeight: CGFloat = 44
        let scrimRect = NSRect(x: 0, y: 0, width: width, height: scrimHeight)
        if let scrim = NSGradient(
            starting: NSColor.black.withAlphaComponent(0.72),
            ending: NSColor.black.withAlphaComponent(0.0)
        ) {
            scrim.draw(in: scrimRect, angle: 90)
        }
        
        // 4. Status dot + short title at bottom-left
        let dotSize: CGFloat = 5.5
        let dotRect = NSRect(x: 9.5, y: 10.5, width: dotSize, height: dotSize)
        let dotColor = snap.isEnabled ? accentNS : NSColor.white.withAlphaComponent(0.45)
        dotColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let titleX: CGFloat = 19.5
        let titleRect = NSRect(x: titleX, y: 5.5, width: max(10, width - titleX - 8), height: 16)
        (snap.shortTitle as NSString).draw(in: titleRect, withAttributes: titleAttrs)
        
        // 5. Crisp inner hairline border
        let borderPath = NSBezierPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            xRadius: max(1, cornerRadius - 0.5),
            yRadius: max(1, cornerRadius - 0.5)
        )
        borderPath.lineWidth = 1.0
        let borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.20)
            : NSColor.white.withAlphaComponent(0.88)
        borderColor.setStroke()
        borderPath.stroke()
        
        return ctx.makeImage()
    }
}


private final class PackCoreAnimationStageNSView: NSView {
    
    private final class CardLayerSlot {
        let container = CALayer()
        let face = CALayer()
        let dimScrim = CALayer()
        let focusRing = CALayer()
        let hoverBorder = CALayer()
        var currentCenter: CGPoint = .zero
        var currentScale: CGFloat = 1.0
        var currentRotation: CGFloat = 0.0
        var hoverAmount: CGFloat = 0.0
        var pressAmount: CGFloat = 0.0
        var isVisibleOnStage: Bool = false
    }
    
    var snapshots: [BotCardSnapshot] = []
    var cardWidth: CGFloat = 126
    var cardHeight: CGFloat = 170
    var cardCornerRadius: CGFloat = 15
    var isDark: Bool = false
    var onActiveIndexChanged: ((Int) -> Void)?
    var onInspectBot: ((AIBotID) -> Void)?
    
    private var slots: [CardLayerSlot] = []
    private var lastAppliedStateSignature: String = ""
    private var deckTrackingArea: NSTrackingArea?
    
    // Continuous deck position in [0, count - 1] (with rubber-banding at ends)
    private var position: CGFloat = 0
    private var reportedIndex: Int = 0
    
    // 120Hz ProMotion CADisplayLink spring & hover/press state
    private var displayLink: CADisplayLink?
    private var isPositionSpringActive = false
    private var springTarget: CGFloat = 0
    private var springVelocity: CGFloat = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    
    // Hover & tactile press state
    private var hoveredCardIndex: Int?
    private var pressedCardIndex: Int?
    
    // Direct gesture tracking
    private var isTrackpadDragging = false
    private var lastScrollSampleTime: CFTimeInterval = 0
    private var smoothedScrollVelocity: CGFloat = 0 // in cards/sec
    
    private var mouseDownPoint: CGPoint?
    private var mouseDragStartPosition: CGFloat = 0
    private var isMouseDragging = false
    private var lastMouseSampleTime: CFTimeInterval = 0
    private var lastMouseX: CGFloat = 0
    private var mouseVelocity: CGFloat = 0 // in cards/sec
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .never
        if let root = self.layer {
            root.masksToBounds = true
            root.cornerRadius = 14
            root.cornerCurve = .continuous
            root.borderWidth = 0.75
        }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = self.deckTrackingArea {
            self.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.deckTrackingArea = area
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window == nil {
            self.stopDisplayLink()
            self.hoveredCardIndex = nil
            self.pressedCardIndex = nil
        }
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.applyPositionsImmediately()
    }
    
    func configure(
        snapshots: [BotCardSnapshot],
        targetIndex: Int,
        stepToken: Int,
        lastHandledStepToken: inout Int,
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        isDark: Bool
    ) {
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.isDark = isDark
        self.snapshots = snapshots
        
        if let root = self.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            root.backgroundColor = isDark
                ? NSColor.white.withAlphaComponent(0.032).cgColor
                : NSColor.black.withAlphaComponent(0.024).cgColor
            root.borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.09).cgColor
                : NSColor.black.withAlphaComponent(0.07).cgColor
            CATransaction.commit()
        }
        
        let maxIdx = max(0, snapshots.count - 1)
        let clampedTarget = min(maxIdx, max(0, targetIndex))
        
        // Rebuild or refresh static card textures only when snapshot content/theme actually changed
        let sig = "\(isDark)|\(Int(cardWidth))x\(Int(cardHeight))|" + snapshots.map {
            let pTok = $0.portraitImage.map { String(UInt(bitPattern: ObjectIdentifier($0))) } ?? "0"
            return "\($0.botID.rawValue):\($0.shortTitle):\($0.accentHex):\($0.isEnabled):\(pTok)"
        }.joined(separator: ",")
        
        if sig != self.lastAppliedStateSignature {
            let isFirstMount = self.lastAppliedStateSignature.isEmpty
            self.lastAppliedStateSignature = sig
            self.rebuildCardLayers()
            if isFirstMount {
                self.position = CGFloat(clampedTarget)
                self.springTarget = self.position
                self.reportedIndex = clampedTarget
            }
            self.applyPositionsImmediately()
        }
        
        if stepToken != lastHandledStepToken {
            lastHandledStepToken = stepToken
            self.reportedIndex = clampedTarget
            self.animateToIndex(clampedTarget, initialVelocity: 0)
        }
    }
    
    private func rebuildCardLayers() {
        guard let root = self.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        
        while self.slots.count > self.snapshots.count {
            let removed = self.slots.removeLast()
            removed.container.removeFromSuperlayer()
        }
        while self.slots.count < self.snapshots.count {
            let slot = CardLayerSlot()
            slot.container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            slot.container.shadowColor = NSColor.black.cgColor
            slot.container.shadowRadius = 7.0
            slot.container.shadowOffset = CGSize(width: 0, height: -4)
            
            slot.face.contentsGravity = .resizeAspectFill
            slot.face.contentsScale = 2.0
            slot.container.addSublayer(slot.face)
            
            slot.dimScrim.cornerCurve = .continuous
            slot.dimScrim.backgroundColor = NSColor.black.cgColor
            slot.dimScrim.opacity = 0
            slot.container.addSublayer(slot.dimScrim)
            
            slot.focusRing.cornerCurve = .continuous
            slot.focusRing.borderWidth = 1.75
            slot.focusRing.backgroundColor = nil
            slot.container.addSublayer(slot.focusRing)
            
            slot.hoverBorder.cornerCurve = .continuous
            slot.hoverBorder.borderWidth = 1.25
            slot.hoverBorder.backgroundColor = nil
            slot.hoverBorder.opacity = 0
            slot.container.addSublayer(slot.hoverBorder)
            
            root.addSublayer(slot.container)
            self.slots.append(slot)
        }
        
        let cardBounds = CGRect(x: 0, y: 0, width: self.cardWidth, height: self.cardHeight)
        let shadowCGPath = CGPath(
            roundedRect: cardBounds,
            cornerWidth: self.cardCornerRadius,
            cornerHeight: self.cardCornerRadius,
            transform: nil
        )
        
        for (idx, snap) in self.snapshots.enumerated() {
            let slot = self.slots[idx]
            slot.container.bounds = cardBounds
            slot.container.shadowPath = shadowCGPath
            slot.container.shadowOpacity = self.isDark ? 0.36 : 0.14
            
            slot.face.frame = cardBounds
            slot.face.contents = PackBakedCardTextureCache.shared.texture(
                for: snap,
                width: self.cardWidth,
                height: self.cardHeight,
                cornerRadius: self.cardCornerRadius,
                isDark: self.isDark
            )
            
            slot.dimScrim.frame = cardBounds
            slot.dimScrim.cornerRadius = self.cardCornerRadius
            
            slot.focusRing.frame = cardBounds
            slot.focusRing.cornerRadius = self.cardCornerRadius
            slot.focusRing.borderColor = NSColor(Color(hexString: snap.accentHex)).cgColor
            
            slot.hoverBorder.frame = cardBounds
            slot.hoverBorder.cornerRadius = self.cardCornerRadius
            slot.hoverBorder.borderColor = (self.isDark
                ? NSColor.white.withAlphaComponent(0.45)
                : NSColor.white.withAlphaComponent(0.95)).cgColor
        }
    }
    
    // MARK: Fan Curve & Zero-Allocation 3D Layer Transform Commit
    
    private static func rubberBanded(_ raw: CGFloat, maxIndex: CGFloat) -> CGFloat {
        if raw < 0 {
            return raw * 0.25
        } else if raw > maxIndex {
            return maxIndex + (raw - maxIndex) * 0.25
        }
        return raw
    }
    
    private func applyPositionsImmediately() {
        guard !self.slots.isEmpty, self.bounds.width > 10 else { return }
        let stageCenterX = self.bounds.width * 0.5
        let stageCenterY = self.bounds.height * 0.5 + 2.0
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (idx, slot) in self.slots.enumerated() {
            let delta = CGFloat(idx) - self.position
            let absDelta = abs(delta)
            
            // Strictly cull cards beyond ±3.45 so at most 7 layers are ever visible and all stay well inside 527pt!
            if absDelta > 3.45 {
                if !slot.container.isHidden {
                    slot.container.isHidden = true
                }
                slot.isVisibleOnStage = false
                continue
            }
            if slot.container.isHidden {
                slot.container.isHidden = false
            }
            slot.isVisibleOnStage = true
            
            let hover = slot.hoverAmount
            let press = slot.pressAmount
            
            // Smooth 3D CoverFlow fan with subtle hover peek & tactile press compression
            let offsetX = CGFloat(tanh(Double(delta) * 0.46)) * 196.0
            let baseDropY = min(15.0, delta * delta * 1.70)
            let hoverLiftY: CGFloat = (absDelta > 0.35 ? 6.5 : 2.5) * hover
            let pressSinkY: CGFloat = -2.0 * press
            
            let baseScale = max(0.71, 1.0 - absDelta * 0.092)
            let hoverScaleBoost: CGFloat = (absDelta > 0.35 ? 0.032 : 0.018) * hover
            let pressScaleDip: CGFloat = -0.028 * press
            let scale = max(0.66, baseScale + hoverScaleBoost + pressScaleDip)
            
            let rotationZ = -CGFloat(tanh(Double(delta) * 0.54)) * (4.8 * .pi / 180.0) * (1.0 - hover * 0.22)
            let rotationY = -CGFloat(tanh(Double(delta) * 0.68)) * (13.5 * .pi / 180.0) * (1.0 - hover * 0.30)
            
            let opacity: Float = absDelta <= 2.65
                ? 1.0
                : Float(max(0.0, (3.45 - absDelta) / 0.80))
            let focusOpacity = Float(max(0.0, 1.0 - absDelta * 1.45))
            
            // Depth scrim darkens distant cards subtly and lifts away smoothly on hover or focus
            let rawDim = min(0.32, Double(absDelta) * (self.isDark ? 0.13 : 0.085))
            let scrimAlpha = Float(max(0.0, rawDim * (1.0 - Double(hover) * 0.72)))
            
            let center = CGPoint(x: stageCenterX + offsetX, y: stageCenterY - baseDropY + hoverLiftY + pressSinkY)
            slot.currentCenter = center
            slot.currentScale = scale
            slot.currentRotation = rotationZ
            
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 920.0
            transform = CATransform3DScale(transform, scale, scale, 1.0)
            transform = CATransform3DRotate(transform, rotationY, 0, 1, 0)
            transform = CATransform3DRotate(transform, rotationZ, 0, 0, 1)
            
            slot.container.position = center
            slot.container.transform = transform
            slot.container.opacity = opacity
            slot.container.zPosition = 200.0 - absDelta * 20.0 + (hover * 3.0)
            slot.container.shadowRadius = CGFloat(max(4.0, (12.0 - Double(absDelta) * 2.4) + Double(hover) * 2.5 - Double(press) * 3.0))
            slot.container.shadowOpacity = Float(
                (self.isDark ? 0.44 : 0.18) * max(0.45, 1.0 - Double(absDelta) * 0.18) + Double(hover) * 0.05
            )
            slot.dimScrim.opacity = scrimAlpha
            slot.focusRing.opacity = focusOpacity
            slot.hoverBorder.opacity = Float(hover * (absDelta > 0.35 ? 0.92 : 0.55))
        }
        CATransaction.commit()
    }
    
    private func notifyNearestIndexIfChanged(haptic: Bool = false) {
        guard !self.snapshots.isEmpty else { return }
        let maxIdx = max(0, self.snapshots.count - 1)
        let nearest = min(maxIdx, max(0, Int(self.position.rounded())))
        if nearest != self.reportedIndex {
            self.reportedIndex = nearest
            if haptic {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            self.onActiveIndexChanged?(nearest)
        }
    }
    
    // MARK: 120Hz ProMotion Spring + Hover/Press Loop
    
    private func ensureDisplayLinkRunning() {
        guard self.displayLink == nil else { return }
        self.lastFrameTimestamp = CACurrentMediaTime()
        let link = self.displayLink(target: self, selector: #selector(self.stepFrame(_:)))
        if #available(macOS 14.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }
    
    private func animateToIndex(_ index: Int, initialVelocity: CGFloat) {
        let maxIdx = max(0, self.snapshots.count - 1)
        let clamped = CGFloat(min(maxIdx, max(0, index)))
        self.springTarget = clamped
        self.springVelocity = initialVelocity
        
        if abs(self.position - clamped) < 0.001 && abs(initialVelocity) < 0.01 {
            self.position = clamped
            self.isPositionSpringActive = false
            self.applyPositionsImmediately()
            self.notifyNearestIndexIfChanged()
            return
        }
        
        self.isPositionSpringActive = true
        self.ensureDisplayLinkRunning()
    }
    
    private func stopSpring() {
        self.isPositionSpringActive = false
        self.springVelocity = 0
    }
    
    private func stopDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.isPositionSpringActive = false
        self.springVelocity = 0
    }
    
    @objc private func stepFrame(_ link: CADisplayLink) {
        let now = link.timestamp > 0 ? link.timestamp : CACurrentMediaTime()
        let rawDT = now - self.lastFrameTimestamp
        self.lastFrameTimestamp = now
        let dt = CGFloat(min(1.0 / 30.0, max(1.0 / 240.0, rawDT)))
        var anyMoving = false
        
        if self.isPositionSpringActive {
            // Smooth lightly underdamped harmonic spring (zeta = 0.88, omega = 19.5 rad/s -> tactile Apple CoverFlow settle)
            let omega: CGFloat = 19.5
            let zeta: CGFloat = 0.88
            let x = self.position - self.springTarget
            let v = self.springVelocity
            let accel = -(omega * omega) * x - (2.0 * zeta * omega) * v
            let vNext = v + accel * dt
            let xNext = x + vNext * dt
            
            if abs(xNext) < 0.0014 && abs(vNext) < 0.014 {
                self.position = self.springTarget
                self.springVelocity = 0
                self.isPositionSpringActive = false
            } else {
                self.position = self.springTarget + xNext
                self.springVelocity = vNext
                anyMoving = true
            }
            self.notifyNearestIndexIfChanged()
        }
        
        // Smooth 120Hz exponential interpolation for per-card hover peek & press depth
        let hoverAlpha = min(1.0, 1.0 - exp(-20.0 * dt))
        let pressAlpha = min(1.0, 1.0 - exp(-28.0 * dt))
        for (idx, slot) in self.slots.enumerated() {
            let hoverTarget: CGFloat = (!self.isMouseDragging && !self.isTrackpadDragging && self.hoveredCardIndex == idx) ? 1.0 : 0.0
            let pressTarget: CGFloat = (!self.isMouseDragging && self.pressedCardIndex == idx) ? 1.0 : 0.0
            
            if abs(slot.hoverAmount - hoverTarget) > 0.004 {
                slot.hoverAmount += (hoverTarget - slot.hoverAmount) * hoverAlpha
                anyMoving = true
            } else {
                slot.hoverAmount = hoverTarget
            }
            
            if abs(slot.pressAmount - pressTarget) > 0.004 {
                slot.pressAmount += (pressTarget - slot.pressAmount) * pressAlpha
                anyMoving = true
            } else {
                slot.pressAmount = pressTarget
            }
        }
        
        self.applyPositionsImmediately()
        if !anyMoving {
            self.stopDisplayLink()
        }
    }
    
    // MARK: Card Hit-Testing & Hover Tracking
    
    private func hitTestCardIndex(at point: CGPoint) -> Int? {
        let hitIndices = self.slots.indices
            .filter { self.slots[$0].isVisibleOnStage }
            .sorted { abs(CGFloat($0) - self.position) < abs(CGFloat($1) - self.position) }
        
        for idx in hitIndices {
            let slot = self.slots[idx]
            let dx = point.x - slot.currentCenter.x
            let dy = point.y - slot.currentCenter.y
            let cosA = cos(-slot.currentRotation)
            let sinA = sin(-slot.currentRotation)
            let localX = (dx * cosA - dy * sinA) / max(0.2, slot.currentScale)
            let localY = (dx * sinA + dy * cosA) / max(0.2, slot.currentScale)
            if abs(localX) <= self.cardWidth * 0.5 && abs(localY) <= self.cardHeight * 0.5 {
                return idx
            }
        }
        return nil
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard !self.isMouseDragging else { return }
        let pt = self.convert(event.locationInWindow, from: nil)
        let hit = self.hitTestCardIndex(at: pt)
        if hit != self.hoveredCardIndex {
            self.hoveredCardIndex = hit
            self.ensureDisplayLinkRunning()
        }
        if hit != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if self.hoveredCardIndex != nil {
            self.hoveredCardIndex = nil
            self.ensureDisplayLinkRunning()
        }
        if !self.isMouseDragging {
            NSCursor.arrow.set()
        }
    }
    
    // MARK: Trackpad Two-Finger Swipe & Mouse Wheel
    
    override func scrollWheel(with event: NSEvent) {
        guard !self.snapshots.isEmpty else {
            super.scrollWheel(with: event)
            return
        }
        
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        
        // Pass vertical scrolling straight through to the parent Settings ScrollView
        if !self.isTrackpadDragging && abs(dy) > abs(dx) * 1.15 {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        
        let maxIdx = CGFloat(max(0, self.snapshots.count - 1))
        
        if event.hasPreciseScrollingDeltas {
            if event.phase == .mayBegin {
                self.stopSpring()
                return
            }
            if event.phase == .began || event.phase == .changed {
                if !self.isTrackpadDragging {
                    self.isTrackpadDragging = true
                    self.hoveredCardIndex = nil
                    self.stopSpring()
                    self.smoothedScrollVelocity = 0
                    self.lastScrollSampleTime = CACurrentMediaTime()
                }
                let now = CACurrentMediaTime()
                let dt = max(0.004, now - self.lastScrollSampleTime)
                self.lastScrollSampleTime = now
                
                let deltaCards = -dx / 84.0
                let instVel = deltaCards / CGFloat(dt)
                self.smoothedScrollVelocity = self.smoothedScrollVelocity * 0.55 + instVel * 0.45
                
                let unclamped = self.position + deltaCards
                self.position = Self.rubberBanded(unclamped, maxIndex: maxIdx)
                self.applyPositionsImmediately()
                self.notifyNearestIndexIfChanged(haptic: true)
                return
            }
            if event.phase == .ended || event.phase == .cancelled {
                guard self.isTrackpadDragging else { return }
                self.isTrackpadDragging = false
                let v = min(14.0, max(-14.0, self.smoothedScrollVelocity))
                let projected = self.position + v * 0.14
                let targetIdx = min(Int(maxIdx), max(0, Int(projected.rounded())))
                self.animateToIndex(targetIdx, initialVelocity: v * 0.55)
                return
            }
            if !event.momentumPhase.isEmpty {
                return
            }
        } else if abs(dx) > 0.05 {
            let baseIdx = Int((self.isPositionSpringActive ? self.springTarget : self.position).rounded())
            let step = dx > 0 ? -1 : 1
            let nextIdx = min(Int(maxIdx), max(0, baseIdx + step))
            if nextIdx != baseIdx {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
            self.animateToIndex(nextIdx, initialVelocity: 0)
        } else {
            self.nextResponder?.scrollWheel(with: event)
        }
    }
    
    // MARK: Mouse Click & 1:1 Drag
    
    override func mouseDown(with event: NSEvent) {
        let pt = self.convert(event.locationInWindow, from: nil)
        self.mouseDownPoint = pt
        self.mouseDragStartPosition = self.position
        self.isMouseDragging = false
        self.mouseVelocity = 0
        self.lastMouseX = pt.x
        self.lastMouseSampleTime = CACurrentMediaTime()
        self.pressedCardIndex = self.hitTestCardIndex(at: pt)
        self.stopSpring()
        if self.pressedCardIndex != nil {
            self.ensureDisplayLinkRunning()
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let startPt = self.mouseDownPoint, !self.snapshots.isEmpty else { return }
        let pt = self.convert(event.locationInWindow, from: nil)
        let totalDX = pt.x - startPt.x
        if !self.isMouseDragging && abs(totalDX) > 4 {
            self.isMouseDragging = true
            self.pressedCardIndex = nil
            self.hoveredCardIndex = nil
            NSCursor.closedHand.set()
        }
        guard self.isMouseDragging else { return }
        
        let now = CACurrentMediaTime()
        let dt = max(0.004, now - self.lastMouseSampleTime)
        let stepDX = pt.x - self.lastMouseX
        self.lastMouseSampleTime = now
        self.lastMouseX = pt.x
        
        let instVel = (-stepDX / 84.0) / CGFloat(dt)
        self.mouseVelocity = self.mouseVelocity * 0.55 + instVel * 0.45
        
        let maxIdx = CGFloat(max(0, self.snapshots.count - 1))
        let raw = self.mouseDragStartPosition - (totalDX / 84.0)
        self.position = Self.rubberBanded(raw, maxIndex: maxIdx)
        self.applyPositionsImmediately()
        self.notifyNearestIndexIfChanged(haptic: true)
    }
    
    override func mouseUp(with event: NSEvent) {
        defer {
            self.mouseDownPoint = nil
            self.isMouseDragging = false
            if self.pressedCardIndex != nil {
                self.pressedCardIndex = nil
                self.ensureDisplayLinkRunning()
            }
        }
        guard !self.snapshots.isEmpty else { return }
        let maxIdx = max(0, self.snapshots.count - 1)
        let pt = self.convert(event.locationInWindow, from: nil)
        
        if self.isMouseDragging {
            let v = min(14.0, max(-14.0, self.mouseVelocity))
            let projected = self.position + v * 0.14
            let targetIdx = min(maxIdx, max(0, Int(projected.rounded())))
            self.animateToIndex(targetIdx, initialVelocity: v * 0.55)
            let hoverAfter = self.hitTestCardIndex(at: pt)
            self.hoveredCardIndex = hoverAfter
            (hoverAfter != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
            return
        }
        
        if let idx = self.hitTestCardIndex(at: pt) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            if abs(CGFloat(idx) - self.position) > 0.32 {
                self.animateToIndex(idx, initialVelocity: 0)
            } else {
                self.onInspectBot?(self.snapshots[idx].botID)
            }
            return
        }
        
        let nearest = min(maxIdx, max(0, Int(self.position.rounded())))
        self.animateToIndex(nearest, initialVelocity: 0)
    }
}


private struct PackCoreAnimationDeckView: NSViewRepresentable {
    
    let snapshots: [BotCardSnapshot]
    let activeIndex: Int
    let externalStepToken: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isDark: Bool
    let onActiveIndexChanged: (Int) -> Void
    let onInspectBot: (AIBotID) -> Void
    
    final class Coordinator {
        var lastHandledStepToken: Int = 0
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> PackCoreAnimationStageNSView {
        let view = PackCoreAnimationStageNSView()
        view.onActiveIndexChanged = self.onActiveIndexChanged
        view.onInspectBot = self.onInspectBot
        view.configure(
            snapshots: self.snapshots,
            targetIndex: self.activeIndex,
            stepToken: self.externalStepToken,
            lastHandledStepToken: &context.coordinator.lastHandledStepToken,
            cardWidth: self.cardWidth,
            cardHeight: self.cardHeight,
            isDark: self.isDark
        )
        return view
    }
    
    func updateNSView(_ nsView: PackCoreAnimationStageNSView, context: Context) {
        nsView.onActiveIndexChanged = self.onActiveIndexChanged
        nsView.onInspectBot = self.onInspectBot
        nsView.configure(
            snapshots: self.snapshots,
            targetIndex: self.activeIndex,
            stepToken: self.externalStepToken,
            lastHandledStepToken: &context.coordinator.lastHandledStepToken,
            cardWidth: self.cardWidth,
            cardHeight: self.cardHeight,
            isDark: self.isDark
        )
    }
}


struct AIBotsSettingsView: View {
    
    /// Exact deterministic content width (`780 - 204 sidebar - 1 divider - 48 padding = 527pt`).
    private static let fixedStageWidth: CGFloat = 527
    private static let galleryColumns = 4
    private static let galleryGap: CGFloat = 13
    private static let galleryCardWidth: CGFloat = 122
    private static let galleryCardHeight: CGFloat = 122
    private static let galleryRowStride: CGFloat = 172
    private static let packCardWidth: CGFloat = 148
    private static let packCardHeight: CGFloat = 148
    private static let packStageHeight: CGFloat = 204
    
    var settingsState: SidebarSettingsState? = nil
    var initialLayoutMode: BotCollectionLayoutMode = .card
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var botStore = AIBotStore.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var piKernel = PiKernelManager.shared
    @State private var layoutMode: BotCollectionLayoutMode = .card
    @State private var didApplyInitialMode = false
    @State private var inspectingBot: AIBotID?
    @State private var allEndpoints: [AIEndpointProfile] = []
    @State private var activeEndpoint: AIEndpointProfile?
    @State private var packActiveIndex: Int = 0
    @State private var packExternalStepToken: Int = 0
    @State private var snapshots: [BotCardSnapshot] = []
    @State private var prewarmTask: Task<Void, Never>?
    @State private var isShowingCreateBot = false
    @State private var editingCustomBot: CustomBotProfile? = nil
    
    @Namespace private var modePillNamespace
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let botID = self.inspectingBot {
                self.inlineInspector(for: botID)
                    .transition(.opacity)
            } else {
                self.morphingCollectionView
                    .transition(.opacity)
            }
        }
        .frame(width: Self.fixedStageWidth, alignment: .topLeading)
        .onAppear {
            if !self.didApplyInitialMode {
                self.didApplyInitialMode = true
                self.layoutMode = self.initialLayoutMode
            }
            self.reload(cachedImagesOnly: true)
            self.consumePendingBotSelection()
            self.startAsyncPortraitPrewarm()
        }
        .onDisappear {
            self.prewarmTask?.cancel()
        }
        .onChange(of: self.settingsState?.pendingBotID) { _, _ in
            self.consumePendingBotSelection()
        }
        .onChange(of: self.settingsState?.pendingCustomBotID) { _, _ in
            self.consumePendingBotSelection()
        }
        .onChange(of: self.settingsState?.pendingCreateCustomBot) { _, _ in
            if self.settingsState?.pendingCreateCustomBot == true {
                self.settingsState?.pendingCreateCustomBot = false
                self.isShowingCreateBot = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload(cachedImagesOnly: true)
            self.startAsyncPortraitPrewarm()
        }
        .sheet(isPresented: self.$isShowingCreateBot) {
            CustomBotCreationSheet { _ in
                self.reload(cachedImagesOnly: true)
            }
        }
        .sheet(item: self.$editingCustomBot) { customBot in
            CustomBotCreationSheet(editingBot: customBot) { _ in
                self.reload(cachedImagesOnly: true)
            }
        }
    }
    
    
    private func consumePendingBotSelection() {
        if self.settingsState?.pendingCreateCustomBot == true {
            self.settingsState?.pendingCreateCustomBot = false
            self.isShowingCreateBot = true
        }
        if let customID = self.settingsState?.pendingCustomBotID {
            self.settingsState?.pendingCustomBotID = nil
            self.inspectingBot = nil
            if let found = self.botStore.customBots.first(where: { $0.id == customID }) {
                self.editingCustomBot = found
            }
            return
        }
        guard let pending = self.settingsState?.pendingBotID else { return }
        self.inspectingBot = pending
        self.settingsState?.pendingBotID = nil
    }
    
    
    private func botDisplayTitle(for botID: AIBotID) -> String {
        let name = self.botStore.resolvedName(for: botID)
        if name != botID.displayName {
            return "\(name) · \(botID.displayName)"
        }
        return botID.displayName
    }
    
    
    private func resolvedEndpoint(for config: AIBotConfig) -> AIEndpointProfile? {
        if let endpointID = config.endpointID,
           let matched = self.allEndpoints.first(where: { $0.id == endpointID })
        {
            return matched
        }
        return self.activeEndpoint
    }
    
    
    private func resolvedCharacter(for botID: AIBotID, config: AIBotConfig) -> AIGijinkaCharacter? {
        let endpoint = self.resolvedEndpoint(for: config)
        let overrideModel = config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !overrideModel.isEmpty {
            return AIGijinkaCharacter.resolve(
                modelName: overrideModel,
                endpointName: endpoint?.displayName,
                baseURL: endpoint?.baseURL
            )
        }
        return AIGijinkaCharacter.resolve(
            modelName: endpoint?.displayModel,
            endpointName: endpoint?.displayName,
            baseURL: endpoint?.baseURL
        ) ?? .claude
    }
    
    
    private func rebuildSnapshots(cachedImagesOnly: Bool) {
        let featureCounts = Dictionary(
            self.analytics.featureDistribution(days: 30).map { ($0.feature, $0.requests) },
            uniquingKeysWith: { first, _ in first }
        )
        
        var nextSnapshots: [BotCardSnapshot] = []
        nextSnapshots.reserveCapacity(AIBotID.allCases.count)
        
        for botID in AIBotID.allCases {
            let config = self.botStore.config(for: botID)
            let endpoint = self.resolvedEndpoint(for: config)
            let character = self.resolvedCharacter(for: botID, config: config)
            let portrait = self.botStore.resolvedPortraitImage(
                for: botID,
                pointWidth: Self.packCardWidth,
                pointHeight: Self.packCardHeight,
                cachedOnly: cachedImagesOnly
            )
            let resolvedName = self.botStore.resolvedName(for: botID)
            let resolvedNickname = self.botStore.resolvedNickname(for: botID)
            let effectiveModel = config.modelOverride.isEmpty
                ? (endpoint?.displayModel ?? AppLanguage.text("未选择模型", en: "No Model"))
                : config.modelOverride
            
            nextSnapshots.append(BotCardSnapshot(
                botID: botID,
                displayTitle: self.botDisplayTitle(for: botID),
                shortTitle: resolvedName,
                subtitle: "@\(resolvedNickname)",
                personaBadge: "@\(resolvedNickname)",
                modelLabel: effectiveModel,
                accentHex: character?.accentHex ?? botID.accentHex,
                isEnabled: config.isEnabled,
                recentCalls: featureCounts[botID.analyticsFeatureKey] ?? 0,
                portraitImage: portrait
            ))
        }
        self.snapshots = nextSnapshots
    }
    
    
    /// Pre-decodes uncached Retina ~3:4 portrait bitmaps off the main thread so opening Bots never stutters.
    private func startAsyncPortraitPrewarm() {
        self.prewarmTask?.cancel()
        let missingWork: [(artwork: AIGijinkaArtwork, source: NSImage)] = AIBotID.allCases.compactMap { botID in
            guard self.botStore.customAvatarImage(for: botID) == nil else { return nil }
            let cfg = self.botStore.config(for: botID)
            guard let character = self.resolvedCharacter(for: botID, config: cfg) else { return nil }
            let artwork = character.artwork(for: botID, variantOverride: cfg.artworkVariantIndex)
            if AIGijinkaImageLoader.shared.cachedPortraitCard(
                for: artwork,
                pointWidth: Self.packCardWidth,
                pointHeight: Self.packCardHeight
            ) != nil {
                return nil
            }
            guard let src = AIGijinkaImageLoader.shared.image(for: artwork) else { return nil }
            return (artwork, src)
        }
        guard !missingWork.isEmpty else {
            if self.snapshots.contains(where: { $0.portraitImage == nil }) {
                self.rebuildSnapshots(cachedImagesOnly: false)
            }
            return
        }
        
        let targetW = Self.packCardWidth
        let targetH = Self.packCardHeight
        self.prewarmTask = Task(priority: .userInitiated) {
            let rendered = await Self.renderMissingPortraits(missingWork, width: targetW, height: targetH)
            guard !Task.isCancelled else { return }
            for (art, bmp) in rendered {
                AIGijinkaImageLoader.shared.storePortraitCard(bmp, for: art, pointWidth: targetW, pointHeight: targetH)
            }
            self.rebuildSnapshots(cachedImagesOnly: false)
            let isDark = (self.colorScheme == .dark)
            for snap in self.snapshots {
                await Task.yield()
                guard !Task.isCancelled else { return }
                _ = PackBakedCardTextureCache.shared.texture(
                    for: snap,
                    width: Self.packCardWidth,
                    height: Self.packCardHeight,
                    cornerRadius: 15,
                    isDark: isDark
                )
            }
        }
    }
    
    
    @concurrent private static func renderMissingPortraits(
        _ work: [(artwork: AIGijinkaArtwork, source: NSImage)],
        width: CGFloat,
        height: CGFloat
    ) async -> [(AIGijinkaArtwork, NSImage)] {
        var rendered: [(AIGijinkaArtwork, NSImage)] = []
        var seen = Set<String>()
        for entry in work where seen.insert(entry.artwork.id).inserted {
            if Task.isCancelled { break }
            if let bitmap = AIGijinkaImageLoader.renderPortraitBitmap(
                from: entry.source,
                cropAnchor: entry.artwork.cropAnchor,
                pointWidth: width,
                pointHeight: height
            ) {
                rendered.append((entry.artwork, bitmap))
            }
        }
        return rendered
    }
    
    
    // MARK: - Morphing Gallery / List / Stack Stage
    
    @ViewBuilder
    private var morphingCollectionView: some View {
        let count = max(1, self.snapshots.count)
        let maxIndex = max(0, count - 1)
        let liveNearestIndex = min(maxIndex, max(0, self.packActiveIndex))
        let rowsCount = Int(ceil(Double(count) / Double(Self.galleryColumns)))
        let stageHeight: CGFloat = switch self.layoutMode {
            case .list: CGFloat(count) * 56.0
            case .card: CGFloat(rowsCount) * Self.galleryRowStride
            case .pack: Self.packStageHeight + 88.0
        }
        let enabledCount = self.snapshots.filter(\.isEnabled).count
        let focusedPackSnap: BotCardSnapshot? = self.snapshots.indices.contains(liveNearestIndex)
            ? self.snapshots[liveNearestIndex]
            : self.snapshots.first
        let isDark = (self.colorScheme == .dark)
        
        VStack(alignment: .leading, spacing: 14) {
            // Segmented Layout Switcher
            HStack(spacing: 4) {
                ForEach(BotCollectionLayoutMode.allCases) { mode in
                    let isSelected = (self.layoutMode == mode)
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.layoutMode = mode
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.08))
                                        .matchedGeometryEffect(id: "botLayoutPill", in: self.modePillNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Spacer()
                
                Text("\(enabledCount)/\(self.snapshots.count) \(AppLanguage.text("已启用", en: "Active"))")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Button {
                    self.isShowingCreateBot = true
                } label: {
                    Label(AppLanguage.text("新建 Bot", en: "New Bot"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Rectangle()
                .fill(self.cardBorder)
                .frame(height: 1)
                .opacity(self.layoutMode == .card ? 0.0 : 1.0)
            
            // Stage
            if self.layoutMode == .pack {
                VStack(spacing: 9) {
                    PackCoreAnimationDeckView(
                        snapshots: self.snapshots,
                        activeIndex: liveNearestIndex,
                        externalStepToken: self.packExternalStepToken,
                        cardWidth: Self.packCardWidth,
                        cardHeight: Self.packCardHeight,
                        isDark: isDark,
                        onActiveIndexChanged: { nextIndex in
                            if self.packActiveIndex != nextIndex {
                                self.packActiveIndex = nextIndex
                            }
                        },
                        onInspectBot: { botID in
                            withAnimation(.easeOut(duration: 0.16)) {
                                self.inspectingBot = botID
                            }
                        }
                    )
                    .frame(width: Self.fixedStageWidth, height: Self.packStageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    
                    // Interactive deck progress pills
                    HStack(spacing: 5) {
                        ForEach(Array(self.snapshots.enumerated()), id: \.element.id) { idx, snap in
                            let isCurrent = (idx == liveNearestIndex)
                            let pillAccent = Color(hexString: snap.accentHex)
                            Button {
                                guard idx != liveNearestIndex else { return }
                                self.packActiveIndex = idx
                                self.packExternalStepToken &+= 1
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            } label: {
                                Capsule(style: .continuous)
                                    .fill(isCurrent
                                          ? pillAccent
                                          : Color.primary.opacity(isDark ? 0.18 : 0.14))
                                    .frame(width: isCurrent ? 18 : 5.5, height: 5.5)
                                    .animation(.snappy(duration: 0.22, extraBounce: 0), value: liveNearestIndex)
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                            .help(snap.displayTitle)
                        }
                    }
                    .frame(height: 10)
                    
                    if let focusedSnap = focusedPackSnap {
                        self.packBottomDockBar(
                            focusedSnap: focusedSnap,
                            activeIndex: liveNearestIndex,
                            total: count,
                            isDark: isDark
                        )
                    }
                }
                .frame(width: Self.fixedStageWidth, height: stageHeight, alignment: .topLeading)
                .clipped()
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(self.snapshots.enumerated()), id: \.element.id) { index, snap in
                        self.stageNode(
                            snap: snap,
                            index: index,
                            isDark: isDark
                        )
                    }
                }
                .frame(width: Self.fixedStageWidth, height: stageHeight, alignment: .topLeading)
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(self.piKernel.isAvailable && self.piKernel.isKernelEnabled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(self.piKernel.statusSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 2)
            
            CustomBotsRosterSection(
                cardSurface: self.cardSurface,
                cardBorder: self.cardBorder,
                onCreateNew: { self.isShowingCreateBot = true },
                onEditBot: { self.editingCustomBot = $0 }
            )
        }
    }
    
    
    @ViewBuilder
    private func stageNode(
        snap: BotCardSnapshot,
        index: Int,
        isDark: Bool
    ) -> some View {
        let botID = snap.botID
        let accent = Color(hexString: snap.accentHex)
        
        let artW: CGFloat = self.layoutMode == .list ? 44 : Self.galleryCardWidth
        let artH: CGFloat = self.layoutMode == .list ? 44 : Self.galleryCardHeight
        let artCorner: CGFloat = self.layoutMode == .list ? 10 : 15
        let itemW: CGFloat = self.layoutMode == .list ? Self.fixedStageWidth : artW
        let itemH: CGFloat = self.layoutMode == .list ? 44 : (artH + 40)
        let posX: CGFloat = self.layoutMode == .list ? 0 : CGFloat(index % Self.galleryColumns) * (artW + Self.galleryGap)
        let posY: CGFloat = self.layoutMode == .list ? CGFloat(index) * 56.0 : CGFloat(index / Self.galleryColumns) * Self.galleryRowStride
        
        ZStack(alignment: .topLeading) {
            BotPortraitTileSurface(
                botID: botID,
                shortTitle: snap.shortTitle,
                accentHex: snap.accentHex,
                isEnabled: snap.isEnabled,
                portraitImage: snap.portraitImage,
                width: artW,
                height: artH,
                cornerRadius: artCorner,
                showPackOverlay: false,
                isPackCenter: false,
                isDark: isDark
            )
            .equatable()
            .contentShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.18)) {
                    self.inspectingBot = botID
                }
            }
            
            if self.layoutMode == .list {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(snap.displayTitle)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(snap.isEnabled ? .primary : .secondary)
                            if let personaBadge = snap.personaBadge {
                                Text(personaBadge)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(accent.opacity(isDark ? 0.16 : 0.10), in: Capsule())
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text(snap.modelLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            if snap.recentCalls > 0 {
                                Text("· \(snap.recentCalls) 次")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    
                    Spacer(minLength: 6)
                    
                    Toggle("", isOn: Binding(
                        get: { snap.isEnabled },
                        set: { enabled in
                            var updated = self.botStore.config(for: botID)
                            updated.isEnabled = enabled
                            self.botStore.updateConfig(updated, for: botID)
                            self.rebuildSnapshots(cachedImagesOnly: false)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    Button {
                        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                            self.inspectingBot = botID
                        }
                    } label: {
                        Text(AppLanguage.text("配置", en: "Edit"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, artW + 12)
                .frame(width: itemW, height: artH, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        self.inspectingBot = botID
                    }
                }
            }
            
            if self.layoutMode == .card {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(snap.shortTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(snap.isEnabled ? .primary : .secondary)
                            .lineLimit(1)
                        
                        Spacer(minLength: 2)
                        
                        Circle()
                            .fill(snap.isEnabled ? accent : Color.primary.opacity(0.18))
                            .frame(width: 6, height: 6)
                    }
                    
                    Text(snap.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: artW, alignment: .leading)
                .offset(y: artH + 6)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
                        self.inspectingBot = botID
                    }
                }
            }
        }
        .frame(width: itemW, height: itemH, alignment: .topLeading)
        .offset(x: posX, y: posY)
        .zIndex(Double(index))
        .pointerStyle(.link)
    }
    
    
    private func packBottomDockBar(
        focusedSnap: BotCardSnapshot,
        activeIndex: Int,
        total: Int,
        isDark: Bool
    ) -> some View {
        let focusedAccent = Color(hexString: focusedSnap.accentHex)
        
        return HStack(spacing: 10) {
            Circle()
                .fill(focusedSnap.isEnabled ? focusedAccent : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(focusedSnap.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let personaBadge = focusedSnap.personaBadge {
                        Text(personaBadge)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(focusedAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(focusedAccent.opacity(0.14), in: Capsule())
                    }
                }
                Text(focusedSnap.modelLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 6)
            
            HStack(spacing: 4) {
                Button {
                    guard activeIndex > 0 else { return }
                    self.packActiveIndex = activeIndex - 1
                    self.packExternalStepToken &+= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(isDark ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(activeIndex <= 0)
                .opacity(activeIndex <= 0 ? 0.35 : 1.0)
                .pointerStyle(activeIndex <= 0 ? .default : .link)
                
                Text("\(activeIndex + 1)/\(total)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .frame(minWidth: 34)
                
                Button {
                    guard activeIndex + 1 < total else { return }
                    self.packActiveIndex = activeIndex + 1
                    self.packExternalStepToken &+= 1
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(isDark ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(activeIndex + 1 >= total)
                .opacity(activeIndex + 1 >= total ? 0.35 : 1.0)
                .pointerStyle(activeIndex + 1 >= total ? .default : .link)
            }
            
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    self.inspectingBot = focusedSnap.botID
                }
            } label: {
                Text(AppLanguage.text("进入配置", en: "Configure"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(Color.primary.opacity(isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 58, alignment: .leading)
        .frame(width: Self.fixedStageWidth)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
    }
    
    
    // MARK: - Inline Bot Inspector
    
    @ViewBuilder
    private func inlineInspector(for botID: AIBotID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                        self.inspectingBot = nil
                    }
                    self.reload(cachedImagesOnly: false)
                    self.startAsyncPortraitPrewarm()
                } label: {
                    Text(AppLanguage.text("← 返回 Bots", en: "← Back to Bots"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
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
                cardSurface: self.cardSurface,
                cardBorder: self.cardBorder,
                onEndpointsUpdated: {
                    self.reload(cachedImagesOnly: false)
                }
            )
        }
    }
    
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    private func reload(cachedImagesOnly: Bool) {
        let profiles = AIEndpointStore.profiles
        self.allEndpoints = profiles
        let activeID = AIEndpointStore.activeID ?? profiles.first?.id
        self.activeEndpoint = profiles.first(where: { $0.id == activeID })
        self.botStore.reloadFromDatabase()
        self.rebuildSnapshots(cachedImagesOnly: cachedImagesOnly)
    }
}


// MARK: - Inline Bot Inspector (Supports All Configured Subscriptions)

private struct AIBotInlineInspectorView: View {
    
    let botID: AIBotID
    let cardSurface: Color
    let cardBorder: Color
    var onEndpointsUpdated: () -> Void = {}
    
    @State private var botStore = AIBotStore.shared
    @State private var butlerManager = CotButlerManager.shared
    @State private var config: AIBotConfig = AIBotConfig()
    @State private var nicknameDraft: String = ""
    @State private var personaDraft: String = ""
    @State private var pendingAvatarData: Data? = nil
    @State private var pendingAvatarSourceURL: URL? = nil
    @State private var pendingResetAvatar = false
    @State private var gatewayGroups: [AIBotStore.SelectableGatewayGroup] = []
    @State private var isRefreshingModels = false
    @State private var isShowingAvatarLibraryPicker = false
    @State private var savedBannerVisible = false
    
    private var activeGatewayGroup: AIBotStore.SelectableGatewayGroup? {
        self.gatewayGroups.first(where: \.isActive) ?? self.gatewayGroups.first
    }
    
    private var targetGatewayProfile: AIEndpointProfile? {
        if let epID = self.config.endpointID,
           let matched = self.gatewayGroups.first(where: { $0.profile.id == epID })?.profile
        {
            return matched
        }
        return self.activeGatewayGroup?.profile
    }
    
    private var resolvedCharacter: AIGijinkaCharacter? {
        let endpoint = self.targetGatewayProfile
        let overrideModel = self.config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIGijinkaCharacter.resolve(
            modelName: overrideModel.isEmpty ? endpoint?.displayModel : overrideModel,
            endpointName: endpoint?.displayName,
            baseURL: endpoint?.baseURL
        )
    }
    
    private var displayedNickname: String {
        let trimmed = self.nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return self.botID == .butler ? "曜" : self.botID.displayName
    }
    
    private var displayedPortrait: NSImage? {
        if let data = self.pendingAvatarData, let img = NSImage(data: data) {
            return img
        }
        if self.pendingResetAvatar {
            return nil
        }
        return self.botStore.resolvedPortraitImage(for: self.botID, pointWidth: 72, pointHeight: 72)
    }
    
    private var selectedModelLabel: String {
        let defaultModel = self.activeGatewayGroup?.profile.displayModel ?? AIProvider.openCodeGo.defaultModel
        let trimmedOverride = self.config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOverride.isEmpty {
            return AppLanguage.text("跟随当前默认 (\(defaultModel))", en: "Default (\(defaultModel))")
        }
        if let epID = self.config.endpointID,
           let group = self.gatewayGroups.first(where: { $0.profile.id == epID }),
           self.gatewayGroups.count > 1
        {
            return "\(group.title) · \(trimmedOverride)"
        }
        return trimmedOverride
    }
    
    private var hasEffectiveCustomAvatar: Bool {
        if self.pendingAvatarData != nil { return true }
        if self.pendingResetAvatar { return false }
        return self.botStore.customAvatarImage(for: self.botID) != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.headerSummaryRow
            Divider()
            self.avatarPickerRow
            self.nicknameRow
            self.modelPickerRow
            self.personaEditorSection
            Divider()
            self.actionBar
        }
        .padding(14)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
        .task(id: self.botID) {
            self.loadInitialState()
        }
    }
    
    private var headerSummaryRow: some View {
        let accent = Color(hexString: self.resolvedCharacter?.accentHex ?? self.botID.accentHex)
        let shownName = self.displayedNickname
        return HStack(spacing: 14) {
            ZStack {
                Color(red: 0.965, green: 0.969, blue: 0.980)
                if let portrait = self.displayedPortrait {
                    Image(nsImage: portrait)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 72, height: 72, alignment: .center)
                } else {
                    Text(String(shownName.prefix(1)))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(accent.opacity(0.32), lineWidth: 0.85)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(shownName)
                    .font(.system(size: 15, weight: .semibold))
                Text(self.selectedModelLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
    
    private var avatarPickerRow: some View {
        HStack(spacing: 10) {
            Text(AppLanguage.text("头像", en: "Avatar"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            
            Button(AppLanguage.text("上传头像", en: "Upload Avatar")) {
                self.pickCustomAvatar()
            }
            .controlSize(.small)
            
            Button {
                self.isShowingAvatarLibraryPicker.toggle()
            } label: {
                Label(AppLanguage.text("头像库", en: "Library"), systemImage: "photo.stack")
            }
            .controlSize(.small)
            .popover(isPresented: self.$isShowingAvatarLibraryPicker, arrowEdge: .bottom) {
                AvatarLibraryPickerPopover { asset in
                    let url = UserMediaLibraryStore.shared.fileURL(for: asset)
                    if let data = try? Data(contentsOf: url), !data.isEmpty {
                        self.pendingAvatarData = data
                        self.pendingAvatarSourceURL = nil
                        self.pendingResetAvatar = false
                        self.savedBannerVisible = false
                    }
                    self.isShowingAvatarLibraryPicker = false
                }
            }
            
            if self.hasEffectiveCustomAvatar {
                Button(AppLanguage.text("恢复默认", en: "Reset")) {
                    self.pendingAvatarData = nil
                    self.pendingAvatarSourceURL = nil
                    self.pendingResetAvatar = true
                    self.savedBannerVisible = false
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }
    
    private var nicknameRow: some View {
        HStack(spacing: 10) {
            Text(AppLanguage.text("昵称", en: "Nickname"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            
            TextField(
                self.botID == .butler ? "曜" : self.botID.displayName,
                text: self.$nicknameDraft
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12.5))
            .onChange(of: self.nicknameDraft) { _, _ in
                self.savedBannerVisible = false
            }
        }
    }
    
    private var modelPickerRow: some View {
        let activeGatewayTitle = self.activeGatewayGroup?.title ?? "API 网关"
        let defaultModel = self.activeGatewayGroup?.profile.displayModel ?? AIProvider.openCodeGo.defaultModel
        return HStack(spacing: 10) {
            Text(AppLanguage.text("后端模型", en: "Model"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            
            Menu {
                let isFollowingDefault = (self.config.endpointID == nil && self.config.modelOverride.isEmpty)
                Button {
                    self.config.endpointID = nil
                    self.config.modelOverride = ""
                    self.savedBannerVisible = false
                } label: {
                    Text(isFollowingDefault
                         ? "✓  跟随 \(activeGatewayTitle) 默认 (\(defaultModel))"
                         : "跟随 \(activeGatewayTitle) 默认 (\(defaultModel))")
                }
                
                ForEach(self.gatewayGroups) { group in
                    if !group.models.isEmpty {
                        Divider()
                        Section(group.title) {
                            ForEach(group.models, id: \.self) { modelID in
                                let picked = (self.config.modelOverride == modelID
                                              && (self.config.endpointID == group.profile.id || (self.config.endpointID == nil && group.isActive)))
                                Button(picked ? "✓  \(modelID)" : modelID) {
                                    self.config.endpointID = group.profile.id
                                    self.config.modelOverride = modelID
                                    self.savedBannerVisible = false
                                }
                            }
                        }
                    }
                }
                
                Divider()
                Button(self.isRefreshingModels ? "正在刷新模型…" : "刷新模型列表") {
                    Task { await self.refreshModels() }
                }
                .disabled(self.isRefreshingModels)
            } label: {
                HStack(spacing: 6) {
                    Text(self.selectedModelLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(self.cardBorder, lineWidth: 0.75)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            
            Button {
                Task { await self.refreshModels() }
            } label: {
                HStack(spacing: 4) {
                    if self.isRefreshingModels {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    }
                    Text(self.isRefreshingModels
                         ? AppLanguage.text("刷新中", en: "Fetching")
                         : AppLanguage.text("刷新模型", en: "Refresh"))
                        .font(.system(size: 11.5))
                }
            }
            .controlSize(.small)
            .disabled(self.isRefreshingModels)
        }
    }
    
    private var personaEditorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.text("性格与情绪", en: "Personality"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            
            ZStack(alignment: .topLeading) {
                TextEditor(text: self.$personaDraft)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .onChange(of: self.personaDraft) { _, _ in
                        self.savedBannerVisible = false
                    }
                if self.personaDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(AppLanguage.text("输入性格、语气与情绪", en: "Describe personality and mood"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 88)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.8))
        }
    }
    
    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(AppLanguage.text("恢复默认", en: "Reset"), role: .destructive) {
                self.botStore.resetBotToDefaults(self.botID)
                if self.botID == .butler {
                    self.butlerManager.name = "曜"
                    self.butlerManager.nickname = "总管"
                    self.butlerManager.syncArtworkVariant(nil)
                }
                self.loadInitialState()
            }
            .controlSize(.small)
            
            Spacer()
            
            if self.savedBannerVisible {
                Text(AppLanguage.text("已保存", en: "Saved"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            
            Button(AppLanguage.text("保存", en: "Save")) {
                self.commitChanges()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    
    private func pickCustomAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let data = try? Data(contentsOf: url)
            else { return }
            Task { @MainActor in
                self.pendingAvatarData = data
                self.pendingAvatarSourceURL = url
                self.pendingResetAvatar = false
                self.savedBannerVisible = false
            }
        }
    }
    
    private func loadInitialState() {
        let loaded = self.botStore.config(for: self.botID)
        self.config = loaded
        if self.botID == .butler {
            self.nicknameDraft = self.butlerManager.name
        } else {
            let preferred = loaded.customName.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackNick = loaded.customNickname.trimmingCharacters(in: .whitespacesAndNewlines)
            self.nicknameDraft = preferred.isEmpty ? fallbackNick : preferred
        }
        self.personaDraft = loaded.customPersona
        self.pendingAvatarData = nil
        self.pendingAvatarSourceURL = nil
        self.pendingResetAvatar = false
        self.savedBannerVisible = false
        self.gatewayGroups = self.botStore.selectableGatewayGroups()
    }
    
    private func commitChanges() {
        if self.pendingResetAvatar {
            self.botStore.setCustomAvatarData(nil, for: self.botID)
        } else if let avatarData = self.pendingAvatarData {
            if let sourceURL = self.pendingAvatarSourceURL {
                _ = UserMediaLibraryStore.shared.importURLs([sourceURL], preferredKind: .avatar)
            }
            self.botStore.setCustomAvatarData(avatarData, for: self.botID)
        }
        self.pendingAvatarData = nil
        self.pendingAvatarSourceURL = nil
        self.pendingResetAvatar = false
        
        let cleanNick = self.nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.botID == .butler {
            self.butlerManager.name = cleanNick.isEmpty ? "曜" : cleanNick
            self.butlerManager.nickname = cleanNick.isEmpty ? "总管" : cleanNick
        } else {
            self.config.customName = cleanNick
            self.config.customNickname = cleanNick
        }
        self.config.customPersona = self.personaDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        self.botStore.updateConfig(self.config, for: self.botID)
        self.onEndpointsUpdated()
        
        withAnimation(.easeOut(duration: 0.15)) {
            self.savedBannerVisible = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.savedBannerVisible = false
                }
            }
        }
    }
    
    private func refreshModels() async {
        self.isRefreshingModels = true
        defer { self.isRefreshingModels = false }
        _ = try? await self.botStore.refreshGatewayModels(for: self.targetGatewayProfile)
        self.gatewayGroups = self.botStore.selectableGatewayGroups()
        self.onEndpointsUpdated()
    }
}
