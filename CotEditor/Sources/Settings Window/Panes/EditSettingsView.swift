//
//  EditSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2023-11-29.
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
import Defaults

struct EditSettingsView: View {
    
    @Namespace private var accessibility
    
    @AppStorage(.autoExpandTab) private var autoExpandTab
    @AppStorage(.tabWidth) private var tabWidth
    @AppStorage(.detectsIndentStyle) private var detectsIndentStyle
    @AppStorage(.autoIndent) private var autoIndent
    @AppStorage(.indentWithTabKey) private var indentWithTabKey
    
    @AppStorage(.autoTrimsTrailingWhitespace) private var autoTrimsTrailingWhitespace
    @AppStorage(.trimsWhitespaceOnlyLines) private var trimsWhitespaceOnlyLines
    
    @AppStorage(.autoLinkDetection) private var autoLinkDetection
    @AppStorage(.highlightBraces) private var highlightBraces
    @AppStorage(.highlightSelectionInstance) private var highlightSelectionInstance
    
    
    var body: some View {
        
        SettingsFormPane(helpAnchor: "settings_edit") {
            Section {
                Picker(String(localized: "Prefer using", table: "EditSettings"), selection: $autoExpandTab) {
                    Text("Spaces", tableName: "EditSettings", comment: "indent style").tag(true)
                    Text("Tabs", tableName: "EditSettings", comment: "indent style").tag(false)
                }
                .pickerStyle(.menu)
                
                LabeledContent {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        StepperNumberField(value: $tabWidth, default: UserDefaults.standard[initial: .tabWidth], in: 1...99)
                            .accessibilityLabeledPair(role: .content, id: "tabWidth", in: self.accessibility)
                        Text("spaces", tableName: "EditSettings", comment: "unit for indentation")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Indent width:", tableName: "EditSettings")
                        .accessibilityLabeledPair(role: .label, id: "tabWidth", in: self.accessibility)
                }
                
                Toggle(String(localized: "Detect indent style on document opening", table: "EditSettings"), isOn: $detectsIndentStyle)
                Toggle(String(localized: "Automatically indent while typing", table: "EditSettings"), isOn: $autoIndent)
                Toggle(String(localized: "Indent selection with Tab key", table: "EditSettings"), isOn: $indentWithTabKey)
            } header: {
                Text("Indentation:", tableName: "EditSettings")
            }
            
            Section {
                Toggle(String(localized: "Automatically trim trailing whitespace", table: "EditSettings"), isOn: $autoTrimsTrailingWhitespace)
                Toggle(String(localized: "Including whitespace-only lines", table: "EditSettings"), isOn: $trimsWhitespaceOnlyLines)
                    .disabled(!self.autoTrimsTrailingWhitespace)
            } header: {
                Text("Whitespace:", tableName: "EditSettings")
            }
            
            Section {
                Toggle(String(localized: "Link URLs in document", table: "EditSettings"), isOn: $autoLinkDetection)
                Toggle(String(localized: "Highlight matching braces", table: "EditSettings"), isOn: $highlightBraces)
                Toggle(String(localized: "Highlight instances of selected text", table: "EditSettings"), isOn: $highlightSelectionInstance)
            } header: {
                Text("Content parse:", tableName: "EditSettings")
            }
        }
    }
}


// MARK: - Preview

#Preview {
    EditSettingsView()
}
