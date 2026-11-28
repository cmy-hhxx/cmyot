//
//  SidebarTypographySettingsPane.swift
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

import AppKit
import Defaults
import SwiftUI

@MainActor
private enum SidebarArchivedFontCache {
    
    private static var lastStandard: (data: Data, font: NSFont)?
    private static var lastMonospaced: (data: Data, font: NSFont)?
    static let allFamilies: [String] = NSFontManager.shared.availableFontFamilies
    static let monospacedFamilies: [String] = {
        let manager = NSFontManager.shared
        return allFamilies.filter { fam in
            guard let font = NSFont(name: fam, size: 12) else { return false }
            return font.isFixedPitch || manager.traits(of: font).contains(.fixedPitchFontMask)
        }
    }()
    
    static func decodeStandard(_ data: Data?) -> NSFont {
        guard let data else { return FontType.standard.systemFont() }
        if let cached = self.lastStandard, cached.data == data { return cached.font }
        let resolved = NSFont(archivedData: data) ?? FontType.standard.systemFont()
        self.lastStandard = (data, resolved)
        return resolved
    }
    
    static func decodeMonospaced(_ data: Data?) -> NSFont {
        guard let data else { return FontType.monospaced.systemFont() }
        if let cached = self.lastMonospaced, cached.data == data { return cached.font }
        let resolved = NSFont(archivedData: data) ?? FontType.monospaced.systemFont()
        self.lastMonospaced = (data, resolved)
        return resolved
    }
}


struct SidebarTypographySettingsPane: View {
    
    @AppStorage(.font) private var fontData
    @AppStorage(.shouldAntialias) private var shouldAntialias
    @AppStorage(.ligature) private var ligature
    
    @AppStorage(.monospacedFont) private var monospacedFontData
    @AppStorage(.monospacedShouldAntialias) private var monospacedShouldAntialias
    @AppStorage(.monospacedLigature) private var monospacedLigature
    
    @AppStorage(.lineHeight) private var lineHeight
    
    @State private var isChoosingStandardFont = false
    @State private var isChoosingMonospacedFont = false
    
    private var standardFont: Binding<NSFont> {
        Binding(
            get: { SidebarArchivedFontCache.decodeStandard(self.fontData) },
            set: { self.fontData = (try? $0.archivedData) ?? self.fontData }
        )
    }
    
    private var monospacedFont: Binding<NSFont> {
        Binding(
            get: { SidebarArchivedFontCache.decodeMonospaced(self.monospacedFontData) },
            set: { self.monospacedFontData = (try? $0.archivedData) ?? self.monospacedFontData }
        )
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("标准字体", en: "Standard Font")) {
                SettingsItemRow(label: AppLanguage.text("字体样式", en: "Font Family")) {
                    HStack(spacing: 8) {
                        Text("\(self.standardFont.wrappedValue.displayName ?? self.standardFont.wrappedValue.fontName) \(Int(self.standardFont.wrappedValue.pointSize))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        FontSizeStepper(AppLanguage.text("字号", en: "Size"), font: self.standardFont)
                        Button(self.isChoosingStandardFont ? AppLanguage.text("收起", en: "Done") : AppLanguage.text("选择字体", en: "Choose Font")) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.isChoosingStandardFont.toggle()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                
                if self.isChoosingStandardFont {
                    SettingsRowDivider()
                    InlineFontFamilySelector(selection: self.standardFont, preferMonospacedOnly: false)
                        .padding(12)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("字体抗锯齿", en: "Antialias Text")) {
                    Toggle("", isOn: self.$shouldAntialias)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("连字效果", en: "Enable Ligatures")) {
                    Toggle("", isOn: self.$ligature)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("等宽字体", en: "Monospaced Font")) {
                SettingsItemRow(label: AppLanguage.text("字体样式", en: "Font Family")) {
                    HStack(spacing: 8) {
                        Text("\(self.monospacedFont.wrappedValue.displayName ?? self.monospacedFont.wrappedValue.fontName) \(Int(self.monospacedFont.wrappedValue.pointSize))")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        FontSizeStepper(AppLanguage.text("字号", en: "Size"), font: self.monospacedFont)
                        Button(self.isChoosingMonospacedFont ? AppLanguage.text("收起", en: "Done") : AppLanguage.text("选择字体", en: "Choose Font")) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.isChoosingMonospacedFont.toggle()
                            }
                        }
                        .controlSize(.small)
                    }
                }
                
                if self.isChoosingMonospacedFont {
                    SettingsRowDivider()
                    InlineFontFamilySelector(selection: self.monospacedFont, preferMonospacedOnly: true)
                        .padding(12)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("等宽抗锯齿", en: "Antialias Monospaced")) {
                    Toggle("", isOn: self.$monospacedShouldAntialias)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("等宽连字", en: "Monospaced Ligatures")) {
                    Toggle("", isOn: self.$monospacedLigature)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("行距排版", en: "Line Spacing")) {
                SettingsItemRow(label: AppLanguage.text("行高倍数", en: "Line Height")) {
                    HStack(spacing: 8) {
                        Text(self.lineHeight, format: .number.precision(.fractionLength(1...2)))
                            .font(.system(size: 12.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Stepper(value: self.$lineHeight, in: 0.8...3.0, step: 0.1) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }
}


private struct InlineFontFamilySelector: View {
    
    @Binding var selection: NSFont
    let preferMonospacedOnly: Bool
    
    @State private var searchQuery = ""
    @State private var showAllFamilies: Bool
    
    init(selection: Binding<NSFont>, preferMonospacedOnly: Bool) {
        self._selection = selection
        self.preferMonospacedOnly = preferMonospacedOnly
        self._showAllFamilies = State(initialValue: !preferMonospacedOnly)
    }
    
    private var filteredFamilies: [String] {
        let pool = self.showAllFamilies
            ? SidebarArchivedFontCache.allFamilies
            : SidebarArchivedFontCache.monospacedFamilies
        let q = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return pool }
        return pool.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    
    var body: some View {
        let currentFamily = self.selection.familyName ?? self.selection.fontName
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(AppLanguage.text("搜索字体族", en: "Search fonts"), text: self.$searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                
                if self.preferMonospacedOnly {
                    Toggle(AppLanguage.text("显示全部字体", en: "All Fonts"), isOn: self.$showAllFamilies)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                }
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(self.filteredFamilies, id: \.self) { family in
                        let isSelected = (family == currentFamily)
                        Button {
                            let size = self.selection.pointSize
                            if let updated = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
                                self.selection = updated
                            }
                        } label: {
                            HStack {
                                Text(family)
                                    .font(.custom(family, size: 12.5))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .frame(minHeight: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 138)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
