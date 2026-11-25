//
//  GeneratedDocumentName.swift
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

/// Names handed to new untitled documents.
///
/// Every new document used to be called 未命名, and `NSDocumentController` starts
/// numbering them (未命名 2, 未命名 3, …) as soon as a second one is open, which says
/// nothing about which window is which. A made-up name is easier to tell apart and
/// becomes the suggested file name if the document is ever saved.
nonisolated enum GeneratedDocumentName {
    
    // MARK: Types
    
    private struct ScenePhrase: Sendable {
        let text: String
        let connector: String
        
        var combinedPrefix: String { self.text + self.connector }
    }
    
    
    // MARK: Private Properties
    
    private static let recentHistoryKey = "GeneratedDocumentNameRecentHistory"
    private static let maxRecentHistory = 300
    private static let maxNameLength = 6
    
    private static let moods: [String] = [
        "打盹的", "加班的", "会飞的", "摸鱼的", "偷懒的", "正经的",
        "刚醒的", "夜班的", "走神的", "冒泡的", "佛系的", "秃头的",
        "迷路的", "写诗的", "打嗝的", "发光的", "偷笑的", "慢拍的",
        "微醺的", "失眠的", "充能的", "放假的", "晚风的", "追星的",
        "泡茶的", "翘班的", "赶稿的", "躲雨的", "吹风的", "发呆的",
        "害羞的", "困倦的", "嘴馋的", "熬夜的", "躺平的", "雀跃的",
        "软萌的", "高冷的", "好奇的", "机智的", "贪吃的", "乐天的",
    ]
    
    private static let scenes: [ScenePhrase] = [
        ScenePhrase(text: "凌晨", connector: "的"),
        ScenePhrase(text: "午后", connector: "的"),
        ScenePhrase(text: "深夜", connector: "的"),
        ScenePhrase(text: "天台", connector: "的"),
        ScenePhrase(text: "海风", connector: "的"),
        ScenePhrase(text: "窗台", connector: "的"),
        ScenePhrase(text: "云端", connector: "的"),
        ScenePhrase(text: "工位", connector: "的"),
        ScenePhrase(text: "书摊", connector: "的"),
        ScenePhrase(text: "山顶", connector: "的"),
        ScenePhrase(text: "海底", connector: "的"),
        ScenePhrase(text: "机房", connector: "里的"),
        ScenePhrase(text: "茶室", connector: "里的"),
        ScenePhrase(text: "书店", connector: "里的"),
        ScenePhrase(text: "太空", connector: "里的"),
        ScenePhrase(text: "落叶", connector: "里的"),
        ScenePhrase(text: "潜艇", connector: "里的"),
        ScenePhrase(text: "梦境", connector: "里的"),
        ScenePhrase(text: "口袋", connector: "里的"),
        ScenePhrase(text: "周末", connector: "的"),
        ScenePhrase(text: "雨夜", connector: "的"),
        ScenePhrase(text: "黄昏", connector: "的"),
    ]
    
    private static let actions: [String] = [
        "发呆的", "啃瓜的", "改码的", "练舞的", "写诗的", "画圈的",
        "弹琴的", "背词的", "数羊的", "织衣的", "看云的", "找猫的",
        "调参的", "修Bug的", "记账的", "捉迷藏的", "拍月的", "听歌的",
        "拼图的", "吹哨的", "盘核桃的", "喝茶的", "晒太阳的", "写日记的",
    ]
    
    private static let nouns: [String] = [
        "橘猫", "水獭", "企鹅", "咸鱼", "泡面", "月亮",
        "泡芙", "榛果", "台灯", "拖鞋", "云朵", "熊猫",
        "布丁", "键盘", "睡袋", "红薯", "闹钟", "糖果",
        "南瓜", "章鱼", "树懒", "海豹", "刺猬", "袋鼠",
        "柯基", "水母", "松鼠", "羊驼", "乌鸦", "可颂",
        "年糕", "狐狸", "小熊", "柴犬", "鲸鱼", "风铃",
        "纸船", "小恐龙", "洗衣机", "萤火虫", "充电宝", "小浣熊",
        "猫头鹰", "土拨鼠", "变色龙", "北极熊", "独角兽", "菠萝包",
        "烤冷面", "鸡蛋仔", "铜锣烧", "小笼包", "冻柠茶", "烤红薯",
        "留声机", "望远镜", "八音盒", "纸飞机", "竹蜻蜓", "魔法师",
    ]
    
    
    private static let shortFallbacks: [String] = [
        "发呆猫", "摸鱼獭", "偷懒鹅", "咸鱼王", "小浣熊", "小布丁", "摸鱼猫",
    ]
    
    private static let knownPrefixes: Set<String> = Set(
        moods + actions + scenes.map(\.combinedPrefix)
    )
    
    private static let knownNouns: [String] = nouns.sorted { $0.count > $1.count }
    
    private static let shortFallbackSet: Set<String> = Set(shortFallbacks)
    
    private static let copyTailRegex = try! NSRegularExpression(
        pattern: #"(?:\s*(?:\(\d+\)|（\d+）|[-_]\d+|\s+\d+|副本\s*\d*|copy\s*\d*|\d+))+$"#,
        options: [.caseInsensitive]
    )
    
    
    // MARK: Public Methods
    
    /// Returns `true` when `title` matches a whimsical placeholder produced by `GeneratedDocumentName`
    /// (e.g. `"啃瓜的小浣熊"`, `"机房里的袋鼠"`, `"潜艇里的柴犬"`), so one-click & nightly organizers
    /// know it is safe to replace with a content-derived title.
    static func isGeneratedName(_ title: String) -> Bool {
        
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 14 else { return false }
        
        let candidates: [String] = {
            var result = [trimmed]
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            let stripped = Self.copyTailRegex
                .stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty && stripped != trimmed {
                result.append(stripped)
            }
            return result
        }()
        
        for candidate in candidates {
            if Self.shortFallbackSet.contains(candidate) {
                return true
            }
            for noun in Self.knownNouns where candidate.hasSuffix(noun) && candidate.count > noun.count {
                let prefix = String(candidate.dropLast(noun.count))
                if Self.knownPrefixes.contains(prefix) {
                    return true
                }
                // Catch historical generated phrases like "<2-4字>里的<noun>" from earlier builds.
                if prefix.hasSuffix("里的") {
                    let stem = prefix.dropLast(2)
                    if stem.count >= 2 && stem.count <= 4 {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    
    /// Returns a name that none of the given documents or recent history uses yet.
    ///
    /// - Parameter usedNames: The display names of the documents already open.
    /// - Returns: A crisp, grammatical playful name within 8 characters.
    static func next(avoiding usedNames: [String]) -> String {
        
        let recent = UserDefaults.standard.stringArray(forKey: self.recentHistoryKey) ?? []
        let used = Set(usedNames).union(recent)
        
        for _ in 0..<80 {
            let name = self.randomName()
            if !used.contains(name) {
                self.record(name, in: recent)
                return name
            }
        }
        
        let openOnly = Set(usedNames)
        for _ in 0..<40 {
            let name = self.randomName()
            if !openOnly.contains(name) {
                self.record(name, in: recent)
                return name
            }
        }
        
        let base = self.randomName()
        let clippedBase = base.count <= 5 ? base : (Self.shortFallbacks.randomElement() ?? "摸鱼猫")
        let fallback = clippedBase + String(usedNames.count + 1)
        self.record(fallback, in: recent)
        return fallback
    }
    
    
    /// Generates one grammatical playful name strictly within `maxNameLength` characters.
    static func generateCandidate() -> String {
        
        self.randomName()
    }
    
    
    /// Removes malformed or overly long historical entries (e.g. `工位底下里的...`) from recent history.
    static func sanitizeRecentHistory() {
        
        let recent = UserDefaults.standard.stringArray(forKey: self.recentHistoryKey) ?? []
        let badFragments = ["底下里的", "上方里的", "边缘里的", "山顶里的", "太平洋底里的", "傍晚里的", "季节里的", "天台里的"]
        let cleaned = recent.filter { name in
            name.count <= self.maxNameLength && !badFragments.contains(where: name.contains)
        }
        UserDefaults.standard.set(cleaned, forKey: self.recentHistoryKey)
    }
    
    
    // MARK: Private Methods
    
    private static func randomName() -> String {
        
        let moodPrefixes = self.moods.filter { $0.hasSuffix("的") && !$0.isEmpty }
        let actionPrefixes = self.actions.filter { $0.hasSuffix("的") && !$0.isEmpty }
        let scenePrefixes = self.scenes.map(\.combinedPrefix)
        
        for _ in 0..<32 {
            let noun = self.nouns.randomElement() ?? "橘猫"
            let roll = Int.random(in: 0..<100)
            let pool: [String] = if roll < 45 {
                moodPrefixes
            } else if roll < 75 {
                actionPrefixes
            } else {
                scenePrefixes
            }
            
            let fitting = pool.filter { $0.count + noun.count <= Self.maxNameLength }
            if let prefix = fitting.randomElement() {
                let candidate = prefix + noun
                if candidate.count <= Self.maxNameLength {
                    return candidate
                }
            }
        }
        
        return "打盹的橘猫"
    }
    
    
    /// Remembers a generated name so consecutive new documents do not repeat across sessions.
    private static func record(_ name: String, in currentHistory: [String]) {
        
        var updated = currentHistory
        updated.removeAll { $0 == name }
        updated.append(name)
        if updated.count > self.maxRecentHistory {
            updated.removeFirst(updated.count - self.maxRecentHistory)
        }
        UserDefaults.standard.set(updated, forKey: self.recentHistoryKey)
    }
}
