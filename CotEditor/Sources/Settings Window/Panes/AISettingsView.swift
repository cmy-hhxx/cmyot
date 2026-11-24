//
//  AISettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-05.
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

import AppKit
import SwiftUI

/// The AI pane of the settings window.
///
/// Renders endpoints directly inside the grouped `Form` (no nested `List` scroll view)
/// so trackpad and mouse-wheel scrolling across the whole Settings window never traps or stalls.
struct AISettingsView: View {
    
    var body: some View {
        ScrollView {
            AIModelsSettingsView()
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: SettingsPaneLayout.width, height: SettingsPaneLayout.height)
        .environment(\.locale, AppLanguage.current.locale)
    }
}


// MARK: - Stored Documents & Custom Config Sheet

struct StoredDocumentsSheetView: View {
    
    var isEmbeddedInline: Bool = false
    var onDone: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var newConfigKey = ""
    @State private var newConfigValue = ""
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("本地 SQLite 数据库管理")
                    .font(self.isEmbeddedInline ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Picker("", selection: self.$selectedTab) {
                    Text("已存文档 (\(CotLocalDatabase.shared.documents.count))").tag(0)
                    Text("键值配置 (\(CotLocalDatabase.shared.configCount))").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: self.isEmbeddedInline ? 210 : 280)
            }
            
