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
    case database
    case appIcon
    case appearance
    case wallpaper
    case mediaLibrary
    case typography
    case editing
    case format
    case effects
    case models
    case bots
    case memory
    case scheduledTasks
    case keyBindings
    case pass
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .general: AppLanguage.text("通用", en: "General")
            case .database: AppLanguage.text("数据库", en: "Database")
            case .appIcon: AppLanguage.text("图标", en: "App Icon")
            case .appearance: AppLanguage.text("外观", en: "Appearance")
            case .wallpaper: AppLanguage.text("壁纸", en: "Wallpaper")
            case .mediaLibrary: AppLanguage.text("素材库", en: "Library")
            case .typography: AppLanguage.text("字体", en: "Fonts")
            case .editing: AppLanguage.text("编辑", en: "Editing")
            case .format: AppLanguage.text("格式", en: "Format")
            case .effects: AppLanguage.text("动效", en: "Motion")
            case .models: AppLanguage.text("API 网关", en: "API Gateway")
            case .bots: AppLanguage.text("Bots", en: "Bots")
            case .memory: AppLanguage.text("偏好记忆", en: "Preferences")
            case .scheduledTasks: AppLanguage.text("定时任务", en: "Schedules")
            case .keyBindings: AppLanguage.text("快捷键", en: "Shortcuts")
            case .pass: AppLanguage.text("通行证", en: "Pass")
        }
    }
    
    var symbolName: String {
        switch self {
            case .general: "gearshape.fill"
            case .database: "internaldrive.fill"
            case .appIcon: "sparkles.rectangle.stack.fill"
            case .appearance: "paintpalette.fill"
            case .wallpaper: "photo.on.rectangle.angled"
            case .mediaLibrary: "photo.stack.fill"
            case .typography: "textformat.size"
            case .editing: "square.and.pencil"
            case .format: "doc.text.fill"
            case .effects: "wand.and.stars"
            case .models: "network"
            case .bots: "sparkles"
            case .memory: "list.bullet.indent"
            case .scheduledTasks: "clock.fill"
            case .keyBindings: "keyboard.fill"
            case .pass: "lanyardcard.fill"
        }
    }
    
    var badgeColor: Color {
        switch self {
            case .general: Color(red: 0.56, green: 0.56, blue: 0.58)
            case .database: Color(red: 0.24, green: 0.54, blue: 0.86)
            case .appIcon: Color(red: 0.85, green: 0.65, blue: 0.16)
            case .appearance: Color(red: 0.44, green: 0.36, blue: 0.70)
            case .wallpaper: Color(red: 0.18, green: 0.52, blue: 0.88)
            case .mediaLibrary: Color(red: 0.90, green: 0.42, blue: 0.56)
            case .typography: Color(red: 0.25, green: 0.48, blue: 0.92)
            case .editing: Color(red: 0.04, green: 0.52, blue: 1.00)
            case .format: Color(red: 0.14, green: 0.65, blue: 0.58)
            case .effects: Color(red: 0.96, green: 0.55, blue: 0.08)
            case .models: Color(red: 0.06, green: 0.72, blue: 0.51)
            case .bots: Color(red: 0.84, green: 0.22, blue: 0.26)
            case .memory: Color(red: 0.35, green: 0.42, blue: 0.92)
            case .scheduledTasks: Color(red: 0.08, green: 0.56, blue: 0.94)
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
    var pendingBotID: AIBotID? = nil
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
        hostingController.safeAreaRegions = []
        
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
    
    
    func openBot(_ botID: AIBotID?) {
        self.state.pendingBotID = botID
        self.openItem(.bots)
    }
}


// MARK: - Unified Design Tokens & Alignment Primitives

private enum SettingsDesignTokens {
    
    static let sidebarWidth: CGFloat = 204
    static let detailWidth: CGFloat = 575 // 204 + 1 + 575 == 780
    static let contentPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let sectionTitleSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 42
    static let cardCornerRadius: CGFloat = 12
    static let segmentedWidth: CGFloat = 188
    static let controlWidth: CGFloat = 188
    static let sliderWidth: CGFloat = 140
    static let readoutWidth: CGFloat = 40
    
    static let sidebarClusters: [[SidebarSettingsItem]] = [
        [.general, .database, .appIcon, .appearance, .wallpaper, .mediaLibrary],
        [.typography, .editing, .format, .effects],
        [.models, .bots, .memory, .scheduledTasks, .keyBindings, .pass],
    ]
}


private struct SidebarSettingsRootView: View {
    
    @Bindable var state: SidebarSettingsState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var dbStatusMessage: String?
    @State private var databaseRefreshRevision: Int = 0
    @State private var hoveredItem: SidebarSettingsItem?
    @Namespace private var sidebarSelectionNamespace
    
    
    private var resolvedColorScheme: ColorScheme? {
        switch self.documentAppearance {
            case .default: nil
            case .light: .light
            case .dark: .dark
        }
    }
    
    private var contentBackground: Color {
        let isDark = (self.resolvedColorScheme ?? self.colorScheme) == .dark
        return isDark
            ? Color(red: 0.141, green: 0.141, blue: 0.149) // #242426 Apple soft dark graphite
            : Color(red: 0.961, green: 0.961, blue: 0.969) // #F5F5F7 Apple light settings canvas
    }
    
    
    var body: some View {
        let isDark = (self.resolvedColorScheme ?? self.colorScheme) == .dark
        let accent = self.studioPalette.tokens(isDark: isDark).accent
        let onAccent = self.studioPalette.tokens(isDark: isDark).onAccentInk
        
        HStack(spacing: 0) {
            // Left Translucent Apple-style Sidebar
            ZStack(alignment: .topLeading) {
                SidebarVisualEffectBackdrop()
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 38)
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(SettingsDesignTokens.sidebarClusters.enumerated()), id: \.offset) { clusterIdx, cluster in
                                if clusterIdx > 0 {
                                    Rectangle()
                                        .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
                                        .frame(height: 0.5)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(cluster) { item in
                                        self.sidebarRow(item, isDark: isDark, accent: accent, onAccent: onAccent)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 14)
                    }
                }
            }
            .frame(width: SettingsDesignTokens.sidebarWidth)
            
            Rectangle()
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
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
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, SettingsDesignTokens.contentPadding)
                    .frame(height: 52)
                    
                    Rectangle()
                        .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                        .frame(height: 0.5)
                    
                    Group {
                        switch self.state.selectedItem {
                            case .keyBindings:
                                KeyBindingsSettingsView(usesFlexibleFrame: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            case .appIcon:
                                SidebarAppIconSettingsPane()
                                    .frame(width: SettingsDesignTokens.detailWidth)
                                    .frame(maxHeight: .infinity)
                            case .wallpaper:
                                SidebarWallpaperSettingsPane()
                                    .frame(width: SettingsDesignTokens.detailWidth)
                                    .frame(maxHeight: .infinity)
                            case .mediaLibrary:
                                MediaLibrarySettingsView()
                                    .frame(width: SettingsDesignTokens.detailWidth)
                                    .frame(maxHeight: .infinity)
                            case .memory:
                                MemoryStarMapSettingsView()
                                    .frame(width: SettingsDesignTokens.detailWidth)
                                    .frame(maxHeight: .infinity)
                            default:
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
        .ignoresSafeArea()
        .preferredColorScheme(self.resolvedColorScheme)
        .tint(accent)
        .environment(\.locale, AppLanguage.current.locale)
    }
    
    
    @ViewBuilder
    private func sidebarRow(_ item: SidebarSettingsItem, isDark: Bool, accent: Color, onAccent: Color) -> some View {
        let isSelected = (self.state.selectedItem == item)
        let isHovered = (self.hoveredItem == item)
        
        Button {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
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
                    .foregroundStyle(isSelected ? onAccent : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(isDark ? 0.84 : 0.90))
                        .matchedGeometryEffect(id: "sidebarActiveTab", in: self.sidebarSelectionNamespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.hoveredItem = hovering ? item : (self.hoveredItem == item ? nil : self.hoveredItem)
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
            case .database:
                LocalDatabaseSettingsView(
                    onExportDatabase: { self.exportLocalDatabase() },
                    onImportDatabase: { self.importLocalDatabase() },
                    refreshRevision: self.databaseRefreshRevision
                )
            case .appIcon:
                SidebarAppIconSettingsPane()
            case .appearance:
                SidebarAppearanceSettingsPane()
            case .wallpaper:
                SidebarWallpaperSettingsPane()
            case .mediaLibrary:
                EmptyView()
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
                AIBotsSettingsView(settingsState: self.state)
            case .memory:
                EmptyView()
            case .scheduledTasks:
                ScheduledAIOrganizeSettingsCard()
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
                    self.databaseRefreshRevision &+= 1
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
                        color: self.colorScheme == .dark ? Color.clear : Color.black.opacity(0.025),
                        radius: 2,
                        y: 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(self.colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.06), lineWidth: 0.5)
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
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 12)
            
            self.control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
    @State private var newUserAvatarImage: NSImage?
    @State private var copyCurrentAIConfig = true
    @State private var confirmDeleteID: String?
    @State private var editingActiveName = ""
    @State private var isEditingActiveName = false
    @State private var isShowingStoredDocs = false
    @State private var isShowingVersionDetails = false
    @State private var isShowingActiveAvatarLibrary = false
    @State private var isShowingNewUserAvatarLibrary = false
    
    
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
                        self.isShowingActiveAvatarLibrary.toggle()
                    } label: {
                        Label("头像库", systemImage: "photo.stack")
                    }
                    .controlSize(.small)
                    .popover(isPresented: self.$isShowingActiveAvatarLibrary, arrowEdge: .bottom) {
                        AvatarLibraryPickerPopover { asset in
                            _ = UserMediaLibraryStore.shared.applyAvatarToActiveUser(assetID: asset.id, profileManager: self.profileManager)
                            self.isShowingActiveAvatarLibrary = false
                        }
                    }
                    
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
                                    customImage: self.newUserAvatarImage
                                )
                            }
                            .buttonStyle(.plain)
                            .help("选择新账户头像")
                            
                            TextField("输入新用户昵称", text: self.$newUserName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { self.submitNewUser() }
                            
                            Button {
                                self.isShowingNewUserAvatarLibrary.toggle()
                            } label: {
                                Image(systemName: "photo.stack")
                            }
                            .controlSize(.small)
                            .help("从头像库选择")
                            .popover(isPresented: self.$isShowingNewUserAvatarLibrary, arrowEdge: .bottom) {
                                AvatarLibraryPickerPopover { asset in
                                    if let img = UserMediaLibraryStore.shared.fullImage(for: asset),
                                       let data = UserProfileManager.processedAvatarPNGData(from: img),
                                       let processed = NSImage(data: data)
                                    {
                                        self.newUserAvatarData = data
                                        self.newUserAvatarImage = processed
                                    }
                                    self.isShowingNewUserAvatarLibrary = false
                                }
                            }
                            
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
            
            // 3. 启动与语言
            SettingsGroupCard(title: AppLanguage.text("启动与语言", en: "Startup & Language")) {
                SettingsItemRow(label: AppLanguage.text("界面语言", en: "Language")) {
                    Picker("", selection: self.$language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(verbatim: lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    .onChange(of: self.language) { _, newValue in
                        newValue.apply()
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
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
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
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
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                        Text(AppLanguage.text("数据目录 · \(CotLocalDatabase.shared.databaseURL.deletingLastPathComponent().path)", en: "Database · \(CotLocalDatabase.shared.databaseURL.path)"))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
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
        self.newUserAvatarImage = nil
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
                  let data = UserProfileManager.processedAvatarPNGData(from: image),
                  let processed = NSImage(data: data)
            else { return }
            Task { @MainActor in
                _ = UserMediaLibraryStore.shared.importURLs([url], preferredKind: .avatar)
                if forActive {
                    self.profileManager.updateProfile(id: self.profileManager.activeProfile.id, avatarData: .some(data))
                } else {
                    self.newUserAvatarData = data
                    self.newUserAvatarImage = processed
                }
            }
        }
    }
}


// MARK: - AppKit Pan/Magnify/Drop Overlay (Prevents isMovableByWindowBackground from hijacking drag)

/// AppKit interaction surface that returns `mouseDownCanMoveWindow == false` so dragging
/// inside preview stages pans artwork smoothly without moving the Settings window.
internal final class WallpaperFramingInteractionNSView: NSView {
    
    var isInteractive: Bool = true {
        didSet {
            if self.isInteractive != oldValue {
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnd: (() -> Void)?
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)?
    var onScrollZoom: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDropTargetedChange: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDropImages: (([NSImage]) -> Void)?
    
    private var dragStartPoint: NSPoint?
    private var isCurrentlyDragging = false
    
    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.registerForDraggedTypes([.fileURL, .tiff, .png])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        guard self.isInteractive else { return }
        self.addCursorRect(self.bounds, cursor: self.isCurrentlyDragging ? .closedHand : .openHand)
    }
    
    override func mouseDown(with event: NSEvent) {
        guard self.isInteractive else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2, let onDoubleClick = self.onDoubleClick {
            onDoubleClick()
            return
        }
        let pt = self.convert(event.locationInWindow, from: nil)
        self.dragStartPoint = pt
        self.isCurrentlyDragging = true
        self.window?.invalidateCursorRects(for: self)
        NSCursor.closedHand.set()
        self.onDragStart?()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard self.isInteractive, let start = self.dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        let pt = self.convert(event.locationInWindow, from: nil)
        let translation = CGSize(width: pt.x - start.x, height: pt.y - start.y)
        self.onDragChanged?(translation)
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasDragging = self.isCurrentlyDragging
        self.dragStartPoint = nil
        self.isCurrentlyDragging = false
        self.window?.invalidateCursorRects(for: self)
        if self.isInteractive {
            NSCursor.openHand.set()
        }
        if wasDragging {
            self.onDragEnd?()
        } else {
            super.mouseUp(with: event)
        }
    }
    
    override func magnify(with event: NSEvent) {
        guard self.isInteractive else {
            super.magnify(with: event)
            return
        }
        self.onMagnify?(event.magnification, event.phase)
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard self.isInteractive, let onScrollZoom = self.onScrollZoom else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.004 : 0.025)
        if abs(delta) > 0.0001 {
            onScrollZoom(delta)
        }
    }
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let hasURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        guard hasURL || hasImage else { return [] }
        self.onDropTargetedChange?(true)
        return .copy
    }
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        self.onDropTargetedChange?(false)
    }
    
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        self.onDropTargetedChange?(false)
    }
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        self.onDropTargetedChange?(false)
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty
        {
            self.onDropURLs?(urls)
            return true
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty
        {
            self.onDropImages?(images)
            return true
        }
        return false
    }
}


internal struct WallpaperFramingInteractionOverlay: NSViewRepresentable {
    
    var isInteractive: Bool = true
    var onDragStart: (() -> Void)? = nil
    var onDragChanged: ((CGSize) -> Void)? = nil
    var onDragEnd: (() -> Void)? = nil
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)? = nil
    var onScrollZoom: ((CGFloat) -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onDropTargetedChange: ((Bool) -> Void)? = nil
    var onDropURLs: (([URL]) -> Void)? = nil
    var onDropImages: (([NSImage]) -> Void)? = nil
    
    func makeNSView(context: Context) -> WallpaperFramingInteractionNSView {
        let view = WallpaperFramingInteractionNSView()
        self.applyCallbacks(to: view)
        return view
    }
    
    func updateNSView(_ nsView: WallpaperFramingInteractionNSView, context: Context) {
        self.applyCallbacks(to: nsView)
    }
    
    private func applyCallbacks(to view: WallpaperFramingInteractionNSView) {
        view.isInteractive = self.isInteractive
        view.onDragStart = self.onDragStart
        view.onDragChanged = self.onDragChanged
        view.onDragEnd = self.onDragEnd
        view.onMagnify = self.onMagnify
        view.onScrollZoom = self.onScrollZoom
        view.onDoubleClick = self.onDoubleClick
        view.onDropTargetedChange = self.onDropTargetedChange
        view.onDropURLs = self.onDropURLs
        view.onDropImages = self.onDropImages
    }
}


// MARK: - 1B. 应用图标自定义工坊 (Pinned Live Dock Preview + Scrollable Studio Controls)

private struct SidebarAppIconSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var iconManager = AppIconManager.shared
    @State private var isDropTargeted = false
    @State private var dragStartOffset: CGSize?
    
    private var customRimBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.iconManager.spec.customBorderHex) },
            set: { newColor in
                self.iconManager.updateSpecLive { spec in
                    spec.customBorderHex = StudioPaletteManager.hexString(from: NSColor(newColor))
                }
            }
        )
    }
    
    private var matColorBinding: Binding<Color> {
        Binding(
            get: { StudioPaletteManager.swiftUIColor(hex: self.iconManager.spec.backgroundMatHex) },
            set: { newColor in
                self.iconManager.updateSpecLive { spec in
                    spec.backgroundMatHex = StudioPaletteManager.hexString(from: NSColor(newColor))
                }
            }
        )
    }
    
    
    var body: some View {
        let _ = self.iconManager.customImageVersion
        let _ = self.iconManager.previewRevision
        
        VStack(spacing: 0) {
            // Pinned Live Dock Showcase (always stays visible when adjusting controls below)
            VStack(spacing: 10) {
                SettingsGroupCard(title: nil) {
                    VStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: self.colorScheme == .dark
                                            ? [Color(red: 0.12, green: 0.13, blue: 0.18), Color(red: 0.08, green: 0.09, blue: 0.13)]
                                            : [Color(red: 0.90, green: 0.91, blue: 0.95), Color(red: 0.84, green: 0.86, blue: 0.91)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            // Frosted mini Dock shelf + neighbor squircles for scale reference
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(width: 246, height: 34)
                                .offset(y: 38)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(Color.white.opacity(self.colorScheme == .dark ? 0.14 : 0.45), lineWidth: 0.6)
                                        .frame(width: 246, height: 34)
                                        .offset(y: 38)
                                )
                                .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.35 : 0.10), radius: 10, y: 4)
                            
                            HStack(alignment: .bottom, spacing: 14) {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 44, height: 44)
                                    .offset(y: -4)
                                
                                Image(nsImage: self.iconManager.previewImage)
                                    .resizable()
                                    .interpolation(.high)
                                    .id(self.iconManager.previewRevision)
                                    .frame(width: 96, height: 96)
                                    .scaleEffect(self.isDropTargeted ? 1.06 : 1.0)
                                    .animation(.spring(response: 0.24, dampingFraction: 0.76), value: self.isDropTargeted)
                                
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 44, height: 44)
                                    .offset(y: -4)
                            }
                            .offset(y: 4)
                            
                            WallpaperFramingInteractionOverlay(
                                isInteractive: true,
                                onDragStart: {
                                    self.dragStartOffset = CGSize(
                                        width: self.iconManager.spec.imageOffsetX,
                                        height: self.iconManager.spec.imageOffsetY
                                    )
                                },
                                onDragChanged: { translation in
                                    let base = self.dragStartOffset ?? .zero
                                    self.iconManager.updateSpecLive { spec in
                                        spec.imageOffsetX = base.width + Double(translation.width) / 140.0
                                        spec.imageOffsetY = base.height - Double(translation.height) / 140.0
                                    }
                                },
                                onDragEnd: {
                                    self.dragStartOffset = nil
                                },
                                onDropTargetedChange: { targeted in
                                    self.isDropTargeted = targeted
                                },
                                onDropURLs: { urls in
                                    if let first = urls.first(where: { NSImage(contentsOf: $0) != nil }),
                                       let image = NSImage(contentsOf: first)
                                    {
                                        _ = self.iconManager.saveCustomImage(image)
                                    }
                                },
                                onDropImages: { images in
                                    if let first = images.first {
                                        _ = self.iconManager.saveCustomImage(first)
                                    }
                                }
                            )
                        }
                        .frame(height: 124)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    self.isDropTargeted ? Color.accentColor : Color.clear,
                                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                                )
                                .allowsHitTesting(false)
                        )
                        
                        HStack(spacing: 8) {
                            Text(self.iconManager.spec.borderStyle.displayName)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05), in: Capsule())
                            
                            Text("\(Int((self.iconManager.spec.imageZoom * 100).rounded()))%")
                                .font(.system(size: 11.5, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.05), in: Capsule())
                            
                            Spacer()
                            
                            if abs(self.iconManager.spec.imageOffsetX) > 0.01 || abs(self.iconManager.spec.imageOffsetY) > 0.01 {
                                Button(AppLanguage.text("画面居中", en: "Center")) {
                                    self.iconManager.updateSpecLive { spec in
                                        spec.imageOffsetX = 0
                                        spec.imageOffsetY = 0
                                    }
                                }
                                .controlSize(.small)
                            }
                            
                            Button(AppLanguage.text("恢复默认", en: "Reset")) {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                                    self.iconManager.resetToDefault()
                                }
                            }
                            .controlSize(.small)
                            
                            Button(AppLanguage.text("上传图片", en: "Upload")) {
                                self.pickCustomArtwork()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
            }
            .padding(.horizontal, SettingsDesignTokens.contentPadding)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider()
            
            // Scrollable Studio Controls below the pinned preview
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
                    // Built-in Chiikawa Artwork & Custom Source
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
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                        self.iconManager.updateSpecLive { $0.source = source }
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
                                        .frame(width: 54, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(
                                                    isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                                                    lineWidth: isSelected ? 2.0 : 0.5
                                                )
                                        )
                                        
                                        Text(source.displayName)
                                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
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
                    
                    // Rim / Gold Inlay Style Presets
                    SettingsGroupCard(title: AppLanguage.text("边框", en: "Frame")) {
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                                ForEach(AppIconBorderStyle.allCases) { style in
                                    let isSelected = (self.iconManager.spec.borderStyle == style)
                                    Button {
                                        withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                                            self.iconManager.updateSpecLive { spec in
                                                spec.borderStyle = style
                                                if style != .clean && spec.borderWidth < 1.5 {
                                                    spec.borderWidth = 4.6
                                                }
                                            }
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
                                        .frame(height: 30)
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
                    
                    // Stepless Fine-Tuning Controls (zero corner badge!)
                    SettingsGroupCard(title: AppLanguage.text("样式", en: "Style")) {
                        SettingsItemRow(label: AppLanguage.text("镶边粗细", en: "Border Width")) {
                            HStack(spacing: 8) {
                                Slider(
                                    value: Binding(
                                        get: { self.iconManager.spec.borderWidth },
                                        set: { newValue in
                                            self.iconManager.updateSpecLive { spec in
                                                spec.borderWidth = newValue
                                                if newValue > 0.25 && spec.borderStyle == .clean {
                                                    spec.borderStyle = .goldInlay
                                                }
                                            }
                                        }
                                    ),
                                    in: 0...10
                                )
                                .frame(width: SettingsDesignTokens.sliderWidth)
                                Text(String(format: "%.1f", self.iconManager.spec.borderWidth))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                            }
                            .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                        }
                        
                        SettingsRowDivider()
                        
                        SettingsItemRow(label: AppLanguage.text("画面缩放", en: "Artwork Zoom")) {
                            HStack(spacing: 8) {
                                Slider(value: self.specBinding(\.imageZoom), in: 0.80...1.35)
                                    .frame(width: SettingsDesignTokens.sliderWidth)
                                Text("\(Int((self.iconManager.spec.imageZoom * 100).rounded()))%")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                            }
                            .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                        }
                        
                        SettingsRowDivider()
                        
                        SettingsItemRow(label: AppLanguage.text("圆角曲率", en: "Corner Curvature")) {
                            HStack(spacing: 8) {
                                Slider(value: self.specBinding(\.cornerRoundness), in: 0.16...0.50)
                                    .frame(width: SettingsDesignTokens.sliderWidth)
                                Text("\(Int((self.iconManager.spec.cornerRoundness * 100).rounded()))%")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                            }
                            .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                        }
                        
                        SettingsRowDivider()
                        
                        SettingsItemRow(label: AppLanguage.text("表面水晶流光", en: "Crystal Gloss")) {
                            HStack(spacing: 8) {
                                Slider(value: self.specBinding(\.glossIntensity), in: 0.0...1.0)
                                    .frame(width: SettingsDesignTokens.sliderWidth)
                                Text("\(Int((self.iconManager.spec.glossIntensity * 100).rounded()))%")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                            }
                            .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
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
                .padding(.horizontal, SettingsDesignTokens.contentPadding)
                .padding(.vertical, 16)
            }
        }
    }
    
    
    private func specBinding<T: Equatable>(_ keyPath: WritableKeyPath<AppIconSpec, T>) -> Binding<T> {
        Binding(
            get: { self.iconManager.spec[keyPath: keyPath] },
            set: { newValue in
                self.iconManager.updateSpecLive { spec in
                    spec[keyPath: keyPath] = newValue
                }
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


// MARK: - 1C. 壁纸 (Pinned Interactive Crop/Pan Studio + Cached Gallery Grid)

private struct SidebarWallpaperSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var manager = WallpaperManager.shared
    @State private var mediaLibrary = UserMediaLibraryStore.shared
    @State private var hoveredID: String?
    @State private var isDropTargeted = false
    @State private var dragStartFraming: WallpaperFraming?
    @State private var magnifyStartScale: Double?
    @State private var isFramingActive = false
    @State private var showViewfinderGrid = false
    
    
    var body: some View {
        let _ = self.manager.catalogVersion
        let _ = self.mediaLibrary.revision
        let items = self.manager.allItems
        let selectedItem = items.first { $0.id == self.manager.spec.selectedID } ?? items.first
        let framing = self.manager.spec.currentFraming
        
        VStack(spacing: 0) {
            self.pinnedPreviewSection(selectedItem: selectedItem, framing: framing)
            Divider()
            self.scrollableControlsSection(items: items)
        }
    }
    
    
    private func pinnedPreviewSection(selectedItem: WallpaperItem?, framing: WallpaperFraming) -> some View {
        VStack(spacing: 0) {
            SettingsGroupCard(title: nil) {
                VStack(spacing: 10) {
                    self.liveEditorPreviewStage(selectedItem: selectedItem)
                        .frame(height: 204)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    self.isDropTargeted
                                        ? StudioPaletteManager.shared.activeAccentColor
                                        : ((self.isFramingActive || self.showViewfinderGrid)
                                            ? StudioPaletteManager.shared.activeAccentColor.opacity(0.65)
                                            : (self.colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))),
                                    style: self.isDropTargeted
                                        ? StrokeStyle(lineWidth: 2, dash: [6, 4])
                                        : StrokeStyle(lineWidth: (self.isFramingActive || self.showViewfinderGrid) ? 1.3 : 0.75)
                                )
                                .allowsHitTesting(false)
                        )
                    
                    HStack(spacing: 7) {
                        if let selectedItem {
                            Circle()
                                .fill(Color(hexString: selectedItem.accentHex))
                                .frame(width: 7, height: 7)
                            Text(selectedItem.title)
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                        }
                        
                        Picker("", selection: Binding(
                            get: { self.manager.spec.displayMode },
                            set: { mode in
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                    self.manager.updateFraming(displayMode: mode)
                                }
                            }
                        )) {
                            ForEach(WallpaperDisplayMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 144)
                        
                        Spacer(minLength: 4)
                        
                        Button {
                            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                                self.showViewfinderGrid.toggle()
                            }
                        } label: {
                            Image(systemName: self.showViewfinderGrid ? "viewfinder.circle.fill" : "viewfinder")
                        }
                        .controlSize(.small)
                        .tint(self.showViewfinderGrid ? StudioPaletteManager.shared.activeAccentColor : nil)
                        .help(AppLanguage.text("构图网格", en: "Grid"))
                        
                        if !framing.isDefault {
                            Button(AppLanguage.text("重置", en: "Reset")) {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                                    self.manager.resetFraming()
                                }
                            }
                            .controlSize(.small)
                        }
                        
                        if let selectedItem, selectedItem.isCustom {
                            Button(role: .destructive) {
                                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
                                    self.manager.deleteCustomWallpaper(id: selectedItem.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .help(AppLanguage.text("删除壁纸", en: "Delete"))
                        }
                        
                        Button {
                            UserMediaLibraryImporter.presentFolderPicker(preferredKind: .background) { result in
                                if let firstID = result.firstAddedBackgroundID {
                                    _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: firstID, wallpaperManager: self.manager)
                                }
                            }
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .controlSize(.small)
                        .help(AppLanguage.text("导入背景文件夹", en: "Import Background Folder"))
                        
                        Button {
                            self.pickCustomWallpaperImage()
                        } label: {
                            Label(AppLanguage.text("上传", en: "Upload"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
        }
        .padding(.horizontal, SettingsDesignTokens.contentPadding)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
    
    
    private func scrollableControlsSection(items: [WallpaperItem]) -> some View {
        let zoomRange = self.manager.spec.displayMode.minScale...WallpaperDisplayMode.maxScale
        
        return ScrollView {
            VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
                SettingsGroupCard(title: AppLanguage.text("画面调整", en: "Framing & Display")) {
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
                    
                    SettingsItemRow(label: AppLanguage.text("缩放比例", en: "Zoom")) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { self.manager.spec.scale },
                                    set: { self.manager.updateFraming(scale: $0) }
                                ),
                                in: zoomRange
                            )
                            .frame(width: SettingsDesignTokens.sliderWidth)
                            .disabled(!self.manager.spec.isEnabled)
                            
                            Text("\(Int((self.manager.spec.scale * 100).rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                        }
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    }
                    
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("画面浓度", en: "Opacity")) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { self.manager.spec.opacity },
                                    set: { self.manager.spec.opacity = $0 }
                                ),
                                in: 0.04...0.85
                            )
                            .frame(width: SettingsDesignTokens.sliderWidth)
                            .disabled(!self.manager.spec.isEnabled)
                            
                            Text("\(Int((self.manager.spec.opacity * 100).rounded()))%")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                        }
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    }
                    
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("柔焦模糊", en: "Soft Blur")) {
                        HStack(spacing: 8) {
                            Slider(
                                value: Binding(
                                    get: { self.manager.spec.blurRadius },
                                    set: { self.manager.spec.blurRadius = $0 }
                                ),
                                in: 0...40
                            )
                            .frame(width: SettingsDesignTokens.sliderWidth)
                            .disabled(!self.manager.spec.isEnabled)
                            
                            Text("\(Int(self.manager.spec.blurRadius.rounded())) px")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                        }
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                    }
                }
                
                if !self.mediaLibrary.backgrounds.isEmpty {
                    SettingsGroupCard(title: AppLanguage.text("我的背景库", en: "My Background Library")) {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                            spacing: 8
                        ) {
                            ForEach(self.mediaLibrary.backgrounds) { asset in
                                self.backgroundLibraryTile(asset)
                            }
                        }
                        .padding(12)
                    }
                }
                
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
            }
            .padding(.horizontal, SettingsDesignTokens.contentPadding)
            .padding(.vertical, 16)
        }
    }
    
    
    @ViewBuilder
    private func liveEditorPreviewStage(selectedItem: WallpaperItem?) -> some View {
        let isDark = (self.colorScheme == .dark)
        let editorBase = isDark ? Color(red: 0.09, green: 0.095, blue: 0.11) : Color(red: 0.985, green: 0.985, blue: 0.99)
        let studioMat = isDark ? Color(red: 0.055, green: 0.06, blue: 0.075) : Color(red: 0.89, green: 0.90, blue: 0.92)
        let artwork = selectedItem.map { self.manager.artworkImage(for: $0.id) }
        let accent = selectedItem.map { Color(hexString: $0.accentHex) } ?? StudioPaletteManager.shared.activeAccentColor
        let framingMode = (self.isFramingActive || self.showViewfinderGrid)
        let previewAlpha = framingMode
            ? 0.94
            : (self.manager.spec.isEnabled ? min(0.95, max(0.20, self.manager.spec.opacity * 1.45)) : 0.16)
        let previewBlur = framingMode
            ? 0.0
            : (self.manager.spec.isEnabled ? min(16, self.manager.spec.blurRadius * 0.42) : 0.0)
        let windowAspect = WallpaperManager.referenceWindowAspectRatio()
        
        GeometryReader { outerGeo in
            // Apple-style true window-aspect miniature preview centered inside the dark studio matte.
            let viewportRect = MediaAssetCropEditorSheet.fittedCropRect(
                in: outerGeo.size,
                aspect: windowAspect,
                inset: 10
            )
            let drawInViewport = artwork.map {
                WallpaperManager.framedDrawRect(
                    imageSize: $0.size,
                    viewportSize: viewportRect.size,
                    scale: self.manager.spec.scale,
                    panX: self.manager.spec.panX,
                    panY: self.manager.spec.panY,
                    isFlippedY: true,
                    displayMode: self.manager.spec.displayMode
                )
            } ?? .zero
            
            ZStack(alignment: .topLeading) {
                studioMat
                
                // Apple Photos / Lock Screen style out-of-frame ghost peek while dragging or zooming.
                if framingMode, let artwork, !drawInViewport.isEmpty {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: max(1, drawInViewport.width), height: max(1, drawInViewport.height))
                        .position(
                            x: viewportRect.minX + drawInViewport.midX,
                            y: viewportRect.minY + drawInViewport.midY
                        )
                        .opacity(0.24)
                }
                
                // True-aspect miniature CotEditor window stage.
                ZStack(alignment: .topLeading) {
                    editorBase
                        .overlay(alignment: .topLeading) {
                            if let artwork, !drawInViewport.isEmpty {
                                Image(nsImage: artwork)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: max(1, drawInViewport.width), height: max(1, drawInViewport.height))
                                    .position(x: drawInViewport.midX, y: drawInViewport.midY)
                                    .blur(radius: previewBlur)
                                    .opacity(previewAlpha)
                                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20), value: selectedItem?.id)
                            }
                        }
                        .frame(width: viewportRect.width, height: viewportRect.height)
                        .clipped()
                    
                    self.miniEditorChrome(isDark: isDark, accent: accent, framingMode: framingMode)
                        .allowsHitTesting(false)
                    
                    if framingMode {
                        self.viewfinderOverlay(size: viewportRect.size, accent: accent)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: viewportRect.width, height: viewportRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            framingMode ? accent.opacity(0.92) : (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.16)),
                            lineWidth: framingMode ? 1.5 : 0.8
                        )
                )
                .shadow(color: Color.black.opacity(isDark ? 0.42 : 0.16), radius: 8, y: 3)
                .offset(x: viewportRect.minX, y: viewportRect.minY)
                
                // Direct AppKit pan / pinch / scroll-zoom / double-click / drop surface across the full stage.
                WallpaperFramingInteractionOverlay(
                    isInteractive: artwork != nil,
                    onDragStart: {
                        guard artwork != nil else { return }
                        if !self.manager.spec.isEnabled { self.manager.spec.isEnabled = true }
                        self.dragStartFraming = self.manager.spec.currentFraming
                        self.isFramingActive = true
                    },
                    onDragChanged: { translation in
                        guard let artwork else { return }
                        let start = self.dragStartFraming ?? self.manager.spec.currentFraming
                        let updated = WallpaperManager.dragUpdatedFraming(
                            start: start,
                            imageSize: artwork.size,
                            viewportSize: viewportRect.size,
                            translation: translation
                        )
                        self.manager.updateFraming(
                            scale: updated.scale,
                            panX: updated.panX,
                            panY: updated.panY,
                            displayMode: updated.displayMode
                        )
                    },
                    onDragEnd: {
                        self.dragStartFraming = nil
                        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
                            self.isFramingActive = false
                        }
                    },
                    onMagnify: { magnificationDelta, phase in
                        if !self.manager.spec.isEnabled { self.manager.spec.isEnabled = true }
                        if phase == .began { self.isFramingActive = true }
                        self.manager.updateFraming(scale: self.manager.spec.scale * (1.0 + Double(magnificationDelta)))
                        if phase == .ended || phase == .cancelled {
                            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
                                self.isFramingActive = false
                            }
                        }
                    },
                    onScrollZoom: { delta in
                        if !self.manager.spec.isEnabled { self.manager.spec.isEnabled = true }
                        self.manager.updateFraming(scale: self.manager.spec.scale * (1.0 + Double(delta)))
                    },
                    onDoubleClick: {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                            if self.manager.spec.currentFraming.isDefault {
                                self.manager.updateFraming(scale: 1.6)
                            } else {
                                self.manager.resetFraming()
                            }
                        }
                    },
                    onDropTargetedChange: { targeted in self.isDropTargeted = targeted },
                    onDropURLs: { urls in self.handleDroppedURLs(urls) },
                    onDropImages: { images in self.handleDroppedImages(images) }
                )
                
                if self.isDropTargeted {
                    ZStack {
                        Color.black.opacity(0.35)
                        Text(AppLanguage.text("松手设为壁纸", en: "Drop to Set Wallpaper"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(accent, in: Capsule())
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
        }
    }
    
    
    private func miniEditorChrome(isDark: Bool, accent: Color, framingMode: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 0.95, green: 0.37, blue: 0.35)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 0.96, green: 0.74, blue: 0.26)).frame(width: 6, height: 6)
                Circle().fill(Color(red: 0.30, green: 0.78, blue: 0.38)).frame(width: 6, height: 6)
                Spacer()
                Text("\(Int((self.manager.spec.scale * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .opacity(framingMode ? 0.95 : 0.65)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(isDark ? Color.black.opacity(0.28) : Color.white.opacity(0.62))
            
            Divider().opacity(0.25)
            
            VStack(alignment: .leading, spacing: 7) {
                self.sampleCodeRow(line: "1", segments: [(accent, 36), (.primary.opacity(0.75), 82), (.secondary.opacity(0.45), 52)])
                self.sampleCodeRow(line: "2", segments: [(.clear, 14), (.primary.opacity(0.65), 98), (accent.opacity(0.75), 44)])
                self.sampleCodeRow(line: "3", segments: [(.clear, 14), (.secondary.opacity(0.50), 120)])
                self.sampleCodeRow(line: "4", segments: [(.clear, 26), (accent.opacity(0.85), 50), (.primary.opacity(0.70), 68)])
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .opacity(framingMode ? 0.14 : 0.96)
            .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.16), value: framingMode)
            
            Spacer(minLength: 0)
        }
    }
    
    
    @ViewBuilder
    private func viewfinderOverlay(size: CGSize, accent: Color) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Path { path in
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3.0
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    let y = size.height * CGFloat(i) / 3.0
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.36), lineWidth: 0.75)
            
            Text("\(self.manager.spec.displayMode.label) · \(Int((self.manager.spec.scale * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.58), in: Capsule())
                .padding(8)
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
                    .fixedSize(horizontal: false, vertical: true)
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
    
    
    @ViewBuilder
    private func backgroundLibraryTile(_ asset: UserMediaAsset) -> some View {
        let libWallpaperID = WallpaperManager.mediaLibraryWallpaperID(for: asset.id)
        let isSelected = (self.manager.spec.selectedID == libWallpaperID)
        let isHovered = (self.hoveredID == libWallpaperID)
        let accent = StudioPaletteManager.shared.activeAccentColor
        let thumb = self.mediaLibrary.thumbnailImage(for: asset, maxPixelSize: 320)
        
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: asset.id, wallpaperManager: self.manager)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumb {
                            Image(nsImage: thumb)
                                .resizable()
                                .interpolation(.medium)
                                .scaledToFill()
                        } else {
                            Rectangle().fill(Color.primary.opacity(0.08))
                        }
                    }
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
                
                Text(asset.title)
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
                self.hoveredID = inside ? libWallpaperID : (self.hoveredID == libWallpaperID ? nil : self.hoveredID)
            }
        }
    }
    
    
    private func pickCustomWallpaperImage() {
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("选择壁纸图片", en: "Choose Wallpaper Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let urls = panel.urls
            Task { @MainActor in
                self.handleDroppedURLs(urls)
            }
        }
    }
    
    
    private func handleDroppedURLs(_ urls: [URL]) {
        let result = self.mediaLibrary.importURLs(urls, preferredKind: .background)
        if let firstID = result.firstAddedBackgroundID {
            _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: firstID, wallpaperManager: self.manager)
            return
        }
        if let firstURL = urls.first {
            let outcome = self.mediaLibrary.addImage(from: firstURL, kind: .background)
            if let existing = outcome.asset {
                _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: existing.id, wallpaperManager: self.manager)
            } else {
                _ = self.manager.saveCustomWallpaper(from: firstURL)
            }
        }
    }
    
    
    private func handleDroppedImages(_ images: [NSImage]) {
        guard let first = images.first else { return }
        let title = "自定义壁纸 \(self.manager.customRecords.count + 1)"
        let outcome = self.mediaLibrary.addImage(first, title: title, kind: .background)
        if let asset = outcome.asset {
            _ = self.mediaLibrary.applyBackgroundToEditorWallpaper(assetID: asset.id, wallpaperManager: self.manager)
        } else {
            _ = self.manager.saveCustomWallpaper(first, title: title)
        }
    }
}


