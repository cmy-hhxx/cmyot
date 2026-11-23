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
    
    
    /// Builds a 9-slice stretchable alpha mask so `NSVisualEffectView`'s backdrop layer and
    /// borderless `NSPanel` shadow clip cleanly to exact rounded corners (zero square corner artifacts).
    static func makeRoundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let side = cornerRadius * 2 + 2
        let size = NSSize(width: side, height: side)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        image.resizingMode = .stretch
        return image
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
        
        let cornerRadius: CGFloat = 16
        let vfx = NSVisualEffectView()
        vfx.material = .popover
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.maskImage = Self.makeRoundedMaskImage(cornerRadius: cornerRadius)
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = cornerRadius
        vfx.layer?.masksToBounds = true
        vfx.layer?.backgroundColor = NSColor.clear.cgColor
        vfx.layer?.borderWidth = 0.5
        vfx.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        
        let contentView = AnyView(
            rootView
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
        hosting.view.layer?.cornerRadius = cornerRadius
        hosting.view.layer?.masksToBounds = true
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
        panel.invalidateShadow()
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
        let accent: Color
        
        init(primary: Color, secondary: Color, tertiary: Color, accent: Color? = nil) {
            self.primary = primary
            self.secondary = secondary
            self.tertiary = tertiary
            self.accent = accent ?? primary
        }
    }
    
    private static var cache: [String: Palette] = [:]
    private static var blurredArtworkCache: [String: NSImage] = [:]
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    
    private static func cacheSignature(for profile: UserProfile, image: NSImage?) -> String {
        if let data = profile.avatarData, !data.isEmpty {
            let head = data.prefix(8).map { String(format: "%02x", $0) }.joined()
            let tail = data.suffix(8).map { String(format: "%02x", $0) }.joined()
            return "\(profile.id)|\(data.count)|\(head)|\(tail)|\(profile.avatarColorHex)"
        }
        let imgPtr = image.map { String(UInt(bitPattern: ObjectIdentifier($0))) } ?? "nil"
        return "\(profile.id)|\(imgPtr)|\(profile.avatarColorHex)"
    }
    
    
    /// Builds a cached Apple Music–style vibrance-boosted, pre-blurred ambient mesh directly from
    /// the user's real avatar artwork so the hero card inherits its organic spatial color layout.
    static func blurredAmbientArtwork(for profile: UserProfile, image: NSImage?) -> NSImage? {
        guard let image else { return nil }
        let key = Self.cacheSignature(for: profile, image: image)
        if let cached = self.blurredArtworkCache[key] {
            return cached
        }
        guard let smallBitmap = Self.downsample(image, side: 72, innerCropFraction: 0.14),
              let cg = smallBitmap.cgImage
        else { return nil }
        
        let input = CIImage(cgImage: cg)
        var current = input
        
        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(current, forKey: kCIInputImageKey)
            colorFilter.setValue(1.52, forKey: kCIInputSaturationKey)
            colorFilter.setValue(1.08, forKey: kCIInputContrastKey)
            colorFilter.setValue(0.02, forKey: kCIInputBrightnessKey)
            if let adjusted = colorFilter.outputImage {
                current = adjusted
            }
        }
        
        if let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.setValue(current.clampedToExtent(), forKey: kCIInputImageKey)
            blurFilter.setValue(15.0, forKey: kCIInputRadiusKey)
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
    
    
    private static func downsample(_ image: NSImage, side: Int, innerCropFraction: CGFloat = 0) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        let target = NSSize(width: side, height: side)
        rep.size = target
        let srcSize = image.size
        let srcRect: NSRect
        if innerCropFraction > 0, srcSize.width > 4, srcSize.height > 4 {
            let insetX = srcSize.width * innerCropFraction
            let insetY = srcSize.height * innerCropFraction
            srcRect = NSRect(
                x: insetX,
                y: insetY,
                width: max(1, srcSize.width - insetX * 2),
                height: max(1, srcSize.height - insetY * 2)
            )
        } else {
            srcRect = .zero
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: target), from: srcRect, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    
    
    static func extractPalette(for profile: UserProfile, image: NSImage?) -> Palette {
        
        let key = Self.cacheSignature(for: profile, image: image)
        if let cached = self.cache[key] {
            return cached
        }
        
        let fallbackBase = NSColor(Color(hexString: profile.avatarColorHex)).usingColorSpace(.sRGB) ?? .systemBlue
        let fallback = Palette(
            primary: self.softAtmosphericColor(from: fallbackBase, hueOffset: 0, saturationScale: 0.9),
            secondary: self.softAtmosphericColor(from: fallbackBase, hueOffset: 0.072, saturationScale: 0.85),
            tertiary: self.softAtmosphericColor(from: fallbackBase, hueOffset: 0.161, saturationScale: 0.80),
            accent: self.vividAccentColor(from: fallbackBase)
        )
        
        guard let image,
              let bitmap = Self.downsample(image, side: 32)
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
        
        // 24 finer hue buckets (15° each); strictly skip achromatic white/gray/black pixels so
        // neutral backgrounds (which have hue == 0) never pollute the Red bucket!
        let bucketCount = 24
        var chromaticBuckets = Array(repeating: Bucket(), count: bucketCount)
        var fallbackBucket = Bucket()
        let center = 15.5
        let twoSigmaSq = 2.0 * 11.5 * 11.5
        
        for y in 0..<32 {
            for x in 0..<32 {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent < 0.35 { continue }
                
                var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
                color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
                
                let dx = Double(x) - center
                let dy = Double(y) - center
                let gaussian = 0.45 + 0.55 * exp(-(dx * dx + dy * dy) / twoSigmaSq)
                
                fallbackBucket.rSum += Double(color.redComponent) * gaussian
                fallbackBucket.gSum += Double(color.greenComponent) * gaussian
                fallbackBucket.bSum += Double(color.blueComponent) * gaussian
                fallbackBucket.weightSum += gaussian
                
                // Ignore near-white, near-black, and neutral gray pixels from hue voting
                guard sat >= 0.14, bri >= 0.12, !(bri > 0.94 && sat < 0.20) else { continue }
                
                // Favor rich mid-to-bright chromatic accents (Apple Music artwork style)
                let midLumaBoost = 1.0 - abs(Double(bri) - 0.58) * 0.65
                let chromaWeight = pow(Double(sat), 1.65) * max(0.35, midLumaBoost) * gaussian
                let idx = min(bucketCount - 1, max(0, Int(hue * CGFloat(bucketCount))))
                
                chromaticBuckets[idx].rSum += Double(color.redComponent) * chromaWeight
                chromaticBuckets[idx].gSum += Double(color.greenComponent) * chromaWeight
                chromaticBuckets[idx].bSum += Double(color.blueComponent) * chromaWeight
                chromaticBuckets[idx].weightSum += chromaWeight
            }
        }
        
        let ranked = chromaticBuckets.enumerated()
            .filter { $0.element.weightSum > 0.01 }
            .sorted { $0.element.weightSum > $1.element.weightSum }
        
        let primaryNS: NSColor
        if let top = ranked.first {
            // Merge immediate neighbor buckets (+/- 15°) for cleaner hue centroid
            let prevIdx = (top.offset - 1 + bucketCount) % bucketCount
            let nextIdx = (top.offset + 1) % bucketCount
            let combinedWeight = top.element.weightSum
                + chromaticBuckets[prevIdx].weightSum * 0.45
                + chromaticBuckets[nextIdx].weightSum * 0.45
            let r = (top.element.rSum + chromaticBuckets[prevIdx].rSum * 0.45 + chromaticBuckets[nextIdx].rSum * 0.45) / combinedWeight
            let g = (top.element.gSum + chromaticBuckets[prevIdx].gSum * 0.45 + chromaticBuckets[nextIdx].gSum * 0.45) / combinedWeight
            let b = (top.element.bSum + chromaticBuckets[prevIdx].bSum * 0.45 + chromaticBuckets[nextIdx].bSum * 0.45) / combinedWeight
            primaryNS = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        } else if fallbackBucket.weightSum > 0 {
            // Monochrome / near-black / near-white avatar: preserve cool slate harmony instead of inventing red
            let r = fallbackBucket.rSum / fallbackBucket.weightSum
            let g = fallbackBucket.gSum / fallbackBucket.weightSum
            let b = fallbackBucket.bSum / fallbackBucket.weightSum
            let avg = NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            avg.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
            primaryNS = (s < 0.08)
                ? NSColor(hue: 0.60, saturation: 0.26, brightness: max(0.62, br), alpha: 1)
                : avg
        } else {
            self.cache[key] = fallback
            return fallback
        }
        
        let primary = Self.softAtmosphericColor(from: primaryNS, hueOffset: 0, saturationScale: 0.96)
        let accent = Self.vividAccentColor(from: primaryNS)
        
        let topOffset = ranked.first?.offset ?? 0
        let second = ranked.first { candidate in
            let dist = min(abs(candidate.offset - topOffset), bucketCount - abs(candidate.offset - topOffset))
            return dist >= 3
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
            secondary = Self.softAtmosphericColor(from: secondaryNS, hueOffset: 0, saturationScale: 0.90)
        } else {
            secondaryNS = primaryNS
            secondary = Self.softAtmosphericColor(from: primaryNS, hueOffset: 0.072, saturationScale: 0.85)
        }
        
        let tertiary = Self.softAtmosphericColor(from: secondaryNS, hueOffset: 0.095, saturationScale: 0.82)
        
        let palette = Palette(primary: primary, secondary: secondary, tertiary: tertiary, accent: accent)
        self.cache[key] = palette
        return palette
    }
    
    
    /// Faithful vibrant accent derived directly from the avatar's winning chromatic cluster.
    private static func vividAccentColor(from color: NSColor) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgb = color.usingColorSpace(.sRGB) ?? color
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let resolvedSat = min(0.82, max(0.38, s * 1.05))
        let resolvedBri = min(0.88, max(0.56, b * 0.95 + 0.08))
        let hsb = NSColor(hue: h, saturation: resolvedSat, brightness: resolvedBri, alpha: 1.0)
            .usingColorSpace(.sRGB) ?? srgb
        return Color(nsColor: hsb)
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
}


