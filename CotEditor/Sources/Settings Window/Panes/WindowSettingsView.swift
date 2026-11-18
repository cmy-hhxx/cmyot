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
        
        Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 8) {
            GridRow {
                Text("Show:", tableName: "WindowSettings")
                    .gridColumnAlignment(.trailing)
                
                VStack(alignment: .leading, spacing: isLiquidGlass ? nil : 6) {
                    Toggle(String(localized: "Line numbers", table: "WindowSettings"), isOn: $showLineNumbers)
                    if #unavailable(macOS 26) {
                        Toggle(String(localized: "Draw separator", table: "WindowSettings"), isOn: $showLineNumberSeparator)
                            .disabled(!self.showLineNumbers)
                            .padding(.leading, 20)
                    }
                    
                    Toggle(String(localized: "Invisible characters", table: "WindowSettings"), isOn: $showInvisibles)
                    Toggle(String(localized: "Indent guides", table: "WindowSettings"), isOn: $showIndentGuides)
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(String(localized: "Page guide at column:", table: "WindowSettings"), isOn: $showPageGuide)
                        StepperNumberField(value: $pageGuideColumn, default: UserDefaults.standard[initial: .pageGuideColumn], in: 1...999)
                            .accessibilityLabel(String(localized: "Page guide at column:", table: "WindowSettings"))
                            .disabled(!self.showPageGuide)
                    }
                }
            }
            
            GridRow {
                Text("Current line:", tableName: "WindowSettings")
                    .gridColumnAlignment(.trailing)
                
                Toggle(String(localized: "Change background color", table: "WindowSettings"), isOn: $highlightCurrentLine)
            }
            
            Divider()
                .padding(.vertical, 6)
            
            GridRow {
                Text("Line wrapping:", tableName: "WindowSettings")
                    .gridColumnAlignment(.trailing)
                
                VStack(alignment: .leading, spacing: isLiquidGlass ? nil : 6) {
                    Toggle(String(localized: "Wrap lines to editor width", table: "WindowSettings"), isOn: $wrapLines)
                    HStack(alignment: .firstTextBaseline) {
                        Toggle(String(localized: "Indent wrapped lines by", table: "WindowSettings"), isOn: $enablesHangingIndent)
                        StepperNumberField(value: $hangingIndentWidth, default: UserDefaults.standard[initial: .hangingIndentWidth], in: 0...99)
                            .disabled(!self.enablesHangingIndent)
                            .accessibilityLabel(String(localized: "wrapped line indent spaces", table: "WindowSettings", comment: "accessibility label"))
                        Text("spaces", tableName: "WindowSettings", comment: "unit for indentation")
                    }
                }
            }
            
            Divider()
                .padding(.vertical, 6)
            
            GridRow {
                Text("Status bar shows:", tableName: "WindowSettings")
                    .accessibilityLabeledPair(role: .label, id: "sideBarShows", in: self.accessibility)
                    .gridColumnAlignment(.trailing)
                
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading, spacing: isLiquidGlass ? nil : 6) {
                        Toggle(String(localized: "Line count", table: "WindowSettings"), isOn: $showStatusBarLines)
                        Toggle(String(localized: "Character count", table: "WindowSettings"), isOn: $showStatusBarChars)
                        Toggle(String(localized: "Word count", table: "WindowSettings"), isOn: $showStatusBarWords)
                    }
                    VStack(alignment: .leading, spacing: isLiquidGlass ? nil : 6) {
                        Toggle(String(localized: "Location", table: "WindowSettings"), isOn: $showStatusBarLocation)
                        Toggle(String(localized: "Current line", table: "WindowSettings"), isOn: $showStatusBarLine)
                        Toggle(String(localized: "Current column", table: "WindowSettings"), isOn: $showStatusBarColumn)
                    }
                }
                .accessibilityLabeledPair(role: .content, id: "sideBarShows", in: self.accessibility)
            }
            .fixedSize()
            
            HStack {
                Spacer()
                HelpLink(anchor: "settings_window")
            }.padding(.top, -8)
        }
        .scenePadding()
        .frame(minWidth: 620)
    }
}


// MARK: - Preview

#Preview {
    WindowSettingsView()
}
