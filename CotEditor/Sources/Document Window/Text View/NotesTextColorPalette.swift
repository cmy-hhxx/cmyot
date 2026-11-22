//
//  NotesTextColorPalette.swift
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

struct NotesColoredPassageItem: Identifiable, Equatable, Sendable {
    
    let id: String
    let range: NSRange
    let color: HighlightColor
    let preview: String
    let isActive: Bool
}


@MainActor
@Observable
final class NotesTextColorPaletteModel {
    
    var selectedColor: HighlightColor?
    var customHue: Double = 210
    var isCustomHueExpanded: Bool = false
    var recentPassages: [NotesColoredPassageItem] = []
    var beakOffsetX: CGFloat = 0
    var pointsDownward: Bool = true
    var appears: Bool = false
}


/// Non-activating frosted floating palette inspired by Notes Text Color.
///
/// Appears beside an active text selection without stealing first responder, lets the user paint
/// 8 curated radial-orb shades or a continuous rainbow hue (`hsl(h, 76%, 72%)`), and jumps back
/// to up to 4 recently colored passages inside the document.
@MainActor
final class NotesTextColorPaletteController {
    
    static let shared = NotesTextColorPaletteController()
    
    private static let panelWidth: CGFloat = 218
    private static let compactHeight: CGFloat = 104
    private static let expandedHeight: CGFloat = 136
    private static let marginPadding: CGFloat = 12
    
    private let model = NotesTextColorPaletteModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotesTextColorPaletteRootView>?
    private weak var textView: EditorTextView?
    private weak var document: Document?
    private var activeRange = NSRange(location: NSNotFound, length: 0)
    private var scrollObserver: (any NSObjectProtocol)?
    private var windowResignObserver: (any NSObjectProtocol)?
    private var dismissWorkItem: DispatchWorkItem?
    
    
    var isVisible: Bool {
        self.panel?.isVisible == true && self.model.appears
    }
    
    
    private init() {}
    
    
    /// Presents or updates the frosted floating color palette for the current selection.
    func present(for textView: EditorTextView, document: Document, selectedRange: NSRange) {
        
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              textView.isEditable,
              selectedRange.length > 0,
              let window = textView.window,
              !textView.string.isEmpty
        else {
            self.dismiss(animated: false)
            return
        }
        
        // Do not show text highlight palette when selecting a standalone inline image token.
        let nsString = textView.string as NSString
        let safeRange = NSIntersectionRange(selectedRange, NSRange(location: 0, length: nsString.length))
        guard safeRange.length > 0 else {
            self.dismiss(animated: false)
            return
        }
        let selectedSnippet = nsString.substring(with: safeRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedSnippet.hasPrefix("⟦🖼"), selectedSnippet.hasSuffix("⟧"), !selectedSnippet.contains("\n") {
            self.dismiss(animated: false)
            return
        }
        
        guard let anchor = self.selectionScreenBounds(in: textView, window: window, range: safeRange) else {
            self.dismiss(animated: false)
            return
        }
        
        self.dismissWorkItem?.cancel()
        self.dismissWorkItem = nil
        
        let isSameTextView = (self.textView === textView)
        self.textView = textView
        self.document = document
        self.activeRange = safeRange
        
        self.syncModel(from: document, selectedRange: safeRange)
        if case .customHue = self.model.selectedColor {
            self.model.isCustomHueExpanded = true
        } else if !isSameTextView {
            self.model.isCustomHueExpanded = false
        }
        
        self.ensurePanel()
        self.attachObservers(textView: textView, window: window)
        self.positionPanel(against: anchor, window: window)
        
        let alreadyShown = self.panel?.isVisible == true && self.model.appears
        if !alreadyShown {
            self.model.appears = false
        }
        self.panel?.orderFront(nil)
        
        if !alreadyShown {
            DispatchQueue.main.async { [weak self] in
                withAnimation(.spring(response: 0.18, dampingFraction: 0.74)) {
                    self?.model.appears = true
                }
            }
        }
    }
    
    
    /// Dismisses the palette cleanly with an optional 140ms fade-out.
    func dismiss(animated: Bool = true) {
        
        self.dismissWorkItem?.cancel()
        self.dismissWorkItem = nil
        self.detachObservers()
        
        guard let panel = self.panel, panel.isVisible else {
            self.model.appears = false
            self.textView = nil
            self.document = nil
            return
        }
        
        guard animated else {
            self.model.appears = false
            panel.orderOut(nil)
            self.textView = nil
            self.document = nil
            return
        }
        
        withAnimation(.easeIn(duration: 0.14)) {
            self.model.appears = false
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.appears else { return }
            self.panel?.orderOut(nil)
            self.textView = nil
            self.document = nil
        }
        self.dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    
    
    // MARK: Actions
    
    private func handlePresetTap(_ color: HighlightColor) {
        
        guard let textView = self.textView,
              let document = self.document
        else { return }
        
        let range = self.clampedActiveRange(in: document)
        guard range.length > 0 else { return }
        
        if self.model.selectedColor == color {
            document.removeHighlights(in: range)
            self.model.selectedColor = nil
        } else {
            document.addHighlight(range: range, color: color)
            self.model.selectedColor = color
        }
        
        self.syncModel(from: document, selectedRange: range)
        textView.needsDisplay = true
    }
    
    
    private func handleToggleRainbowSlider() {
        
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            self.model.isCustomHueExpanded.toggle()
        }
        if let textView = self.textView,
           let window = textView.window,
           let anchor = self.selectionScreenBounds(in: textView, window: window, range: self.activeRange)
        {
            self.positionPanel(against: anchor, window: window)
        }
        if self.model.isCustomHueExpanded {
            self.handleCustomHueChanged(self.model.customHue)
        }
    }
    
    
    private func handleCustomHueChanged(_ hue: Double) {
        
        let normalized = HighlightColor.normalizedHue(hue)
        self.model.customHue = normalized
        
        guard let textView = self.textView,
              let document = self.document
        else { return }
        
        let range = self.clampedActiveRange(in: document)
        guard range.length > 0 else { return }
        
        let customColor = HighlightColor.customHue(normalized)
        document.addHighlight(range: range, color: customColor)
        self.model.selectedColor = customColor
        self.syncModel(from: document, selectedRange: range)
        textView.needsDisplay = true
    }
    
    
    private func handleJumpToPassage(_ item: NotesColoredPassageItem) {
        
        guard let textView = self.textView,
              let document = self.document
        else { return }
        
        let nsLength = (textView.string as NSString).length
        let safeRange = NSIntersectionRange(item.range, NSRange(location: 0, length: nsLength))
        guard safeRange.length > 0 else { return }
        
        textView.scrollRangeToVisible(safeRange)
        textView.setSelectedRange(safeRange)
        self.present(for: textView, document: document, selectedRange: safeRange)
    }
    
    
    // MARK: Model & Layout Helpers
    
    private func clampedActiveRange(in document: Document) -> NSRange {
        
        NSIntersectionRange(self.activeRange, NSRange(location: 0, length: document.textStorage.length))
    }
    
    
    private func syncModel(from document: Document, selectedRange: NSRange) {
        
        let touching = document.textHighlights.first { NSIntersectionRange($0.range, selectedRange).length > 0 }
        self.model.selectedColor = touching?.color
        if case .customHue(let hue) = touching?.color {
            self.model.customHue = hue
        }
        
        let string = document.textStorage.string as NSString
        let wholeRange = NSRange(location: 0, length: string.length)
        
        var orderedMarks = document.textHighlights
        if let activeMark = touching,
           let idx = orderedMarks.firstIndex(where: { $0 == activeMark })
        {
            orderedMarks.remove(at: idx)
            orderedMarks.insert(activeMark, at: 0)
        } else {
            orderedMarks.reverse()
        }
        
        var items: [NotesColoredPassageItem] = []
        for mark in orderedMarks.prefix(4) {
            let safeRange = NSIntersectionRange(mark.range, wholeRange)
            guard safeRange.length > 0 else { continue }
            
            let raw = string.substring(with: safeRange)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            
            let preview = raw.count > 16 ? String(raw.prefix(15)) + "…" : raw
            let isActive = NSIntersectionRange(safeRange, selectedRange).length > 0
            items.append(NotesColoredPassageItem(
                id: "\(safeRange.location)-\(safeRange.length)",
                range: safeRange,
                color: mark.color,
                preview: preview,
                isActive: isActive
            ))
        }
        self.model.recentPassages = items
    }
    
    
    private func ensurePanel() {
        
        if self.panel != nil { return }
        
        let rootView = NotesTextColorPaletteRootView(
            model: self.model,
            onSelectPreset: { [weak self] color in self?.handlePresetTap(color) },
            onToggleRainbow: { [weak self] in self?.handleToggleRainbowSlider() },
            onChangeHue: { [weak self] hue in self?.handleCustomHueChanged(hue) },
            onSelectPassage: { [weak self] item in self?.handleJumpToPassage(item) }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        
        self.hostingView = hosting
        self.panel = panel
    }
    
    
    private func positionPanel(against anchor: (firstLine: NSRect, lastLine: NSRect), window: NSWindow) {
        
        guard let panel = self.panel else { return }
        
        let panelHeight = self.model.isCustomHueExpanded ? Self.expandedHeight : Self.compactHeight
        let panelSize = NSSize(width: Self.panelWidth, height: panelHeight)
        
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        let selectionMidX = anchor.firstLine.midX
        var originX = selectionMidX - panelSize.width * 0.5
        originX = max(visibleFrame.minX + Self.marginPadding,
                      min(visibleFrame.maxX - Self.marginPadding - panelSize.width, originX))
        
        let aboveY = anchor.firstLine.maxY + 8
        let belowY = anchor.lastLine.minY - panelSize.height - 8
        
        let originY: CGFloat
        if aboveY + panelSize.height <= visibleFrame.maxY - Self.marginPadding {
            originY = aboveY
            self.model.pointsDownward = true
        } else {
            originY = max(visibleFrame.minY + Self.marginPadding, belowY)
            self.model.pointsDownward = false
        }
        
        let halfSpan = panelSize.width * 0.5 - 22
        let rawBeak = selectionMidX - (originX + panelSize.width * 0.5)
        self.model.beakOffsetX = max(-halfSpan, min(halfSpan, rawBeak))
        
        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize), display: true)
    }
    
    
    private func selectionScreenBounds(
        in textView: EditorTextView,
        window: NSWindow,
        range: NSRange
    ) -> (firstLine: NSRect, lastLine: NSRect)? {
        
        let rects = textView.boundingRects(for: range).filter { !$0.isEmpty }
        guard let first = rects.first, let last = rects.last else { return nil }
        
        let firstInWindow = textView.convert(first, to: nil)
        let lastInWindow = textView.convert(last, to: nil)
        
        let visibleInView = textView.visibleRect
        guard first.intersects(visibleInView) || last.intersects(visibleInView) else {
            return nil
        }
        
        return (
            firstLine: window.convertToScreen(firstInWindow),
            lastLine: window.convertToScreen(lastInWindow)
        )
    }
    
    
    private func attachObservers(textView: EditorTextView, window: NSWindow) {
        
        self.detachObservers()
        
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            self.scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismiss(animated: false)
                }
            }
        }
        
        self.windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss(animated: false)
            }
        }
    }
    
    
    private func detachObservers() {
        
        if let scrollObserver = self.scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        if let windowResignObserver = self.windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
            self.windowResignObserver = nil
        }
    }
}


