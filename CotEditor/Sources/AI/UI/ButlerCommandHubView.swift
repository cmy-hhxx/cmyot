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
import UniformTypeIdentifiers

// MARK: - Top Toolbar Capsule Button + Resizable Pinnable Floating Panel

@MainActor
final class ToolbarButlerBotButtonView: NSView {
    
    private final class ButlerFloatingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    
    private final class ToolbarClickButton: NSButton {
        override func menu(for event: NSEvent) -> NSMenu? {
            self.superview?.menu(for: event)
        }
    }
    
    private let hostingView: NSHostingView<ButlerToolbarCapsuleLabel>
    private let clickButton = ToolbarClickButton()
    private var panel: ButlerFloatingPanel?
    private var panelHosting: NSHostingController<AnyView>?
    private var isPinnedPanel: Bool = CotLocalDatabase.shared.bool(
        forKey: CotLocalDatabase.ConfigKey.butlerFloatingPanelPinned,
        default: true
    )
    private var suppressAutoDismiss: Bool = false
    private var identityObserver: (any NSObjectProtocol)?
    private var openHubObserver: (any NSObjectProtocol)?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyMonitor: Any?
    private var windowCloseObserver: (any NSObjectProtocol)?
    private var panelResizeObserver: (any NSObjectProtocol)?
    private var panelMoveObserver: (any NSObjectProtocol)?
    
