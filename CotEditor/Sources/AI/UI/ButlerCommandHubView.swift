//
//  ButlerCommandHubView.swift
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

// MARK: - Top Toolbar Capsule Button + Anchored Floating Panel

@MainActor
final class ToolbarButlerBotButtonView: NSView {
    
    private final class ButlerFloatingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    
    private let hostingView: NSHostingView<ButlerToolbarCapsuleLabel>
    private let clickButton = NSButton()
    private var panel: ButlerFloatingPanel?
    private var panelHosting: NSHostingController<AnyView>?
    private var identityObserver: (any NSObjectProtocol)?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyMonitor: Any?
    private var windowCloseObserver: (any NSObjectProtocol)?
    
    
    override init(frame frameRect: NSRect) {
        self.hostingView = NSHostingView(rootView: ButlerToolbarCapsuleLabel())
        super.init(frame: NSRect(x: 0, y: 0, width: 88, height: 28))
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.hostingView)
        
        self.clickButton.translatesAutoresizingMaskIntoConstraints = false
        self.clickButton.title = ""
        self.clickButton.isBordered = false
        self.clickButton.isTransparent = true
        self.clickButton.focusRingType = .none
        self.clickButton.target = self
        self.clickButton.action = #selector(self.togglePanel(_:))
        self.addSubview(self.clickButton)
        
        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: 28),
            self.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            self.widthAnchor.constraint(lessThanOrEqualToConstant: 144),
            self.hostingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.hostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.hostingView.topAnchor.constraint(equalTo: self.topAnchor),
            self.hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.clickButton.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.clickButton.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.clickButton.topAnchor.constraint(equalTo: self.topAnchor),
            self.clickButton.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
        
        self.refreshTooltip()
        self.identityObserver = NotificationCenter.default.addObserver(
            forName: CotButlerManager.identityDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTooltip()
                self?.invalidateIntrinsicContentSize()
            }
        }
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        if let identityObserver {
            NotificationCenter.default.removeObserver(identityObserver)
        }
        self.closeFloatingPanel()
    }
    
    
    override var intrinsicContentSize: NSSize {
        let fitting = self.hostingView.fittingSize
        return NSSize(width: min(144, max(64, ceil(fitting.width))), height: 28)
    }
    
    
    private func refreshTooltip() {
        let butler = CotButlerManager.shared
        let label = "\(butler.name) · @\(butler.nickname)"
        self.toolTip = label
        self.clickButton.toolTip = label
    }
    
    
    @objc private func togglePanel(_ sender: Any?) {
        if let panel = self.panel, panel.isVisible {
            self.closeFloatingPanel()
            return
        }
        self.showFloatingPanel()
    }
    
    
    private func showFloatingPanel() {
        guard let hostWindow = self.window else { return }
        self.closeFloatingPanel()
        _ = CotAgentCoordinator.shared.captureWorkspaceSnapshot()
        
        let rootView = ButlerCommandHubView(
            hostWindow: hostWindow,
            onDismiss: { [weak self] in
                self?.closeFloatingPanel()
            }
        )
        
        let cornerRadius: CGFloat = 16
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.maskImage = UserAvatarToolbarButtonView.makeRoundedMaskImage(cornerRadius: cornerRadius)
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.layer?.masksToBounds = true
        vfx.layer?.backgroundColor = NSColor.clear.cgColor
        vfx.layer?.borderWidth = 0.5
        vfx.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        
        let panelSize = NSSize(width: 492, height: 560)
        let hosting = NSHostingController(
            rootView: AnyView(
                rootView
                    .frame(width: panelSize.width, height: panelSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
        )
        hosting.sizingOptions = []
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.view.layer?.cornerRadius = cornerRadius
        hosting.view.layer?.masksToBounds = true
        vfx.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])
        
        let btnInWindow = self.convert(self.bounds, to: nil)
        let btnScreen = hostWindow.convertToScreen(btnInWindow)
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: btnScreen,
            panelSize: panelSize,
            visibleScreenFrame: screenFrame
        )
        
        let panel = ButlerFloatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = hostWindow.effectiveAppearance
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = vfx
        panel.invalidateShadow()
        panel.alphaValue = 0
        
        hostWindow.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().alphaValue = 1.0
        }
        
        self.panel = panel
        self.panelHosting = hosting
        self.installMonitors(hostWindow: hostWindow, panel: panel)
    }
    
    
    private func installMonitors(hostWindow: NSWindow, panel: ButlerFloatingPanel) {
        self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window === panel { return event }
            if event.window === self.window {
                let locInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(locInSelf) { return event }
            }
            self.closeFloatingPanel()
            return event
        }
        
        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeFloatingPanel()
            }
        }
        
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, event.keyCode == 53 else { return event }
            if let fieldEditor = panel.firstResponder as? NSTextView, fieldEditor.isFieldEditor {
                return event
            }
            self.closeFloatingPanel()
            return nil
        }
        
        self.windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: hostWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closeFloatingPanel()
            }
        }
    }
    
    
    private func closeFloatingPanel() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
        if let panel = self.panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
        }
        self.panelHosting = nil
    }
}


