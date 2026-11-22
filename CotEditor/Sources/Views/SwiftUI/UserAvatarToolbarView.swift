//
//  UserAvatarToolbarView.swift
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

extension Color {
    
    /// Creates a color from a `#RRGGBB` hex string, defaulting to accent blue on parse failure.
    init(hexString: String) {
        
        let raw = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard Scanner(string: raw).scanHexInt64(&value), raw.count == 6 else {
            self = .accentColor
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}


/// Reusable circular avatar view displaying either a cropped photo or a tinted monogram.
struct UserAvatarCircleView: View {
    
    let profile: UserProfile
    let size: CGFloat
    var customImage: NSImage?
    
    @State private var manager = UserProfileManager.shared
    
    
    var body: some View {
        let resolvedImage = self.customImage ?? self.manager.avatarImage(for: self.profile)
        let baseColor = Color(hexString: self.profile.avatarColorHex)
        
        ZStack {
            if let resolvedImage {
                Image(nsImage: resolvedImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [baseColor.opacity(0.92), baseColor.opacity(0.80)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(UserProfileManager.initials(for: self.profile.displayName))
                    .font(.system(size: max(10, self.size * 0.42), weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
        )
    }
}


private struct UserAvatarToolbarBadgeLabel: View {
    
    @State private var manager = UserProfileManager.shared
    @State private var isHovered = false
    
    
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    Color(red: 0.18, green: 0.56, blue: 0.40).opacity(self.isHovered ? 0.55 : 0),
                    lineWidth: 1.5
                )
                .frame(width: 28, height: 28)
                .scaleEffect(self.isHovered ? 1.08 : 0.94)
            
            UserAvatarCircleView(profile: self.manager.activeProfile, size: 24)
                .scaleEffect(self.isHovered ? 1.07 : 1.0)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: self.isHovered)
        .onHover { self.isHovered = $0 }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
    }
}


/// Top-right toolbar avatar control that opens the flagship personal command hub panel
/// with screen-edge-safe anchoring (never clips off the right screen edge).
@MainActor final class UserAvatarToolbarButtonView: NSView {
    
    private final class UserProfileFloatingPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    
    private let hostingView: NSHostingView<UserAvatarToolbarBadgeLabel>
    private let clickButton = NSButton()
    private var panel: UserProfileFloatingPanel?
    private var panelHosting: NSHostingController<AnyView>?
    private var profileObserver: (any NSObjectProtocol)?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyMonitor: Any?
    private var windowCloseObserver: (any NSObjectProtocol)?
    private var panelSizeObserver: NSObjectProtocol?
    
    
    override init(frame frameRect: NSRect) {
        
        self.hostingView = NSHostingView(rootView: UserAvatarToolbarBadgeLabel())
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        
        self.translatesAutoresizingMaskIntoConstraints = false
        
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.hostingView)
        
        self.clickButton.translatesAutoresizingMaskIntoConstraints = false
        self.clickButton.title = ""
        self.clickButton.isBordered = false
        self.clickButton.isTransparent = true
        self.clickButton.focusRingType = .none
        self.clickButton.target = self
        self.clickButton.action = #selector(self.togglePopover(_:))
        self.addSubview(self.clickButton)
        
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: 28),
            self.heightAnchor.constraint(equalToConstant: 28),
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
        self.profileObserver = NotificationCenter.default.addObserver(
            forName: UserProfileManager.activeProfileDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTooltip()
            }
        }
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        
        if let profileObserver = self.profileObserver {
            NotificationCenter.default.removeObserver(profileObserver)
        }
        self.closeFloatingPanel()
    }
    
    
    override var intrinsicContentSize: NSSize {
        
        NSSize(width: 28, height: 28)
    }
    
    
    /// Computes the screen-clamped floating frame right-aligned beneath `buttonScreenRect` so it never clips off the edge.
    static func anchoredPanelFrame(
        buttonScreenRect: NSRect,
        panelSize: NSSize,
        visibleScreenFrame: NSRect
    ) -> NSRect {
        let margin: CGFloat = 14
        let minX = visibleScreenFrame.minX + margin
        let maxX = max(minX, visibleScreenFrame.maxX - panelSize.width - margin)
        let preferredX = buttonScreenRect.maxX - panelSize.width + 6
        let originX = max(minX, min(preferredX, maxX))
        
        let minY = visibleScreenFrame.minY + margin
        let maxY = max(minY, visibleScreenFrame.maxY - panelSize.height - margin)
        let preferredY = buttonScreenRect.minY - panelSize.height - 8
        let originY = max(minY, min(preferredY, maxY))
        
        return NSRect(x: originX, y: originY, width: panelSize.width, height: panelSize.height)
    }
    
    
    private func refreshTooltip() {
        
        let name = UserProfileManager.shared.activeProfile.displayName
        self.toolTip = name
        self.clickButton.toolTip = name
    }
    
    
    @objc private func togglePopover(_ sender: Any?) {
        
        if let panel = self.panel, panel.isVisible {
            self.closeFloatingPanel()
            return
        }
        self.showFloatingPanel()
    }
    
    
    private func showFloatingPanel() {
        
        guard let hostWindow = self.window else { return }
        self.closeFloatingPanel()
        
        let rootView = UserProfilePopoverView(
            hostWindow: hostWindow,
            closePopover: { [weak self] in
                self?.closeFloatingPanel()
            }
        )
        
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 16
        vfx.layer?.masksToBounds = true
        vfx.layer?.borderWidth = 0.75
        vfx.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        
        let contentView = AnyView(
            rootView
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] newHeight in
                    Task { @MainActor in
                        self?.repositionFloatingPanel(preferredHeight: newHeight)
                    }
                }
        )
        let hosting = NSHostingController(rootView: contentView)
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
        hosting.view.layoutSubtreeIfNeeded()
        
        let fitted = hosting.view.fittingSize
        let size = NSSize(width: 348, height: max(260, fitted.height))
        let btnInWindow = self.convert(self.bounds, to: nil)
        let btnScreen = hostWindow.convertToScreen(btnInWindow)
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = Self.anchoredPanelFrame(buttonScreenRect: btnScreen, panelSize: size, visibleScreenFrame: screenFrame)
        
