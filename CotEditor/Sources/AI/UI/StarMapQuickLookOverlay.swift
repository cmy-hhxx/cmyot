//
//  StarMapQuickLookOverlay.swift
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
import Observation
import SwiftUI

// MARK: - Pure Deterministic Quick Look Spatial Geometry

/// Deterministic macOS Finder Quick Look spatial transition geometry:
/// computes panel dimensions, origin-card zoom-out/retract transforms, and safe titlebar drag bounds.
nonisolated enum StarMapQuickLookGeometry {
    
    struct CollapsedTransform: Equatable, Sendable {
        let offset: CGSize
        let scale: CGFloat
    }
    
    static let compactMaxWidth: CGFloat = 780
    static let compactMaxHeight: CGFloat = 580
    static let expandedMaxWidth: CGFloat = 1140
    static let dismissRetractDurationMs: Int = 220
    
    
    static func panelSize(in containerSize: CGSize, isExpanded: Bool) -> CGSize {
        let safeW = max(360, containerSize.width)
        let safeH = max(280, containerSize.height)
        if isExpanded {
            let w = min(Self.expandedMaxWidth, max(480, safeW - 44))
            let h = max(360, safeH - 48)
            return CGSize(width: w, height: h)
        }
        let w = min(Self.compactMaxWidth, max(440, safeW - 76))
        let h = min(Self.compactMaxHeight, max(340, safeH - 96))
        return CGSize(width: w, height: h)
    }
    
    
    /// Computes the collapsed starting/ending transform anchored to the source Star-Map card.
    /// When the card is off-screen or unavailable, falls back to a crisp Apple center-lift transform.
    static func collapsedTransform(
        from anchorRect: CGRect?,
        panelSize: CGSize,
        in containerSize: CGSize
    ) -> CollapsedTransform {
        guard let anchorRect,
              anchorRect.width > 12,
              anchorRect.height > 12,
              containerSize.width > 120,
              containerSize.height > 120
        else {
            return CollapsedTransform(offset: CGSize(width: 0, height: 14), scale: 0.88)
        }
        
        let marginX: CGFloat = 48
        let marginY: CGFloat = 48
        let clampedX = min(max(anchorRect.midX, marginX), max(marginX, containerSize.width - marginX))
        let clampedY = min(max(anchorRect.midY, marginY), max(marginY, containerSize.height - marginY))
        
        let panelCenterX = containerSize.width * 0.5
        let panelCenterY = containerSize.height * 0.5
        let dx = clampedX - panelCenterX
        let dy = clampedY - panelCenterY
        
        let widthRatio = anchorRect.width / max(1, panelSize.width)
        let heightRatio = anchorRect.height / max(1, panelSize.height)
        let rawScale = max(widthRatio, heightRatio)
        let scale = min(0.46, max(0.24, rawScale))
        
        return CollapsedTransform(offset: CGSize(width: dx, height: dy), scale: scale)
    }
    
    
    /// Keeps a dragged floating Quick Look panel reachable inside the window bounds.
    static func clampedDragOffset(
        _ rawOffset: CGSize,
        panelSize: CGSize,
        in containerSize: CGSize
    ) -> CGSize {
        let maxX = max(0, (containerSize.width - panelSize.width) * 0.5 + panelSize.width * 0.35)
        let maxY = max(0, (containerSize.height - panelSize.height) * 0.5 + 24)
        return CGSize(
            width: min(maxX, max(-maxX, rawOffset.width)),
            height: min(maxY, max(-maxY, rawOffset.height))
        )
    }
}


// MARK: - Interruptible Quick Look Presentation Controller

/// Manages mount/unmount lifetime for Apple-style Quick Look so the panel retains its content
/// during the retract-to-card spring animation and reverses smoothly if Spacebar is tapped mid-flight.
@MainActor @Observable final class StarMapQuickLookController {
    
    /// Item ID currently mounted in the overlay (kept alive during the ~220ms retract animation).
    private(set) var mountedID: String?
    /// Logical presentation flag (`true` while open/opening, `false` while closing/closed).
    private(set) var isVisible: Bool = false
    /// Toggled via the Finder-style expand button or double-clicking the titlebar.
    var isExpanded: Bool = false
    /// Live screen rect of the active card in container coordinates for origin-zoom & retract targeting.
    var anchorRect: CGRect?
    
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    
    var isOpen: Bool {
        self.mountedID != nil && self.isVisible
    }
    