private struct ButlerToolbarCapsuleLabel: View {
    
    @State private var butler = CotButlerManager.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let artwork = self.butler.resolvedArtwork()
        let portrait = self.butler.customAvatarImage ?? self.imageLoader.thumbnail(for: artwork, maxPixelSize: 64)
        let shownLabel = self.butler.nickname.isEmpty ? self.butler.name : self.butler.nickname
        
        HStack(spacing: 6) {
            ZStack {
                if let portrait {
                    Image(nsImage: portrait)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tokens.accent.opacity(0.16))
                    Text(String(shownLabel.prefix(1)))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            
            Text(shownLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk)
                .lineLimit(1)
            
            if self.butler.isStreaming {
                DissolveThinkingOrbView(
                    state: .thinking,
                    size: 14,
                    dots: 42,
                    interactive: false,
                    color: tokens.accent
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            self.isHovered ? tokens.insetHover : tokens.inset,
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(tokens.hairlineStrong, lineWidth: 0.7)
        )
        .contentShape(Capsule())
        .onHover { self.isHovered = $0 }
    }
}


// MARK: - Unified Bot Chat Hub (Beautiful UI + DissolveThinkingOrbView · Hello Empty State)

struct ButlerCommandHubView: View {
    
    weak var hostWindow: NSWindow?
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @State private var butler = CotButlerManager.shared
    @State private var botStore = AIBotStore.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    
    @State private var showSessionSidebar = true
    @State private var hoveredSessionID: String?
    @State private var renamingSessionID: String?
    @State private var renameDraft: String = ""
    @State private var availableModels: [AgentModelOption] = []
    
    private var resolvedIsDark: Bool {
        switch self.documentAppearance {
            case .light: false
            case .dark: true
            case .default: self.colorScheme == .dark
        }
    }
    
    private var buiTokens: BeautifulUITokens {
        BeautifulUITokens.resolve(isDark: self.resolvedIsDark)
    }
    
    private var activeModelTitle: String {
        let cfg = self.botStore.config(for: .butler)
        let custom = cfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }
        return self.botStore.openCodeGoSelectableModels().profile?.displayModel ?? AIProvider.openCodeGo.defaultModel
    }
    
    
    var body: some View {
        let tokens = self.buiTokens
        let portrait = self.botStore.resolvedAvatarImage(for: .butler, pointSize: 80)
            ?? self.butler.customAvatarImage
            ?? self.imageLoader.thumbnail(for: self.butler.resolvedArtwork(), maxPixelSize: 80)
        
        VStack(spacing: 0) {
            AgentChatHeaderBar(
                avatarImage: portrait,
                name: self.butler.name,
                nickname: self.butler.nickname,
                accent: tokens.accent,
                tokens: tokens,
                leadingControl: {
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                            self.showSessionSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(self.showSessionSidebar ? tokens.accentInk : tokens.ink2)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                },
                trailingActions: {
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            self.butler.startNewSession()
                        }
                    } label: {
                        Text(AppLanguage.text("新对话", en: "New Chat"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.ink2)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(tokens.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.onDismiss()
                        (NSApp.delegate as? AppDelegate)?.openBotSettings(selecting: .butler)
                    } label: {
                        Text(AppLanguage.text("设置", en: "Settings"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(tokens.ink2)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(tokens.field, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            )
            
            Rectangle()
                .fill(tokens.line)
                .frame(height: 1)
            
            HStack(spacing: 0) {
                if self.showSessionSidebar {
                    self.sessionRail(tokens: tokens)
                        .frame(width: 152)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    Rectangle()
                        .fill(tokens.line)
                        .frame(width: 1)
                }
                
                AgentChatTranscriptSurface(
                    messages: self.mappedMessages,
                    isStreaming: self.butler.isStreaming,
                    streamingDraft: self.butler.streamingDraft,
                    errorMessage: nil,
                    placeholder: "@\(self.butler.nickname)",
                    availableModels: self.availableModels,
                    selectedModelTitle: self.activeModelTitle,
                    orbColor: tokens.ink,
                    tokens: tokens,
                    onSelectModel: { option in
                        var cfg = self.botStore.config(for: .butler)
                        cfg.endpointID = option.endpointID
                        cfg.modelOverride = option.modelID
                        self.botStore.updateConfig(cfg, for: .butler)
                    },
                    onOpenSettings: {
                        self.onDismiss()
                        (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
                    },
                    onSend: { prompt in
                        Task {
                            await self.butler.sendMessage(prompt)
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(tokens.page)
        .task {
            self.reloadModels()
            if let fetched = try? await self.botStore.refreshOpenCodeGoModels() {
                let profileID = self.botStore.openCodeGoSelectableModels().profile?.id
                self.availableModels = fetched.map { AgentModelOption(endpointID: profileID, modelID: $0) }
            }
        }
    }
    
    
    private var mappedMessages: [AgentChatMessageItem] {
        self.butler.messages.map { msg in
            let receipts = CotButlerManager.decodeReceipts(from: msg.actionsJSON)
            let chips = receipts.map { AgentToolChipItem(id: $0.id, label: $0.summary) }
            return AgentChatMessageItem(
                id: msg.id,
                isUser: (msg.role == "user"),
                text: msg.content,
                toolChips: chips
            )
        }
    }
    
    
    private func reloadModels() {
        let info = self.botStore.openCodeGoSelectableModels()
        let endpointID = info.profile?.id
        self.availableModels = info.models.map { AgentModelOption(endpointID: endpointID, modelID: $0) }
    }
    
    
    // MARK: - Left Persisted Sessions Rail
    
    private func sessionRail(tokens: BeautifulUITokens) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(self.butler.sessions) { session in
                    self.sessionRow(session, tokens: tokens)
                }
            }
            .padding(8)
        }
        .background(tokens.inset)
    }
    
    
    @ViewBuilder
    private func sessionRow(_ session: ButlerSessionRecord, tokens: BeautifulUITokens) -> some View {
        let isActive = (session.id == self.butler.activeSessionID)
        let isHovered = (self.hoveredSessionID == session.id)
        let isRenaming = (self.renamingSessionID == session.id)
        
        HStack(spacing: 5) {
            if session.isPinned {
                Circle()
                    .fill(tokens.accent)
                    .frame(width: 5, height: 5)
            }
            
            if isRenaming {
                TextField("", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(tokens.ink)
                    .onSubmit {
                        self.commitSessionRename(session.id)
                    }
            } else {
                Text(session.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? tokens.ink : tokens.ink2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if isHovered && !isRenaming {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        self.butler.deleteSession(session.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tokens.ink3)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? tokens.surface : (isHovered ? tokens.hover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? tokens.lineStrong : Color.clear, lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            self.hoveredSessionID = hovering ? session.id : (self.hoveredSessionID == session.id ? nil : self.hoveredSessionID)
        }
        .onTapGesture(count: 2) {
            self.renameDraft = session.title
            self.renamingSessionID = session.id
        }
        .onTapGesture {
            self.butler.selectSession(session.id)
        }
        .contextMenu {
            Button(session.isPinned
                   ? AppLanguage.text("取消置顶", en: "Unpin")
                   : AppLanguage.text("置顶会话", en: "Pin"))
            {
                self.butler.togglePinSession(session.id)
            }
            Button(AppLanguage.text("重命名", en: "Rename")) {
                self.renameDraft = session.title
                self.renamingSessionID = session.id
            }
            Divider()
            Button(AppLanguage.text("删除会话", en: "Delete"), role: .destructive) {
                self.butler.deleteSession(session.id)
            }
        }
    }
    
    
    private func commitSessionRename(_ sessionID: String) {
        let trimmed = self.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            self.butler.renameSession(sessionID, to: trimmed)
        }
        self.renamingSessionID = nil
    }
}
