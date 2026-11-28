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


// MARK: - Master-Detail Bots Settings

struct AIBotsSettingsView: View {
    
    /// Exact deterministic content width (`780 - 204 sidebar - 1 divider - 48 padding = 527pt`).
    private static let fixedStageWidth: CGFloat = 527
    
    var settingsState: SidebarSettingsState? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var botStore = AIBotStore.shared
    @State private var selectedTarget: SelectedBotTarget = .builtIn(.butler)
    @State private var isShowingCreateBot = false
    @State private var editingCustomBot: CustomBotProfile? = nil
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BotsGlobalProactiveCard()
            
            HStack(alignment: .top, spacing: 12) {
                BotMasterListSidebar(
                    selectedTarget: self.$selectedTarget,
                    builtInBots: AIBotID.allCases,
                    customBots: self.botStore.customBots,
                    botStore: self.botStore,
                    cardSurface: self.cardSurface,
                    cardBorder: self.cardBorder,
                    onCreateBot: { self.isShowingCreateBot = true }
                )
                
                self.detailInspector
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: Self.fixedStageWidth, alignment: .topLeading)
        .onAppear {
            self.botStore.reloadFromDatabase()
            self.consumePendingBotSelection()
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
        .onChange(of: self.botStore.customBotsRevision) { _, _ in
            if case .custom(let cid) = self.selectedTarget,
               !self.botStore.customBots.contains(where: { $0.id == cid })
            {
                self.selectedTarget = .builtIn(.butler)
            }
        }
        .sheet(isPresented: self.$isShowingCreateBot) {
            CustomBotCreationSheet { created in
                self.selectedTarget = .custom(created.id)
                self.botStore.reloadFromDatabase()
            }
        }
        .sheet(item: self.$editingCustomBot) { customBot in
            CustomBotCreationSheet(editingBot: customBot) { updated in
                self.selectedTarget = .custom(updated.id)
                self.botStore.reloadFromDatabase()
            }
        }
    }
    
    
    @ViewBuilder
    private var detailInspector: some View {
        switch self.selectedTarget {
            case .builtIn(let botID):
                AIBotInlineInspectorView(
                    botID: botID,
                    cardSurface: self.cardSurface,
                    cardBorder: self.cardBorder,
                    onEndpointsUpdated: {
                        self.botStore.reloadFromDatabase()
                    }
                )
                
            case .custom(let customID):
                if let customBot = self.botStore.customBots.first(where: { $0.id == customID }) {
                    CustomBotInspectorView(
                        customBot: customBot,
                        cardSurface: self.cardSurface,
                        cardBorder: self.cardBorder,
                        onEdit: { self.editingCustomBot = customBot }
                    )
                } else {
                    AIBotInlineInspectorView(
                        botID: .butler,
                        cardSurface: self.cardSurface,
                        cardBorder: self.cardBorder,
                        onEndpointsUpdated: {
                            self.botStore.reloadFromDatabase()
                        }
                    )
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
            self.selectedTarget = .custom(customID)
            return
        }
        guard let pending = self.settingsState?.pendingBotID else { return }
        self.selectedTarget = .builtIn(pending)
        self.settingsState?.pendingBotID = nil
    }
    
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
}


// MARK: - Inline Built-In Bot Inspector

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
    @State private var proactiveLevel: BotProactiveLevel = .off
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
        return self.botStore.resolvedPortraitImage(for: self.botID, pointWidth: 44, pointHeight: 44)
    }
    
    private var selectedModelLabel: String {
        let defaultModel = self.activeGatewayGroup?.profile.displayModel ?? AIProvider.openCodeGo.defaultModel
        let trimmedOverride = self.config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOverride.isEmpty {
            return AppLanguage.text("默认 (\(defaultModel))", en: "Default (\(defaultModel))")
        }
        return trimmedOverride
    }
    
    private var hasEffectiveCustomAvatar: Bool {
        if self.pendingAvatarData != nil { return true }
        if self.pendingResetAvatar { return false }
        return self.botStore.customAvatarImage(for: self.botID) != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroupCard(title: AppLanguage.text("身份", en: "Identity")) {
                VStack(alignment: .leading, spacing: 10) {
                    self.headerSummaryRow
                    Divider()
                    self.avatarPickerRow
                    self.nicknameRow
                }
                .padding(12)
            }
            
            SettingsGroupCard(title: AppLanguage.text("模型", en: "Model")) {
                self.modelPickerRow
                    .padding(12)
            }
            
            BotProactiveAndWorkspaceCard(
                botIDString: self.botID.rawValue,
                proactiveLevel: self.$proactiveLevel,
                onProactiveChanged: { nextLevel in
                    self.config.proactiveLevel = nextLevel
                    self.botStore.updateConfig(self.config, for: self.botID)
                    self.savedBannerVisible = false
                }
            )
            
            SettingsGroupCard(title: AppLanguage.text("人设", en: "Persona")) {
                VStack(alignment: .leading, spacing: 10) {
                    self.personaEditorSection
                    Divider()
                    self.actionBar
                }
                .padding(12)
            }
        }
        .task(id: self.botID) {
            self.loadInitialState()
        }
    }
    
    private var headerSummaryRow: some View {
        let accent = Color(hexString: self.resolvedCharacter?.accentHex ?? self.botID.accentHex)
        let shownName = self.displayedNickname
        return HStack(spacing: 10) {
            ZStack {
                if let portrait = self.displayedPortrait {
                    Image(nsImage: portrait)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 44, height: 44, alignment: .center)
                } else {
                    accent.opacity(0.16)
                    Text(String(shownName.prefix(1)))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(self.cardBorder, lineWidth: 0.75)
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(shownName)
                    .font(.system(size: 14, weight: .semibold))
                Text(self.botID.handle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 6)
            
            if self.botID != .butler {
                Toggle("", isOn: self.$config.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.config.isEnabled) { _, _ in
                        self.botStore.updateConfig(self.config, for: self.botID)
                    }
            }
            
            Button(AppLanguage.text("打开对话", en: "Open Chat")) {
                _ = self.butlerManager.openDirectChat(botID: self.botID.rawValue)
                self.butlerManager.requestOpenHub()
            }
            .controlSize(.small)
        }
    }
    
    private var avatarPickerRow: some View {
        HStack(spacing: 8) {
            Text(AppLanguage.text("头像", en: "Avatar"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            
            Button(AppLanguage.text("上传", en: "Upload")) {
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
        HStack(spacing: 8) {
            Text(AppLanguage.text("名称", en: "Name"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            
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
        return HStack(spacing: 8) {
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
                        .font(.system(size: 10, weight: .semibold))
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
                Text(self.isRefreshingModels
                     ? AppLanguage.text("刷新中", en: "Fetching")
                     : AppLanguage.text("刷新", en: "Refresh"))
                    .font(.system(size: 12))
            }
            .controlSize(.small)
            .disabled(self.isRefreshingModels)
        }
    }
    
    private var personaEditorSection: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: self.$personaDraft)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(6)
                .onChange(of: self.personaDraft) { _, _ in
                    self.savedBannerVisible = false
                }
            if self.personaDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(AppLanguage.text("性格、语气与边界", en: "Personality and tone"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 82)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.8))
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
        self.proactiveLevel = loaded.effectiveProactiveLevel(for: self.botID)
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
        self.config.proactiveLevel = self.proactiveLevel
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
