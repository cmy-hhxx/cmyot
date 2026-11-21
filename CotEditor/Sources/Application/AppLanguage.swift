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
/// preferences rather than following the system language, defaulting to Simplified Chinese.
/// Changing the language is applied after relaunching the app.
enum AppLanguage: String, CaseIterable, Sendable {
    
    /// Simplified Chinese.
    case simplifiedChinese = "zh-Hans"
    
    /// English.
    case english = "en"
    
    static let explicitPreferenceKey = "cotPreferredLanguage"
    
    
    /// The language applied to the currently running app (defaults to Simplified Chinese).
    static var current: AppLanguage {
        
        self.current(in: .standard)
    }
    
    
    /// Reads the configured language from `defaults`, always defaulting to Simplified Chinese
    /// unless the user explicitly selected English in Settings.
    static func current(in defaults: UserDefaults) -> AppLanguage {
        
        if let explicit = defaults.string(forKey: Self.explicitPreferenceKey) {
            return explicit.lowercased().hasPrefix("en") ? .english : .simplifiedChinese
        }
        
        return .simplifiedChinese
    }
    
    
    /// Returns the Simplified Chinese string by default, or English only when explicitly selected in Settings.
    static func text(_ zh: String, en: String) -> String {
        
        self.current == .english ? en : zh
    }
    
    
    /// The `Locale` matching this language.
    var locale: Locale {
        
        Locale(identifier: self.rawValue)
    }
    
    
    /// The label of the language written in the language itself.
    var displayName: String {
        
        switch self {
            case .simplifiedChinese: "简体中文"
            case .english: "English"
        }
    }
    
    
    /// Ensures Simplified Chinese is pinned on first launch before AppKit loads localized nibs/menus.
    static func ensureDefaultInitialized(defaults: UserDefaults = .standard) {
        
        guard defaults.string(forKey: Self.explicitPreferenceKey) == nil else { return }
        
        defaults.set(Self.simplifiedChinese.rawValue, forKey: Self.explicitPreferenceKey)
        defaults.set([Self.simplifiedChinese.rawValue], forKey: "AppleLanguages")
    }
    
    
    /// Writes the receiver as the preferred app language for the next launch.
    func apply(to defaults: UserDefaults = .standard) {
        
        defaults.set(self.rawValue, forKey: Self.explicitPreferenceKey)
        defaults.set([self.rawValue], forKey: "AppleLanguages")
    }
}
