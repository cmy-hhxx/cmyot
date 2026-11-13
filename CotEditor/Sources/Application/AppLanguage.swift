//
//  AppLanguage.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-06.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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

/// The interface language of the app.
///
/// This fork pins the app language through the `AppleLanguages` user default in the app's own
/// preferences rather than following the system language. Therefore, changing the language can
/// only be applied by relaunching the app.
enum AppLanguage: String, CaseIterable, Sendable {
    
    /// Simplified Chinese.
    case simplifiedChinese = "zh-Hans"
    
    /// English.
    case english = "en"
    
    
    /// The language applied to the currently running app.
    static var current: AppLanguage {
        
        let identifier = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
        
        return (identifier?.lowercased().hasPrefix("zh") == true) ? .simplifiedChinese : .english
    }
    
    
    /// The label of the language written in the language itself.
    var displayName: String {
        
        switch self {
            case .simplifiedChinese: "简体中文"
            case .english: "English"
        }
    }
    
    
    /// Writes the receiver as the preferred app language for the next launch.
    func apply() {
        
        UserDefaults.standard.set([self.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
}
