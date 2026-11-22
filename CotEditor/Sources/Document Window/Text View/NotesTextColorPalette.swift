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
    var isDarkAppearance: Bool = true
}


/// Non-activating quiet floating highlight bar inspired by Apple Notes.
///
/// Appears cleanly beside non-whitespace text selections without stealing first responder,
/// offering 8 crisp color swatches, a continuous rainbow hue ring, clear-highlight button,
/// and compact passage jumps only when colored passages already exist.
@MainActor
final class NotesTextColorPaletteController {
    
    static let shared = NotesTextColorPaletteController()
    
    private static let basePanelWidth: CGFloat = 244
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
    
    
    /// Returns whether `rawSelection` contains non-whitespace, non-inline-image text eligible for highlighting.
    nonisolated static func shouldPresent(for rawSelection: String) -> Bool {
        let trimmed = rawSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("⟦🖼"), trimmed.hasSuffix("⟧"), !trimmed.contains("\n") {
            return false
        }
        return true
    }
    
    
    /// Presents or updates the quiet floating highlight bar for the current selection.
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
        
        let nsString = textView.string as NSString
        let safeRange = NSIntersectionRange(selectedRange, NSRange(location: 0, length: nsString.length))
        guard safeRange.length > 0 else {
            self.dismiss(animated: false)
            return
        }
        
        let rawSelectedText = nsString.substring(with: safeRange)
        guard Self.shouldPresent(for: rawSelectedText) else {
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
        self.model.isDarkAppearance = window.effectiveAppearance.isDark
        
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
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                    self?.model.appears = true
                }
            }
        }
    }
    
    
    /// Dismisses the palette cleanly with an optional 130ms fade-out.
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
        
        withAnimation(.easeIn(duration: 0.13)) {
            self.model.appears = false
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.appears else { return }
            self.panel?.orderOut(nil)
            self.textView = nil
            self.document = nil
        }
        self.dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
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
        self.repositionIfVisible()
        textView.needsDisplay = true
    }
    
    
    private func handleClearHighlight() {
        
        guard let textView = self.textView,
              let document = self.document
        else { return }
        
        let range = self.clampedActiveRange(in: document)
        guard range.length > 0 else { return }
        
        document.removeHighlights(in: range)
        self.model.selectedColor = nil
        self.model.isCustomHueExpanded = false
        self.syncModel(from: document, selectedRange: range)
        self.repositionIfVisible()
        textView.needsDisplay = true
    }
    
    
    private func handleToggleRainbowSlider() {
        
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
            self.model.isCustomHueExpanded.toggle()
        }
        self.repositionIfVisible()
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
        self.repositionIfVisible()
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
    
    
    private func repositionIfVisible() {
        if let textView = self.textView,
           let window = textView.window,
           let anchor = self.selectionScreenBounds(in: textView, window: window, range: self.activeRange)
        {
            self.positionPanel(against: anchor, window: window)
        }
    }
    
    
    // MARK: Model & Layout Helpers
    
    private func clampedActiveRange(in document: Document) -> NSRange {
        
        NSIntersectionRange(self.activeRange, NSRange(location: 0, length: document.textStorage.length))
    }
    
    
    private func computedPanelSize() -> NSSize {
        let hasClear = (self.model.selectedColor != nil)
        let width: CGFloat = hasClear ? Self.basePanelWidth + 24 : Self.basePanelWidth
        var height: CGFloat = 52
        if self.model.isCustomHueExpanded {
            height += 26
        }
        if !self.model.recentPassages.isEmpty {
            height += 32
        }
        return NSSize(width: width, height: height)
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
        for mark in orderedMarks.prefix(3) {
            let safeRange = NSIntersectionRange(mark.range, wholeRange)
            guard safeRange.length > 0 else { continue }
            
            let raw = string.substring(with: safeRange)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            
            let preview = raw.count > 10 ? String(raw.prefix(9)) + "…" : raw
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
            onClear: { [weak self] in self?.handleClearHighlight() },
            onToggleRainbow: { [weak self] in self?.handleToggleRainbowSlider() },
            onChangeHue: { [weak self] hue in self?.handleCustomHueChanged(hue) },
            onSelectPassage: { [weak self] item in self?.handleJumpToPassage(item) }
        )
        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: self.computedPanelSize()),
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
        
        let panelSize = self.computedPanelSize()
        let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        
        let selectionMidX = anchor.firstLine.midX
        var originX = selectionMidX - panelSize.width * 0.5
        originX = max(visibleFrame.minX + Self.marginPadding,
                      min(visibleFrame.maxX - Self.marginPadding - panelSize.width, originX))
        
        let aboveY = anchor.firstLine.maxY + 6
        let belowY = anchor.lastLine.minY - panelSize.height - 6
        
        let originY: CGFloat
        if aboveY + panelSize.height <= visibleFrame.maxY - Self.marginPadding {
            originY = aboveY
            self.model.pointsDownward = true
        } else {
            originY = max(visibleFrame.minY + Self.marginPadding, belowY)
            self.model.pointsDownward = false
        }
        
        let halfSpan = panelSize.width * 0.5 - 20
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


