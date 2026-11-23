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
                    Circle()
                        .fill(tokens.accent.opacity(0.18))
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.accent)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(Circle())
            
            Text(shownLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tokens.primaryInk)
                .lineLimit(1)
            
            if self.butler.isStreaming {
                Circle()
                    .fill(tokens.accent)
                    .frame(width: 6, height: 6)
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


// MARK: - Pure Session Chat Hub (Zero Helper Text · Preferences in Settings -> Bots -> 总管)

struct ButlerCommandHubView: View {
    
    weak var hostWindow: NSWindow?
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var butler = CotButlerManager.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    
    @State private var showSessionSidebar = true
    @State private var draftMessage: String = ""
    @State private var hoveredSessionID: String?
    @State private var renamingSessionID: String?
    @State private var renameDraft: String = ""
    
    private var resolvedIsDark: Bool {
        switch self.documentAppearance {
            case .light: false
            case .dark: true
            case .default: self.colorScheme == .dark
        }
    }
    
    private var tokens: StudioColorTokens {
        _ = self.studioPalette.revision
        return self.studioPalette.tokens(isDark: self.resolvedIsDark)
    }
    
    private var secondaryInk: Color {
        self.tokens.isDark
            ? Color(red: 0.62, green: 0.65, blue: 0.72)
            : Color(red: 0.34, green: 0.37, blue: 0.44)
    }
    
    private var mutedInk: Color {
        self.tokens.isDark
            ? Color(red: 0.46, green: 0.50, blue: 0.57)
            : Color(red: 0.48, green: 0.52, blue: 0.58)
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.headerBar
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            HStack(spacing: 0) {
                if self.showSessionSidebar {
                    self.sessionRail
                        .frame(width: 154)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    Rectangle()
                        .fill(self.tokens.hairline)
                        .frame(width: 1)
                }
                
                self.chatStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(self.tokens.canvasTop.opacity(0.95))
    }
    
    
    // MARK: - Top Identity & Actions Bar (Read-Only Identity, Settings Gear)
    
    private var headerBar: some View {
        let artwork = self.butler.resolvedArtwork()
        let portrait = self.butler.customAvatarImage ?? self.imageLoader.thumbnail(for: artwork, maxPixelSize: 80)
        
        return HStack(spacing: 8) {
            Button {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                    self.showSessionSidebar.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.showSessionSidebar ? self.tokens.accentText : self.secondaryInk)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            
            ZStack {
                if let portrait {
                    Image(nsImage: portrait)
                        .resizable()
                        .scaledToFill()
                } else {
                    self.tokens.accent.opacity(0.16)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.tokens.accent)
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.7))
            
            Text(self.butler.name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(self.tokens.primaryInk)
                .lineLimit(1)
            
            Text("@\(self.butler.nickname)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(self.secondaryInk)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(self.tokens.inset, in: Capsule())
                .lineLimit(1)
            
            Spacer(minLength: 4)
            
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    self.butler.startNewSession()
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.secondaryInk)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("新建对话", en: "New Chat"))
            
            Button {
                self.onDismiss()
                (NSApp.delegate as? AppDelegate)?.openBotSettings(selecting: .butler)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(self.secondaryInk)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("总管设置", en: "Butler Settings"))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
    
    
    // MARK: - Left Persisted Sessions Rail
    
    private var sessionRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 3) {
                ForEach(self.butler.sessions) { session in
                    self.sessionRow(session)
                }
            }
            .padding(8)
        }
        .background(self.tokens.inset.opacity(0.45))
    }
    
    
    @ViewBuilder
    private func sessionRow(_ session: ButlerSessionRecord) -> some View {
        let isActive = (session.id == self.butler.activeSessionID)
        let isHovered = (self.hoveredSessionID == session.id)
        let isRenaming = (self.renamingSessionID == session.id)
        
        HStack(spacing: 5) {
            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(self.tokens.accent)
            }
            
            if isRenaming {
                TextField("", text: self.$renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(self.tokens.primaryInk)
                    .onSubmit {
                        self.commitSessionRename(session.id)
                    }
            } else {
                Text(session.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? self.tokens.primaryInk : self.secondaryInk)
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
                        .foregroundStyle(self.mutedInk)
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
                .fill(isActive ? self.tokens.card : (isHovered ? self.tokens.card.opacity(0.55) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isActive ? self.tokens.hairlineStrong : Color.clear, lineWidth: 0.7)
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
    
    
    // MARK: - Main Pure Chat Stage
    
    private var chatStage: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    if self.butler.messages.isEmpty && !self.butler.isStreaming {
                        VStack(spacing: 9) {
                            Spacer().frame(height: 110)
                            ForEach(self.starterChips, id: \.self) { chip in
                                Button {
                                    self.sendPrompt(chip)
                                } label: {
                                    Text(chip)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .foregroundStyle(self.tokens.primaryInk)
                                        .padding(.horizontal, 14)
                                        .frame(height: 32)
                                        .background(self.tokens.card, in: Capsule())
                                        .overlay(Capsule().strokeBorder(self.tokens.hairlineStrong, lineWidth: 0.7))
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(16)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(self.butler.messages) { msg in
                                self.chatBubble(msg)
                                    .id(msg.id)
                            }
                            if self.butler.isStreaming {
                                self.streamingBubble
                                    .id("streaming-draft")
                            }
                        }
                        .padding(14)
                    }
                }
                .onChange(of: self.butler.messages.count) { _, _ in
                    if let lastID = self.butler.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            
            Rectangle()
                .fill(self.tokens.hairline)
                .frame(height: 1)
            
            self.composerBar
        }
    }
    
    
    private var composerBar: some View {
        let canSend = !self.butler.isStreaming && !self.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("", text: self.$draftMessage, prompt: Text("@\(self.butler.nickname)"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(self.tokens.primaryInk)
                .lineLimit(1...5)
                .onSubmit {
                    self.sendPrompt(self.draftMessage)
                }
                .padding(.vertical, 6)
            
            Button {
                self.sendPrompt(self.draftMessage)
            } label: {
                Image(systemName: self.butler.isStreaming ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(canSend ? self.tokens.accent : self.mutedInk.opacity(0.65))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.bottom, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(self.tokens.card.opacity(0.75))
    }
    
    
    private var starterChips: [String] {
        [
            AppLanguage.text("看盘 恒生科技", en: "Markets HSTECH"),
            AppLanguage.text("记住我的写作风格", en: "Remember Style"),
            AppLanguage.text("帮我看看当前工作区", en: "Inspect Workspace"),
        ]
    }
    
    
    private func chatBubble(_ msg: ButlerChatMessage) -> some View {
        let isUser = (msg.role == "user")
        let receipts = CotButlerManager.decodeReceipts(from: msg.actionsJSON)
        
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            Text(msg.content)
                .font(.system(size: 12.5))
                .foregroundStyle(isUser ? self.tokens.onAccentInk : self.tokens.primaryInk)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isUser ? self.tokens.accent : self.tokens.card,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isUser ? Color.clear : self.tokens.hairline, lineWidth: 0.8)
                )
            
            if !receipts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(receipts) { receipt in
                            HStack(spacing: 4) {
                                Image(systemName: receipt.symbolName)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(receipt.summary)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(self.tokens.accentText)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(self.tokens.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
    
    
    private var streamingBubble: some View {
        HStack(spacing: 8) {
            if self.butler.streamingDraft.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(self.butler.streamingDraft)
                    .font(.system(size: 12.5))
                    .foregroundStyle(self.tokens.primaryInk)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(self.tokens.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(self.tokens.hairline, lineWidth: 0.8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    
    private func sendPrompt(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.draftMessage = ""
        Task {
            await self.butler.sendMessage(trimmed)
        }
    }
}