// MARK: - 2. 字体 (Zero-Popup Inline Font Picker)

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


// MARK: - 3. 外观 (Apple-Native Soft Appearance & Adaptive Color Palettes)

private struct SidebarAppearanceSettingsPane: View {
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @AppStorage(.windowAlpha) private var windowAlpha
    @State private var studioPalette = StudioPaletteManager.shared
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let activePreview = self.studioPalette.softPreviewColors(for: self.studioPalette.selectedID, isDark: isDark)
        
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            // 1. 外观模式（Apple 原生浅色 / 深色 / 自动缩略图选择）
            SettingsGroupCard(title: AppLanguage.text("外观", en: "Appearance")) {
                AppearanceModeThumbnailsRow(
                    selectedMode: self.documentAppearance,
                    accent: activePreview.swatch,
                    isDark: isDark
                ) { newMode in
                    withAnimation(.easeInOut(duration: 0.22)) {
                        self.studioPalette.applyAppearanceMode(newMode)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            
            // 2. 主题配色（柔和适配当前深浅外观，消除刺眼黑块与重框对比）
            SettingsGroupCard(title: AppLanguage.text("主题配色", en: "Color Palettes")) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(StudioPaletteID.allCases) { preset in
                        AppearancePaletteCard(
                            preset: preset,
                            preview: self.studioPalette.softPreviewColors(for: preset, isDark: isDark),
                            isSelected: self.studioPalette.selectedID == preset,
                            isDark: isDark
                        ) {
                            withAnimation(.easeInOut(duration: 0.20)) {
                                self.studioPalette.selectPalette(preset, syncEditorTheme: true)
                            }
                        }
                    }
                }
                .padding(12)
            }
            
            // 3. 窗口透明度与光标配色
            SettingsGroupCard(title: AppLanguage.text("窗口与光标", en: "Window & Cursor")) {
                SettingsItemRow(label: AppLanguage.text("窗口不透明度", en: "Window Opacity")) {
                    HStack(spacing: 8) {
                        Slider(value: self.$windowAlpha, in: 0.2...1.0)
                            .frame(width: SettingsDesignTokens.sliderWidth)
                        Text(self.windowAlpha, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: SettingsDesignTokens.readoutWidth, alignment: .trailing)
                    }
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("光标颜色", en: "Insertion Point")) {
                    CustomCursorColorControl()
                }
            }
        }
    }
}


