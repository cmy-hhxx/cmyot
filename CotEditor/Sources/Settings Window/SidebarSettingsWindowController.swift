//
//  SidebarSettingsWindowController.swift
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
import SwiftUI
import UniformTypeIdentifiers
import Defaults
import FileEncoding
import LineEnding
import SyntaxFormat

// MARK: - Sidebar Navigation Model

enum SidebarSettingsItem: String, CaseIterable, Identifiable, Sendable {
    
    case general
    case appearance
    case editor
    case aiBots
    case keyBindings
    case labs
    case pass
    case about
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .general: "通用"
            case .appearance: "外观与显示"
            case .editor: "编辑与格式"
            case .aiBots: "AI 助手"
            case .keyBindings: "快捷键"
            case .labs: "实验室"
            case .pass: "通行证"
            case .about: "关于"
        }
    }
    
    var symbolName: String {
        switch self {
            case .general: "gearshape.fill"
            case .appearance: "textformat.size"
            case .editor: "slider.horizontal.3"
            case .aiBots: "sparkles"
            case .keyBindings: "keyboard.fill"
            case .labs: "flask.fill"
            case .pass: "wallet.pass.fill"
            case .about: "info.circle.fill"
        }
    }
    
    var badgeColor: Color {
        switch self {
            case .general: Color(red: 0.56, green: 0.56, blue: 0.58)
            case .appearance: Color(red: 0.35, green: 0.34, blue: 0.84)
            case .editor: Color(red: 0.04, green: 0.52, blue: 1.00)
            case .aiBots: Color(red: 0.06, green: 0.72, blue: 0.51)
            case .keyBindings: Color(red: 0.69, green: 0.32, blue: 0.87)
            case .labs: Color(red: 1.00, green: 0.58, blue: 0.00)
            case .pass: Color(red: 0.08, green: 0.72, blue: 0.65)
            case .about: Color(red: 0.04, green: 0.52, blue: 1.00)
        }
    }
    
    
    init(legacyPane: SettingsPane) {
        switch legacyPane {
            case .general, .dashboard: self = .general
            case .appearance, .window: self = .appearance
            case .edit, .format: self = .editor
            case .keyBindings: self = .keyBindings
            case .ai, .aiPersona: self = .aiBots
        }
    }
}


@MainActor @Observable
final class SidebarSettingsState {
    
    var selectedItem: SidebarSettingsItem = .general
}


// MARK: - Window & Controller

private final class SidebarSettingsWindow: NSWindow {
    
    override var canBecomeMain: Bool { true }
    
    override func cancelOperation(_ sender: Any?) {
        self.close()
    }
}


@MainActor
final class SidebarSettingsWindowController: NSWindowController {
    
    private let state = SidebarSettingsState()
    
    
    init() {
        let rootView = SidebarSettingsRootView(state: self.state)
        let hostingController = NSHostingController(rootView: rootView)
        
        let window = SidebarSettingsWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 820, height: 610))
        window.minSize = NSSize(width: 740, height: 540)
        window.center()
        
        super.init(window: window)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func openPane(_ pane: SettingsPane) {
        if pane == .dashboard {
            AnalyticsDashboardWindowController.shared.showWindow(nil)
            return
        }
        self.state.selectedItem = SidebarSettingsItem(legacyPane: pane)
        self.showWindow(nil)
    }
}


// MARK: - Root Split Layout

private struct SidebarSettingsRootView: View {
    
