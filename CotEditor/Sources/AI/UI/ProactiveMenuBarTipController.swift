//
//  ProactiveMenuBarTipController.swift
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

/// Pure frame geometry helper for anchoring floating panels cleanly beneath the macOS menu bar item.
nonisolated enum MenuBarFloatingGeometry {
    
    static func anchoredFrame(
        statusItemRect: NSRect?,
        panelSize: NSSize,
        visibleScreenFrame: NSRect,
        margin: CGFloat = 10
    ) -> NSRect {
        let anchorX: CGFloat
        let topY: CGFloat
        if let rect = statusItemRect, rect.width > 0, rect.height > 0 {
            anchorX = rect.midX - panelSize.width * 0.5
            topY = rect.minY - 6
        } else {
            anchorX = visibleScreenFrame.maxX - panelSize.width - margin
            topY = visibleScreenFrame.maxY - margin
        }
        let clampedX = min(
            max(visibleScreenFrame.minX + margin, anchorX),
            max(visibleScreenFrame.minX + margin, visibleScreenFrame.maxX - panelSize.width - margin)
        )
        let clampedY = max(visibleScreenFrame.minY + margin, topY - panelSize.height)
        return NSRect(x: floor(clampedX), y: floor(clampedY), width: panelSize.width, height: panelSize.height)
    }
}


/// Manages the macOS menu bar extra icon, non-activating floating tip bubble,
/// and compact daily-journal hub popover for CotEditor's proactive agent.
@MainActor
final class ProactiveMenuBarTipController: NSObject {
    
    static let shared = ProactiveMenuBarTipController()
    
    private final class FloatingTipPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    
    private final class HubPopoverPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    
    private let service: ProactiveDailyJournalService
    private var statusItem: NSStatusItem?
    private var tipPanel: FloatingTipPanel?
    private var tipHosting: NSHostingController<ProactiveFloatingTipView>?
    private var hubPanel: HubPopoverPanel?
    private var hubHosting: NSHostingController<ProactiveMenuBarHubView>?
    private var autoDismissTask: Task<Void, Never>?
    private var isTipHovered = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    
    
    private init(service: ProactiveDailyJournalService = .shared) {
        self.service = service
        super.init()
    }
    
    
    func setupStatusItemIfNeeded() {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        if self.statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(self.toggleHubPopover(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            self.statusItem = item
            self.refreshStatusItemAppearance()
        }
        
        self.service.onTipPublished = { [weak self] tip in
            self?.refreshStatusItemAppearance()
            self?.presentFloatingTip(tip)
        }
    }
    
    
    func refreshStatusItemAppearance() {
        guard let button = self.statusItem?.button else { return }
        let unread = self.service.unreadCount
        let symbolName = unread > 0 ? "note.text.badge.plus" : "note.text"
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: AppLanguage.text("总管随记", en: "Agent Journal"))
        img?.isTemplate = true
        button.image = img
        button.toolTip = unread > 0
            ? AppLanguage.text("总管随记 · \(unread) 条未读", en: "Agent Journal · \(unread) unread")
            : AppLanguage.text("总管随记", en: "Agent Journal")
    }
    
    
    func presentFloatingTip(_ tip: ProactiveTipItem) {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        guard self.hubPanel?.isVisible != true else { return }
        
        self.dismissFloatingTip(animated: false)
        self.isTipHovered = false
        
        let cornerRadius: CGFloat = 14
        let rootView = ProactiveFloatingTipView(
            tip: tip,
            butlerName: CotButlerManager.shared.name,
            onOpenJournal: { [weak self] in
                self?.dismissFloatingTip(animated: true)
                self?.service.openTodayJournalWindow()
                self?.refreshStatusItemAppearance()
            },
            onNextTip: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    _ = await self.service.recordProactiveNote(allowRemoteAI: false, showFloatingTip: true)
                }
            },
            onDismiss: { [weak self] in
                self?.dismissFloatingTip(animated: true)
            },
            onHoverChanged: { [weak self] hovered in
                self?.isTipHovered = hovered
                if !hovered {
                    self?.scheduleAutoDismiss(seconds: 6)
                } else {
                    self?.autoDismissTask?.cancel()
                }
            }
        )
        
        let panelSize = NSSize(width: 312, height: 118)
        let (vfx, hosting) = Self.makeGlassContainer(rootView: rootView, cornerRadius: cornerRadius)
        let frame = self.resolveMenuBarAnchoredFrame(size: panelSize)
        
        let panel = FloatingTipPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = vfx
        panel.invalidateShadow()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().alphaValue = 1.0
        }
        
        self.tipPanel = panel
        self.tipHosting = hosting
        self.scheduleAutoDismiss(seconds: 12)
    }
    
    
    func dismissFloatingTip(animated: Bool = true) {
        self.autoDismissTask?.cancel()
        self.autoDismissTask = nil
        guard let panel = self.tipPanel else { return }
        self.tipPanel = nil
        self.tipHosting = nil
        
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                }
            })
        } else {
            panel.orderOut(nil)
        }
    }
    
    
    @objc private func toggleHubPopover(_ sender: Any?) {
        if self.hubPanel?.isVisible == true {
            self.closeHubPopover()
            return
        }
        self.presentHubPopover()
    }
    
    
    private func presentHubPopover() {
        self.dismissFloatingTip(animated: false)
        self.closeHubPopover()
        _ = self.service.ensureTodayDocument()
        self.refreshStatusItemAppearance()
        
        let cornerRadius: CGFloat = 14
        let rootView = ProactiveMenuBarHubView(
            service: self.service,
            onOpenJournal: { [weak self] in
                self?.closeHubPopover()
                self?.service.openTodayJournalWindow()
                self?.refreshStatusItemAppearance()
            },
            onRecordNow: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    _ = await self.service.recordProactiveNote(allowRemoteAI: false, showFloatingTip: false)
                    self.refreshStatusItemAppearance()
                }
            },
            onOpenButlerChat: { [weak self] in
                self?.closeHubPopover()
                NSApp.activate(ignoringOtherApps: true)
                CotButlerManager.shared.requestOpenHub()
            }
        )
        
        let panelSize = NSSize(width: 332, height: 344)
        let (vfx, hosting) = Self.makeGlassContainer(rootView: rootView, cornerRadius: cornerRadius)
        let frame = self.resolveMenuBarAnchoredFrame(size: panelSize)
        
        let panel = HubPopoverPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = vfx
        panel.invalidateShadow()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().alphaValue = 1.0
        }
        
        self.hubPanel = panel
        self.hubHosting = hosting
        self.installHubDismissMonitors(panel: panel)
    }
    
    
    private func closeHubPopover() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        self.hubPanel?.orderOut(nil)
        self.hubPanel = nil
        self.hubHosting = nil
    }
    
    
    private func installHubDismissMonitors(panel: HubPopoverPanel) {
        self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window === panel { return event }
            if let buttonWindow = self.statusItem?.button?.window, event.window === buttonWindow {
                return event
            }
            self.closeHubPopover()
            return event
        }
        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeHubPopover()
            }
        }
    }
    
    
    private func scheduleAutoDismiss(seconds: Int) {
        self.autoDismissTask?.cancel()
        self.autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isTipHovered else { return }
            self.dismissFloatingTip(animated: true)
        }
    }
    
    
    private func resolveMenuBarAnchoredFrame(size: NSSize) -> NSRect {
        let button = self.statusItem?.button
        let statusRect: NSRect? = button?.window.map { win in
            let rectInWin = button?.convert(button?.bounds ?? .zero, to: nil) ?? .zero
            return win.convertToScreen(rectInWin)
        }
        let screen = button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return MenuBarFloatingGeometry.anchoredFrame(
            statusItemRect: statusRect,
            panelSize: size,
            visibleScreenFrame: visible
        )
    }
    
    
    private static func makeGlassContainer<Content: View>(
        rootView: Content,
        cornerRadius: CGFloat
    ) -> (NSVisualEffectView, NSHostingController<Content>) {
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.maskImage = UserAvatarToolbarButtonView.makeRoundedMaskImage(cornerRadius: cornerRadius)
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.layer?.cornerCurve = .continuous
        vfx.layer?.masksToBounds = true
        vfx.layer?.borderWidth = 0.6
        vfx.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.26).cgColor
        
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = []
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        vfx.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: vfx.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: vfx.bottomAnchor),
        ])
        return (vfx, hosting)
    }
}


