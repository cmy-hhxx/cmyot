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
    
    private static let modifiers: [String] = [
        "打盹的", "加班的", "会飞的", "摸鱼的", "偷偷发光的", "假装严肃的",
        "刚睡醒的", "值夜班的", "走神的", "蹦蹦跳跳的", "佛系的", "秃头的",
        "迷路的", "会写诗的", "打嗝的", "藏在抽屉里的", "戴墨镜的", "慢半拍的",
        "半夜emo的", "爱吃香菜的", "不睡觉的", "会讲冷笑话的",
    ]
    
    private static let nouns: [String] = [
        "橘猫", "水獭", "企鹅", "咸鱼", "泡面", "月亮",
        "蒲公英", "程序员", "咖啡渍", "小恐龙", "仙人掌", "洗衣机",
        "泡芙", "榛果", "台灯", "拖鞋", "云朵", "螺蛳粉",
        "熊猫", "布丁", "键盘", "萤火虫", "充电宝", "睡袋",
        "红薯", "电风扇", "闹钟", "糖果", "南瓜", "章鱼",
    ]
    
    
    // MARK: Public Methods
    
    /// Returns a name that none of the given documents uses yet.
    ///
    /// - Parameter usedNames: The display names of the documents already open.
    /// - Returns: A made-up name, e.g. `打盹的橘猫`.
    static func next(avoiding usedNames: [String]) -> String {
        
        let used = Set(usedNames)
        let combinations = self.modifiers.count * self.nouns.count
        
        for _ in 0..<20 where combinations > used.count {
            let name = self.randomName()
            
            if !used.contains(name) {
                return name
            }
        }
        
        return self.randomName() + " " + String(used.count + 1)
    }
    
    
    // MARK: Private Methods
    
    /// Returns a random combination of a modifier and a noun.
    private static func randomName() -> String {
        
        let modifier = self.modifiers.randomElement() ?? ""
        let noun = self.nouns.randomElement() ?? ""
        
        return modifier + noun
    }
}