    @Bindable var state: SidebarSettingsState
    @Environment(\.colorScheme) private var colorScheme
    @State private var dbStatusMessage: String?
    
    
    private var contentBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
    
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Translucent Sidebar
            ZStack(alignment: .topLeading) {
                SidebarVisualEffectBackdrop()
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 2) {
                    Spacer().frame(height: 36)
                    
                    ForEach([SidebarSettingsItem.general, .appearance, .editor, .aiBots]) { item in
                        self.sidebarRow(item)
                    }
                    
                    Text("高级")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    
                    ForEach([SidebarSettingsItem.keyBindings, .labs]) { item in
                        self.sidebarRow(item)
                    }
                    
                    Text("CotEditor")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    
                    ForEach([SidebarSettingsItem.pass, .about]) { item in
                        self.sidebarRow(item)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .frame(width: 204)
            
            Rectangle()
                .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                .frame(width: 1)
                .ignoresSafeArea()
            
            // Right Detail Canvas
            ZStack(alignment: .topLeading) {
                self.contentBackground.ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 0) {
                    // Header strip
                    HStack(spacing: 10) {
                        SettingsSquircleBadge(
                            symbolName: self.state.selectedItem.symbolName,
                            color: self.state.selectedItem.badgeColor,
                            size: 24
                        )
                        Text(self.state.selectedItem.title)
                            .font(.system(size: 16, weight: .semibold))
                        
                        Spacer()
                        
                        if let dbStatusMessage = self.dbStatusMessage {
                            Text(dbStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                    
                    if self.state.selectedItem == .keyBindings {
                        KeyBindingsSettingsView(usesFlexibleFrame: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            self.detailContent
                                .padding(.horizontal, 24)
                                .padding(.bottom, 26)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 740, minHeight: 540)
        .environment(\.locale, AppLanguage.current.locale)
    }
    
    
    @ViewBuilder
    private func sidebarRow(_ item: SidebarSettingsItem) -> some View {
        let isSelected = (self.state.selectedItem == item)
        
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                self.state.selectedItem = item
            }
        } label: {
            HStack(spacing: 9) {
                SettingsSquircleBadge(symbolName: item.symbolName, color: item.badgeColor, size: 22)
                
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? (self.colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    
    @ViewBuilder
    private var detailContent: some View {
        switch self.state.selectedItem {
            case .general:
                SidebarGeneralSettingsPane(
                    onExportDatabase: { self.exportLocalDatabase() },
                    onImportDatabase: { self.importLocalDatabase() }
                )
            case .appearance:
                SidebarAppearanceSettingsPane()
            case .editor:
                SidebarEditorFormatPane()
            case .aiBots:
                AIBotsSettingsView()
            case .keyBindings:
                EmptyView()
            case .labs:
                SidebarLabsSettingsPane()
            case .pass:
                CotPassSettingsView {
                    self.exportLocalDatabase()
                }
            case .about:
                SidebarAboutSettingsPane()
        }
    }
    
    
    private func exportLocalDatabase() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "cot-backup-\(AnalyticsManager.dateKey()).sqlite3"
        savePanel.canCreateDirectories = true
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task { @MainActor in
                do {
                    try CotLocalDatabase.shared.exportDatabase(to: url)
                    self.setTemporaryStatus("✓ 已导出完整备份（含端点、Key 与头像）：\(url.lastPathComponent)")
                } catch {
                    self.setTemporaryStatus("导出失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    
    private func importLocalDatabase() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                do {
                    try CotLocalDatabase.shared.importDatabase(from: url)
                    self.setTemporaryStatus("✓ 已从 \(url.lastPathComponent) 恢复文档、端点 Key 与头像")
                } catch {
                    self.setTemporaryStatus("导入失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    
    private func setTemporaryStatus(_ msg: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            self.dbStatusMessage = msg
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                if self.dbStatusMessage == msg {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.dbStatusMessage = nil
                    }
                }
            }
        }
    }
}


private struct SidebarVisualEffectBackdrop: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}


private struct SettingsSquircleBadge: View {
    
    let symbolName: String
    let color: Color
    let size: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: max(5, self.size * 0.27), style: .continuous)
            .fill(self.color)
            .frame(width: self.size, height: self.size)
            .overlay(
                Image(systemName: self.symbolName)
                    .font(.system(size: self.size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}


private struct SettingsGroupCard<Content: View>: View {
    
    var title: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                self.content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07), lineWidth: 1)
            )
        }
    }
}


// MARK: - 通用（包含本地多账户与完整数据库迁移）

private struct SidebarGeneralSettingsPane: View {
    
    let onExportDatabase: () -> Void
    let onImportDatabase: () -> Void
    
    @AppStorage(.quitAlwaysKeepsWindows) private var quitAlwaysKeepsWindows
    @AppStorage(.noDocumentOnLaunchOption) private var noDocumentOnLaunchOption
    @AppStorage(.enablesAutosaveInPlace) private var enablesAutosaveInPlace
    
    @State private var language: AppLanguage = .current
    @State private var isLanguageConfirmationPresented = false
    
    @State private var profileManager = UserProfileManager.shared
    @State private var isCreatingUser = false
    @State private var newUserName = ""
    @State private var newUserAvatarData: Data?
    @State private var copyCurrentAIConfig = true
    @State private var confirmDeleteID: String?
    @State private var editingActiveName = ""
    @State private var isEditingActiveName = false
    @State private var isShowingStoredDocs = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Local Account Management (moved cleanly from top-right popover!)
            SettingsGroupCard(title: "本地账户（每账户独立 SQLite 数据库）") {
                let active = self.profileManager.activeProfile
                
                HStack(spacing: 12) {
                    Button {
                        self.pickAvatar(forActive: true)
                    } label: {
                        UserAvatarCircleView(profile: active, size: 46)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help("点击更换当前账户头像")
                    
                    VStack(alignment: .leading, spacing: 3) {
                        if self.isEditingActiveName {
                            HStack(spacing: 6) {
                                TextField("昵称", text: self.$editingActiveName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .onSubmit { self.commitActiveRename() }
                                Button("保存") { self.commitActiveRename() }
                                    .controlSize(.small)
                                Button("取消") { self.isEditingActiveName = false }
                                    .controlSize(.small)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Text(active.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                Button {
                                    self.editingActiveName = active.displayName
                                    self.isEditingActiveName = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("当前账户 · 数据文件 \(active.dbFilename)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.isCreatingUser.toggle()
                        }
                    } label: {
                        Label("新建本地用户", systemImage: "person.badge.plus")
                    }
                    .controlSize(.small)
                }
                
                if self.isCreatingUser {
                    Divider()
                    HStack(spacing: 10) {
                        Button {
                            self.pickAvatar(forActive: false)
                        } label: {
                            let previewHex = UserProfileManager.avatarPresetColors[self.profileManager.profiles.count % UserProfileManager.avatarPresetColors.count]
                            UserAvatarCircleView(
                                profile: UserProfile(
                                    id: "draft",
                                    displayName: self.newUserName.isEmpty ? "新" : self.newUserName,
                                    avatarData: self.newUserAvatarData,
                                    avatarColorHex: previewHex,
                                    dbFilename: "",
                                    accountKind: "local",
                                    email: nil,
                                    remoteUserID: nil,
                                    createdAt: Date(),
                                    lastActiveAt: Date()
                                ),
                                size: 32,
                                customImage: self.newUserAvatarData.flatMap { NSImage(data: $0) }
                            )
                        }
                        .buttonStyle(.plain)
                        .help("选择新账户头像")
                        
                        TextField("输入新用户昵称", text: self.$newUserName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { self.submitNewUser() }
                        
                        Button {
                            self.newUserName = GeneratedDocumentName.generateCandidate()
                        } label: {
                            Image(systemName: "dice")
                        }
                        .help("随机生成昵称")
                        
                        Toggle("沿用 AI 端点与 Key", isOn: self.$copyCurrentAIConfig)
                            .controlSize(.small)
                            .fixedSize()
                        
                        Button("创建") {
                            self.submitNewUser()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                
                if self.profileManager.profiles.count > 1 {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(self.profileManager.profiles) { profile in
                            let isCurrent = (profile.id == active.id)
                            HStack(spacing: 8) {
                                UserAvatarCircleView(profile: profile, size: 22)
                                Text(profile.displayName)
                                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                                Spacer()
                                if isCurrent {
                                    Text("使用中")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Button("切换") {
                                        self.confirmDeleteID = nil
                                        self.profileManager.switchToProfile(id: profile.id)
                                    }
                                    .controlSize(.small)
                                    
                                    let isConfirming = (self.confirmDeleteID == profile.id)
                                    Button(isConfirming ? "确认删除" : "删除", role: .destructive) {
                                        if isConfirming {
                                            self.profileManager.deleteProfile(id: profile.id)
                                            self.confirmDeleteID = nil
                                        } else {
                                            self.confirmDeleteID = profile.id
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }
            
            // 2. Full Database Backup & Migration
            SettingsGroupCard(title: "完整数据迁移") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("单文件全量备份与恢复")
                            .font(.system(size: 13, weight: .medium))
                        Text("自动打包文档、周报、AI 端点与 API Key、用户头像昵称、Bots 与看板统计")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("导出备份…") {
                            self.onExportDatabase()
                        }
                        Button("导入迁移…") {
                            self.onImportDatabase()
                        }
                    }
                }
                
                Divider()
                
                HStack {
                    Label("本地文档与配置库 (\(CotLocalDatabase.shared.documents.count) 篇)", systemImage: "internaldrive")
                        .font(.system(size: 12.5))
                    Spacer()
                    Button("管理数据库内容…") {
                        self.isShowingStoredDocs = true
                    }
                    .controlSize(.small)
                }
            }
            
            // 3. Language & Startup
            SettingsGroupCard(title: "启动与语言") {
                HStack {
                    Text("界面语言")
                    Spacer()
                    Picker("", selection: self.$language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(verbatim: lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: self.language) { _, newValue in
                        newValue.apply()
                        self.isLanguageConfirmationPresented = true
                    }
                }
                
                Divider()
                
                Toggle("下次启动重新打开上次窗口", isOn: self.$quitAlwaysKeepsWindows)
                
                HStack {
                    Text("无已开文档时启动动作")
                    Spacer()
                    Picker("", selection: self.$noDocumentOnLaunchOption) {
                        Text("新建空白文档").tag(NoDocumentOnLaunchOption.untitledDocument)
                        Text("显示打开面板").tag(NoDocumentOnLaunchOption.openPanel)
                        Text("不执行动作").tag(NoDocumentOnLaunchOption.none)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                
                Toggle("启用版本自动保存 (Auto Save)", isOn: self.$enablesAutosaveInPlace)
            }
        }
        .sheet(isPresented: self.$isShowingStoredDocs) {
            StoredDocumentsSheetView()
        }
        .confirmationDialog("需要重启生效", isPresented: self.$isLanguageConfirmationPresented) {
            Button("立即重启") {
                (NSApp.delegate as? AppDelegate)?.needsRelaunch = true
                NSApp.terminate(nil)
            }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("界面语言将在重启 CotEditor 后完整生效。")
        }
    }
    
    
    private func commitActiveRename() {
        let trimmed = self.editingActiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self.profileManager.updateProfile(id: self.profileManager.activeProfile.id, displayName: trimmed)
        }
        self.isEditingActiveName = false
    }
    
    
    private func submitNewUser() {
        let name = self.newUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = UserProfileManager.avatarPresetColors[self.profileManager.profiles.count % UserProfileManager.avatarPresetColors.count]
        self.profileManager.createProfile(
            displayName: name.isEmpty ? GeneratedDocumentName.generateCandidate() : name,
            avatarData: self.newUserAvatarData,
            avatarColorHex: color,
            copyCurrentAIEndpoints: self.copyCurrentAIConfig,
            switchImmediately: true
        )
        self.newUserName = ""
        self.newUserAvatarData = nil
        self.isCreatingUser = false
    }
    
    
    private func pickAvatar(forActive: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let image = NSImage(contentsOf: url),
                  let data = UserProfileManager.processedAvatarPNGData(from: image)
            else { return }
            Task { @MainActor in
                if forActive {
                    self.profileManager.updateProfile(id: self.profileManager.activeProfile.id, avatarData: .some(data))
                } else {
                    self.newUserAvatarData = data
                }
            }
        }
    }
}


// MARK: - 外观与显示

private struct SidebarAppearanceSettingsPane: View {
    
    @AppStorage(.font) private var fontData
    @AppStorage(.monospacedFont) private var monospacedFontData
    @AppStorage(.lineHeight) private var lineHeight
    @AppStorage(.documentAppearance) private var documentAppearance
    @AppStorage(.windowAlpha) private var windowAlpha
    
    @AppStorage(.showLineNumbers) private var showLineNumbers
    @AppStorage(.wrapLines) private var wrapLines
    @AppStorage(.highlightCurrentLine) private var highlightCurrentLine
    @AppStorage(.showInvisibles) private var showInvisibles
    @AppStorage(.showIndentGuides) private var showIndentGuides
    
    private var standardFont: Binding<NSFont> {
        Binding(
            get: { self.fontData.flatMap(NSFont.init(archivedData:)) ?? FontType.standard.systemFont() },
            set: { self.fontData = (try? $0.archivedData) ?? self.fontData }
        )
    }
    
    private var monospacedFont: Binding<NSFont> {
        Binding(
            get: { self.monospacedFontData.flatMap(NSFont.init(archivedData:)) ?? FontType.monospaced.systemFont() },
            set: { self.monospacedFontData = (try? $0.archivedData) ?? self.monospacedFontData }
        )
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroupCard(title: "字体与行距") {
                HStack {
                    Text("标准字体")
                    Spacer()
                    Text("\(self.standardFont.wrappedValue.displayName ?? self.standardFont.wrappedValue.fontName) \(Int(self.standardFont.wrappedValue.pointSize))pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FontSizeStepper("字号", font: self.standardFont)
                    FontPicker("选择…", selection: self.standardFont)
                }
                
                HStack {
                    Text("等宽字体")
                    Spacer()
                    Text("\(self.monospacedFont.wrappedValue.displayName ?? self.monospacedFont.wrappedValue.fontName) \(Int(self.monospacedFont.wrappedValue.pointSize))pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FontSizeStepper("字号", font: self.monospacedFont)
                    FontPicker("选择…", selection: self.monospacedFont)
                }
                
                HStack {
                    Text("行高倍数")
                    Spacer()
                    Stepper(value: self.$lineHeight, in: 0.8...3.0, step: 0.1, format: .number.precision(.fractionLength(1...2))) {
                        EmptyView()
                    }
                    .monospacedDigit()
                }
            }
            
            SettingsGroupCard(title: "外观与光标") {
                HStack {
                    Text("窗口模式")
                    Spacer()
                    Picker("", selection: self.$documentAppearance) {
                        Text("跟随系统").tag(AppearanceMode.default)
                        Text("浅色").tag(AppearanceMode.light)
                        Text("深色").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                
                HStack {
                    Text("窗口不透明度")
                    Spacer()
                    Slider(value: self.$windowAlpha, in: 0.2...1.0)
                        .frame(width: 200)
                    Text(self.windowAlpha, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                
                HStack {
                    Text("光标颜色")
                    Spacer()
                    CustomCursorColorControl()
                }
            }
            
            SettingsGroupCard(title: "编辑器显示") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    Toggle("显示行号", isOn: self.$showLineNumbers)
                    Toggle("自动换行", isOn: self.$wrapLines)
                    Toggle("高亮当前行", isOn: self.$highlightCurrentLine)
                    Toggle("显示缩进参考线", isOn: self.$showIndentGuides)
                    Toggle("显示不可见字符", isOn: self.$showInvisibles)
                }
            }
            
            SettingsGroupCard(title: "配色主题") {
                ThemeView()
                    .frame(height: 224)
            }
        }
    }
}


// MARK: - 编辑与格式

private struct SidebarEditorFormatPane: View {
    
    @AppStorage(.autoExpandTab) private var autoExpandTab
    @AppStorage(.tabWidth) private var tabWidth
    @AppStorage(.autoIndent) private var autoIndent
    @AppStorage(.indentWithTabKey) private var indentWithTabKey
    @AppStorage(.autoTrimsTrailingWhitespace) private var autoTrimsTrailingWhitespace
    @AppStorage(.highlightBraces) private var highlightBraces
    @AppStorage(.highlightSelectionInstance) private var highlightSelectionInstance
    
    @AppStorage(.lineEndCharCode) private var lineEnding
    @AppStorage(.encoding) private var encoding
    @AppStorage(.saveUTF8BOM) private var saveUTF8BOM
    @AppStorage(.referToEncodingTag) private var referToEncodingTag
    @AppStorage(.syntax) private var syntax
    
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
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroupCard(title: "缩进与空白") {
                HStack {
                    Text("缩进字符")
                    Spacer()
                    Picker("", selection: self.$autoExpandTab) {
                        Text("空格").tag(true)
                        Text("制表符 (Tab)").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
                
                HStack {
                    Text("缩进宽度")
                    Spacer()
                    StepperNumberField(value: self.$tabWidth, default: 4, in: 1...99)
                    Text("空格")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    Toggle("输入时自动缩进", isOn: self.$autoIndent)
                    Toggle("按 Tab 缩进选区", isOn: self.$indentWithTabKey)
                    Toggle("自动清除行尾空白", isOn: self.$autoTrimsTrailingWhitespace)
                    Toggle("高亮匹配括号", isOn: self.$highlightBraces)
                    Toggle("高亮相同选中词", isOn: self.$highlightSelectionInstance)
                }
            }
            
            SettingsGroupCard(title: "默认换行、编码与语法") {
                HStack {
                    Text("默认换行符")
                    Spacer()
                    Picker("", selection: self.$lineEnding) {
                        ForEach(LineEnding.allCases.filter(\.isBasic), id: \.self) {
                            Text(verbatim: "\($0.description) (\($0.label))").tag($0.index)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                
                HStack {
                    Text("默认文本编码")
                    Spacer()
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
                    .frame(width: 220)
                    
                    Button("排序…") {
                        self.isEncodingListPresented = true
                    }
                    .controlSize(.small)
                }
                
                HStack {
                    Text("默认语法高亮")
                    Spacer()
                    Picker("", selection: self.$syntax) {
                        Text("无").tag(SyntaxName.none)
                        Divider()
                        ForEach(self.syntaxNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                
                Toggle("读取文档内的编码声明标签", isOn: self.$referToEncodingTag)
            }
        }
        .onReceive(SyntaxManager.shared.$settingNames) { self.syntaxNames = $0 }
        .sheet(isPresented: self.$isEncodingListPresented) {
            EncodingListView(defaultEncoding: self.encodingManager.defaultEncoding)
        }
    }
}


// MARK: - 实验室（Vim / 动效 / AI 性格弹幕）

private struct SidebarLabsSettingsPane: View {
    
    @AppStorage(.vimMode) private var vimMode
    @State private var analytics = AnalyticsManager.shared
    
    @State private var typewriterEnabled = true
    @State private var typewriterStyle: TypingEffectPreset = .powerMode
    @State private var vimCursorTrailEnabled = true
    @State private var plainTextImagesEnabled = true
    @State private var autoPersonalityEnabled = true
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroupCard(title: "模态编辑与动感反馈") {
                Toggle("启用 Vim 模式 (Normal / Visual / Insert + ⌃A 分屏)", isOn: self.$vimMode)
                
                Toggle("Vim 流体弹簧光标与尾迹", isOn: self.$vimCursorTrailEnabled)
                    .onChange(of: self.vimCursorTrailEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                    }
                
                Divider()
                
                Toggle("动感打字粒子特效", isOn: self.$typewriterEnabled)
                    .onChange(of: self.typewriterEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                    }
                
                HStack {
                    Text("打字特效风格")
                    Spacer()
                    Picker("", selection: self.$typewriterStyle) {
                        ForEach(TypingEffectPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 240)
                    .disabled(!self.typewriterEnabled)
                    .onChange(of: self.typewriterStyle) { _, val in
                        CotLocalDatabase.shared.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                        UserDefaults.standard.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                    }
                }
                
                Toggle("纯文本内嵌图片预览卡片", isOn: self.$plainTextImagesEnabled)
                    .onChange(of: self.plainTextImagesEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                        UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled)
                    }
            }
            
            SettingsGroupCard(title: "头像性格弹幕（后台每 6 小时自动洞察）") {
                Toggle("开启后台自动提炼用户性格标签（<= 8 字弹幕）", isOn: self.$autoPersonalityEnabled)
                    .onChange(of: self.autoPersonalityEnabled) { _, val in
                        CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled)
                    }
                
                HStack {
                    if let profile = self.analytics.personalityProfile {
                        Text("最近画像：\(profile.conceptTitle)（\(profile.tags.count) 个标签）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未生成过性格画像")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(self.analytics.isAnalyzingPersonality ? "分析中…" : "立即分析一次") {
                        Task {
                            await self.analytics.refreshPersonalityProfile(force: true)
                        }
                    }
                    .controlSize(.small)
                    .disabled(self.analytics.isAnalyzingPersonality)
                }
            }
        }
        .onAppear {
            let db = CotLocalDatabase.shared
            self.typewriterEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled, default: true)
            self.typewriterStyle = TypingEffectPreset.resolve(
                db.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: TypingEffectPreset.powerMode.rawValue)
            )
            self.vimCursorTrailEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled, default: true)
            self.plainTextImagesEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled, default: true)
            self.autoPersonalityEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled, default: true)
        }
    }
}


// MARK: - 关于

private struct SidebarAboutSettingsPane: View {
    
    var body: some View {
        SettingsGroupCard {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                
                Text(Bundle.main.bundleName)
                    .font(.system(size: 18, weight: .semibold))
                
                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.bundleVersion))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
                Text("个人深度定制版 · 集成多用户隔离、GrokBot AI 矩阵、创作工作室看板与通行证")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    Button("打开完整致谢与开源许可…") {
                        NSApp.orderFrontStandardAboutPanel(nil)
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}
