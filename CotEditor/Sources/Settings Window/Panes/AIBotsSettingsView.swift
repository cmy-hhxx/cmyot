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
import UniformTypeIdentifiers

// MARK: - Wrapping Flow Layout (Zero Truncation)

private struct WrappingFlowLayout: Layout {
    
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6
    
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                usedWidth = max(usedWidth, currentX - self.horizontalSpacing)
                currentX = 0
                currentY += rowHeight + self.verticalSpacing
                rowHeight = 0
            }
            currentX += size.width + self.horizontalSpacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, currentX - self.horizontalSpacing)
        }
        let totalHeight = subviews.isEmpty ? 0 : currentY + rowHeight
        return CGSize(width: proposal.width ?? usedWidth, height: totalHeight)
    }
    
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + self.verticalSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
            )
            currentX += size.width + self.horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}


// MARK: - API 网关 (OpenCode Go 一站式配置 · Pi 内核状态)

struct AIModelsSettingsView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var profile: AIEndpointProfile = AIProvider.openCodeGo.makeProfile()
    @State private var apiKey: String = ""
    @State private var isRevealingKey = false
    @State private var probeStatus: EndpointProbeStatus? = nil
    @State private var fetchedModels: [AIModel] = []
    @State private var isFetchingModels = false
    @State private var didSaveIndicator = false
    @State private var persistDebounceTask: Task<Void, Never>?
    
    @State private var piKernel = PiKernelManager.shared
    @State private var kernelEnabled: Bool = PiKernelManager.shared.isKernelEnabled
    
    private let labelColumnWidth: CGFloat = 68
    
    private enum EndpointProbeStatus: Equatable {
        case running
        case succeeded(String, latencyMs: Int)
        case failed(String)
    }
    
    
    private var trimmedKey: String {
        self.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var standardOpenCodeGoURL: String {
        (self.profile.endpoint == .anthropicMessages)
            ? "https://opencode.ai/zen/go"
            : "https://opencode.ai/zen/go/v1"
    }
    
    private var isCustomURLModified: Bool {
        let current = self.profile.resolvedBaseURL
        return current != "https://opencode.ai/zen/go/v1" && current != "https://opencode.ai/zen/go"
    }
    
    private var currentModelLabel: String {
        let trimmed = self.profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AIProvider.openCodeGo.defaultModel : trimmed
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Section 1: OpenCode Go One-Step Setup
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AppLanguage.text("OpenCode Go 订阅接入", en: "OpenCode Go Subscription"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer(minLength: 8)
                    
                    HStack(spacing: 5) {
                        Circle()
                            .fill(self.trimmedKey.isEmpty ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(self.trimmedKey.isEmpty
                             ? AppLanguage.text("待输入 Key", en: "Key Required")
                             : self.currentModelLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.trimmedKey.isEmpty ? Color.orange : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.trailing, 3)
                }
                
                self.openCodeGoCard
            }
            
            // Section 2: Pi 内核开关（极简状态行）
            VStack(alignment: .leading, spacing: 7) {
                Text(AppLanguage.text("Pi 内核底座", en: "Pi Kernel Runtime"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 3)
                
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
        .task {
            self.reload()
            if !self.trimmedKey.isEmpty && self.fetchedModels.isEmpty {
                await self.fetchRemoteModels(silentError: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
    }
    
    
    // MARK: - OpenCode Go Setup Card
    
    private var openCodeGoCard: some View {
        let accent = Color(hexString: AIProvider.openCodeGo.accentHex)
        let hasKey = !self.trimmedKey.isEmpty
        
        return VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
                
                Text("OpenCode Go")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(hasKey
                     ? AppLanguage.text("已激活", en: "Active")
                     : AppLanguage.text("未填 Key", en: "Key Needed"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hasKey ? Color.green : Color.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background((hasKey ? Color.green : Color.orange).opacity(0.14), in: Capsule())
                
                if self.didSaveIndicator {
                    Text(AppLanguage.text("已自动保存", en: "Saved"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                
                Spacer(minLength: 8)
                
                Button {
                    Task { await self.testOpenCodeGo() }
                } label: {
                    HStack(spacing: 5) {
                        if case .running = self.probeStatus {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                                .frame(width: 12, height: 12)
                        }
                        Text(AppLanguage.text("测试连接", en: "Test Connection"))
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(hasKey ? Color.white : Color.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(hasKey ? accent : Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasKey || self.probeStatus == .running)
                .pointerStyle(hasKey ? .link : .default)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            self.rowDivider
            
            // Row 1: Single API Key Input
            HStack(alignment: .center, spacing: 12) {
                Text("API Key")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: self.labelColumnWidth, alignment: .leading)
                
                HStack(spacing: 8) {
                    Group {
                        if self.isRevealingKey {
                            TextField(
                                AppLanguage.text("直接粘贴 OpenCode Go Key，输入即生效", en: "Paste OpenCode Go API Key"),
                                text: self.apiKeyBinding
                            )
                            .font(.system(size: 12, design: .monospaced))
                        } else {
                            SecureField(
                                AppLanguage.text("直接粘贴 OpenCode Go Key，输入即生效", en: "Paste OpenCode Go API Key"),
                                text: self.apiKeyBinding
                            )
                            .font(.system(size: 12))
                        }
                    }
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if hasKey {
                            Task { await self.testOpenCodeGo() }
                        }
                    }
                    
                    if self.trimmedKey.isEmpty {
                        Button(AppLanguage.text("粘贴", en: "Paste")) {
                            if let pasted = NSPasteboard.general.string(forType: .string)?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !pasted.isEmpty
                            {
                                self.apiKeyBinding.wrappedValue = pasted
                            }
                        }
                        .controlSize(.mini)
                    } else {
                        Button(self.isRevealingKey ? AppLanguage.text("隐藏", en: "Hide") : AppLanguage.text("显示", en: "Show")) {
                            self.isRevealingKey.toggle()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        
                        Button(AppLanguage.text("清除", en: "Clear")) {
                            self.apiKeyBinding.wrappedValue = ""
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(self.cardBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            self.rowDivider
            
            // Row 2: Pre-filled URL & Protocol Selector
            HStack(alignment: .top, spacing: 12) {
                Text(AppLanguage.text("接口地址", en: "Endpoint"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: self.labelColumnWidth, alignment: .leading)
                    .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("https://opencode.ai/zen/go/v1", text: self.baseURLBinding)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.05 : 0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(self.cardBorder, lineWidth: 0.75)
                            )
                        
                        if self.isCustomURLModified {
                            Button(AppLanguage.text("恢复默认", en: "Reset")) {
                                self.baseURLBinding.wrappedValue = self.standardOpenCodeGoURL
                            }
                            .controlSize(.small)
                        }
                    }
                    
                    WrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(AIEndpoint.subscriptionProtocols, id: \.self) { proto in
                            let selected = (self.profile.endpoint == proto)
                            Button {
                                self.switchProtocol(proto)
                            } label: {
                                Text(proto.shortProtocolBadge)
                                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                    .foregroundStyle(selected ? Color.white : Color.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selected ? accent : Color.primary.opacity(self.colorScheme == .dark ? 0.07 : 0.045))
                                    )
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            self.rowDivider
            
            // Row 3: Default Model Pure Selection + Curated Quick-Switch Model Chips
            HStack(alignment: .top, spacing: 12) {
                Text(AppLanguage.text("默认模型", en: "Model"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: self.labelColumnWidth, alignment: .leading)
                    .padding(.top, 5)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(AIProvider.openCodeGoModelGroups) { group in
                                Section(group.title) {
                                    ForEach(group.models, id: \.self) { modelID in
                                        Button(self.currentModelLabel == modelID ? "✓  \(modelID)" : modelID) {
                                            self.selectModel(modelID)
                                        }
                                    }
                                }
                            }
                            let curatedSet = Set(AIProvider.openCodeGo.recommendedModels)
                            let remoteExtras = self.fetchedModels.map(\.id).filter { !curatedSet.contains($0) }
                            if !remoteExtras.isEmpty {
                                Section(AppLanguage.text("接口获取模型", en: "Fetched Models")) {
                                    ForEach(remoteExtras, id: \.self) { modelID in
                                        Button(self.currentModelLabel == modelID ? "✓  \(modelID)" : modelID) {
                                            self.selectModel(modelID)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(self.currentModelLabel)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 4)
                                Text("▾")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(self.cardBorder, lineWidth: 1)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        
                        if self.profile.model != AIProvider.openCodeGo.defaultModel {
                            Button(AppLanguage.text("设为默认", en: "Default")) {
                                self.selectModel(AIProvider.openCodeGo.defaultModel)
                            }
                            .controlSize(.small)
                        }
                        
                        if hasKey {
                            Button {
                                Task { await self.fetchRemoteModels(silentError: false) }
                            } label: {
                                HStack(spacing: 4) {
                                    if self.isFetchingModels {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.7)
                                            .frame(width: 12, height: 12)
                                    }
                                    Text(self.isFetchingModels
                                         ? AppLanguage.text("刷新中", en: "Fetching")
                                         : AppLanguage.text("刷新模型", en: "Refresh Models"))
                                        .font(.system(size: 11))
                                }
                            }
                            .controlSize(.small)
                            .disabled(self.isFetchingModels)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AIProvider.openCodeGoModelGroups) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.title)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                
                                WrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                    ForEach(group.models, id: \.self) { modelID in
                                        self.modelChip(modelID: modelID, accent: accent)
                                    }
                                }
                            }
                        }
                        
                        let curatedSet = Set(AIProvider.openCodeGo.recommendedModels)
                        let remoteExtras = self.fetchedModels
                            .map(\.id)
                            .filter { !curatedSet.contains($0) }
                        if !remoteExtras.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(AppLanguage.text("接口获取模型", en: "Fetched Models"))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                
                                WrappingFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                                    ForEach(remoteExtras.prefix(12), id: \.self) { modelID in
                                        self.modelChip(modelID: modelID, accent: accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            if let probeStatus = self.probeStatus {
                self.rowDivider
                self.probeBanner(probeStatus)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
    }
    
    
    @ViewBuilder
    private func modelChip(modelID: String, accent: Color) -> some View {
        let isSelected = (self.profile.model == modelID)
        
        Button {
            self.selectModel(modelID)
        } label: {
            Text(modelID)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.86))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? accent : Color.primary.opacity(self.colorScheme == .dark ? 0.065 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(isSelected ? accent : self.cardBorder, lineWidth: isSelected ? 1.1 : 0.75)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    @ViewBuilder
    private func probeBanner(_ probe: EndpointProbeStatus) -> some View {
        HStack(alignment: .center, spacing: 8) {
            switch probe {
                case .running:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                    Text(AppLanguage.text("正在测速连通性", en: "Testing Connection"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .succeeded(let reply, let latencyMs):
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text("连通 · \(latencyMs) ms · \(reply)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
    
    
    // MARK: - Bindings & Persistence
    
    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { self.apiKey },
            set: { newKey in
                self.apiKey = newKey
                self.scheduleDebouncedPersistOpenCodeGo()
            }
        )
    }
    
    private var baseURLBinding: Binding<String> {
        Binding(
            get: { self.profile.baseURL },
            set: { newURL in
                self.profile.baseURL = newURL
                self.scheduleDebouncedPersistOpenCodeGo()
            }
        )
    }
    
    
    private var rowDivider: some View {
        Rectangle()
            .fill(self.colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white
    }
    
    private var cardBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    private func reload() {
        AIEndpointStore.migrateLegacyConfigurationIfNeeded()
        let storedProfiles = AIEndpointStore.profiles
        let activeID = AIEndpointStore.activeID
        
        let existingOpenCodeGo = storedProfiles.first(where: { $0.id == activeID && $0.provider == .openCodeGo })
            ?? storedProfiles.first(where: { $0.provider == .openCodeGo })
        
        if var target = existingOpenCodeGo {
            var didNormalize = false
            for (k, v) in AIProvider.openCodeGo.defaultCustomHeaders where target.customHeaders[k] == nil {
                target.customHeaders[k] = v
                didNormalize = true
            }
            let prevSaved = target.savedModels
            target.rememberModels(AIProvider.openCodeGo.recommendedModels)
            if target.savedModels != prevSaved {
                didNormalize = true
            }
            if target.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                target.model = AIProvider.openCodeGo.defaultModel
                didNormalize = true
            }
            let key = AIEndpointStore.apiKey(for: target)
            if didNormalize || AIEndpointStore.activeID != target.id {
                AIEndpointStore.save(target, apiKey: key)
                AIEndpointStore.activeID = target.id
                CotLocalDatabase.shared.syncAIEndpointsToDatabase()
                _ = try? self.piKernel.syncWorkspace()
            }
            self.profile = target
            self.apiKey = key
        } else {
            let created = AIProvider.openCodeGo.makeProfile()
            AIEndpointStore.save(created, apiKey: "")
            AIEndpointStore.activeID = created.id
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
            _ = try? self.piKernel.syncWorkspace()
            self.profile = created
            self.apiKey = ""
        }
        
        self.kernelEnabled = self.piKernel.isKernelEnabled
    }
    
    
    private func scheduleDebouncedPersistOpenCodeGo() {
        self.persistDebounceTask?.cancel()
        self.persistDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self.persistOpenCodeGo()
        }
    }
    
    
    private func persistOpenCodeGo() {
        self.persistDebounceTask?.cancel()
        self.persistDebounceTask = nil
        var updated = self.profile
        if updated.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.name = AIProvider.openCodeGo.label
        }
        for (k, v) in AIProvider.openCodeGo.defaultCustomHeaders where updated.customHeaders[k] == nil {
            updated.customHeaders[k] = v
        }
        updated.rememberModels(AIProvider.openCodeGo.recommendedModels + [updated.model])
        
        self.profile = updated
        AIEndpointStore.save(updated, apiKey: self.trimmedKey)
        AIEndpointStore.activeID = updated.id
        CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        _ = try? self.piKernel.syncWorkspace()
        self.probeStatus = nil
        
        withAnimation(.easeOut(duration: 0.14)) {
            self.didSaveIndicator = true
        }
        let targetKeySnapshot = self.trimmedKey
        let targetModelSnapshot = updated.model
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if self.trimmedKey == targetKeySnapshot && self.profile.model == targetModelSnapshot {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.didSaveIndicator = false
                }
            }
        }
    }
    
    
    private func switchProtocol(_ newEndpoint: AIEndpoint) {
        guard self.profile.endpoint != newEndpoint else { return }
        self.profile.endpoint = newEndpoint
        if !self.isCustomURLModified || self.profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.profile.baseURL = (newEndpoint == .anthropicMessages)
                ? "https://opencode.ai/zen/go"
                : "https://opencode.ai/zen/go/v1"
        }
        self.persistOpenCodeGo()
    }
    
    
    private func selectModel(_ modelID: String) {
        self.profile.model = modelID
        self.profile.rememberModels([modelID])
        self.persistOpenCodeGo()
    }
    
    
    private func fetchRemoteModels(silentError: Bool) async {
        self.isFetchingModels = true
        defer { self.isFetchingModels = false }
        let config = self.profile.configuration(apiKey: self.trimmedKey)
        do {
            let models = try await AIService.shared.fetchModels(configuration: config)
            self.fetchedModels = models
            var updated = self.profile
            updated.rememberModels(models.prefix(24).map(\.id))
            self.profile = updated
            AIEndpointStore.save(updated, apiKey: self.trimmedKey)
            CotLocalDatabase.shared.syncAIEndpointsToDatabase()
        } catch {
            if !silentError {
                self.probeStatus = .failed("拉取模型失败：\(error.localizedDescription)")
            }
        }
    }
    
    
    private func testOpenCodeGo() async {
        self.probeStatus = .running
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let reply = try await AIService.shared.testConnection(
                configuration: self.profile.configuration(apiKey: self.trimmedKey)
            )
            let elapsed = start.duration(to: clock.now)
            let ms = max(1, Int(elapsed.components.seconds * 1000) + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
            self.probeStatus = .succeeded(reply, latencyMs: ms)
        } catch {
            self.probeStatus = .failed(error.localizedDescription)
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
    let avatarImage: NSImage?
    
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
            && lhs.avatarImage === rhs.avatarImage
    }
}


private struct BotStageNodeView: View, Equatable {
    
    let snapshot: BotCardSnapshot
    let index: Int
    let total: Int
    let layoutMode: BotCollectionLayoutMode
    let isHovered: Bool
    let hoveredIndex: Int?
    let isDark: Bool
    let cardBorder: Color
    let onInspect: () -> Void
    let onToggleEnabled: (Bool) -> Void
    let onHoverChanged: (Bool) -> Void
    
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.index == rhs.index
            && lhs.total == rhs.total
            && lhs.layoutMode == rhs.layoutMode
            && lhs.isHovered == rhs.isHovered
            && lhs.hoveredIndex == rhs.hoveredIndex
            && lhs.isDark == rhs.isDark
    }
    
    
    private static let fixedStageWidth: CGFloat = 527
    private static let galleryColumns = 4
    private static let galleryGap: CGFloat = 13
    private static let galleryAvatarSide: CGFloat = 122
    private static let galleryRowStride: CGFloat = 180
    private static let packAvatarSide: CGFloat = 110
    
    
    var body: some View {
        let accent = Color(hexString: self.snapshot.accentHex)
        
        let itemWidth: CGFloat
        let itemHeight: CGFloat
        let artSide: CGFloat
        let artCorner: CGFloat
        let posX: CGFloat
        let posY: CGFloat
        let rotation: Double
        let packScale: CGFloat
        
        switch self.layoutMode {
            case .list:
                artSide = 46
                artCorner = 11
                itemWidth = Self.fixedStageWidth
                itemHeight = 52
                posX = 0
                posY = CGFloat(self.index) * 64.0
                rotation = 0
                packScale = 1.0
            case .card:
                artSide = Self.galleryAvatarSide
                artCorner = 22
                itemWidth = artSide
                itemHeight = artSide + 52
                let col = self.index % Self.galleryColumns
                let row = self.index / Self.galleryColumns
                posX = CGFloat(col) * (artSide + Self.galleryGap)
                posY = CGFloat(row) * Self.galleryRowStride
                rotation = 0
                packScale = 1.0
            case .pack:
                artSide = Self.packAvatarSide
                artCorner = 20
                itemWidth = artSide
                itemHeight = artSide
                let maxDeckSpan = Self.fixedStageWidth - artSide - 56
                let spread = self.total > 1 ? min(39.0, maxDeckSpan / CGFloat(self.total - 1)) : 0
                let mid = Double(self.total - 1) * 0.5
                let offsetIndex = Double(self.index) - mid
                var fanShift: CGFloat = 0
                if let hIdx = self.hoveredIndex, hIdx != self.index {
                    fanShift = self.index < hIdx ? -11.0 : 11.0
                }
                posX = (Self.fixedStageWidth - artSide) * 0.5 + CGFloat(offsetIndex) * spread + fanShift
                posY = 44.0 + abs(CGFloat(offsetIndex)) * 2.4 - (self.isHovered ? 12.0 : 0.0)
                rotation = self.isHovered ? 0.0 : offsetIndex * 2.4
                packScale = self.isHovered ? 1.06 : 1.0
        }
        
        return ZStack(alignment: .topLeading) {
            // 1:1 Square Avatar Frame across all 3 views (zero drawingGroup, pure pre-rasterized bitmap)
            ZStack {
                if let avatar = self.snapshot.avatarImage {
                    Image(nsImage: avatar)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .opacity(self.snapshot.isEnabled ? 1.0 : 0.45)
                } else {
                    LinearGradient(
                        colors: [
                            accent.opacity(self.isDark ? 0.22 : 0.14),
                            self.isDark
                                ? Color(red: 0.14, green: 0.14, blue: 0.17)
                                : Color(red: 0.96, green: 0.96, blue: 0.98),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(self.snapshot.shortTitle.prefix(1)))
                        .font(.system(size: min(artSide * 0.36, 28), weight: .semibold))
                        .foregroundStyle(accent)
                        .opacity(self.snapshot.isEnabled ? 1.0 : 0.45)
                }
                
                if self.layoutMode == .pack {
                    VStack(spacing: 0) {
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(self.snapshot.isEnabled ? accent : Color.white.opacity(0.45))
                                .frame(width: 5, height: 5)
                            Text(self.snapshot.shortTitle)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.0), Color.black.opacity(0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(width: artSide, height: artSide)
            .clipShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: artCorner, style: .continuous)
                    .strokeBorder(
                        self.isHovered
                            ? accent.opacity(0.85)
                            : (self.layoutMode == .pack
                               ? Color.white.opacity(self.isDark ? 0.20 : 0.78)
                               : self.cardBorder),
                        lineWidth: self.isHovered ? 1.6 : 0.9
                    )
            )
            .scaleEffect(packScale)
            .rotationEffect(.degrees(rotation))
            .contentShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
            .onTapGesture(perform: self.onInspect)
            
            // List view metadata right of 1:1 square avatar
            if self.layoutMode == .list {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(self.snapshot.displayTitle)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(self.snapshot.isEnabled ? .primary : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let personaBadge = self.snapshot.personaBadge {
                                Text(personaBadge)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(accent.opacity(self.isDark ? 0.16 : 0.10), in: Capsule())
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text(self.snapshot.modelLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                            if self.snapshot.recentCalls > 0 {
                                Text("· \(self.snapshot.recentCalls) 次")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    
                    Spacer(minLength: 6)
                    
                    Toggle("", isOn: Binding(
                        get: { self.snapshot.isEnabled },
                        set: { self.onToggleEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    
                    Button(action: self.onInspect) {
                        Text(AppLanguage.text("配置", en: "Edit"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(self.isHovered ? accent : Color(nsColor: .tertiaryLabelColor))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, artSide + 12)
                .frame(width: itemWidth, height: artSide, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: self.onInspect)
            }
            
            // Gallery square avatar caption underneath (zero ellipsis)
            if self.layoutMode == .card {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(self.snapshot.shortTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(self.snapshot.isEnabled ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer(minLength: 2)
                        
                        Circle()
                            .fill(self.snapshot.isEnabled ? accent : Color.primary.opacity(0.18))
                            .frame(width: 6, height: 6)
                    }
                    
                    Text(self.snapshot.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: artSide, alignment: .leading)
                .offset(y: artSide + 6)
                .onTapGesture(perform: self.onInspect)
            }
        }
        .frame(width: itemWidth, height: itemHeight, alignment: .topLeading)
        .offset(x: posX, y: posY)
        .zIndex(Double(self.index) + (self.isHovered && self.layoutMode == .pack ? 50 : 0))
        .onHover { hovering in
            guard self.layoutMode != .pack else { return }
            self.onHoverChanged(hovering)
        }
        .pointerStyle(.link)
        .help("\(self.snapshot.displayTitle) · \(self.snapshot.modelLabel)")
    }
}


struct AIBotsSettingsView: View {
    
    /// Exact deterministic content width (`780 - 204 sidebar - 1 divider - 48 padding = 527pt`)
    /// so entering the Agents pane matches all other panes flush edge-to-edge with zero geometry jump.
    private static let fixedStageWidth: CGFloat = 527
    
    var settingsState: SidebarSettingsState? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var botStore = AIBotStore.shared
    @State private var butlerManager = CotButlerManager.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    @State private var piKernel = PiKernelManager.shared
    @State private var layoutMode: BotCollectionLayoutMode = .card
    @State private var inspectingBot: AIBotID?
    @State private var allEndpoints: [AIEndpointProfile] = []
    @State private var activeEndpoint: AIEndpointProfile?
    @State private var hoveredBotID: AIBotID?
    @State private var snapshots: [BotCardSnapshot] = []
    
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
            self.reload()
            self.consumePendingBotSelection()
        }
        .onChange(of: self.settingsState?.pendingBotID) { _, _ in
            self.consumePendingBotSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
    }
    
    
    private func consumePendingBotSelection() {
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
    
    
    private func rebuildSnapshots() {
        let featureCounts = Dictionary(
            self.analytics.featureDistribution(days: 30).map { ($0.feature, $0.requests) },
            uniquingKeysWith: { first, _ in first }
        )
        
        var nextSnapshots: [BotCardSnapshot] = []
        var artworksToPrefetch: [AIGijinkaArtwork] = []
        
        for botID in AIBotID.allCases {
            let config = self.botStore.config(for: botID)
            let endpoint = self.resolvedEndpoint(for: config)
            let character = self.resolvedCharacter(for: botID, config: config)
            let artwork = character?.artwork(for: botID, variantOverride: config.artworkVariantIndex)
            if let artwork {
                artworksToPrefetch.append(artwork)
            }
            
            let avatarImage = self.botStore.resolvedAvatarImage(for: botID, pointSize: 122)
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
                avatarImage: avatarImage
            ))
        }
        self.imageLoader.prefetch(artworksToPrefetch)
        self.snapshots = nextSnapshots
    }
    
    
    // MARK: Morphing Gallery / List / Pack Stage
    
    @ViewBuilder
    private var morphingCollectionView: some View {
        let bots = AIBotID.allCases
        let cols = 4
        let rowsCount = Int(ceil(Double(bots.count) / Double(cols)))
        let galleryRowStride: CGFloat = 180
        let stageHeight: CGFloat = switch self.layoutMode {
            case .list: CGFloat(bots.count) * 64.0
            case .card: CGFloat(rowsCount) * galleryRowStride
            case .pack: 274.0
        }
        let enabledCount = self.snapshots.filter(\.isEnabled).count
        let hoveredIndex = self.hoveredBotID.flatMap { id in bots.firstIndex(of: id) }
        let focusedPackSnap = self.snapshots.first(where: { $0.botID == self.hoveredBotID }) ?? self.snapshots.first
        let isDark = (self.colorScheme == .dark)
        
        VStack(alignment: .leading, spacing: 14) {
            // Segmented Layout Switcher with shared sliding capsule (clean typography, zero decorative icons)
            HStack(spacing: 4) {
                ForEach(BotCollectionLayoutMode.allCases) { mode in
                    let isSelected = (self.layoutMode == mode)
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.28)) {
                            self.layoutMode = mode
                            if mode == .pack, self.hoveredBotID == nil {
                                self.hoveredBotID = bots.first
                            }
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
                        .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.022))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(self.cardBorder, lineWidth: 0.75)
                        )
                        .frame(width: Self.fixedStageWidth, height: 190)
                        .allowsHitTesting(false)
                }
                
                ForEach(Array(self.snapshots.enumerated()), id: \.element.id) { index, snap in
                    let botID = snap.botID
                    BotStageNodeView(
                        snapshot: snap,
                        index: index,
                        total: self.snapshots.count,
                        layoutMode: self.layoutMode,
                        isHovered: self.hoveredBotID == botID,
                        hoveredIndex: self.layoutMode == .pack ? hoveredIndex : nil,
                        isDark: isDark,
                        cardBorder: self.cardBorder,
                        onInspect: {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                self.inspectingBot = botID
                            }
                        },
                        onToggleEnabled: { enabled in
                            var updated = self.botStore.config(for: botID)
                            updated.isEnabled = enabled
                            self.botStore.updateConfig(updated, for: botID)
                            self.rebuildSnapshots()
                        },
                        onHoverChanged: { hovering in
                            guard self.layoutMode != .pack else { return }
                            if hovering {
                                if self.hoveredBotID != botID {
                                    self.hoveredBotID = botID
                                }
                            } else if self.hoveredBotID == botID {
                                self.hoveredBotID = nil
                            }
                        }
                    )
                    .equatable()
                }
                
                if self.layoutMode == .pack, let focusedSnap = focusedPackSnap {
                    let focusedAccent = Color(hexString: focusedSnap.accentHex)
                    
                    HStack(spacing: 12) {
                        Circle()
                            .fill(focusedSnap.isEnabled ? focusedAccent : Color.secondary.opacity(0.35))
                            .frame(width: 8, height: 8)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(focusedSnap.displayTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
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
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                self.inspectingBot = focusedSnap.botID
                            }
                        } label: {
                            Text(AppLanguage.text("进入配置", en: "Configure"))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Color.primary.opacity(isDark ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(width: Self.fixedStageWidth, alignment: .leading)
                    .frame(minHeight: 62)
                    .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
                    .offset(y: 204)
                }
            }
            .frame(width: Self.fixedStageWidth, height: stageHeight, alignment: .topLeading)
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard self.layoutMode == .pack else { return }
                switch phase {
                    case .active(let loc):
                        guard loc.y <= 198, !bots.isEmpty else { return }
                        let total = bots.count
                        let bestIdx = (0..<total).min { lhs, rhs in
                            abs(loc.x - self.packRestCenterX(index: lhs, total: total))
                                < abs(loc.x - self.packRestCenterX(index: rhs, total: total))
                        } ?? 0
                        let currentIdx = self.hoveredBotID.flatMap { bots.firstIndex(of: $0) }
                        let resolvedIdx: Int
                        if let currentIdx, currentIdx != bestIdx {
                            let currentDist = abs(loc.x - self.packRestCenterX(index: currentIdx, total: total))
                            let bestDist = abs(loc.x - self.packRestCenterX(index: bestIdx, total: total))
                            resolvedIdx = (bestDist + 8.0 < currentDist) ? bestIdx : currentIdx
                        } else {
                            resolvedIdx = bestIdx
                        }
                        let nextBot = bots[resolvedIdx]
                        if self.hoveredBotID != nextBot {
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.88)) {
                                self.hoveredBotID = nextBot
                            }
                        }
                    case .ended:
                        break
                }
            }
            
            HStack(spacing: 6) {
                Circle()
                    .fill(self.piKernel.isAvailable && self.piKernel.isKernelEnabled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(self.piKernel.statusSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.top, 2)
        }
    }
    
    
    private func packRestCenterX(index: Int, total: Int) -> CGFloat {
        let artSide: CGFloat = 110
        let maxDeckSpan = Self.fixedStageWidth - artSide - 56
        let spread = total > 1 ? min(39.0, maxDeckSpan / CGFloat(total - 1)) : 0
        let mid = Double(total - 1) * 0.5
        let offsetIndex = Double(index) - mid
        return Self.fixedStageWidth * 0.5 + CGFloat(offsetIndex) * spread
    }
    
    
    // MARK: Simplified Inline Bot Inspector (Avatar · Name · Nickname · Selectable OpenCode Go Model)
    
    @ViewBuilder
    private func inlineInspector(for botID: AIBotID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.inspectingBot = nil
                    }
                    self.reload()
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
                    self.reload()
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
        self.botStore.reloadFromDatabase()
        self.rebuildSnapshots()
    }
}


// MARK: - Simplified Inline Bot Inspector

private struct AIBotInlineInspectorView: View {
    
    let botID: AIBotID
    let cardSurface: Color
    let cardBorder: Color
    var onEndpointsUpdated: () -> Void = {}
    
    @State private var botStore = AIBotStore.shared
    @State private var butlerManager = CotButlerManager.shared
    @State private var config: AIBotConfig = AIBotConfig()
    @State private var customNameDraft: String = ""
    @State private var customNicknameDraft: String = ""
    @State private var openCodeGoModels: [String] = []
    @State private var isRefreshingModels = false
    
    
    private var resolvedOpenCodeGoProfile: AIEndpointProfile? {
        self.botStore.openCodeGoSelectableModels().profile
    }
    
    private var resolvedCharacter: AIGijinkaCharacter? {
        let endpoint = self.resolvedOpenCodeGoProfile
        let overrideModel = self.config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIGijinkaCharacter.resolve(
            modelName: overrideModel.isEmpty ? endpoint?.displayModel : overrideModel,
            endpointName: endpoint?.displayName,
            baseURL: endpoint?.baseURL
        )
    }
    
    
    var body: some View {
        let endpoint = self.resolvedOpenCodeGoProfile
        let character = self.resolvedCharacter
        let artwork = character?.artwork(for: self.botID, variantOverride: self.config.artworkVariantIndex)
        let accent = Color(hexString: character?.accentHex ?? self.botID.accentHex)
        let portrait = self.botStore.resolvedAvatarImage(for: self.botID, pointSize: 80)
        let shownName = self.botID == .butler
            ? (self.butlerManager.name.isEmpty ? "曜" : self.butlerManager.name)
            : (self.customNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? self.botID.displayName : self.customNameDraft)
        let shownNick = self.botID == .butler
            ? (self.butlerManager.nickname.isEmpty ? "总管" : self.butlerManager.nickname)
            : (self.customNicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? self.botID.defaultNickname : self.customNicknameDraft)
        let defaultModel = endpoint?.displayModel ?? AIProvider.openCodeGo.defaultModel
        let selectedModelLabel = self.config.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? AppLanguage.text("跟随 OpenCode Go 默认 (\(defaultModel))", en: "Default (\(defaultModel))")
            : self.config.modelOverride
        let hasCustomAvatar = self.botStore.customAvatarImage(for: self.botID) != nil
        
        VStack(alignment: .leading, spacing: 14) {
            // Identity Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(accent.opacity(0.14))
                    if let portrait {
                        Image(nsImage: portrait)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .opacity(self.config.isEnabled ? 1.0 : 0.45)
                    } else {
                        Text(String(shownName.prefix(1)))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.32), lineWidth: 0.75)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(shownName)
                            .font(.system(size: 15, weight: .semibold))
                        Text("@\(shownNick)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(selectedModelLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Toggle(AppLanguage.text("启用", en: "Enabled"), isOn: self.$config.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.config.isEnabled) { _, _ in
                        self.saveBotConfig()
                    }
            }
            
            Divider()
            
            // Row 1: 头像（上传头像 / 切换预设形象）
            HStack(spacing: 10) {
                Text(AppLanguage.text("头像", en: "Avatar"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                Button(AppLanguage.text("上传头像", en: "Upload Avatar")) {
                    self.pickCustomAvatar()
                }
                .controlSize(.small)
                
                if let character, character.artworks.count > 1 {
                    Menu {
                        Button(self.config.artworkVariantIndex == nil && !hasCustomAvatar ? "✓  自动分配形象" : "自动分配形象") {
                            self.botStore.setCustomAvatarData(nil, for: self.botID)
                            self.config.artworkVariantIndex = nil
                            self.saveBotConfig()
                            if self.botID == .butler {
                                self.butlerManager.syncArtworkVariant(nil)
                            }
                        }
                        Divider()
                        ForEach(Array(character.artworks.enumerated()), id: \.element.id) { idx, item in
                            let selected = (artwork?.id == item.id && self.config.artworkVariantIndex != nil && !hasCustomAvatar)
                            Button(selected ? "✓  \(item.title)" : item.title) {
                                self.botStore.setCustomAvatarData(nil, for: self.botID)
                                self.config.artworkVariantIndex = idx
                                self.saveBotConfig()
                                if self.botID == .butler {
                                    self.butlerManager.syncArtworkVariant(idx)
                                }
                            }
                        }
                    } label: {
                        Text("\(artwork?.title ?? AppLanguage.text("切换形象", en: "Preset Art")) ▾")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                
                if hasCustomAvatar {
                    Button(AppLanguage.text("恢复默认头像", en: "Reset Avatar")) {
                        self.botStore.setCustomAvatarData(nil, for: self.botID)
                    }
                    .controlSize(.small)
                }
                
                Spacer(minLength: 0)
            }
            
            // Row 2: 名称
            HStack(spacing: 10) {
                Text(AppLanguage.text("名称", en: "Name"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                if self.botID == .butler {
                    TextField("曜", text: self.$butlerManager.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                } else {
                    TextField(self.botID.displayName, text: self.$customNameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                        .onChange(of: self.customNameDraft) { _, newValue in
                            self.config.customName = newValue
                            self.saveBotConfig()
                        }
                }
            }
            
            // Row 3: 昵称
            HStack(spacing: 10) {
                Text(AppLanguage.text("昵称", en: "Nickname"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                if self.botID == .butler {
                    TextField("总管", text: self.$butlerManager.nickname)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                } else {
                    TextField(self.botID.defaultNickname, text: self.$customNicknameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                        .onChange(of: self.customNicknameDraft) { _, newValue in
                            self.config.customNickname = newValue
                            self.saveBotConfig()
                        }
                }
            }
            
            // Row 4: 纯选择 OpenCode Go 模型（无手动输入 Custom ID）
            HStack(spacing: 10) {
                Text(AppLanguage.text("模型", en: "Model"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                Menu {
                    let isFollowingDefault = (self.config.endpointID == nil && self.config.modelOverride.isEmpty)
                    Button {
                        let previousBrand = self.resolvedCharacter?.id
                        self.config.endpointID = nil
                        self.config.modelOverride = ""
                        if self.resolvedCharacter?.id != previousBrand {
                            self.config.artworkVariantIndex = nil
                        }
                        self.saveBotConfig()
                    } label: {
                        Text(isFollowingDefault
                             ? "✓  跟随 OpenCode Go 默认 (\(defaultModel))"
                             : "跟随 OpenCode Go 默认 (\(defaultModel))")
                    }
                    
                    if !self.openCodeGoModels.isEmpty {
                        Divider()
                        Section("OpenCode Go 可选模型") {
                            ForEach(self.openCodeGoModels, id: \.self) { modelID in
                                let picked = (self.config.modelOverride == modelID)
                                Button(picked ? "✓  \(modelID)" : modelID) {
                                    let previousBrand = self.resolvedCharacter?.id
                                    self.config.endpointID = endpoint?.id
                                    self.config.modelOverride = modelID
                                    if self.resolvedCharacter?.id != previousBrand {
                                        self.config.artworkVariantIndex = nil
                                    }
                                    self.saveBotConfig()
                                }
                            }
                        }
                    }
                    
                    Divider()
                    Button(self.isRefreshingModels ? "正在刷新模型…" : "刷新 OpenCode Go 模型列表") {
                        Task { await self.refreshModels() }
                    }
                    .disabled(self.isRefreshingModels)
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedModelLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text("▾")
                            .font(.system(size: 10.5, weight: .semibold))
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
                            .font(.system(size: 11))
                    }
                }
                .controlSize(.small)
                .disabled(self.isRefreshingModels)
            }
            
            Divider()
            
            HStack {
                Button(AppLanguage.text("恢复默认", en: "Reset Defaults"), role: .destructive) {
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
            }
        }
        .padding(14)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 1))
        .task(id: self.botID) {
            self.loadInitialState()
            if let ep = self.resolvedOpenCodeGoProfile,
               !AIEndpointStore.apiKey(for: ep).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                await self.refreshModels()
            }
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
            self.botStore.setCustomAvatarData(data, for: self.botID)
        }
    }
    
    
    private func loadInitialState() {
        let loaded = self.botStore.config(for: self.botID)
        self.config = loaded
        self.customNameDraft = loaded.customName
        self.customNicknameDraft = loaded.customNickname
        self.openCodeGoModels = self.botStore.openCodeGoSelectableModels().models
    }
    
    
    private func saveBotConfig() {
        self.botStore.updateConfig(self.config, for: self.botID)
    }
    
    
    private func refreshModels() async {
        self.isRefreshingModels = true
        defer { self.isRefreshingModels = false }
        if let models = try? await self.botStore.refreshOpenCodeGoModels() {
            self.openCodeGoModels = models
            self.onEndpointsUpdated()
        } else {
            self.openCodeGoModels = self.botStore.openCodeGoSelectableModels().models
        }
    }
}
