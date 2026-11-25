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

/// Pure frame & pointer geometry for anchoring a speech-bubble tip directly beneath the Butler toolbar button.
nonisolated enum ButlerTipBubbleGeometry {
    
    struct Placement: Equatable, Sendable {
        var frame: NSRect
        /// Horizontal X coordinate inside the bubble frame where the upward speech-bubble tail points.
        var arrowCenterX: CGFloat
    }
    
    static func placement(
        anchorScreenRect: NSRect,
        bubbleSize: NSSize,
        visibleScreenFrame: NSRect,
        margin: CGFloat = 10
    ) -> Placement {
        let desiredX = anchorScreenRect.midX - bubbleSize.width * 0.5
        let minX = visibleScreenFrame.minX + margin
        let maxX = max(minX, visibleScreenFrame.maxX - bubbleSize.width - margin)
        let clampedX = min(max(minX, desiredX), maxX)
        let topY = anchorScreenRect.minY - 4
        let clampedY = max(visibleScreenFrame.minY + margin, topY - bubbleSize.height)
        
        let rawArrowX = anchorScreenRect.midX - clampedX
        let clampedArrowX = min(max(24, rawArrowX), max(24, bubbleSize.width - 24))
        
        return Placement(
            frame: NSRect(x: floor(clampedX), y: floor(clampedY), width: bubbleSize.width, height: bubbleSize.height),
            arrowCenterX: clampedArrowX
        )
    }
}


/// Speech bubble silhouette with an upward pointer triangle aimed at the Butler icon beside Todos.
struct ButlerSpeechBubbleShape: Shape {
    
    var cornerRadius: CGFloat = 13
    var arrowHeight: CGFloat = 8
    var arrowWidth: CGFloat = 16
    var arrowCenterX: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let r = min(self.cornerRadius, min(rect.width, rect.height - self.arrowHeight) * 0.5)
        let topY = rect.minY + self.arrowHeight
        let halfArrow = self.arrowWidth * 0.5
        let clampedArrowX = min(max(rect.minX + r + halfArrow + 4, self.arrowCenterX), rect.maxX - r - halfArrow - 4)
        let arrowLeft = clampedArrowX - halfArrow
        let arrowRight = clampedArrowX + halfArrow
        
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: topY))
        path.addLine(to: CGPoint(x: arrowLeft, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: clampedArrowX, y: rect.minY + 1),
            control: CGPoint(x: arrowLeft + halfArrow * 0.45, y: topY)
        )
        path.addQuadCurve(
            to: CGPoint(x: arrowRight, y: topY),
            control: CGPoint(x: arrowRight - halfArrow * 0.45, y: topY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: topY))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: topY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: topY + r))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: topY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}


/// Presents lightweight, non-activating speech-bubble reminders exclusively anchored
/// beneath the Butler toolbar button beside the Todos icon (no macOS system menu bar icon).
@MainActor
final class ButlerToolbarTipBubbleController: NSObject {
    
    static let shared = ButlerToolbarTipBubbleController()
    
    private final class SpeechBubblePanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
    
    private struct WeakAnchor {
        weak var view: ToolbarButlerBotButtonView?
    }
    