private struct AppearanceModeThumbnailsRow: View {
    
    let selectedMode: AppearanceMode
    let accent: Color
    let isDark: Bool
    let onSelect: (AppearanceMode) -> Void
    
    private static let orderedModes: [AppearanceMode] = [.light, .dark, .default]
    
    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.orderedModes, id: \.self) { mode in
                AppearanceModeThumbnailCard(
                    mode: mode,
                    isSelected: self.selectedMode == mode,
                    accent: self.accent,
                    isDark: self.isDark,
                    onSelect: { self.onSelect(mode) }
                )
            }
        }
    }
}


private struct AppearanceModeThumbnailCard: View {
    
    let mode: AppearanceMode
    let isSelected: Bool
    let accent: Color
    let isDark: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    private var title: String {
        switch self.mode {
            case .light: AppLanguage.text("浅色", en: "Light")
            case .dark: AppLanguage.text("深色", en: "Dark")
            case .default: AppLanguage.text("自动", en: "Auto")
        }
    }
    
    var body: some View {
        Button(action: self.onSelect) {
            VStack(spacing: 7) {
                self.thumbnailArtwork
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                self.isDark
                                    ? Color.white.opacity(self.isHovered ? 0.16 : 0.10)
                                    : Color.black.opacity(self.isHovered ? 0.14 : 0.08),
                                lineWidth: 0.6
                            )
                    )
                    .padding(2.5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                            .strokeBorder(
                                self.isSelected ? self.accent.opacity(0.82) : Color.clear,
                                lineWidth: 1.75
                            )
                    )
                
                Text(self.title)
                    .font(.system(size: 12, weight: self.isSelected ? .semibold : .regular))
                    .foregroundStyle(self.isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    
    @ViewBuilder
    private var thumbnailArtwork: some View {
        switch self.mode {
            case .light:
                self.miniDesktopMockup(dark: false)
            case .dark:
                self.miniDesktopMockup(dark: true)
            case .default:
                HStack(spacing: 0) {
                    self.miniDesktopMockup(dark: false)
                    self.miniDesktopMockup(dark: true)
                }
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 0.5)
                )
        }
    }
    
    
    private func miniDesktopMockup(dark: Bool) -> some View {
        let backdropTop = dark
            ? Color(red: 0.20, green: 0.22, blue: 0.27)
            : Color(red: 0.90, green: 0.93, blue: 0.97)
        let backdropBottom = dark
            ? Color(red: 0.25, green: 0.27, blue: 0.33)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
        let windowSurface = dark
            ? Color(red: 0.21, green: 0.215, blue: 0.24)
            : Color.white
        let sidebarSurface = dark
            ? Color(red: 0.255, green: 0.26, blue: 0.29)
            : Color(red: 0.955, green: 0.96, blue: 0.975)
        let lineColor = dark ? Color.white.opacity(0.20) : Color.black.opacity(0.11)
        let faintLine = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
        
        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [backdropTop, backdropBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            
            // Soft floating miniature macOS window
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2.5) {
                        Circle().fill(Color(red: 0.90, green: 0.48, blue: 0.45).opacity(0.75)).frame(width: 3.5, height: 3.5)
                        Circle().fill(Color(red: 0.92, green: 0.74, blue: 0.38).opacity(0.75)).frame(width: 3.5, height: 3.5)
                        Circle().fill(Color(red: 0.45, green: 0.78, blue: 0.52).opacity(0.75)).frame(width: 3.5, height: 3.5)
                    }
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(lineColor)
                        .frame(width: 14, height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(faintLine)
                        .frame(width: 10, height: 2.5)
                    Spacer(minLength: 0)
                }
                .padding(.top, 5)
                .padding(.leading, 5)
                .frame(width: 26, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(sidebarSurface)
                
                VStack(alignment: .leading, spacing: 4.5) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(self.accent.opacity(dark ? 0.65 : 0.55))
                        .frame(width: 22, height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(lineColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(faintLine)
                        .frame(width: 34, height: 2.5)
                    Spacer(minLength: 0)
                }
                .padding(.top, 7)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(windowSurface)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(dark ? 0.22 : 0.07), radius: 3, y: 1)
            .padding(.top, 9)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.bottom, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


private struct AppearancePaletteCard: View {
    
    let preset: StudioPaletteID
    let preview: StudioPalettePreviewColors
    let isSelected: Bool
    let isDark: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        let cardFill: Color = if self.isSelected {
            self.isDark ? Color.white.opacity(0.08) : Color.white
        } else if self.isHovered {
            self.isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.032)
        } else {
            self.isDark ? Color.white.opacity(0.025) : Color.black.opacity(0.016)
        }
        
        let borderStroke: Color = if self.isSelected {
            self.preview.swatch.opacity(self.isDark ? 0.58 : 0.48)
        } else if self.isHovered {
            self.isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.10)
        } else {
            self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
        }
        
        Button(action: self.onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                AppearancePalettePreviewStrip(preview: self.preview, isDark: self.isDark)
                
                HStack(spacing: 7) {
                    Circle()
                        .fill(self.preview.swatch)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .strokeBorder(self.isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10), lineWidth: 0.5)
                        )
                    
                    Text(self.preset.displayName)
                        .font(.system(size: 12.5, weight: self.isSelected ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(self.isSelected ? 1.0 : 0.86))
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    if self.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(self.preview.swatch)
                    }
                }
                .padding(.horizontal, 2)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cardFill)
                    .shadow(
                        color: (self.isSelected && !self.isDark) ? Color.black.opacity(0.05) : Color.clear,
                        radius: 4,
                        y: 1.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderStroke, lineWidth: self.isSelected ? 1.15 : 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
}