private enum QuickTodoDDL: String, CaseIterable, Identifiable {
    
    case min15 = "15分"
    case hour1 = "1小时"
    case tonight = "今晚"
    case none = "无期限"
    
    var id: String { self.rawValue }
}


// MARK: - Dedicated Toolbar Capsule Todo Region (Left of Avatar)

/// Sorts active todos in reverse chronological order of deadline (latest DDL first, timeless last), and formats time badges.
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
                        return lhs.dueDate > rhs.dueDate
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
    
    
    /// Formats an explicit DDL timestamp (`HH:mm` today or `MM/dd HH:mm` on other days) for display alongside countdowns.
    static func deadlineClockText(for item: UserReminder, now: Date) -> String? {
        guard item.hasDeadline else { return nil }
        let cal = Calendar.current
        if cal.isDate(item.dueDate, inSameDayAs: now) {
            return item.dueDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return item.dueDate.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
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
        
        let cornerRadius: CGFloat = 14
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
        
        let contentView = AnyView(
            rootView
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
        hosting.view.layer?.cornerRadius = cornerRadius
        hosting.view.layer?.masksToBounds = true
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
        panel.invalidateShadow()
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
                    let progress = Self.countdownProgress(for: top, now: now)
                    let extraCount = prioritized.count - 1
                    
                    HStack(spacing: 6) {
                        // Meter Remaining–inspired mini circular countdown ring
                        ZStack {
                            Circle()
                                .stroke(badgeColor.opacity(0.24), lineWidth: 1.8)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(badgeColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        .frame(width: 12, height: 12)
                        
                        Text(top.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 108, alignment: .leading)
                        
                        Text(timeText)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(badgeColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(badgeColor.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                        
                        if extraCount > 0 {
                            Text("+\(extraCount)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(self.pillFill(isHovered: self.isHovered))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                urgency >= 3 ? badgeColor.opacity(0.45) : Color.clear,
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
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(self.pillFill(isHovered: self.isHovered))
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
        guard isHovered else { return .clear }
        return self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
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
    
    
    static func countdownProgress(for item: UserReminder, now: Date) -> CGFloat {
        guard item.hasDeadline else { return 0.72 }
        let total = max(60.0, item.dueDate.timeIntervalSince(item.createdAt))
        let remaining = item.dueDate.timeIntervalSince(now)
        if remaining <= 0 { return 1.0 }
        let ratio = min(1.0, max(0.08, remaining / total))
        return CGFloat(ratio)
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
        self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.03)
    }
    
    private var subtleFill: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.055)
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
                    Text(AppLanguage.text("待办", en: "Todos"))
                        .font(.system(size: 13.5, weight: .semibold))
                    
                    if !prioritized.isEmpty {
                        Text(String(format: "%02d", prioritized.count))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(self.subtleFill, in: Capsule())
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
                
                // Inline Live-Activity Quick Composer
                if self.isCreating || prioritized.isEmpty {
                    VStack(spacing: 8) {
                        TextField(AppLanguage.text("输入待办，回车添加", en: "New todo, press Return"), text: self.$todoTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .focused(self.$isFieldFocused)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(self.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                                Text(AppLanguage.text("添加待办", en: "Add Todo"))
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
                    .background(self.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(self.hairline, lineWidth: 0.75))
                }
                
                // Live-Activity Focus Hero Card for Soonest Todo (Picking up order / ETA 5:50 + Meter Remaining 1:13 inspired)
                if let focusItem = prioritized.first {
                    self.liveActivityHeroTodoCard(item: focusItem, now: now, tokens: tokens)
                }
                
                // Remaining Prioritized Todos
                if prioritized.count > 1 {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(Array(prioritized.dropFirst())) { item in
                                self.todoRow(item: item, now: now, tokens: tokens)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding(12)
            .frame(width: 334)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    
    @ViewBuilder
    private func liveActivityHeroTodoCard(item: UserReminder, now: Date, tokens: StudioColorTokens) -> some View {
        let isCompleting = self.completingIDs.contains(item.id)
        let urgency = ToolbarCapsuleTodoHelper.urgencyLevel(for: item, now: now)
        let accentColor: Color = switch urgency {
            case 4: Color(red: 0.92, green: 0.30, blue: 0.30)
            case 3: Color(red: 0.94, green: 0.50, blue: 0.20)
            case 2: Color(red: 0.90, green: 0.64, blue: 0.18)
            default: tokens.accent
        }
        let statusLabel: String = switch urgency {
            case 4: AppLanguage.text("已超时", en: "Overdue")
            case 3: AppLanguage.text("即将到期", en: "Due Soon")
            case 2: AppLanguage.text("进行中", en: "Active")
            default: item.hasDeadline ? AppLanguage.text("待处理", en: "Upcoming") : AppLanguage.text("随时可做", en: "Anytime")
        }
        let timeText = ToolbarCapsuleTodoHelper.timeBadgeText(for: item, now: now)
        let elapsedRatio: CGFloat = {
            guard item.hasDeadline else { return 0.36 }
            let total = max(60.0, item.dueDate.timeIntervalSince(item.createdAt))
            let elapsed = now.timeIntervalSince(item.createdAt)
            return CGFloat(min(1.0, max(0.08, elapsed / total)))
        }()
        let ringRemaining = ToolbarCapsuleTodoTriggerView.countdownProgress(for: item, now: now)
        
        VStack(alignment: .leading, spacing: 10) {
            // Top telemetry bar: status + bold tabular ETA / countdown
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                
                Spacer()
                
                Text(timeText)
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(urgency >= 3 ? accentColor : .primary)
                
                if let ddlClock = ToolbarCapsuleTodoHelper.deadlineClockText(for: item, now: now) {
                    Text(ddlClock)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            
            // Picking-up-order inspired luminous horizontal progress track
            GeometryReader { geo in
                let trackW = max(40, geo.size.width)
                let fillW = max(14, trackW * elapsedRatio)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(accentColor.opacity(self.colorScheme == .dark ? 0.20 : 0.14))
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.65), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillW)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: accentColor.opacity(0.55), radius: 3)
                        .offset(x: max(2, min(trackW - 10, fillW - 9)))
                }
            }
            .frame(height: 10)
            
            // Bottom action row: Circular countdown ring + Task Title (left), tactile round action pills (right)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.22), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: ringRemaining)
                        .stroke(accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 18, height: 18)
                
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isCompleting ? .secondary : .primary)
                    .strikethrough(isCompleting)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer(minLength: 4)
                
                // Tactile circular action pills (Complete / +15m / Remove)
                Button {
                    self.completeItem(item)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(isCompleting ? .white : accentColor)
                        .frame(width: 26, height: 24)
                        .background(
                            Capsule().fill(isCompleting ? Color(red: 0.20, green: 0.72, blue: 0.45) : accentColor.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(AppLanguage.text("标记完成", en: "Complete"))
                
                if !isCompleting {
                    Button {
                        self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                    } label: {
                        Text("+15m")
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6.5)
                            .frame(height: 24)
                            .background(self.subtleFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("延后 15 分钟", en: "Snooze 15m"))
                    
                    Button {
                        self.analytics.unpinReminder(id: item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(self.subtleFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("移除", en: "Remove"))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(self.colorScheme == .dark ? 0.14 : 0.08),
                            self.cardSurface,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(accentColor.opacity(self.colorScheme == .dark ? 0.28 : 0.20), lineWidth: 0.8)
        )
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
        let progress = ToolbarCapsuleTodoTriggerView.countdownProgress(for: item, now: now)
        
        HStack(spacing: 8) {
            Button {
                self.completeItem(item)
            } label: {
                ZStack {
                    if isCompleting {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.72, blue: 0.45))
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Circle()
                            .stroke(badgeColor.opacity(0.24), lineWidth: 1.8)
                            .frame(width: 16, height: 16)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(badgeColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 16, height: 16)
                    }
                }
                .frame(width: 22, height: 22)
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
            
            // Always show tabular DDL clock + countdown pill
            if let ddlClock = ToolbarCapsuleTodoHelper.deadlineClockText(for: item, now: now) {
                Text(ddlClock)
                    .font(.system(size: 10, weight: .medium, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            
            Text(timeText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(self.colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                .fixedSize()
            
            if !isCompleting {
                Button {
                    self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                } label: {
                    Text("+15m")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
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
        .padding(.horizontal, 9)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isHovered ? self.subtleFill : self.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
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
        
        VStack(spacing: 0) {
            // 1. Seamless Edge-to-Edge Hero Card with Diffused Aurora + 3D Cosmic Nebula Danmaku
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
                        .foregroundStyle(self.isDanmakuEnabled ? ambient.accent : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            self.isDanmakuEnabled
                                ? ambient.accent.opacity(self.colorScheme == .dark ? 0.22 : 0.14)
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
                    accent: ambient.accent,
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
                                .strokeBorder(ambient.accent.opacity(self.avatarPulseOpacity), lineWidth: 2)
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
                                    color: ambient.accent.opacity(0.36),
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
            .padding(.top, 14)
            .padding(.bottom, 14)
            .padding(.horizontal, 14)
            .background {
                SoftAvatarAuroraBackdrop(
                    palette: ambient,
                    blurredCoverImage: blurredCover,
                    surface: .clear,
                    isDark: self.colorScheme == .dark,
                    cornerRadius: 0
                )
            }
            
            // Single quiet hairline divider separating Hero stage from Command Dock (zero nested boxes)
            Rectangle()
                .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                .frame(height: 0.5)
            
            // 2. Seamless 2-Tile Command Dock (数据看板 | 个人设置 / 通行证)
            HStack(spacing: 0) {
                Button {
                    let targetWindow = self.hostWindow
                    self.closePopover()
                    AnalyticsDashboardWindowController.shared.showInWindow(preferredWindow: targetWindow)
                } label: {
                    HStack(spacing: 9) {
                        MiniPopoverSparkMatrix(values: recent5, accent: studioTokens.accentText, emptyColor: self.surfaceFill)
                            .frame(width: 26, height: 18)
                            .padding(5)
                            .background(studioTokens.positivePillBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        
                        Text(AppLanguage.text("数据看板", en: "Dashboard"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        
                        Spacer(minLength: 2)
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(self.isDashboardHovered ? studioTokens.accentText : .secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(self.isDashboardHovered ? self.surfaceFill : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .onHover { hovering in
                    withAnimation(Self.quick) { self.isDashboardHovered = hovering }
                }
                
                Rectangle()
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                    .frame(width: 0.5, height: 28)
                
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
                        .padding(.leading, 14)
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
                    .padding(.trailing, 10)
                }
                .frame(height: 48)
                .frame(maxWidth: .infinity)
                .background(self.isSettingsHovered ? self.surfaceFill : Color.clear)
                .onHover { hovering in
                    withAnimation(Self.quick) { self.isSettingsHovered = hovering }
                }
            }
            
            // 3. Compact Horizontal Account Switcher Strip (if multiple local users exist)
            if self.manager.profiles.count > 1 {
                Rectangle()
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                    .frame(height: 0.5)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(self.manager.profiles) { profile in
                            self.profileSwitchPill(profile, isActive: profile.id == active.id, accent: studioTokens.accentText)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
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
    var cornerRadius: CGFloat = 14
    
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
        
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
                            // Extracted dominant accent wash anchors the hero card to the avatar's true color
                            RadialGradient(
                                colors: [self.palette.accent.opacity(self.isDark ? 0.42 : 0.30), .clear],
                                center: UnitPoint(x: 0.30 + sin(t * 0.25) * 0.08, y: 0.26),
                                startRadius: 8,
                                endRadius: 215
                            )
                            RadialGradient(
                                colors: [self.palette.secondary.opacity(self.isDark ? 0.32 : 0.22), .clear],
                                center: UnitPoint(x: 0.76, y: 0.36 + cos(t * 0.22) * 0.08),
                                startRadius: 8,
                                endRadius: 205
                            )
                            
                            if let cover = self.blurredCoverImage {
                                // Authentic Apple Music cover-art ambient mesh strictly bounded to `geo.size`
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.medium)
                                    .frame(width: side, height: side)
                                    .rotationEffect(angleA)
                                    .offset(x: driftX, y: driftY)
                                    .opacity(self.isDark ? 0.54 : 0.46)
                                
                                Image(nsImage: cover)
                                    .resizable()
                                    .interpolation(.medium)
                                    .frame(width: side * 1.10, height: side * 1.10)
                                    .rotationEffect(angleB)
                                    .offset(x: -driftX * 0.8, y: -driftY * 0.8)
                                    .blendMode(self.isDark ? .softLight : .overlay)
                                    .opacity(self.isDark ? 0.44 : 0.30)
                            } else {
                                RadialGradient(
                                    colors: [self.palette.tertiary.opacity(self.isDark ? 0.28 : 0.20), .clear],
                                    center: .bottom,
                                    startRadius: 8,
                                    endRadius: 190
                                )
                            }
                            
                            // Clean atmospheric scrim preserving extracted chroma while keeping nickname legible
                            LinearGradient(
                                stops: self.isDark
                                    ? [
                                        .init(color: Color.black.opacity(0.16), location: 0.0),
                                        .init(color: Color.black.opacity(0.24), location: 0.55),
                                        .init(color: Color.black.opacity(0.42), location: 1.0),
                                    ]
                                    : [
                                        .init(color: Color.white.opacity(0.26), location: 0.0),
                                        .init(color: Color.white.opacity(0.36), location: 0.55),
                                        .init(color: Color.white.opacity(0.56), location: 1.0),
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


// MARK: - Stratified Non-Overlapping Danmaku Stage (分层无遮挡环绕弹幕)

nonisolated enum AvatarDanmakuLaneScheduler {
    
    struct ScheduledItem: Identifiable, Sendable {
        var id: String { self.tag.id }
        let tag: UserPersonalityTag
        let index: Int
        let laneIndex: Int
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
        let opacity: Double
    }
    
    static let stageWidth: CGFloat = 320
    static let stageHeight: CGFloat = 186
    static let pillEstimatedWidth: CGFloat = 116
    static let pillEstimatedHeight: CGFloat = 22
    static let cycleSpan: CGFloat = 480
    
    // 4 strictly disjoint horizontal bands:
    // Lane 0 (outer top): y ≈ -76  [-87, -65]
    // Lane 1 (inner top): y ≈ -48  [-59, -37] (clears central 68x68 avatar radius = 34pt)
    // Lane 2 (inner bot): y ≈ +48  [+37, +59]
    // Lane 3 (outer bot): y ≈ +76  [+65, +87]
    private static let laneBaseY: [CGFloat] = [-76, -48, 48, 76]
    private static let laneSpeeds: [Double] = [-24.0, 19.0, -21.0, 17.0]
    private static let laneInitialPhase: [Double] = [30, 150, 90, 210]
    
    static func schedule(
        tags: [UserPersonalityTag],
        elapsed: TimeInterval,
        shockExpand: CGFloat = 0
    ) -> [ScheduledItem] {
        let clampedTags = Array(tags.prefix(8))
        guard !clampedTags.isEmpty else { return [] }
        
        let halfSpan = Self.cycleSpan * 0.5
        return clampedTags.enumerated().map { idx, tag in
            let lane = idx % 4
            let slot = idx / 4
            let speed = Self.laneSpeeds[lane]
            let rawPos = Self.laneInitialPhase[lane]
                + Double(slot) * Double(halfSpan)
                + elapsed * speed
            var wrapped = rawPos.truncatingRemainder(dividingBy: Double(Self.cycleSpan))
            if wrapped < 0 { wrapped += Double(Self.cycleSpan) }
            let x = CGFloat(wrapped) - halfSpan
            
            let baseY = Self.laneBaseY[lane]
            let signY: CGFloat = baseY < 0 ? -1 : 1
            let arch: CGFloat = (lane == 1 || lane == 2)
                ? signY * 2.0 * CGFloat(exp(-Double((x / 52.0) * (x / 52.0))))
                : 0
            let shockOffset = signY * min(4.0, abs(shockExpand) * 0.22) * (shockExpand >= 0 ? 1 : -0.4)
            let y = baseY + arch + shockOffset
            
            let absX = abs(x)
            let edgeFade: Double = if absX <= 122 {
                1.0
            } else if absX >= 172 {
                0.0
            } else {
                Double(1.0 - (absX - 122) / 50.0)
            }
            let laneScale: CGFloat = (lane == 1 || lane == 2) ? 0.98 : 0.95
            
            return ScheduledItem(
                tag: tag,
                index: idx,
                laneIndex: lane,
                x: x,
                y: y,
                scale: laneScale,
                opacity: edgeFade
            )
        }
    }
}


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
    
    private let stageWidth: CGFloat = AvatarDanmakuLaneScheduler.stageWidth
    private let stageHeight: CGFloat = AvatarDanmakuLaneScheduler.stageHeight
    
    
    var body: some View {
        let uniqueTags = UserPersonalityAnalyzer.deduplicatedTags(self.tags, maxCount: 8)
        
        TimelineView(.animation(minimumInterval: nil, paused: AnimationConstants.isReducedMotionEnabled)) { context in
            let dt = self.isPaused
                ? self.accumulatedTime
                : self.accumulatedTime + max(0, context.date.timeIntervalSince(self.anchorDate))
            let shockElapsed = max(0, context.date.timeIntervalSince(self.shockwaveTimestamp))
            let shockExpand: CGFloat = (shockElapsed < 0.85)
                ? CGFloat(sin(shockElapsed * 12.0) * exp(-3.6 * shockElapsed) * 18.0)
                : 0
            let shockRingProgress: CGFloat = (shockElapsed < 0.78) ? CGFloat(shockElapsed / 0.78) : -1
            
            let scheduled = AvatarDanmakuLaneScheduler.schedule(
                tags: uniqueTags,
                elapsed: dt,
                shockExpand: shockExpand
            )
            
            ZStack {
                // Layer 0: Subtle ambient starfield & sanctuary rings around the center avatar
                self.cosmicNebulaCanvas(elapsed: dt, shockExpand: shockExpand, shockRingProgress: shockRingProgress)
                    .zIndex(0)
                
                // Layer 1: Central User Avatar in unobstructed sanctuary
                self.avatarContent()
                    .zIndex(1)
                
                // Layer 2: Strictly non-overlapping stratified danmaku tracks
                ForEach(scheduled) { item in
                    self.nebulaTagView(item, elapsed: dt)
                        .zIndex(self.hoveredTagID == item.tag.id ? 4 : 2)
                }
            }
            .frame(width: self.stageWidth, height: self.stageHeight)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.10),
                        .init(color: .black, location: 0.90),
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
    private func nebulaTagView(_ item: AvatarDanmakuLaneScheduler.ScheduledItem, elapsed: TimeInterval) -> some View {
        let tag = item.tag
        let isHovered = (self.hoveredTagID == tag.id)
        let isTapped = (self.tappedTagID == tag.id)
        let isSelected = (self.selectedTagID == tag.id)
        let toneColor = UserProfilePopoverView.toneColor(for: tag.tone)
        let isDark = (self.colorScheme == .dark)
        
        let hoverScale: CGFloat = isHovered ? 1.08 : (isTapped ? 0.94 : 1.0)
        let finalScale = item.scale * hoverScale
        let finalOpacity = (isHovered || isSelected) ? max(item.opacity, 0.96) : item.opacity
        let starPulse = 0.65 + 0.35 * sin(elapsed * 3.0 + Double(item.index) * 1.4)
        
        Button {
            self.handleTagTap(tag)
        } label: {
            HStack(spacing: 4.5) {
                Circle()
                    .fill(isSelected ? Color.white : toneColor)
                    .frame(width: 4.5, height: 4.5)
                    .shadow(color: toneColor.opacity(0.75 * starPulse), radius: 2.5)
                
                Text(tag.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(isDark ? 0.94 : 0.88))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .frame(height: AvatarDanmakuLaneScheduler.pillEstimatedHeight)
            .background {
                if isSelected {
                    Capsule().fill(self.accent)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            toneColor.opacity(isDark ? 0.22 : 0.13),
                                            self.secondaryAccent.opacity(isDark ? 0.10 : 0.05),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
            }
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: isHovered || isSelected
                                ? [Color.white.opacity(0.80), toneColor.opacity(0.70)]
                                : (isDark
                                    ? [Color.white.opacity(0.26), toneColor.opacity(0.20)]
                                    : [Color.white.opacity(0.92), toneColor.opacity(0.26)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHovered || isSelected ? 1.05 : 0.75
                    )
            )
            .shadow(
                color: toneColor.opacity(isHovered ? 0.30 : (isDark ? 0.18 : 0.08)),
                radius: isHovered ? 6 : 3,
                y: isHovered ? 2 : 1
            )
            .scaleEffect(finalScale)
            .opacity(finalOpacity)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .allowsHitTesting(item.opacity > 0.12)
        .offset(x: item.x, y: item.y)
        .onHover { inside in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.68)) {
                if inside {
                    self.hoveredTagID = tag.id
                } else if self.hoveredTagID == tag.id {
                    self.hoveredTagID = nil
                }
            }
        }
    }
    
    
    @ViewBuilder
    private func cosmicNebulaCanvas(
        elapsed: TimeInterval,
        shockExpand: CGFloat,
        shockRingProgress: CGFloat
    ) -> some View {
        let isDark = (self.colorScheme == .dark)
        let cosmicViolet = Color(red: 0.48, green: 0.36, blue: 0.92)
        let cosmicCyan = Color(red: 0.22, green: 0.76, blue: 0.96)
        
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            
            // 1. Soft radial aurora around center avatar
            for arm in 0..<2 {
                let armAngle = elapsed * (arm == 0 ? 0.14 : -0.11) + Double(arm) * 2.1
                let armCenter = CGPoint(
                    x: center.x + CGFloat(cos(armAngle)) * 22,
                    y: center.y + CGFloat(sin(armAngle)) * 10
                )
                let cloudRadius: CGFloat = arm == 0 ? 110 : 88
                let cloudColor = arm == 0 ? self.accent : cosmicViolet
                let cloudRect = CGRect(
                    x: armCenter.x - cloudRadius,
                    y: armCenter.y - cloudRadius * 0.58,
                    width: cloudRadius * 2,
                    height: cloudRadius * 1.16
                )
                context.fill(
                    Ellipse().path(in: cloudRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            cloudColor.opacity(isDark ? 0.18 : 0.10),
                            cosmicCyan.opacity(isDark ? 0.06 : 0.03),
                            .clear,
                        ]),
                        center: armCenter,
                        startRadius: 4,
                        endRadius: cloudRadius
                    )
                )
            }
            
            // 2. Subtle ambient starfield
            for i in 0..<26 {
                let seed = Double(i) * 1.61803398875
                let baseRadius = 46.0 + (seed.truncatingRemainder(dividingBy: 1.0)) * 102.0
                let theta = Double(i) * 2.39996 + elapsed * (0.04 + Double(i % 4) * 0.01) * (i.isMultiple(of: 2) ? 1.0 : -1.0)
                let sx = center.x + CGFloat(cos(theta) * baseRadius)
                let sy = center.y + CGFloat(sin(theta) * baseRadius * 0.54)
                let twinkle = 0.25 + 0.75 * (0.5 + 0.5 * sin(elapsed * (1.8 + Double(i % 4) * 0.6) + Double(i) * 1.7))
                let starR: CGFloat = (i % 7 == 0) ? 1.5 : 0.9
                let starColor: Color = i.isMultiple(of: 3) ? self.accent : (i.isMultiple(of: 2) ? cosmicCyan : cosmicViolet)
                let alpha = (isDark ? 0.55 : 0.36) * twinkle
                let dotRect = CGRect(x: sx - starR, y: sy - starR, width: starR * 2, height: starR * 2)
                context.fill(Circle().path(in: dotRect), with: .color(starColor.opacity(alpha)))
            }
            
            // 3. Quiet concentric sanctuary ring around avatar
            let sanctuaryR = 40 + shockExpand * 0.25
            let sanctuaryRect = CGRect(x: center.x - sanctuaryR, y: center.y - sanctuaryR, width: sanctuaryR * 2, height: sanctuaryR * 2)
            context.stroke(
                Circle().path(in: sanctuaryRect),
                with: .color(self.accent.opacity(isDark ? 0.22 : 0.16)),
                style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
            )
            
            // 4. Supernova shockwave ring on avatar tap
            if shockRingProgress >= 0, shockRingProgress <= 1 {
                let waveR = 36 + shockRingProgress * 110
                let waveAlpha = Double(1.0 - shockRingProgress) * (isDark ? 0.52 : 0.38)
                let waveRect = CGRect(x: center.x - waveR, y: center.y - waveR * 0.68, width: waveR * 2, height: waveR * 1.36)
                context.stroke(
                    Ellipse().path(in: waveRect),
                    with: .color(self.accent.opacity(waveAlpha)),
                    lineWidth: max(0.6, 2.0 * (1.0 - shockRingProgress))
                )
            }
        }
        .allowsHitTesting(false)
    }
    
    
    private func handleTagTap(_ tag: UserPersonalityTag) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(.spring(response: 0.18, dampingFraction: 0.42)) {
            self.tappedTagID = tag.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.56)) {
                if self.tappedTagID == tag.id {
                    self.tappedTagID = nil
                }
            }
        }
        self.onTapTag(tag)
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
