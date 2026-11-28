//
//  SidebarEditingSettingsPane.swift
//
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

import Defaults
import FileEncoding
import LineEnding
import SwiftUI
import SyntaxFormat

/// Consolidated Editing & Format settings pane (Vim, View helpers, Indentation, Content helpers, and Format/Encoding).
struct SidebarEditingSettingsPane: View {
    
    @AppStorage(.showLineNumbers) private var showLineNumbers
    @AppStorage(.wrapLines) private var wrapLines
    @AppStorage(.highlightCurrentLine) private var highlightCurrentLine
    @AppStorage(.showIndentGuides) private var showIndentGuides
    @AppStorage(.showInvisibles) private var showInvisibles
    
    @AppStorage(.autoExpandTab) private var autoExpandTab
    @AppStorage(.tabWidth) private var tabWidth
    @AppStorage(.autoIndent) private var autoIndent
    @AppStorage(.indentWithTabKey) private var indentWithTabKey
    
    @AppStorage(.autoTrimsTrailingWhitespace) private var autoTrimsTrailingWhitespace
    @AppStorage(.highlightBraces) private var highlightBraces
    @AppStorage(.highlightSelectionInstance) private var highlightSelectionInstance
    @AppStorage(.vimMode) private var vimMode
    
    @AppStorage(.lineEndCharCode) private var lineEnding
    @AppStorage(.encoding) private var encoding
    @AppStorage(.saveUTF8BOM) private var saveUTF8BOM
    @AppStorage(.referToEncodingTag) private var referToEncodingTag
    @AppStorage(.syntax) private var syntax
    
    @State private var plainTextImagesEnabled = true
    @State private var encodingManager: EncodingManager = .shared
    @State private var syntaxNames: [String] = SyntaxManager.shared.settingNames
    @State private var isEncodingListPresented = false
    
