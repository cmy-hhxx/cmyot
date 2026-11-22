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

// MARK: - Sidebar Navigation Model (12 Atomic Tabs)

enum SidebarSettingsItem: String, CaseIterable, Identifiable, Sendable {
    
    case general
    case appIcon
    case appearance
    case wallpaper
    case typography
    case editing
    case format
    case effects
    case models
    case bots
    case keyBindings
    case pass
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .general: AppLanguage.text("通用", en: "General")
            case .appIcon: AppLanguage.text("图标", en: "App Icon")
            case .appearance: AppLanguage.text("外观", en: "Appearance")
            case .wallpaper: AppLanguage.text("壁纸", en: "Wallpaper")
            case .typography: AppLanguage.text("字体", en: "Fonts")
            case .editing: AppLanguage.text("编辑", en: "Editing")
            case .format: AppLanguage.text("格式", en: "Format")
            case .effects: AppLanguage.text("动效", en: "Motion")
            case .models: AppLanguage.text("模型", en: "Models")
            case .bots: AppLanguage.text("智能体", en: "Agents")
            case .keyBindings: AppLanguage.text("快捷键", en: "Shortcuts")
            case .pass: AppLanguage.text("通行证", en: "Pass")
        }
    }
    
    var symbolName: String {
        switch self {
            case .general: "gearshape.fill"
            case .appIcon: "sparkles.rectangle.stack.fill"
            case .appearance: "paintpalette.fill"
            case .wallpaper: "photo.on.rectangle.angled"
            case .typography: "textformat.size"
            case .editing: "square.and.pencil"
            case .format: "doc.text.fill"
            case .effects: "wand.and.stars"
            case .models: "cpu.fill"
            case .bots: "sparkles"
            case .keyBindings: "keyboard.fill"
            case .pass: "lanyardcard.fill"
        }
    }
    
    var badgeColor: Color {
        switch self {
            case .general: Color(red: 0.56, green: 0.56, blue: 0.58)
            case .appIcon: Color(red: 0.85, green: 0.65, blue: 0.16)
            case .appearance: Color(red: 0.44, green: 0.36, blue: 0.70)
            case .wallpaper: Color(red: 0.18, green: 0.52, blue: 0.88)
            case .typography: Color(red: 0.25, green: 0.48, blue: 0.92)
            case .editing: Color(red: 0.04, green: 0.52, blue: 1.00)
            case .format: Color(red: 0.14, green: 0.65, blue: 0.58)
            case .effects: Color(red: 0.96, green: 0.55, blue: 0.08)
            case .models: Color(red: 0.06, green: 0.72, blue: 0.51)
            case .bots: Color(red: 0.84, green: 0.22, blue: 0.26)
            case .keyBindings: Color(red: 0.69, green: 0.32, blue: 0.87)
            case .pass: Color(red: 0.08, green: 0.72, blue: 0.65)
        }
    }
    
    
    init(legacyPane: SettingsPane) {
        switch legacyPane {
            case .general, .dashboard: self = .general
            case .appearance, .window: self = .appearance
            case .edit: self = .editing
            case .format: self = .format
            case .keyBindings: self = .keyBindings
            case .ai: self = .models
            case .aiPersona: self = .bots
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
    
    /// Optimal macOS System Settings–proportioned fixed window size (non-resizable).
    static let fixedContentSize = NSSize(width: 780, height: 560)
    
    private let state = SidebarSettingsState()
    
    
    init() {
        let rootView = SidebarSettingsRootView(state: self.state)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        
        let window = SidebarSettingsWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.setContentSize(Self.fixedContentSize)
        window.contentMinSize = Self.fixedContentSize
        window.contentMaxSize = Self.fixedContentSize
        let lockedFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.fixedContentSize)).size
        window.minSize = lockedFrameSize
        window.maxSize = lockedFrameSize
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
        self.openItem(SidebarSettingsItem(legacyPane: pane))
    }
    
    
    func openItem(_ item: SidebarSettingsItem) {
        self.state.selectedItem = item
        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}


// MARK: - Unified Design Tokens & Alignment Primitives

private enum SettingsDesignTokens {
    
    static let sidebarWidth: CGFloat = 204
    static let detailWidth: CGFloat = 575 // 204 + 1 + 575 == 780
    static let contentPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let sectionTitleSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 44
    static let cardCornerRadius: CGFloat = 10
    static let segmentedWidth: CGFloat = 172
    
    static let sidebarClusters: [[SidebarSettingsItem]] = [
        [.general, .appIcon, .appearance, .wallpaper],
        [.typography, .editing, .format, .effects],
        [.models, .bots, .keyBindings, .pass],
    ]
}


private struct SidebarSettingsRootView: View {
    
