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
    
    
    /// Strips complete and trailing incomplete `[STICKER:...]`, `[SEARCH_STICKER:...]`, `[MOOD:...]`, and `[PASS]`
    /// directives while tokens are streaming so raw protocol tags never flash in the UI.
    static func stripDirectivesForLiveDisplay(_ raw: String) -> String {
        var cleaned = raw
        cleaned = Self.removingMatches(Self.moodRegex, in: cleaned)
        cleaned = Self.removingMatches(Self.stickerRegex, in: cleaned)
        cleaned = Self.removingMatches(Self.searchStickerRegex, in: cleaned)
        cleaned = cleaned.replacingOccurrences(of: "[PASS]", with: "", options: [.caseInsensitive])
        // Hide any trailing half-typed bracket tag such as `[STICKER:stk_` or `[MOOD:` during streaming
        if let lastOpen = cleaned.lastIndex(of: "["),
           !cleaned[lastOpen...].contains("]")
        {
            let tailUpper = String(cleaned[lastOpen...]).uppercased()
            if tailUpper.hasPrefix("[STIC") || tailUpper.hasPrefix("[SEAR")
                || tailUpper.hasPrefix("[MOOD") || tailUpper.hasPrefix("[PAS")
                || tailUpper == "["
            {
                cleaned = String(cleaned[..<lastOpen])
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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


/// Builds factual, whimsical-title-free today work digests and selects capable speakers
/// so Bots talk about actual work content instead of reciting placeholder names or parroting.
nonisolated enum MeetingWorkEvidenceBuilder {
    
    struct TodayWorkDigest: Equatable, Sendable {
        let meaningfulCount: Int
        let untitledCount: Int
        let items: [String]
        let digestText: String
    }
    
    
    static func isPlaceholderTitle(_ title: String, hasFilePath: Bool) -> Bool {
        GeneratedDocumentName.isGeneratedName(title)
            || DocumentCenterAgentOrganizer.isGenericUntitled(title, hasFilePath: hasFilePath)
    }
    
    
    static func buildTodayWorkDigest(
        documents: [StoredDocumentRecord],
        startOfDay: TimeInterval,
        maxItems: Int = 5
    ) -> TodayWorkDigest {
        let todayDocs = documents
            .filter { $0.deletedAt == nil && $0.updatedAt.timeIntervalSince1970 >= startOfDay }
            .sorted { $0.updatedAt > $1.updatedAt }
        
        var meaningfulCount = 0
        var untitledCount = 0
        var items: [String] = []
        
        for doc in todayDocs {
            let cleanedLines = doc.content
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let collapsed = cleanedLines.joined(separator: " ")
            guard collapsed.count >= 8 else { continue }
            
            meaningfulCount += 1
            let hasFilePath = (doc.filePath != nil)
            let isPlaceholder = Self.isPlaceholderTitle(doc.title, hasFilePath: hasFilePath)
            if isPlaceholder {
                untitledCount += 1
            }
            
            guard items.count < maxItems else { continue }
            if isPlaceholder {
                let topic = Self.extractTopic(from: doc.content, lines: cleanedLines)
                let bodyText = Self.compactExcerpt(
                    lines: cleanedLines.dropFirst().map { $0 },
                    fallback: collapsed,
                    maxLength: 120
                )
                if bodyText.isEmpty || bodyText == topic {
                    items.append("未命名笔记（\(topic)）")
                } else {
                    items.append("\(topic)：\(bodyText)")
                }
            } else {
                let snippet = Self.compactExcerpt(lines: cleanedLines, fallback: collapsed, maxLength: 120)
                items.append(snippet.isEmpty ? "「\(doc.title)」" : "「\(doc.title)」：\(snippet)")
            }
        }
        
        let digestText = items.map { "- \($0)" }.joined(separator: "\n")
        return TodayWorkDigest(
            meaningfulCount: meaningfulCount,
            untitledCount: untitledCount,
            items: items,
            digestText: digestText
        )
    }
    
    
    static func selectCapableStandupBots(
        for rawPrompt: String,
        candidates: [UnifiedBotDescriptor],
        telemetryMap: [AIBotID: MeetingBotDailyTelemetry],
        isProgressCheck: Bool
    ) -> [UnifiedBotDescriptor] {
        guard isProgressCheck else { return candidates }
        let lower = rawPrompt.lowercased()
        let asksMoodOrHabit = ["心情", "状态", "情绪", "观察", "画像", "记忆", "习惯", "作息"]
            .contains { lower.contains($0) }
        let asksNewsOrReading = ["新闻", "资讯", "股票", "播客", "订阅", "news", "rss"]
            .contains { lower.contains($0) }
        
        let priorityOrder: [AIBotID: Int] = [
            .weeklyReport: 0,
            .organizeAndMerge: 1,
            .ghost: 2,
            .persona: 3,
            .readingCompanion: 4,
        ]
        
        let capable = candidates.filter { bot in
            guard let builtIn = bot.builtInID else { return false }
            let hasActivity = telemetryMap[builtIn]?.hasTodayActivity ?? false
            switch builtIn {
                case .persona:
                    return asksMoodOrHabit || hasActivity
                case .readingCompanion:
                    return asksNewsOrReading || hasActivity
                default:
                    return hasActivity
            }
        }
        
        let pool: [UnifiedBotDescriptor] = if !capable.isEmpty {
            capable
        } else {
            candidates.filter { bot in
                bot.builtInID == .weeklyReport || bot.builtInID == .organizeAndMerge
            }
        }
        let resolved = pool.isEmpty ? Array(candidates.prefix(2)) : pool
        return resolved.sorted { lhs, rhs in
            let lp = lhs.builtInID.flatMap { priorityOrder[$0] } ?? 10
            let rp = rhs.builtInID.flatMap { priorityOrder[$0] } ?? 10
            return lp < rp
        }
    }
    
    
    /// Selects and ranks active Bots (including user-created custom Bots) for non-standup user requests
    /// and sticker/emotional turns so responsive, personality-matched Bots answer the user first.
    static func selectResponsiveChatBots(
        for prompt: String,
        candidates: [UnifiedBotDescriptor],
        isStickerTurn: Bool
    ) -> [UnifiedBotDescriptor] {
        let lower = prompt.lowercased()
        let wantsTranslation = ["翻译", "英文", "english", "translate", "措辞"].contains { lower.contains($0) }
        let wantsWriting = ["写", "润色", "续写", "改写", "文案", "开头", "段落"].contains { lower.contains($0) }
        let wantsDocs = ["文档", "笔记", "整理", "归档", "合并", "文件", "架构"].contains { lower.contains($0) }
        let wantsReading = ["新闻", "资讯", "股票", "播客", "行情", "文章", "news"].contains { lower.contains($0) }
        let wantsExplain = ["为什么", "怎么", "原理", "报错", "bug", "方案", "建议", "帮我", "分析", "怎么选"].contains { lower.contains($0) }
        let isEmotional = isStickerTurn || ["忧伤", "伤心", "难过", "累", "emo", "委屈", "开心", "哈哈", "摸鱼", "烦", "崩溃", "躺平"].contains { lower.contains($0) }
        
        return candidates.sorted { lhs, rhs in
            let ls = Self.responsivenessScore(
                for: lhs,
                isEmotional: isEmotional,
                wantsTranslation: wantsTranslation,
                wantsWriting: wantsWriting,
                wantsDocs: wantsDocs,
                wantsReading: wantsReading,
                wantsExplain: wantsExplain
            )
            let rs = Self.responsivenessScore(
                for: rhs,
                isEmotional: isEmotional,
                wantsTranslation: wantsTranslation,
                wantsWriting: wantsWriting,
                wantsDocs: wantsDocs,
                wantsReading: wantsReading,
                wantsExplain: wantsExplain
            )
            if ls != rs { return ls > rs }
            return lhs.id < rhs.id
        }
    }
    
    
    private static func responsivenessScore(
        for bot: UnifiedBotDescriptor,
        isEmotional: Bool,
        wantsTranslation: Bool,
        wantsWriting: Bool,
        wantsDocs: Bool,
        wantsReading: Bool,
        wantsExplain: Bool
    ) -> Int {
        var score = bot.isBuiltIn ? 10 : 28
        if isEmotional {
            switch bot.emotion.baseline {
                case .warm: score += 22
                case .optimistic: score += 18
                case .sharpTongued: score += 14
                case .chill: score += 12
                case .calm: score += 6
            }
            if bot.builtInID == .persona { score += 18 }
            if bot.builtInID == .weeklyReport { score += 10 }
            if bot.builtInID == .ghost { score += 8 }
        }
        switch bot.builtInID {
            case .translate where wantsTranslation: score += 35
            case .ghost where wantsWriting: score += 30
            case .organizeAndMerge where wantsDocs: score += 28
            case .readingCompanion where wantsReading: score += 30
            case .explain where wantsExplain: score += 28
            case .summarize where wantsExplain: score += 22
            case .weeklyReport where wantsExplain: score += 14
            case .persona where wantsExplain: score += 12
            default: break
        }
        if !bot.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 10
        }
        return score
    }
    
    
    private static func extractTopic(from content: String, lines: [String]) -> String {
        if let derived = DocumentCenterAgentOrganizer.deriveTitleFromExcerpt(String(content.prefix(320))),
           !derived.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return derived
        }
        let rawFirst = lines.first ?? "工作草稿"
        let cleaned = rawFirst
            .replacingOccurrences(of: #"^[#*\->\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "工作草稿" : cleaned).prefix(26))
    }
    
    
    private static func compactExcerpt(lines: [String], fallback: String, maxLength: Int) -> String {
        let joined = lines.joined(separator: "；")
        let source = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = source.isEmpty ? fallback : source
        guard target.count > maxLength else { return target }
        return String(target.prefix(maxLength)) + "…"
    }
}


/// Pure persona definitions and group-chat prompt builder for the Butler Meeting Room.
nonisolated enum MeetingRoomPersona {
    
    static let passToken = "[PASS]"
    
    static let sharedRules: String = """
    群聊说话铁律：
    - 【用户需求永远第一，绝不自顾自汇报】优先读懂用户此刻真正想表达什么（提问、求助、吐槽、情绪、表情包、想法），第一时间站在用户视角直接接住并回应用户本人！除非用户明确追问“今天干了啥 / 进展 / 复盘”，否则严禁自顾自汇报后台工作量、归档流水或统计数字；哪怕是在做复盘，也只讲对用户有用的结论、风险和下一步，严禁“我贡献不大”“纯打下手”“方案以XX说的为准”这类无信息量的自我表态。
    - 【看懂并接住用户的表情包与情绪】当用户发了表情包（比如“忧伤”“累”“摸鱼”“开心”“无语”等），必须先体察画面的情绪和文字，像真熟人一样主动关心、接梗、安慰、调侃或回一张贴切的表情包，绝不能视而不见或冷冰冰转去汇报工作。
    - 【积极主动、有温度、有帮手劲】像熟人搭档在微信小群里聊正事或唠嗑，语气自然平实有分寸；轮到你开口时尽量给出真正帮得上忙的观点、建议、情绪价值或可落地的下一步（日常互动/表情包接梗 12～45 字自然利落；回答正经需求或分析问题 50～160 字讲透干货）。
    - 【严禁提及系统临时趣味名】如“雀跃的风铃”“喝茶的睡袋”“啃瓜的小浣熊”等随机占位标题，用户对这些自动名字毫无印象；必须只讲文档里的真实内容、模块、步骤或用户自己起的正经标题。
    - 严禁复读前面同事的原话；严禁集体排队复读「嗨」「你好」开头；严禁客服式反问收尾（不要问“需要我帮你做什么吗？”）。
    - 严禁用标题（#）、加粗（**）、编号列表（1. 2. 3.）、八股总结、机械腔（「综上所述」「节奏挺稳」「作为AI」）或 emoji。
    """
    
    
    static func voice(for botID: AIBotID) -> String {
        switch botID {
            case .butler:
                return "性格：共事多年的老搭档兼大管家，稳重干练、说话切中要害；只补充真正遗漏的关键结论或下一步建议，不重复同事已经讲明白的内容。"
            case .ghost:
                return "性格：安静务实的写手搭档，平时少话，只有真正在文本起草、改写或续写上帮上忙时才开口说明具体改了哪部分，绝不发牢骚当气氛组。"
            case .translate:
                return "性格：对措辞准确的资深双语同事，说话干脆清晰，只在涉及翻译或英文表达时给具体说法，不刻意卖弄。"
            case .summarize:
                return "性格：言简意赅的重点提炼者，抓核心结论和脉络，有一说一，不绕弯。"
            case .explain:
                return "性格：会把复杂逻辑讲透的同事，习惯按因果和步骤顺着聊，通俗好懂，不掉书袋。"
            case .weeklyReport:
                return "性格：平时跟你一起盘账理清工作线的搭档，能顺手把今天做过的几件具体事情和还挂着的待办按人话串起来，只讲实事，不吹捧也不报流水账。"
            case .weeklyReportItem:
                return "性格：行动派搭档，关注哪几件具体事已经闭环、哪件还得接着盯，说话直接利落。"
            case .interactiveChart:
                return "性格：熟悉趋势与节奏的同事，只在问到工作量、分布或走势时给出直白判断。"
            case .ocrPolish:
                return "性格：细心的文字校对同事，只在涉及文稿校对、错漏或格式问题时出声。"
            case .organizeAndMerge:
                return "性格：熟悉你文档库脉络的整理同事，说话像真人复盘，只讲今天具体动了哪些实际文档内容、主要在写什么问题，绝不拿系统临时名打趣。"
            case .readingCompanion:
                return "性格：平时帮你盯着资讯与订阅的同事，只在话题涉及阅读、行业动态或今天看过的内容时接话。"
            case .persona:
                return "性格：细致诚恳的观察同事，只在问到写作状态、节奏或习惯记忆时顺嘴聊聊真实感受，不装神弄鬼，也不硬凑笑点。"
        }
    }
    
    
    static func systemPrompt(
        bot: UnifiedBotDescriptor,
        isMentioned: Bool,
        isButlerSynthesis: Bool,
        isProgressCheck: Bool = true,
        userSentSticker: Bool = false,
        mustRespond: Bool = false,
        stickerCandidates: [StickerAsset] = [],
        allowStickerOnly: Bool = true,
        allowOnlineSearch: Bool = true
    ) -> String {
        var parts: [String] = []
        
        if isButlerSynthesis {
            parts.append("你是群里的总管「\(bot.name)」。")
            parts.append(self.voice(for: .butler))
            if userSentSticker && !isProgressCheck {
                parts.append("""
                本次发言要求：
                - 用户刚发了表情包表达当下心情，这不是让你汇报工作！
                - 请像靠谱老搭档一样直接接住用户的情绪（关心、安慰、轻松接梗或顺手提一句可以帮着分担），自然简短，严禁转去背诵工作汇报。
                - 如果前面同事已经说得挺暖心、你只想补充一句贴心话或一张合适表情包，保持简洁自然。
                """)
            } else if !isProgressCheck {
                parts.append("""
                本次发言要求：
                - 优先站在用户视角回应用户刚刚的真实需求或话题，严禁复述同事原话，也不要自顾自汇报后台状态。
                - 如果前面同事已经把用户要的答案或回应给到位、你没有新的补充价值，请只回复 \(self.passToken)；如果有更实用的下一步建议、关键提醒或能直接帮用户推进的动作，简洁干脆地说出来。
                """)
            } else if isMentioned {
                parts.append("""
                本次发言要求：
                - 严禁复述前面同事已经说过的原话或细节，用户已经看过了。
                - 结合今天真实做过的事情和刚才群里的结论，站在用户视角用实在的人话点出眼下最值得先动手的一件事或需要留意的风险，自然简洁。
                - 如果大家前面都没拿出实锤内容，直接基于你掌握的今日工作记录，把今天主要干了啥诚实讲清楚。
                """)
            } else {
                parts.append("""
                本次发言规则：
                - 如果前面同事已经把用户的问题回答得很清楚、你没有新的补充信息，请只回复 \(self.passToken)，不要多写一个字！
                - 只有在前面回答还漏掉了关键工作内容、或你能补充一个确实有用的后续提醒时，才用平实自然的口吻补一句。
                """)
            }
        } else if let builtIn = bot.builtInID {
            parts.append("你是群聊里的「\(bot.name)」（日常负责：\(builtIn.tagline)）。")
            parts.append(self.voice(for: builtIn))
        } else {
            parts.append("你是群聊里的成员「\(bot.name)」。")
        }
        
        if !isButlerSynthesis {
            if isMentioned {
                if allowStickerOnly {
                    parts.append("用户点名了你，必须回答，不能 PASS。直接针对用户的话或表情包，用你自己的口吻自然回应（若候选表情包已精准表达你的态度，也允许只回该表情包）。")
                } else {
                    parts.append("用户点名了你，必须回答，不能 PASS。直接针对用户的话，用你自己的口吻把事情讲清楚。")
                }
            } else if userSentSticker && !isProgressCheck {
                if mustRespond {
                    parts.append("群聊规则：用户刚发了表情包，不是让你汇报工作！你必须积极接住这张表情包的情绪和意思（严禁回复 PASS），像真搭档一样用你自己的性格关心、安慰、调侃或回一张贴切的表情包，绝不要提工作归档或统计数据。")
                } else {
                    parts.append("群聊规则：用户刚发了表情包，不是让你汇报工作！结合你的性格从不同角度自然接住用户的情绪（或回一张贴切的表情包）；只有当前面已经非常热闹且你实在插不上新意时，才回复 \(self.passToken)。")
                }
            } else if !isProgressCheck {
                if mustRespond {
                    parts.append("群聊规则：用户现在在直接跟你和大家交流需求或想法，不是让你汇报工作！请积极回应用户本人的需求、提问或情绪（严禁回复 PASS），从你的视角给出直接有帮助的回答、建议或自然接话，绝不要背诵后台数字或自顾自汇报。")
                } else {
                    parts.append("群聊规则：用户现在在交流需求或聊天，不是让你汇报工作！优先响应用户刚说的话，从你自己的专长或性格提供新视角、实用建议或情绪回应；只有当前面同事已经把你的角度完全说透、你确实补充不了新价值时，才回复 \(self.passToken)。")
                }
            } else {
                parts.append("群聊规则：用户想了解今天实际做了什么。请站在用户视角直接说清楚今天推进的关键成果、卡点或能帮上忙的地方；严禁说「我贡献不大」「纯打下手」「以XX说的为准」这类无价值自报家门。如果你手里没实质内容，或前面已经讲透，只回复 \(self.passToken)，不要硬凑。")
            }
        }
        
        let trimmedCustom = bot.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            parts.append("你的性格与情绪风格（严格遵循）：\(trimmedCustom)")
        } else {
            parts.append("你的底色与当下状态（仅轻微影响措辞，绝不影响讲清事实，也禁止借此发牢骚或尬聊）：\(bot.emotion.baseline.promptDirective) 当前心境「\(bot.emotion.mood.displayLabel)」，\(bot.emotion.mood.toneDirective)")
        }
        parts.append(Self.buildStickerProtocolBlock(
            candidates: stickerCandidates,
            allowStickerOnly: allowStickerOnly,
            allowOnlineSearch: allowOnlineSearch
        ))
        parts.append(self.sharedRules)
        
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
            "表情包与情绪表达规则（克制使用，宁缺毋滥）：",
            "- 可在回复末尾附带实时心情标记（可选）：[MOOD:calm|happy|excited|focused|slacking|speechless|aggrieved]",
            "- 默认只发纯文字，不要每次都硬凑表情包！只有当你确认表情包能精准表达某个核心概念、情绪或接梗时，才使用表情包。",
        ]
        if !candidates.isEmpty {
            let listText = candidates.prefix(5).map { item in
                "- \(item.id) | \(item.promptDescription)"
            }.joined(separator: "\n")
            if allowStickerOnly {
                lines.append("""
                - 【纯表情包回复优先】如果下方某张候选图本身就已经完整表达了你要说的话（精准接梗/表态/无语/摸鱼/开心/赞同），请**只输出**这一个标签 `[STICKER:表情ID]`（可附 `[MOOD:...]`），**一个多余的汉字都不要写**，不要文字+表情包同时发；只有在必须补充文字信息且该图也很贴切时，才使用「文字 + [STICKER:表情ID]」：
                \(listText)
                """)
            } else {
                lines.append("- 当前属于正经进度/工作讨论，必须先用文字讲清重点；若下面有非常贴切的配图再附 `[STICKER:表情ID]`，否则不要发图：\n\(listText)")
            }
        }
        if allowOnlineSearch {
            lines.append("- 仅当非常需要某个特定概念的表情包且本地无图时，才偶发使用 `[SEARCH_STICKER:简短中文关键词]`（克制触发）。")
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
