//
//  SettingsPane.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2023-01-23.
//
//  ---------------------------------------------------------------------------
//
//  © 2023-2025 1024jp
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

import SwiftUI
import ControlUI

enum SettingsPaneLayout {
    
    /// Unified content size across every settings pane (roughly 4:3, matching macOS System Settings proportions).
    static let width: CGFloat = 660
    static let height: CGFloat = 500
}


/// Shared Apple System Settings–style grouped form scaffold with a consistent frame and footer bar.
struct SettingsFormPane<Content: View>: View {
    
    var helpAnchor: String?
    @ViewBuilder var content: () -> Content
    
    
    var body: some View {
        
        VStack(spacing: 0) {
            Form {
                self.content()
            }
            .formStyle(.grouped)
            
            if let helpAnchor {
                Divider()
                HStack {
                    Spacer()
                    HelpLink(anchor: helpAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .frame(width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
    }
}


enum SettingsPane: String, ControlUI.SettingsPane {
    
    case general
    case appearance
    case window
    case edit
    case format
    case keyBindings
    case ai
    case aiPersona
    
    
    /// The localized label.
    var label: String {
        
        switch self {
            case .general:
                String(localized: "SettingsPane.general.label",
                       defaultValue: "General",
                       table: "Settings")
            case .appearance:
                String(localized: "SettingsPane.appearance.label",
                       defaultValue: "Appearance",
                       table: "Settings")
            case .window:
                String(localized: "SettingsPane.window.label",
                       defaultValue: "Window",
                       table: "Settings")
            case .edit:
                String(localized: "SettingsPane.edit.label",
                       defaultValue: "Edit",
                       table: "Settings")
            case .format:
                String(localized: "SettingsPane.format.label",
                       defaultValue: "Format",
                       table: "Settings")
            case .keyBindings:
                String(localized: "SettingsPane.keyBindings.label",
                       defaultValue: "Key Bindings",
                       table: "Settings")
            case .ai:
                "AI"
            case .aiPersona:
                "AI Persona"
        }
    }
    
    
    /// The symbol image for tab item.
    var systemSymbolName: String {
        
        switch self {
            case .general: "gearshape"
            case .appearance: "eyeglasses"
            case .window: "uiwindow.split.2x1"
            case .edit: "square.and.pencil"
            case .format: "text.document"
            case .keyBindings: "keyboard"
            case .ai: "sparkles"
            case .aiPersona: "person.text.rectangle"
        }
    }
    
    
    /// The content view.
    @MainActor var view: any View {
        
        switch self {
            case .general: GeneralSettingsView()
            case .appearance: AppearanceSettingsView()
            case .window: WindowSettingsView()
            case .edit: EditSettingsView()
            case .format: FormatSettingsView()
            case .keyBindings: KeyBindingsSettingsView()
            case .ai: AISettingsView()
            case .aiPersona: AIPersonaSettingsView()
        }
    }
}