// MARK: - SwiftUI Views (Floating Tip & Menu Bar Popover)

struct ProactiveFloatingTipView: View {
    
    let tip: ProactiveTipItem
    let butlerName: String
    let onOpenJournal: () -> Void
    let onNextTip: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(self.tip.category)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                
                Text("\(self.butlerName) · \(ProactiveJournalComposer.clockText(for: self.tip.createdAt))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 4)
                
                Button(action: self.onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(self.tip.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(self.tip.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 8) {
                Button(action: self.onOpenJournal) {
                    Text(AppLanguage.text("打开今日随记", en: "Open Journal"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button(action: self.onNextTip) {
                    Text(AppLanguage.text("再记一条", en: "Next Tip"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onHover(perform: self.onHoverChanged)
    }
}


struct ProactiveMenuBarHubView: View {
    
    @Bindable var service: ProactiveDailyJournalService
    let onOpenJournal: () -> Void
    let onRecordNow: () -> Void
    let onOpenButlerChat: () -> Void
    
    @State private var hoveredTipID: String?
    
    var body: some View {
        let _ = self.service.revision
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.service.todayDocumentTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(AppLanguage.text("\(self.service.todayTips.count) 条记录", en: "\(self.service.todayTips.count) entries"))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 8)
                
                Button(action: self.onOpenJournal) {
                    Text(AppLanguage.text("打开文档", en: "Open"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Divider()
            
            if self.service.todayTips.isEmpty {
                VStack(spacing: 10) {
                    Text(AppLanguage.text("今日随记暂无记录", en: "No entries yet"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button(action: self.onRecordNow) {
                        Label(AppLanguage.text("立即记录一条", en: "Record Note"), systemImage: "plus")
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(self.service.todayTips) { tip in
                            self.tipRow(tip)
                        }
                    }
                    .padding(10)
                }
            }
            
            Divider()
            
            HStack(spacing: 8) {
                Button(action: self.onRecordNow) {
                    Label(AppLanguage.text("记一条", en: "Log"), systemImage: "square.and.pencil")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: self.onOpenButlerChat) {
                    Text(AppLanguage.text("总管对话", en: "Butler"))
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer(minLength: 4)
                
                Toggle(AppLanguage.text("浮窗提醒", en: "Tips"), isOn: self.$service.tipsEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    
    private func tipRow(_ tip: ProactiveTipItem) -> some View {
        let isHovered = (self.hoveredTipID == tip.id)
        return Button(action: self.onOpenJournal) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tip.category)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(ProactiveJournalComposer.clockText(for: tip.createdAt))
                        .font(.system(size: 10, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !tip.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(tip.headline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(tip.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(isHovered ? 0.065 : 0.03),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0.06), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { inside in
            self.hoveredTipID = inside ? tip.id : (self.hoveredTipID == tip.id ? nil : self.hoveredTipID)
        }
    }
}