            if self.selectedTab == 0 {
                List {
                    ForEach(CotLocalDatabase.shared.documents) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .fontWeight(.medium)
                                Text("\(record.syntax) · \(record.content.count) 字 · \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("打开为新标签") {
                                _ = try? (NSDocumentController.shared as? DocumentController)?
                                    .openUntitledDocument(content: record.content, title: record.title, display: true)
                                if let onDone = self.onDone {
                                    onDone()
                                } else {
                                    self.dismiss()
                                }
                            }
                            .controlSize(.small)
                            
                            Button(role: .destructive) {
                                CotLocalDatabase.shared.deleteDocument(id: record.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(height: 260)
            } else {
                List {
                    ForEach(CotLocalDatabase.shared.configEntries) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .frame(width: 150, alignment: .leading)
                            Text(entry.value.count > 240 ? String(entry.value.prefix(240)) + "…" : entry.value)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(3)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                CotLocalDatabase.shared.removeConfig(forKey: entry.key)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .frame(height: 220)
                
                HStack(spacing: 8) {
                    TextField(text: self.$newConfigKey, prompt: Text("配置 Key (如 custom.signature)"), label: EmptyView.init)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 168)
                    TextField(text: self.$newConfigValue, prompt: Text("配置 Value"), label: EmptyView.init)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                    Button("写入 DB") {
                        let key = self.newConfigKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        CotLocalDatabase.shared.set(self.newConfigValue, forKey: key)
                        self.newConfigKey = ""
                        self.newConfigValue = ""
                    }
                    .disabled(self.newConfigKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            HStack {
                Text(CotLocalDatabase.shared.databaseURL.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer()
                Button("完成") {
                    if let onDone = self.onDone {
                        onDone()
                    } else {
                        self.dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(self.isEmbeddedInline ? 14 : 20)
        .frame(width: self.isEmbeddedInline ? nil : 600)
        .frame(maxWidth: self.isEmbeddedInline ? .infinity : nil)
        .environment(\.locale, AppLanguage.current.locale)
    }
}


// MARK: - Scroll-Passthrough Text Editor for Grouped Settings Forms

private final class PassthroughTextScrollView: NSScrollView {
    
    override func scrollWheel(with event: NSEvent) {
        
        guard let documentView = self.documentView else {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        let contentHeight = documentView.bounds.height
        let visibleHeight = self.contentView.bounds.height
        if contentHeight <= visibleHeight + 1 {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        let currentY = self.contentView.bounds.origin.y
        let maxY = max(0, contentHeight - visibleHeight)
        let atTop = currentY <= 0.5 && event.scrollingDeltaY > 0
        let atBottom = currentY >= maxY - 0.5 && event.scrollingDeltaY < 0
        if atTop || atBottom {
            self.nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}


private struct ScrollPassthroughTextEditor: NSViewRepresentable {
    
    @Binding var text: String
    var font: NSFont
    
    
    func makeCoordinator() -> Coordinator {
        
        Coordinator(self)
    }
    
    
    func makeNSView(context: Context) -> NSScrollView {
        
        let scrollView = PassthroughTextScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.font = self.font
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = self.text
        
        scrollView.documentView = textView
        return scrollView
    }
    
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != self.text {
            let selected = textView.selectedRange()
            textView.string = self.text
            let clampedLoc = min(selected.location, (self.text as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLoc, length: 0))
        }
        if textView.font != self.font {
            textView.font = self.font
        }
    }
    
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        
        var parent: ScrollPassthroughTextEditor
        
        init(_ parent: ScrollPassthroughTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
        }
    }
}


// MARK: - AI Persona & Stage Prompts Settings View

struct AIPersonaSettingsView: View {
    
    private struct PersonaPreset: Identifiable {
        let id: String
        let title: String
        let prompt: String
    }
    
    private static let personaPresets: [PersonaPreset] = [
        .init(id: "expert",
              title: "精炼技术专家",
              prompt: "严谨资深的系统工程师，回答直击本质、注重准确性与高信噪比，避免空话和冗余铺垫。"),
        .init(id: "weekly",
              title: "直白周报搭档",
              prompt: "高效务实的研发协作伙伴，善于把零散工作记录提炼为清晰、实在、不堆砌套话的周报总结。"),
        .init(id: "architect",
              title: "深度架构顾问",
              prompt: "擅长从边界设计、并发安全、可维护性与性能权衡角度审视方案的架构顾问，兼顾落地成本与长期演进。"),
        .init(id: "editor",
              title: "双语润色编辑",
              prompt: "兼具中文书面表达功底与英文技术术语准确性的编辑，善于梳理文档结构、消除翻译腔并提升可读性。"),
    ]
    
    @State private var personaText: String = ""
    @State private var selectedStageAction: AIAction = .weeklyReport
    @State private var stagePromptText: String = ""
    @State private var typewriterEnabled: Bool = true
    @State private var typewriterStyle: TypingEffectPreset = .powerMode
    @State private var vimCursorTrailEnabled: Bool = true
    @State private var plainTextImagesEnabled: Bool = true
    
    
    var body: some View {
        
        SettingsFormPane {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("快捷人设:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        ForEach(Self.personaPresets) { preset in
                            let isSelected = self.personaText.trimmingCharacters(in: .whitespacesAndNewlines) == preset.prompt
                            Button(preset.title) {
                                self.personaText = preset.prompt
                                CotLocalDatabase.shared.aiPersona = preset.prompt
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? .accentColor : nil)
                            .controlSize(.small)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer()
                        if !self.personaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("清空") {
                                self.personaText = ""
                                CotLocalDatabase.shared.aiPersona = ""
                            }
                            .controlSize(.small)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        ScrollPassthroughTextEditor(
                            text: self.$personaText,
                            font: .systemFont(ofSize: 12)
                        )
                        .frame(height: 76)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                        )
                        .onChange(of: self.personaText) { _, newValue in
                            guard newValue != CotLocalDatabase.shared.aiPersona else { return }
                            CotLocalDatabase.shared.aiPersona = newValue
                        }
                        
                        if self.personaText.isEmpty {
                            Text("输入自定义 AI 人设，例如：严谨架构师，所有输出保持分点简洁，优先给出可执行结论")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } header: {
                Label("AI 角色人设 (Persona)", systemImage: "person.text.rectangle")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Picker("", selection: self.$selectedStageAction) {
                            ForEach(AIAction.allCases, id: \.self) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: self.selectedStageAction) { _, newAction in
                            self.loadStagePrompt(for: newAction)
                        }
                        
                        let isCustomized = self.stagePromptText != self.selectedStageAction.defaultSystemPrompt
                        Text(isCustomized ? "已自定义" : "默认")
                            .font(.caption2)
                            .foregroundStyle(isCustomized ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill((isCustomized ? Color.accentColor : Color.secondary).opacity(0.12))
                            )
                        
                        Spacer()
                        
                        Button("恢复默认") {
                            let defaultPrompt = self.selectedStageAction.defaultSystemPrompt
                            self.stagePromptText = defaultPrompt
                            CotLocalDatabase.shared.set(defaultPrompt, forKey: self.selectedStageAction.databaseConfigKey)
                        }
                        .controlSize(.small)
                        .disabled(self.stagePromptText == self.selectedStageAction.defaultSystemPrompt)
                    }
                    
                    ScrollPassthroughTextEditor(
                        text: self.$stagePromptText,
                        font: .monospacedSystemFont(ofSize: 11.5, weight: .regular)
                    )
                    .frame(height: 168)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    )
                    .onChange(of: self.stagePromptText) { _, newValue in
                        let storedOrDefault = CotLocalDatabase.shared.customStagePrompt(forKey: self.selectedStageAction.databaseConfigKey)
                            ?? self.selectedStageAction.defaultSystemPrompt
                        guard newValue != storedOrDefault else { return }
                        CotLocalDatabase.shared.set(newValue, forKey: self.selectedStageAction.databaseConfigKey)
                    }
                }
            } header: {
                Label("阶段提示词 (Stage Prompt)", systemImage: "text.bubble")
            }
            
            Section {
                Toggle("动感打字特效", isOn: self.$typewriterEnabled)
                    .onChange(of: self.typewriterEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                    }
                
                Picker("特效风格", selection: self.$typewriterStyle) {
                    ForEach(TypingEffectPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(!self.typewriterEnabled)
                .onChange(of: self.typewriterStyle) { _, val in
                    CotLocalDatabase.shared.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                    UserDefaults.standard.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                }
                
                Toggle("Vim 流体光标特效", isOn: self.$vimCursorTrailEnabled)
                    .onChange(of: self.vimCursorTrailEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                    }
                
                Toggle("纯文本内嵌图片预览", isOn: self.$plainTextImagesEnabled)
                    .onChange(of: self.plainTextImagesEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                    }
                
                LabeledContent("光标颜色") {
                    CustomCursorColorControl()
                }
            } header: {
                Label("沉浸交互与视觉反馈", systemImage: "wand.and.stars")
            }
        }
        .task { self.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.reload()
        }
    }
    
    
    private func reload() {
        
        let db = CotLocalDatabase.shared
        self.personaText = db.aiPersona
        self.loadStagePrompt(for: self.selectedStageAction)
        self.typewriterEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled, default: true)
        let styleRaw = db.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: TypingEffectPreset.powerMode.rawValue)
        self.typewriterStyle = TypingEffectPreset.resolve(styleRaw)
        self.vimCursorTrailEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled, default: true)
        self.plainTextImagesEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled, default: true)
    }
    
    
    private func loadStagePrompt(for action: AIAction) {
        
        self.stagePromptText = CotLocalDatabase.shared.customStagePrompt(forKey: action.databaseConfigKey)
            ?? action.defaultSystemPrompt
    }
}


// MARK: - Preview

#Preview {
    AISettingsView()
}

#Preview("AI Persona") {
    AIPersonaSettingsView()
}
