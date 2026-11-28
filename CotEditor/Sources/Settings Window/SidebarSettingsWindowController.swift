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
import Defaults
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar Navigation Model (11 Focused Tabs in 2 Groups)

enum SidebarSettingsItem: String, CaseIterable, Identifiable, Sendable {
    
    case profile
    case general
    case appearance
    case typography
    case editing
    case models
    case bots
    case memory
    case scheduledTasks
    case keyBindings
    case pass
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
            case .profile: AppLanguage.text("个人", en: "Profile")
            case .general: AppLanguage.text("通用", en: "General")
            case .appearance: AppLanguage.text("外观", en: "Appearance")
            case .typography: AppLanguage.text("字体", en: "Fonts")
            case .editing: AppLanguage.text("编辑", en: "Editing")
            case .models: AppLanguage.text("API 网关", en: "API Gateway")
            case .bots: "Bots"
            case .memory: "Memory"
            case .scheduledTasks: AppLanguage.text("定时任务", en: "Schedules")
            case .keyBindings: AppLanguage.text("快捷键", en: "Shortcuts")
            case .pass: AppLanguage.text("通行证", en: "Pass")
        }
    }
    
    var symbolName: String {
        switch self {
            case .profile: "person.crop.circle.fill"
            case .general: "gearshape.fill"
            case .appearance: "paintpalette.fill"
            case .typography: "textformat.size"
            case .editing: "square.and.pencil"
            case .models: "network"
            case .bots: "bubble.left.and.bubble.right.fill"
            case .memory: "list.bullet.indent"
            case .scheduledTasks: "clock.fill"
            case .keyBindings: "keyboard.fill"
            case .pass: "lanyardcard.fill"
        }
    }
    
    var badgeColor: Color {
        switch self {
            case .profile: Color(red: 0.24, green: 0.54, blue: 0.86)
            case .general: Color(red: 0.56, green: 0.56, blue: 0.58)
            case .appearance: Color(red: 0.44, green: 0.36, blue: 0.70)
            case .typography: Color(red: 0.25, green: 0.48, blue: 0.92)
            case .editing: Color(red: 0.04, green: 0.52, blue: 1.00)
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
            case .edit, .format: self = .editing
            case .keyBindings: self = .keyBindings
            case .ai: self = .models
            case .aiPersona: self = .bots
        }
    }
}


@MainActor @Observable
final class SidebarSettingsState {
    
    var selectedItem: SidebarSettingsItem = .profile
    var pendingAppearanceSubTab: AppearanceSubTab? = nil
    var pendingBotID: AIBotID? = nil
    var pendingCustomBotID: String? = nil
    var pendingCreateCustomBot: Bool = false
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
    
    
    func openAppearanceSubTab(_ subTab: AppearanceSubTab) {
        self.state.pendingAppearanceSubTab = subTab
        self.openItem(.appearance)
    }
    
    
    func openBot(_ botID: AIBotID?) {
        self.state.pendingCustomBotID = nil
        self.state.pendingBotID = botID
        self.openItem(.bots)
    }
    
    
    func openBot(idString: String) {
        if let builtIn = AIBotID(rawValue: idString) {
            self.openBot(builtIn)
        } else {
            self.state.pendingBotID = nil
            self.state.pendingCustomBotID = idString
            self.openItem(.bots)
        }
    }
    
    
    func openUserProfileSettings() {
        self.openItem(.profile)
    }
    
    
    func openCreateCustomBot() {
        self.state.pendingCreateCustomBot = true
        self.openItem(.bots)
    }
}


// MARK: - Root Split Scaffold

private struct SidebarSettingsRootView: View {
    
    @Bindable var state: SidebarSettingsState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var dbStatusMessage: String?
    @State private var isMigratingDatabase: Bool = false
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
            ? Color(red: 0.141, green: 0.141, blue: 0.149)
            : Color(red: 0.961, green: 0.961, blue: 0.969)
    }
    
    
    var body: some View {
        let isDark = (self.resolvedColorScheme ?? self.colorScheme) == .dark
        let accent = self.studioPalette.tokens(isDark: isDark).accent
        let onAccent = self.studioPalette.tokens(isDark: isDark).onAccentInk
        
        HStack(spacing: 0) {
            self.sidebarPane(isDark: isDark, accent: accent, onAccent: onAccent)
            
            Rectangle()
                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .frame(width: 1)
                .ignoresSafeArea()
            
            self.detailPane(isDark: isDark)
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
    
    
    private func sidebarPane(isDark: Bool, accent: Color, onAccent: Color) -> some View {
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
    }
    
    
    private func detailPane(isDark: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            self.contentBackground.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
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
                        case .appearance:
                            SidebarAppearanceContainerPane(settingsState: self.state)
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
            case .profile:
                SidebarProfileSettingsPane(
                    onExportDatabase: { self.exportLocalDatabase() },
                    onImportDatabase: { self.importLocalDatabase() },
                    refreshRevision: self.databaseRefreshRevision,
                    isMigrating: self.isMigratingDatabase,
                    migrationStatus: self.dbStatusMessage
                )
            case .general:
                SidebarGeneralSettingsPane()
            case .appearance:
                EmptyView()
            case .typography:
                SidebarTypographySettingsPane()
            case .editing:
                SidebarEditingSettingsPane()
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
    
    
    private static let archiveByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()
    
    
    private func exportLocalDatabase() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "cot-backup-\(AnalyticsManager.dateKey()).\(MigrationArchiveService.archiveExtension)"
        if let backupType = UTType(filenameExtension: MigrationArchiveService.archiveExtension) {
            savePanel.allowedContentTypes = [backupType]
        }
        savePanel.canCreateDirectories = true
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task { @MainActor in
                self.isMigratingDatabase = true
                defer { self.isMigratingDatabase = false }
                do {
                    let result = try await MigrationArchiveService.exportArchive(from: .shared, to: url)
                    let sizeText = Self.archiveByteFormatter.string(fromByteCount: result.archiveBytes)
                    self.setTemporaryStatus(AppLanguage.text("已导出 \(sizeText)", en: "Exported \(sizeText)"))
                } catch {
                    self.setTemporaryStatus(AppLanguage.text("导出失败：\(error.localizedDescription)", en: "Export failed: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    
    private func importLocalDatabase() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        var allowed: [UTType] = []
        for ext in [MigrationArchiveService.archiveExtension, "sqlite3", "sqlite", "db"] {
            if let type = UTType(filenameExtension: ext) {
                allowed.append(type)
            }
        }
        if !allowed.isEmpty {
            openPanel.allowedContentTypes = allowed
        }
        openPanel.begin { response in
            guard response == .OK, let url = openPanel.url else { return }
            Task { @MainActor in
                self.isMigratingDatabase = true
                defer { self.isMigratingDatabase = false }
                do {
                    _ = try await MigrationArchiveService.importArchive(from: url, into: .shared)
                    self.databaseRefreshRevision &+= 1
                    self.setTemporaryStatus(AppLanguage.text("已还原本地数据", en: "Restored backup"))
                } catch {
                    self.setTemporaryStatus(AppLanguage.text("导入失败：\(error.localizedDescription)", en: "Import failed: \(error.localizedDescription)"))
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