        let panel = UserProfileFloatingPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = vfx
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
    
    
    private func repositionFloatingPanel(preferredHeight: CGFloat) {
        
        guard let panel = self.panel, let hostWindow = self.window, preferredHeight > 120 else { return }
        let clampedH = min(640, max(240, preferredHeight))
        guard abs(panel.frame.height - clampedH) > 1.5 else { return }
        let btnInWindow = self.convert(self.bounds, to: nil)
        let btnScreen = hostWindow.convertToScreen(btnInWindow)
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let updated = Self.anchoredPanelFrame(
            buttonScreenRect: btnScreen,
            panelSize: NSSize(width: 348, height: clampedH),
            visibleScreenFrame: screenFrame
        )
        panel.setFrame(updated, display: true)
    }
    
    
    private func installMonitors(hostWindow: NSWindow, panel: UserProfileFloatingPanel) {
        
        self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window === panel {
                return event
            }
            if event.window === self.window {
                let locInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(locInSelf) {
                    return event
                }
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
            Task { @MainActor in
                self?.closeFloatingPanel()
            }
        }
    }
    
    
    private func closeFloatingPanel() {
        
        if let m = self.localMouseMonitor { NSEvent.removeMonitor(m); self.localMouseMonitor = nil }
        if let m = self.globalMouseMonitor { NSEvent.removeMonitor(m); self.globalMouseMonitor = nil }
        if let m = self.keyMonitor { NSEvent.removeMonitor(m); self.keyMonitor = nil }
        if let o = self.windowCloseObserver { NotificationCenter.default.removeObserver(o); self.windowCloseObserver = nil }
        
        if let panel = self.panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
        }
        self.panelHosting = nil
    }
}


// MARK: - Soft Perceptual Avatar Aurora Extractor

@MainActor
enum AvatarColorExtractor {
    
    struct Palette: Equatable {
        let primary: Color
        let secondary: Color
        let tertiary: Color
    }
    
    private static var cache: [String: Palette] = [:]
    
    
    static func extractPalette(for profile: UserProfile, image: NSImage?) -> Palette {
        
        let key = "\(profile.id)|\(profile.avatarData?.count ?? 0)|\(profile.avatarColorHex)"
        if let cached = self.cache[key] {
            return cached
        }
        
        let fallbackBase = NSColor(Color(hexString: profile.avatarColorHex)).usingColorSpace(.sRGB) ?? .systemBlue
        let fallback = Palette(
            primary: self.softAtmosphericColor(from: fallbackBase, hueOffset: 0, saturationScale: 0.9),
            secondary: self.softAtmosphericColor(from: fallbackBase, hueOffset: 0.072, saturationScale: 0.85),
            tertiary: self.softAtmosphericColor(from: fallbackBase, hueOffset: 0.161, saturationScale: 0.80)
        )
        
        guard let image,
              let bitmap = Self.downsample24x24(image)
        else {
            self.cache[key] = fallback
            return fallback
        }
        
        struct Bucket {
            var rSum: Double = 0
            var gSum: Double = 0
            var bSum: Double = 0
            var weightSum: Double = 0
        }
        
        var buckets = Array(repeating: Bucket(), count: 12)
        let center = 11.5
        let twoSigmaSq = 2.0 * 7.5 * 7.5
        
        for y in 0..<24 {
            for x in 0..<24 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent < 0.25 { continue }
                
                var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
                
                // Gaussian center-weighting avoids corner backgrounds overpowering the portrait mood
                let dx = Double(x) - center
                let dy = Double(y) - center
                let gaussian = exp(-(dx * dx + dy * dy) / twoSigmaSq)
                let lumaWeight: Double = (bri < 0.10 || bri > 0.94) ? 0.22 : 1.0
                let chromaWeight = (0.14 + Double(sat) * 1.15) * lumaWeight * gaussian
                let idx = min(11, max(0, Int(hue * 12.0)))
                
                buckets[idx].rSum += Double(color.redComponent) * chromaWeight
                buckets[idx].gSum += Double(color.greenComponent) * chromaWeight
                buckets[idx].bSum += Double(color.blueComponent) * chromaWeight
                buckets[idx].weightSum += chromaWeight
            }
        }
        
        let ranked = buckets.enumerated()
            .filter { $0.element.weightSum > 0 }
            .sorted { $0.element.weightSum > $1.element.weightSum }
        
        guard let top = ranked.first else {
            self.cache[key] = fallback
            return fallback
        }
        
        let primaryNS = NSColor(
            srgbRed: top.element.rSum / top.element.weightSum,
            green: top.element.gSum / top.element.weightSum,
            blue: top.element.bSum / top.element.weightSum,
            alpha: 1
        )
        let primary = Self.softAtmosphericColor(from: primaryNS, hueOffset: 0, saturationScale: 0.92)
        
        let second = ranked.first { candidate in
            let dist = min(abs(candidate.offset - top.offset), 12 - abs(candidate.offset - top.offset))
            return dist >= 2
        }
        let secondaryNS: NSColor
        let secondary: Color
        if let second {
            secondaryNS = NSColor(
                srgbRed: second.element.rSum / second.element.weightSum,
                green: second.element.gSum / second.element.weightSum,
                blue: second.element.bSum / second.element.weightSum,
                alpha: 1
            )
            secondary = Self.softAtmosphericColor(from: secondaryNS, hueOffset: 0, saturationScale: 0.88)
        } else {
            secondaryNS = primaryNS
            secondary = Self.softAtmosphericColor(from: primaryNS, hueOffset: 0.072, saturationScale: 0.85)
        }
        
        let tertiary = Self.softAtmosphericColor(from: secondaryNS, hueOffset: 0.095, saturationScale: 0.80)
        
        let palette = Palette(primary: primary, secondary: secondary, tertiary: tertiary)
        self.cache[key] = palette
        return palette
    }
    
    
    /// Clamps extracted colors into silky atmospheric aurora tones (`S: 0.24...0.48`, `B: 0.62...0.84`)
    /// so neon avatars stay tasteful and dark avatars never turn muddy brown.
    private static func softAtmosphericColor(
        from color: NSColor,
        hueOffset: CGFloat,
        saturationScale: CGFloat
    ) -> Color {
        
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgb = color.usingColorSpace(.sRGB) ?? color
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        
        let resolvedHue = (h + hueOffset).truncatingRemainder(dividingBy: 1.0)
        let resolvedSat = min(0.48, max(0.24, s * saturationScale))
        let resolvedBri = min(0.84, max(0.62, b * 0.90 + 0.14))
        
        let hsbColor = NSColor(hue: resolvedHue < 0 ? resolvedHue + 1 : resolvedHue,
                               saturation: resolvedSat,
                               brightness: resolvedBri,
                               alpha: 1.0).usingColorSpace(.sRGB) ?? srgb
        return Color(nsColor: hsbColor)
    }
    
    
    private static func downsample24x24(_ image: NSImage) -> NSBitmapImageRep? {
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 24,
            pixelsHigh: 24,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        
        rep.size = NSSize(width: 24, height: 24)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 24, height: 24), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}


