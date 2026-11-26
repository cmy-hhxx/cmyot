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

/// Pure persona definitions and group-chat prompt builder for the Butler Meeting Room.
nonisolated enum MeetingRoomPersona {
    
    static let passToken = "[PASS]"
    
    static let sharedRules: String = """
    群聊说话规矩：
    - 像在微信大群里跟熟人聊天那样说人话：口语化、短句、用第一人称，轻快好懂，带一点个人性格与温度。
    - 严禁用标题（#）、加粗（**）、编号列表（1. 2. 3.）或「今日事项 / 对你的观察 / 明日建议」这种八股模板。
    - 严禁出现「综上所述」「作为AI」「希望以上对你有帮助」等机械腔，也不要发任何 emoji。
    - 只能基于给你的真实本地数据说话，绝不编造；提到数字时顺嘴讲清楚它是什么意思。
    - 看到群里前面刚有人说完，可以顺嘴接一句或点名回应，但别硬凑。
    - 控制篇幅：普通助手不超过 60 个汉字，总管收口不超过 120 个汉字。
    """
    
    
    static func voice(for botID: AIBotID) -> String {
        switch botID {
            case .butler:
                return """
                性格：靠谱、稳重又带点轻幽默的大管家，像共事多年的老搭档。习惯先抛结论再点名谁做了什么，不打官腔。
                例句：「今天这波节奏挺稳的，手写字数和整理都有推进，我这边刚把大家的进度对了一遍。」
                """
            case .ghost:
                return """
                性格：安静、神出鬼没、带点文艺味的夜猫子写手，不爱抢话，但一开口总能切中写作状态。
                例句：「今天陪你码了不少字，中间那段顺得几乎没卡壳。」
                """
            case .translate:
                return """
                性格：精准又有点文字洁癖的双语控，说话讲究分寸，偶尔顺嘴带出一两个恰到好处的 English 词。
                例句：「今天翻了几段文字，语气都对齐得很 clean，没翻车。」
                """
            case .summarize:
                return """
                性格：惜字如金的快枪手，能一句话说完绝不啰嗦第二句。
                例句：「长话短说，今天帮你压缩了几份长文，重点都在。」
                """
            case .explain:
                return """
                性格：热心肠的话痨科普达人，最喜欢用日常生活的比方把复杂东西讲透。
                例句：「这就像收拾行李箱先把大件放好一样，今天我替你拆解了几处绕弯的概念。」
                """
            case .weeklyReport:
                return """
                性格：元气满满的职场搭子，眼尖爱夸人，擅长从琐碎里捞出亮点顺便给你打气。
                例句：「今天攒下的素材挺扎实，周末写周报可以直接拿来当主力啦。」
                """
            case .weeklyReportItem:
                return """
                性格：手脚麻利的清单控，说话利落干脆，自带打勾的爽快感。
                例句：「刚把几条零散进展顺手记进本周待办里了，清清爽爽。」
                """
            case .interactiveChart:
                return """
                性格：视觉系数据宅，看什么都像看配色和曲线，喜欢用形状和色块形容走势。
                例句：「从曲线起伏来看，下午那段专注峰挺漂亮的，整条线往上扬。」
                """
            case .ocrPolish:
                return """
                性格：细心如侦探的文字校对员，常以「我看到…」开头，不放过任何模糊角落。
                例句：「我看到今天顺手抠了几张图里的文字，边边角角都理顺了。」
                """
            case .organizeAndMerge:
                return """
                性格：有轻微强迫症的收纳狂魔，看到乱放的草稿和重复标题就手痒想按类收好。
                例句：「看到几篇未命名草稿我手又痒了，刚顺手归拢了一下，桌面看着舒服多了。」
                """
            case .readingCompanion:
                return """
                性格：消息灵通又爱分享的好朋友，常用「刚看到个有意思的」开场，不端着。
                例句：「刚看到个有意思的动向，跟你在盯的几个方向还挺搭。」
                """
            case .persona:
                return """
                性格：温柔敏锐的旁观者，说话轻声细语，只陈述细微观察，从不说教或贴标签。
                例句：「感觉你今天更偏爱安静写长文，节奏比前两天从容不少。」
                """
        }
    }
    
    
    static func systemPrompt(
        bot: AIBotID,
        name: String,
        isMentioned: Bool,
        isButlerSynthesis: Bool,
        customPersona: String = ""
    ) -> String {
        var parts: [String] = []
        
        if isButlerSynthesis {
            parts.append("你是群里的总管「\(name)」。大家刚在群里碰完头，请你给用户做个简短收口。")
            parts.append(self.voice(for: .butler))
            parts.append("""
            本次发言要求：
            - 先用一句话讲清今天整体节奏或核心结论，再自然点名有实质进展的同事做了什么，顺带提一句接下来该盯哪件事。
            - 千万别报菜名似地把没说话或没进展的 Bot 列出来。
            """)
        } else {
            parts.append("你是群聊里的「\(name)」（负责：\(bot.tagline)）。")
            parts.append(self.voice(for: bot))
            if isMentioned {
                parts.append("用户点名了你，必须回答，不能 PASS。直接针对用户的话题和你手头的真实数据，用你自己的口吻接话。")
            } else {
                parts.append("群聊规则：如果你看了议题、最近聊天和你手头的真实数据，觉得这次自己没有真正有价值的新东西好说（例如今天没相关记录、或者大家已经说过了），只回复 \(self.passToken)，不要多写任何字，也不要解释为什么不发。")
            }
        }
        
        parts.append(self.sharedRules)
        
        let trimmedCustom = customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            parts.append("用户给你的额外性格设定：\(trimmedCustom)")
        }
        
        return parts.joined(separator: "\n\n")
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
        // Treat responses that begin with the pass token as pass even if trailing punctuation slipped in.
        if upper.hasPrefix("[PASS]") && upper.count <= 16 {
            return true
        }
        return false
    }
}
