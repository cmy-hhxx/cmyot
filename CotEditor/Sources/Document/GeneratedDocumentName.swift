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

import Foundation

/// Names handed to new untitled documents.
///
/// Every new document used to be called 未命名, and `NSDocumentController` starts
/// numbering them (未命名 2, 未命名 3, …) as soon as a second one is open, which says
/// nothing about which window is which. A made-up name is easier to tell apart and
/// becomes the suggested file name if the document is ever saved.
enum GeneratedDocumentName {
    
    // MARK: Private Properties
    
    private static let recentHistoryKey = "GeneratedDocumentNameRecentHistory"
    private static let maxRecentHistory = 300
    private static let maxNameLength = 8
    
    private static let moods: [String] = [
        "打盹的", "加班的", "会飞的", "摸鱼的", "偷偷发光的", "假装严肃的",
        "刚睡醒的", "值夜班的", "走神的", "蹦蹦跳跳的", "佛系的", "秃头的",
        "迷路的", "会写诗的", "打嗝的", "藏在抽屉里的", "戴墨镜的", "慢半拍的",
        "半夜emo的", "爱吃香菜的", "不睡觉的", "会讲冷笑话的", "正在充电的", "穿格子衫的",
        "想休假的", "喝冰美式的", "在天台吹风的", "倒立洗头的", "忘记带钥匙的", "数星星的",
        "追赶落日的", "揣着明白装糊涂的", "在云端散步的", "刚理完发的", "泡枸杞的", "翘二郎腿的",
        "听爵士乐的", "写不出周报的", "试图减肥的", "满脑子问号的", "刚中五块钱的", "踩着滑板的",
        "躲雨的", "晒太阳的", "吹泡泡的", "在宇宙漂流的", "偷偷记笔记的", "一本正经的",
        "灵魂出窍的", "假装在开会的", "找不到的", "会后空翻的", "爱吃宵夜的", "不按套路出牌的",
        "带着小板凳的", "顺路买菜的", "在地铁看书的", "刚充完会员的", "等待周末的", "满血复活的",
    ]
    
    private static let scenes: [String] = [
        "凌晨三点", "咖啡馆角落", "天台边缘", "末班地铁上", "会议室后排", "老式收音机里",
        "秋名山顶", "便利店门口", "工位底下", "旧书摊旁", "太平洋底", "平行宇宙里",
        "键盘缝隙中", "阳台花盆旁", "南极冰川上", "下午茶时间", "周日傍晚", "梅雨季节",
        "太空舱里", "街角面包店", "落叶堆里", "服务器机房", "晚高峰路口", "图书馆三楼",
        "深海潜艇里", "旋转木马上", "云层上方", "篝火晚会旁", "自动售货机前", "复古列车上",
    ]
    
    private static let actions: [String] = [
        "思考人生的", "偷吃薯片的", "重构代码的", "练习太空步的", "等待投喂的", "研究量子力学的",
        "画圈圈的", "弹尤克里里的", "背单词的", "数羊毛的", "织毛衣的", "看夕阳的",
        "找眼镜的", "调参数的", "修bug的", "写散文的", "煮螺蛳粉的", "剥橘子的",
        "算命的", "看云的", "记账的", "发呆的", "捉迷藏的", "熬夜看球的",
        "拍月亮的", "攒机票的", "听播客的", "拼乐高的", "吹口哨的", "盘核桃的",
    ]
    
    private static let nouns: [String] = [
        "橘猫", "水獭", "企鹅", "咸鱼", "泡面", "月亮",
        "蒲公英", "程序员", "咖啡渍", "小恐龙", "仙人掌", "洗衣机",
        "泡芙", "榛果", "台灯", "拖鞋", "云朵", "螺蛳粉",
        "熊猫", "布丁", "键盘", "萤火虫", "充电宝", "睡袋",
        "红薯", "电风扇", "闹钟", "糖果", "南瓜", "章鱼",
        "卡皮巴拉", "小浣熊", "树懒", "猫头鹰", "海豹", "刺猬",
        "袋鼠", "柯基", "土拨鼠", "变色龙", "寄居蟹", "水母",
        "北极熊", "松鼠", "羊驼", "乌鸦", "信天翁", "独角兽",
        "菠萝包", "烤冷面", "冰糖葫芦", "鸡蛋仔", "铜锣烧", "小笼包",
        "抹茶拿铁", "冻柠茶", "可颂", "年糕", "煎饼果子", "烤红薯",
        "留声机", "望远镜", "八音盒", "万花筒", "手电筒", "指南针",
        "纸飞机", "竹蜻蜓", "玻璃弹珠", "磁带", "胶片机", "打字机",
        "宇航员", "外星人", "机器人", "魔法师", "炼金术士", "旅行家",
    ]
    
    
    // MARK: Public Methods
    
    /// Returns a name that none of the given documents or recent history uses yet.
    ///
    /// - Parameter usedNames: The display names of the documents already open.
    /// - Returns: A made-up name, e.g. `打盹的橘猫` or `凌晨三点思考人生的卡皮巴拉`.
    static func next(avoiding usedNames: [String]) -> String {
        
        let recent = UserDefaults.standard.stringArray(forKey: self.recentHistoryKey) ?? []
        let used = Set(usedNames).union(recent)
        
        for _ in 0..<60 {
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
    
    
    // MARK: Private Methods
    
    /// Returns a random combination across playful templates kept strictly within `maxNameLength`
    /// characters so tab titles display in full without ugly `...` truncation.
    private static func randomName() -> String {
        
        let shortNouns = self.nouns.filter { $0.count <= 4 }
        let shortMoods = self.moods.filter { $0.count <= 4 }
        let shortScenes = self.scenes.filter { $0.count <= 4 }
        let shortActions = self.actions.filter { $0.count <= 4 }
        
        for _ in 0..<24 {
            let noun = shortNouns.randomElement() ?? "橘猫"
            let roll = Int.random(in: 0..<100)
            let candidate: String
            
            if roll < 50 {
                // Classic: 摸鱼的橘猫 / 加班的小恐龙
                let prefixPool = shortMoods.filter { $0.count + noun.count <= Self.maxNameLength }
                let mood = prefixPool.randomElement() ?? "打盹的"
                candidate = mood + noun
            } else if roll < 80 {
                // Action + Noun: 修bug的橘猫 / 发呆的水獭
                let prefixPool = shortActions.filter { $0.count + noun.count <= Self.maxNameLength }
                let action = prefixPool.randomElement() ?? "发呆的"
                candidate = action + noun
            } else {
                // Scene + Noun: 机房里的企鹅 / 天台的橘猫
                let prefixPool = shortScenes.filter { $0.count + 1 + noun.count <= Self.maxNameLength }
                let scene = prefixPool.randomElement() ?? "天台"
                let connector = scene.hasSuffix("里") || scene.hasSuffix("上") || scene.hasSuffix("中") || scene.hasSuffix("旁") ? "的" : "里的"
                let joined = scene + connector + noun
                candidate = joined.count <= Self.maxNameLength ? joined : (scene + "的" + noun)
            }
            
            if candidate.count <= Self.maxNameLength {
                return candidate
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
