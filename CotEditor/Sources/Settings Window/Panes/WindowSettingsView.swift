//
//  WindowSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-04-18.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2025 1024jp
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

struct WindowSettingsView: View {
    
    @Namespace private var accessibility
    
    @AppStorage(.showLineNumbers) private var showLineNumbers
    @available(macOS, deprecated: 26)
    @AppStorage(.showLineNumberSeparator) private var showLineNumberSeparator
    @AppStorage(.showInvisibles) private var showInvisibles
    @AppStorage(.showIndentGuides) private var showIndentGuides
    @AppStorage(.showPageGuide) private var showPageGuide
    @AppStorage(.pageGuideColumn) private var pageGuideColumn
    @AppStorage(.highlightCurrentLine) private var highlightCurrentLine
    
    @AppStorage(.wrapLines) private var wrapLines
    @AppStorage(.enablesHangingIndent) private var enablesHangingIndent
    @AppStorage(.hangingIndentWidth) private var hangingIndentWidth
    
    @AppStorage(.showStatusBarLines) private var showStatusBarLines
    @AppStorage(.showStatusBarChars) private var showStatusBarChars
    @AppStorage(.showStatusBarWords) private var showStatusBarWords
    @AppStorage(.showStatusBarLocation) private var showStatusBarLocation
    @AppStorage(.showStatusBarLine) private var showStatusBarLine
    @AppStorage(.showStatusBarColumn) private var showStatusBarColumn
    
    
    var body: some View {
        
        SettingsFormPane(helpAnchor: "settings_window") {
            Section {
                Toggle(String(localized: "Line numbers", table: "WindowSettings"), isOn: $showLineNumbers)
                    .lineLimit(1)
                if #unavailable(macOS 26) {
                    Toggle(String(localized: "Draw separator", table: "WindowSettings"), isOn: $showLineNumberSeparator)
                        .lineLimit(1)
                        .disabled(!self.showLineNumbers)
                        .padding(.leading, 20)
                }
                Toggle(String(localized: "Invisible characters", table: "WindowSettings"), isOn: $showInvisibles)
                    .lineLimit(1)
                Toggle(String(localized: "Indent guides", table: "WindowSettings"), isOn: $showIndentGuides)
                    .lineLimit(1)
                
                LabeledContent {
                    StepperNumberField(value: $pageGuideColumn, default: UserDefaults.standard[initial: .pageGuideColumn], in: 1...999)
                        .accessibilityLabel(String(localized: "Page guide at column:", table: "WindowSettings"))
                        .disabled(!self.showPageGuide)
                } label: {
                    Toggle(String(localized: "Page guide at column:", table: "WindowSettings"), isOn: $showPageGuide)
                        .lineLimit(1)
                }
                
                Toggle(isOn: $highlightCurrentLine) {
                    HStack(spacing: 6) {
                        Text("Current line:", tableName: "WindowSettings")
                        Text("Change background color", tableName: "WindowSettings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
            } header: {
                Text("Show:", tableName: "WindowSettings")
            }
            
            Section {
                Toggle(String(localized: "Wrap lines to editor width", table: "WindowSettings"), isOn: $wrapLines)
                    .lineLimit(1)
                
                LabeledContent {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        StepperNumberField(value: $hangingIndentWidth, default: UserDefaults.standard[initial: .hangingIndentWidth], in: 0...99)
                            .disabled(!self.enablesHangingIndent)
                            .accessibilityLabel(String(localized: "wrapped line indent spaces", table: "WindowSettings", comment: "accessibility label"))
                        Text("spaces", tableName: "WindowSettings", comment: "unit for indentation")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } label: {
                    Toggle(String(localized: "Indent wrapped lines by", table: "WindowSettings"), isOn: $enablesHangingIndent)
                        .lineLimit(1)
                }
            } header: {
                Text("Line wrapping:", tableName: "WindowSettings")
            }
            
            Section {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                    GridRow {
                        Toggle(String(localized: "Line count", table: "WindowSettings"), isOn: $showStatusBarLines)
                            .lineLimit(1)
                        Toggle(String(localized: "Location", table: "WindowSettings"), isOn: $showStatusBarLocation)
                            .lineLimit(1)
                    }
                    GridRow {
                        Toggle(String(localized: "Character count", table: "WindowSettings"), isOn: $showStatusBarChars)
                            .lineLimit(1)
                        Toggle(String(localized: "Current line", table: "WindowSettings"), isOn: $showStatusBarLine)
                            .lineLimit(1)
                    }
                    GridRow {
                        Toggle(String(localized: "Word count", table: "WindowSettings"), isOn: $showStatusBarWords)
                            .lineLimit(1)
                        Toggle(String(localized: "Current column", table: "WindowSettings"), isOn: $showStatusBarColumn)
                            .lineLimit(1)
                    }
                }
                .accessibilityLabeledPair(role: .content, id: "sideBarShows", in: self.accessibility)
            } header: {
                Text("Status bar shows:", tableName: "WindowSettings")
                    .accessibilityLabeledPair(role: .label, id: "sideBarShows", in: self.accessibility)
            }
        }
    }
}


// MARK: - Preview

#Preview {
    WindowSettingsView()
}
