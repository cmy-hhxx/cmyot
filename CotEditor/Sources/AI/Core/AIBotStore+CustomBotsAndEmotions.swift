//
//  AIBotStore+CustomBotsAndEmotions.swift
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
import Foundation

extension AIBotStore {
    
    static let customBotsDidChangeNotification = Notification.Name("AIBotStoreCustomBotsDidChange")
    
    private static let customAccentPalette = [
        "#2F6BFF", "#10B981", "#F59E0B", "#EC4899", "#8B5CF6", "#0EA5E9", "#F97316", "#E11D48",
    ]
    
    
    func reloadCustomBotsAndEmotions() {
        let decoder = JSONDecoder()
        let botPayloads = self.database.fetchCustomBotPayloads()
        var loadedBots: [CustomBotProfile] = []
        for raw in botPayloads {
            if let data = raw.data(using: .utf8),
               let bot = try? decoder.decode(CustomBotProfile.self, from: data)
            {
                loadedBots.append(bot)
            }
        }
        self.customBots = loadedBots
        self.customBotAvatarCache.removeAll()
        
        let emoPayloads = self.database.fetchBotEmotionPayloads()
        var loadedEmotions: [String: BotEmotionState] = [:]
        for (botID, raw) in emoPayloads {
            if let data = raw.data(using: .utf8),
               let state = try? decoder.decode(BotEmotionState.self, from: data)
            {
                loadedEmotions[botID] = BotEmotionEngine.decayed(state)
            }
        }
        self.emotionStates = loadedEmotions
        self.customBotsRevision &+= 1
    }
    
    
    // MARK: - Custom Bots CRUD
    
    @discardableResult
    func createCustomBot(
        name: String,
        nickname: String = "",
        avatarAssetID: String? = nil,
        avatarArtworkID: String? = nil,
        avatarData: Data? = nil,
        endpointID: UUID? = nil,
        modelOverride: String = "",
        personaPrompt: String,
        baseline: BotPersonalityBaseline = .calm,
        preferredStickerCategories: [String] = []
    ) -> CustomBotProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = cleanName.isEmpty ? AppLanguage.text("新助手", en: "Custom Bot") : cleanName
        let cleanNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNick = cleanNick.isEmpty ? resolvedName : cleanNick
        let id = "custom_\(UUID().uuidString.prefix(8).lowercased())"
        let paletteIdx = abs(id.hashValue) % Self.customAccentPalette.count
        
        var avatarB64: String? = nil
        if let avatarData,
           let rawImage = NSImage(data: avatarData),
           let pngData = UserProfileManager.processedAvatarPNGData(from: rawImage)
        {
            avatarB64 = pngData.base64EncodedString()
        }
        