private enum QuickTodoDDL: String, CaseIterable, Identifiable {
    
    case none = "无期限"
    case min15 = "15分"
    case hour1 = "1小时"
    case tonight = "今晚"
    
    var id: String { self.rawValue }
}


/// Flagship Personal Command Hub popover featuring 360° surrounding tech danmaku,
/// soft multi-cloud aurora extraction, mascot-infused capsule todos, and direct studio navigation.
struct UserProfilePopoverView: View {
    
    var hostWindow: NSWindow?
    var closePopover: () -> Void = {}
    
    @Environment(\.colorScheme) private var colorScheme
    
    @AppStorage("cot.pinnedTodo.mascotKind") private var mascotKindRaw = TodoMascotKind.autoMix.rawValue
    @State private var manager = UserProfileManager.shared
    @State private var analytics = AnalyticsManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var editingName = ""
    @State private var isEditingName = false
    @State private var didJustSaveName = false
    @State private var isAvatarHovered = false
    @State private var isAvatarDropTargeted = false
    @State private var isNameHovered = false
    @State private var isDashboardHovered = false
    @State private var isSettingsHovered = false
    @State private var greeting = Self.nextRandomGreeting()
    @State private var isCreateButtonHovered = false
    @State private var isCreatingTodo = false
    @State private var todoTitle = ""
    @State private var todoDDL: QuickTodoDDL = .none
    @State private var hoveredTodoID: String?
    @State private var completingTodoIDs: Set<String> = []
    
    // Avatar tactile & 360° danmaku shockwave state
    @State private var avatarTapCount = 0
    @State private var avatarSquish = false
    @State private var avatarSpinAngle: Double = 0
    @State private var avatarPulseScale: CGFloat = 0.85
    @State private var avatarPulseOpacity: Double = 0
    @State private var shockwaveTimestamp: Date = .distantPast
    @State private var nameWiggleAngle: Double = 0
    @State private var selectedTag: UserPersonalityTag?
    @State private var isDanmakuEnabled: Bool = CotLocalDatabase.shared.bool(
        forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled,
        default: true
    )
    
    @FocusState private var isNameFieldFocused: Bool
    @FocusState private var isTodoFieldFocused: Bool
    
