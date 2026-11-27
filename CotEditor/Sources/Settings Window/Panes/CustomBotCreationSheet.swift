//
//  CustomBotCreationSheet.swift
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

struct CustomBotCreationSheet: View {
    
    var editingBot: CustomBotProfile? = nil
    let onSaved: (CustomBotProfile) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var botStore = AIBotStore.shared
    @State private var nickname: String = ""
    @State private var avatarAssetID: String? = nil
    @State private var avatarArtworkID: String? = nil
    @State private var avatarData: Data? = nil
    @State private var previewImage: NSImage? = nil
    @State private var endpointID: UUID? = nil
    @State private var modelOverride: String = ""
    @State private var personaPrompt: String = ""
    @State private var gatewayGroups: [AIBotStore.SelectableGatewayGroup] = []
    @State private var isRefreshingModels = false
    @State private var showAvatarPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(self.editingBot == nil
                     ? AppLanguage.text("新建 Bot", en: "New Bot")
                     : AppLanguage.text("编辑 Bot", en: "Edit Bot"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            
            self.avatarAndNicknameSection
            self.modelSection
            self.personaSection
            
            HStack {
                if let editingBot = self.editingBot {
                    Button(AppLanguage.text("删除", en: "Delete"), role: .destructive) {
                        self.botStore.deleteCustomBot(id: editingBot.id)
                        self.dismiss()
                    }
                }
                Spacer()
                Button(AppLanguage.text("取消", en: "Cancel")) {
                    self.dismiss()
                }
                Button(AppLanguage.text("保存", en: "Save")) {
                    self.saveBot()
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear { self.loadInitial() }
    }
    
    
    private var avatarAndNicknameSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String((self.nickname.isEmpty ? "B" : self.nickname).prefix(1)))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                TextField(AppLanguage.text("昵称", en: "Nickname"), text: self.$nickname)
                    .textFieldStyle(.roundedBorder)
                
                HStack(spacing: 8) {
                    Button(AppLanguage.text("上传头像", en: "Upload")) {
                        self.pickLocalAvatar()
                    }
                    .controlSize(.small)
                    
                    Button(AppLanguage.text("头像库", en: "Library")) {
                        self.showAvatarPicker.toggle()
                    }
                    .controlSize(.small)
                    .popover(isPresented: self.$showAvatarPicker, arrowEdge: .bottom) {
                        AvatarLibraryPickerPopover { asset in
                            self.avatarAssetID = asset.id
                            self.avatarArtworkID = nil
                            self.avatarData = nil
                            self.previewImage = UserMediaLibraryStore.shared.thumbnailImage(for: asset, maxPixelSize: 160)
                            self.showAvatarPicker = false
                        }
                    }
                }
            }
        }
    }
    
    
    private var modelSection: some View {
        let groups = self.gatewayGroups
        let activeGroup = groups.first(where: \.isActive) ?? groups.first
        let defaultModel = activeGroup?.profile.displayModel ?? AIProvider.openCodeGo.defaultModel
        let activeTitle = activeGroup?.title ?? "API 网关"
        let selectedLabel: String = {
            let trimmed = self.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return AppLanguage.text("跟随当前默认 (\(defaultModel))", en: "Default (\(defaultModel))")
            }
            if let epID = self.endpointID,
               let group = groups.first(where: { $0.profile.id == epID }),
               groups.count > 1
            {
                return "\(group.title) · \(trimmed)"
            }
            return trimmed
        }()
        
        return HStack(spacing: 10) {
            Text(AppLanguage.text("后端模型", en: "Model"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            
            Menu {
                let isDefault = (self.endpointID == nil && self.modelOverride.isEmpty)
                Button(isDefault ? "✓  跟随 \(activeTitle) 默认 (\(defaultModel))" : "跟随 \(activeTitle) 默认 (\(defaultModel))") {
                    self.endpointID = nil
                    self.modelOverride = ""
                }
                ForEach(groups) { group in
                    if !group.models.isEmpty {
                        Divider()
                        Section(group.isActive ? "\(group.title)（当前）" : group.title) {
                            ForEach(group.models, id: \.self) { modelID in
                                let picked = (self.modelOverride == modelID
                                              && (self.endpointID == group.profile.id || (self.endpointID == nil && group.isActive)))
                                Button(picked ? "✓  \(modelID)" : modelID) {
                                    self.endpointID = group.profile.id
                                    self.modelOverride = modelID
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedLabel)
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
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            
            Button {
                Task { await self.refreshModels() }
            } label: {
                Text(self.isRefreshingModels
                     ? AppLanguage.text("刷新中", en: "Fetching")
                     : AppLanguage.text("刷新模型", en: "Refresh"))
                    .font(.system(size: 11.5))
            }
            .controlSize(.small)
            .disabled(self.isRefreshingModels)
        }
    }
    
    
    private var personaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.text("性格与情绪", en: "Personality"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            
            ZStack(alignment: .topLeading) {
                TextEditor(text: self.$personaPrompt)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if self.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8))
        }
    }
    
    
    private func loadInitial() {
        self.gatewayGroups = self.botStore.selectableGatewayGroups()
        guard let editingBot else { return }
        let preferred = editingBot.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nickname = preferred.isEmpty ? editingBot.name : preferred
        self.avatarAssetID = editingBot.avatarAssetID
        self.avatarArtworkID = editingBot.avatarArtworkID
        self.endpointID = editingBot.endpointID
        self.modelOverride = editingBot.modelOverride
        self.personaPrompt = editingBot.personaPrompt
        self.previewImage = self.botStore.resolvedAvatarImage(forBotID: editingBot.id, pointSize: 120)
    }
    
    
    private func pickLocalAvatar() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let data = try? Data(contentsOf: url)
            else { return }
            Task { @MainActor in
                self.avatarData = data
                self.avatarAssetID = nil
                self.avatarArtworkID = nil
                self.previewImage = NSImage(data: data)
            }
        }
    }
    
    
    private func refreshModels() async {
        self.isRefreshingModels = true
        defer { self.isRefreshingModels = false }
        let target = self.gatewayGroups.first(where: { $0.profile.id == self.endpointID })?.profile
            ?? self.gatewayGroups.first(where: \.isActive)?.profile
        _ = try? await self.botStore.refreshGatewayModels(for: target)
        self.gatewayGroups = self.botStore.selectableGatewayGroups()
    }
    
    
    private func saveBot() {
        let cleanNick = self.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNick.isEmpty else { return }
        let cleanPersona = self.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if var existing = self.editingBot {
            existing.name = cleanNick
            existing.nickname = cleanNick
            existing.avatarAssetID = self.avatarAssetID
            existing.avatarArtworkID = self.avatarArtworkID
            if let avatarData = self.avatarData,
               let rawImg = NSImage(data: avatarData),
               let png = UserProfileManager.processedAvatarPNGData(from: rawImg)
            {
                existing.avatarBase64 = png.base64EncodedString()
            }
            existing.endpointID = self.endpointID
            existing.modelOverride = self.modelOverride
            existing.personaPrompt = cleanPersona
            existing.baseline = .calm
            existing.preferredStickerCategories = []
            self.botStore.updateCustomBot(existing)
            self.onSaved(existing)
        } else {
            let created = self.botStore.createCustomBot(
                name: cleanNick,
                nickname: cleanNick,
                avatarAssetID: self.avatarAssetID,
                avatarArtworkID: self.avatarArtworkID,
                avatarData: self.avatarData,
                endpointID: self.endpointID,
                modelOverride: self.modelOverride,
                personaPrompt: cleanPersona,
                baseline: .calm,
                preferredStickerCategories: []
            )
            self.onSaved(created)
        }
        self.dismiss()
    }
}


/// Compact section listing user-created custom Bots with quick edit & create triggers.
struct CustomBotsRosterSection: View {
    
    let cardSurface: Color
    let cardBorder: Color
    let onCreateNew: () -> Void
    let onEditBot: (CustomBotProfile) -> Void
    
    @State private var botStore = AIBotStore.shared
    
    var body: some View {
        let _ = self.botStore.customBotsRevision
        if !self.botStore.customBots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppLanguage.text("自定义 Bots", en: "Custom Bots"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(self.botStore.customBots.count)")
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                VStack(spacing: 6) {
                    ForEach(self.botStore.customBots) { bot in
                        self.customBotRow(bot)
                    }
                }
            }
        }
    }
    
    
    private func customBotRow(_ bot: CustomBotProfile) -> some View {
        let avatar = self.botStore.resolvedAvatarImage(forBotID: bot.id, pointSize: 56)
        let summary = bot.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hexString: bot.accentHex).opacity(0.14))
                if let avatar {
                    Image(nsImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(bot.name.prefix(1)))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hexString: bot.accentHex))
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(bot.name)
                    .font(.system(size: 13, weight: .semibold))
                if !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { bot.isEnabled },
                set: { next in
                    var copy = bot
                    copy.isEnabled = next
                    self.botStore.updateCustomBot(copy)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            
            Button(AppLanguage.text("编辑", en: "Edit")) {
                self.onEditBot(bot)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.cardBorder, lineWidth: 0.8))
    }
}