    private var shouldProtectFromOutsideDismiss: Bool {
        self.isPinnedPanel
            || self.suppressAutoDismiss
            || ButlerMeetingRoomManager.shared.isActive
            || ButlerMeetingRoomManager.shared.isConvening
            || CotButlerManager.shared.isStreaming
    }
    
    
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
        ButlerToolbarTipBubbleController.shared.unregisterAnchor(self)
        self.closeFloatingPanel()
    }
    
    
    var isFloatingChatVisible: Bool {
        self.panel?.isVisible == true
    }
    
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            ButlerToolbarTipBubbleController.shared.registerAnchor(self)
        } else {
            ButlerToolbarTipBubbleController.shared.unregisterAnchor(self)
        }
    }
    
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let openJournal = NSMenuItem(
            title: AppLanguage.text("打开今日总管随记", en: "Open Today's Journal"),
            action: #selector(self.openTodayJournal(_:)),
            keyEquivalent: ""
        )
        openJournal.target = self
        menu.addItem(openJournal)
        
        let recordTip = NSMenuItem(
            title: AppLanguage.text("立即弹出一条主动提醒", en: "Show Proactive Tip Now"),
            action: #selector(self.triggerProactiveTipNow(_:)),
            keyEquivalent: ""
        )
        recordTip.target = self
        menu.addItem(recordTip)
        
        menu.addItem(.separator())
        
        let toggleItem = NSMenuItem(
            title: AppLanguage.text("主动提醒气泡", en: "Proactive Tip Bubbles"),
            action: #selector(self.toggleProactiveTips(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = ProactiveDailyJournalService.shared.tipsEnabled ? .on : .off
        menu.addItem(toggleItem)
        return menu
    }
    
    
    @objc private func openTodayJournal(_ sender: Any?) {
        ButlerToolbarTipBubbleController.shared.dismiss(animated: false)
        ProactiveDailyJournalService.shared.openTodayJournalWindow(preferredWindow: self.window)
    }
    
    
    @objc private func triggerProactiveTipNow(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let tip = await ProactiveDailyJournalService.shared.recordProactiveNote(
                allowRemoteAI: false,
                showFloatingTip: false
            ) {
                ButlerToolbarTipBubbleController.shared.presentTip(tip, preferredAnchor: self)
            }
        }
    }
    
    
    @objc private func toggleProactiveTips(_ sender: Any?) {
        ProactiveDailyJournalService.shared.tipsEnabled.toggle()
        if !ProactiveDailyJournalService.shared.tipsEnabled {
            ButlerToolbarTipBubbleController.shared.dismiss(animated: true)
        }
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
        ButlerToolbarTipBubbleController.shared.dismiss(animated: false)
        if let panel = self.panel, panel.isVisible {
            self.closeFloatingPanel()
            return
        }
        self.showFloatingPanel()
    }
    
    
    private func showFloatingPanel() {
        guard let hostWindow = self.window else { return }
        ButlerToolbarTipBubbleController.shared.dismiss(animated: false)
        self.closeFloatingPanel()
        _ = CotAgentCoordinator.shared.captureWorkspaceSnapshot()
        
        let pinnedBinding = Binding<Bool>(
            get: { [weak self] in self?.isPinnedPanel ?? true },
            set: { [weak self] newValue in
                self?.isPinnedPanel = newValue
                CotLocalDatabase.shared.set(newValue, forKey: CotLocalDatabase.ConfigKey.butlerFloatingPanelPinned)
                self?.panel?.level = newValue ? .floating : .popUpMenu
            }
        )
        
        let cornerRadius: CGFloat = 16
        let rootView = ButlerCommandHubView(
            hostWindow: hostWindow,
            isDockedPane: false,
            panelCornerRadius: cornerRadius,
            isPinnedPanel: pinnedBinding,
            onDockToPane: { [weak self] in
                self?.closeFloatingPanel()
                CotAgentCoordinator.shared.openBoard(.butler, splitRight: true)
            },
            onSetSuppressDismiss: { [weak self] suppress in
                self?.suppressAutoDismiss = suppress
                if !suppress {
                    self?.panel?.makeKeyAndOrderFront(nil)
                }
            },
            onDismiss: { [weak self] in
                self?.closeFloatingPanel()
            }
        )
        
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.maskImage = UserAvatarToolbarButtonView.makeRoundedMaskImage(cornerRadius: cornerRadius)
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.layer?.cornerCurve = .continuous
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
        hosting.view.layer?.cornerCurve = .continuous
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
        let defaultFrame = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: btnScreen,
            panelSize: panelSize,
            visibleScreenFrame: screenFrame
        )
        let frame = Self.restoredPanelFrame(in: screenFrame) ?? defaultFrame
        
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
            if self.shouldProtectFromOutsideDismiss { return event }
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
                guard let self, !self.shouldProtectFromOutsideDismiss else { return }
                self.closeFloatingPanel()
            }
        }
        
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, event.keyCode == 53 else { return event }
            if self.shouldProtectFromOutsideDismiss { return event }
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
        
        self.panelResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                Self.persistPanelFrame(panel.frame)
            }
        }
        
        self.panelMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel, panel.isVisible else { return }
                Self.persistPanelFrame(panel.frame)
            }
        }
    }
    
    
    private static func persistPanelFrame(_ frame: NSRect) {
        let payload: [Double] = [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else { return }
        CotLocalDatabase.shared.set(json, forKey: CotLocalDatabase.ConfigKey.butlerFloatingPanelFrameJSON)
    }
    
    
    private static func restoredPanelFrame(in visibleScreenFrame: NSRect) -> NSRect? {
        let raw = CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.butlerFloatingPanelFrameJSON, default: "")
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let vals = try? JSONDecoder().decode([Double].self, from: data),
              vals.count == 4
        else { return nil }
        let width = min(1120, max(500, vals[2]))
        let height = min(860, max(420, vals[3]))
        let clampedW = min(width, max(500, visibleScreenFrame.width - 24))
        let clampedH = min(height, max(420, visibleScreenFrame.height - 24))
        let clampedX = min(max(vals[0], visibleScreenFrame.minX + 12), visibleScreenFrame.maxX - clampedW - 12)
        let clampedY = min(max(vals[1], visibleScreenFrame.minY + 12), visibleScreenFrame.maxY - clampedH - 12)
        return NSRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
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
        if let panelResizeObserver {
            NotificationCenter.default.removeObserver(panelResizeObserver)
            self.panelResizeObserver = nil
        }
        if let panelMoveObserver {
            NotificationCenter.default.removeObserver(panelMoveObserver)
            self.panelMoveObserver = nil
        }
        if let panel = self.panel {
            Self.persistPanelFrame(panel.frame)
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil
        }
        self.panelHosting = nil
    }
}


private struct ButlerToolbarCapsuleLabel: View {
    