private struct AppearancePalettePreviewStrip: View {
    
    let preview: StudioPalettePreviewColors
    let isDark: Bool
    
    var body: some View {
        ZStack(alignment: .leading) {
            self.preview.canvas
            
            LinearGradient(
                colors: [self.preview.ambientWash, Color.clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            
            HStack(spacing: 0) {
                // Soft sidebar sliver
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.preview.accent.opacity(0.75))
                        .frame(width: 18, height: 3.5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.preview.lineSecondary)
                        .frame(width: 24, height: 2.5)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.preview.lineSecondary)
                        .frame(width: 15, height: 2.5)
                }
                .padding(.horizontal, 7)
                .frame(width: 44, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(self.preview.sidebar)
                
                Rectangle()
                    .fill(self.isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                    .frame(width: 0.5)
                
                // Clean airy editor preview lines
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(self.preview.accent.opacity(0.82))
                            .frame(width: 28, height: 3.5)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(self.preview.linePrimary)
                            .frame(width: 46, height: 3)
                    }
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.preview.linePrimary)
                        .frame(maxWidth: 118)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(self.preview.lineSecondary)
                        .frame(maxWidth: 78)
                        .frame(height: 3)
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.055), lineWidth: 0.5)
        )
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
                SettingsItemRow(label: "纯文本 / Markdown 内嵌贴图") {
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
                        Text("无").tag(SyntaxName.none)
                        Divider()
                        ForEach(self.syntaxNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                }
            }
            
            SettingsGroupCard(title: AppLanguage.text("编码识别", en: "Encoding Detection")) {
                SettingsItemRow(label: AppLanguage.text("识别文档内编码声明", en: "Refer to Encoding Tag")) {
                    Toggle("", isOn: self.$referToEncodingTag)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
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
}


// MARK: - 6. 动效

private struct SidebarEffectsSettingsPane: View {
    
    @State private var typewriterEnabled = true
    @State private var typewriterStyle: TypingEffectPreset = .powerMode
    @State private var vimCursorTrailEnabled = true
    @State private var autoPersonalityEnabled = true
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionSpacing) {
            SettingsGroupCard(title: AppLanguage.text("编辑器动效", en: "Editor Motion")) {
                SettingsItemRow(label: AppLanguage.text("打字粒子特效", en: "Typing Particles")) {
                    Toggle("", isOn: self.$typewriterEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.typewriterEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                            UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
                        }
                }
                
                if self.typewriterEnabled {
                    SettingsRowDivider()
                    
                    SettingsItemRow(label: AppLanguage.text("粒子风格", en: "Particle Style")) {
                        Picker("", selection: self.$typewriterStyle) {
                            ForEach(TypingEffectPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: SettingsDesignTokens.controlWidth, alignment: .trailing)
                        .onChange(of: self.typewriterStyle) { _, val in
                            CotLocalDatabase.shared.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                            UserDefaults.standard.set(val.rawValue, forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
                        }
                    }
                }
                
                SettingsRowDivider()
                
                SettingsItemRow(label: AppLanguage.text("Vim 流体光标尾迹", en: "Vim Fluid Cursor Trail")) {
                    Toggle("", isOn: self.$vimCursorTrailEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: self.vimCursorTrailEnabled) { _, val in
                            CotLocalDatabase.shared.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                            UserDefaults.standard.set(val, forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
                        }
                }
                
                SettingsRowDivider()
                
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
