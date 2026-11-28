//
//  SidebarSettingsPrimitives.swift
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

enum SettingsDesignTokens {
    
    static let sidebarWidth: CGFloat = 204
    static let detailWidth: CGFloat = 575 // 204 + 1 + 575 == 780
    static let contentPadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 18
    static let sectionTitleSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 42
    static let cardCornerRadius: CGFloat = 12
    static let segmentedWidth: CGFloat = 188
    static let controlWidth: CGFloat = 188
    static let sliderWidth: CGFloat = 140
    static let readoutWidth: CGFloat = 40
    
    static let sidebarClusters: [[SidebarSettingsItem]] = [
        [.profile, .general, .appearance, .typography, .editing],
        [.models, .bots, .memory, .scheduledTasks, .keyBindings, .pass],
    ]
}


struct SidebarVisualEffectBackdrop: NSViewRepresentable {
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}


struct SettingsSquircleBadge: View {
    
    let symbolName: String
    let color: Color
    let size: CGFloat
    var isSelected: Bool = false
    
    var body: some View {
        let radius = max(5, self.size * 0.27)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [self.color.opacity(0.88), self.color],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: self.size, height: self.size)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(self.isSelected ? 0.50 : 0.32), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .overlay(
                Image(systemName: self.symbolName)
                    .font(.system(size: self.size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: self.color.opacity(0.22), radius: 1.5, y: 0.5)
    }
}


struct SettingsGroupCard<Content: View>: View {
    
    var title: String?
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignTokens.sectionTitleSpacing) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                self.content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.cardCornerRadius, style: .continuous)
                    .fill(self.colorScheme == .dark ? Color.white.opacity(0.055) : Color.white)
                    .shadow(
                        color: self.colorScheme == .dark ? Color.clear : Color.black.opacity(0.025),
                        radius: 2,
                        y: 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.cardCornerRadius, style: .continuous)
                    .strokeBorder(self.colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
    }
}


struct SettingsItemRow<Control: View>: View {
    
    let label: String
    @ViewBuilder let control: () -> Control
    
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(self.label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 12)
            
            self.control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: SettingsDesignTokens.rowHeight)
    }
}


struct SettingsRowDivider: View {
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Rectangle()
            .fill(self.colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}


// MARK: - AppKit Pan/Magnify/Drop Overlay

/// AppKit interaction surface that returns `mouseDownCanMoveWindow == false` so dragging
/// inside preview stages pans artwork smoothly without moving the Settings window.
internal final class WallpaperFramingInteractionNSView: NSView {
    
    var isInteractive: Bool = true {
        didSet {
            if self.isInteractive != oldValue {
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnd: (() -> Void)?
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)?
    var onScrollZoom: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onDropTargetedChange: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?
    var onDropImages: (([NSImage]) -> Void)?
    
    private var dragStartPoint: NSPoint?
    private var isCurrentlyDragging = false
    
    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.registerForDraggedTypes([.fileURL, .tiff, .png])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func resetCursorRects() {
        super.resetCursorRects()
        guard self.isInteractive else { return }
        self.addCursorRect(self.bounds, cursor: self.isCurrentlyDragging ? .closedHand : .openHand)
    }
    
    override func mouseDown(with event: NSEvent) {
        guard self.isInteractive else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2, let onDoubleClick = self.onDoubleClick {
            onDoubleClick()
            return
        }
        let pt = self.convert(event.locationInWindow, from: nil)
        self.dragStartPoint = pt
        self.isCurrentlyDragging = true
        self.window?.invalidateCursorRects(for: self)
        NSCursor.closedHand.set()
        self.onDragStart?()
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard self.isInteractive, let start = self.dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        let pt = self.convert(event.locationInWindow, from: nil)
        let translation = CGSize(width: pt.x - start.x, height: pt.y - start.y)
        self.onDragChanged?(translation)
    }
    
    override func mouseUp(with event: NSEvent) {
        let wasDragging = self.isCurrentlyDragging
        self.dragStartPoint = nil
        self.isCurrentlyDragging = false
        self.window?.invalidateCursorRects(for: self)
        if self.isInteractive {
            NSCursor.openHand.set()
        }
        if wasDragging {
            self.onDragEnd?()
        } else {
            super.mouseUp(with: event)
        }
    }
    
    override func magnify(with event: NSEvent) {
        guard self.isInteractive else {
            super.magnify(with: event)
            return
        }
        self.onMagnify?(event.magnification, event.phase)
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard self.isInteractive, let onScrollZoom = self.onScrollZoom else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.004 : 0.025)
        if abs(delta) > 0.0001 {
            onScrollZoom(delta)
        }
    }
    
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let hasURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        guard hasURL || hasImage else { return [] }
        self.onDropTargetedChange?(true)
        return .copy
    }
    
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        self.onDropTargetedChange?(false)
    }
    
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        self.onDropTargetedChange?(false)
    }
    
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        self.onDropTargetedChange?(false)
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty
        {
            self.onDropURLs?(urls)
            return true
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !images.isEmpty
        {
            self.onDropImages?(images)
            return true
        }
        return false
    }
}


internal struct WallpaperFramingInteractionOverlay: NSViewRepresentable {
    
    var isInteractive: Bool = true
    var onDragStart: (() -> Void)? = nil
    var onDragChanged: ((CGSize) -> Void)? = nil
    var onDragEnd: (() -> Void)? = nil
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)? = nil
    var onScrollZoom: ((CGFloat) -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onDropTargetedChange: ((Bool) -> Void)? = nil
    var onDropURLs: (([URL]) -> Void)? = nil
    var onDropImages: (([NSImage]) -> Void)? = nil
    
    func makeNSView(context: Context) -> WallpaperFramingInteractionNSView {
        let view = WallpaperFramingInteractionNSView()
        self.applyCallbacks(to: view)
        return view
    }
    
    func updateNSView(_ nsView: WallpaperFramingInteractionNSView, context: Context) {
        self.applyCallbacks(to: nsView)
    }
    
    private func applyCallbacks(to view: WallpaperFramingInteractionNSView) {
        view.isInteractive = self.isInteractive
        view.onDragStart = self.onDragStart
        view.onDragChanged = self.onDragChanged
        view.onDragEnd = self.onDragEnd
        view.onMagnify = self.onMagnify
        view.onScrollZoom = self.onScrollZoom
        view.onDoubleClick = self.onDoubleClick
        view.onDropTargetedChange = self.onDropTargetedChange
        view.onDropURLs = self.onDropURLs
        view.onDropImages = self.onDropImages
    }
}