    private let service: ProactiveDailyJournalService
    private var anchors: [WeakAnchor] = []
    private var bubblePanel: SpeechBubblePanel?
    private var bubbleHosting: NSHostingController<ButlerToolbarSpeechBubbleView>?
    private var autoDismissTask: Task<Void, Never>?
    private var isBubbleHovered = false
    private var windowCloseObserver: (any NSObjectProtocol)?
    
    
    private init(service: ProactiveDailyJournalService = .shared) {
        self.service = service
        super.init()
    }
    
    
    func startListening() {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        self.service.onTipPublished = { [weak self] tip in
            self?.presentTip(tip)
        }
    }
    
    
    func registerAnchor(_ view: ToolbarButlerBotButtonView) {
        self.anchors.removeAll { $0.view == nil || $0.view === view }
        self.anchors.append(WeakAnchor(view: view))
    }
    
    
    func unregisterAnchor(_ view: ToolbarButlerBotButtonView) {
        self.anchors.removeAll { $0.view == nil || $0.view === view }
    }
    
    
    func presentTip(_ tip: ProactiveTipItem, preferredAnchor: ToolbarButlerBotButtonView? = nil) {
        guard !CotLocalDatabase.isRunningUnitTests else { return }
        guard let anchor = preferredAnchor ?? self.resolveActiveAnchor(),
              let hostWindow = anchor.window,
              hostWindow.isVisible,
              !anchor.isFloatingChatVisible
        else { return }
        
        self.dismiss(animated: false)
        self.isBubbleHovered = false
        
        let bubbleSize = NSSize(width: 294, height: 118)
        let btnInWindow = anchor.convert(anchor.bounds, to: nil)
        let btnScreen = hostWindow.convertToScreen(btnInWindow)
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let placement = ButlerTipBubbleGeometry.placement(
            anchorScreenRect: btnScreen,
            bubbleSize: bubbleSize,
            visibleScreenFrame: screenFrame
        )
        
        let rootView = ButlerToolbarSpeechBubbleView(
            tip: tip,
            butlerName: CotButlerManager.shared.name,
            arrowCenterX: placement.arrowCenterX,
            onOpenJournal: { [weak self, weak hostWindow] in
                self?.dismiss(animated: true)
                self?.service.openTodayJournalWindow(preferredWindow: hostWindow)
            },
            onDismiss: { [weak self] in
                self?.dismiss(animated: true)
            },
            onHoverChanged: { [weak self] hovered in
                self?.isBubbleHovered = hovered
                if hovered {
                    self?.autoDismissTask?.cancel()
                } else {
                    self?.scheduleAutoDismiss(seconds: 6)
                }
            }
        )
        
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = []
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        
        let panel = SpeechBubblePanel(
            contentRect: placement.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = hostWindow.effectiveAppearance
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = hosting
        panel.invalidateShadow()
        panel.alphaValue = 0
        
        hostWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            panel.animator().alphaValue = 1.0
        }
        
        self.bubblePanel = panel
        self.bubbleHosting = hosting
        self.windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: hostWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss(animated: false)
            }
        }
        self.scheduleAutoDismiss(seconds: 11)
    }
    
    
    func dismiss(animated: Bool = true) {
        self.autoDismissTask?.cancel()
        self.autoDismissTask = nil
        if let observer = self.windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            self.windowCloseObserver = nil
        }
        guard let panel = self.bubblePanel else { return }
        self.bubblePanel = nil
        self.bubbleHosting = nil
        
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    panel.parent?.removeChildWindow(panel)
                    panel.orderOut(nil)
                }
            })
        } else {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
    
    
    private func resolveActiveAnchor() -> ToolbarButlerBotButtonView? {
        self.anchors.removeAll { $0.view == nil }
        let live = self.anchors.compactMap(\.view).filter { $0.window?.isVisible == true }
        if let key = live.first(where: { $0.window?.isKeyWindow == true }) {
            return key
        }
        if let main = live.first(where: { $0.window?.isMainWindow == true }) {
            return main
        }
        return live.first
    }
    
    
    private func scheduleAutoDismiss(seconds: Int) {
        self.autoDismissTask?.cancel()
        self.autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, !self.isBubbleHovered else { return }
            self.dismiss(animated: true)
        }
    }
}


// MARK: - SwiftUI Speech Bubble View

struct ButlerToolbarSpeechBubbleView: View {
    
    let tip: ProactiveTipItem
    let butlerName: String
    let arrowCenterX: CGFloat
    let onOpenJournal: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let shape = ButlerSpeechBubbleShape(
            cornerRadius: 13,
            arrowHeight: 8,
            arrowWidth: 16,
            arrowCenterX: self.arrowCenterX
        )
        let fillSurface = self.colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor).opacity(0.92)
            : Color.white.opacity(0.95)
        let borderColor = self.colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.10)
        
        VStack(alignment: .leading, spacing: 7) {
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
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(self.tip.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 8) {
                Button(action: self.onOpenJournal) {
                    Text(AppLanguage.text("查看今日随记", en: "Open Journal"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button(action: self.onDismiss) {
                    Text(AppLanguage.text("知道了", en: "Dismiss"))
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
        .padding(.top, 18)
        .padding(.bottom, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(fillSurface)
            }
        )
        .overlay(
            shape.stroke(borderColor, lineWidth: 0.8)
        )
        .clipShape(shape)
        .onHover(perform: self.onHoverChanged)
    }
}
