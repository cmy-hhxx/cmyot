//
//  CotCustomBot.swift
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

import Foundation

/// Personality baseline governing a Bot's resting mood and emotional drift.
nonisolated enum BotPersonalityBaseline: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case optimistic
    case calm
    case sharpTongued
    case warm
    case chill
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .optimistic: "乐观"
            case .calm: "冷静"
            case .sharpTongued: "毒舌"
            case .warm: "暖心"
            case .chill: "咸鱼"
        }
    }
    
    var defaultMood: BotMood {
        switch self {
            case .optimistic: .happy
            case .calm: .calm
            case .sharpTongued: .focused
            case .warm: .happy
            case .chill: .slacking
        }
    }
    
    var defaultEnergy: Int {
        switch self {
            case .optimistic: 78
            case .calm: 65
            case .sharpTongued: 72
            case .warm: 75
            case .chill: 48
        }
    }
    
    var promptDirective: String {
        switch self {
            case .optimistic: "性格底色偏乐观明快，爱发现进展里值得开心的点。"
            case .calm: "性格底色冷静克制，说话不慌不忙、言简意赅。"
            case .sharpTongued: "性格底色带点机灵毒舌与冷吐槽，嘴硬心软，直指痛点。"
            case .warm: "性格底色温柔体贴，关心搭档的状态与感受。"
            case .chill: "性格底色松弛咸鱼，不内耗不卷，爱插科打诨。"
        }
    }
}


/// 7-state live emotion model for every Bot.
nonisolated enum BotMood: String, CaseIterable, Codable, Identifiable, Sendable {
    
    case calm
    case happy
    case excited
    case focused
    case slacking
    case speechless
    case aggrieved
    
    var id: String { self.rawValue }
    
    var displayLabel: String {
        switch self {
            case .calm: "平静"
            case .happy: "开心"
            case .excited: "兴奋"
            case .focused: "专注"
            case .slacking: "摸鱼"
            case .speechless: "无语"
            case .aggrieved: "委屈"
        }
    }
    
    var englishLabel: String {
        switch self {
            case .calm: "Calm"
            case .happy: "Happy"
            case .excited: "Excited"
            case .focused: "Focused"
            case .slacking: "Chill"
            case .speechless: "Deadpan"
            case .aggrieved: "Sulking"
        }
    }
    
    var toneDirective: String {
        switch self {
            case .calm: "当前心境平静自然，正常搭话即可。"
            case .happy: "当前心情不错、带点笑意，语气轻快。"
            case .excited: "当前兴致很高、干劲满满，可以带一点雀跃感。"
            case .focused: "当前进入专注状态，说话利落直接、切中要点。"
            case .slacking: "当前有点犯懒想摸鱼，语气松弛随性。"
            case .speechless: "当前略显无奈，语气偏淡定克制，不强行吐槽。"
            case .aggrieved: "当前有点小低落，语气轻一点，正常沟通即可。"
        }
    }
    
    static func fromModelTag(_ raw: String) -> BotMood? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = Self(rawValue: lower) { return exact }
        switch lower {
            case "平静", "淡定": return .calm
            case "开心", "高兴", "愉快": return .happy
            case "兴奋", "激动", "冲": return .excited
            case "专注", "认真": return .focused
            case "摸鱼", "摆烂", "困", "chill": return .slacking
            case "无语", "无奈", "deadpan": return .speechless
            case "委屈", "难过", "sulking": return .aggrieved
            default: return nil
        }
    }
}


/// Persisted emotional state for one Bot (built-in or custom).
nonisolated struct BotEmotionState: Codable, Equatable, Sendable {
    var botID: String
    var mood: BotMood
    var energy: Int
    var baseline: BotPersonalityBaseline
    var updatedAt: Double
    var lastReason: String
}


/// User-created freeform persona Bot that participates in Meeting Room & `@mention` chats.
nonisolated struct CustomBotProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var nickname: String
    var avatarAssetID: String?
    var avatarArtworkID: String?
    var avatarBase64: String?
    var endpointID: UUID?
    var modelOverride: String
    var personaPrompt: String
    var baseline: BotPersonalityBaseline
    var preferredStickerCategories: [String]
    var accentHex: String
    var isEnabled: Bool
    var createdAt: Double
    
    var handle: String {
        let clean = self.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return "@\(clean.isEmpty ? self.name : clean)"
    }
}


/// Unified descriptor bridging both built-in `AIBotID` bots and user-created `CustomBotProfile` bots.
nonisolated struct UnifiedBotDescriptor: Identifiable, Equatable, Sendable {
    var id: String
    var isBuiltIn: Bool
    var builtInID: AIBotID?
    var customProfile: CustomBotProfile?
    var name: String
    var nickname: String
    var handle: String
    var roleLabel: String
    var accentHex: String
    var personaPrompt: String
    var preferredStickerCategories: [String]
    var emotion: BotEmotionState
    var isEnabled: Bool
}