    var activeID: String? {
        self.isVisible ? self.mountedID : nil
    }
    
    
    func open(_ id: String, anchorRect: CGRect? = nil) {
        self.dismissTask?.cancel()
        self.dismissTask = nil
        if let anchorRect {
            self.anchorRect = anchorRect
        }
        if self.mountedID != id {
            self.mountedID = id
        }
        self.isVisible = true
    }
    
    
    func step(to id: String, anchorRect: CGRect? = nil) {
        guard self.mountedID != nil else { return }
        self.dismissTask?.cancel()
        self.dismissTask = nil
        if let anchorRect {
            self.anchorRect = anchorRect
        }
        self.mountedID = id
        self.isVisible = true
    }
    
    
    func close(animated: Bool = true) {
        guard self.mountedID != nil else { return }
        self.dismissTask?.cancel()
        self.dismissTask = nil
        if !animated {
            self.isVisible = false
            self.mountedID = nil
            self.isExpanded = false
            return
        }
        self.isVisible = false
        self.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(StarMapQuickLookGeometry.dismissRetractDurationMs))
            guard let self, !Task.isCancelled, !self.isVisible else { return }
            self.mountedID = nil
            self.isExpanded = false
        }
    }
    
    
    func toggle(_ id: String, anchorRect: CGRect? = nil) {
        if self.isOpen {
            self.close(animated: true)
        } else {
            self.open(id, anchorRect: anchorRect)
        }
    }
    
    
    func cancelPendingDismiss() {
        self.dismissTask?.cancel()
        self.dismissTask = nil
    }
}


// MARK: - Apple macOS Quick Look Floating Overlay

/// Native macOS Finder Quick Look-inspired Spacebar preview panel:
/// - Springs smoothly out of the selected card's exact screen coordinates and retracts right back into it on close
/// - Vibrant translucent utility titlebar with centered title, compact segmented prev/next switcher, and expand toggle
/// - Draggable floating panel over a whisper-light scrim so the Star Map context remains legible underneath
struct StarMapQuickLookOverlay<HeaderActions: View, BodyContent: View>: View {
    
