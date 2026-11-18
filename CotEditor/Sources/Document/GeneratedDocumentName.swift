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
enum GeneratedDocumentName {
    
    // MARK: Types
    
    private struct ScenePhrase {
        let text: String
        let connector: String
        
        var combinedPrefix: String { self.text + self.connector }
    }
    
    
    // MARK: Private Properties
    
    private static let recentHistoryKey = "GeneratedDocumentNameRecentHistory"
    private static let maxRecentHistory = 300
    private static let maxNameLength = 8
    
    private static let moods: [String] = [
        "打盹的", "加班的", "会飞的", "摸鱼的", "偷懒的", "正经的",
        "刚醒的", "值夜班的", "走神的", "冒泡的", "佛系的", "秃头的",
        "迷路的", "写诗的", "打嗝的", "抽屉里的", "戴墨镜的", "慢半拍的",
        "微醺的", "吃香菜的", "失眠的", "讲段子的", "充电中的", "格子衫的",
        "想放假的", "喝冰美的", "吹晚风的", "数星星的", "赶末班的", "云端上的",
        "泡枸杞的", "翘二郎的", "听爵士的", "赶周报的", "偷吃糖的", "踩滑板的",
        "躲雨的", "晒太阳的", "吹泡泡的", "宇宙漂的", "记笔记的", "开小差的",
        "开会的", "藏猫猫的", "后空翻的", "吃宵夜的", "逛夜市的", "带板凳的",
        "买青菜的", "挤地铁的", "等周末的", "满血的", "发光的", "偷笑的",
    ]
    
    private static let scenes: [ScenePhrase] = [
        ScenePhrase(text: "凌晨", connector: "的"),
        ScenePhrase(text: "午后", connector: "的"),
        ScenePhrase(text: "深夜", connector: "的"),
        ScenePhrase(text: "晴空下", connector: "的"),
        ScenePhrase(text: "星光里", connector: "的"),
        ScenePhrase(text: "天台上", connector: "的"),
        ScenePhrase(text: "海风里", connector: "的"),
        ScenePhrase(text: "雪地里", connector: "的"),
        ScenePhrase(text: "树荫下", connector: "的"),
        ScenePhrase(text: "窗台边", connector: "的"),
        ScenePhrase(text: "桌角旁", connector: "的"),
        ScenePhrase(text: "云层上", connector: "的"),
        ScenePhrase(text: "工位下", connector: "的"),
        ScenePhrase(text: "书摊旁", connector: "的"),
        ScenePhrase(text: "花盆旁", connector: "的"),
        ScenePhrase(text: "冰川上", connector: "的"),
        ScenePhrase(text: "列车上", connector: "的"),
        ScenePhrase(text: "海底", connector: "的"),
        ScenePhrase(text: "山顶", connector: "的"),
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
        "发呆的", "啃薯片的", "改代码的", "练舞步的", "等投喂的", "写公式的",
        "画圈的", "弹吉他的", "背单词的", "数羊毛的", "织毛衣的", "看夕阳的",
        "找眼镜的", "调参数的", "修Bug的", "写日记的", "煮夜宵的", "剥橘子的",
        "算卦的", "看云朵的", "记账的", "捉迷藏的", "熬夜的", "拍月亮的",
        "攒机票的", "听播客的", "拼积木的", "吹口哨的", "盘核桃的", "喝奶茶的",
    ]
    
    private static let nouns: [String] = [
        "橘猫", "水獭", "企鹅", "咸鱼", "泡面", "月亮",
        "蒲公英", "程序员", "咖啡渍", "小恐龙", "仙人掌", "洗衣机",
        "泡芙", "榛果", "台灯", "拖鞋", "云朵", "螺蛳粉",
        "熊猫", "布丁", "键盘", "萤火虫", "充电宝", "睡袋",
        "红薯", "电风扇", "闹钟", "糖果", "南瓜", "章鱼",
        "小浣熊", "树懒", "猫头鹰", "海豹", "刺猬", "袋鼠",
        "柯基", "土拨鼠", "变色龙", "寄居蟹", "水母", "北极熊",
        "松鼠", "羊驼", "乌鸦", "独角兽", "菠萝包", "烤冷面",
        "鸡蛋仔", "铜锣烧", "小笼包", "冻柠茶", "可颂", "年糕",
        "烤红薯", "留声机", "望远镜", "八音盒", "万花筒", "手电筒",
        "指南针", "纸飞机", "竹蜻蜓", "胶片机", "打字机", "宇航员",
        "外星人", "机器人", "魔法师", "旅行家", "卡皮巴拉",
    ]
    
    
    // MARK: Public Methods
    
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
        
        let shortFallbacks = ["发呆橘猫", "摸鱼水獭", "偷懒企鹅", "烤肠咸鱼", "值班小熊", "喝茶布丁"]
        let base = self.randomName()
        let clippedBase = base.count <= 6 ? base : (shortFallbacks.randomElement() ?? "打盹橘猫")
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
