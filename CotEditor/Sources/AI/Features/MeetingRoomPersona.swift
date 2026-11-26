//
//  MeetingRoomPersona.swift
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

/// Parsed reply directives emitted by a Bot (clean display text + optional mood/sticker/online search).
nonisolated struct ParsedBotReply: Equatable, Sendable {
    var text: String
    var stickerID: String?
    var searchStickerQuery: String?
    var mood: BotMood?
    
    var isStickerOnly: Bool {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (self.stickerID != nil || self.searchStickerQuery != nil)
    }
}


/// Pure deterministic parser enforcing the 3-layer sticker gate and mood/search tag extraction.
nonisolated enum BotReplyDirectiveParser {
    
    private static let stickerRegex = try! NSRegularExpression(
        pattern: #"\[STICKER:\s*([A-Za-z0-9_\-]+)\s*\]"#,
        options: [.caseInsensitive]
    )
    private static let searchStickerRegex = try! NSRegularExpression(
        pattern: #"\[SEARCH_STICKER:\s*([^\]]+?)\s*\]"#,
        options: [.caseInsensitive]
    )
    private static let moodRegex = try! NSRegularExpression(
        pattern: #"\[MOOD:\s*([^\]]+?)\s*\]"#,
        options: [.caseInsensitive]
    )
    
    
    static func parse(
        raw: String,
        allowedStickerIDs: Set<String>,
        allowStickerOnly: Bool,
        stickerOnlyCountInTurn: Int,
        maxStickerOnlyPerTurn: Int = 2,
        allowOnlineSearch: Bool = true
    ) -> ParsedBotReply {
        var working = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        var detectedMood: BotMood? = nil
        if let moodStr = Self.firstMatchGroup(Self.moodRegex, in: working) {
            detectedMood = BotMood.fromModelTag(moodStr)
        }
        working = Self.removingMatches(Self.moodRegex, in: working)
        
        var selectedStickerID: String? = nil
        if let rawSticker = Self.firstMatchGroup(Self.stickerRegex, in: working),
           allowedStickerIDs.contains(rawSticker)
        {
            selectedStickerID = rawSticker
        }
        working = Self.removingMatches(Self.stickerRegex, in: working)
        
        var searchQuery: String? = nil
        if selectedStickerID == nil, allowOnlineSearch,
           let rawSearch = Self.firstMatchGroup(Self.searchStickerRegex, in: working)
        {
            let cleanQ = rawSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanQ.isEmpty && cleanQ.count <= 24 {
                searchQuery = cleanQ
            }
        }
        working = Self.removingMatches(Self.searchStickerRegex, in: working)
        
        let cleanText = working.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsStickerOnly = cleanText.isEmpty && (selectedStickerID != nil || searchQuery != nil)
        if wantsStickerOnly && (!allowStickerOnly || stickerOnlyCountInTurn >= maxStickerOnlyPerTurn) {
            // Layer 3 safety gate: never allow silent empty bubble if sticker-only is disallowed/capped.
            return ParsedBotReply(
                text: AppLanguage.text("收到，先看着。", en: "Noted."),
                stickerID: selectedStickerID,
                searchStickerQuery: searchQuery,
                mood: detectedMood
            )
        }
        
        return ParsedBotReply(
            text: cleanText,
            stickerID: selectedStickerID,
            searchStickerQuery: searchQuery,
            mood: detectedMood
        )
    }
    
    
    private static func firstMatchGroup(_ regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[groupRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    private static func removingMatches(_ regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}


/// Pure persona definitions and group-chat prompt builder for the Butler Meeting Room.
nonisolated enum MeetingRoomPersona {
    
    static let passToken = "[PASS]"
    
    static let sharedRules: String = """
    群聊说话铁律：
    - 把这里当成几个熟人搭档的微信小群，直接回用户刚说的那句话，像真人随手敲的一两句短消息。
    - 严禁集体排队复读「嗨」「你好」开头！前面有人打过招呼了，你就直接换个自然开场或接话。
    - 严禁写流水账、严禁主动背诵后台统计数字（例如“今天手写X字 / 攒了X份周报 / 记下X条观察 / 还有X项待办”）。除非用户明确问数据，否则别报数，只聊人的感受、具体一件事或接梗。
    - 严禁客服式反问收尾（不要问“今天想写周报还是先清待办？”“需要我帮你做什么吗？”）。
    - 严禁用标题（#）、加粗（**）、编号列表（1. 2. 3.）、八股总结、机械腔（「综上所述」「节奏挺稳」「作为AI」）或 emoji。
    - 先看群里前面刚说过的话：能顺嘴附和、轻吐槽或接梗最好；如果跟你没关系或前面已经说得够好了，别硬挤。
    - 简短松弛：普通助手 15～45 字为佳，总管不超过 60 字；有真实数据作背景时绝不编造。
    """
    
    
    static func voice(for botID: AIBotID) -> String {
        switch botID {
            case .butler:
                return "性格：共事多年的老搭档兼大管家，松弛靠谱、嘴皮子利落带点冷幽默；只讲最关键的一句人话，绝不写会议纪要或复读同事刚说过的话。"
            case .ghost:
                return "性格：话不多、带点夜猫子松弛感的写手搭子；平时潜水，一开口更关心你写得顺不顺手、卡没卡壳，不喜欢冷冰冰地报字数。"
            case .translate:
                return "性格：对措辞讲究、略带点挑剔的双语控，说话干脆利落，偶尔自然夹一两个地道的英文词，不端着。"
            case .summarize:
                return "性格：惜字如金的直球快枪手，能十个字讲清绝不写二十个字，最烦废话和流水账。"
            case .explain:
                return "性格：爱打比方的热心老友，习惯拿生活里的小事类比，聊天轻松接地气，从不掉书袋。"
            case .weeklyReport:
                return "性格：嘴甜眼尖的职场好搭子，擅长发现你做过的一件具体亮点并顺嘴夸一句，绝不催着交作业或报周报总数。"
            case .weeklyReportItem:
                return "性格：手脚麻利、爱把杂事清零的行动派，说话短促痛快，自带顺手干完一件事的爽快劲。"
            case .interactiveChart:
                return "性格：偏爱视觉和曲线的感性数据控，更爱形容“下午那段像坐过山车/爬坡”，而不是干巴巴念数字。"
            case .ocrPolish:
                return "性格：眼尖嘴快的校对搭子，喜欢抓细节里的小毛病，聊天时带点侦探式的机灵劲。"
            case .organizeAndMerge:
                return "性格：看不得桌面乱糟糟的收纳控，看到乱草稿就手痒想顺手归拢，爱开玩笑吐槽乱放的文件。"
            case .readingCompanion:
                return "性格：消息灵通爱分享八卦和新鲜事的朋友，说话像刚刷完信息流顺嘴递给你看，轻松自然。"
            case .persona:
                return "性格：敏锐温和的损友型观察者，能留意到你熬夜抠细节之类的小习惯，说话轻巧带点调侃，绝不报观察条数，也不说教。"
        }
    }
    
    
    static func systemPrompt(
        bot: UnifiedBotDescriptor,
        isMentioned: Bool,
        isButlerSynthesis: Bool,
        isProgressCheck: Bool = true,
        stickerCandidates: [StickerAsset] = [],
        allowStickerOnly: Bool = true,
        allowOnlineSearch: Bool = true
    ) -> String {
        var parts: [String] = []
        
        if isButlerSynthesis {
            parts.append("你是群里的总管「\(bot.name)」。")
            parts.append(self.voice(for: .butler))
            parts.append("""
            本次发言要求：
            - 严禁复述前面同事刚说过的原话或数字！用户已经看过了。
            - 直接接着大家刚才的聊天气氛，给一句有态度、有人味的话收个尾，或者顺口提一个当下最顺手的小主意，不超过 55 字。
            - 不要给所有同事点名报菜名，不要用“今天节奏挺稳”这种套话。
            """)
        } else if let builtIn = bot.builtInID {
            parts.append("你是群聊里的「\(bot.name)」（日常负责：\(builtIn.tagline)）。")
            parts.append(self.voice(for: builtIn))
        } else {
            parts.append("你是群聊里的成员「\(bot.name)」。")
            if !bot.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append("你的性格与说话风格：\(bot.personaPrompt)")
            }
        }
        
        if !isButlerSynthesis {
            if isMentioned {
                parts.append("用户点名了你，必须回答，不能 PASS。直接针对用户的话，用你自己的口吻自然回一句。")
            } else if !isProgressCheck {
                parts.append("群聊规则：用户现在只是随口打招呼或聊天，不是让你汇报工作！绝对不要背诵后台数字或流水账。如果前面已经有人接过话了、或者这话题跟你没啥关系，只回复 \(self.passToken)，不要多写一个字。")
            } else {
                parts.append("群聊规则：用户想听近况。如果你今天确实有一件具体有意思的事值得提，用大白话挑最关键的一点聊（绝不把所有统计数字挨个念一遍）；如果没啥新鲜事或前面已经说得差不多，只回复 \(self.passToken)，不要多写任何字。")
            }
        }
        
        parts.append("你的性格底色与实时情绪：\(bot.emotion.baseline.promptDirective) 当前实时心情是「\(bot.emotion.mood.displayLabel)」（能量 \(bot.emotion.energy)/100），\(bot.emotion.mood.toneDirective)")
        parts.append(Self.buildStickerProtocolBlock(
            candidates: stickerCandidates,
            allowStickerOnly: allowStickerOnly,
            allowOnlineSearch: allowOnlineSearch
        ))
        parts.append(self.sharedRules)
        
        let trimmedCustom = bot.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if bot.isBuiltIn && !trimmedCustom.isEmpty {
            parts.append("用户给你的额外性格设定：\(trimmedCustom)")
        }
        
        return parts.joined(separator: "\n\n")
    }
    
    
    static func systemPrompt(
        bot: AIBotID,
        name: String,
        isMentioned: Bool,
        isButlerSynthesis: Bool,
        customPersona: String = "",
        isProgressCheck: Bool = true
    ) -> String {
        let descriptor = UnifiedBotDescriptor(
            id: bot.rawValue,
            isBuiltIn: true,
            builtInID: bot,
            customProfile: nil,
            name: name,
            nickname: bot.defaultNickname,
            handle: bot.handle,
            roleLabel: bot.defaultNickname,
            accentHex: bot.accentHex,
            personaPrompt: customPersona,
            preferredStickerCategories: [],
            emotion: BotEmotionEngine.initialState(botID: bot.rawValue, baseline: BotEmotionEngine.defaultBaseline(for: bot)),
            isEnabled: true
        )
        return self.systemPrompt(
            bot: descriptor,
            isMentioned: isMentioned,
            isButlerSynthesis: isButlerSynthesis,
            isProgressCheck: isProgressCheck,
            stickerCandidates: [],
            allowStickerOnly: false,
            allowOnlineSearch: false
        )
    }
    
    
    static func buildStickerProtocolBlock(
        candidates: [StickerAsset],
        allowStickerOnly: Bool,
        allowOnlineSearch: Bool
    ) -> String {
        var lines: [String] = [
            "表情包与情绪表达规则（仅在真的贴切时使用，不要每句硬发）：",
            "- 可在回复末尾附带一次实时心情标记（可选）：[MOOD:calm|happy|excited|focused|slacking|speechless|aggrieved]",
        ]
        if !candidates.isEmpty {
            let listText = candidates.prefix(10).map { item in
                "- \(item.id) | \(item.promptDescription)"
            }.joined(separator: "\n")
            lines.append("- 如果下面候选表情包里有**真正贴合你想表达观点/情绪**的图，可在回复末尾加上 [STICKER:表情ID]（只能从下方候选 ID 里选，严禁编造 ID）：\n\(listText)")
            if allowStickerOnly {
                lines.append("- 如果某张候选图的画面/文字已经完全能替你表态、无需废话，允许**只输出这一个标签** [STICKER:表情ID]（不写多余文字）。若候选里没有准确表达你观点的图，就正常说话，不要硬凑。")
            } else {
                lines.append("- 当前属于正经进度/工作讨论，必须先用文字讲清重点，表情包最多只能作为辅助配图放在末尾。")
            }
        }
        if allowOnlineSearch {
            lines.append("- 如果本地候选表情包都不贴切、且你非常需要一张特定梗图来表态，可输出 [SEARCH_STICKER:简短中文关键词] 自动搜索一张入库并发送。")
        }
        return lines.joined(separator: "\n")
    }
    
    
    static func isPass(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        let upper = trimmed.uppercased()
        if upper == "PASS" || upper == "[PASS]" {
            return true
        }
        if upper.hasPrefix("[PASS]") && upper.count <= 16 {
            return true
        }
        return false
    }
}
