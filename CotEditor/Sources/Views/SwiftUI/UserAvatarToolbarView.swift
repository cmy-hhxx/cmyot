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
import CoreImage
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
        let fitted = hosting.sizeThatFits(in: CGSize(width: 348, height: 520))
        let size = NSSize(width: 348, height: min(520, max(280, ceil(fitted.height))))
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
        let clampedH = min(520, max(260, ceil(preferredHeight)))
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
    private static var blurredArtworkCache: [String: NSImage] = [:]
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    
    /// Builds a cached Apple Music–style vibrance-boosted, pre-blurred ambient mesh directly from
    /// the user's real avatar artwork so the hero card inherits its organic spatial color layout.
    static func blurredAmbientArtwork(for profile: UserProfile, image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        let key = "\(profile.id)|\(profile.avatarData?.count ?? 0)"
        if let cached = self.blurredArtworkCache[key] {
            return cached
        }
        guard let smallBitmap = Self.downsample(image, side: 72),
              let cg = smallBitmap.cgImage
        else { return nil }
        
        let input = CIImage(cgImage: cg)
        var current = input
        
        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(current, forKey: kCIInputImageKey)
            colorFilter.setValue(1.42, forKey: kCIInputSaturationKey)
            colorFilter.setValue(1.06, forKey: kCIInputContrastKey)
            colorFilter.setValue(0.02, forKey: kCIInputBrightnessKey)
            if let adjusted = colorFilter.outputImage {
                current = adjusted
            }
        }
        
        if let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.setValue(current.clampedToExtent(), forKey: kCIInputImageKey)
            blurFilter.setValue(16.0, forKey: kCIInputRadiusKey)
            if let blurred = blurFilter.outputImage?.cropped(to: input.extent) {
                current = blurred
            }
        }
        
        guard let outCG = self.ciContext.createCGImage(current, from: input.extent) else { return nil }
        let rendered = NSImage(cgImage: outCG, size: NSSize(width: 72, height: 72))
        if self.blurredArtworkCache.count > 16 {
            self.blurredArtworkCache.removeAll()
        }
        self.blurredArtworkCache[key] = rendered
        return rendered
    }
    
    
    private static func downsample(_ image: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        let target = NSSize(width: side, height: side)
        rep.size = target
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    
    
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
    
    case min15 = "15分"
    case hour1 = "1小时"
    case tonight = "今晚"
    case none = "无期限"
    
    var id: String { self.rawValue }
}


// MARK: - Dedicated Toolbar Capsule Todo Region (Left of Avatar)

