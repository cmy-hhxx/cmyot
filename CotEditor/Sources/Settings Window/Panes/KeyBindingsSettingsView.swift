//
//  KeyBindingsSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2014-08-20.
//
//  ---------------------------------------------------------------------------
//
//  © 2014-2026 1024jp
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
import AppKit
import OSLog
import Shortcut

struct KeyBindingsSettingsView: View {
    
    var usesFlexibleFrame: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var model = KeyBindingModel()
    @State private var searchText: String = ""
    @State private var onlyModified: Bool = false
    @State private var hoveredMenuIndex: Int?
    @FocusState private var isSearchFocused: Bool
    
    
    var body: some View {
        let _ = self.model.revision
        let isDark = (self.colorScheme == .dark)
        let palette = self.studioPalette.tokens(isDark: isDark)
        let accent = palette.accent
        let onAccent = palette.onAccentInk
        let isGlobalList = !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || self.onlyModified
        let displayedRows = self.model.rows(searchText: self.searchText, onlyModified: self.onlyModified)
        let modifiedTotal = self.model.modifiedCount
        let sidePad: CGFloat = self.usesFlexibleFrame ? 24 : 20
        
        VStack(spacing: 0) {
            // Zone 1: Top Search & Filter Bar (aligned to 24pt Settings header axis)
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    TextField(AppLanguage.text("搜索命令或快捷键", en: "Search commands or shortcuts"), text: self.$searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused(self.$isSearchFocused)
                    
                    if !self.searchText.isEmpty {
                        Button {
                            self.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(self.colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            self.isSearchFocused
                                ? accent.opacity(0.65)
                                : Color.primary.opacity(self.colorScheme == .dark ? 0.12 : 0.08),
                            lineWidth: self.isSearchFocused ? 1.1 : 0.75
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture {
                    self.model.stopRecording()
                    self.isSearchFocused = true
                }
                
                HStack(spacing: 2) {
                    self.filterChip(
                        title: AppLanguage.text("全部", en: "All"),
                        isActive: !self.onlyModified
                    ) {
                        self.model.stopRecording()
                        self.onlyModified = false
                    }
                    self.filterChip(
                        title: modifiedTotal > 0
                            ? AppLanguage.text("已修改 \(modifiedTotal)", en: "Modified \(modifiedTotal)")
                            : AppLanguage.text("已修改", en: "Modified"),
                        isActive: self.onlyModified
                    ) {
                        self.model.stopRecording()
                        self.onlyModified = true
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05))
                )
            }
            .padding(.horizontal, sidePad)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            // Zone 2: Split Two-Pane Shortcut Browser & Instant Click-to-Record List
            HStack(spacing: 0) {
                if !isGlobalList {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(self.model.tree.enumerated()), id: \.offset) { idx, node in
                                let isSelected = ((self.model.rootIndex ?? 0) == idx)
                                let isHovered = (self.hoveredMenuIndex == idx)
                                let hasModified = self.model.menuHasModified(at: idx)
                                let menuTitle = KeyBindingModel.localizedMenuTitle(node.name)
                                
                                Button {
                                    self.model.stopRecording()
                                    self.model.rootIndex = idx
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(menuTitle)
                                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? onAccent : Color.primary.opacity(0.88))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 2)
                                        if hasModified {
                                            Circle()
                                                .fill(isSelected ? onAccent.opacity(0.90) : accent)
                                                .frame(width: 5.5, height: 5.5)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(minHeight: 32)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? accent
                                                    : (isHovered ? Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.055) : Color.clear)
                                            )
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                .onHover { inside in
                                    if inside {
                                        self.hoveredMenuIndex = idx
                                    } else if self.hoveredMenuIndex == idx {
                                        self.hoveredMenuIndex = nil
                                    }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(width: 148)
                    .background(Color.primary.opacity(self.colorScheme == .dark ? 0.035 : 0.025))
                    
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 0.75)
                }
                
                // Command List
                if displayedRows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: self.onlyModified ? "keyboard" : "magnifyingglass")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(
                            self.onlyModified
                                ? AppLanguage.text("暂无自定义快捷键", en: "No Customized Shortcuts")
                                : AppLanguage.text("没有匹配的命令", en: "No Matching Commands")
                        )
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(displayedRows) { row in
                                KeyBindingCommandRowView(
                                    row: row,
                                    showMenuPrefix: isGlobalList,
                                    accent: accent,
                                    onAccent: onAccent,
                                    model: self.model
                                )
                                Rectangle()
                                    .fill(Color.primary.opacity(self.colorScheme == .dark ? 0.06 : 0.05))
                                    .frame(height: 0.5)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(self.colorScheme == .dark ? 0.11 : 0.08), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, sidePad)
            
            // Zone 3: Elevated Unclipped Footer Action Bar (comfortably inset above bottom window edge)
            HStack(spacing: 10) {
                Button {
                    self.model.stopRecording()
                    self.model.restore()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text(AppLanguage.text("恢复默认", en: "Restore Defaults"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(self.model.isRestorable ? Color.primary.opacity(0.88) : Color.secondary.opacity(0.55))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                self.model.isRestorable
                                    ? (self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                                    : Color.primary.opacity(0.03)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(self.model.isRestorable ? 0.14 : 0.06),
                                lineWidth: 0.75
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!self.model.isRestorable)
                .pointerStyle(self.model.isRestorable ? .link : .default)
                
                if let error = self.model.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error.localizedDescription)
                            .font(.system(size: 11.5, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.10), in: Capsule())
                } else if self.model.recordingItemID != nil {
                    Text(AppLanguage.text("直接按下组合键 · Esc 取消 · Delete 清除", en: "Press shortcut · Esc to cancel · Delete to clear"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 6)
                
                HelpLink(anchor: "settings_keybindings")
            }
            .padding(.horizontal, sidePad)
            .padding(.top, 10)
            .padding(.bottom, self.usesFlexibleFrame ? 14 : 12)
        }
        .onAppear {
            self.model.load()
        }
        .onDisappear {
            self.model.stopRecording()
        }
        .onChange(of: self.isSearchFocused) { _, focused in
            if focused {
                self.model.stopRecording()
            }
        }
        .onChange(of: self.searchText) { _, _ in
            self.model.stopRecording()
        }
        .frame(
            width: self.usesFlexibleFrame ? nil : SettingsPaneLayout.width,
            height: self.usesFlexibleFrame ? nil : SettingsPaneLayout.height
        )
        .frame(
            maxWidth: self.usesFlexibleFrame ? .infinity : nil,
            maxHeight: self.usesFlexibleFrame ? .infinity : nil
        )
        .environment(\.locale, AppLanguage.current.locale)
    }
    
    
    private func filterChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? (self.colorScheme == .dark ? Color.white.opacity(0.14) : Color.white) : Color.clear)
                        .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 1.5, y: 0.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}


private struct KeyBindingCommandRowView: View {
    
    let row: KeyBindingModel.FlattenedCommandRow
    let showMenuPrefix: Bool
    let accent: Color
    let onAccent: Color
    @Bindable var model: KeyBindingModel
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    
    var body: some View {
        let currentShortcut = self.row.item.shortcut
        let defaultShortcut = self.row.item.defaultShortcut
        let isModified = (currentShortcut != defaultShortcut)
        let isRecording = self.model.isRecording(self.row.item)
        let localizedMenu = KeyBindingModel.localizedMenuTitle(self.row.menuName)
        let localizedSubmenu = self.row.submenuPath.map { KeyBindingModel.localizedSubmenuPath($0) }
        let breadcrumb = self.showMenuPrefix
            ? (localizedSubmenu.map { "\(localizedMenu) › \($0)" } ?? localizedMenu)
            : localizedSubmenu
        
        let showReset = isModified && !isRecording
        let showClear = (currentShortcut != nil) && (self.isHovered || isModified) && !isRecording
        
        HStack(spacing: 8) {
            // Left full-width clickable area: clicking anywhere on the row starts/toggles recording immediately
            HStack(spacing: 6) {
                if let breadcrumb, !breadcrumb.isEmpty {
                    Text(breadcrumb)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Text(KeyBindingModel.localizedCommandTitle(self.row.commandTitle))
                    .font(.system(size: 12.5, weight: (isModified || isRecording) ? .semibold : .regular))
                    .foregroundStyle(isRecording ? self.accent : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                self.model.toggleRecording(self.row.item)
            }
            
            // Fixed-width trailing utility slot so hovering NEVER shifts the shortcut recorder pill
            HStack(spacing: 4) {
                Button {
                    self.model.stopRecording()
                    self.model.updateShortcut(defaultShortcut, for: self.row.item)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.07), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .opacity(showReset ? 1 : 0)
                .allowsHitTesting(showReset)
                .help(AppLanguage.text("恢复此项默认", en: "Reset Shortcut"))
                
                Button {
                    self.model.stopRecording()
                    self.model.updateShortcut(nil, for: self.row.item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .opacity(showClear ? 1 : 0)
                .allowsHitTesting(showClear)
                .help(AppLanguage.text("清除快捷键", en: "Clear Shortcut"))
            }
            .frame(width: 52, alignment: .trailing)
            
            // Generous, single-click Shortcut Recorder Pill with unmistakable active recording state
            Button {
                self.model.toggleRecording(self.row.item)
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Circle()
                            .fill(self.accent)
                            .frame(width: 6, height: 6)
                        Text(AppLanguage.text("按下快捷键", en: "Type keys"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(self.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let symbol = currentShortcut?.symbol, !symbol.isEmpty {
                        Text(symbol)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(isModified ? self.accent : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(AppLanguage.text("点击设置", en: "Set Shortcut"))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary.opacity(self.isHovered ? 0.90 : 0.60))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 8)
                .frame(minWidth: 122, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isRecording
                                ? self.accent.opacity(self.colorScheme == .dark ? 0.22 : 0.13)
                                : (isModified
                                    ? self.accent.opacity(self.colorScheme == .dark ? 0.15 : 0.09)
                                    : Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isRecording
                                ? self.accent
                                : (isModified
                                    ? self.accent.opacity(0.55)
                                    : Color.primary.opacity(self.isHovered ? 0.24 : (self.colorScheme == .dark ? 0.14 : 0.10))),
                            lineWidth: isRecording ? 1.5 : (isModified ? 1.0 : 0.75)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 38)
        .background(
            isRecording
                ? self.accent.opacity(self.colorScheme == .dark ? 0.09 : 0.05)
                : (self.isHovered ? Color.primary.opacity(self.colorScheme == .dark ? 0.055 : 0.035) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            if inside != self.isHovered {
                self.isHovered = inside
            }
        }
    }
}


@MainActor @Observable final class KeyBindingModel {
    
    typealias Item = Node<KeyBindingItem>
    
    struct FlattenedCommandRow: Identifiable {
        let id: String
        let menuIndex: Int
        let menuName: String
        let submenuPath: String?
        let commandTitle: String
        let item: KeyBindingItem
    }
    
    private(set) var tree: [Item] = []
    private(set) var isRestorable: Bool = false
    private(set) var revision: Int = 0
    private(set) var recordingItemID: ObjectIdentifier?
    var error: (any Error)?
    
    var rootIndex: Int?
    
    private let manager: KeyBindingManager = .shared
    @ObservationIgnored private var recordingItem: KeyBindingItem?
    @ObservationIgnored private var keyDownMonitor: Any?
    
    
    isolated deinit {
        if let monitor = self.keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    
    func isRecording(_ item: KeyBindingItem) -> Bool {
        self.recordingItemID == ObjectIdentifier(item)
    }
    
    
    func toggleRecording(_ item: KeyBindingItem) {
        if self.isRecording(item) {
            self.stopRecording()
        } else {
            self.startRecording(item)
        }
    }
    
    
    func startRecording(_ item: KeyBindingItem) {
        self.stopRecording()
        // Dismiss any active search field focus so keystrokes go straight to the recorder
        NSApp.keyWindow?.makeFirstResponder(nil)
        self.error = nil
        self.recordingItem = item
        self.recordingItemID = ObjectIdentifier(item)
        
        self.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleRecordedKeyEvent(event) ? nil : event
        }
    }
    
    
    func stopRecording() {
        if let monitor = self.keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            self.keyDownMonitor = nil
        }
        self.recordingItem = nil
        if self.recordingItemID != nil {
            self.recordingItemID = nil
        }
    }
    
    
    @discardableResult
    func handleRecordedKeyEvent(_ event: NSEvent) -> Bool {
        guard let item = self.recordingItem else { return false }
        let cleanModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        
        // Single Escape cancels recording without modifying shortcut (even under IME)
        if event.keyCode == 53, cleanModifiers.isEmpty {
            self.error = nil
            self.stopRecording()
            return true
        }
        
        // Single Delete / Backspace clears shortcut (even under IME)
        if (event.specialKey == .delete || event.specialKey == .backspace || event.keyCode == 51 || event.keyCode == 117),
           cleanModifiers.isEmpty
        {
            self.updateShortcut(nil, for: item)
            self.stopRecording()
            return true
        }
        
        guard let shortcut = Shortcut(keyDownEvent: event) else { return true }
        
        // Pressing the exact same shortcut keeps it and ends recording cleanly
        if shortcut == item.shortcut {
            self.error = nil
            self.stopRecording()
            return true
        }
        
        do {
            try shortcut.checkCustomizationAvailability(for: NSApp.mainMenu)
        } catch {
            self.error = error
            NSSound.beep()
            return true
        }
        
        self.updateShortcut(shortcut, for: item)
        self.stopRecording()
        return true
    }
    
    
    /// Loads data from the user defaults.
    func load() {
        
        self.tree = self.manager.menuTree
        if self.rootIndex == nil && !self.tree.isEmpty {
            self.rootIndex = 0
        }
        self.isRestorable = self.manager.isCustomized
        self.revision &+= 1
    }
    
    
    /// Restores key binding setting to default.
    func restore() {
        
        try? self.manager.restoreDefaults()
        
        self.tree = self.manager.menuTree
        self.isRestorable = false
        self.error = nil
        self.revision &+= 1
    }
    
    
    func updateShortcut(_ shortcut: Shortcut?, for item: KeyBindingItem) {
        self.error = nil
        guard item.shortcut != shortcut else { return }
        item.shortcut = shortcut
        self.save()
        self.revision &+= 1
    }
    
    
    /// Saves the current settings.
    func save() {
        guard !self.tree.isEmpty else { return }
        
        do {
            try self.manager.save(tree: self.tree)
        } catch {
            Logger.app.error("\(error.localizedDescription)")
        }
        
        self.isRestorable = self.manager.isCustomized
    }
    
    
    static func localizedMenuTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppLanguage.current == .simplifiedChinese else {
            return trimmed.replacingOccurrences(of: "CoTEditor", with: "CotEditor")
        }
        switch trimmed.lowercased() {
            case "coteditor": return "CotEditor"
            case "file": return "文件"
            case "edit": return "编辑"
            case "format": return "格式"
            case "view": return "视图"
            case "text": return "文本"
            case "find": return "查找"
            case "weekly report", "weekly reports": return "周报"
            case "script", "scripts": return "脚本"
            case "window": return "窗口"
            case "help": return "帮助"
            default: return trimmed.replacingOccurrences(of: "CoTEditor", with: "CotEditor")
        }
    }
    
    
    private static let zhCommandTable: [String: String] = [
        "about coteditor": "关于 CotEditor",
        "about scripting": "关于脚本",
        "add to tab bar": "添加到标签栏",
        "advanced character count…": "高级字数统计…",
        "ai organize & merge all documents…": "AI 一键整理合并所有文档…",
        "align markdown table": "一键对齐表格",
        "antialias": "抗锯齿",
        "appearance": "外观",
        "applescript dictionary": "AppleScript 词典",
        "bigger": "增大字号",
        "bigger font": "增大字号",
        "block comment": "块注释",
        "braces": "大括号",
        "brackets": "方括号",
        "bring all to front": "前置全部窗口",
        "capitalize": "首字母大写",
        "check document now": "立即检查文稿",
        "check for updates…": "检查更新…",
        "check grammar with spelling": "检查拼写和语法",
        "check spelling while typing": "输入时检查拼写",
        "clear highlight": "清除高亮",
        "clear menu": "清除菜单",
        "close": "关闭",
        "close all": "全部关闭",
        "close split editor": "关闭分栏",
        "close tab": "关闭标签页",
        "close window": "关闭窗口",
        "comment": "注释",
        "complete": "代码补全",
        "console": "控制台",
        "convert alphanumeric text to full width": "将字母数字转换为全角",
        "convert alphanumeric text to half width": "将字母数字转换为半角",
        "convert indentation to spaces": "将缩进转换为空格",
        "convert indentation to tabs": "将缩进转换为制表符",
        "convert to full width": "转换为全角",
        "convert to half width": "转换为半角",
        "copy": "拷贝",
        "copy as rich text": "以多信息文本拷贝",
        "copy file path": "拷贝文件路径",
        "correct spelling automatically": "自动纠正拼写",
        "coteditor help": "CotEditor 帮助",
        "coteditor scripting guide": "CotEditor 脚本手册",
        "coteditor web site": "CotEditor 网站",
        "create issue report": "创建问题报告",
        "custom…": "自定义…",
        "customize toolbar…": "自定工具栏…",
        "cut": "剪切",
        "dark": "深色",
        "delete": "删除",
        "delete duplicates": "删除重复行",
        "delete line": "删除行",
        "direction": "方向",
        "document inspector": "文稿信息",
        "documents": "文档中心",
        "double quotes": "双引号",
        "duplicate": "复制文档",
        "duplicate line": "复制行",
        "edit": "编辑",
        "edit color code…": "编辑颜色代码…",
        "edit snippets…": "编辑代码片段…",
        "enter full screen": "进入全屏",
        "export…": "导出…",
        "export settings…": "导出设置…",
        "file": "文件",
        "file browser": "文件浏览器",
        "find": "查找",
        "find all": "全部查找",
        "find next": "查找下一个",
        "find previous": "查找上一个",
        "find…": "查找…",
        "font": "字体",
        "font type": "字体类型",
        "format": "格式",
        "generate weekly report…": "生成本周周报（说人话版）…",
        "go to line…": "跳转到行…",
        "help": "帮助",
        "hide coteditor": "隐藏 CotEditor",
        "hide others": "隐藏其他",
        "hide toolbar": "隐藏工具栏",
        "highlight all": "全部高亮",
        "horizontal": "横排",
        "import settings…": "导入设置…",
        "import weekly reports (.zip / folder)…": "导入历史周报 (.zip / 文件夹)…",
        "indentation": "缩进",
        "inline comment": "行注释",
        "insert backslash": "输入反斜杠",
        "insert by unicode code point…": "Unicode 码位输入…",
        "insert image (plain text)…": "嵌入图片…",
        "insert snippet": "插入片段",
        "insert yen mark": "输入日元符号",
        "inspect character": "检视字符",
        "inspector": "检查器",
        "join lines": "合并行",
        "jump to selection": "跳到所选内容",
        "keep on top": "窗口置顶",
        "left to right": "从左到右",
        "ligatures": "连字",
        "light": "浅色",
        "line endings": "换行符",
        "lines": "行",
        "make lower case": "变为小写",
        "make upper case": "变为大写",
        "manage multiple replace…": "管理批量替换…",
        "minimize": "最小化",
        "monospaced": "等宽",
        "move down": "下移",
        "move focus to next editor": "焦点移至下一分栏",
        "move focus to previous editor": "焦点移至上一分栏",
        "move tab to new window": "移动标签页到新窗口",
        "move up": "上移",
        "multiple replace": "批量替换",
        "multiple replace…": "批量替换…",
        "new": "新建",
        "new document": "新建文稿",
        "new tab": "新建标签页",
        "new window": "新建窗口",
        "open ai settings": "打开 AI 设置",
        "open outline menu": "打开大纲菜单",
        "open recent": "打开最近使用",
        "open weekly report center…": "打开周报中心（历史与生成）…",
        "open…": "打开…",
        "organize & merge all tabs + map…": "一键整理合并全部文档…",
        "orientation": "排版方向",
        "outline": "大纲",
        "page setup…": "页面设置…",
        "parentheses": "圆括号",
        "paste": "粘贴",
        "paste and match style": "粘贴并匹配样式",
        "paste exactly": "精确粘贴",
        "pin tab": "固定标签页",
        "prevent editing": "锁定编辑",
        "print…": "打印…",
        "quit coteditor": "退出 CotEditor",
        "redo": "重做",
        "release notes": "发布说明",
        "remove highlights": "移除高亮标记",
        "rename…": "重新命名…",
        "replace": "替换",
        "replace all": "全部替换",
        "replace and find": "替换并查找",
        "replace and find next": "替换并查找下一个",
        "replace dashes": "替换破折号",
        "replace quotes": "替换引号",
        "replace text": "替换文本",
        "report issue": "报告问题",
        "reports": "周报中心",
        "reset font size": "重置字号",
        "reset syntax analysis": "重置语法分析",
        "reset text size": "重置文字大小",
        "reverse": "逆序排列",
        "revert to saved": "复原到已存储状态",
        "right to left": "从右到左",
        "save": "存储",
        "save all": "全部存储",
        "save as…": "存储为…",
        "script": "脚本",
        "select": "选择",
        "select all": "全选",
        "select all find matches": "选择全部查找匹配项",
        "select column down": "向下选择列",
        "select column up": "向上选择列",
        "select enclosing symbols": "选择括号内内容",
        "select line": "选择整行",
        "select next outline item": "选择下一个大纲项",
        "select previous outline item": "选择上一个大纲项",
        "select word": "选择词组",
        "services": "服务",
        "settings…": "设置…",
        "share…": "共享…",
        "shift left": "左移缩进",
        "shift right": "右移缩进",
        "show all": "全部显示",
        "show fonts": "显示字体",
        "show in finder": "在访达中显示",
        "show indent guides": "显示缩进参考线",
        "show inspector": "切换检查器",
        "show invisibles": "显示不可见字符",
        "show line numbers": "显示行号",
        "show navigation bar": "显示导航栏",
        "show page guide": "显示页面参考线",
        "show quick actions…": "显示快速操作…",
        "show sidebar": "显示边栏",
        "show spelling and grammar": "显示拼写和语法",
        "show status bar": "显示状态栏",
        "show substitutions": "显示替换",
        "show tab bar": "显示标签栏",
        "shuffle": "随机排列",
        "sidebar": "边栏",
        "single quotes": "单引号",
        "smaller": "减小字号",
        "smaller font": "减小字号",
        "smart copy/paste": "智能拷贝/粘贴",
        "smart dashes": "智能破折号",
        "smart quotes": "智能引号",
        "sort": "排序",
        "sort by pattern…": "按规则排序…",
        "speech": "语音",
        "spelling": "拼写",
        "spelling and grammar": "拼写和语法",
        "split bottom": "向下分屏",
        "split down": "向下分栏",
        "split editor": "分栏编辑",
        "split left": "向左分屏",
        "split right": "向右分屏",
        "split selection by lines": "按行拆分选区",
        "split top": "向上分屏",
        "stack editors vertically": "纵向分栏排列",
        "standard": "标准",
        "start speaking": "开始朗读",
        "stop speaking": "停止朗读",
        "straighten quotes": "直引号",
        "substitutions": "替换",
        "surround selection with": "包裹选中内容",
        "syntax": "语法",
        "system": "跟随系统",
        "tab width": "制表符宽度",
        "terminal": "终端",
        "text": "文本",
        "text encoding": "文本编码",
        "text replacement": "文本替换",
        "text size": "文字大小",
        "text size (continuous)": "文字大小（无极）",
        "theme": "主题",
        "tile two windows": "并排两个窗口",
        "toggle comment": "切换注释",
        "toggle inspector": "切换检查器",
        "toggle split orientation": "切换分栏方向",
        "transformations": "大小写转换",
        "trim trailing whitespace": "移除行尾空白",
        "uncomment": "取消注释",
        "undo": "撤销",
        "unicode normalizations": "Unicode 标准化",
        "unpin tab": "取消固定标签页",
        "url decode": "URL 解码",
        "url encode": "URL 编码",
        "use selection for find": "查找所选内容",
        "use selection for replace": "替换所选内容",
        "use spaces for indentation": "使用空格缩进",
        "vertical": "竖排",
        "view": "视图",
        "warnings": "警告",
        "weekly reports": "周报",
        "what’s new in coteditor": "CotEditor 新功能",
        "what's new in coteditor": "CotEditor 新功能",
        "window": "窗口",
        "wrap lines": "自动换行",
        "writing direction": "书写方向",
        "zoom": "缩放",
    ]
    
    
    static func localizedCommandTitle(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "CoTEditor", with: "CotEditor")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppLanguage.current == .simplifiedChinese else { return normalized }
        
        let key = normalized
            .replacingOccurrences(of: "...", with: "…")
            .lowercased()
        
        return Self.zhCommandTable[key] ?? normalized
    }
    
    
    static func localizedSubmenuPath(_ rawPath: String) -> String {
        rawPath
            .components(separatedBy: " › ")
            .map { Self.localizedCommandTitle($0) }
            .joined(separator: " › ")
    }
    
    
    var modifiedCount: Int {
        self.allFlattenedRows().count { $0.item.shortcut != $0.item.defaultShortcut }
    }
    
    
    func menuHasModified(at index: Int) -> Bool {
        guard self.tree.indices.contains(index) else { return false }
        return self.tree[index].flatValues.contains { $0.shortcut != $0.defaultShortcut }
    }
    
    
    func rows(searchText: String, onlyModified: Bool) -> [FlattenedCommandRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isGlobal = !trimmed.isEmpty || onlyModified
        let sourceRows: [FlattenedCommandRow] = if isGlobal {
            self.allFlattenedRows()
        } else {
            self.flattenedRows(forMenuAt: self.rootIndex ?? 0)
        }
        
        return sourceRows.filter { row in
            if onlyModified && row.item.shortcut == row.item.defaultShortcut {
                return false
            }
            if !trimmed.isEmpty {
                let hay = [
                    row.menuName,
                    Self.localizedMenuTitle(row.menuName),
                    row.submenuPath ?? "",
                    row.submenuPath.map { Self.localizedSubmenuPath($0) } ?? "",
                    row.commandTitle,
                    Self.localizedCommandTitle(row.commandTitle),
                    row.item.shortcut?.symbol ?? "",
                    row.item.defaultShortcut?.symbol ?? "",
                ].joined(separator: " ").lowercased()
                return hay.contains(trimmed)
            }
            return true
        }
    }
    
    
    private func allFlattenedRows() -> [FlattenedCommandRow] {
        self.tree.indices.flatMap { self.flattenedRows(forMenuAt: $0) }
    }
    
    
    private func flattenedRows(forMenuAt menuIndex: Int) -> [FlattenedCommandRow] {
        guard self.tree.indices.contains(menuIndex) else { return [] }
        let rootNode = self.tree[menuIndex]
        var result: [FlattenedCommandRow] = []
        
        func walk(_ node: Item, trail: [String]) {
            switch node.item {
                case .value(let item):
                    let path = trail.isEmpty ? nil : trail.joined(separator: " › ")
                    let rowID = "\(menuIndex):\(path ?? ""):\(node.name):\(item.action.description):\(item.tag):\(result.count)"
                    result.append(FlattenedCommandRow(
                        id: rowID,
                        menuIndex: menuIndex,
                        menuName: rootNode.name,
                        submenuPath: path,
                        commandTitle: node.name,
                        item: item
                    ))
                case .children(let children):
                    let nextTrail = trail + [node.name]
                    for child in children {
                        walk(child, trail: nextTrail)
                    }
            }
        }
        
        if let topChildren = rootNode.children {
            for child in topChildren {
                walk(child, trail: [])
            }
        }
        return result
    }
}


private struct KeyBindingTreeView: NSViewControllerRepresentable {
    
    typealias NSViewControllerType = NSViewController
    
    
    @Binding var model: KeyBindingModel
    
    
    func makeNSViewController(context: Context) -> NSViewController {
        
        NSStoryboard(name: "KeyBindingTreeView", bundle: nil).instantiateInitialController { coder in
            KeyBindingTreeViewController(model: self.model, coder: coder)
        }!
    }
    
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        
    }
}


// MARK: -

/// Column identifiers for outline view.
private extension NSUserInterfaceItemIdentifier {
    
    static let command = NSUserInterfaceItemIdentifier("command")
    static let key = NSUserInterfaceItemIdentifier("key")
}


final class KeyBindingTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    
    // MARK: Private Properties
    
    private let model: KeyBindingModel
    
    @IBOutlet private weak var listView: NSTableView?
    @IBOutlet private weak var outlineView: NSOutlineView?
    
    
    // MARK: Lifecycle
    
    fileprivate init?(model: KeyBindingModel, coder: NSCoder) {
        
        self.model = model
        
        super.init(coder: coder)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.listView?.rowSizeStyle = .medium
        self.outlineView?.rowSizeStyle = .medium
    }
    
    
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.listView?.reloadData()
        self.outlineView?.reloadData()
        
        self.observe()
    }
    
    
    // MARK: Outline View Data Source
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        
        if let node = item as? Node<KeyBindingItem> {
            node.children?.count ?? 0
        } else if let rootIndex = self.model.rootIndex, rootIndex >= 0 {
            self.model.tree[rootIndex].children?.count ?? 0
        } else {
            0
        }
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        
        (item as? Node<KeyBindingItem>)?.children != nil
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        
        if let node = item as? Node<KeyBindingItem> {
            node.children![index]
        } else if let rootIndex = self.model.rootIndex {
            self.model.tree[rootIndex].children![index]
        } else {
            preconditionFailure()
        }
    }
    
    
    // MARK: Outline View Delegate
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        
        guard
            let node = item as? Node<KeyBindingItem>,
            let identifier = tableColumn?.identifier,
            let cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        else { return nil }
        
        switch identifier {
            case .command:
                cellView.objectValue = node.name
                
            case .key:
                switch node.item {
                    case .value(let item):
                        cellView.objectValue = item.shortcut
                        cellView.textField?.placeholderString = item.defaultShortcut?.symbol
                        
                    case .children:
                        cellView.textField?.isEditable = false
                }
                
            default:
                preconditionFailure()
        }
        
        return cellView
    }
    
    
    // MARK: Action Messages
    
    /// Validates and apply new shortcut key input.
    @IBAction func didEditShortcut(_ sender: ShortcutTextField) {
        
        guard let outlineView = self.outlineView else { return assertionFailure() }
        
        let row = outlineView.row(for: sender)
        let column = outlineView.column(for: sender)
        
        guard
            let node = outlineView.item(atRow: row) as? Node<KeyBindingItem>,
            let item = node.value
        else { return }
        
        let oldShortcut = item.shortcut
        let shortcut = sender.objectValue as? Shortcut
        
        // reset once warning
        self.model.error = nil
        
        // not edited
        guard shortcut != oldShortcut else { return }
        
        if let shortcut {
            do {
                try shortcut.checkCustomizationAvailability(for: NSApp.mainMenu)
            } catch {
                self.model.error = error
                sender.objectValue = oldShortcut  // reset text field
                NSSound.beep()
                
                // make text field edit mode again
                Task {
                    outlineView.editColumn(column, row: row, with: nil, select: true)
                }
                return
            }
        }
        
        // successfully update data
        item.shortcut = shortcut
        self.model.save()
        outlineView.reloadData(forRowIndexes: [row], columnIndexes: [column])
    }
    
    
    // MARK: Private Methods
    
    /// Recursively observes the `.isRestorable` flag.
    private func observe() {
        
        withObservationTracking {
            if self.model.isRestorable == false {
                self.outlineView?.reloadData()
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
            }
        }
    }
}


extension KeyBindingTreeViewController: NSTableViewDataSource, NSTableViewDelegate {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        
        self.model.tree.count
    }
    
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        
        self.model.tree[row].name
    }
    
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        
        guard let tableView = notification.object as? NSTableView else { return }
        
        tableView.window?.makeFirstResponderDiscardingMarkedText(nil)
        self.model.rootIndex = tableView.selectedRow
        self.outlineView?.reloadData()
    }
}


// MARK: - Preview

#Preview {
    KeyBindingsSettingsView()
}