// MARK: - SwiftUI Frosted Nine-Color Palette

private struct NotesTextColorPaletteRootView: View {
    
    let model: NotesTextColorPaletteModel
    let onSelectPreset: (HighlightColor) -> Void
    let onToggleRainbow: () -> Void
    let onChangeHue: (Double) -> Void
    let onSelectPassage: (NotesColoredPassageItem) -> Void
    
    
    var body: some View {
        ZStack(alignment: self.model.pointsDownward ? .bottom : .top) {
            // Rotated square beak rendered behind card edge so no interior stroke seam appears
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    self.model.pointsDownward
                        ? Color(red: 0.141, green: 0.145, blue: 0.153).opacity(0.97)
                        : Color(red: 0.208, green: 0.212, blue: 0.220).opacity(0.94)
                )
                .frame(width: 12, height: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                )
                .rotationEffect(.degrees(45))
                .shadow(color: Color.black.opacity(0.28), radius: 5, y: 2)
                .offset(x: self.model.beakOffsetX, y: self.model.pointsDownward ? -1 : 1)
            
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 9) {
                    self.colorOrbGrid
                    
                    if !self.model.recentPassages.isEmpty {
                        self.recentPassagesList
                    } else {
                        self.emptyRecentPlaceholder
                    }
                }
                