    @Bindable var state: SidebarSettingsState
    @Environment(\.colorScheme) private var colorScheme
    @State private var dbStatusMessage: String?
    @State private var hoveredItem: SidebarSettingsItem?
    @Namespace private var sidebarSelectionNamespace
    
    
    private var contentBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 0.118, green: 0.118, blue: 0.125) // #1E1E20
            : Color(red: 0.961, green: 0.961, blue: 0.969) // #F5F5F7
    }
    
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Translucent Apple-style Sidebar
            ZStack(alignment: .topLeading) {
                SidebarVisualEffectBackdrop()
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 10) {
                    Spacer().frame(height: 32)
                    
                    ForEach(Array(SettingsDesignTokens.sidebarClusters.enumerated()), id: \.offset) { _, cluster in
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(cluster) { item in
                                self.sidebarRow(item)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
            .frame(width: SettingsDesignTokens.sidebarWidth)
            
            Rectangle()
                .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .frame(width: 1)
                .ignoresSafeArea()
            
            // Right Detail Canvas
            ZStack(alignment: .topLeading) {
                self.contentBackground.ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 0) {
                    // Header strip aligned optically with traffic lights
                    HStack(spacing: 10) {
                        SettingsSquircleBadge(
                            symbolName: self.state.selectedItem.symbolName,
                            color: self.state.selectedItem.badgeColor,
                            size: 22
                        )
                        Text(self.state.selectedItem.title)
                            .font(.system(size: 16, weight: .semibold))
                            .contentTransition(.interpolate)
                        
                        Spacer()
                        
                        if let dbStatusMessage = self.dbStatusMessage {
                            Text(dbStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, SettingsDesignTokens.contentPadding)
                    .frame(height: 52)
                    
                    Rectangle()
                        .fill(self.colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                        .frame(height: 0.5)
                    
                    Group {
                        if self.state.selectedItem == .keyBindings {
                            KeyBindingsSettingsView(usesFlexibleFrame: true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                self.detailContent
                                    .padding(.horizontal, SettingsDesignTokens.contentPadding)
                                    .padding(.top, 20)
                                    .padding(.bottom, 28)
                                    .frame(width: SettingsDesignTokens.detailWidth, alignment: .topLeading)
                            }
                            .frame(width: SettingsDesignTokens.detailWidth)
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .id(self.state.selectedItem)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 4)),
                        removal: .opacity
                    ))
                }
            }
            .frame(width: SettingsDesignTokens.detailWidth)
            .frame(maxHeight: .infinity)
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20), value: self.state.selectedItem)
        }
        .frame(
            width: SidebarSettingsWindowController.fixedContentSize.width,
            height: SidebarSettingsWindowController.fixedContentSize.height
        )
        .environment(\.locale, AppLanguage.current.locale)
    }
    
    
    @ViewBuilder
    private func sidebarRow(_ item: SidebarSettingsItem) -> some View {
        let isSelected = (self.state.selectedItem == item)
        let isHovered = (self.hoveredItem == item)
        
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                self.state.selectedItem = item
            }
        } label: {
            HStack(spacing: 9) {
                SettingsSquircleBadge(
                    symbolName: item.symbolName,
                    color: item.badgeColor,
                    size: 20,
                    isSelected: isSelected
                )
                
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.24), radius: 4, y: 1)
                        .matchedGeometryEffect(id: "sidebarActiveTab", in: self.sidebarSelectionNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .fill(self.colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                self.hoveredItem = hovering ? item : (self.hoveredItem == item ? nil : self.hoveredItem)
            }
        }
    }
    
    
    @ViewBuilder
    private var detailContent: some View {
        switch self.state.selectedItem {
            case .general:
                SidebarGeneralSettingsPane(
                    onExportDatabase: { self.exportLocalDatabase() },
                    onImportDatabase: { self.importLocalDatabase() }
                )
            case .appIcon:
                SidebarAppIconSettingsPane()
            case .appearance:
                SidebarAppearanceSettingsPane()
            case .wallpaper:
                SidebarWallpaperSettingsPane()
            case .typography:
                SidebarTypographySettingsPane()
            case .editing:
                SidebarEditingSettingsPane()
            case .format:
                SidebarFormatSettingsPane()
            case .effects:
                SidebarEffectsSettingsPane()
            case .models:
                AIModelsSettingsView()
            case .bots:
                AIBotsSettingsView()
            case .keyBindings:
                EmptyView()
            case .pass:
                CotPassSettingsView()
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
                    self.setTemporaryStatus("✓ 已导出完整备份：\(url.lastPathComponent)")
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
                    self.setTemporaryStatus("✓ 已恢复本地数据：\(url.lastPathComponent)")
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
    var isSelected: Bool = false
    
    var body: some View {
        let radius = max(5, self.size * 0.27)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [self.color.opacity(0.88), self.color],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: self.size, height: self.size)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(self.isSelected ? 0.50 : 0.32), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .overlay(
                Image(systemName: self.symbolName)
                    .font(.system(size: self.size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: self.color.opacity(0.22), radius: 1.5, y: 0.5)
    }
}


private struct SettingsGroupCard<Content: View>: View {
    
    var title: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionTitleSpacing) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                self.content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.cardCornerRadius, style: .continuous)
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white)
                    .shadow(
                        color: self.colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                        radius: 1.5,
                        y: 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}


private struct SettingsItemRow<Control: View>: View {
    
    let label: String
    @ViewBuilder let control: () -> Control
    
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(self.label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer(minLength: 12)
            
            self.control()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: SettingsDesignTokens.rowHeight)
    }
}


private struct SettingsRowDivider: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Rectangle()
            .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}


