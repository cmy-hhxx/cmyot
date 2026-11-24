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

// MARK: - Top Toolbar Capsule Button + Resizable Pinnable Floating Panel

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
    private var isPinnedPanel: Bool = false
    private var identityObserver: (any NSObjectProtocol)?
    private var openHubObserver: (any NSObjectProtocol)?
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
        self.openHubObserver = NotificationCenter.default.addObserver(
            forName: CotButlerManager.openHubRequestedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let hostWindow = self.window else { return }
                let isTargetWindow = hostWindow.isMainWindow
                    || hostWindow.isKeyWindow
                    || (NSApp.mainWindow == nil && NSApp.orderedWindows.first(where: { $0.windowController is DocumentWindowController }) === hostWindow)
                guard isTargetWindow else { return }
                
                if self.panel?.isVisible != true {
                    self.showFloatingPanel()
                } else {
                    self.panel?.makeKeyAndOrderFront(nil)
                }
                
                let autoSend = (notification.userInfo?["autoSend"] as? Bool) == true
                let draft = (notification.userInfo?["draft"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let quote = (notification.userInfo?["quote"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if autoSend, !draft.isEmpty {
                    _ = CotButlerManager.shared.consumePendingDraftAndQuote()
                    Task {
                        await CotButlerManager.shared.sendMessage(draft, quote: quote.isEmpty ? nil : quote)
                    }
                }
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
        if let openHubObserver {
            NotificationCenter.default.removeObserver(openHubObserver)
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
        
        let pinnedBinding = Binding<Bool>(
            get: { [weak self] in self?.isPinnedPanel ?? false },
            set: { [weak self] newValue in
                self?.isPinnedPanel = newValue
                self?.panel?.level = newValue ? .floating : .popUpMenu
            }
        )
        
        let rootView = ButlerCommandHubView(
            hostWindow: hostWindow,
            isDockedPane: false,
            isPinnedPanel: pinnedBinding,
            onDockToPane: { [weak self] in
                self?.closeFloatingPanel()
                CotAgentCoordinator.shared.openBoard(.butler, splitRight: true)
            },
            onDismiss: { [weak self] in
                self?.closeFloatingPanel()
            }
        )
        
        let cornerRadius: CGFloat = 16
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.layer?.masksToBounds = true
        vfx.layer?.backgroundColor = NSColor.clear.cgColor
        vfx.layer?.borderWidth = 0.5
        vfx.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = NSSize(
            width: min(740, max(540, screenFrame.width * 0.52)),
            height: min(600, max(480, screenFrame.height * 0.68))
        )
        let hosting = NSHostingController(
            rootView: AnyView(
                rootView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let frame = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: btnScreen,
            panelSize: panelSize,
            visibleScreenFrame: screenFrame
        )
        
        let panel = ButlerFloatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 500, height: 420)
        panel.maxSize = NSSize(width: 1120, height: 860)
        panel.appearance = hostWindow.effectiveAppearance
        panel.isFloatingPanel = true
        panel.level = self.isPinnedPanel ? .floating : .popUpMenu
        panel.isMovableByWindowBackground = true
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
            if self.isPinnedPanel { return event }
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
                guard let self, !self.isPinnedPanel else { return }
                self.closeFloatingPanel()
            }
        }
        
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, event.keyCode == 53 else { return event }
            if self.isPinnedPanel { return event }
            // Allow Escape inside WebView menus/popovers; only close if panel is key and user presses Escape
            if panel.firstResponder is NSTextView {
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


// MARK: - Unified Beautiful UI Butler Command Hub (Powered by Pi 1.6+ RPC Kernel)

struct ButlerCommandHubView: View {
    
    weak var hostWindow: NSWindow?
    var isDockedPane: Bool = false
    var initialSeedPrompt: String = ""
    var isPinnedPanel: Binding<Bool> = .constant(false)
    var onDockToPane: (() -> Void)? = nil
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @State private var butler = CotButlerManager.shared
    @State private var botStore = AIBotStore.shared
    @State private var piKernel = PiKernelManager.shared
    @State private var userProfile = UserProfileManager.shared
    @State private var webController = BeautifulAgentWebController()
    @State private var availableModels: [BeautifulAgentModelPayload] = []
    @State private var quotedExcerpt: String? = nil
    @State private var streamListenerID: UUID? = nil
    
    private var resolvedIsDark: Bool {
        switch self.documentAppearance {
            case .light: false
            case .dark: true
            case .default: self.colorScheme == .dark
        }
    }
    
    private var activeModelID: String {
        let cfg = self.botStore.config(for: .butler)
        let custom = cfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            return custom
        }
        return self.botStore.resolvedConfiguration(for: .butler).model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? (self.botStore.openCodeGoSelectableModels().profile?.displayModel ?? AIProvider.openCodeGo.defaultModel)
            : self.botStore.resolvedConfiguration(for: .butler).model
    }
    
    
    var body: some View {
        BeautifulAgentWebView(
            state: self.buildHostState(),
            controller: self.webController,
            callbacks: self.buildCallbacks()
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            self.reloadModels()
            self.consumeAnyPendingHandoff()
            if self.streamListenerID == nil {
                self.streamListenerID = self.butler.addStreamPatchListener { [weak webController] patch in
                    webController?.pushStreamPatch(patch)
                }
            }
            self.webController.focusComposer()
        }
        .onDisappear {
            if let id = self.streamListenerID {
                self.butler.removeStreamPatchListener(id)
                self.streamListenerID = nil
            }
        }
        .onChange(of: self.butler.pendingDraftText) { _, _ in
            self.consumeAnyPendingHandoff()
        }
        .onChange(of: self.butler.pendingQuoteExcerpt) { _, _ in
            self.consumeAnyPendingHandoff()
        }
        .task {
            self.reloadModels()
            if let fetched = try? await self.botStore.refreshOpenCodeGoModels() {
                let profileID = self.botStore.openCodeGoSelectableModels().profile?.id.uuidString
                self.availableModels = Self.mapModels(fetched, endpointID: profileID)
            }
        }
    }
    
    
    private func consumeAnyPendingHandoff() {
        let pair = self.butler.consumePendingDraftAndQuote()
        let seed = self.initialSeedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = pair.draft?.trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = pair.quote?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let quote, !quote.isEmpty {
            self.quotedExcerpt = quote
        }
        if let draft, !draft.isEmpty {
            self.webController.injectDraft(draft, quote: self.quotedExcerpt)
            self.webController.focusComposer()
        } else if let quote, !quote.isEmpty {
            self.webController.injectDraft("", quote: quote)
            self.webController.focusComposer()
        } else if !seed.isEmpty, self.butler.messages.isEmpty {
            self.webController.injectDraft(seed, quote: nil)
        }
    }
    
    
    private func buildHostState() -> BeautifulAgentHostStatePayload {
        let isZh = AppLanguage.current == .simplifiedChinese
        let avatarDataURL = self.butler.resolvedAvatarDataURL(pointSize: 72)
        
        var payloadMessages: [BeautifulAgentMessagePayload] = self.butler.messages.map { msg in
            let meta = CotButlerManager.decodeMetadata(from: msg.actionsJSON)
            var chips: [BeautifulAgentToolReceipt] = meta.receipts.map {
                BeautifulAgentToolReceipt(id: $0.id, label: $0.summary, detail: nil, status: "done")
            }
            for chipLabel in meta.toolChips where !chips.contains(where: { $0.label == chipLabel }) {
                chips.append(BeautifulAgentToolReceipt(id: "tool-\(msg.id)-\(chipLabel)", label: chipLabel, detail: nil, status: "done"))
            }
            return BeautifulAgentMessagePayload(
                id: msg.id,
                role: msg.role == "user" ? "user" : "assistant",
                text: msg.content,
                thinking: meta.thinking,
                thinkingDurationMs: meta.thinkingDurationMs,
                steps: meta.steps.isEmpty ? nil : meta.steps,
                toolChips: chips.isEmpty ? nil : chips,
                followUps: meta.followUps.isEmpty ? nil : meta.followUps,
                isStreaming: false,
                isError: meta.errorMessage != nil,
                quoteContext: meta.quoteContext,
                createdAt: msg.createdAt.timeIntervalSince1970 * 1000
            )
        }
        
        if self.butler.isStreaming, let streamID = self.butler.streamingMessageID {
            let elapsedMs = self.butler.streamingStartedAt.map { max(0, Int(Date().timeIntervalSince($0) * 1000)) } ?? 0
            payloadMessages.append(BeautifulAgentMessagePayload(
                id: streamID,
                role: "assistant",
                text: self.butler.streamingDraft,
                thinking: self.butler.streamingThinking.isEmpty ? nil : self.butler.streamingThinking,
                thinkingDurationMs: elapsedMs,
                steps: self.butler.streamingSteps.isEmpty ? nil : self.butler.streamingSteps,
                toolChips: nil,
                followUps: nil,
                isStreaming: true,
                isError: false,
                quoteContext: nil,
                createdAt: Date().timeIntervalSince1970 * 1000
            ))
        }
        
        let sessions = self.butler.sessions.map {
            BeautifulAgentSessionPayload(
                id: $0.id,
                title: $0.title,
                isPinned: $0.isPinned,
                messageCount: $0.messageCount,
                updatedAt: $0.updatedAt.timeIntervalSince1970 * 1000
            )
        }
        
        let snap = CotAgentCoordinator.shared.lastWorkspaceSnapshot
        var contextSources: [BeautifulAgentContextSourcePayload] = [
            .init(
                key: "doc",
                name: AppLanguage.text("当前文档", en: "Active Doc"),
                desc: snap?.activeDocumentTitle ?? AppLanguage.text("带入正在编辑的文件正文", en: "Attach active document"),
                glyph: "doc",
                insertText: "@当前文档 "
            ),
            .init(
                key: "selection",
                name: AppLanguage.text("当前选区", en: "Selection"),
                desc: AppLanguage.text("带入编辑器中选中的片段", en: "Attach selected text"),
                glyph: "quote",
                insertText: "@选区 "
            ),
            .init(
                key: "watchlist",
                name: AppLanguage.text("自选行情", en: "Watchlist"),
                desc: AppLanguage.text("结合自选股池查行情与分析", en: "Include watchlist stocks"),
                glyph: "market",
                insertText: "@自选股 "
            ),
            .init(
                key: "news",
                name: AppLanguage.text("本地资讯", en: "NEWS"),
                desc: AppLanguage.text("关联最新缓存的科技与金融热点", en: "Include cached news"),
                glyph: "news",
                insertText: "@资讯 "
            ),
        ]
        if let activeTitle = snap?.activeDocumentTitle, !activeTitle.isEmpty {
            contextSources[0].desc = activeTitle
        }
        
        let slashCommands: [BeautifulAgentSlashCommandPayload] = [
            .init(key: "market", name: "/market", desc: AppLanguage.text("查实时股价并分析走势", en: "Lookup live stock quote"), insertText: "/market "),
            .init(key: "news", name: "/news", desc: AppLanguage.text("汇总今天最值得关注的 AI/科技热点", en: "Summarize today's news"), insertText: "/news "),
            .init(key: "note", name: "/note", desc: AppLanguage.text("把要点整理成一篇新 Markdown 笔记", en: "Create Markdown note"), insertText: "/note "),
            .init(key: "memory", name: "/memory", desc: AppLanguage.text("记住我的长期偏好或习惯", en: "Save to long-term memory"), insertText: "/memory "),
            .init(key: "new", name: "/new", desc: AppLanguage.text("开启一段全新对话", en: "Start a fresh chat"), insertText: "/new"),
        ]
        
        let suggestions: [BeautifulAgentSuggestionPayload] = [
            .init(
                id: "s-stock",
                label: AppLanguage.text("查一只股票实时行情", en: "Check live stock quote"),
                prompt: AppLanguage.text("帮我查一下三安光电和英伟达今天的实时行情和近期走势", en: "Look up live quotes and recent trends for NVDA"),
                icon: "market"
            ),
            .init(
                id: "s-news",
                label: AppLanguage.text("今天有哪些重磅 AI 资讯", en: "Today's top AI news"),
                prompt: AppLanguage.text("帮我看看今天有哪些最值得关注的 AI 与科技热点，用要点总结", en: "Summarize today's top AI and tech headlines"),
                icon: "news"
            ),
            .init(
                id: "s-doc",
                label: AppLanguage.text("梳理当前正在写的文档", en: "Review active document"),
                prompt: AppLanguage.text("读取我当前正在编辑的文档，提炼核心要点并给出结构优化建议", en: "Review my active document and suggest improvements"),
                icon: "doc"
            ),
            .init(
                id: "s-memory",
                label: AppLanguage.text("查看我的记忆与自选清单", en: "Check memory & watchlist"),
                prompt: AppLanguage.text("帮我回顾一下你记住的我的偏好和当前的自选股清单", en: "Review my saved preferences and watchlist"),
                icon: "spark"
            ),
        ]
        
        let userDisplayName = self.userProfile.activeProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetingName = userDisplayName.isEmpty ? self.butler.name : userDisplayName
        
        return BeautifulAgentHostStatePayload(
            mode: "butler",
            isDark: self.resolvedIsDark,
            locale: isZh ? "zh" : "en",
            botName: self.butler.name,
            botNickname: self.butler.nickname,
            botAvatarDataURL: avatarDataURL,
            piAvailable: self.piKernel.canRunRPC,
            piStatusLabel: self.piKernel.statusSummary,
            isPinnedPanel: self.isPinnedPanel.wrappedValue,
            isDockedPane: self.isDockedPane,
            showSidebar: true,
            sessions: sessions,
            activeSessionID: self.butler.activeSessionID,
            messages: payloadMessages,
            isStreaming: self.butler.isStreaming,
            streamingStatusLabel: self.butler.streamingStatusLabel.isEmpty ? nil : self.butler.streamingStatusLabel,
            errorMessage: self.butler.lastErrorMessage,
            placeholder: AppLanguage.text("向 @\(self.butler.nickname) 提问，支持 @引用、/命令、查行情与操作编辑器…", en: "Ask @\(self.butler.nickname)..."),
            greetingName: greetingName,
            greetingSubtitle: self.piKernel.canRunRPC
                ? AppLanguage.text("已连接 Pi 内核，可直接查实时行情、搜资讯、读本地笔记并控制编辑器", en: "Connected to Pi kernel for live quotes, search, notes & editor control")
                : AppLanguage.text("随时帮你查行情、理文档、记偏好或切换看板", en: "Ask about live quotes, documents, preferences, or boards"),
            articleTitle: nil,
            articleSource: nil,
            quotedExcerpt: self.quotedExcerpt,
            availableModels: self.availableModels,
            selectedModelID: self.activeModelID,
            selectedModelTitle: self.activeModelID,
            effort: nil,
            suggestions: suggestions,
            contextSources: contextSources,
            slashCommands: slashCommands
        )
    }
    
    
    private func buildCallbacks() -> BeautifulAgentWebActionCallbacks {
        var cb = BeautifulAgentWebActionCallbacks()
        cb.onSend = { prompt, quote in
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "/new" {
                self.butler.startNewSession()
                return
            }
            let effectiveQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? self.quotedExcerpt
                : quote
            self.quotedExcerpt = nil
            
            var contextSources: [String] = []
            if trimmed.contains("@当前文档") || trimmed.contains("@Active Doc") { contextSources.append("doc") }
            if trimmed.contains("@选区") || trimmed.contains("@Selection") { contextSources.append("selection") }
            if trimmed.contains("@自选股") || trimmed.contains("@Watchlist") { contextSources.append("watchlist") }
            if trimmed.contains("@资讯") || trimmed.contains("@NEWS") { contextSources.append("news") }
            
            var resolvedPrompt = trimmed
            if resolvedPrompt.hasPrefix("/market ") {
                let target = String(resolvedPrompt.dropFirst("/market ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedPrompt = "帮我查询 \(target) 的实时行情、涨跌幅和近期K线走势，并给出简明分析。"
            } else if resolvedPrompt.hasPrefix("/news ") {
                let topic = String(resolvedPrompt.dropFirst("/news ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedPrompt = "帮我检索并总结关于「\(topic)」的最新资讯热点。"
            } else if resolvedPrompt.hasPrefix("/note ") {
                let topic = String(resolvedPrompt.dropFirst("/note ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedPrompt = "请帮我把「\(topic)」整理成结构清晰的 Markdown 笔记，并用 open_document 在编辑器新建文档。"
            } else if resolvedPrompt.hasPrefix("/memory ") {
                let mem = String(resolvedPrompt.dropFirst("/memory ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedPrompt = "请帮我记住这件事并存入我的长期记忆：\(mem)"
            }
            
            Task {
                await self.butler.sendMessage(resolvedPrompt, quote: effectiveQuote, contextSources: contextSources)
            }
        }
        cb.onAbort = {
            self.butler.abortStreaming()
        }
        cb.onRetry = {
            self.butler.retryLastMessage()
        }
        cb.onClearChat = {
            self.butler.clearCurrentSession()
        }
        cb.onClearQuote = {
            self.quotedExcerpt = nil
        }
        cb.onSelectModel = { model in
            var cfg = self.botStore.config(for: .butler)
            if let epStr = model.endpointID, let uuid = UUID(uuidString: epStr) {
                cfg.endpointID = uuid
            }
            cfg.modelOverride = model.modelID
            self.botStore.updateConfig(cfg, for: .butler)
            _ = try? PiKernelManager.shared.syncWorkspace()
        }
        cb.onNewSession = {
            self.butler.startNewSession()
        }
        cb.onSelectSession = { id in
            self.butler.selectSession(id)
        }
        cb.onDeleteSession = { id in
            self.butler.deleteSession(id)
        }
        cb.onRenameSession = { id, title in
            self.butler.renameSession(id, to: title)
        }
        cb.onTogglePinSession = { id in
            self.butler.togglePinSession(id)
        }
        cb.onInsertToEditor = { text in
            CotAgentCoordinator.shared.insertTextIntoActiveEditor(text)
        }
        cb.onOpenNewDocument = { text in
            let firstLine = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#* >\t ")) }
                .first { !$0.isEmpty } ?? AppLanguage.text("总管笔记", en: "Butler Note")
            CotAgentCoordinator.shared.openNewMarkdownDocument(
                title: String(firstLine.prefix(24)),
                content: text,
                splitRight: true
            )
        }
        cb.onOpenSettings = { target in
            if !self.isDockedPane {
                self.onDismiss()
            }
            if target == "ai" {
                (NSApp.delegate as? AppDelegate)?.showAIPreferences(nil)
            } else {
                (NSApp.delegate as? AppDelegate)?.openBotSettings(selecting: .butler)
            }
        }
        cb.onTogglePinPanel = {
            self.isPinnedPanel.wrappedValue.toggle()
        }
        cb.onDockToPane = {
            self.onDockToPane?()
        }
        return cb
    }
    
    
    private func reloadModels() {
        let info = self.botStore.openCodeGoSelectableModels()
        let endpointID = info.profile?.id.uuidString
        var list = Self.mapModels(info.models, endpointID: endpointID)
        
        // Also surface active profile's configured models if user uses a non-OpenCodeGo gateway
        if list.isEmpty, let activeProfile = self.botStore.resolvedEndpointProfile(for: .butler) {
            list = Self.mapModels(activeProfile.availableModelIDs, endpointID: activeProfile.id.uuidString)
        }
        self.availableModels = list
    }
    
    
    private static func mapModels(_ ids: [String], endpointID: String?) -> [BeautifulAgentModelPayload] {
        ids.map { mid in
            let lower = mid.lowercased()
            let isFlagship = lower.contains("opus") || lower.contains("gpt-5") || lower.contains("glm-5") || lower.contains("deepseek-v4") || lower.contains("gemini-2.5-pro")
            let tag: String? = if lower.contains("flash") || lower.contains("haiku") || lower.contains("mini") {
                AppLanguage.text("快推", en: "Fast")
            } else if lower.contains("opus") || lower.contains("pro") || lower.contains("reasoner") {
                AppLanguage.text("深度", en: "Deep")
            } else if lower.contains("glm-5") || lower.contains("sonnet") || lower.contains("gpt-5") {
                AppLanguage.text("主力", en: "Flagship")
            } else {
                nil
            }
            return BeautifulAgentModelPayload(
                id: "\(endpointID ?? "default"):\(mid)",
                modelID: mid,
                title: mid,
                endpointID: endpointID,
                tag: tag,
                isFlagship: isFlagship
            )
        }
    }
}