                if self.model.isCustomHueExpanded {
                    self.rainbowHueSlider
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.208, green: 0.212, blue: 0.220).opacity(0.95),
                                Color(red: 0.141, green: 0.145, blue: 0.153).opacity(0.98),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        DarkHudBlurBackdrop()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .opacity(0.28)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.42), radius: 14, y: 7)
            .padding(.bottom, self.model.pointsDownward ? 6 : 0)
            .padding(.top, self.model.pointsDownward ? 0 : 6)
        }
        .scaleEffect(
            self.model.appears ? 1.0 : 0.84,
            anchor: self.model.pointsDownward ? .bottom : .top
        )
        .offset(y: self.model.appears ? 0 : (self.model.pointsDownward ? 5 : -5))
        .opacity(self.model.appears ? 1 : 0)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
    
    
    private var colorOrbGrid: some View {
        let presets = HighlightColor.palettePresets
        return VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { col in
                        let idx = row * 3 + col
                        if idx < presets.count {
                            self.presetOrbButton(presets[idx])
                        } else {
                            self.rainbowCustomOrbButton
                        }
                    }
                }
            }
        }
    }
    
    
    private func presetOrbButton(_ color: HighlightColor) -> some View {
        let isSelected = (self.model.selectedColor == color)
        let pair = color.orbGradientColors
        let inner = Color(nsColor: pair.inner)
        let outer = Color(nsColor: pair.outer)
        
        return Button {
            self.onSelectPreset(color)
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [inner, outer],
                            center: .center,
                            startRadius: 1,
                            endRadius: 9
                        )
                    )
                    .frame(width: 17, height: 17)
                    .shadow(color: outer.opacity(0.32), radius: 2.5)
                
                if isSelected {
                    Circle()
                        .strokeBorder(Color(red: 0.933, green: 0.933, blue: 0.937), lineWidth: 1.4)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 17, height: 17)
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.68), value: isSelected)
        }
        .buttonStyle(.plain)
        .help(color.localizedName)
    }
    
    
    private var rainbowCustomOrbButton: some View {
        let isCustomSelected: Bool = if case .customHue = self.model.selectedColor { true } else { false }
        let isActive = isCustomSelected || self.model.isCustomHueExpanded
        
        return Button(action: self.onToggleRainbow) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hue: 0.00, saturation: 0.78, brightness: 0.92),
                                Color(hue: 0.17, saturation: 0.78, brightness: 0.92),
                                Color(hue: 0.34, saturation: 0.78, brightness: 0.92),
                                Color(hue: 0.52, saturation: 0.78, brightness: 0.92),
                                Color(hue: 0.70, saturation: 0.78, brightness: 0.92),
                                Color(hue: 0.86, saturation: 0.78, brightness: 0.92),
                                Color(hue: 1.00, saturation: 0.78, brightness: 0.92),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 17, height: 17)
                
                Circle()
                    .fill(Color(red: 0.161, green: 0.165, blue: 0.180))  // #292a2e cutout
                    .frame(width: 8, height: 8)
                
                if isActive {
                    Circle()
                        .strokeBorder(Color(red: 0.933, green: 0.933, blue: 0.937), lineWidth: 1.4)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 17, height: 17)
        }
        .buttonStyle(.plain)
        .help(AppLanguage.text("自定义色相", en: "Custom Hue"))
    }
    
    
    private var recentPassagesList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(self.model.recentPassages) { item in
                let barColor = Color(nsColor: item.color.swatchColor)
                Button {
                    self.onSelectPassage(item)
                } label: {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(barColor)
                            .frame(width: 2, height: 8)
                        
                        Text(item.preview)
                            .font(.system(size: 10, weight: item.isActive ? .semibold : .regular))
                            .foregroundStyle(Color(red: 0.933, green: 0.933, blue: 0.937))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 5)
                    .frame(width: 108, height: 14, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(item.isActive ? Color.white.opacity(0.11) : Color.white.opacity(0.03))
                    )
                    .opacity(item.isActive ? 1.0 : 0.56)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    
    private var emptyRecentPlaceholder: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(AppLanguage.text("点击色点上色", en: "Pick a shade"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.74))
            Text(AppLanguage.text("可跳回最近段落", en: "Quick passage jumps"))
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.42))
        }
        .frame(width: 108, alignment: .leading)
        .padding(.top, 2)
    }
    
    
    private var rainbowHueSlider: some View {
        let thumbColor = Color(nsColor: HighlightColor.colorFromHSL(
            hueDegrees: self.model.customHue,
            saturation: 0.76,
            lightness: 0.72
        ))
        
        return GeometryReader { geo in
            let w = max(40, geo.size.width)
            let progress = CGFloat(HighlightColor.normalizedHue(self.model.customHue) / 360.0)
            let thumbX = max(7, min(w - 7, w * progress))
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: (0...6).map { idx in
                                Color(hue: Double(idx) / 6.0, saturation: 0.78, brightness: 0.90)
                            },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 8)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
                
                Circle()
                    .fill(thumbColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.8))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .position(x: thumbX, y: geo.size.height * 0.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = max(0, min(1, value.location.x / w))
                        self.onChangeHue(Double(clamped) * 360.0)
                    }
            )
        }
        .frame(height: 18)
    }
}


private struct DarkHudBlurBackdrop: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