// MARK: - Quiet Single-Row Highlight Bar (Unslopped: Zero Filler Copy, Zero Excess Shadows)

private struct NotesTextColorPaletteRootView: View {
    
    let model: NotesTextColorPaletteModel
    let onSelectPreset: (HighlightColor) -> Void
    let onClear: () -> Void
    let onToggleRainbow: () -> Void
    let onChangeHue: (Double) -> Void
    let onSelectPassage: (NotesColoredPassageItem) -> Void
    
    
    private var surfaceFill: Color {
        self.model.isDarkAppearance
            ? Color(red: 0.145, green: 0.145, blue: 0.153)
            : Color(red: 0.992, green: 0.992, blue: 0.996)
    }
    
    private var hairlineStroke: Color {
        self.model.isDarkAppearance
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.09)
    }
    
    private var primaryInk: Color {
        self.model.isDarkAppearance
            ? Color(red: 0.93, green: 0.93, blue: 0.94)
            : Color(red: 0.11, green: 0.11, blue: 0.12)
    }
    
    private var secondarySurface: Color {
        self.model.isDarkAppearance
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.045)
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(HighlightColor.palettePresets, id: \.self) { color in
                    self.presetSwatchButton(color)
                }
                
                self.rainbowCustomButton
                
                if self.model.selectedColor != nil {
                    Rectangle()
                        .fill(self.hairlineStroke)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 1)
                    
                    Button(action: self.onClear) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(self.primaryInk.opacity(0.70))
                            .frame(width: 18, height: 18)
                            .background(self.secondarySurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .help(AppLanguage.text("清除高亮", en: "Clear Highlight"))
                }
            }
            
            if self.model.isCustomHueExpanded {
                self.rainbowHueSlider
                    .transition(.opacity)
            }
            
            if !self.model.recentPassages.isEmpty {
                Rectangle()
                    .fill(self.hairlineStroke)
                    .frame(height: 0.75)
                
                HStack(spacing: 6) {
                    ForEach(self.model.recentPassages) { item in
                        self.recentPassageChip(item)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.surfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(self.hairlineStroke, lineWidth: 0.75)
        )
        .shadow(
            color: Color.black.opacity(self.model.isDarkAppearance ? 0.22 : 0.08),
            radius: 6,
            y: 2
        )
        .scaleEffect(
            self.model.appears ? 1.0 : 0.94,
            anchor: self.model.pointsDownward ? .bottom : .top
        )
        .offset(y: self.model.appears ? 0 : (self.model.pointsDownward ? 4 : -4))
        .opacity(self.model.appears ? 1 : 0)
        .padding(4)
    }
    
    
    private func presetSwatchButton(_ color: HighlightColor) -> some View {
        let isSelected = (self.model.selectedColor == color)
        let swatch = Color(nsColor: color.swatchColor)
        
        return Button {
            self.onSelectPreset(color)
        } label: {
            ZStack {
                Circle()
                    .fill(swatch)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                
                if isSelected {
                    Circle()
                        .strokeBorder(self.primaryInk, lineWidth: 1.5)
                        .frame(width: 21, height: 21)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(color.localizedName)
    }
    
    
    private var rainbowCustomButton: some View {
        let isCustomSelected: Bool = if case .customHue = self.model.selectedColor { true } else { false }
        let isActive = isCustomSelected || self.model.isCustomHueExpanded
        
        return Button(action: self.onToggleRainbow) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(hue: 0.00, saturation: 0.72, brightness: 0.90),
                                Color(hue: 0.17, saturation: 0.72, brightness: 0.90),
                                Color(hue: 0.34, saturation: 0.72, brightness: 0.90),
                                Color(hue: 0.52, saturation: 0.72, brightness: 0.90),
                                Color(hue: 0.70, saturation: 0.72, brightness: 0.90),
                                Color(hue: 0.86, saturation: 0.72, brightness: 0.90),
                                Color(hue: 1.00, saturation: 0.72, brightness: 0.90),
                            ],
                            center: .center
                        )
                    )
                    .frame(width: 16, height: 16)
                
                Circle()
                    .fill(self.surfaceFill)
                    .frame(width: 7, height: 7)
                
                if isActive {
                    Circle()
                        .strokeBorder(self.primaryInk, lineWidth: 1.5)
                        .frame(width: 21, height: 21)
                }
            }
            .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(AppLanguage.text("自定义色相", en: "Custom Hue"))
    }
    
    
    private func recentPassageChip(_ item: NotesColoredPassageItem) -> some View {
        let barColor = Color(nsColor: item.color.swatchColor)
        return Button {
            self.onSelectPassage(item)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(barColor)
                    .frame(width: 5, height: 5)
                Text(item.preview)
                    .font(.system(size: 11, weight: item.isActive ? .medium : .regular))
                    .foregroundStyle(self.primaryInk.opacity(item.isActive ? 0.95 : 0.70))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(item.isActive ? self.secondarySurface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(self.hairlineStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
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
                                Color(hue: Double(idx) / 6.0, saturation: 0.74, brightness: 0.88)
                            },
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 6)
                
                Circle()
                    .fill(thumbColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.6))
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
        .frame(height: 16)
    }
}