    private var fileEncoding: Binding<FileEncoding> {
        Binding(
            get: { FileEncoding(encoding: String.Encoding(rawValue: UInt(self.encoding)), withUTF8BOM: self.saveUTF8BOM) },
            set: {
                self.encoding = Int($0.encoding.rawValue)
                self.saveUTF8BOM = $0.withUTF8BOM
            }
        )
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            if self.isEncodingListPresented {
                self.encodingPriorityDrillDown
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                self.mainContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onAppear {
            self.plainTextImagesEnabled = CotLocalDatabase.shared.bool(
                forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled,
                default: true
            )
        }
        .onReceive(SyntaxManager.shared.$settingNames) { self.syntaxNames = $0 }
        .onChange(of: FormatSettingsView.Presentation.shared.encodingListRequestID) { _, newValue in
            if newValue != nil {
                self.isEncodingListPresented = true
            }
        }
    }
    
    
    private var encodingPriorityDrillDown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    self.isEncodingListPresented = false
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(AppLanguage.text("返回编辑设置", en: "Back to Editing"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            SettingsGroupCard(title: AppLanguage.text("编码优先顺序", en: "Encoding Priority")) {
                EncodingListView(defaultEncoding: self.encodingManager.defaultEncoding, isEmbeddedInline: true) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        self.isEncodingListPresented = false
                    }
                }
            }
        }
    }
    
    
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            self.vimAndDisplayCard
            self.indentationCard
            self.contentHelpersCard
            self.documentFormatCard
            self.encodingDetectionCard
        }
    }
    
    
    private var vimAndDisplayCard: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("Vim 模态编辑", en: "Vim Modal Editing")) {
                SettingsItemRow(label: AppLanguage.text("启用 Vim 模式", en: "Enable Vim Mode")) {
                    Toggle("", isOn: self.$vimMode).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("视图辅助", en: "View Guides")) {
                SettingsItemRow(label: AppLanguage.text("显示行号", en: "Show Line Numbers")) {
                    Toggle("", isOn: self.$showLineNumbers).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: AppLanguage.text("自动换行", en: "Wrap Lines")) {
                    Toggle("", isOn: self.$wrapLines).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: AppLanguage.text("高亮当前行", en: "Highlight Current Line")) {
                    Toggle("", isOn: self.$highlightCurrentLine).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: AppLanguage.text("显示缩进参考线", en: "Show Indent Guides")) {
                    Toggle("", isOn: self.$showIndentGuides).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: AppLanguage.text("显示不可见字符", en: "Show Invisibles")) {
                    Toggle("", isOn: self.$showInvisibles).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }
    
    
    private var indentationCard: some View {
        SettingsGroupCard(title: AppLanguage.text("缩进规则", en: "Indentation")) {
            SettingsItemRow(label: AppLanguage.text("缩进方式", en: "Indent Style")) {
                Picker("", selection: self.$autoExpandTab) {
                    Text(AppLanguage.text("空格", en: "Spaces")).tag(true)
                    Text("Tab").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: SettingsDesignTokens.segmentedWidth)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("缩进宽度", en: "Tab Width")) {
                StepperNumberField(value: self.$tabWidth, default: 4, in: 1...99)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("输入时自动缩进", en: "Auto Indent")) {
                Toggle("", isOn: self.$autoIndent).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("按 Tab 缩进选区", en: "Indent Selection with Tab")) {
                Toggle("", isOn: self.$indentWithTabKey).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }
    
    
    private var contentHelpersCard: some View {
        SettingsGroupCard(title: AppLanguage.text("内容辅助", en: "Content Assistance")) {
            SettingsItemRow(label: AppLanguage.text("自动清除行尾空白", en: "Trim Trailing Whitespace")) {
                Toggle("", isOn: self.$autoTrimsTrailingWhitespace).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("高亮匹配括号", en: "Highlight Matching Braces")) {
                Toggle("", isOn: self.$highlightBraces).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("高亮相同选词", en: "Highlight Same Words")) {
                Toggle("", isOn: self.$highlightSelectionInstance).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("纯文本 / Markdown 内嵌贴图", en: "Inline Plain-Text Images")) {
                Toggle("", isOn: self.$plainTextImagesEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.plainTextImagesEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                    }
            }
        }
    }
    
    
    private var documentFormatCard: some View {
        SettingsGroupCard(title: AppLanguage.text("文档格式", en: "Document Format")) {
            SettingsItemRow(label: AppLanguage.text("默认换行符", en: "Line Ending")) {
                Picker("", selection: self.$lineEnding) {
                    ForEach(LineEnding.allCases.filter(\.isBasic), id: \.self) {
                        Text(verbatim: "\($0.description) (\($0.label))").tag($0.index)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("默认编码", en: "Default Encoding")) {
                Picker("", selection: self.fileEncoding) {
                    ForEach(Array(self.encodingManager.fileEncodings.enumerated()), id: \.offset) { _, enc in
                        if let enc {
                            Text(enc.localizedName).tag(enc)
                        } else {
                            Divider()
                        }
                    }
                }
                .labelsHidden()
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("默认语法", en: "Default Syntax")) {
                Picker("", selection: self.$syntax) {
                    Text(AppLanguage.text("无", en: "None")).tag(SyntaxName.none)
                    Divider()
                    ForEach(self.syntaxNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
            }
        }
    }
    
    
    private var encodingDetectionCard: some View {
        SettingsGroupCard(title: AppLanguage.text("编码识别", en: "Encoding Detection")) {
            SettingsItemRow(label: AppLanguage.text("识别文档内编码声明", en: "Refer to Encoding Tag")) {
                Toggle("", isOn: self.$referToEncodingTag).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            SettingsRowDivider()
            SettingsItemRow(label: AppLanguage.text("编码优先顺序", en: "Encoding Priority")) {
                Button(AppLanguage.text("调整顺序", en: "Edit Order")) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                        self.isEncodingListPresented = true
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
