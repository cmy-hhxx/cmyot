//
//  BotEmotionEngine.swift
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

/// Pure deterministic emotion state machine governing how Bot moods evolve across turns and decay at rest.
nonisolated enum BotEmotionEngine {
    
    private static let praiseKeywords = ["厉害", "不错", "棒", "谢", "好评", "稳", "牛", "赞", "nice", "good", "great", "爱了", "辛苦"]
    private static let complaintKeywords = ["又改", "重做", "错了", "卡死", "崩溃", "离谱", "无语", "烦", "不行", "bug", "报错", "返工", "垃圾"]
    private static let sadKeywords = ["忧伤", "伤心", "悲伤", "难过", "emo", "委屈", "心累", "叹气", "郁闷", "哭", "丧"]
    private static let tiredKeywords = ["好累", "困", "摸鱼", "下班", "不想干", "摆烂", "熬夜", "太晚"]
    private static let workKeywords = ["评测", "梳理", "进展", "周报", "整理", "分析", "代码", "数据", "总结", "方案"]
    
    
    static func defaultBaseline(for botID: AIBotID) -> BotPersonalityBaseline {
        switch botID {
            case .butler: .calm
            case .ghost: .chill
            case .translate, .summarize, .ocrPolish: .calm
            case .explain, .weeklyReport: .warm
            case .weeklyReportItem, .interactiveChart: .optimistic
            case .organizeAndMerge: .calm
            case .readingCompanion: .optimistic
            case .persona: .sharpTongued
        }
    }
    
    
    static func initialState(botID: String, baseline: BotPersonalityBaseline, now: Date = .now) -> BotEmotionState {
        BotEmotionState(
            botID: botID,
            mood: baseline.defaultMood,
            energy: baseline.defaultEnergy,
            baseline: baseline,
            updatedAt: now.timeIntervalSince1970,
            lastReason: "初始状态"
        )
    }
    
    
    /// Gradually drifts idle emotions back toward the Bot's baseline after 4+ hours of inactivity.
    static func decayed(_ state: BotEmotionState, now: Date = .now) -> BotEmotionState {
        let elapsedHours = (now.timeIntervalSince1970 - state.updatedAt) / 3600.0
        guard elapsedHours >= 4.0 else { return state }
        var next = state
        let targetEnergy = state.baseline.defaultEnergy
        let step = min(abs(targetEnergy - state.energy), Int(elapsedHours * 4))
        if state.energy < targetEnergy {
            next.energy += step
        } else if state.energy > targetEnergy {
            next.energy -= step
        }
        if elapsedHours >= 8.0 {
            next.mood = state.baseline.defaultMood
        }
        return next
    }
    
    
    /// Evolves a Bot's mood and energy after a conversation turn.
    static func evolve(
        _ current: BotEmotionState,
        userPrompt: String,
        botReply: String,
        explicitMoodTag: BotMood?,
        now: Date = .now
    ) -> BotEmotionState {
        var next = Self.decayed(current, now: now)
        let combined = "\(userPrompt) \(botReply)".lowercased()
        let hour = Calendar.current.component(.hour, from: now)
        
        if let explicitMoodTag {
            next.mood = explicitMoodTag
            next.energy = Self.adjustedEnergy(current: next.energy, for: explicitMoodTag)
            next.lastReason = "对话氛围触发"
        } else if Self.sadKeywords.contains(where: { combined.contains($0) }) {
            next.mood = (next.baseline == .warm || next.baseline == .optimistic) ? .aggrieved : .calm
            next.energy = max(28, next.energy - 6)
            next.lastReason = "感受到用户低落情绪"
        } else if Self.complaintKeywords.contains(where: { combined.contains($0) }) {
            next.mood = (next.baseline == .warm) ? .aggrieved : .speechless
            next.energy = max(18, next.energy - 10)
            next.lastReason = "遇到槽点或返工"
        } else if Self.praiseKeywords.contains(where: { combined.contains($0) }) {
            next.mood = (next.energy >= 82) ? .excited : .happy
            next.energy = min(98, next.energy + 10)
            next.lastReason = "收到正面反馈"
        } else if Self.tiredKeywords.contains(where: { combined.contains($0) }) || hour >= 23 || hour < 6 {
            next.mood = .slacking
            next.energy = max(25, next.energy - 8)
            next.lastReason = hour >= 23 || hour < 6 ? "深夜时段" : "摸鱼氛围"
        } else if Self.workKeywords.contains(where: { combined.contains($0) }) {
            next.mood = .focused
            next.energy = max(35, min(92, next.energy + 2))
            next.lastReason = "投入讨论正事"
        } else {
            next.mood = next.baseline.defaultMood
            next.lastReason = "日常互动"
        }
        
        next.updatedAt = now.timeIntervalSince1970
        return next
    }
    
    
    private static func adjustedEnergy(current: Int, for mood: BotMood) -> Int {
        switch mood {
            case .excited: min(98, max(78, current + 14))
            case .happy: min(94, max(66, current + 8))
            case .focused: min(88, max(55, current + 2))
            case .calm: 65
            case .slacking: max(22, min(55, current - 8))
            case .speechless: max(25, current - 6)
            case .aggrieved: max(20, current - 10)
        }
    }
}