        let now = Date().timeIntervalSince1970
        let profile = CustomBotProfile(
            id: id,
            name: resolvedName,
            nickname: resolvedNick,
            avatarAssetID: avatarAssetID,
            avatarArtworkID: avatarArtworkID,
            avatarBase64: avatarB64,
            endpointID: endpointID,
            modelOverride: modelOverride.trimmingCharacters(in: .whitespacesAndNewlines),
            personaPrompt: personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            baseline: baseline,
            preferredStickerCategories: preferredStickerCategories,
            accentHex: Self.customAccentPalette[paletteIdx],
            isEnabled: true,
            createdAt: now
        )
        self.saveCustomBot(profile)
        let initialEmotion = BotEmotionEngine.initialState(botID: id, baseline: baseline)
        self.saveEmotionState(initialEmotion)
        return profile
    }
    
    
    func updateCustomBot(_ profile: CustomBotProfile) {
        self.saveCustomBot(profile)
        var emo = self.emotionState(for: profile.id)
        if emo.baseline != profile.baseline {
            emo.baseline = profile.baseline
            self.saveEmotionState(emo)
        }
    }
    
    
    func deleteCustomBot(id: String) {
        self.database.deleteCustomBot(id: id)
        self.customBots.removeAll { $0.id == id }
        self.customBotAvatarCache.removeValue(forKey: id)
        self.emotionStates.removeValue(forKey: id)
        self.customBotsRevision &+= 1
        NotificationCenter.default.post(name: Self.customBotsDidChangeNotification, object: self)
    }
    
    
    private func saveCustomBot(_ profile: CustomBotProfile) {
        let now = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(profile),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.upsertCustomBotPayload(
                id: profile.id,
                json: json,
                createdAt: profile.createdAt,
                updatedAt: now
            )
        }
        if let idx = self.customBots.firstIndex(where: { $0.id == profile.id }) {
            self.customBots[idx] = profile
        } else {
            self.customBots.append(profile)
        }
        self.customBotAvatarCache.removeValue(forKey: profile.id)
        self.customBotsRevision &+= 1
        NotificationCenter.default.post(name: Self.customBotsDidChangeNotification, object: self)
    }
    
    
    // MARK: - Emotion State Machine
    
    func emotionState(for botID: String) -> BotEmotionState {
        if let existing = self.emotionStates[botID] {
            return BotEmotionEngine.decayed(existing)
        }
        let baseline: BotPersonalityBaseline = if let builtIn = AIBotID(rawValue: botID) {
            BotEmotionEngine.defaultBaseline(for: builtIn)
        } else if let custom = self.customBots.first(where: { $0.id == botID }) {
            custom.baseline
        } else {
            .calm
        }
        return BotEmotionEngine.initialState(botID: botID, baseline: baseline)
    }
    
    
    func updateEmotion(
        for botID: String,
        userPrompt: String,
        botReply: String,
        explicitMood: BotMood?
    ) {
        let current = self.emotionState(for: botID)
        let next = BotEmotionEngine.evolve(
            current,
            userPrompt: userPrompt,
            botReply: botReply,
            explicitMoodTag: explicitMood
        )
        self.saveEmotionState(next)
    }
    
    
    func setBaseline(_ baseline: BotPersonalityBaseline, for botID: String) {
        var current = self.emotionState(for: botID)
        current.baseline = baseline
        current.mood = baseline.defaultMood
        current.energy = baseline.defaultEnergy
        current.updatedAt = Date().timeIntervalSince1970
        current.lastReason = "切换性格底色"
        self.saveEmotionState(current)
        if var custom = self.customBots.first(where: { $0.id == botID }) {
            custom.baseline = baseline
            self.saveCustomBot(custom)
        }
    }
    
    
    func resetEmotion(for botID: String) {
        let current = self.emotionState(for: botID)
        let fresh = BotEmotionEngine.initialState(botID: botID, baseline: current.baseline)
        self.saveEmotionState(fresh)
    }
    
    
    private func saveEmotionState(_ state: BotEmotionState) {
        self.emotionStates[state.botID] = state
        if let data = try? JSONEncoder().encode(state),
           let json = String(data: data, encoding: .utf8)
        {
            self.database.upsertBotEmotionPayload(botID: state.botID, json: json, updatedAt: state.updatedAt)
        }
        self.customBotsRevision &+= 1
    }
    
    
    // MARK: - Unified Bot Resolution (Built-In + Custom)
    
    func allUnifiedBots(includeDisabled: Bool = false) -> [UnifiedBotDescriptor] {
        var list: [UnifiedBotDescriptor] = []
        for builtIn in AIBotID.allCases {
            let cfg = self.config(for: builtIn)
            if !includeDisabled && !cfg.isEnabled && builtIn != .butler {
                continue
            }
            let name = self.resolvedName(for: builtIn)
            let nick = self.resolvedNickname(for: builtIn)
            let roleLabel = builtIn == .butler
                ? AppLanguage.text("总管统筹", en: "Chief")
                : builtIn.defaultNickname
            list.append(UnifiedBotDescriptor(
                id: builtIn.rawValue,
                isBuiltIn: true,
                builtInID: builtIn,
                customProfile: nil,
                name: name,
                nickname: nick,
                handle: builtIn.handle,
                roleLabel: roleLabel,
                accentHex: builtIn.accentHex,
                personaPrompt: cfg.customPersona,
                preferredStickerCategories: Self.defaultStickerCategories(for: builtIn),
                emotion: self.emotionState(for: builtIn.rawValue),
                isEnabled: builtIn == .butler ? true : cfg.isEnabled
            ))
        }
        for custom in self.customBots {
            if !includeDisabled && !custom.isEnabled { continue }
            list.append(UnifiedBotDescriptor(
                id: custom.id,
                isBuiltIn: false,
                builtInID: nil,
                customProfile: custom,
                name: custom.name,
                nickname: custom.nickname,
                handle: custom.handle,
                roleLabel: custom.baseline.displayName,
                accentHex: custom.accentHex,
                personaPrompt: custom.personaPrompt,
                preferredStickerCategories: custom.preferredStickerCategories,
                emotion: self.emotionState(for: custom.id),
                isEnabled: custom.isEnabled
            ))
        }
        return list
    }
    
    
    func unifiedBot(id: String) -> UnifiedBotDescriptor? {
        self.allUnifiedBots(includeDisabled: true).first { $0.id == id }
    }
    
    
    func resolvedConfiguration(forBotID id: String) -> AIConfiguration {
        if let builtIn = AIBotID(rawValue: id) {
            return self.resolvedConfiguration(for: builtIn)
        }
        guard let custom = self.customBots.first(where: { $0.id == id }) else {
            return self.resolvedConfiguration(for: .butler)
        }
        var resolved: AIConfiguration
        if let targetID = custom.endpointID,
           let matched = AIEndpointStore.profiles.first(where: { $0.id == targetID })
        {
            resolved = matched.configuration(apiKey: AIEndpointStore.apiKey(for: matched))
        } else {
            resolved = AIConfiguration.current
        }
        if !custom.modelOverride.isEmpty {
            resolved.model = custom.modelOverride
        }
        return resolved
    }
    
    
    func resolvedAvatarImage(forBotID id: String, pointSize: CGFloat = 96) -> NSImage? {
        if let builtIn = AIBotID(rawValue: id) {
            return self.resolvedAvatarImage(for: builtIn, pointSize: pointSize)
        }
        if let cached = self.customBotAvatarCache[id] {
            return cached
        }
        guard let custom = self.customBots.first(where: { $0.id == id }) else { return nil }
        if let assetID = custom.avatarAssetID,
           let asset = UserMediaLibraryStore.shared.avatars.first(where: { $0.id == assetID }),
           let thumb = UserMediaLibraryStore.shared.thumbnailImage(for: asset, maxPixelSize: pointSize * 2)
        {
            self.customBotAvatarCache[id] = thumb
            return thumb
        }
        if let artworkID = custom.avatarArtworkID {
            for char in AIGijinkaCharacter.allCharacters {
                if let art = char.artworks.first(where: { $0.id == artworkID }),
                   let sq = AIGijinkaImageLoader.shared.squareAvatar(for: art, pointSize: pointSize)
                {
                    self.customBotAvatarCache[id] = sq
                    return sq
                }
            }
        }
        if let b64 = custom.avatarBase64,
           !b64.isEmpty,
           let data = Data(base64Encoded: b64),
           let img = NSImage(data: data)
        {
            self.customBotAvatarCache[id] = img
            return img
        }
        return nil
    }
    
    
    private static func defaultStickerCategories(for botID: AIBotID) -> [String] {
        switch botID {
            case .butler: ["deepseek", "claude", "reaction"]
            case .ghost: ["cat", "reaction"]
            case .translate, .summarize, .explain: ["reaction", "claude"]
            case .weeklyReport, .weeklyReportItem: ["cat", "dog", "reaction"]
            case .persona, .readingCompanion: ["baoman", "cat", "dog"]
            default: ["reaction", "cat"]
        }
    }
}