// MARK: - 1. 通用

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
    @State private var isShowingVersionDetails = false
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            if self.isShowingStoredDocs {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isShowingStoredDocs = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(AppLanguage.text("返回通用设置", en: "Back to General"))
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    SettingsGroupCard(title: AppLanguage.text("本地文档库与配置", en: "Document Vault")) {
                        StoredDocumentsSheetView(isEmbeddedInline: true) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                self.isShowingStoredDocs = false
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                self.generalMainContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
    
    
    private var generalMainContent: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            // 1. 本地账户
            SettingsGroupCard(title: "本地账户") {
                let active = self.profileManager.activeProfile
                
                HStack(spacing: 12) {
                    Button {
                        self.pickAvatar(forActive: true)
                    } label: {
                        UserAvatarCircleView(profile: active, size: 42)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 15, height: 15)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help("点击更换当前账户头像")
                    
                    if self.isEditingActiveName {
                        HStack(spacing: 6) {
                            TextField("昵称", text: self.$editingActiveName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                                .onSubmit { self.commitActiveRename() }
                            Button("保存") { self.commitActiveRename() }
                                .controlSize(.small)
                            Button("取消") { self.isEditingActiveName = false }
                                .controlSize(.small)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(active.displayName)
                                .font(.system(size: 13.5, weight: .semibold))
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
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.isCreatingUser.toggle()
                        }
                    } label: {
                        Label("新建用户", systemImage: "person.badge.plus")
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                
                if self.isCreatingUser {
                    SettingsRowDivider()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
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
                                    size: 30,
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
                            .controlSize(.small)
                            .help("随机生成昵称")
                            
                            Button("创建") {
                                self.submitNewUser()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        HStack {
                            Text("同步当前模型配置")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: self.$copyCurrentAIConfig)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                
                if self.profileManager.profiles.count > 1 {
                    SettingsRowDivider()
                    
                    ForEach(Array(self.profileManager.profiles.enumerated()), id: \.element.id) { idx, profile in
                        if idx > 0 {
                            SettingsRowDivider()
                        }
                        let isCurrent = (profile.id == active.id)
                        HStack(spacing: 8) {
                            UserAvatarCircleView(profile: profile, size: 22)
                            Text(profile.displayName)
                                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                            Spacer()
                            if isCurrent {
                                Text("使用中")
                                    .font(.caption.weight(.semibold))
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
                        .padding(.horizontal, 14)
                        .frame(minHeight: SettingsDesignTokens.rowHeight)
                    }
                }
            }
            
            // 2. 数据备份
            SettingsGroupCard(title: AppLanguage.text("数据备份", en: "Data Backup")) {
                SettingsItemRow(label: AppLanguage.text("全量数据备份", en: "Full Backup")) {
                    HStack(spacing: 8) {
                        Button(AppLanguage.text("导出备份", en: "Export")) {
                            self.onExportDatabase()
                        }
                        .controlSize(.small)
                        Button(AppLanguage.text("导入迁移", en: "Import")) {
                            self.onImportDatabase()
                        }
                        .controlSize(.small)
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("本地文档库", en: "Document Vault")) {
                    Button(AppLanguage.text("管理文档", en: "Manage")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isShowingStoredDocs = true
                        }
                    }
                    .controlSize(.small)
                }
            }
            
            // 3. 启动选项
            SettingsGroupCard(title: AppLanguage.text("启动选项", en: "Startup")) {
                SettingsItemRow(label: AppLanguage.text("界面语言", en: "Language")) {
                    Picker("", selection: self.$language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(verbatim: lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: self.language) { _, newValue in
                        newValue.apply()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isLanguageConfirmationPresented = true
                        }
                    }
                }
                
                if self.isLanguageConfirmationPresented {
                    SettingsRowDivider()
                    HStack(spacing: 10) {
                        Text(AppLanguage.text("语言已切换，重启 CotEditor 后完整生效", en: "Restart CotEditor to apply language"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(AppLanguage.text("稍后", en: "Later")) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                self.isLanguageConfirmationPresented = false
                            }
                        }
                        .controlSize(.small)
                        Button(AppLanguage.text("立即重启", en: "Relaunch")) {
                            (NSApp.delegate as? AppDelegate)?.needsRelaunch = true
                            NSApp.terminate(nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("无文档启动动作", en: "When Opening Without Documents")) {
                    Picker("", selection: self.$noDocumentOnLaunchOption) {
                        Text(AppLanguage.text("新建空白文档", en: "Create New Document")).tag(NoDocumentOnLaunchOption.untitledDocument)
                        Text(AppLanguage.text("显示打开面板", en: "Show Open Panel")).tag(NoDocumentOnLaunchOption.openPanel)
                        Text(AppLanguage.text("不执行动作", en: "Do Nothing")).tag(NoDocumentOnLaunchOption.none)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("启动时恢复上次窗口", en: "Restore Windows on Launch")) {
                    Toggle("", isOn: self.$quitAlwaysKeepsWindows)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("自动保存文档修改", en: "Autosave Documents")) {
                    Toggle("", isOn: self.$enablesAutosaveInPlace)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            // 4. 关于版本
            SettingsGroupCard(title: AppLanguage.text("关于版本", en: "Version")) {
                SettingsItemRow(label: "\(Bundle.main.bundleName) \(Bundle.main.shortVersion) (\(Bundle.main.bundleVersion))") {
                    Button(self.isShowingVersionDetails ? AppLanguage.text("收起详情", en: "Hide") : AppLanguage.text("版本详情", en: "Details")) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            self.isShowingVersionDetails.toggle()
                        }
                    }
                    .controlSize(.small)
                }
                
                if self.isShowingVersionDetails {
                    SettingsRowDivider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bundle ID · \(Bundle.main.bundleIdentifier ?? "local.cmy.Cot")")
                        Text(AppLanguage.text("数据目录 · \(CotLocalDatabase.shared.databaseURL.deletingLastPathComponent().path)", en: "Database · \(CotLocalDatabase.shared.databaseURL.path)"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
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


// MARK: - 1B. 应用图标自定义工坊 (App Icon Studio)

private struct SidebarAppIconSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var iconManager = AppIconManager.shared
    @State private var isDropTargeted = false
    
    private var customRimBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.iconManager.spec.customBorderHex) },
            set: { newColor in
                self.iconManager.spec.customBorderHex = StudioPaletteManager.hexString(from: NSColor(newColor))
                self.iconManager.applyIconToSystemAndDock()
            }
        )
    }
    
    private var matColorBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.iconManager.spec.backgroundMatHex) },
            set: { newColor in
                self.iconManager.spec.backgroundMatHex = StudioPaletteManager.hexString(from: NSColor(newColor))
                self.iconManager.applyIconToSystemAndDock()
            }
        )
    }
    
    
    var body: some View {
        let _ = self.iconManager.customImageVersion
        
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            // 1. Dock Showcase (no small-font explanatory captions)
            SettingsGroupCard(title: nil) {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: self.colorScheme == .dark
                                        ? [Color(red: 0.12, green: 0.13, blue: 0.18), Color(red: 0.08, green: 0.09, blue: 0.13)]
                                        : [Color(red: 0.90, green: 0.91, blue: 0.95), Color(red: 0.84, green: 0.86, blue: 0.91)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 144)
                        
                        // Frosted mini Dock shelf beneath icon
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: 170, height: 32)
                            .offset(y: 44)
                            .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.35 : 0.10), radius: 10, y: 4)
                        
                        Image(nsImage: self.iconManager.previewImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 112, height: 112)
                            .scaleEffect(self.isDropTargeted ? 1.07 : 1.0)
                            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: self.isDropTargeted)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                self.isDropTargeted ? Color.accentColor : Color.clear,
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                    )
                    .onDrop(of: [.image, .fileURL], isTargeted: self.$isDropTargeted) { providers in
                        self.handleDrop(providers: providers)
                    }
                    
                    HStack(spacing: 10) {
                        Button(AppLanguage.text("上传图片", en: "Upload")) {
                            self.pickCustomArtwork()
                        }
                        .controlSize(.small)
                        
                        Button(AppLanguage.text("恢复默认", en: "Reset")) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                self.iconManager.resetToDefault()
                            }
                        }
                        .controlSize(.small)
                        
                        Spacer()
                    }
                }
                .padding(14)
            }
            
            // 2. Built-in Chiikawa Artwork & Custom Source
            SettingsGroupCard(title: AppLanguage.text("图标", en: "Icon")) {
                HStack(spacing: 10) {
                    ForEach(AppIconSource.allCases) { source in
                        let isSelected = (self.iconManager.spec.source == source)
                        let thumb = self.iconManager.sourceImage(for: source)
                        
                        Button {
                            if source == .customImage && !self.iconManager.hasCustomImage {
                                self.pickCustomArtwork()
                                return
                            }
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                self.iconManager.spec.source = source
                                self.iconManager.applyIconToSystemAndDock()
                            }
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if let thumb {
                                        Image(nsImage: thumb)
                                            .resizable()
                                            .interpolation(.high)
                                            .scaledToFill()
                                    } else {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                            lineWidth: isSelected ? 2.0 : 0.5
                                        )
                                )
                                
                                Text(source.displayName)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.045) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                }
                .padding(10)
            }
            
            // 3. Rim / Gold Inlay Style Presets
            SettingsGroupCard(title: AppLanguage.text("边框", en: "Frame")) {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                        ForEach(AppIconBorderStyle.allCases) { style in
                            let isSelected = (self.iconManager.spec.borderStyle == style)
                            Button {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                    self.iconManager.spec.borderStyle = style
                                    if style != .clean && self.iconManager.spec.borderWidth < 1.5 {
                                        self.iconManager.spec.borderWidth = 4.6
                                    }
                                    self.iconManager.applyIconToSystemAndDock()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: style.previewColors,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 12, height: 12)
                                        .overlay(
                                            Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                                        )
                                    
                                    Text(style.displayName)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .primary : .secondary)
                                        .fixedSize()
                                }
                                .padding(.horizontal, 9)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color.primary.opacity(self.colorScheme == .dark ? 0.12 : 0.07) : Color.primary.opacity(0.03))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.70) : Color.clear, lineWidth: 1.2)
                                )
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    
                    if self.iconManager.spec.borderStyle == .customColor {
                        HStack {
                            Text(AppLanguage.text("自定义镶边颜色", en: "Custom Rim Color"))
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                            ColorPicker("", selection: self.customRimBinding, supportsOpacity: false)
                                .labelsHidden()
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(12)
            }
            
            // 4. Stepless Fine-Tuning Controls
            SettingsGroupCard(title: AppLanguage.text("样式", en: "Style")) {
                SettingsItemRow(label: AppLanguage.text("镶边粗细", en: "Border Width")) {
                    HStack(spacing: 8) {
                        Slider(value: self.specBinding(\.borderWidth), in: 0...10)
                            .frame(width: 150)
                        Text(String(format: "%.1f", self.iconManager.spec.borderWidth))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("画面缩放", en: "Artwork Zoom")) {
                    HStack(spacing: 8) {
                        Slider(value: self.specBinding(\.imageZoom), in: 0.80...1.35)
                            .frame(width: 150)
                        Text("\(Int((self.iconManager.spec.imageZoom * 100).rounded()))%")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("圆角曲率", en: "Corner Curvature")) {
                    HStack(spacing: 8) {
                        Slider(value: self.specBinding(\.cornerRoundness), in: 0.16...0.50)
                            .frame(width: 150)
                        Text("\(Int((self.iconManager.spec.cornerRoundness * 100).rounded()))%")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("表面水晶流光", en: "Crystal Gloss")) {
                    HStack(spacing: 8) {
                        Slider(value: self.specBinding(\.glossIntensity), in: 0.0...1.0)
                            .frame(width: 150)
                        Text("\(Int((self.iconManager.spec.glossIntensity * 100).rounded()))%")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("装饰角标", en: "Corner Badge")) {
                    Picker("", selection: self.specBinding(\.cornerBadge)) {
                        ForEach(AppIconBadge.allCases) { badge in
                            Text(badge.displayName).tag(badge)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                
                if self.iconManager.spec.imageZoom < 0.99 {
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("画布衬底色", en: "Background Mat")) {
                        ColorPicker("", selection: self.matColorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
        }
    }
    
    
    private func specBinding<T: Equatable>(_ keyPath: WritableKeyPath<AppIconSpec, T>) -> Binding<T> {
        Binding(
            get: { self.iconManager.spec[keyPath: keyPath] },
            set: { newValue in
                self.iconManager.spec[keyPath: keyPath] = newValue
                self.iconManager.applyIconToSystemAndDock()
            }
        )
    }
    
    
    private func pickCustomArtwork() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("选择应用图标图片", en: "Choose App Icon Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url)
            else { return }
            Task { @MainActor in
                _ = self.iconManager.saveCustomImage(image)
            }
        }
    }
    
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = if let data = item as? Data {
                        URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        item as? URL
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        if let image = NSImage(contentsOf: url) {
                            _ = self.iconManager.saveCustomImage(image)
                        }
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in
                        _ = self.iconManager.saveCustomImage(image)
                    }
                }
                return true
            }
        }
        return false
    }
}


// MARK: - 1C. 壁纸 (Silky 120fps Live Editor Preview + Cached Gallery Grid)

private struct SidebarWallpaperSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var manager = WallpaperManager.shared
    @State private var hoveredID: String?
    @State private var isDropTargeted = false
    
    
    var body: some View {
        let _ = self.manager.catalogVersion
        let items = self.manager.allItems
        let selectedItem = items.first { $0.id == self.manager.spec.selectedID } ?? items.first
        
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            // 1. Miniature Editor Stage
            SettingsGroupCard(title: nil) {
                VStack(spacing: 12) {
                    self.liveEditorPreviewStage(selectedItem: selectedItem)
                        .frame(height: 184)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    self.isDropTargeted
                                        ? StudioPaletteManager.shared.activeAccentColor
                                        : (self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)),
                                    style: self.isDropTargeted ? StrokeStyle(lineWidth: 2, dash: [6, 4]) : StrokeStyle(lineWidth: 0.75)
                                )
                        )
                        .onDrop(of: [.image, .fileURL], isTargeted: self.$isDropTargeted) { providers in
                            self.handleDrop(providers: providers)
                        }
                    
                    HStack(spacing: 8) {
                        if let selectedItem {
                            Circle()
                                .fill(Color(hexString: selectedItem.accentHex))
                                .frame(width: 8, height: 8)
                            Text(selectedItem.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if let selectedItem, selectedItem.isCustom {
                            Button(role: .destructive) {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                    self.manager.deleteCustomWallpaper(id: selectedItem.id)
                                }
                            } label: {
                                Label(AppLanguage.text("删除", en: "Delete"), systemImage: "trash")
                            }
                            .controlSize(.small)
                        }
                        
                        Button {
                            self.pickCustomWallpaperImage()
                        } label: {
                            Label(AppLanguage.text("上传图片", en: "Upload"), systemImage: "photo.badge.plus")
                        }
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
            
            // 2. Clean 4-Column Cached Wallpaper Gallery Grid
            SettingsGroupCard(title: AppLanguage.text("精选壁纸", en: "Gallery")) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    ForEach(items) { item in
                        self.wallpaperTile(item)
                    }
                }
                .padding(12)
            }
            
            // 3. Editor Backdrop Controls
            SettingsGroupCard(title: AppLanguage.text("编辑器背景显示", en: "Editor Backdrop")) {
                SettingsItemRow(label: AppLanguage.text("启用编辑器壁纸", en: "Enable Wallpaper")) {
                    Toggle("", isOn: Binding(
                        get: { self.manager.spec.isEnabled },
                        set: { val in
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.manager.spec.isEnabled = val
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("画面浓度", en: "Opacity")) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { self.manager.spec.opacity },
                                set: { self.manager.spec.opacity = $0 }
                            ),
                            in: 0.04...0.48
                        )
                        .frame(width: 152)
                        .disabled(!self.manager.spec.isEnabled)
                        
                        Text("\(Int((self.manager.spec.opacity * 100).rounded()))%")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("柔焦模糊", en: "Soft Blur")) {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { self.manager.spec.blurRadius },
                                set: { self.manager.spec.blurRadius = $0 }
                            ),
                            in: 0...32
                        )
                        .frame(width: 152)
                        .disabled(!self.manager.spec.isEnabled)
                        
                        Text("\(Int(self.manager.spec.blurRadius.rounded())) px")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func liveEditorPreviewStage(selectedItem: WallpaperItem?) -> some View {
        let isDark = (self.colorScheme == .dark)
        let editorBase = isDark ? Color(red: 0.09, green: 0.095, blue: 0.11) : Color(red: 0.985, green: 0.985, blue: 0.99)
        let artwork = selectedItem.map { self.manager.artworkImage(for: $0.id) }
        let accent = selectedItem.map { Color(hexString: $0.accentHex) } ?? StudioPaletteManager.shared.activeAccentColor
        let previewAlpha = self.manager.spec.isEnabled ? min(0.82, max(0.18, self.manager.spec.opacity * 1.65)) : 0.12
        let previewBlur = self.manager.spec.isEnabled ? min(14, self.manager.spec.blurRadius * 0.45) : 0
        
        ZStack(alignment: .topLeading) {
            editorBase
            
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .blur(radius: previewBlur)
                    .opacity(previewAlpha)
                    .scaleEffect(1.06)
                    .clipped()
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: selectedItem?.id)
            }
            
            // Miniature authentic CotEditor window chrome & code skeleton (real product material)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 0.95, green: 0.37, blue: 0.35)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.96, green: 0.74, blue: 0.26)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.30, green: 0.78, blue: 0.38)).frame(width: 7, height: 7)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(isDark ? Color.black.opacity(0.26) : Color.white.opacity(0.55))
                
                Divider().opacity(0.25)
                
                VStack(alignment: .leading, spacing: 7) {
                    self.sampleCodeRow(line: "1", segments: [(accent, 42), (.primary.opacity(0.75), 96), (.secondary.opacity(0.45), 64)])
                    self.sampleCodeRow(line: "2", segments: [(.clear, 16), (.primary.opacity(0.65), 118), (accent.opacity(0.75), 54)])
                    self.sampleCodeRow(line: "3", segments: [(.clear, 16), (.secondary.opacity(0.50), 146)])
                    self.sampleCodeRow(line: "4", segments: [(.clear, 32), (accent.opacity(0.85), 62), (.primary.opacity(0.70), 82)])
                    self.sampleCodeRow(line: "5", segments: [(.primary.opacity(0.55), 36)])
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                
                Spacer(minLength: 0)
            }
            
            if self.isDropTargeted {
                ZStack {
                    Color.black.opacity(0.35)
                    Text(AppLanguage.text("松手设为自定义壁纸", en: "Drop Image to Use as Wallpaper"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accent, in: Capsule())
                }
            }
        }
    }
    
    
    private func sampleCodeRow(line: String, segments: [(Color, CGFloat)]) -> some View {
        HStack(spacing: 8) {
            Text(line)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
            HStack(spacing: 5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    if seg.0 == .clear {
                        Color.clear.frame(width: seg.1, height: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(seg.0)
                            .frame(width: seg.1, height: 6)
                    }
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func wallpaperTile(_ item: WallpaperItem) -> some View {
        let isSelected = (self.manager.spec.selectedID == item.id)
        let isHovered = (self.hoveredID == item.id)
        let accent = Color(hexString: item.accentHex)
        let thumb = self.manager.thumbnailImage(for: item.id)
        
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                self.manager.selectWallpaper(id: item.id, enableIfDisabled: true)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: thumb)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(height: 64)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? accent : Color.primary.opacity(isHovered ? 0.22 : 0.08),
                                    lineWidth: isSelected ? 2 : 0.75
                                )
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, accent)
                            .padding(4)
                    }
                }
                
                Text(item.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { inside in
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.14)) {
                self.hoveredID = inside ? item.id : (self.hoveredID == item.id ? nil : self.hoveredID)
            }
        }
    }
    
    
    private func pickCustomWallpaperImage() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("选择壁纸图片", en: "Choose Wallpaper Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
            let baseTitle = url.deletingPathExtension().lastPathComponent
            Task { @MainActor in
                _ = self.manager.saveCustomWallpaper(image, title: baseTitle)
            }
        }
    }
    
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = if let data = item as? Data {
                        URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        item as? URL
                    }
                    guard let url, let image = NSImage(contentsOf: url) else { return }
                    let title = url.deletingPathExtension().lastPathComponent
                    Task { @MainActor in
                        _ = self.manager.saveCustomWallpaper(image, title: title)
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in
                        _ = self.manager.saveCustomWallpaper(image)
                    }
                }
                return true
            }
        }
        return false
    }
}