/// Sorts active todos prioritizing overdue and soonest-expiring items first, and always formats a time badge.
nonisolated enum ToolbarCapsuleTodoHelper {
    
    static func prioritizedTodos(_ todos: [UserReminder]) -> [UserReminder] {
        todos.sorted { lhs, rhs in
            switch (lhs.hasDeadline, rhs.hasDeadline) {
                case (true, false):
                    return true
                case (false, true):
                    return false
                case (true, true):
                    if lhs.dueDate != rhs.dueDate {
                        return lhs.dueDate < rhs.dueDate
                    }
                    return lhs.createdAt > rhs.createdAt
                case (false, false):
                    return lhs.createdAt > rhs.createdAt
            }
        }
    }
    
    
    /// Always produces a readable time badge: live countdown for deadline items, or creation `HH:mm` for timeless items.
    static func timeBadgeText(for item: UserReminder, now: Date) -> String {
        if item.hasDeadline {
            return PinnedTodoUrgency.compactBadgeText(item.dueDate.timeIntervalSince(now))
        }
        return item.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
    
    
    static func urgencyLevel(for item: UserReminder, now: Date) -> Int {
        guard item.hasDeadline else { return 0 }
        let rem = item.dueDate.timeIntervalSince(now)
        if rem <= 0 { return 4 }
        if rem <= 600 { return 3 }
        if rem <= 1800 { return 2 }
        return 1
    }
}


/// Dedicated toolbar control placed directly to the left of the user avatar.
/// Displays the soonest-expiring capsule todo with its time badge at all times; clicking expands the full list.
@MainActor final class ToolbarCapsuleTodoButtonView: NSView {
    
    private final class TodoDropdownPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }
    
    private let hostingView: NSHostingView<ToolbarCapsuleTodoTriggerView>
    private var panel: TodoDropdownPanel?
    private var panelHosting: NSHostingController<AnyView>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var keyMonitor: Any?
    private var windowCloseObserver: (any NSObjectProtocol)?
    private var widthConstraint: NSLayoutConstraint?
    
    
    override init(frame frameRect: NSRect) {
        let placeholder = ToolbarCapsuleTodoTriggerView(onToggle: {}, onWidthChange: { _ in })
        self.hostingView = NSHostingView(rootView: placeholder)
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        
        self.hostingView.rootView = ToolbarCapsuleTodoTriggerView(
            onToggle: { [weak self] in self?.toggleDropdown() },
            onWidthChange: { [weak self] width in self?.updateContainerWidth(width) }
        )
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.hostingView)
        
        let wc = self.widthAnchor.constraint(equalToConstant: 120)
        self.widthConstraint = wc
        NSLayoutConstraint.activate([
            wc,
            self.heightAnchor.constraint(equalToConstant: 28),
            self.hostingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.hostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.hostingView.topAnchor.constraint(equalTo: self.topAnchor),
            self.hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        self.closeDropdown()
    }
    
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: self.widthConstraint?.constant ?? 120, height: 28)
    }
    
    
    private func updateContainerWidth(_ width: CGFloat) {
        let clamped = max(64, min(236, ceil(width)))
        guard abs((self.widthConstraint?.constant ?? 0) - clamped) > 0.5 else { return }
        self.widthConstraint?.constant = clamped
        self.invalidateIntrinsicContentSize()
    }
    
    
    private func toggleDropdown() {
        if let panel = self.panel, panel.isVisible {
            self.closeDropdown()
            return
        }
        self.showDropdown()
    }
    
    
    private func showDropdown() {
        guard let hostWindow = self.window else { return }
        self.closeDropdown()
        
        let rootView = ToolbarCapsuleTodoDropdownView(closeDropdown: { [weak self] in
            self?.closeDropdown()
        })
        
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 14
        vfx.layer?.masksToBounds = true
        vfx.layer?.borderWidth = 0.75
        vfx.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.32).cgColor
        
        let contentView = AnyView(
            rootView
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [weak self] newHeight in
                    Task { @MainActor in
                        self?.repositionDropdown(preferredHeight: newHeight)
                    }
                }
        )
        let hosting = NSHostingController(rootView: contentView)
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
        let fitted = hosting.sizeThatFits(in: CGSize(width: 324, height: 480))
        let size = NSSize(width: 324, height: min(480, max(168, ceil(fitted.height))))
        let btnInWindow = self.convert(self.bounds, to: nil)
        let btnScreen = hostWindow.convertToScreen(btnInWindow)
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: btnScreen,
            panelSize: size,
            visibleScreenFrame: screenFrame
        )
        
        let panel = TodoDropdownPanel(
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
    
    
    private func repositionDropdown(preferredHeight: CGFloat) {
        guard let panel = self.panel, let hostWindow = self.window, preferredHeight > 80 else { return }
        let clampedH = min(480, max(148, preferredHeight))
        guard abs(panel.frame.height - clampedH) > 1.5 else { return }
        let btnInWindow = self.convert(self.bounds, to: nil)
        let btnScreen = hostWindow.convertToScreen(btnInWindow)
        let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let updated = UserAvatarToolbarButtonView.anchoredPanelFrame(
            buttonScreenRect: btnScreen,
            panelSize: NSSize(width: 324, height: clampedH),
            visibleScreenFrame: screenFrame
        )
        panel.setFrame(updated, display: true)
    }
    
    
    private func installMonitors(hostWindow: NSWindow, panel: TodoDropdownPanel) {
        self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window === panel { return event }
            if event.window === self.window {
                let locInSelf = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(locInSelf) { return event }
            }
            self.closeDropdown()
            return event
        }
        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeDropdown() }
        }
        self.keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, event.keyCode == 53 else { return event }
            if let fieldEditor = panel.firstResponder as? NSTextView, fieldEditor.isFieldEditor {
                return event
            }
            self.closeDropdown()
            return nil
        }
        self.windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: hostWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closeDropdown() }
        }
    }
    
    
    private func closeDropdown() {
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


private struct ToolbarCapsuleTodoTriggerView: View {
    
    let onToggle: () -> Void
    let onWidthChange: (CGFloat) -> Void
    
    @State private var analytics = AnalyticsManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        let prioritized = ToolbarCapsuleTodoHelper.prioritizedTodos(self.analytics.pinnedTodos)
        
        TimelineView(.periodic(from: .now, by: prioritized.contains(where: \.hasDeadline) ? 1.0 : 30.0)) { context in
            let now = context.date
            let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
            
            Button(action: self.onToggle) {
                if let top = prioritized.first {
                    let urgency = ToolbarCapsuleTodoHelper.urgencyLevel(for: top, now: now)
                    let badgeColor = self.urgencyColor(urgency, fallback: tokens.accentText)
                    let timeText = ToolbarCapsuleTodoHelper.timeBadgeText(for: top, now: now)
                    let extraCount = prioritized.count - 1
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(badgeColor)
                            .frame(width: 6, height: 6)
                        
                        Text(top.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 108, alignment: .leading)
                        
                        Text(timeText)
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(badgeColor.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                        
                        if extraCount > 0 {
                            Text("+\(extraCount)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(self.pillFill(isHovered: self.isHovered))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                urgency >= 3 ? badgeColor.opacity(0.45) : self.pillBorder,
                                lineWidth: 0.75
                            )
                    )
                    .fixedSize()
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(AppLanguage.text("待办", en: "Todo"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(self.pillFill(isHovered: self.isHovered))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(self.pillBorder, lineWidth: 0.75)
                    )
                    .fixedSize()
                }
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { hovering in
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.14)) {
                    self.isHovered = hovering
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w in
                self.onWidthChange(w)
            }
        }
        .frame(height: 28)
    }
    
    
    private func pillFill(isHovered: Bool) -> Color {
        if self.colorScheme == .dark {
            return Color.white.opacity(isHovered ? 0.11 : 0.065)
        }
        return Color.black.opacity(isHovered ? 0.075 : 0.045)
    }
    
    private var pillBorder: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }
    
    private func urgencyColor(_ level: Int, fallback: Color) -> Color {
        switch level {
            case 4: Color(red: 0.90, green: 0.28, blue: 0.28)
            case 3: Color(red: 0.92, green: 0.48, blue: 0.18)
            case 2: Color(red: 0.88, green: 0.62, blue: 0.16)
            default: fallback
        }
    }
}


private struct ToolbarCapsuleTodoDropdownView: View {
    
    var closeDropdown: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var analytics = AnalyticsManager.shared
    @State private var studioPalette = StudioPaletteManager.shared
    @State private var isCreating = false
    @State private var todoTitle = ""
    @State private var todoDDL: QuickTodoDDL = .hour1
    @State private var hoveredID: String?
    @State private var completingIDs: Set<String> = []
    @FocusState private var isFieldFocused: Bool
    
    
    private var cardSurface: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }
    
    private var subtleFill: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    
    private var hairline: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    
    
    var body: some View {
        let prioritized = ToolbarCapsuleTodoHelper.prioritizedTodos(self.analytics.pinnedTodos)
        let tokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        
        TimelineView(.periodic(from: .now, by: prioritized.contains(where: \.hasDeadline) ? 1.0 : 30.0)) { context in
            let now = context.date
            
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    Text(AppLanguage.text("胶囊待办", en: "Capsule Todos"))
                        .font(.system(size: 13, weight: .semibold))
                    
                    if !prioritized.isEmpty {
                        Text("\(prioritized.count)")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                            self.isCreating.toggle()
                            if self.isCreating {
                                DispatchQueue.main.async { self.isFieldFocused = true }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: self.isCreating ? "xmark" : "plus")
                                .font(.system(size: 10, weight: .semibold))
                            Text(self.isCreating ? AppLanguage.text("收起", en: "Close") : AppLanguage.text("新建", en: "New"))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundStyle(self.isCreating ? Color.secondary : tokens.accentText)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            self.isCreating ? self.subtleFill : tokens.positivePillBg,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                // Inline composer
                if self.isCreating || prioritized.isEmpty {
                    VStack(spacing: 8) {
                        TextField(AppLanguage.text("输入待办，回车添加", en: "New todo, press Return"), text: self.$todoTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .focused(self.$isFieldFocused)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(self.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onSubmit { self.submitTodo() }
                        
                        HStack(spacing: 4) {
                            ForEach(QuickTodoDDL.allCases) { option in
                                let selected = (self.todoDDL == option)
                                Button {
                                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.14)) {
                                        self.todoDDL = option
                                    }
                                } label: {
                                    Text(option.rawValue)
                                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? tokens.onAccentInk : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 24)
                                        .background(
                                            Capsule().fill(selected ? tokens.accent : self.subtleFill)
                                        )
                                }
                                .buttonStyle(.plain)
                                .pointerStyle(.link)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Spacer()
                            Button {
                                self.submitTodo()
                            } label: {
                                Text(AppLanguage.text("添加到胶囊", en: "Add Todo"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(tokens.onAccentInk)
                                    .padding(.horizontal, 12)
                                    .frame(height: 26)
                                    .background(tokens.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .pointerStyle(.link)
                        }
                    }
                    .padding(10)
                    .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(self.hairline, lineWidth: 0.75))
                }
                
                // All prioritized todos (soonest-expiring first)
                if !prioritized.isEmpty {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(prioritized) { item in
                                self.todoRow(item: item, now: now, tokens: tokens)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
            .padding(12)
            .frame(width: 324)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    
    @ViewBuilder
    private func todoRow(item: UserReminder, now: Date, tokens: StudioColorTokens) -> some View {
        let isHovered = (self.hoveredID == item.id)
        let isCompleting = self.completingIDs.contains(item.id)
        let urgency = ToolbarCapsuleTodoHelper.urgencyLevel(for: item, now: now)
        let badgeColor: Color = switch urgency {
            case 4: Color(red: 0.90, green: 0.28, blue: 0.28)
            case 3: Color(red: 0.92, green: 0.48, blue: 0.18)
            case 2: Color(red: 0.88, green: 0.62, blue: 0.16)
            default: tokens.accentText
        }
        let timeText = ToolbarCapsuleTodoHelper.timeBadgeText(for: item, now: now)
        
        HStack(spacing: 8) {
            Button {
                self.completeItem(item)
            } label: {
                ZStack {
                    Circle()
                        .fill(isCompleting ? Color(red: 0.20, green: 0.72, blue: 0.45) : badgeColor.opacity(0.14))
                        .frame(width: 20, height: 20)
                    Image(systemName: isCompleting ? "checkmark" : "circle.fill")
                        .font(.system(size: isCompleting ? 9.5 : 4.5, weight: .bold))
                        .foregroundStyle(isCompleting ? .white : badgeColor)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(AppLanguage.text("标记完成", en: "Complete"))
            
            Text(item.title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isCompleting ? .secondary : .primary)
                .strikethrough(isCompleting)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer(minLength: 4)
            
            // Always show time pill
            Text(timeText)
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                .fixedSize()
            
            if !isCompleting {
                Button {
                    self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                } label: {
                    Text("+15m")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5.5)
                        .frame(height: 22)
                        .background(self.subtleFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("延后 15 分钟", en: "Snooze 15m"))
                
                Button {
                    self.analytics.unpinReminder(id: item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(self.subtleFill, in: Circle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("移除", en: "Remove"))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? self.subtleFill : self.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(self.hairline, lineWidth: 0.65)
        )
        .onHover { hovering in
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.12)) {
                self.hoveredID = hovering ? item.id : (self.hoveredID == item.id ? nil : self.hoveredID)
            }
        }
    }
    
    
    private func submitTodo() {
        let trimmed = self.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let deadline: Date? = switch self.todoDDL {
            case .min15: now.addingTimeInterval(15 * 60)
            case .hour1: now.addingTimeInterval(3600)
            case .tonight:
                Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: now).flatMap {
                    $0.timeIntervalSince(now) > 1800 ? $0 : now.addingTimeInterval(3 * 3600)
                } ?? now.addingTimeInterval(3 * 3600)
            case .none: nil
        }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) {
            self.analytics.addPinnedTodo(title: trimmed, deadline: deadline)
            self.todoTitle = ""
            self.todoDDL = .hour1
            self.isCreating = false
        }
    }
    
    
    private func completeItem(_ item: UserReminder) {
        guard !self.completingIDs.contains(item.id) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            _ = self.completingIDs.insert(item.id)
        }
        let targetID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            withAnimation(.easeOut(duration: 0.14)) {
                self.analytics.toggleReminderCompleted(id: targetID)
                self.completingIDs.remove(targetID)
            }
        }
    }
}


/// Flagship Personal Command Hub popover featuring 360° surrounding tech danmaku,
/// soft multi-cloud aurora extraction, mascot-infused capsule todos, and direct studio navigation.
struct UserProfilePopoverView: View {
    
    var hostWindow: NSWindow?
    var closePopover: () -> Void = {}
    
    @Environment(\.colorScheme) private var colorScheme
    
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
    
    
    var body: some View {
        let active = self.manager.activeProfile
        let avatarImage = self.manager.avatarImage(for: active)
        let ambient = AvatarColorExtractor.extractPalette(for: active, image: avatarImage)
        let blurredCover = AvatarColorExtractor.blurredAmbientArtwork(for: active, image: avatarImage)
        let recent5 = self.analytics.dailySeries(days: 5).map { Double($0.typedChars) }
        let studioTokens = self.studioPalette.tokens(isDark: self.colorScheme == .dark)
        let tags = UserPersonalityAnalyzer.deduplicatedTags(
            self.analytics.personalityProfile?.tags ?? [],
            maxCount: 8
        )
        
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
                    blurredCoverImage: blurredCover,
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
                    .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity)
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
        }
        .padding(10)
        .frame(width: 348)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            self.editingName = self.manager.activeProfile.displayName
            self.greeting = Self.nextRandomGreeting()
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


// MARK: - Apple Music–Style Diffused Cover-Art Ambient Backdrop

struct SoftAvatarAuroraBackdrop: View {
    
    let palette: AvatarColorExtractor.Palette
    let blurredCoverImage: NSImage?
    let surface: Color
    let isDark: Bool
    
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        
        shape
            .fill(self.surface)
            .overlay {
                GeometryReader { geo in
                    let side = max(geo.size.width, geo.size.height) * 1.48
                    
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: AnimationConstants.isReducedMotionEnabled)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let angleA = Angle.degrees(t * 2.2)
                        let angleB = Angle.degrees(-t * 1.6 + 110)
                        let driftX = CGFloat(sin(t * 0.28) * 14)
                        let driftY = CGFloat(cos(t * 0.22) * 10)
                        
                        ZStack {
                            if let cover = self.blurredCoverImage {
                                // Authentic Apple Music cover-art ambient mesh strictly bounded to `geo.size`
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.medium)
                                    .frame(width: side, height: side)
                                    .rotationEffect(angleA)
                                    .offset(x: driftX, y: driftY)
                                    .opacity(self.isDark ? 0.56 : 0.44)
                                
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.medium)
                                    .frame(width: side * 1.10, height: side * 1.10)
                                    .rotationEffect(angleB)
                                    .offset(x: -driftX * 0.8, y: -driftY * 0.8)
                                    .blendMode(self.isDark ? .softLight : .plusLighter)
                                    .opacity(self.isDark ? 0.48 : 0.34)
                            } else {
                                // Organic mesh fallback for monogram avatars
                                RadialGradient(
                                    colors: [self.palette.primary.opacity(self.isDark ? 0.42 : 0.28), .clear],
                                    center: UnitPoint(x: 0.28 + sin(t * 0.25) * 0.08, y: 0.24),
                                    startRadius: 8,
                                    endRadius: 210
                                )
                                RadialGradient(
                                    colors: [self.palette.secondary.opacity(self.isDark ? 0.36 : 0.24), .clear],
                                    center: UnitPoint(x: 0.78, y: 0.32 + cos(t * 0.22) * 0.08),
                                    startRadius: 8,
                                    endRadius: 200
                                )
                                RadialGradient(
                                    colors: [self.palette.tertiary.opacity(self.isDark ? 0.28 : 0.18), .clear],
                                    center: .bottom,
                                    startRadius: 8,
                                    endRadius: 190
                                )
                            }
                            
                            // Apple Music atmospheric scrim + seamless vertical integration into card surface
                            LinearGradient(
                                stops: self.isDark
                                    ? [
                                        .init(color: Color.black.opacity(0.24), location: 0.0),
                                        .init(color: Color.black.opacity(0.32), location: 0.55),
                                        .init(color: Color.black.opacity(0.52), location: 1.0),
                                    ]
                                    : [
                                        .init(color: Color.white.opacity(0.46), location: 0.0),
                                        .init(color: Color.white.opacity(0.58), location: 0.55),
                                        .init(color: Color.white.opacity(0.76), location: 1.0),
                                    ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .clipShape(shape)
    }
}


// MARK: - 360° Q弹 Expressive Jelly Danmaku Stage

private struct AvatarSurroundingDanmakuStage<AvatarContent: View>: View {
    
    let tags: [UserPersonalityTag]
    let selectedTagID: String?
    let accent: Color
    let secondaryAccent: Color
    let shockwaveTimestamp: Date
    let onTapTag: (UserPersonalityTag) -> Void
    @ViewBuilder let avatarContent: () -> AvatarContent
    
    @State private var hoveredTagID: String?
    @State private var tappedTagID: String?
    @State private var anchorDate = Date()
    @State private var accumulatedTime: TimeInterval = 0
    @State private var isPaused = false
    @Environment(\.colorScheme) private var colorScheme
    
    private let stageWidth: CGFloat = 304
    private let stageHeight: CGFloat = 180
    
    
    private var laneConfigs: [(yOffset: CGFloat, speed: CGFloat, dir: CGFloat, scale: CGFloat, opacity: Double, isForeground: Bool)] {
        [
            (-64, 11.4, -1, 1.00, 1.00, true),   // Top foreground arc
            (-19, 9.6, +1, 0.94, 0.92, false),   // Upper middle orbit behind portrait
            (+22, 10.2, -1, 0.94, 0.92, false),  // Lower middle orbit behind portrait
            (+64, 12.2, +1, 1.00, 1.00, true),   // Bottom foreground arc
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
            // Underdamped jelly shockwave: outward push + elastic squash-stretch oscillation!
            let shockImpulse: CGFloat = (shockElapsed < 0.72)
                ? CGFloat(sin(shockElapsed * 14.5) * exp(-4.2 * shockElapsed) * 16.0)
                : 0
            let shockJelly: CGFloat = (shockElapsed < 0.72)
                ? CGFloat(cos(shockElapsed * 18.0) * exp(-4.8 * shockElapsed) * 0.14)
                : 0
            
            ZStack {
                self.orbitalRingsLayer(elapsed: dt, shockImpulse: shockImpulse)
                    .zIndex(0)
                
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
                        yOffset: cfg.yOffset + (cfg.yOffset < 0 ? -shockImpulse * 0.75 : shockImpulse * 0.75),
                        shockJelly: shockJelly,
                        stageWidth: self.stageWidth,
                        selectedTagID: self.selectedTagID,
                        hoveredTagID: self.$hoveredTagID,
                        tappedTagID: self.$tappedTagID,
                        accent: self.accent,
                        curvesAroundPortrait: true,
                        onTap: self.handleTagTap
                    )
                    .zIndex(1)
                }
                
                self.avatarContent()
                    .zIndex(2)
                
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
                        shockJelly: shockJelly,
                        stageWidth: self.stageWidth,
                        selectedTagID: self.selectedTagID,
                        hoveredTagID: self.$hoveredTagID,
                        tappedTagID: self.$tappedTagID,
                        accent: self.accent,
                        curvesAroundPortrait: false,
                        onTap: self.handleTagTap
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
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
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
    
    
    private func handleTagTap(_ tag: UserPersonalityTag) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.18, dampingFraction: 0.36)) {
            self.tappedTagID = tag.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.48)) {
                if self.tappedTagID == tag.id {
                    self.tappedTagID = nil
                }
            }
        }
        self.onTapTag(tag)
    }
    
    
    @ViewBuilder
    private func orbitalRingsLayer(elapsed: TimeInterval, shockImpulse: CGFloat) -> some View {
        let innerAngle = Angle.degrees(elapsed * 11)
        let outerAngle = Angle.degrees(-elapsed * 7)
        
        ZStack {
            Circle()
                .stroke(
                    self.accent.opacity(self.colorScheme == .dark ? 0.24 : 0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 5])
                )
                .frame(width: 98 + shockImpulse * 0.8, height: 98 + shockImpulse * 0.8)
                .rotationEffect(innerAngle)
            
            ZStack {
                Ellipse()
                    .strokeBorder(self.secondaryAccent.opacity(self.colorScheme == .dark ? 0.16 : 0.12), lineWidth: 0.85)
                    .frame(width: 146 + shockImpulse, height: 134 + shockImpulse)
                
                Circle()
                    .fill(self.accent)
                    .frame(width: 4.5, height: 4.5)
                    .offset(x: (146 + shockImpulse) * 0.5)
                
                Circle()
                    .fill(self.secondaryAccent)
                    .frame(width: 3.5, height: 3.5)
                    .offset(x: -(146 + shockImpulse) * 0.5)
            }
            .rotationEffect(outerAngle)
        }
        .allowsHitTesting(false)
    }
    
    
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
    let shockJelly: CGFloat
    let stageWidth: CGFloat
    let selectedTagID: String?
    @Binding var hoveredTagID: String?
    @Binding var tappedTagID: String?
    let accent: Color
    let curvesAroundPortrait: Bool
    let onTap: (UserPersonalityTag) -> Void
    
    @State private var measuredWidths: [String: CGFloat] = [:]
    @Environment(\.colorScheme) private var colorScheme
    
    
    private static func toneSymbol(for tone: PersonalityTagTone) -> String {
        switch tone {
            case .warm: "flame.fill"
            case .sharp: "bolt.fill"
            case .playful: "sparkle"
            case .calm: "leaf.fill"
        }
    }
    
    
    var body: some View {
        ZStack {
            ForEach(Array(self.tags.enumerated()), id: \.element.id) { idx, tag in
                let pillW = self.measuredWidths[tag.id] ?? CGFloat(max(66, tag.label.count * 13 + 28))
                let margin: CGFloat = 24
                let activeSpan = self.stageWidth + pillW + margin * 2
                let period = max(activeSpan, CGFloat(max(1, self.tags.count)) * 188.0)
                let stagger = (CGFloat(idx) / CGFloat(max(1, self.tags.count))) * period + CGFloat(self.laneIndex) * 58.0
                let rawProgress = (CGFloat(self.elapsed) * self.speed + stagger).truncatingRemainder(dividingBy: period)
                
                let xPos: CGFloat = self.direction < 0
                    ? (self.stageWidth * 0.5 + pillW * 0.5 + margin) - rawProgress
                    : -(self.stageWidth * 0.5 + pillW * 0.5 + margin) + rawProgress
                
                let phase = Double(idx) * 1.9 + Double(self.laneIndex) * 1.3
                // Buoyant multi-harmonic wave bob + gentle jelly squash-and-stretch breathing!
                let bobY = CGFloat(sin(self.elapsed * 2.1 + phase) * 3.2 + cos(self.elapsed * 1.15 + phase) * 1.1)
                let breathWave = CGFloat(sin(self.elapsed * 2.6 + phase)) * 0.026
                let swayTilt = sin(self.elapsed * 1.55 + phase) * 2.4
                
                let orbitBend: CGFloat = self.curvesAroundPortrait
                    ? (self.yOffset < 0 ? -1.0 : 1.0) * max(0, 1.0 - abs(xPos) / 78.0) * 11.0
                    : 0
                
                // Edge pop-in / pop-out scale so pills bloom smoothly into view
                let edgeDist = max(0, (self.stageWidth * 0.5 + pillW * 0.25) - abs(xPos))
                let edgePop = min(1.0, 0.78 + (edgeDist / 48.0) * 0.22)
                
                let isThisHovered = (self.hoveredTagID == tag.id)
                let isThisTapped = (self.tappedTagID == tag.id)
                let isSelected = (self.selectedTagID == tag.id)
                let toneColor = UserProfilePopoverView.toneColor(for: tag.tone)
                let fontSize: CGFloat = (idx % 2 == 0) ? 11.5 : 10.8
                
                // Combine breathing + shockwave + tap squish into elastic Q弹 scaleX / scaleY
                let baseS = (isThisHovered ? 1.14 : self.scale) * edgePop
                let squishX: CGFloat = isThisTapped ? 1.18 : (1.0 + breathWave + self.shockJelly)
                let squishY: CGFloat = isThisTapped ? 0.84 : (1.0 - breathWave - self.shockJelly)
                let hoverLiftY: CGFloat = isThisHovered ? -3.0 : 0.0
                
                if xPos >= -(self.stageWidth * 0.5 + pillW + 8) && xPos <= (self.stageWidth * 0.5 + pillW + 8) {
                    Button {
                        self.onTap(tag)
                    } label: {
                        HStack(spacing: 4.5) {
                            Image(systemName: Self.toneSymbol(for: tag.tone))
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(isSelected ? Color.white : toneColor)
                            
                            Text(tag.label)
                                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.92))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .fixedSize(horizontal: true, vertical: true)
                        .background {
                            if isSelected {
                                Capsule().fill(self.accent)
                            } else {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(
                                        Capsule()
                                            .fill(toneColor.opacity(self.colorScheme == .dark ? 0.16 : 0.10))
                                    )
                            }
                        }
                        .overlay(
                            // Plump jelly top specular highlight rim
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: isThisHovered || isSelected
                                            ? [Color.white.opacity(0.70), toneColor.opacity(0.65)]
                                            : (self.colorScheme == .dark
                                                ? [Color.white.opacity(0.28), Color.white.opacity(0.06)]
                                                : [Color.white.opacity(0.92), toneColor.opacity(0.22)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: isThisHovered || isSelected ? 1.15 : 0.85
                                )
                        )
                        .shadow(
                            color: (isThisHovered ? toneColor.opacity(0.24) : Color.black.opacity(self.colorScheme == .dark ? 0.22 : 0.07)),
                            radius: isThisHovered ? 6 : 3,
                            y: isThisHovered ? 3 : 1.5
                        )
                        .scaleEffect(x: baseS * squishX, y: baseS * squishY)
                        .rotationEffect(.degrees(isThisHovered ? 0 : swayTilt))
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
                    .offset(x: xPos, y: self.yOffset + bobY + orbitBend + hoverLiftY)
                    .onHover { inside in
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.48)) {
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