    let isPresented: Bool
    let title: String
    let subtitle: String
    let indexText: String?
    let anchorRect: CGRect?
    let isExpanded: Bool
    let canStepPrevious: Bool
    let canStepNext: Bool
    let onToggleExpand: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void
    @ViewBuilder let headerActions: () -> HeaderActions
    @ViewBuilder let bodyContent: () -> BodyContent
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var visualProgress: CGFloat = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize?
    
    
    init(
        isPresented: Bool = true,
        title: String,
        subtitle: String,
        indexText: String? = nil,
        anchorRect: CGRect? = nil,
        isExpanded: Bool = false,
        canStepPrevious: Bool,
        canStepNext: Bool,
        onToggleExpand: @escaping () -> Void = {},
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onClose: @escaping () -> Void,
        @ViewBuilder headerActions: @escaping () -> HeaderActions,
        @ViewBuilder bodyContent: @escaping () -> BodyContent
    ) {
        self.isPresented = isPresented
        self.title = title
        self.subtitle = subtitle
        self.indexText = indexText
        self.anchorRect = anchorRect
        self.isExpanded = isExpanded
        self.canStepPrevious = canStepPrevious
        self.canStepNext = canStepNext
        self.onToggleExpand = onToggleExpand
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onClose = onClose
        self.headerActions = headerActions
        self.bodyContent = bodyContent
    }
    
    
    var body: some View {
        let isDark = (self.colorScheme == .dark)
        let tokens = DashPalette.editorialTokens(isDark: isDark)
        let p = self.visualProgress
        
        GeometryReader { geo in
            let size = StarMapQuickLookGeometry.panelSize(in: geo.size, isExpanded: self.isExpanded)
            let collapsed = StarMapQuickLookGeometry.collapsedTransform(
                from: self.anchorRect,
                panelSize: size,
                in: geo.size
            )
            let clampedDrag = self.isExpanded
                ? .zero
                : StarMapQuickLookGeometry.clampedDragOffset(self.dragOffset, panelSize: size, in: geo.size)
            let currentScale = collapsed.scale + (1.0 - collapsed.scale) * p
            let currentOffsetX = collapsed.offset.width * (1.0 - p) + clampedDrag.width * p
            let currentOffsetY = collapsed.offset.height * (1.0 - p) + clampedDrag.height * p
            let panelOpacity = min(1.0, max(0.0, p * 1.45))
            
            ZStack {
                // Whisper-light macOS focus veil so the Star Map stays clearly visible underneath.
                Color.black
                    .opacity((isDark ? 0.28 : 0.085) * p)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        self.onClose()
                    }
                
                VStack(spacing: 0) {
                    self.titleBar(tokens: tokens, isDark: isDark, panelSize: size, containerSize: geo.size)
                    
                    Rectangle()
                        .fill(Color.primary.opacity(isDark ? 0.10 : 0.08))
                        .frame(height: 0.75)
                    
                    self.bodyContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor).opacity(isDark ? 0.94 : 0.985))
                }
                .frame(width: size.width, height: size.height)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isDark ? 0.14 : 0.65),
                            lineWidth: 0.75
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isDark ? 0.22 : 0.12),
                            lineWidth: 0.5
                        )
                        .allowsHitTesting(false)
                )
                .shadow(color: Color.black.opacity(isDark ? 0.44 : 0.11), radius: 6, y: 2)
                .shadow(color: Color.black.opacity(isDark ? 0.52 : 0.16), radius: 32, y: 16)
                .scaleEffect(currentScale, anchor: .center)
                .offset(x: currentOffsetX, y: currentOffsetY)
                .opacity(panelOpacity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(self.isPresented)
        .onAppear {
            self.visualProgress = 0
            if self.isPresented {
                withAnimation(.spring(response: 0.27, dampingFraction: 0.88, blendDuration: 0)) {
                    self.visualProgress = 1
                }
            }
        }
        .onChange(of: self.isPresented) { _, presented in
            if presented {
                withAnimation(.spring(response: 0.27, dampingFraction: 0.88, blendDuration: 0)) {
                    self.visualProgress = 1
                }
            } else {
                withAnimation(.spring(response: 0.21, dampingFraction: 0.94, blendDuration: 0)) {
                    self.visualProgress = 0
                }
            }
        }
        .onChange(of: self.isExpanded) { _, expanded in
            if expanded {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.90, blendDuration: 0)) {
                    self.dragOffset = .zero
                }
            }
        }
    }
    
    
    // MARK: Native Utility Titlebar
    
    private func titleBar(
        tokens: StudioColorTokens,
        isDark: Bool,
        panelSize: CGSize,
        containerSize: CGSize
    ) -> some View {
        ZStack {
            // Centered macOS utility window title & metadata
            VStack(spacing: 1.5) {
                Text(self.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !self.subtitle.isEmpty {
                    Text(self.subtitle)
                        .font(.system(size: 10.5, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(tokens.primaryInk.opacity(0.50))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 196)
            .allowsHitTesting(false)
            
            HStack(spacing: 8) {
                // Left: Apple close + expand + compact segmented pager
                HStack(spacing: 6) {
                    QuickLookChromeButton(
                        symbol: "xmark",
                        symbolSize: 10,
                        helpText: "关闭预览（空格 / Esc）",
                        tokens: tokens,
                        action: self.onClose
                    )
                    
                    QuickLookChromeButton(
                        symbol: self.isExpanded
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        symbolSize: 9.5,
                        helpText: self.isExpanded ? "恢复紧凑尺寸" : "展开阅读尺寸",
                        tokens: tokens
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.90, blendDuration: 0)) {
                            self.onToggleExpand()
                        }
                    }
                    
                    if self.canStepPrevious || self.canStepNext || self.indexText != nil {
                        self.segmentedPager(tokens: tokens, isDark: isDark)
                    }
                }
                
                Spacer(minLength: 12)
                
                // Right: concise document/report actions
                self.headerActions()
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 46)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.90, blendDuration: 0)) {
                self.onToggleExpand()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    guard !self.isExpanded else { return }
                    if self.dragStartOffset == nil {
                        self.dragStartOffset = self.dragOffset
                    }
                    if let base = self.dragStartOffset {
                        let raw = CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height
                        )
                        self.dragOffset = StarMapQuickLookGeometry.clampedDragOffset(
                            raw,
                            panelSize: panelSize,
                            in: containerSize
                        )
                    }
                }
                .onEnded { _ in
                    self.dragStartOffset = nil
                }
        )
    }
    
    
    private func segmentedPager(tokens: StudioColorTokens, isDark: Bool) -> some View {
        HStack(spacing: 0) {
            Button(action: self.onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(self.canStepPrevious ? 0.78 : 0.25))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(self.canStepPrevious ? .link : .default)
            .disabled(!self.canStepPrevious)
            
            Rectangle()
                .fill(Color.primary.opacity(isDark ? 0.12 : 0.09))
                .frame(width: 0.75, height: 12)
            
            Button(action: self.onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tokens.primaryInk.opacity(self.canStepNext ? 0.78 : 0.25))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(self.canStepNext ? .link : .default)
            .disabled(!self.canStepNext)
            
            if let indexText = self.indexText, !indexText.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(isDark ? 0.12 : 0.09))
                    .frame(width: 0.75, height: 12)
                Text(indexText)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(tokens.primaryInk.opacity(0.56))
                    .padding(.horizontal, 7)
            }
        }
        .frame(height: 24)
        .background(
            Color.primary.opacity(isDark ? 0.08 : 0.048),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}


private struct QuickLookChromeButton: View {
    
    let symbol: String
    let symbolSize: CGFloat
    let helpText: String
    let tokens: StudioColorTokens
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.symbol)
                .font(.system(size: self.symbolSize, weight: .semibold))
                .foregroundStyle(self.tokens.primaryInk.opacity(self.isHovered ? 0.90 : 0.68))
                .frame(width: 24, height: 24)
                .background(
                    Color.primary.opacity(self.isHovered ? 0.10 : 0.055),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(self.helpText)
        .onHover { hovering in
            if hovering != self.isHovered {
                self.isHovered = hovering
            }
        }
    }
}