    @State private var butler = CotButlerManager.shared
    @State private var journalService = ProactiveDailyJournalService.shared
    @State private var imageLoader = AIGijinkaImageLoader.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let _ = self.journalService.revision
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
            } else if self.journalService.unreadCount > 0 {
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


// MARK: - Unified Beautiful UI Butler Command Hub (Powered by Pi 1.6+ RPC Kernel)

struct ButlerCommandHubView: View {
    
    weak var hostWindow: NSWindow?
    var isDockedPane: Bool = false
    var initialSeedPrompt: String = ""
    var panelCornerRadius: CGFloat = 0
    var surfaceColor: Color? = nil
    var isDarkOverride: Bool? = nil
    var hasCustomBackground: Bool = false
    var isPinnedPanel: Binding<Bool> = .constant(false)
    var onDockToPane: (() -> Void)? = nil
    var onSetSuppressDismiss: ((Bool) -> Void)? = nil
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(.documentAppearance) private var documentAppearance
    @State private var butler = CotButlerManager.shared
    @State private var botStore = AIBotStore.shared
    @State private var database = CotLocalDatabase.shared
    @State private var piKernel = PiKernelManager.shared
    @State private var userProfile = UserProfileManager.shared
    @State private var proactiveEngine = CotButlerProactiveEngine.shared
    @State private var meetingRoom = ButlerMeetingRoomManager.shared
    @State private var stickerStore = CotStickerLibraryStore.shared
    @State private var webController = BeautifulAgentWebController()
    @State private var availableModels: [BeautifulAgentModelPayload] = []
    @State private var quotedExcerpt: String? = nil
    @State private var streamListenerID: UUID? = nil
    
    private var resolvedIsDark: Bool {
        if let isDarkOverride {
            return isDarkOverride
        }
        switch self.documentAppearance {
            case .light: return false
            case .dark: return true
            case .default: return self.colorScheme == .dark
        }
    }
    
    private func resolvedThemeSurfaces(isDark: Bool) -> (pageHex: String?, canvasHex: String?) {
        guard self.isDockedPane, let surfaceColor else {
            return (nil, nil)
        }
        let fallbackSRGB = isDark
            ? NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
            : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1.0)
        let srgb = NSColor(surfaceColor).usingColorSpace(.sRGB) ?? fallbackSRGB
        let targetComponent: CGFloat = isDark ? 1.0 : 0.0
        let ratio: CGFloat = isDark ? 0.035 : 0.025
        let blended = NSColor(
            srgbRed: srgb.redComponent * (1 - ratio) + targetComponent * ratio,
            green: srgb.greenComponent * (1 - ratio) + targetComponent * ratio,
            blue: srgb.blueComponent * (1 - ratio) + targetComponent * ratio,
            alpha: 1.0
        )
        if self.hasCustomBackground {
            let pr = Int((srgb.redComponent * 255).rounded())
            let pg = Int((srgb.greenComponent * 255).rounded())
            let pb = Int((srgb.blueComponent * 255).rounded())
            let cr = Int((blended.redComponent * 255).rounded())
            let cg = Int((blended.greenComponent * 255).rounded())
            let cb = Int((blended.blueComponent * 255).rounded())
            return (
                "rgba(\(pr), \(pg), \(pb), 0.56)",
                "rgba(\(cr), \(cg), \(cb), 0.78)"
            )
        }
        return (StudioPaletteManager.hexString(from: srgb), StudioPaletteManager.hexString(from: blended))
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
            callbacks: self.buildCallbacks(),
            cornerRadius: self.panelCornerRadius
        )
        .equatable()
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
        .onReceive(NotificationCenter.default.publisher(for: CotStickerLibraryStore.didChangeNotification)) { _ in
            self.webController.syncState(self.buildHostState(), force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: AIBotStore.customBotsDidChangeNotification)) { _ in
            self.webController.syncState(self.buildHostState(), force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: CotButlerManager.identityDidChangeNotification)) { _ in
            self.webController.syncState(self.buildHostState(), force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserProfileManager.activeProfileDidChangeNotification)) { _ in
            self.webController.syncState(self.buildHostState(), force: true)
        }
        .task {
            self.reloadModels()
            let targetProfile = self.botStore.resolvedEndpointProfile(for: .butler)
            if (try? await self.botStore.refreshGatewayModels(for: targetProfile)) != nil {
                self.reloadModels()
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
        _ = self.database.documentsRevision
        
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
                createdAt: msg.createdAt.timeIntervalSince1970 * 1000,
                attachedDocuments: meta.attachedDocuments.isEmpty ? nil : meta.attachedDocuments,
                delegatedBotID: meta.delegatedBotID,
                delegatedBotName: meta.delegatedBotName,
                delegatedModel: meta.delegatedModel,
                stickerID: meta.stickerID,
                stickerURL: meta.stickerURL,
                stickerCaption: meta.stickerCaption
            )
        }
        
        let isActiveSessionStreaming = self.butler.isStreaming
            && self.butler.streamingSessionID == self.butler.activeSessionID
        if isActiveSessionStreaming, let streamID = self.butler.streamingMessageID {
            let startedAtMs = (self.butler.streamingStartedAt ?? Date()).timeIntervalSince1970 * 1000
            payloadMessages.append(BeautifulAgentMessagePayload(
                id: streamID,
                role: "assistant",
                text: self.butler.streamingDraft,
                thinking: self.butler.streamingThinking.isEmpty ? nil : self.butler.streamingThinking,
                thinkingDurationMs: nil,
                steps: self.butler.streamingSteps.isEmpty ? nil : self.butler.streamingSteps,
                toolChips: nil,
                followUps: nil,
                isStreaming: true,
                isError: false,
                quoteContext: nil,
                createdAt: startedAtMs
            ))
        }
        
        let sessions = self.butler.sessions.map {
            BeautifulAgentSessionPayload(
                id: $0.id,
                title: $0.title,
                isPinned: $0.isPinned,
                messageCount: $0.messageCount,
                updatedAt: $0.updatedAt.timeIntervalSince1970 * 1000,
                workspaceID: $0.workspaceID,
                workspacePath: $0.workspacePath,
                workspaceName: $0.workspaceName,
                sortOrder: $0.sortOrder
            )
        }
        
        let workspaces = self.butler.availableWorkspaces().map {
            BeautifulAgentWorkspacePayload(
                id: $0.id,
                path: $0.path,
                name: $0.name,
                folderPath: $0.folderPath,
                subtitle: $0.subtitle,
                isFolderBacked: $0.isFolderBacked,
                isOpenInEditor: $0.isOpenInEditor
            )
        }
        
        let availableDocuments = self.buildDocumentMentionCandidates()
        let availableBots = self.buildBotMentionCandidates()
        
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
                glyph: "selection",
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
            .init(key: "meeting", name: "/meeting", desc: AppLanguage.text("进入会议室召集所有 Bot 复盘汇报", en: "Convene all bots in Meeting Room"), insertText: "/meeting "),
            .init(key: "market", name: "/market", desc: AppLanguage.text("查实时股价并分析走势", en: "Lookup live stock quote"), insertText: "/market "),
            .init(key: "news", name: "/news", desc: AppLanguage.text("汇总今天最值得关注的 AI/科技热点", en: "Summarize today's news"), insertText: "/news "),
            .init(key: "memory", name: "/memory", desc: AppLanguage.text("记住我的长期偏好或习惯", en: "Save to long-term memory"), insertText: "/memory "),
            .init(key: "new", name: "/new", desc: AppLanguage.text("开启一段全新对话", en: "Start a fresh chat"), insertText: "/new"),
        ]
        
        let userDisplayName = self.userProfile.activeProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let greetingName = userDisplayName.isEmpty ? self.butler.name : userDisplayName
        let isDark = self.resolvedIsDark
        let surfaces = self.resolvedThemeSurfaces(isDark: isDark)
        let _ = self.proactiveEngine.revision
        let _ = self.meetingRoom.revision
        let _ = self.stickerStore.revision
        let _ = self.botStore.customBotsRevision
        let _ = self.botStore.avatarRevision
        let avatarRev = self.botStore.avatarRevision &+ self.botStore.customBotsRevision
        let rawUserHash = (self.userProfile.activeProfile.avatarData?.hashValue ?? 0)
            ^ self.userProfile.activeProfile.id.hashValue
        let userAvatarRev = Int(bitPattern: UInt(bitPattern: rawUserHash) & 0x7FFF_FFFF)
        let workers = self.proactiveEngine.workers
        let meetingBots = self.meetingRoom.participantRoster(botStore: self.botStore)
        let meetingSessions = self.meetingRoom.sessions.map {
            MeetingRoomSessionPayload(
                id: $0.id,
                title: $0.title,
                isPinned: $0.isPinned,
                updatedAt: $0.updatedAtMs,
                participantIDs: $0.participantIDs
            )
        }
        let refreshedMeetingMessages: [MeetingRoomMessage] = self.meetingRoom.messages.map { msg in
            guard msg.role == "bot", let bid = msg.botID, !bid.isEmpty else { return msg }
            var copy = msg
            if let liveName = self.botStore.unifiedBot(id: bid)?.name, !liveName.isEmpty {
                copy.botName = liveName
            }
            copy.botAvatarURL = CotMediaSchemeHandler.botAvatarURLString(botID: bid, revision: avatarRev)
            return copy
        }
        let stickerCatalog: [BeautifulAgentStickerPayload] = self.stickerStore.stickers.map { stk in
            BeautifulAgentStickerPayload(
                id: stk.id,
                url: CotMediaSchemeHandler.stickerURLString(id: stk.id),
                category: stk.category,
                ocrText: stk.ocrText,
                meaning: stk.meaning,
                moods: stk.moods,
                tags: stk.tags,
                isFavorite: stk.isFavorite,
                isAnimated: stk.isAnimated,
                useCount: stk.useCount
            )
        }
        
        return BeautifulAgentHostStatePayload(
            mode: "butler",
            isDark: isDark,
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
            isStreaming: isActiveSessionStreaming,
            streamingStatusLabel: isActiveSessionStreaming && !self.butler.streamingStatusLabel.isEmpty ? self.butler.streamingStatusLabel : nil,
            errorMessage: self.butler.lastErrorMessage,
            placeholder: AppLanguage.text("输入问题，输入 @ 引用文档或指派 Bots", en: "Ask anything, or type @ for docs & bots"),
            greetingName: greetingName,
            greetingSubtitle: nil,
            articleTitle: nil,
            articleSource: nil,
            quotedExcerpt: self.quotedExcerpt,
            availableModels: self.availableModels,
            selectedModelID: self.activeModelID,
            selectedModelTitle: self.activeModelID,
            effort: nil,
            suggestions: [],
            contextSources: contextSources,
            slashCommands: slashCommands,
            availableWorkspaces: workspaces,
            availableDocuments: availableDocuments,
            availableBots: availableBots,
            themePageHex: surfaces.pageHex,
            themeCanvasHex: surfaces.canvasHex,
            proactiveCards: nil,
            backgroundWorkers: workers,
            meetingRoomActive: self.meetingRoom.isActive,
            meetingRoomIsConvening: self.meetingRoom.isConvening,
            meetingRoomMessages: refreshedMeetingMessages,
            meetingRoomBots: meetingBots,
            meetingRoomSessions: meetingSessions,
            activeMeetingSessionID: self.meetingRoom.activeSessionID,
            stickerCatalog: stickerCatalog,
            userAvatarURL: CotMediaSchemeHandler.userAvatarURLString(revision: userAvatarRev),
            onlineStickerExpansionEnabled: OnlineStickerSearchService.isAutoExpansionEnabled
        )
    }
    
    
    private func buildDocumentMentionCandidates() -> [BeautifulAgentDocumentMentionPayload] {
        var result: [BeautifulAgentDocumentMentionPayload] = []
        var seenPaths: Set<String> = []
        var seenIDs: Set<String> = []
        
        // 1. Live open editor tabs
        for openDoc in CotAgentCoordinator.shared.openEditorDocuments(maxContentChars: 120) {
            if let fp = openDoc.filePath { seenPaths.insert(fp) }
            guard seenIDs.insert(openDoc.id).inserted else { continue }
            let desc = openDoc.isActive
                ? AppLanguage.text("当前正在编辑", en: "Active tab")
                : AppLanguage.text("已打开标签页", en: "Open tab")
            result.append(BeautifulAgentDocumentMentionPayload(
                id: openDoc.id,
                title: openDoc.title,
                desc: desc,
                sourceKind: "open_tab",
                filePath: openDoc.filePath,
                isActive: openDoc.isActive
            ))
        }
        
        // 2. Files in active session's bound workspace folder
        if let wsPath = self.butler.activeWorkspacePath, !wsPath.isEmpty {
            let wsURL = URL(filePath: wsPath)
            let wsName = wsURL.lastPathComponent
            for file in CotAgentCoordinator.listWorkspaceFiles(at: wsURL, limit: 28) {
                guard !seenPaths.contains(file.fullPath) else { continue }
                seenPaths.insert(file.fullPath)
                let id = "ws:\(file.fullPath)"
                guard seenIDs.insert(id).inserted else { continue }
                result.append(BeautifulAgentDocumentMentionPayload(
                    id: id,
                    title: file.title,
                    desc: "\(wsName)/\(file.relativePath)",
                    sourceKind: "workspace_file",
                    filePath: file.fullPath,
                    isActive: false
                ))
            }
        }
        
        // 3. Stored Document Center documents
        for doc in self.database.documents where doc.deletedAt == nil {
            if result.count >= 64 { break }
            if let fp = doc.filePath, !fp.isEmpty, seenPaths.contains(fp) { continue }
            let id = "doc:\(doc.id)"
            guard seenIDs.insert(id).inserted else { continue }
            let desc = doc.groupName.isEmpty
                ? AppLanguage.text("文档库", en: "Document Library")
                : doc.groupName
            result.append(BeautifulAgentDocumentMentionPayload(
                id: id,
                title: doc.title,
                desc: desc,
                sourceKind: "stored_doc",
                filePath: doc.filePath,
                isActive: false
            ))
        }
        
        // 4. Recent weekly reports
        for rep in self.database.weeklyReports.prefix(8) {
            let id = "report:\(rep.id)"
            guard seenIDs.insert(id).inserted else { continue }
            result.append(BeautifulAgentDocumentMentionPayload(
                id: id,
                title: rep.title,
                desc: AppLanguage.text("周报 · \(rep.periodLabel)", en: "Report · \(rep.periodLabel)"),
                sourceKind: "weekly_report",
                filePath: rep.sourcePath,
                isActive: false
            ))
        }
        
        return result
    }
    
    
    private func buildBotMentionCandidates() -> [BeautifulAgentBotMentionPayload] {
        let avatarRev = self.botStore.avatarRevision &+ self.botStore.customBotsRevision
        var list: [BeautifulAgentBotMentionPayload] = []
        // Put user-created custom Bots first so newly added Bots immediately surface in @ menus
        for custom in self.botStore.customBots where custom.isEnabled {
            let trimmedPersona = custom.personaPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            list.append(BeautifulAgentBotMentionPayload(
                id: custom.id,
                name: custom.name,
                nickname: custom.nickname,
                handle: custom.handle,
                tagline: trimmedPersona.isEmpty ? "" : String(trimmedPersona.prefix(28)),
                accentHex: custom.accentHex,
                model: custom.modelOverride.isEmpty ? nil : custom.modelOverride,
                avatarURL: CotMediaSchemeHandler.botAvatarURLString(botID: custom.id, revision: avatarRev),
                isCustom: true
            ))
        }
        let delegatable: [AIBotID] = [
            .translate,
            .summarize,
            .explain,
            .weeklyReport,
            .weeklyReportItem,
            .interactiveChart,
            .organizeAndMerge,
            .ocrPolish,
            .readingCompanion,
            .persona,
        ]
        for botID in delegatable {
            let cfg = self.botStore.config(for: botID)
            guard cfg.isEnabled else { continue }
            let resolvedModel = cfg.modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            list.append(BeautifulAgentBotMentionPayload(
                id: botID.rawValue,
                name: self.botStore.resolvedName(for: botID),
                nickname: self.botStore.resolvedNickname(for: botID),
                handle: botID.handle,
                tagline: botID.tagline,
                accentHex: botID.accentHex,
                model: resolvedModel.isEmpty ? nil : resolvedModel,
                avatarURL: CotMediaSchemeHandler.botAvatarURLString(botID: botID.rawValue, revision: avatarRev),
                isCustom: false
            ))
        }
        return list
    }
    
    
    private func presentWorkspaceFolderPicker(sessionID: String, createNewSession: Bool, workspaceID: String? = nil) {
        self.onSetSuppressDismiss?(true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = AppLanguage.text("关联文件夹", en: "Link Folder")
        panel.message = AppLanguage.text("可选：为该工作区关联一个本地文件夹（不选也可作为纯逻辑工作区使用）", en: "Optional: link a local folder to this workspace")
        if let existing = self.butler.activeWorkspacePath, FileManager.default.fileExists(atPath: existing) {
            panel.directoryURL = URL(filePath: existing)
        } else if let activeDir = CotAgentCoordinator.shared.activeWorkingDirectoryURL() {
            panel.directoryURL = activeDir
        }
        let response = panel.runModal()
        self.onSetSuppressDismiss?(false)
        guard response == .OK, let selectedURL = panel.url else { return }
        let path = selectedURL.standardizedFileURL.path(percentEncoded: false)
        if let workspaceID, !workspaceID.isEmpty {
            self.butler.updateWorkspaceFolder(workspaceID, folderPath: path)
        } else if createNewSession {
            self.butler.startNewSession(workspacePath: path)
        } else {
            let targetSessionID = sessionID.isEmpty ? self.butler.activeSessionID : sessionID
            if let existingWSID = self.butler.sessions.first(where: { $0.id == targetSessionID })?.workspaceID {
                self.butler.updateWorkspaceFolder(existingWSID, folderPath: path)
            } else {
                self.butler.setSessionWorkspace(targetSessionID, workspacePath: path)
            }
        }
        self.webController.focusComposer()
    }
    
    
    private func buildCallbacks() -> BeautifulAgentWebActionCallbacks {
        var cb = BeautifulAgentWebActionCallbacks()
        // Keep the shared send handler outside `cb` so `cb.onSend` does not capture
        // the mutable `cb` struct by reference box (which creates a retain cycle and
        // causes infinite recursion in SwiftUI's AG::LayoutDescriptor::compare_heap_objects).
        let handleSendRichWithSticker: (String, String, [ButlerDocumentAttachment], String?, String?) -> Void = { prompt, quote, attachedDocs, delegatedBotID, stickerID in
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "/new" {
                self.meetingRoom.setActive(false)
                self.butler.startNewSession(workspaceID: self.butler.activeWorkspaceID, workspacePath: self.butler.activeWorkspacePath)
                return
            }
            if MeetingRoomRouter.isMeetingTriggerInButlerChat(trimmed) {
                let agenda = trimmed.hasPrefix("/meeting")
                    ? String(trimmed.dropFirst("/meeting".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    : trimmed
                self.meetingRoom.setActive(true)
                let finalAgenda = agenda.isEmpty ? AppLanguage.text("汇总一下今天的信息", en: "Summarize today's updates") : agenda
                Task {
                    await self.meetingRoom.submitPrompt(finalAgenda, stickerID: stickerID, explicitBotID: delegatedBotID)
                }
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
                await self.butler.sendMessage(
                    resolvedPrompt,
                    quote: effectiveQuote,
                    contextSources: contextSources,
                    attachedDocuments: attachedDocs,
                    delegatedBotID: delegatedBotID,
                    stickerID: stickerID
                )
            }
        }
        cb.onSendRichWithSticker = handleSendRichWithSticker
        cb.onSendRich = { prompt, quote, attachedDocs, delegatedBotID in
            handleSendRichWithSticker(prompt, quote, attachedDocs, delegatedBotID, nil)
        }
        cb.onSend = { prompt, quote in
            handleSendRichWithSticker(prompt, quote, [], nil, nil)
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
            self.meetingRoom.setActive(false)
            self.butler.startNewSession(workspaceID: self.butler.activeWorkspaceID, workspacePath: self.butler.activeWorkspacePath)
        }
        cb.onNewSessionInWorkspace = { wsPath in
            self.meetingRoom.setActive(false)
            self.butler.startNewSession(workspacePath: wsPath)
        }
        cb.onNewSessionInWorkspaceTarget = { wsID, wsPath in
            self.meetingRoom.setActive(false)
            self.butler.startNewSession(workspaceID: wsID, workspacePath: wsPath)
        }
        cb.onSelectSession = { id in
            self.meetingRoom.setActive(false)
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
        cb.onSetSessionWorkspace = { sessionID, wsPath in
            self.butler.setSessionWorkspace(sessionID, workspacePath: wsPath)
        }
        cb.onSetSessionWorkspaceTarget = { sessionID, wsID, wsPath in
            if let wsID, !wsID.isEmpty {
                self.butler.setSessionWorkspace(sessionID, workspaceID: wsID)
            } else if let wsPath, !wsPath.isEmpty {
                self.butler.setSessionWorkspace(sessionID, workspacePath: wsPath)
            } else {
                self.butler.setSessionWorkspace(sessionID, workspaceID: nil)
            }
        }
        cb.onChooseWorkspaceFolder = { sessionID, createNew in
            self.presentWorkspaceFolderPicker(sessionID: sessionID, createNewSession: createNew)
        }
        cb.onCreateWorkspace = { name, folderPath, startSession, assignSessionID in
            _ = self.butler.createWorkspace(
                name: name,
                folderPath: folderPath,
                startSession: startSession,
                assignSessionID: assignSessionID
            )
            self.webController.focusComposer()
        }
        cb.onRenameWorkspace = { id, name in
            self.butler.renameWorkspace(id, to: name)
        }
        cb.onDeleteWorkspace = { id in
            self.butler.deleteWorkspace(id)
        }
        cb.onUpdateWorkspaceFolder = { id, folderPath in
            self.butler.updateWorkspaceFolder(id, folderPath: folderPath)
        }
        cb.onChooseWorkspaceFolderForWorkspace = { wsID in
            self.presentWorkspaceFolderPicker(sessionID: self.butler.activeSessionID, createNewSession: false, workspaceID: wsID)
        }
        cb.onReorderWorkspaces = { orderedIDs in
            self.butler.reorderWorkspaces(orderedIDs)
        }
        cb.onMoveSession = { sessionID, targetWSID, orderedIDs, isPinned in
            self.butler.moveSession(sessionID, toWorkspaceID: targetWSID, orderedSessionIDs: orderedIDs, isPinned: isPinned)
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
            self.webController.syncState(self.buildHostState(), force: true)
        }
        cb.onDockToPane = {
            self.onDockToPane?()
        }
        cb.onDismissPanel = {
            self.onDismiss()
        }
        cb.onDismissProactiveCard = { id in
            self.proactiveEngine.dismissCard(id: id)
        }
        cb.onOpenWorkerAction = { board, query in
            let splitRight = !self.isDockedPane
            Task {
                _ = await CotAgentCoordinator.shared.execute([
                    CotAgentAction(type: "open_board", board: board, query: query, splitRight: splitRight),
                ])
            }
        }
        cb.onDismissWorker = { id in
            self.proactiveEngine.dismissWorker(id: id)
        }
        cb.onToggleMeetingRoom = { active in
            self.meetingRoom.setActive(active)
        }
        cb.onSendMeetingPrompt = { prompt, botID in
            self.meetingRoom.setActive(true)
            Task {
                await self.meetingRoom.submitPrompt(prompt, explicitBotID: botID)
            }
        }
        cb.onSendMeetingPromptRich = { prompt, stickerID, botID in
            self.meetingRoom.setActive(true)
            Task {
                await self.meetingRoom.submitPrompt(prompt, stickerID: stickerID, explicitBotID: botID)
            }
        }
        cb.onClearMeetingRoom = {
            self.meetingRoom.clearMeeting()
        }
        cb.onAbortMeetingRoom = {
            self.meetingRoom.abortMeeting()
        }
        cb.onNewMeetingSession = {
            _ = self.meetingRoom.createSession()
        }
        cb.onSelectMeetingSession = { id in
            self.meetingRoom.selectSession(id)
        }
        cb.onRenameMeetingSession = { id, title in
            self.meetingRoom.renameSession(id, title: title)
        }
        cb.onDeleteMeetingSession = { id in
            self.meetingRoom.deleteSession(id)
        }
        cb.onTogglePinMeetingSession = { id in
            self.meetingRoom.togglePinSession(id)
        }
        cb.onToggleMeetingParticipant = { botID in
            self.meetingRoom.toggleParticipant(botID)
        }
        cb.onUploadSticker = {
            self.onSetSuppressDismiss?(true)
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .heic]
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            let response = panel.runModal()
            self.onSetSuppressDismiss?(false)
            if response == .OK, !panel.urls.isEmpty {
                let urls = panel.urls
                Task { @MainActor in
                    _ = await CotStickerLibraryStore.shared.importFiles(urls, defaultCategory: "custom")
                }
            }
        }
        cb.onToggleFavoriteSticker = { id in
            CotStickerLibraryStore.shared.toggleFavorite(id: id)
        }
        cb.onSearchOnlineStickers = { query in
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return }
            Task {
                let results = await OnlineStickerSearchService.search(query: q, limitPerSource: 3)
                for candidate in results.prefix(3) {
                    _ = await OnlineStickerSearchService.downloadAndImport(candidate: candidate)
                }
            }
        }
        cb.onOpenCreateBotSheet = {
            if !self.isDockedPane {
                self.onDismiss()
            }
            (NSApp.delegate as? AppDelegate)?.openCreateCustomBotSettings()
        }
        cb.onOpenBotConfig = { targetID in
            if !self.isDockedPane {
                self.onDismiss()
            }
            if targetID == "user" {
                (NSApp.delegate as? AppDelegate)?.openUserProfileSettings()
            } else {
                (NSApp.delegate as? AppDelegate)?.openBotConfig(idString: targetID)
            }
        }
        cb.onRefreshStickers = {
            self.stickerStore.syncWithDiskAndDatabase()
            self.webController.syncState(self.buildHostState(), force: true)
        }
        return cb
    }
    
    
    private func reloadModels() {
        let groups = self.botStore.selectableGatewayGroups()
        let showGatewayLabel = groups.count > 1
        var list: [BeautifulAgentModelPayload] = []
        for group in groups {
            let endpointID = group.profile.id.uuidString
            let gatewaySuffix = showGatewayLabel ? group.title : nil
            list.append(contentsOf: Self.mapModels(group.models, endpointID: endpointID, gatewayLabel: gatewaySuffix))
        }
        self.availableModels = list
    }
    
    
    private static func mapModels(
        _ ids: [String],
        endpointID: String?,
        gatewayLabel: String? = nil
    ) -> [BeautifulAgentModelPayload] {
        ids.map { mid in
            let lower = mid.lowercased()
            let isFlagship = lower.contains("opus") || lower.contains("gpt-5") || lower.contains("glm-5") || lower.contains("deepseek-v4") || lower.contains("gemini-2.5-pro")
            let tierTag: String? = if lower.contains("flash") || lower.contains("haiku") || lower.contains("mini") {
                AppLanguage.text("快推", en: "Fast")
            } else if lower.contains("opus") || lower.contains("pro") || lower.contains("reasoner") {
                AppLanguage.text("深度", en: "Deep")
            } else if lower.contains("glm-5") || lower.contains("sonnet") || lower.contains("gpt-5") {
                AppLanguage.text("主力", en: "Flagship")
            } else {
                nil
            }
            let combinedTag: String? = switch (gatewayLabel, tierTag) {
                case let (gw?, tier?): "\(gw) · \(tier)"
                case let (gw?, nil): gw
                case let (nil, tier?): tier
                case (nil, nil): nil
            }
            return BeautifulAgentModelPayload(
                id: "\(endpointID ?? "default"):\(mid)",
                modelID: mid,
                title: mid,
                endpointID: endpointID,
                tag: combinedTag,
                isFlagship: isFlagship
            )
        }
    }
}