    private var mascotMode: TodoMascotKind {
        TodoMascotKind(rawValue: self.mascotKindRaw) ?? .autoMix
    }
    
    
    var body: some View {
        let active = self.manager.activeProfile
        let avatarImage = self.manager.avatarImage(for: active)
        let ambient = AvatarColorExtractor.extractPalette(for: active, image: avatarImage)
        let recent5 = self.analytics.dailySeries(days: 5).map { Double($0.typedChars) }
        let studioTokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let tags = UserPersonalityAnalyzer.deduplicatedTags(
            self.analytics.personalityProfile?.tags ?? [],
            maxCount: 8
        )
        let pinned = self.analytics.pinnedTodos
        
        VStack(spacing: 10) {
            // 1. Flagship Hero Card with Soft Aurora Clouds + 360° Surrounding Danmaku Stage (Zero Refresh Button, Zero Right Label)
            VStack(spacing: 6) {
                // Header micro-row (Greeting left, Danmaku toggle right — seamless auto-updates)
                HStack(spacing: 6) {
                    Text(self.greeting)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .onTapGesture {
                            withAnimation(Self.quick) {
                                self.greeting = Self.nextRandomGreeting()
                            }
                        }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(Self.spring) {
                            self.isDanmakuEnabled.toggle()
                            CotLocalDatabase.shared.set(
                                self.isDanmakuEnabled,
                                forKey: CotLocalDatabase.ConfigKey.aiPersonalityAutoEnabled
                            )
                            if !self.isDanmakuEnabled {
                                self.selectedTag = nil
                            } else {
                                Task {
                                    await self.analytics.refreshPersonalityProfile(force: false)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: self.isDanmakuEnabled ? "sparkles" : "sparkles.slash")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(AppLanguage.text("环绕弹幕", en: "Orbit Tags"))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(self.isDanmakuEnabled ? studioTokens.accentText : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            self.isDanmakuEnabled
                                ? studioTokens.positivePillBg
                                : self.surfaceFill,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                // 360° Surrounding Danmaku Stage + Centered Interactive Avatar
                AvatarSurroundingDanmakuStage(
                    tags: self.isDanmakuEnabled ? tags : [],
                    selectedTagID: self.selectedTag?.id,
                    accent: studioTokens.accent,
                    secondaryAccent: ambient.secondary,
                    shockwaveTimestamp: self.shockwaveTimestamp,
                    onTapTag: { tapped in
                        withAnimation(Self.spring) {
                            self.selectedTag = (self.selectedTag?.id == tapped.id) ? nil : tapped
                        }
                    }
                ) {
                    Button {
                        self.triggerAvatarFunTap()
                    } label: {
                        ZStack(alignment: .bottom) {
                            Circle()
                                .strokeBorder(ambient.primary.opacity(self.avatarPulseOpacity), lineWidth: 2)
                                .frame(width: 78, height: 78)
                                .scaleEffect(self.avatarPulseScale)
                            
                            UserAvatarCircleView(profile: active, size: 68, customImage: avatarImage)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                        .frame(width: 68, height: 68)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            Color.white.opacity(self.isAvatarDropTargeted ? 0.90 : (self.isAvatarHovered ? 0.55 : 0.28)),
                                            lineWidth: self.isAvatarDropTargeted ? 2.5 : 1.5
                                        )
                                )
                                .scaleEffect(self.avatarSquish ? 0.85 : (self.isAvatarDropTargeted ? 1.08 : (self.isAvatarHovered ? 1.04 : 1.0)))
                                .rotationEffect(.degrees(self.avatarSpinAngle))
                                .shadow(
                                    color: ambient.primary.opacity(0.28),
                                    radius: 14,
                                    y: 4
                                )
                            
                            if self.isAvatarDropTargeted {
                                Text(AppLanguage.text("松手换头像", en: "Drop Avatar"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2.5)
                                    .background(Color.black.opacity(0.65), in: Capsule())
                                    .offset(y: 6)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { hovering in
                        withAnimation(Self.spring) { self.isAvatarHovered = hovering }
                    }
                    .onDrop(of: [.image, .fileURL], isTargeted: self.$isAvatarDropTargeted) { providers in
                        self.handleAvatarDrop(providers: providers)
                    }
                    .contextMenu {
                        Button(AppLanguage.text("更换头像", en: "Change Avatar")) { self.pickAvatarForActiveUser() }
                        if avatarImage != nil {
                            Button(AppLanguage.text("恢复默认头像", en: "Reset Default Avatar")) {
                                self.manager.updateProfile(id: active.id, avatarData: .some(nil))
                            }
                        }
                        Divider()
                        Button(AppLanguage.text("修改昵称", en: "Edit Name")) {
                            withAnimation(Self.spring) {
                                self.editingName = active.displayName
                                self.isEditingName = true
                            }
                        }
                    }
                }
                
                // Centered Identity Footer (Pure Nickname, Zero Right Label)
                if self.isEditingName {
                    HStack(spacing: 6) {
                        TextField(AppLanguage.text("昵称", en: "Name"), text: self.$editingName)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14, weight: .medium))
                            .focused(self.$isNameFieldFocused)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(maxWidth: 168)
                            .onSubmit { self.commitNameEdit() }
                            .onExitCommand { self.cancelNameEdit() }
                            .onAppear {
                                DispatchQueue.main.async { self.isNameFieldFocused = true }
                            }
                            .onChange(of: self.isNameFieldFocused) { _, focused in
                                if !focused && self.isEditingName {
                                    self.commitNameEdit()
                                }
                            }
                        
                        Button(AppLanguage.text("完成", en: "Done")) {
                            self.commitNameEdit()
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(studioTokens.onAccentInk)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(studioTokens.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    ZStack {
                        Button {
                            self.triggerNameFunTap()
                        } label: {
                            HStack(spacing: 5) {
                                Text(active.displayName)
                                    .font(.system(size: 15.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .rotationEffect(.degrees(self.nameWiggleAngle))
                                
                                if self.didJustSaveName {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(studioTokens.accentText)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(self.isNameHovered ? self.surfaceFill : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .contextMenu {
                            Button(AppLanguage.text("修改昵称", en: "Edit Name")) {
                                withAnimation(Self.spring) {
                                    self.editingName = active.displayName
                                    self.isEditingName = true
                                }
                            }
                            Button(AppLanguage.text("更换头像", en: "Change Avatar")) { self.pickAvatarForActiveUser() }
                        }
                        .overlay(alignment: .trailing) {
                            if self.isNameHovered {
                                Button {
                                    withAnimation(Self.spring) {
                                        self.editingName = active.displayName
                                        self.isEditingName = true
                                    }
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                        .background(self.surfaceFill, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                                .offset(x: 24)
                                .transition(.opacity)
                            }
                        }
                    }
                    .onHover { hovering in
                        withAnimation(Self.quick) { self.isNameHovered = hovering }
                    }
                }
                
                // Expandable AI Insight Bubble when tapping any orbiting danmaku pill
                if self.isDanmakuEnabled, let tag = self.selectedTag {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.toneColor(for: tag.tone))
                            .frame(width: 6, height: 6)
                        Text(tag.explanation.isEmpty ? (self.analytics.personalityProfile?.conceptSummary ?? tag.label) : tag.explanation)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture {
                        withAnimation(Self.quick) { self.selectedTag = nil }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 11)
            .padding(.bottom, 12)
            .padding(.horizontal, 12)
            .background {
                SoftAvatarAuroraBackdrop(
                    palette: ambient,
                    surface: self.cardSurface,
                    isDark: self.colorScheme == .dark
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: self.colorScheme == .dark
                                ? [Color.white.opacity(0.14), Color.white.opacity(0.03)]
                                : [Color.white.opacity(0.85), Color.black.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            
            // 2. 2-Tile Primary Command Dock (数据看板 + 个人设置 / 通行证)
            HStack(spacing: 8) {
                Button {
                    let targetWindow = self.hostWindow
                    self.closePopover()
                    AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: targetWindow)
                } label: {
                    HStack(spacing: 9) {
                        MiniPopoverSparkMatrix(values: recent5, accent: studioTokens.accentText, emptyColor: self.surfaceFill)
                            .frame(width: 26, height: 18)
                            .padding(5)
                            .background(studioTokens.positivePillBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        Text(AppLanguage.text("数据看板", en: "Dashboard"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Spacer(minLength: 2)
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.isDashboardHovered ? studioTokens.accentText : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(
                        self.isDashboardHovered ? self.surfaceFill : self.cardSurface,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(self.softCardStroke(active: self.isDashboardHovered, accent: studioTokens.accentText), lineWidth: 0.75)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(Self.spring) { self.isDashboardHovered = hovering }
                }
                
                HStack(spacing: 4) {
                    Button {
                        self.closePopover()
                        (NSApp.delegate as? AppDelegate)?.showSettingsItem(.general)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(AppLanguage.text("个人设置", en: "Settings"))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    
                    Button {
                        self.closePopover()
                        (NSApp.delegate as? AppDelegate)?.showSettingsItem(.pass)
                    } label: {
                        Image(systemName: "lanyardcard.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(studioTokens.accentText)
                            .frame(width: 26, height: 26)
                            .background(studioTokens.positivePillBg, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("打开手稿铭牌通行证", en: "Open Atelier Pass"))
                    .padding(.trailing, 7)
                }
                .frame(height: 44)
                .frame(maxWidth: 148)
                .background(
                    self.isSettingsHovered ? self.surfaceFill : self.cardSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(self.softCardStroke(active: self.isSettingsHovered, accent: studioTokens.accentText), lineWidth: 0.75)
                )
                .onHover { hovering in
                    withAnimation(Self.spring) { self.isSettingsHovered = hovering }
                }
            }
            
            // 3. Compact Horizontal Account Switcher Strip (if multiple local users exist)
            if self.manager.profiles.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(self.manager.profiles) { profile in
                            self.profileSwitchPill(profile, isActive: profile.id == active.id, accent: studioTokens.accentText)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            
            // 4. Layered Mascot Capsule Pinned Todos + Creator
            if !pinned.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(pinned.prefix(3).enumerated()), id: \.element.id) { idx, item in
                        self.popoverTodoCapsule(item: item, index: idx, accent: studioTokens.accentText)
                    }
                }
            }
            
            if self.isCreatingTodo {
                self.createTodoCard(tokens: studioTokens)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            } else {
                Button {
                    withAnimation(Self.spring) {
                        self.isCreatingTodo = true
                        DispatchQueue.main.async {
                            self.isTodoFieldFocused = true
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        PinnedTodoMascotAvatar(
                            kind: self.mascotMode.resolvedKind(for: "new-todo-btn"),
                            isHovered: self.isCreateButtonHovered,
                            size: 16
                        )
                        Text(AppLanguage.text("新建胶囊置顶", en: "New Capsule Todo"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(self.isCreateButtonHovered ? studioTokens.accentText : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        Capsule()
                            .fill(self.isCreateButtonHovered ? studioTokens.positivePillBg : self.cardSurface)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                self.isCreateButtonHovered ? Color.clear : self.softCardStroke(active: false, accent: studioTokens.accentText),
                                lineWidth: 0.65
                            )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(Self.quick) {
                        self.isCreateButtonHovered = hovering
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 348)
        .onAppear {
            self.editingName = self.manager.activeProfile.displayName
            self.greeting = Self.nextRandomGreeting()
            self.mascotKindRaw = TodoMascotKind.persisted.rawValue
            if self.isDanmakuEnabled {
                Task {
                    await self.analytics.refreshPersonalityProfile(force: false)
                }
            }
        }
        .onChange(of: self.manager.activeProfile.id) { _, _ in
            self.editingName = self.manager.activeProfile.displayName
            self.isEditingName = false
            self.selectedTag = nil
        }
    }
    
    
    @ViewBuilder
    private func popoverTodoCapsule(item: UserReminder, index: Int, accent: Color) -> some View {
        let isHovered = (self.hoveredTodoID == item.id)
        let isCompleting = self.completingTodoIDs.contains(item.id)
        let mascot = self.mascotMode.resolvedKind(for: item.id)
        
        HStack(alignment: .center, spacing: 6) {
            // Content-hugging capsule with generous button hit targets
            HStack(alignment: .center, spacing: 5) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(self.colorScheme == .dark ? 0.14 : 0.08))
                        .frame(width: 26, height: 26)
                    PinnedTodoMascotAvatar(
                        kind: mascot,
                        isHovered: isHovered,
                        isCompleting: isCompleting,
                        size: 20,
                        phaseSeed: Double(index) * 1.13
                    )
                }
                
                Text(item.title)
                    .font(.system(size: 12.2, weight: .medium))
                    .foregroundStyle(isCompleting ? .secondary : .primary)
                    .strikethrough(isCompleting)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 164, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                
                if item.hasDeadline {
                    Text(PinnedTodoUrgency.compactBadgeText(item.dueDate.timeIntervalSinceNow))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accent.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                }
                
                if !isCompleting {
                    Button {
                        self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                    } label: {
                        Text("+15m")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(self.surfaceFill, in: Capsule())
                            .frame(minWidth: 34, minHeight: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("延后 15 分钟", en: "Snooze 15m"))
                    
                    Button {
                        self.analytics.unpinReminder(id: item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(self.surfaceFill, in: Circle())
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("取消置顶", en: "Unpin"))
                }
                
                Button {
                    self.completePopoverTodo(item)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isCompleting ? Color(red: 0.20, green: 0.72, blue: 0.45) : accent.opacity(0.16))
                            .frame(width: 24, height: 24)
                        Image(systemName: isCompleting ? "checkmark" : "circle.fill")
                            .font(.system(size: isCompleting ? 10.5 : 5, weight: .bold))
                            .foregroundStyle(isCompleting ? .white : accent)
                    }
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("标记已完成", en: "Complete"))
            }
            .padding(.horizontal, 6)
            .frame(height: 36)
            .fixedSize()
            .background(
                Capsule()
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.90))
                    .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0.28 : 0.06), radius: 8, y: 3)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: self.colorScheme == .dark
                                ? [Color.white.opacity(0.15), Color.clear]
                                : [Color.white.opacity(0.9), Color.black.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.65
                    )
            )
            .onHover { hovering in
                withAnimation(Self.quick) {
                    self.hoveredTodoID = hovering ? item.id : (self.hoveredTodoID == item.id ? nil : self.hoveredTodoID)
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    
    @ViewBuilder
    private func profileSwitchPill(_ profile: UserProfile, isActive: Bool, accent: Color) -> some View {
        Button {
            guard !isActive else { return }
            withAnimation(Self.spring) {
                self.manager.switchToProfile(id: profile.id)
            }
        } label: {
            HStack(spacing: 6) {
                UserAvatarCircleView(profile: profile, size: 18)
                Text(profile.displayName)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(isActive ? self.surfaceFill : self.cardSurface)
            )
            .overlay(
                Capsule()
                    .strokeBorder(self.softCardStroke(active: isActive, accent: accent), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .contextMenu {
            if self.manager.profiles.count > 1 && !isActive {
                Button(AppLanguage.text("删除账户「\(profile.displayName)」", en: "Delete \(profile.displayName)"), role: .destructive) {
                    withAnimation(Self.spring) {
                        _ = self.manager.deleteProfile(id: profile.id)
                    }
                }
            }
        }
    }
    
    
    private func createTodoCard(tokens: StudioColorTokens) -> some View {
        
        VStack(spacing: 9) {
            TextField(AppLanguage.text("输入待办，回车置顶为轻胶囊", en: "Enter todo, press Return"), text: self.$todoTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(self.$isTodoFieldFocused)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(self.surfaceFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit {
                    self.submitTodo()
                }
            
            HStack(spacing: 5) {
                ForEach(QuickTodoDDL.allCases) { option in
                    let isSelected = (self.todoDDL == option)
                    Button {
                        withAnimation(Self.quick) {
                            self.todoDDL = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? tokens.onAccentInk : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(
                                Capsule().fill(isSelected ? tokens.accent : self.surfaceFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
            }
            
            HStack(spacing: 8) {
                Button {
                    withAnimation(Self.spring) {
                        self.resetTodoDraft()
                    }
                } label: {
                    Text(AppLanguage.text("取消", en: "Cancel"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(self.surfaceFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                
                Button {
                    self.submitTodo()
                } label: {
                    Text(AppLanguage.text("置顶", en: "Pin"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.onAccentInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(tokens.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
            }
        }
        .padding(10)
        .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(self.softCardStroke(active: false, accent: tokens.accentText), lineWidth: 0.75)
        )
    }
    
    
    // MARK: Visual Tokens & Helpers
    
    private static let quick = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.14)
    private static let spring = Animation.spring(response: 0.30, dampingFraction: 0.80)
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.025)
    }
    
    private var surfaceFill: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.045)
    }
    
    private func softCardStroke(active: Bool, accent: Color) -> Color {
        if active {
            return accent.opacity(0.32)
        }
        return self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055)
    }
    
    
    static func toneColor(for tone: PersonalityTagTone) -> Color {
        switch tone {
            case .warm: Color(red: 0.92, green: 0.52, blue: 0.32)
            case .sharp: Color(red: 0.22, green: 0.72, blue: 0.92)
            case .playful: Color(red: 0.80, green: 0.44, blue: 0.88)
            case .calm: Color(red: 0.26, green: 0.76, blue: 0.58)
        }
    }
    
    
    // MARK: Actions
    
    private static var lastGreetingIndex: Int?
    
    private static let randomGreetings: [String] = [
        "灵感已上线",
        "键盘热好了",
        "先写第一行",
        "草稿不怕丑",
        "敲字胜发呆",
        "状态正加载",
        "大脑营业中",
        "别卡在标题",
        "手感在升温",
        "思路已就位",
        "摸会鱼再写",
        "写完这句歇",
    ]
    
    private static func nextRandomGreeting() -> String {
        
        var candidates = Array(Self.randomGreetings.indices)
        if let last = Self.lastGreetingIndex, candidates.count > 1 {
            candidates.removeAll { $0 == last }
        }
        let picked = candidates.randomElement() ?? 0
        Self.lastGreetingIndex = picked
        return Self.randomGreetings[picked]
    }
    
    
    private func commitNameEdit() {
        
        let trimmed = self.editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = !trimmed.isEmpty && trimmed != self.manager.activeProfile.displayName
        if changed {
            self.manager.updateProfile(id: self.manager.activeProfile.id, displayName: trimmed)
        } else {
            self.editingName = self.manager.activeProfile.displayName
        }
        withAnimation(Self.spring) {
            self.isEditingName = false
            if changed {
                self.didJustSaveName = true
            }
        }
        if changed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(Self.quick) {
                    self.didJustSaveName = false
                }
            }
        }
    }
    
    
    private func cancelNameEdit() {
        
        self.editingName = self.manager.activeProfile.displayName
        withAnimation(Self.spring) {
            self.isEditingName = false
        }
    }
    
    
    private func triggerAvatarFunTap() {
        
        self.avatarTapCount += 1
        self.shockwaveTimestamp = Date()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(Self.quick) {
            self.greeting = Self.nextRandomGreeting()
        }
        withAnimation(.spring(response: 0.20, dampingFraction: 0.42)) {
            self.avatarSquish = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.56)) {
                self.avatarSquish = false
            }
        }
        if self.avatarTapCount % 3 == 0 {
            withAnimation(.spring(response: 0.50, dampingFraction: 0.72)) {
                self.avatarSpinAngle += 360
            }
        }
        self.avatarPulseScale = 0.88
        self.avatarPulseOpacity = 0.75
        withAnimation(.easeOut(duration: 0.44)) {
            self.avatarPulseScale = 1.46
            self.avatarPulseOpacity = 0
        }
    }
    
    
    private func triggerNameFunTap() {
        
        withAnimation(Self.quick) {
            self.greeting = Self.nextRandomGreeting()
        }
        withAnimation(.spring(response: 0.16, dampingFraction: 0.35)) {
            self.nameWiggleAngle = -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.48)) {
                self.nameWiggleAngle = 0
            }
        }
    }
    
    
    private func completePopoverTodo(_ item: UserReminder) {
        guard !self.completingTodoIDs.contains(item.id) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            _ = self.completingTodoIDs.insert(item.id)
        }
        let targetID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeOut(duration: 0.16)) {
                self.analytics.toggleReminderCompleted(id: targetID)
                self.completingTodoIDs.remove(targetID)
            }
        }
    }
    
    
    private func submitTodo() {
        
        let trimmed = self.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let deadline: Date? = switch self.todoDDL {
            case .none: nil
            case .min15: now.addingTimeInterval(15 * 60)
            case .hour1: now.addingTimeInterval(3600)
            case .tonight:
                Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now).flatMap {
                    $0.timeIntervalSince(now) > 1800 ? $0 : now.addingTimeInterval(3 * 3600)
                } ?? now.addingTimeInterval(3 * 3600)
        }
        withAnimation(Self.spring) {
            self.analytics.addPinnedTodo(title: trimmed, deadline: deadline)
            self.resetTodoDraft()
        }
    }
    
    
    private func resetTodoDraft() {
        
        self.isCreatingTodo = false
        self.todoTitle = ""
        self.todoDDL = .none
    }
    
    
    private func pickAvatarForActiveUser() {
        
        self.chooseAvatarData { data in
            self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(data))
        }
    }
    
    
    private func handleAvatarDrop(providers: [NSItemProvider]) -> Bool {
        
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
                        guard let image = NSImage(contentsOf: url),
                              let png = UserProfileManager.processedAvatarPNGData(from: image)
                        else { return }
                        self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(png))
                    }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in
                        guard let png = UserProfileManager.processedAvatarPNGData(from: image) else { return }
                        self.manager.updateProfile(id: self.manager.activeProfile.id, avatarData: .some(png))
                    }
                }
                return true
            }
        }
        return false
    }
    
    
    private func chooseAvatarData(_ completion: @escaping @MainActor (Data) -> Void) {
        
        let panel = NSOpenPanel()
        panel.title = AppLanguage.text("选择头像图片", en: "Choose Avatar Image")
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url),
                  let data = UserProfileManager.processedAvatarPNGData(from: image)
            else { return }
            Task { @MainActor in
                completion(data)
            }
        }
    }
}


// MARK: - Soft Multi-Cloud Aurora Backdrop (Unblurred Solid Base + Clipped Blurred Clouds)

private struct SoftAvatarAuroraBackdrop: View {
    
    let palette: AvatarColorExtractor.Palette
    let surface: Color
    let isDark: Bool
    
    
    var body: some View {
        let baseAlpha = self.isDark ? 0.24 : 0.16
        let midAlpha = self.isDark ? 0.11 : 0.08
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        
        ZStack {
            shape.fill(self.surface)
            
            ZStack {
                RadialGradient(
                    stops: [
                        .init(color: self.palette.primary.opacity(baseAlpha), location: 0.0),
                        .init(color: self.palette.primary.opacity(midAlpha), location: 0.45),
                        .init(color: .clear, location: 1.0),
                    ],
                    center: .topLeading,
                    startRadius: 6,
                    endRadius: 210
                )
                
                RadialGradient(
                    stops: [
                        .init(color: self.palette.secondary.opacity(baseAlpha * 0.9), location: 0.0),
                        .init(color: self.palette.secondary.opacity(midAlpha * 0.85), location: 0.45),
                        .init(color: .clear, location: 1.0),
                    ],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 200
                )
                
                RadialGradient(
                    stops: [
                        .init(color: self.palette.tertiary.opacity(baseAlpha * 0.72), location: 0.0),
                        .init(color: self.palette.tertiary.opacity(midAlpha * 0.65), location: 0.48),
                        .init(color: .clear, location: 1.0),
                    ],
                    center: .bottom,
                    startRadius: 6,
                    endRadius: 180
                )
            }
            .blur(radius: 28)
            .clipShape(shape)
        }
    }
}


// MARK: - 360° Tech + Playful Surrounding Danmaku Stage (Deduplicated, Unclipped, Calm Pacing)

private struct AvatarSurroundingDanmakuStage<AvatarContent: View>: View {
    
    let tags: [UserPersonalityTag]
    let selectedTagID: String?
    let accent: Color
    let secondaryAccent: Color
    let shockwaveTimestamp: Date
    let onTapTag: (UserPersonalityTag) -> Void
    @ViewBuilder let avatarContent: () -> AvatarContent
    
    @State private var hoveredTagID: String?
    @State private var anchorDate = Date()
    @State private var accumulatedTime: TimeInterval = 0
    @State private var isPaused = false
    @Environment(\.colorScheme) private var colorScheme
    
    private let stageWidth: CGFloat = 304
    private let stageHeight: CGFloat = 180
    
    
    private var laneConfigs: [(yOffset: CGFloat, speed: CGFloat, dir: CGFloat, scale: CGFloat, opacity: Double, isForeground: Bool)] {
        [
            (-64, 9.2, -1, 1.00, 1.00, true),   // Top foreground arc
            (-19, 8.2, +1, 0.94, 0.92, false),  // Upper middle orbit behind portrait
            (+21, 8.8, -1, 0.94, 0.92, false),  // Lower middle orbit behind portrait
            (+64, 10.4, +1, 1.00, 1.00, true),  // Bottom foreground arc
        ]
    }
    
    
    var body: some View {
        let uniqueTags = UserPersonalityAnalyzer.deduplicatedTags(self.tags, maxCount: 8)
        let laneBuckets = self.distributeUniqueTagsAcrossLanes(uniqueTags)
        
        TimelineView(.animation(minimumInterval: nil, paused: AnimationConstants.isReducedMotionEnabled)) { context in
            let dt = self.isPaused
                ? self.accumulatedTime
                : self.accumulatedTime + max(0, context.date.timeIntervalSince(self.anchorDate))
            let shockElapsed = max(0, context.date.timeIntervalSince(self.shockwaveTimestamp))
            let shockImpulse: CGFloat = (shockElapsed < 0.55)
                ? CGFloat(sin(shockElapsed / 0.55 * .pi) * exp(-2.5 * shockElapsed) * 12.0)
                : 0
            
            ZStack {
                // 1. Tech HUD Dual Concentric Orbital Telemetry Rings
                self.orbitalRingsLayer(elapsed: dt, shockImpulse: shockImpulse)
                    .zIndex(0)
                
                // 2. Behind-Portrait Orbit Lanes (never sliced by harsh radial mask; portrait sits crisply in front!)
                ForEach([1, 2], id: \.self) { laneIdx in
                    let cfg = self.laneConfigs[laneIdx]
                    OrbitingUniqueLaneView(
                        tags: laneBuckets[laneIdx],
                        laneIndex: laneIdx,
                        elapsed: dt,
                        speed: cfg.speed,
                        direction: cfg.dir,
                        scale: cfg.scale,
                        baseOpacity: cfg.opacity,
                        yOffset: cfg.yOffset + (cfg.yOffset < 0 ? -shockImpulse * 0.7 : shockImpulse * 0.7),
                        stageWidth: self.stageWidth,
                        selectedTagID: self.selectedTagID,
                        hoveredTagID: self.$hoveredTagID,
                        accent: self.accent,
                        curvesAroundPortrait: true,
                        onTap: self.onTapTag
                    )
                    .zIndex(1)
                }
                
                // 3. Center Interactive Avatar (opaque disk sits cleanly between behind & foreground orbits)
                self.avatarContent()
                    .zIndex(2)
                
                // 4. Foreground Top & Bottom Orbit Lanes
                ForEach([0, 3], id: \.self) { laneIdx in
                    let cfg = self.laneConfigs[laneIdx]
                    OrbitingUniqueLaneView(
                        tags: laneBuckets[laneIdx],
                        laneIndex: laneIdx,
                        elapsed: dt,
                        speed: cfg.speed,
                        direction: cfg.dir,
                        scale: cfg.scale,
                        baseOpacity: cfg.opacity,
                        yOffset: cfg.yOffset + (cfg.yOffset < 0 ? -shockImpulse : shockImpulse),
                        stageWidth: self.stageWidth,
                        selectedTagID: self.selectedTagID,
                        hoveredTagID: self.$hoveredTagID,
                        accent: self.accent,
                        curvesAroundPortrait: false,
                        onTap: self.onTapTag
                    )
                    .zIndex(3)
                }
            }
            .frame(width: self.stageWidth, height: self.stageHeight)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.03),
                        .init(color: .black, location: 0.97),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .onAppear {
            self.anchorDate = Date()
        }
        .onChange(of: self.hoveredTagID) { _, key in
            let shouldPause = (key != nil)
            guard shouldPause != self.isPaused else { return }
            let now = Date()
            if shouldPause {
                self.accumulatedTime += max(0, now.timeIntervalSince(self.anchorDate))
            } else {
                self.anchorDate = now
            }
            self.isPaused = shouldPause
        }
    }
    
    
    @ViewBuilder
    private func orbitalRingsLayer(elapsed: TimeInterval, shockImpulse: CGFloat) -> some View {
        let innerAngle = Angle.degrees(elapsed * 11)
        let outerAngle = Angle.degrees(-elapsed * 7)
        
        ZStack {
            Circle()
                .stroke(
                    self.accent.opacity(self.colorScheme == .dark ? 0.30 : 0.24),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                )
                .frame(width: 98 + shockImpulse * 0.8, height: 98 + shockImpulse * 0.8)
                .rotationEffect(innerAngle)
            
            ZStack {
                Ellipse()
                    .strokeBorder(self.secondaryAccent.opacity(self.colorScheme == .dark ? 0.18 : 0.14), lineWidth: 0.9)
                    .frame(width: 146 + shockImpulse, height: 134 + shockImpulse)
                
                Circle()
                    .fill(self.accent)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: self.accent.opacity(0.8), radius: 4)
                    .offset(x: (146 + shockImpulse) * 0.5)
                
                Circle()
                    .fill(self.secondaryAccent)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(color: self.secondaryAccent.opacity(0.75), radius: 3)
                    .offset(x: -(146 + shockImpulse) * 0.5)
            }
            .rotationEffect(outerAngle)
        }
        .allowsHitTesting(false)
    }
    
    
    /// Assigns each unique tag ONCE (never duplicates across empty lanes) so zero repeat labels ever appear.
    private func distributeUniqueTagsAcrossLanes(_ uniqueTags: [UserPersonalityTag]) -> [[UserPersonalityTag]] {
        var buckets: [[UserPersonalityTag]] = [[], [], [], []]
        for (idx, tag) in uniqueTags.enumerated() {
            buckets[idx % 4].append(tag)
        }
        return buckets
    }
}


private struct OrbitingUniqueLaneView: View {
    
    let tags: [UserPersonalityTag]
    let laneIndex: Int
    let elapsed: TimeInterval
    let speed: CGFloat
    let direction: CGFloat
    let scale: CGFloat
    let baseOpacity: Double
    let yOffset: CGFloat
    let stageWidth: CGFloat
    let selectedTagID: String?
    @Binding var hoveredTagID: String?
    let accent: Color
    let curvesAroundPortrait: Bool
    let onTap: (UserPersonalityTag) -> Void
    
    @State private var measuredWidths: [String: CGFloat] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        ZStack {
            ForEach(Array(self.tags.enumerated()), id: \.element.id) { idx, tag in
                let pillW = self.measuredWidths[tag.id] ?? CGFloat(max(58, tag.label.count * 12 + 24))
                let margin: CGFloat = 24
                let activeSpan = self.stageWidth + pillW + margin * 2
                let period = max(activeSpan, CGFloat(max(1, self.tags.count)) * 185.0)
                let stagger = (CGFloat(idx) / CGFloat(max(1, self.tags.count))) * period + CGFloat(self.laneIndex) * 58.0
                let rawProgress = (CGFloat(self.elapsed) * self.speed + stagger).truncatingRemainder(dividingBy: period)
                
                // Continuous wrap from entry edge to exit edge without ever spawning a duplicate copy!
                let xPos: CGFloat = self.direction < 0
                    ? (self.stageWidth * 0.5 + pillW * 0.5 + margin) - rawProgress
                    : -(self.stageWidth * 0.5 + pillW * 0.5 + margin) + rawProgress
                
                let bobY = CGFloat(sin(self.elapsed * 1.45 + Double(idx) * 1.7 + Double(self.laneIndex))) * 2.0
                let orbitBend: CGFloat = self.curvesAroundPortrait
                    ? (self.yOffset < 0 ? -1.0 : 1.0) * max(0, 1.0 - abs(xPos) / 76.0) * 10.0
                    : 0
                
                let isThisHovered = (self.hoveredTagID == tag.id)
                let isSelected = (self.selectedTagID == tag.id)
                let toneColor = UserProfilePopoverView.toneColor(for: tag.tone)
                
                if xPos >= -(self.stageWidth * 0.5 + pillW + 8) && xPos <= (self.stageWidth * 0.5 + pillW + 8) {
                    Button {
                        self.onTap(tag)
                    } label: {
                        HStack(spacing: 4.5) {
                            Circle()
                                .fill(isSelected ? Color.white : toneColor)
                                .frame(width: 5, height: 5)
                                .shadow(color: toneColor.opacity(0.65), radius: 3)
                            
                            Text(tag.label)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.90))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .fixedSize(horizontal: true, vertical: true)
                        .background {
                            if isSelected {
                                Capsule().fill(self.accent)
                            } else {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .fill(toneColor.opacity(self.colorScheme == .dark ? 0.12 : 0.07))
                                    )
                            }
                        }
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isThisHovered || isSelected
                                        ? toneColor.opacity(0.75)
                                        : Color.primary.opacity(self.colorScheme == .dark ? 0.14 : 0.08),
                                    lineWidth: isThisHovered || isSelected ? 1.0 : 0.65
                                )
                        )
                        .scaleEffect(isThisHovered ? 1.08 : self.scale)
                        .opacity(self.baseOpacity)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { newWidth in
                            if newWidth > 10, abs((self.measuredWidths[tag.id] ?? 0) - newWidth) > 0.5 {
                                self.measuredWidths[tag.id] = newWidth
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .offset(x: xPos, y: self.yOffset + bobY + orbitBend)
                    .onHover { inside in
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.76)) {
                            if inside {
                                self.hoveredTagID = tag.id
                            } else if self.hoveredTagID == tag.id {
                                self.hoveredTagID = nil
                            }
                        }
                    }
                }
            }
        }
    }
}


private struct MiniPopoverSparkMatrix: View {
    
    let values: [Double]
    let accent: Color
    let emptyColor: Color
    
    
    var body: some View {
        
        Canvas { context, size in
            let cols = max(1, self.values.count)
            let rows = 4
            let gap: CGFloat = 1.6
            let side = max(2.0, min((size.width - gap * CGFloat(cols - 1)) / CGFloat(cols), (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)))
            let peak = max(1.0, self.values.max() ?? 1.0)
            
            for col in 0..<cols {
                let val = self.values[col]
                let active = val > 0 ? max(1, Int((val / peak * Double(rows)).rounded(.up))) : 0
                for row in 0..<rows {
                    let yIdx = rows - 1 - row
                    let rect = CGRect(
                        x: CGFloat(col) * (side + gap),
                        y: CGFloat(yIdx) * (side + gap),
                        width: side,
                        height: side
                    )
                    let color = row < active ? self.accent.opacity(0.45 + 0.55 * Double(row + 1) / Double(rows)) : self.emptyColor
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.2, style: .continuous), with: .color(color))
                }
            }
        }
    }
}
