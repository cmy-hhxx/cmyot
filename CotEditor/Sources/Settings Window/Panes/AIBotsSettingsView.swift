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

// MARK: - API 网关 (服务端点 · Pi 内核桥接 · 全局人设)

struct AIModelsSettingsView: View {
    
    private static let quickProviders: [AIProvider] = AIProvider.curatedPresets
    
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
    @State private var imageLoader = AIGijinkaImageLoader.shared
    @State private var piKernel = PiKernelManager.shared
    @State private var kernelEnabled: Bool = PiKernelManager.shared.isKernelEnabled
    @State private var showPiInstallPrompt = false
    @State private var didCopyPiPrompt = false
    
    // cc-switch style quick preset connect drawer
    @State private var showPresetGallery = false
    @State private var quickConnectProvider: AIProvider? = nil
    @State private var quickConnectAPIKey: String = ""
    @State private var quickConnectModel: String = ""
    @State private var quickConnectUseAnthropic: Bool = false
    @State private var quickConnectNotice: String? = nil
    
    
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
                        Text(AppLanguage.text("返回 API 网关", en: "Back to API Gateways"))
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
            // Section 1: cc-switch 风格快速接入 (OpenCode Go 重点 + 主流预设)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(AppLanguage.text("快速接入网关", en: "Quick Switch & Presets"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                            self.showPresetGallery.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(self.showPresetGallery
                                 ? AppLanguage.text("收起主流预设", en: "Hide Presets")
                                 : AppLanguage.text("全部主流预设 (\(Self.quickProviders.count))", en: "All Presets (\(Self.quickProviders.count))"))
                                .font(.system(size: 11.5, weight: .medium))
                            Image(systemName: self.showPresetGallery ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    // Featured Flagship Row: OpenCode Go + Top Mainstream Shortcuts
                    HStack(spacing: 8) {
                        self.quickPresetChip(.openCodeGo, prominent: true)
                        self.quickPresetChip(.openAI, prominent: false)
                        self.quickPresetChip(.anthropic, prominent: false)
                        self.quickPresetChip(.deepSeek, prominent: false)
                        self.quickPresetChip(.google, prominent: false)
                        
                        Spacer(minLength: 0)
                        
                        Button {
                            self.beginAddingEndpoint()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(AppLanguage.text("自定义", en: "Custom"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    
                    if self.showPresetGallery {
                        self.rowDivider
                        
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 4)
                        LazyVGrid(columns: columns, spacing: 7) {
                            ForEach(Self.quickProviders, id: \.self) { provider in
                                self.presetGridTile(provider)
                            }
                        }
                        .padding(12)
                    }
                    
                    if let targetProvider = self.quickConnectProvider {
                        self.rowDivider
                        self.quickConnectBar(for: targetProvider)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            }
            
            // Section 2: 已配置网关 (cc-switch 一键切换)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(AppLanguage.text("已配置网关（点击一键切换）", en: "Configured Gateways"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                    
                    Spacer()
                    
                    if let notice = self.quickConnectNotice {
                        Text(notice)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    } else {
                        self.activeEnginePill
                    }
                }
                
                VStack(spacing: 0) {
                    if self.profiles.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bolt.horizontal.circle")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text(AppLanguage.text("点上方 OpenCode Go 或任意预设，粘贴 Key 即可一键启用", en: "Pick a preset above to connect in one step"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(Array(self.profiles.enumerated()), id: \.element.id) { idx, profile in
                            if idx > 0 {
                                self.rowDivider
                            }
                            self.endpointRow(profile)
                        }
                    }
                }
                .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
            }
            
            // Section 2: Pi 内核底座
            VStack(alignment: .leading, spacing: 7) {
                Text(AppLanguage.text("Pi 内核底座", en: "Pi Kernel Runtime"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(self.piKernel.isAvailable && self.kernelEnabled ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        
                        Text(self.piKernel.statusSummary)
                            .font(.system(size: 13, weight: .medium))
                        
                        Spacer()
                        
                        if !self.piKernel.isAvailable {
                            Button(self.didCopyPiPrompt ? AppLanguage.text("已复制提示词", en: "Copied") : AppLanguage.text("安装提示词", en: "Install Prompt")) {
                                self.copyPiInstallPrompt()
                                withAnimation(.easeOut(duration: 0.16)) {
                                    self.showPiInstallPrompt.toggle()
                                }
                            }
                            .controlSize(.small)
                        } else {
                            Button(self.showPiInstallPrompt ? AppLanguage.text("收起提示词", en: "Hide Prompt") : AppLanguage.text("安装提示词", en: "Install Prompt")) {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    self.showPiInstallPrompt.toggle()
                                }
                            }
                            .controlSize(.small)
                        }
                        
                        Button {
                            Task { await self.piKernel.refreshEnvironment() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderless)
                        .help(AppLanguage.text("刷新 Pi 状态", en: "Refresh Pi Status"))
                        
                        Toggle("", isOn: self.$kernelEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: self.kernelEnabled) { _, enabled in
                                self.piKernel.isKernelEnabled = enabled
                            }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    
                    if self.showPiInstallPrompt || !self.piKernel.isAvailable {
                        self.rowDivider
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ScrollView(.vertical, showsIndicators: true) {
                                Text(PiKernelManager.installPrompt)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(maxHeight: 150)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(self.cardBorder, lineWidth: 1)
                            )
                            
                            HStack {
                                Spacer()
                                Button {
                                    self.copyPiInstallPrompt()
                                } label: {
                                    Label(
                                        self.didCopyPiPrompt
                                            ? AppLanguage.text("已复制", en: "Copied")
                                            : AppLanguage.text("复制提示词", en: "Copy Prompt"),
                                        systemImage: self.didCopyPiPrompt ? "checkmark" : "doc.on.doc"
                                    )
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                    }
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
            Text(activeProfile?.displayName ?? AppLanguage.text("未配置网关", en: "Unconfigured"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(activeProfile != nil ? Color.secondary : Color.orange)
                .lineLimit(1)
        }
        .padding(.trailing, 3)
    }
    
    
    @ViewBuilder
    private func quickPresetChip(_ provider: AIProvider, prominent: Bool) -> some View {
        let isSelected = (self.quickConnectProvider == provider)
        let accent = Color(hexString: provider.accentHex)
        let hasConfigured = self.profiles.contains { $0.provider == provider }
        
        Button {
            self.selectQuickConnect(provider)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(prominent && !isSelected ? Color.white : accent)
                    .frame(width: 6, height: 6)
                
                Text(provider == .google ? "Gemini" : (provider == .anthropic ? "Claude" : provider.label))
                    .font(.system(size: 11.5, weight: (prominent || isSelected) ? .semibold : .medium))
                    .lineLimit(1)
                
                if provider.isFeatured {
                    Text(AppLanguage.text("主打", en: "GO"))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (prominent && !isSelected ? Color.white.opacity(0.22) : accent.opacity(0.16)),
                            in: Capsule()
                        )
                } else if hasConfigured {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isSelected ? Color.white : .green)
                }
            }
            .foregroundStyle(
                isSelected || prominent
                    ? Color.white
                    : Color.primary.opacity(0.86)
            )
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? accent
                            : (prominent
                               ? accent.opacity(self.colorScheme == .dark ? 0.88 : 0.92)
                               : Color.primary.opacity(self.colorScheme == .dark ? 0.07 : 0.05))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent : (prominent ? accent : self.cardBorder),
                        lineWidth: isSelected ? 1.2 : 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    @ViewBuilder
    private func presetGridTile(_ provider: AIProvider) -> some View {
        let isSelected = (self.quickConnectProvider == provider)
        let accent = Color(hexString: provider.accentHex)
        let isConfigured = self.profiles.contains { $0.provider == provider }
        
        Button {
            self.selectQuickConnect(provider)
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 18)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.label)
                        .font(.system(size: 11.5, weight: isSelected || provider.isFeatured ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(provider.badgeLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(provider.isFeatured ? accent : .secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 2)
                
                if isConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? accent.opacity(self.colorScheme == .dark ? 0.20 : 0.12)
                            : Color.primary.opacity(self.colorScheme == .dark ? 0.045 : 0.03)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.75) : (provider.isFeatured ? accent.opacity(0.35) : self.cardBorder),
                        lineWidth: isSelected ? 1.1 : 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    @ViewBuilder
    private func quickConnectBar(for provider: AIProvider) -> some View {
        let accent = Color(hexString: provider.accentHex)
        let requiresKey = provider.endpoint.requiresAPIKey
        let canConnect = !requiresKey || !self.quickConnectAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                
                Text(provider.label)
                    .font(.system(size: 13, weight: .semibold))
                
                Text(provider == .openCodeGo && self.quickConnectUseAnthropic
                     ? "https://opencode.ai/zen/go"
                     : provider.defaultBaseURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer(minLength: 4)
                
                if provider == .openCodeGo {
                    Picker("", selection: self.$quickConnectUseAnthropic) {
                        Text("OpenAI 协议").tag(false)
                        Text("Anthropic 协议").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 158)
                }
                
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        self.quickConnectProvider = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            
            HStack(spacing: 8) {
                if requiresKey {
                    SecureField(provider.apiKeyPlaceholder, text: self.$quickConnectAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onSubmit {
                            if canConnect { self.commitQuickConnect(provider) }
                        }
                } else {
                    Text(AppLanguage.text("本地模型免 API Key，直接启用", en: "No API Key needed for local runner"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Menu {
                    ForEach(provider.recommendedModels, id: \.self) { m in
                        Button(m) {
                            self.quickConnectModel = m
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(self.quickConnectModel.isEmpty ? provider.defaultModel : self.quickConnectModel)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .frame(maxWidth: 146)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                
                Button {
                    self.commitQuickConnect(provider)
                } label: {
                    Text(AppLanguage.text("接入并启用", en: "Connect"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(
                            canConnect ? accent : Color.secondary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canConnect)
                .pointerStyle(canConnect ? .link : .default)
                
                Button {
                    let built = provider.makeProfile(
                        modelOverride: self.quickConnectModel,
                        useAnthropicProtocol: self.quickConnectUseAnthropic
                    )
                    let key = self.quickConnectAPIKey
                    self.quickConnectProvider = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.editingEndpointTarget = EndpointEditTarget(profile: built, apiKey: key, isNew: true)
                    }
                } label: {
                    Text(AppLanguage.text("完整表单", en: "Advanced"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(accent.opacity(self.colorScheme == .dark ? 0.08 : 0.045))
    }
    
    
    private func selectQuickConnect(_ provider: AIProvider) {
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
            if self.quickConnectProvider == provider {
                self.quickConnectProvider = nil
            } else {
                self.quickConnectProvider = provider
                self.quickConnectAPIKey = ""
                self.quickConnectModel = provider.defaultModel
                self.quickConnectUseAnthropic = false
            }
        }
    }
    
    
    private func commitQuickConnect(_ provider: AIProvider) {
        let trimmedKey = self.quickConnectAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.endpoint.requiresAPIKey && trimmedKey.isEmpty { return }
        
        let profile = provider.makeProfile(
            modelOverride: self.quickConnectModel,
            useAnthropicProtocol: self.quickConnectUseAnthropic
        )
        AIEndpointStore.save(profile, apiKey: trimmedKey)
        self.activeID = profile.id
        AIEndpointStore.activeID = profile.id
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        _ = try? self.piKernel.syncWorkspace()
        
        withAnimation(.easeOut(duration: 0.18)) {
            self.quickConnectProvider = nil
            self.quickConnectAPIKey = ""
            self.quickConnectNotice = "已接入并启用 \(profile.displayName)"
        }
        self.reload()
        Task {
            await self.testEndpoint(profile)
            try? await Task.sleep(for: .seconds(3))
            if self.quickConnectNotice?.contains(profile.displayName) == true {
                self.quickConnectNotice = nil
            }
        }
    }
    
    
    @ViewBuilder
    private func endpointRow(_ profile: AIEndpointProfile) -> some View {
        let isActive = (profile.id == self.activeID)
        let probe = self.endpointStatus[profile.id]
        let fetched = self.fetchedModels[profile.id] ?? []
        let isFetching = self.fetchingModelsIDs.contains(profile.id)
        let isConfirmingDelete = (self.confirmDeleteID == profile.id)
        let provider = profile.provider
        let providerAccent = Color(hexString: provider.accentHex)
        let gijinka = AIGijinkaCharacter.resolve(
            modelName: profile.displayModel,
            endpointName: profile.displayName,
            baseURL: profile.baseURL
        )
        let portrait = gijinka.flatMap { self.imageLoader.image(for: $0) }
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    self.activateEndpoint(profile)
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isActive ? Color.green : Color.clear)
                            .frame(width: 3, height: 22)
                        
                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14.5))
                            .foregroundStyle(isActive ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                            .frame(width: 18)
                        
                        if let gijinka {
                            ZStack {
                                if let portrait {
                                    AIGijinkaCompleteArtworkView(
                                        image: portrait,
                                        accent: Color(hexString: gijinka.accentHex),
                                        width: 26,
                                        height: 26,
                                        isDark: self.colorScheme == .dark,
                                        isEnabled: true
                                    )
                                } else {
                                    Circle()
                                        .fill(providerAccent.opacity(0.15))
                                    Text(String(gijinka.brand.prefix(1)))
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(providerAccent)
                                }
                            }
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(isActive ? Color.green.opacity(0.55) : self.cardBorder, lineWidth: 0.9))
                            .help(gijinka.name)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(profile.displayName)
                                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                                    .lineLimit(1)
                                
                                if isActive {
                                    Text(AppLanguage.text("生效中", en: "Active"))
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 5.5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.green.opacity(0.14), in: Capsule())
                                }
                            }
                            
                            Text(profile.baseURL.isEmpty ? profile.endpoint.defaultBaseURL : profile.baseURL)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer(minLength: 4)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
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
                    let saved = Array(NSOrderedSet(array: profile.availableModelIDs + profile.provider.recommendedModels).compactMap { $0 as? String })
                    if !saved.isEmpty {
                        Section(AppLanguage.text("推荐与已保存模型", en: "Models")) {
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
    
    
    private func copyPiInstallPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PiKernelManager.installPrompt, forType: .string)
        self.didCopyPiPrompt = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            self.didCopyPiPrompt = false
        }
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
        self.kernelEnabled = self.piKernel.isKernelEnabled
        _ = try? self.piKernel.syncWorkspace()
    }
    
    
    private func activateEndpoint(_ profile: AIEndpointProfile) {
        self.activeID = profile.id
        AIEndpointStore.activeID = profile.id
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        _ = try? self.piKernel.syncWorkspace()
    }
    
    
    private func beginAddingEndpoint(preset provider: AIProvider? = nil) {
        let profile: AIEndpointProfile
        if let provider, provider != .custom {
            profile = provider.makeProfile()
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


// MARK: - Bots (Pi 内核智能体编队 · 固定宽度零跳动 · 卡片 / 列表 / 叠放视图)

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


struct AIBotsSettingsView: View {
    
    /// Exact deterministic content width (`780 - 204 sidebar - 1 divider - 48 padding = 527pt`)
    /// so entering the Agents pane matches all other panes flush edge-to-edge with zero geometry jump.
    private static let fixedStageWidth: CGFloat = 527
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var botStore = AIBotStore.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    @State private var piKernel = PiKernelManager.shared
    @State private var layoutMode: BotCollectionLayoutMode = .card
    @State private var inspectingBot: AIBotID?
    @State private var allEndpoints: [AIEndpointProfile] = []
    @State private var activeEndpoint: AIEndpointProfile?
    @State private var globalPersona: String = ""
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
                    .transition(.opacity)
            } else {
                self.morphingCollectionView(featureCounts: featureCounts)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.fixedStageWidth, alignment: .topLeading)
        .onAppear {
            self.reload()
            self.prefetchResolvedCharacters()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
            self.prefetchResolvedCharacters()
        }
    }
    
    
    private func resolvedEndpoint(for config: AIBotConfig) -> AIEndpointProfile? {
        if let endpointID = config.endpointID,
           let matched = self.allEndpoints.first(where: { $0.id == endpointID })
        {
            return matched
        }
        return self.activeEndpoint
    }
    
    
    /// Resolves the Bot visual persona strictly from the model & gateway selected for `botID`.
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
        )
    }
    
    
    private func prefetchResolvedCharacters() {
        let artworks = AIBotID.allCases.compactMap { botID -> AIGijinkaArtwork? in
            let config = self.botStore.config(for: botID)
            guard let character = self.resolvedCharacter(for: botID, config: config) else { return nil }
            return character.artwork(for: botID, variantOverride: config.artworkVariantIndex)
        }
        self.imageLoader.prefetch(artworks)
    }
    
    
    private static func swiftUIAlignment(for anchor: AIGijinkaCropAnchor) -> Alignment {
        switch anchor {
            case .top: .top
            case .center: .center
            case .leading: .topLeading
        }
    }
    
    
    // MARK: Morphing Gallery / List / Pack Stage
    
    @ViewBuilder
    private func morphingCollectionView(featureCounts: [String: Int]) -> some View {
        let bots = AIBotID.allCases
        let cols = 3
        let rowsCount = Int(ceil(Double(bots.count) / Double(cols)))
        let cardGap: CGFloat = 12
        let cardWidth = floor((Self.fixedStageWidth - cardGap * CGFloat(cols - 1)) / CGFloat(cols)) // 167pt
        let portraitHeight: CGFloat = 222 // True 3:4 portrait card proportion (167 x 222) tailored for vertical HD portraits
        let cardRowStride: CGFloat = portraitHeight + 54
        let stageHeight: CGFloat = switch self.layoutMode {
            case .list: CGFloat(bots.count) * 64.0
            case .card: CGFloat(rowsCount) * cardRowStride
            case .pack: 308.0
        }
        let enabledCount = bots.filter { self.botStore.config(for: $0).isEnabled }.count
        let hoveredIndex = self.hoveredBotID.flatMap { id in bots.firstIndex(of: id) }
        let focusedPackBot = self.hoveredBotID ?? bots.first
        
        VStack(alignment: .leading, spacing: 14) {
            // Segmented Layout Switcher with shared sliding capsule
            HStack(spacing: 4) {
                ForEach(BotCollectionLayoutMode.allCases) { mode in
                    let isSelected = (self.layoutMode == mode)
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.36)) {
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
                                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08))
                                    .matchedGeometryEffect(id: "botLayoutPill", in: self.modePillNamespace)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Spacer()
                
                Text("\(enabledCount)/\(bots.count) \(AppLanguage.text("已启用", en: "Active"))")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            
            Rectangle()
                .fill(self.cardBorder)
                .frame(height: 1)
                .opacity(self.layoutMode == .card ? 0.0 : 1.0)
                .animation(.easeOut(duration: 0.18), value: self.layoutMode)
            
            // Unified Identity-Preserving Morph Stage
            ZStack(alignment: .topLeading) {
                if self.layoutMode == .pack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            self.colorScheme == .dark
                                ? Color.white.opacity(0.03)
                                : Color.black.opacity(0.022)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(self.cardBorder, lineWidth: 0.75)
                        )
                        .frame(width: Self.fixedStageWidth, height: 224)
                        .allowsHitTesting(false)
                }
                
                ForEach(Array(bots.enumerated()), id: \.element) { index, botID in
                    let cfg = self.botStore.config(for: botID)
                    let calls = featureCounts[botID.analyticsFeatureKey] ?? 0
                    self.morphingBotNode(
                        botID: botID,
                        index: index,
                        total: bots.count,
                        hoveredIndex: hoveredIndex,
                        config: cfg,
                        recentCalls: calls,
                        cardWidth: cardWidth,
                        portraitHeight: portraitHeight,
                        cardGap: cardGap,
                        cardRowStride: cardRowStride
                    )
                }
                
                if self.layoutMode == .pack, let focusedPackBot {
                    let focusedCfg = self.botStore.config(for: focusedPackBot)
                    let focusedEndpoint = self.resolvedEndpoint(for: focusedCfg)
                    let focusedChar = self.resolvedCharacter(for: focusedPackBot, config: focusedCfg)
                    let focusedAccent = Color(hexString: focusedChar?.accentHex ?? focusedPackBot.accentHex)
                    let focusedModel = focusedCfg.modelOverride.isEmpty
                        ? (focusedEndpoint?.displayModel ?? AppLanguage.text("跟随全局默认", en: "Default Model"))
                        : focusedCfg.modelOverride
                    
                    HStack(spacing: 12) {
                        Circle()
                            .fill(focusedCfg.isEnabled ? focusedAccent : Color.secondary.opacity(0.35))
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(focusedPackBot.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                if let focusedChar {
                                    Text(focusedChar.name)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(focusedAccent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(focusedAccent.opacity(0.14), in: Capsule())
                                }
                            }
                            Text(focusedModel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                self.inspectingBot = focusedPackBot
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(AppLanguage.text("进入配置", en: "Configure"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.primary.opacity(self.colorScheme == .dark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 14)
                    .frame(width: Self.fixedStageWidth, height: 62)
                    .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
                    .offset(y: 238)
                    .transition(.opacity)
                }
            }
            .frame(width: Self.fixedStageWidth, height: stageHeight, alignment: .topLeading)
            
            HStack(spacing: 6) {
                Circle()
                    .fill(self.piKernel.isAvailable && self.piKernel.isKernelEnabled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(self.piKernel.statusSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(AppLanguage.text("角色形象随所选网关与模型自动切换", en: "Personas follow selected gateway & model"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        }
    }
    
    
    private func morphingBotNode(
        botID: AIBotID,
        index: Int,
        total: Int,
        hoveredIndex: Int?,
        config: AIBotConfig,
        recentCalls: Int,
        cardWidth: CGFloat,
        portraitHeight: CGFloat,
        cardGap: CGFloat,
        cardRowStride: CGFloat
    ) -> some View {
        let endpoint = self.resolvedEndpoint(for: config)
        let character = self.resolvedCharacter(for: botID, config: config)
        let artwork = character?.artwork(for: botID, variantOverride: config.artworkVariantIndex)
        let accent = Color(hexString: character?.accentHex ?? botID.accentHex)
        let portrait = artwork.flatMap { self.imageLoader.image(for: $0) }
        let effectiveModelLabel = config.modelOverride.isEmpty
            ? (endpoint?.displayModel ?? AppLanguage.text("未选择模型", en: "No Model"))
            : config.modelOverride
        let isHovered = (self.hoveredBotID == botID)
        
        let itemWidth: CGFloat
        let itemHeight: CGFloat
        let artWidth: CGFloat
        let artHeight: CGFloat
        let artCorner: CGFloat
        let posX: CGFloat
        let posY: CGFloat
        let rotation: Double
        let packScale: CGFloat
        
        switch self.layoutMode {
            case .list:
                artWidth = 48
                artHeight = 48
                artCorner = 10
                itemWidth = Self.fixedStageWidth
                itemHeight = artHeight
                posX = 0
                posY = CGFloat(index) * 64.0
                rotation = 0
                packScale = 1.0
            case .card:
                artWidth = cardWidth
                artHeight = portraitHeight
                artCorner = 12
                itemWidth = cardWidth
                itemHeight = portraitHeight + 44
                let col = index % 3
                let row = index / 3
                posX = CGFloat(col) * (cardWidth + cardGap)
                posY = CGFloat(row) * cardRowStride
                rotation = 0
                packScale = 1.0
            case .pack:
                artWidth = 112
                artHeight = 148
                artCorner = 13
                itemWidth = artWidth
                itemHeight = artHeight
                // Fit fanned deck cleanly inside fixedStageWidth (525pt) with zero edge clipping
                let maxDeckSpan = Self.fixedStageWidth - artWidth - 56
                let spread = total > 1 ? min(44.0, maxDeckSpan / CGFloat(total - 1)) : 0
                let mid = Double(total - 1) * 0.5
                let offsetIndex = Double(index) - mid
                var fanShift: CGFloat = 0
                if let hIdx = hoveredIndex, hIdx != index {
                    fanShift = index < hIdx ? -18.0 : 18.0
                }
                posX = (Self.fixedStageWidth - artWidth) * 0.5 + CGFloat(offsetIndex) * spread + fanShift
                // Generous vertical headroom (baseY = 38) so rotated corners never clip top or bottom
                posY = 38.0 + abs(CGFloat(offsetIndex)) * 3.2 - (isHovered ? 12.0 : 0.0)
                rotation = isHovered ? 0.0 : offsetIndex * 3.2
                packScale = isHovered ? 1.05 : 1.0
        }
        
        return ZStack(alignment: .topLeading) {
            // Persistent Bot Portrait Frame (full-bleed 3:4 static cover)
            ZStack {
                RoundedRectangle(cornerRadius: artCorner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(self.colorScheme == .dark ? 0.16 : 0.10),
                                self.colorScheme == .dark
                                    ? Color(red: 0.12, green: 0.12, blue: 0.15)
                                    : Color(red: 0.96, green: 0.96, blue: 0.98),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                if let portrait {
                    AIGijinkaCompleteArtworkView(
                        image: portrait,
                        accent: accent,
                        width: artWidth,
                        height: artHeight,
                        isDark: self.colorScheme == .dark,
                        isEnabled: config.isEnabled
                    )
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: botID.symbolName)
                            .font(.system(size: min(artWidth * 0.34, 24), weight: .medium))
                            .foregroundStyle(accent)
                        if self.layoutMode != .list {
                            Text(character?.name ?? effectiveModelLabel)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                        }
                    }
                }
                
                if self.layoutMode == .pack {
                    // Bottom translucent name bar so every stacked card is immediately identifiable
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(config.isEnabled ? accent : Color.white.opacity(0.4))
                                .frame(width: 5, height: 5)
                            Text(botID.displayName)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.0), Color.black.opacity(0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .allowsHitTesting(false)
                } else if self.layoutMode == .card, portrait != nil {
                    // Subtle lower vignette for magazine-grade card finish
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.32)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 34)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: artWidth, height: artHeight)
            .clipShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: artCorner, style: .continuous)
                    .strokeBorder(
                        isHovered ? accent.opacity(0.85) : (self.layoutMode == .pack ? Color.white.opacity(self.colorScheme == .dark ? 0.16 : 0.72) : self.cardBorder),
                        lineWidth: isHovered ? 1.5 : 0.9
                    )
            )
            .shadow(
                color: Color.black.opacity(self.layoutMode == .pack ? (isHovered ? 0.28 : 0.16) : 0.05),
                radius: self.layoutMode == .pack ? (isHovered ? 14 : 7) : 3,
                y: self.layoutMode == .pack ? (isHovered ? 8 : 3) : 1
            )
            .scaleEffect(packScale)
            .rotationEffect(.degrees(rotation))
            .contentShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .onTapGesture {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                    self.inspectingBot = botID
                }
            }
            
            // List view metadata right of portrait thumbnail
            if self.layoutMode == .list {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(botID.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(config.isEnabled ? .primary : .secondary)
                            if let character {
                                Text(character.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(accent.opacity(self.colorScheme == .dark ? 0.16 : 0.10), in: Capsule())
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text(effectiveModelLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
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
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
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
                .padding(.leading, artWidth + 12)
                .frame(width: itemWidth, height: artHeight, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                        self.inspectingBot = botID
                    }
                }
            }
            
            // Card view caption under standing portrait (bot role primary + resolved model brand subtitle)
            if self.layoutMode == .card {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(botID.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(config.isEnabled ? .primary : .secondary)
                            .lineLimit(1)
                        
                        Spacer(minLength: 2)
                        
                        Circle()
                            .fill(config.isEnabled ? accent : Color.primary.opacity(0.18))
                            .frame(width: 6.5, height: 6.5)
                    }
                    
                    Text(character?.name ?? effectiveModelLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: cardWidth, alignment: .leading)
                .offset(y: portraitHeight + 7)
                .onTapGesture {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                        self.inspectingBot = botID
                    }
                }
            }
        }
        .frame(width: itemWidth, height: itemHeight, alignment: .topLeading)
        .offset(x: posX, y: posY)
        .zIndex(Double(index) + (isHovered && self.layoutMode == .pack ? 50 : 0))
        .onHover { hovering in
            if hovering {
                if self.hoveredBotID != botID {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        self.hoveredBotID = botID
                    }
                }
            } else if self.hoveredBotID == botID && self.layoutMode != .pack {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                    self.hoveredBotID = nil
                }
            }
        }
        .pointerStyle(.link)
        .help(character.map { "\(botID.displayName) · \($0.name)" } ?? "\(botID.displayName) · \(effectiveModelLabel)")
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
                    self.reload()
                    self.prefetchResolvedCharacters()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text(AppLanguage.text("返回 Bots", en: "Back to Bots"))
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
                allEndpoints: self.allEndpoints,
                activeEndpoint: self.activeEndpoint,
                globalPersona: self.globalPersona,
                cardSurface: self.cardSurface,
                cardBorder: self.cardBorder,
                onEndpointsUpdated: {
                    self.reload()
                    self.prefetchResolvedCharacters()
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
    
    
    private func reload() {
        let profiles = AIEndpointStore.profiles
        self.allEndpoints = profiles
        let activeID = AIEndpointStore.activeID ?? profiles.first?.id
        self.activeEndpoint = profiles.first(where: { $0.id == activeID })
        self.globalPersona = CotLocalDatabase.shared.aiPersona
        self.botStore.reloadFromDatabase()
    }
}


// MARK: - Inline Bot Inspector

private struct AIBotInlineInspectorView: View {
    
    let botID: AIBotID
    let allEndpoints: [AIEndpointProfile]
    let activeEndpoint: AIEndpointProfile?
    let globalPersona: String
    let cardSurface: Color
    let cardBorder: Color
    var onEndpointsUpdated: () -> Void = {}
    
    @State private var botStore = AIBotStore.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    @State private var config: AIBotConfig = AIBotConfig()
    @State private var promptText: String = ""
    
    @State private var inlineCompletionEnabled: Bool = true
    @State private var nextTokenStrategy: AINextTokenStrategy = .smart
    @State private var nextTokenDebounceMs: Int = 420
    @State private var nextTokenDailyCap: Int = 300
    
    @State private var fetchedModelsByEndpoint: [UUID: [String]] = [:]
    @State private var fetchingEndpointIDs: Set<UUID> = []
    
    @State private var sampleInput: String = ""
    @State private var sampleOutput: String = ""
    @State private var testError: String?
    @State private var isTesting = false
    
    
    private var effectiveEndpoint: AIEndpointProfile? {
        if let endpointID = self.config.endpointID,
           let matched = self.allEndpoints.first(where: { $0.id == endpointID })
        {
            return matched
        }
        return self.activeEndpoint
    }
    
    
    private var resolvedCharacter: AIGijinkaCharacter? {
        let endpoint = self.effectiveEndpoint
        let overrideModel = self.config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
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
        )
    }
    
    
    private func selectableModels(for profile: AIEndpointProfile) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        let fetched = self.fetchedModelsByEndpoint[profile.id] ?? []
        let providerDefault = profile.provider == .custom ? [] : [profile.provider.defaultModel]
        let candidates = profile.availableModelIDs + fetched + providerDefault
        for raw in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
    
    
    private func cropAlignment(for anchor: AIGijinkaCropAnchor) -> Alignment {
        switch anchor {
            case .top: .top
            case .center: .center
            case .leading: .topLeading
        }
    }
    
    
    var body: some View {
        let endpoint = self.effectiveEndpoint
        let character = self.resolvedCharacter
        let artwork = character?.artwork(for: self.botID, variantOverride: self.config.artworkVariantIndex)
        let accent = Color(hexString: character?.accentHex ?? self.botID.accentHex)
        let portrait = artwork.flatMap { self.imageLoader.image(for: $0) }
        let modelLabel = self.config.modelOverride.isEmpty
            ? (endpoint?.displayModel ?? AppLanguage.text("未选择模型", en: "No Model"))
            : self.config.modelOverride
        let endpointTag: String = if let selectedID = self.config.endpointID,
                                     let ep = self.allEndpoints.first(where: { $0.id == selectedID })
        {
            ep.displayName
        } else {
            AppLanguage.text("默认网关", en: "Default")
        }
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.14))
                    if let portrait {
                        AIGijinkaCompleteArtworkView(
                            image: portrait,
                            accent: accent,
                            width: 76,
                            height: 102,
                            isDark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
                            isEnabled: self.config.isEnabled
                        )
                    } else {
                        Image(systemName: self.botID.symbolName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 76, height: 102)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(accent.opacity(0.35), lineWidth: 0.75)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(self.botID.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(character.map { "\($0.name) · \(modelLabel)" } ?? modelLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    if let character, character.artworks.count > 1 {
                        Menu {
                            Button {
                                self.config.artworkVariantIndex = nil
                                self.saveBotConfig()
                            } label: {
                                if self.config.artworkVariantIndex == nil {
                                    Label(AppLanguage.text("自动分配形象", en: "Auto Variant"), systemImage: "checkmark")
                                } else {
                                    Text(AppLanguage.text("自动分配形象", en: "Auto Variant"))
                                }
                            }
                            Divider()
                            ForEach(Array(character.artworks.enumerated()), id: \.element.id) { idx, item in
                                Button {
                                    self.config.artworkVariantIndex = idx
                                    self.saveBotConfig()
                                } label: {
                                    if artwork?.id == item.id && self.config.artworkVariantIndex != nil {
                                        Label(item.title, systemImage: "checkmark")
                                    } else {
                                        Text(item.title)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.stack")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text(artwork?.title ?? AppLanguage.text("切换立绘", en: "Switch Art"))
                                    .font(.system(size: 10.5, weight: .medium))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .foregroundStyle(accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.11), in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
                
                Spacer()
                
                if PiKernelManager.shared.isAvailable {
                    Button {
                        _ = PiKernelManager.shared.launchBotInFrontmostTerminal(self.botID)
                    } label: {
                        Label(AppLanguage.text("在终端唤起 Agent", en: "Open in Terminal"), systemImage: "terminal")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .controlSize(.small)
                    .help(AppLanguage.text("在编辑器底部终端启动该 Bot 对应的 Pi Agent 会话", en: "Launch interactive Pi Agent session in built-in Terminal"))
                }
                
                Toggle("启用", isOn: self.$config.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.config.isEnabled) { _, _ in
                        self.saveBotConfig()
                    }
            }
            
            Divider()
            
            // Gateway + Model Selector (supports ANY model under ANY configured API gateway)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(AppLanguage.text("网关模型", en: "Gateway"))
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 66, alignment: .leading)
                    
                    Menu {
                        Button {
                            let previousBrand = self.resolvedCharacter?.id
                            self.config.endpointID = nil
                            self.config.modelOverride = ""
                            if self.resolvedCharacter?.id != previousBrand {
                                self.config.artworkVariantIndex = nil
                            }
                            self.saveBotConfig()
                        } label: {
                            let isFollowingDefault = (self.config.endpointID == nil && self.config.modelOverride.isEmpty)
                            let defaultDesc = self.activeEndpoint.map {
                                "\($0.displayName) · \($0.displayModel ?? AppLanguage.text("默认", en: "Default"))"
                            } ?? AppLanguage.text("全局默认", en: "Global Default")
                            if isFollowingDefault {
                                Label("跟随全局默认 (\(defaultDesc))", systemImage: "checkmark")
                            } else {
                                Text("跟随全局默认 (\(defaultDesc))")
                            }
                        }
                        
                        if !self.allEndpoints.isEmpty {
                            Divider()
                            ForEach(self.allEndpoints) { profile in
                                let models = self.selectableModels(for: profile)
                                let isDefaultEndpoint = (profile.id == self.activeEndpoint?.id)
                                let sectionHeader = isDefaultEndpoint
                                    ? "\(profile.displayName)（当前默认）"
                                    : profile.displayName
                                
                                Section(sectionHeader) {
                                    ForEach(models, id: \.self) { modelID in
                                        let isPicked = (self.config.endpointID == profile.id && self.config.modelOverride == modelID)
                                        Button {
                                            let previousBrand = self.resolvedCharacter?.id
                                            self.config.endpointID = profile.id
                                            self.config.modelOverride = modelID
                                            if self.resolvedCharacter?.id != previousBrand {
                                                self.config.artworkVariantIndex = nil
                                            }
                                            self.saveBotConfig()
                                        } label: {
                                            if isPicked {
                                                Label(modelID, systemImage: "checkmark")
                                            } else {
                                                Text(modelID)
                                            }
                                        }
                                    }
                                    
                                    Button {
                                        Task { await self.fetchModels(for: profile) }
                                    } label: {
                                        Label(
                                            self.fetchingEndpointIDs.contains(profile.id)
                                                ? "正在刷新模型…"
                                                : "刷新「\(profile.displayName)」模型列表",
                                            systemImage: "arrow.triangle.2.circlepath"
                                        )
                                    }
                                    .disabled(self.fetchingEndpointIDs.contains(profile.id))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if !self.fetchingEndpointIDs.isEmpty {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "cpu")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(accent)
                            }
                            Text("\(endpointTag) · \(modelLabel)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(self.cardBorder, lineWidth: 0.75)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                
                HStack(spacing: 10) {
                    Text(AppLanguage.text("自定义ID", en: "Custom ID"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .leading)
                    
                    TextField(endpoint?.displayModel ?? "输入任意模型 ID（覆盖默认）", text: self.$config.modelOverride)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .onChange(of: self.config.modelOverride) { _, _ in
                            self.saveBotConfig()
                        }
                    
                    if self.config.endpointID != nil || !self.config.modelOverride.isEmpty {
                        Button(AppLanguage.text("默认", en: "Reset")) {
                            self.config.endpointID = nil
                            self.config.modelOverride = ""
                            self.config.artworkVariantIndex = nil
                            self.saveBotConfig()
                        }
                        .controlSize(.small)
                    }
                }
            }
            
            HStack(spacing: 10) {
                Text(AppLanguage.text("Pi 能力", en: "Pi Mode"))
                    .font(.system(size: 12.5, weight: .medium))
                    .frame(width: 66, alignment: .leading)
                
                Picker("", selection: Binding(
                    get: { self.config.effectiveToolProfile(for: self.botID) },
                    set: { selected in
                        self.config.toolProfile = (selected == self.botID.defaultPiToolProfile) ? nil : selected
                        self.saveBotConfig()
                    }
                )) {
                    ForEach(PiBotToolProfile.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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
    
    
    private func fetchModels(for profile: AIEndpointProfile) async {
        self.fetchingEndpointIDs.insert(profile.id)
        defer { self.fetchingEndpointIDs.remove(profile.id) }
        let config = profile.configuration(apiKey: AIEndpointStore.apiKey(for: profile))
        do {
            let models = try await AIService.shared.fetchModels(configuration: config)
            let ids = models.map(\.id)
            self.fetchedModelsByEndpoint[profile.id] = ids
            var updated = profile
            updated.rememberModels(Array(ids.prefix(24)))
            AIEndpointStore.save(updated, apiKey: AIEndpointStore.apiKey(for: profile))
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
            self.onEndpointsUpdated()
        } catch {
            self.testError = "刷新「\(profile.displayName)」模型失败：\(error.localizedDescription)"
        }
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


// MARK: - Adaptive HD Portrait & Bust Avatar Renderer

/// Renders HD standing character portraits with aspect-aware framing:
/// - In square/circular avatar frames (`width ≈ height`), zooms cleanly onto the character's head & bust.
/// - In `3:4` portrait cards (`Gallery`, `Pack`, `Inspector`), fills the vertical card edge-to-edge
///   aligned from the top so there are zero blurry side bars and zero forehead/hair-ornament clipping,
///   backed by a cohesive studio paper surface that keeps transparent cutouts crisp in both Light and Dark mode.
private struct AIGijinkaCompleteArtworkView: View {
    
    let image: NSImage
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let isDark: Bool
    let isEnabled: Bool
    
    private var isCompactAvatar: Bool {
        abs(self.width - self.height) <= 4 && self.width <= 64
    }
    
    private var imageAspectRatio: CGFloat {
        let size = self.image.size
        guard size.width > 1, size.height > 1 else { return 0.75 }
        return size.width / size.height
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Unified pearl-tinted studio card surface so both transparent cutouts and white-studio illustrations match seamlessly
            LinearGradient(
                colors: [
                    self.isDark
                        ? Color(red: 0.945, green: 0.952, blue: 0.968)
                        : Color(red: 0.985, green: 0.988, blue: 0.995),
                    self.isDark
                        ? Color(red: 0.905, green: 0.916, blue: 0.938)
                        : Color(red: 0.955, green: 0.962, blue: 0.976),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            RadialGradient(
                colors: [
                    self.accent.opacity(self.isDark ? 0.16 : 0.11),
                    Color.clear,
                ],
                center: .top,
                startRadius: 4,
                endRadius: max(self.width, self.height) * 0.85
            )
            
            if self.isCompactAvatar {
                // Close-up head & bust framing for 26x26 gateway badges and 48x48 list avatars
                let zoomedWidth = self.width * (self.imageAspectRatio < 0.65 ? 1.48 : 1.32)
                Image(nsImage: self.image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: zoomedWidth, height: self.height * 1.12, alignment: .top)
                    .offset(y: -self.height * 0.02)
            } else if self.imageAspectRatio > 0.92 {
                // 1:1 square illustrations fit edge-to-edge vertically and center cleanly
                Image(nsImage: self.image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: self.width, height: self.height, alignment: .center)
            } else {
                // 9:16, 2:3 & 3:4 vertical standing portraits fill 100% card width from top headroom down (3/4-to-full body, zero side bars)
                Image(nsImage: self.image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: self.width, height: self.height, alignment: .top)
            }
        }
        .frame(width: self.width, height: self.height)
        .clipped()
        .opacity(self.isEnabled ? 1.0 : 0.45)
    }
}