// MARK: - 2. 字体 (Zero-Popup Inline Font Picker)

private struct SidebarTypographySettingsPane: View {
    
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


/// Inline searchable font family & weight chooser replacing modal `NSFontPanel`.
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
        let manager = NSFontManager.shared
        let all = manager.availableFontFamilies
        let pool: [String]
        if self.showAllFamilies {
            pool = all
        } else {
            pool = all.filter { fam in
                guard let font = NSFont(name: fam, size: 12) else { return false }
                return font.isFixedPitch || manager.traits(of: font).contains(.fixedPitchFontMask)
            }
        }
        let q = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return pool }
        return pool.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    
    var body: some View {
        let currentFamily = self.selection.familyName ?? self.selection.fontName
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(AppLanguage.text("搜索字体族…", en: "Search fonts…"), text: self.$searchQuery)
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
                                    .lineLimit(1)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 24)
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


// MARK: - 3. 外观 (Designer 3-Color Swatches + Window + Theme)

private struct SidebarAppearanceSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @AppStorage(.windowAlpha) private var windowAlpha
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var syncedToast: String?
    
    private var customLightBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.studioPalette.customLightHex) },
            set: { self.studioPalette.customLightHex = StudioPaletteManager.hexString(from: NSColor($0)) }
        )
    }
    
    private var customDarkBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.studioPalette.customDarkHex) },
            set: { self.studioPalette.customDarkHex = StudioPaletteManager.hexString(from: NSColor($0)) }
        )
    }
    
    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.studioPalette.customAccentHex) },
            set: { self.studioPalette.customAccentHex = StudioPaletteManager.hexString(from: NSColor($0)) }
        )
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            // 1. Curated Designer Color Triads (Synced Globally & to Data Dashboard)
            SettingsGroupCard(title: AppLanguage.text("配色方案", en: "Color System")) {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(StudioPaletteID.allCases) { preset in
                            self.paletteCard(preset)
                        }
                    }
                    
                    if self.studioPalette.selectedID == .custom {
                        HStack(spacing: 14) {
                            HStack(spacing: 5) {
                                Text(AppLanguage.text("浅底色", en: "Light"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                ColorPicker("", selection: self.customLightBinding, supportsOpacity: false)
                                    .labelsHidden()
                            }
                            HStack(spacing: 5) {
                                Text(AppLanguage.text("深底色", en: "Dark"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                ColorPicker("", selection: self.customDarkBinding, supportsOpacity: false)
                                    .labelsHidden()
                            }
                            HStack(spacing: 5) {
                                Text(AppLanguage.text("主亮色", en: "Accent"))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                ColorPicker("", selection: self.customAccentBinding, supportsOpacity: false)
                                    .labelsHidden()
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    SettingsRowDivider()
                        .padding(.horizontal, -12)
                    
                    HStack(spacing: 10) {
                        Button(AppLanguage.text("应用至浅色正文主题", en: "Sync Light Editor Theme")) {
                            self.studioPalette.applyPaletteToEditorTheme(preferDark: false)
                            self.showSyncedToast(AppLanguage.text("已生成并应用浅色正文主题", en: "Applied Light Theme"))
                        }
                        .controlSize(.small)
                        
                        Button(AppLanguage.text("应用至深色正文主题", en: "Sync Dark Editor Theme")) {
                            self.studioPalette.applyPaletteToEditorTheme(preferDark: true)
                            self.showSyncedToast(AppLanguage.text("已生成并应用深色正文主题", en: "Applied Dark Theme"))
                        }
                        .controlSize(.small)
                        
                        Spacer()
                        
                        if let syncedToast = self.syncedToast {
                            Text(syncedToast)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                }
                .padding(12)
            }
            
            SettingsGroupCard(title: AppLanguage.text("窗口外观", en: "Window Appearance")) {
                SettingsItemRow(label: AppLanguage.text("深浅模式", en: "Appearance Mode")) {
                    Picker("", selection: self.$documentAppearance) {
                        Text(AppLanguage.text("跟随系统", en: "System")).tag(AppearanceMode.default)
                        Text(AppLanguage.text("浅色", en: "Light")).tag(AppearanceMode.light)
                        Text(AppLanguage.text("深色", en: "Dark")).tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: SettingsDesignTokens.segmentedWidth)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("窗口不透明度", en: "Window Opacity")) {
                    HStack(spacing: 6) {
                        Slider(value: self.$windowAlpha, in: 0.2...1.0)
                            .frame(width: 118)
                        Text(self.windowAlpha, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 12.5).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .frame(width: SettingsDesignTokens.segmentedWidth, alignment: .trailing)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("光标配色", en: "Cursor Color")) {
                SettingsItemRow(label: AppLanguage.text("光标颜色", en: "Insertion Point")) {
                    CustomCursorColorControl()
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("配色主题", en: "Syntax Themes")) {
                ThemeView()
                    .frame(height: 344)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(6)
            }
        }
    }
    
    
    @ViewBuilder
    private func paletteCard(_ preset: StudioPaletteID) -> some View {
        let triad = self.studioPalette.triad(for: preset)
        let isSelected = (self.studioPalette.selectedID == preset)
        let darkSwatch = StudioPaletteManager.swiftUIColor(hex: triad.darkInkHex)
        let lightSwatch = StudioPaletteManager.swiftUIColor(hex: triad.lightPaperHex)
        let accentSwatch = StudioPaletteManager.swiftUIColor(hex: triad.accentHex)
        
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                self.studioPalette.selectPalette(preset)
                self.studioPalette.syncActiveEditorTheme(preferDark: self.colorScheme == .dark, applyIfNonStudio: true)
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(darkSwatch)
                        .frame(height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(lightSwatch)
                        .frame(height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(accentSwatch)
                        .frame(height: 18)
                }
                
                HStack(spacing: 5) {
                    Text(preset.displayName)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .fixedSize()
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(accentSwatch)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(self.colorScheme == .dark ? 0.10 : 0.05) : Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? accentSwatch.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.75)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
    
    
    private func showSyncedToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.16)) {
            self.syncedToast = msg
        }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            await MainActor.run {
                if self.syncedToast == msg {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.syncedToast = nil
                    }
                }
            }
        }
    }
}


// MARK: - 4. 编辑

private struct SidebarEditingSettingsPane: View {
    
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
    
    @State private var plainTextImagesEnabled = true
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("Vim 模态编辑", en: "Vim Modal Editing")) {
                SettingsItemRow(label: AppLanguage.text("启用 Vim 模式", en: "Enable Vim Mode")) {
                    Toggle("", isOn: self.$vimMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: "视图辅助") {
                SettingsItemRow(label: "显示行号") {
                    Toggle("", isOn: self.$showLineNumbers)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "自动换行") {
                    Toggle("", isOn: self.$wrapLines)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "高亮当前行") {
                    Toggle("", isOn: self.$highlightCurrentLine)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "显示缩进参考线") {
                    Toggle("", isOn: self.$showIndentGuides)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "显示不可见字符") {
                    Toggle("", isOn: self.$showInvisibles)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: "缩进规则") {
                SettingsItemRow(label: "缩进方式") {
                    Picker("", selection: self.$autoExpandTab) {
                        Text("空格").tag(true)
                        Text("Tab").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: SettingsDesignTokens.segmentedWidth)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: "缩进宽度") {
                    StepperNumberField(value: self.$tabWidth, default: 4, in: 1...99)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: "输入时自动缩进") {
                    Toggle("", isOn: self.$autoIndent)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: "按 Tab 缩进选区") {
                    Toggle("", isOn: self.$indentWithTabKey)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: "内容辅助") {
                SettingsItemRow(label: "自动清除行尾空白") {
                    Toggle("", isOn: self.$autoTrimsTrailingWhitespace)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "高亮匹配括号") {
                    Toggle("", isOn: self.$highlightBraces)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "高亮相同选词") {
                    Toggle("", isOn: self.$highlightSelectionInstance)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                SettingsRowDivider()
                SettingsItemRow(label: "纯文本内嵌贴图") {
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
        .onAppear {
            self.plainTextImagesEnabled = CotLocalDatabase.shared.bool(
                forKey: CotLocalDatabase.ConfigKey.plainTextInlineImagesEnabled,
                default: true
            )
        }
    }
}


// MARK: - 5. 格式

private struct SidebarFormatSettingsPane: View {
    
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
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            if self.isEncodingListPresented {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isEncodingListPresented = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(AppLanguage.text("返回格式设置", en: "Back to Format"))
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
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                self.formatMainContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .onReceive(SyntaxManager.shared.$settingNames) { self.syntaxNames = $0 }
    }
    
    
    private var formatMainContent: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: "换行标准") {
                SettingsItemRow(label: "默认换行符") {
                    Picker("", selection: self.$lineEnding) {
                        ForEach(LineEnding.allCases.filter(\.isBasic), id: \.self) {
                            Text(verbatim: "\($0.description) (\($0.label))").tag($0.index)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            
            SettingsGroupCard(title: "文本编码") {
                SettingsItemRow(label: "默认编码") {
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
                    .fixedSize()
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("编码优先顺序", en: "Encoding Priority")) {
                    Button(AppLanguage.text("调整顺序", en: "Edit Order")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            self.isEncodingListPresented = true
                        }
                    }
                    .controlSize(.small)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: "识别文档内编码声明") {
                    Toggle("", isOn: self.$referToEncodingTag)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            SettingsGroupCard(title: "语法高亮") {
                SettingsItemRow(label: "默认语法") {
                    Picker("", selection: self.$syntax) {
                        Text("无").tag(SyntaxName.none)
                        Divider()
                        ForEach(self.syntaxNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}


// MARK: - 6. 动效

private struct SidebarEffectsSettingsPane: View {
    
    @State private var analytics = AnalyticsManager.shared
    
    @State private var typewriterEnabled = true
    @State private var typewriterStyle: TypingEffectPreset = .powerMode
    @State private var vimCursorTrailEnabled = true
    @State private var autoPersonalityEnabled = true
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: "打字反馈") {
                SettingsItemRow(label: "打字粒子特效") {
                    Toggle("", isOn: self.$typewriterEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.typewriterEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                            UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                        }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: "粒子风格") {
                    Picker("", selection: self.$typewriterStyle) {
                        ForEach(TypingEffectPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!self.typewriterEnabled)
                    .onChange(of: self.typewriterStyle) { _, val in
                        CotLocalDatabase.shared.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                        UserDefaults.standard.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                    }
                }
            }
            
            SettingsGroupCard(title: "光标动效") {
                SettingsItemRow(label: "Vim 流体光标尾迹") {
                    Toggle("", isOn: self.$vimCursorTrailEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.vimCursorTrailEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                            UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                        }
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("性格弹幕", en: "Orbit Danmaku")) {
                SettingsItemRow(label: AppLanguage.text("头像环绕弹幕", en: "Avatar Orbit Tags")) {
                    Toggle("", isOn: self.$autoPersonalityEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.autoPersonalityEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled)
                        }
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
            self.autoPersonalityEnabled = db.bool(forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled, default: true)
        }
    }
}
