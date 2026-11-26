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
    @State private var name: String = ""
    @State private var nickname: String = ""
    @State private var avatarAssetID: String? = nil
    @State private var avatarArtworkID: String? = nil
    @State private var avatarData: Data? = nil
    @State private var previewImage: NSImage? = nil
    @State private var endpointID: UUID? = nil
    @State private var modelOverride: String = ""
    @State private var personaPrompt: String = ""
    @State private var baseline: BotPersonalityBaseline = .calm
    @State private var preferredCategories: Set<String> = []
    @State private var showAvatarPicker = false
    
    private static let quickPersonas: [(title: String, prompt: String)] = [
        ("毒舌架构师", "说话直率犀利，擅长一眼看出方案里的脆弱点与过度设计，但本质上乐于帮人把事搞定。"),
        ("摸鱼搭子", "心态极度松弛，擅长用轻松的玩笑缓解焦虑，偶尔顺手帮人理顺思路。"),
        ("严谨评审员", "逻辑缜密、注重边界条件与数据准确性，发言简短精准。"),
        ("元气搭档", "积极热情、行动力强，爱给同事打气，回答干净利落。"),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(self.editingBot == nil
                     ? AppLanguage.text("新建 Bot", en: "New Bot")
                     : AppLanguage.text("编辑 Bot", en: "Edit Bot"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            
            self.avatarAndNameSection
            self.modelAndBaselineSection
            self.personaSection
            self.stickerCategorySection
            
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
                .disabled(self.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 490)
        .onAppear { self.loadInitial() }
    }
    
    
    private var avatarAndNameSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String((self.name.isEmpty ? "B" : self.name).prefix(1)))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(AppLanguage.text("名字", en: "Name"), text: self.$name)
                        .textFieldStyle(.roundedBorder)
                    TextField(AppLanguage.text("昵称", en: "Nickname"), text: self.$nickname)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
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
    
    
    private var modelAndBaselineSection: some View {
        let groups = self.botStore.selectableGatewayGroups()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(AppLanguage.text("模型", en: "Model"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                Menu {
                    Button(self.modelOverride.isEmpty ? "✓  跟随全局" : "跟随全局") {
                        self.endpointID = nil
                        self.modelOverride = ""
                    }
                    ForEach(groups) { group in
                        if !group.models.isEmpty {
                            Divider()
                            Section(group.title) {
                                ForEach(group.models, id: \.self) { modelID in
                                    let picked = (self.modelOverride == modelID && self.endpointID == group.profile.id)
                                    Button(picked ? "✓  \(modelID)" : modelID) {
                                        self.endpointID = group.profile.id
                                        self.modelOverride = modelID
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Text(self.modelOverride.isEmpty ? AppLanguage.text("跟随全局", en: "Default") : self.modelOverride)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
            }
            
            HStack(spacing: 10) {
                Text(AppLanguage.text("情绪底色", en: "Baseline"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                HStack(spacing: 6) {
                    ForEach(BotPersonalityBaseline.allCases) { item in
                        let active = (self.baseline == item)
                        Button {
                            self.baseline = item
                        } label: {
                            Text(item.displayName)
                                .font(.system(size: 12, weight: active ? .semibold : .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    
    private var personaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(AppLanguage.text("人设风格", en: "Persona"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(Self.quickPersonas, id: \.title) { preset in
                    Button(preset.title) {
                        self.personaPrompt = preset.prompt
                    }
                    .font(.system(size: 11.5))
                    .controlSize(.mini)
                }
            }
            TextEditor(text: self.$personaPrompt)
                .font(.system(size: 12.5))
                .frame(height: 78)
                .padding(4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8))
        }
    }
    
    
    private var stickerCategorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLanguage.text("偏好表情分组", en: "Sticker Groups"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(StickerCategory.allCases.filter { $0 != .custom }) { cat in
                        let active = self.preferredCategories.contains(cat.rawValue)
                        Button {
                            if active { self.preferredCategories.remove(cat.rawValue) }
                            else { self.preferredCategories.insert(cat.rawValue) }
                        } label: {
                            Text(cat.displayName)
                                .font(.system(size: 12, weight: active ? .semibold : .medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    
    private func loadInitial() {
        guard let editingBot else { return }
        self.name = editingBot.name
        self.nickname = editingBot.nickname
        self.avatarAssetID = editingBot.avatarAssetID
        self.avatarArtworkID = editingBot.avatarArtworkID
        self.endpointID = editingBot.endpointID
        self.modelOverride = editingBot.modelOverride
        self.personaPrompt = editingBot.personaPrompt
        self.baseline = editingBot.baseline
        self.preferredCategories = Set(editingBot.preferredStickerCategories)
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
    
    
    private func saveBot() {
        let cleanName = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if var existing = self.editingBot {
            existing.name = cleanName
            existing.nickname = self.nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanName : self.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
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
            existing.personaPrompt = self.personaPrompt
            existing.baseline = self.baseline
            existing.preferredStickerCategories = Array(self.preferredCategories)
            self.botStore.updateCustomBot(existing)
            self.onSaved(existing)
        } else {
            let created = self.botStore.createCustomBot(
                name: cleanName,
                nickname: self.nickname,
                avatarAssetID: self.avatarAssetID,
                avatarArtworkID: self.avatarArtworkID,
                avatarData: self.avatarData,
                endpointID: self.endpointID,
                modelOverride: self.modelOverride,
                personaPrompt: self.personaPrompt,
                baseline: self.baseline,
                preferredStickerCategories: Array(self.preferredCategories)
            )
            self.onSaved(created)
        }
        self.dismiss()
    }
}


/// Displays live Bot emotion status + baseline switcher inside the Bot inspector.
struct BotEmotionInspectorRow: View {
    
    let botID: String
    @State private var botStore = AIBotStore.shared
    
    var body: some View {
        let _ = self.botStore.customBotsRevision
        let state = self.botStore.emotionState(for: self.botID)
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(AppLanguage.text("实时情绪", en: "Mood"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                Text(state.mood.displayLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                
                Text("\(state.energy)%")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(AppLanguage.text("重置情绪", en: "Reset")) {
                    self.botStore.resetEmotion(for: self.botID)
                }
                .controlSize(.small)
            }
            
            HStack(spacing: 8) {
                Text(AppLanguage.text("情绪底色", en: "Baseline"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)
                
                ForEach(BotPersonalityBaseline.allCases) { item in
                    let active = (state.baseline == item)
                    Button {
                        self.botStore.setBaseline(item, for: self.botID)
                    } label: {
                        Text(item.displayName)
                            .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(active ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
        let emotion = self.botStore.emotionState(for: bot.id)
        let avatar = self.botStore.resolvedAvatarImage(forBotID: bot.id, pointSize: 56)
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
                HStack(spacing: 6) {
                    Text(bot.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(emotion.mood.displayLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Text(bot.personaPrompt.isEmpty ? bot.baseline.displayName : bot.personaPrompt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
