//
//  EditorContextMenuViews.swift
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
import Foundation

// MARK: - Pure Layout Metrics & Context State

/// Shared width & rhythm constants so every custom row inside editor & image context menus aligns on one grid.
nonisolated enum EditorContextMenuMetrics {
    
    static let menuWidth: CGFloat = 278
    static let horizontalInset: CGFloat = 10
    static let dockHeight: CGFloat = 52
    static let featuredRowHeight: CGFloat = 38
    static let chipStripHeight: CGFloat = 34
    static let imageZoomRowHeight: CGFloat = 68
}


/// Deterministic layout geometry for `ContextMenuQuickHighlightRowView`, guaranteeing
/// zero icon clipping, uniform spacing, and generous clearance around the vertical divider.
nonisolated enum QuickHighlightRowMetrics {
    
    static let maxQuickSwatches: Int = 7
    static let height: CGFloat = 34
    static let leadingPadding: CGFloat = 14
    static let leadingIconWidth: CGFloat = 16
    static let iconToSwatchesGap: CGFloat = 10
    static let swatchSize: CGFloat = 18
    static let swatchSpacing: CGFloat = 3
    static let swatchesToSeparatorMinGap: CGFloat = 10
    static let separatorWidth: CGFloat = 1
    static let separatorHeight: CGFloat = 14
    static let separatorToToolsGap: CGFloat = 8
    static let toolButtonSize: CGFloat = 20
    static let toolsSpacing: CGFloat = 2
    static let trailingPadding: CGFloat = 12
    
    static func minimumWidth(swatchCount: Int) -> CGFloat {
        let count = max(0, min(self.maxQuickSwatches, swatchCount))
        let swatchesW = count > 0
            ? CGFloat(count) * self.swatchSize + CGFloat(max(0, count - 1)) * self.swatchSpacing
            : 0
        return self.leadingPadding
            + self.leadingIconWidth
            + self.iconToSwatchesGap
            + swatchesW
            + self.swatchesToSeparatorMinGap
            + self.separatorWidth
            + self.separatorToToolsGap
            + self.toolButtonSize
            + self.toolsSpacing
            + self.toolButtonSize
            + self.trailingPadding
    }
}


/// Pure state snapshot governing enablement, visibility, and contextual promotion in the editor right-click menu.
nonisolated struct EditorContextMenuState: Equatable, Sendable {
    
    let isEditable: Bool
    let isEmptyDocument: Bool
    let hasSelection: Bool
    let selectedCharacterCount: Int
    let canHighlightSelection: Bool
    let hasClipboardText: Bool
    let hasClipboardImage: Bool
    let supportsInlineImages: Bool
    let hasTable: Bool
    let splitPaneCount: Int
    let showsLineNumber: Bool
    let hasDocumentController: Bool
    
    var canCut: Bool { self.isEditable && self.hasSelection }
    var canCopy: Bool { self.hasSelection }
    var canPaste: Bool { self.isEditable && (self.hasClipboardText || (self.supportsInlineImages && self.hasClipboardImage)) }
    var canSelectAll: Bool { !self.isEmptyDocument }
    var showsHighlightBar: Bool { self.hasDocumentController && self.isEditable && self.canHighlightSelection }
    var canCleanStructure: Bool { self.isEditable && !self.isEmptyDocument }
    var canSemanticRestructure: Bool { !self.isEmptyDocument }
    var canAlignTable: Bool { self.isEditable && !self.isEmptyDocument }
    var canInteractiveChart: Bool { self.hasSelection || self.hasTable }
    var canFlowPresentation: Bool { self.hasSelection }
    var canInsertInlineImage: Bool { self.isEditable && self.supportsInlineImages }
    var canEditLines: Bool { self.isEditable && !self.isEmptyDocument }
    var showsClipboardImageHint: Bool { self.isEditable && self.supportsInlineImages && self.hasClipboardImage }
    
    func butlerContextBadge(isEnglish: Bool) -> String {
        if self.hasSelection {
            return isEnglish ? "\(self.selectedCharacterCount) ch" : "\(self.selectedCharacterCount) 字"
        }
        if self.isEmptyDocument {
            return isEnglish ? "Empty" : "空文档"
        }
        return isEnglish ? "Doc" : "全文"
    }
}


// MARK: - Cached SF Symbol Factory

@MainActor
enum EditorContextMenuSymbols {
    
    private static var cache: [String: NSImage] = [:]
    
    static func image(
        named name: String,
        pointSize: CGFloat = 13,
        weight: NSFont.Weight = .medium
    ) -> NSImage? {
        let key = "\(name)|\(pointSize)|\(weight.rawValue)"
        if let cached = self.cache[key] {
            return cached
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return nil }
        symbol.isTemplate = true
        self.cache[key] = symbol
        return symbol
    }
}


// MARK: - Top 4-Tile Action Dock

struct ContextMenuDockAction {
    
    let title: String
    let symbolName: String
    let toolTip: String
    let isEnabled: Bool
    let isDestructive: Bool
    let showsAccentDot: Bool
    let onAction: () -> Void
    
    init(
        title: String,
        symbolName: String,
        toolTip: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        showsAccentDot: Bool = false,
        onAction: @escaping () -> Void
    ) {
        self.title = title
        self.symbolName = symbolName
        self.toolTip = toolTip
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.showsAccentDot = showsAccentDot
        self.onAction = onAction
    }
}


final class ContextMenuActionDockView: NSView {
    
    private let actions: [ContextMenuDockAction]
    private var tileViews: [ContextMenuDockTileButton] = []
    private var hoveredIndex: Int?
    
    init(actions: [ContextMenuDockAction], width: CGFloat = EditorContextMenuMetrics.menuWidth) {
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: EditorContextMenuMetrics.dockHeight))
        self.autoresizingMask = [.width]
        
        let container = NSStackView()
        container.orientation = .horizontal
        container.distribution = .fillEqually
        container.alignment = .centerY
        container.spacing = 2
        container.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: EditorContextMenuMetrics.horizontalInset + 3),
            container.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -(EditorContextMenuMetrics.horizontalInset + 3)),
            container.topAnchor.constraint(equalTo: self.topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -4),
        ])
        
        for (index, action) in actions.enumerated() {
            let tile = ContextMenuDockTileButton(action: action) { [weak self] isHovered in
                guard let self else { return }
                self.hoveredIndex = isHovered ? index : (self.hoveredIndex == index ? nil : self.hoveredIndex)
                self.needsDisplay = true
            }
            self.tileViews.append(tile)
            container.addArrangedSubview(tile)
            NSLayoutConstraint.activate([
                tile.heightAnchor.constraint(equalTo: container.heightAnchor),
            ])
        }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let railRect = NSRect(
            x: EditorContextMenuMetrics.horizontalInset,
            y: 2,
            width: self.bounds.width - EditorContextMenuMetrics.horizontalInset * 2,
            height: self.bounds.height - 4
        )
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let railFill = isDark
            ? NSColor.white.withAlphaComponent(0.065)
            : NSColor.black.withAlphaComponent(0.042)
        let railBorder = isDark
            ? NSColor.white.withAlphaComponent(0.11)
            : NSColor.black.withAlphaComponent(0.08)
        
        let railPath = NSBezierPath(roundedRect: railRect, xRadius: 9, yRadius: 9)
        railFill.setFill()
        railPath.fill()
        railBorder.setStroke()
        railPath.lineWidth = 0.5
        railPath.stroke()
        
        // Crisp recessed vertical hairline separators between adjacent non-hovered tiles
        guard self.actions.count > 1 else { return }
        let dividerColor = isDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.08)
        dividerColor.setFill()
        
        let innerW = railRect.width - 6
        let step = innerW / CGFloat(self.actions.count)
        let divHeight: CGFloat = 20
        let divY = railRect.midY - divHeight * 0.5
        for idx in 1..<self.actions.count {
            if self.hoveredIndex == idx || self.hoveredIndex == idx - 1 {
                continue
            }
            let x = round(railRect.minX + 3 + step * CGFloat(idx))
            NSRect(x: x, y: divY, width: 0.5, height: divHeight).fill()
        }
    }
}


private final class ContextMenuDockTileButton: NSControl {
    
    private let actionModel: ContextMenuDockAction
    private let iconImage: NSImage?
    private let onHoverChanged: (Bool) -> Void
    private var isHovered = false
    private var isPressed = false
    
    init(action: ContextMenuDockAction, onHoverChanged: @escaping (Bool) -> Void) {
        self.actionModel = action
        self.iconImage = EditorContextMenuSymbols.image(named: action.symbolName, pointSize: 13.5, weight: .medium)
        self.onHoverChanged = onHoverChanged
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.toolTip = action.toolTip
        self.isEnabled = action.isEnabled
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard self.actionModel.isEnabled else { return }
        self.isHovered = true
        self.onHoverChanged(true)
        self.needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        self.isHovered = false
        self.isPressed = false
        self.onHoverChanged(false)
        self.needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        guard self.actionModel.isEnabled else { return }
        self.isPressed = true
        self.needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard self.actionModel.isEnabled else { return }
        let local = self.convert(event.locationInWindow, from: nil)
        let inside = self.bounds.contains(local)
        if inside != self.isPressed {
            self.isPressed = inside
            self.needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard self.actionModel.isEnabled else { return }
        let local = self.convert(event.locationInWindow, from: nil)
        self.isPressed = false
        self.needsDisplay = true
        if self.bounds.contains(local) {
            self.actionModel.onAction()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let enabled = self.actionModel.isEnabled
        
        if enabled && (self.isHovered || self.isPressed) {
            let fill: NSColor
            if self.actionModel.isDestructive {
                fill = NSColor.systemRed.withAlphaComponent(self.isPressed ? 0.22 : 0.14)
            } else if isDark {
                fill = NSColor.white.withAlphaComponent(self.isPressed ? 0.18 : 0.12)
            } else {
                fill = NSColor.black.withAlphaComponent(self.isPressed ? 0.12 : 0.075)
            }
            fill.setFill()
            NSBezierPath(roundedRect: self.bounds, xRadius: 7, yRadius: 7).fill()
        }
        
        let foreground: NSColor
        if !enabled {
            foreground = NSColor.labelColor.withAlphaComponent(0.32)
        } else if self.actionModel.isDestructive && (self.isHovered || self.isPressed) {
            foreground = .systemRed
        } else if self.isHovered || self.isPressed {
            foreground = .labelColor
        } else {
            foreground = NSColor.labelColor.withAlphaComponent(0.86)
        }
        
        // Icon centered in upper half
        if let icon = self.iconImage {
            let size = icon.size
            let iconRect = NSRect(
                x: round((self.bounds.width - size.width) * 0.5),
                y: round(self.bounds.height * 0.50),
                width: size.width,
                height: size.height
            )
            drawTintedTemplate(icon, color: foreground, in: iconRect)
            
            if enabled && self.actionModel.showsAccentDot {
                let dotRect = NSRect(x: iconRect.maxX + 1.5, y: iconRect.maxY - 4.5, width: 5, height: 5)
                StudioPaletteManager.shared.activeNSAccentColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
        
        // Concise label centered in lower half
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: foreground,
        ]
        let label = NSAttributedString(string: self.actionModel.title, attributes: attrs)
        let labelSize = label.size()
        label.draw(at: NSPoint(
            x: round((self.bounds.width - labelSize.width) * 0.5),
            y: round(self.bounds.height * 0.14)
        ))
    }
}


// MARK: - Featured Butler Command Row

final class ContextMenuFeaturedActionRowView: NSControl {
    
    private let title: String
    private let badgeText: String
    private let iconImage: NSImage?
    private let onAction: () -> Void
    private var isHovered = false
    private var isPressed = false
    
    init(
        title: String,
        symbolName: String,
        badgeText: String,
        width: CGFloat = EditorContextMenuMetrics.menuWidth,
        onAction: @escaping () -> Void
    ) {
        self.title = title
        self.badgeText = badgeText
        self.iconImage = EditorContextMenuSymbols.image(named: symbolName, pointSize: 12.5, weight: .semibold)
        self.onAction = onAction
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: EditorContextMenuMetrics.featuredRowHeight))
        self.autoresizingMask = [.width]
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.isHovered = true
        self.needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        self.isHovered = false
        self.isPressed = false
        self.needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        self.isPressed = true
        self.needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let inside = self.bounds.contains(self.convert(event.locationInWindow, from: nil))
        if inside != self.isPressed {
            self.isPressed = inside
            self.needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let local = self.convert(event.locationInWindow, from: nil)
        self.isPressed = false
        self.needsDisplay = true
        if self.bounds.contains(local) {
            self.onAction()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let cardRect = NSRect(
            x: EditorContextMenuMetrics.horizontalInset,
            y: 2,
            width: self.bounds.width - EditorContextMenuMetrics.horizontalInset * 2,
            height: self.bounds.height - 4
        )
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)
        let cardFill: NSColor
        if self.isPressed {
            cardFill = isDark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.11)
        } else if self.isHovered {
            cardFill = isDark ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.07)
        } else {
            cardFill = isDark ? NSColor.white.withAlphaComponent(0.055) : NSColor.black.withAlphaComponent(0.036)
        }
        cardFill.setFill()
        cardPath.fill()
        
        let strokeColor = isDark
            ? NSColor.white.withAlphaComponent(self.isHovered ? 0.16 : 0.09)
            : NSColor.black.withAlphaComponent(self.isHovered ? 0.13 : 0.07)
        strokeColor.setStroke()
        cardPath.lineWidth = 0.5
        cardPath.stroke()
        
        // Leading squircle emblem with restrained studio accent wash
        let accent = StudioPaletteManager.shared.activeNSAccentColor
        let iconBoxSide: CGFloat = 22
        let iconBoxRect = NSRect(
            x: cardRect.minX + 7,
            y: round(cardRect.midY - iconBoxSide * 0.5),
            width: iconBoxSide,
            height: iconBoxSide
        )
        accent.withAlphaComponent(isDark ? 0.22 : 0.14).setFill()
        NSBezierPath(roundedRect: iconBoxRect, xRadius: 6, yRadius: 6).fill()
        
        if let icon = self.iconImage {
            let sz = icon.size
            let drawRect = NSRect(
                x: round(iconBoxRect.midX - sz.width * 0.5),
                y: round(iconBoxRect.midY - sz.height * 0.5),
                width: sz.width,
                height: sz.height
            )
            drawTintedTemplate(icon, color: accent, in: drawRect)
        }
        
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let titleStr = NSAttributedString(string: self.title, attributes: titleAttrs)
        let titleSize = titleStr.size()
        titleStr.draw(at: NSPoint(
            x: iconBoxRect.maxX + 8,
            y: round(cardRect.midY - titleSize.height * 0.5)
        ))
        
        // Right-aligned tabular context badge
        if !self.badgeText.isEmpty {
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let badgeStr = NSAttributedString(string: self.badgeText, attributes: badgeAttrs)
            let badgeSize = badgeStr.size()
            let pillW = ceil(badgeSize.width) + 12
            let pillH: CGFloat = 18
            let pillRect = NSRect(
                x: cardRect.maxX - pillW - 7,
                y: round(cardRect.midY - pillH * 0.5),
                width: pillW,
                height: pillH
            )
            let pillFill = isDark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.055)
            pillFill.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: pillH * 0.5, yRadius: pillH * 0.5).fill()
            badgeStr.draw(at: NSPoint(
                x: round(pillRect.midX - badgeSize.width * 0.5),
                y: round(pillRect.midY - badgeSize.height * 0.5)
            ))
        }
    }
}


// MARK: - Horizontal 3-Chip Quick Action Strip

struct ContextMenuChipAction {
    
    let title: String
    let symbolName: String
    let isEnabled: Bool
    let onAction: () -> Void
}


final class ContextMenuChipStripView: NSView {
    
    init(chips: [ContextMenuChipAction], width: CGFloat = EditorContextMenuMetrics.menuWidth) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: EditorContextMenuMetrics.chipStripHeight))
        self.autoresizingMask = [.width]
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: EditorContextMenuMetrics.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -EditorContextMenuMetrics.horizontalInset),
            stack.topAnchor.constraint(equalTo: self.topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -3),
        ])
        
        for chip in chips {
            let button = ContextMenuChipButton(chip: chip)
            stack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalTo: stack.heightAnchor),
            ])
        }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class ContextMenuChipButton: NSControl {
    
    private let chip: ContextMenuChipAction
    private let iconImage: NSImage?
    private var isHovered = false
    private var isPressed = false
    
    init(chip: ContextMenuChipAction) {
        self.chip = chip
        self.iconImage = EditorContextMenuSymbols.image(named: chip.symbolName, pointSize: 11.5, weight: .medium)
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.isEnabled = chip.isEnabled
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard self.chip.isEnabled else { return }
        self.isHovered = true
        self.needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        self.isHovered = false
        self.isPressed = false
        self.needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        guard self.chip.isEnabled else { return }
        self.isPressed = true
        self.needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard self.chip.isEnabled else { return }
        let inside = self.bounds.contains(self.convert(event.locationInWindow, from: nil))
        if inside != self.isPressed {
            self.isPressed = inside
            self.needsDisplay = true
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard self.chip.isEnabled else { return }
        let local = self.convert(event.locationInWindow, from: nil)
        self.isPressed = false
        self.needsDisplay = true
        if self.bounds.contains(local) {
            self.chip.onAction()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let enabled = self.chip.isEnabled
        let path = NSBezierPath(roundedRect: self.bounds, xRadius: 7, yRadius: 7)
        
        let fill: NSColor
        if !enabled {
            fill = isDark ? NSColor.white.withAlphaComponent(0.03) : NSColor.black.withAlphaComponent(0.024)
        } else if self.isPressed {
            fill = isDark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.11)
        } else if self.isHovered {
            fill = isDark ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.075)
        } else {
            fill = isDark ? NSColor.white.withAlphaComponent(0.055) : NSColor.black.withAlphaComponent(0.04)
        }
        fill.setFill()
        path.fill()
        
        let border = isDark
            ? NSColor.white.withAlphaComponent(enabled && self.isHovered ? 0.16 : 0.08)
            : NSColor.black.withAlphaComponent(enabled && self.isHovered ? 0.13 : 0.07)
        border.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        
        let fg: NSColor = enabled
            ? (self.isHovered ? .labelColor : NSColor.labelColor.withAlphaComponent(0.88))
            : NSColor.labelColor.withAlphaComponent(0.32)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: fg,
        ]
        let label = NSAttributedString(string: self.chip.title, attributes: attrs)
        let labelSize = label.size()
        let iconW: CGFloat = self.iconImage?.size.width ?? 0
        let gap: CGFloat = iconW > 0 ? 4.5 : 0
        let totalW = iconW + gap + labelSize.width
        let startX = round((self.bounds.width - totalW) * 0.5)
        
        if let icon = self.iconImage {
            let iconRect = NSRect(
                x: startX,
                y: round((self.bounds.height - icon.size.height) * 0.5),
                width: icon.size.width,
                height: icon.size.height
            )
            drawTintedTemplate(icon, color: fg, in: iconRect)
        }
        
        label.draw(at: NSPoint(
            x: round(startX + iconW + gap),
            y: round((self.bounds.height - labelSize.height) * 0.5)
        ))
    }
}


// MARK: - Live Stepless Inline Image Zoom Rail

final class ContextMenuInlineImageZoomView: NSView {
    
    private let slider: NSSlider
    private let percentLabel: NSTextField
    private let resetButton: QuickMenuIconButton
    private var presetButtons: [(scale: CGFloat, button: ZoomPresetPillButton)] = []
    private let scaleBounds: ClosedRange<CGFloat>
    private let onScaleChange: (CGFloat, Bool) -> InlineImageTransform
    private let onReset: () -> Void
    private var currentScale: CGFloat
    
    init(
        initialScale: CGFloat,
        scaleBounds: ClosedRange<CGFloat>,
        isIdentity: Bool,
        width: CGFloat = EditorContextMenuMetrics.menuWidth,
        onScaleChange: @escaping (CGFloat, Bool) -> InlineImageTransform,
        onReset: @escaping () -> Void
    ) {
        self.scaleBounds = scaleBounds
        self.currentScale = max(scaleBounds.lowerBound, min(scaleBounds.upperBound, initialScale))
        self.onScaleChange = onScaleChange
        self.onReset = onReset
        
        self.slider = NSSlider(
            value: Double(self.currentScale),
            minValue: Double(scaleBounds.lowerBound),
            maxValue: Double(scaleBounds.upperBound),
            target: nil,
            action: nil
        )
        self.percentLabel = NSTextField(labelWithString: "\(Int((self.currentScale * 100).rounded()))%")
        
        var resetHandler: (() -> Void)?
        self.resetButton = QuickMenuIconButton(
            symbolName: "arrow.counterclockwise",
            toolTipText: AppLanguage.text("恢复原始大小", en: "Reset Size")
        ) {
            resetHandler?()
        }
        
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: EditorContextMenuMetrics.imageZoomRowHeight))
        self.autoresizingMask = [.width]
        
        let zoomIcon = NSImageView()
        zoomIcon.image = EditorContextMenuSymbols.image(named: "magnifyingglass", pointSize: 12, weight: .medium)
        zoomIcon.contentTintColor = .secondaryLabelColor
        zoomIcon.translatesAutoresizingMaskIntoConstraints = false
        
        self.slider.isContinuous = true
        self.slider.controlSize = .small
        self.slider.target = self
        self.slider.action = #selector(self.handleSliderChanged(_:))
        self.slider.translatesAutoresizingMaskIntoConstraints = false
        
        self.percentLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        self.percentLabel.textColor = .labelColor
        self.percentLabel.alignment = .right
        self.percentLabel.translatesAutoresizingMaskIntoConstraints = false
        
        self.resetButton.isEnabled = !isIdentity
        self.resetButton.alphaValue = isIdentity ? 0.35 : 1.0
        
        resetHandler = { [weak self] in
            self?.handleResetClicked()
        }
        
        let topRow = NSStackView(views: [zoomIcon, self.slider, self.percentLabel, self.resetButton])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 6
        topRow.translatesAutoresizingMaskIntoConstraints = false
        
        let presets = InlineImageZoomMath.quickScalePresets(
            for: scaleBounds,
            fitLabel: AppLanguage.text("适配宽", en: "Fit")
        )
        let presetStack = NSStackView()
        presetStack.orientation = .horizontal
        presetStack.distribution = .fillEqually
        presetStack.alignment = .centerY
        presetStack.spacing = 5
        presetStack.translatesAutoresizingMaskIntoConstraints = false
        
        for preset in presets {
            let pill = ZoomPresetPillButton(title: preset.label) { [weak self] in
                self?.applyPresetScale(preset.scale)
            }
            self.presetButtons.append((preset.scale, pill))
            presetStack.addArrangedSubview(pill)
            NSLayoutConstraint.activate([
                pill.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        
        self.addSubview(topRow)
        self.addSubview(presetStack)
        
        NSLayoutConstraint.activate([
            zoomIcon.widthAnchor.constraint(equalToConstant: 14),
            zoomIcon.heightAnchor.constraint(equalToConstant: 14),
            self.percentLabel.widthAnchor.constraint(equalToConstant: 40),
            
            topRow.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: EditorContextMenuMetrics.horizontalInset + 8),
            topRow.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -(EditorContextMenuMetrics.horizontalInset + 6)),
            topRow.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            topRow.heightAnchor.constraint(equalToConstant: 22),
            
            presetStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: EditorContextMenuMetrics.horizontalInset + 8),
            presetStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -(EditorContextMenuMetrics.horizontalInset + 8)),
            presetStack.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 6),
            presetStack.heightAnchor.constraint(equalToConstant: 22),
        ])
        
        self.syncSelectionIndicators(scale: self.currentScale, isIdentity: isIdentity)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let cardRect = NSRect(
            x: EditorContextMenuMetrics.horizontalInset,
            y: 2,
            width: self.bounds.width - EditorContextMenuMetrics.horizontalInset * 2,
            height: self.bounds.height - 4
        )
        let path = NSBezierPath(roundedRect: cardRect, xRadius: 9, yRadius: 9)
        (isDark ? NSColor.white.withAlphaComponent(0.055) : NSColor.black.withAlphaComponent(0.036)).setFill()
        path.fill()
        (isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.075)).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
    
    @objc private func handleSliderChanged(_ sender: NSSlider) {
        let target = CGFloat(sender.doubleValue)
        let isLive = (NSApp.currentEvent?.type != .leftMouseUp)
        let applied = self.onScaleChange(target, isLive)
        self.currentScale = applied.scale
        self.syncSelectionIndicators(scale: applied.scale, isIdentity: applied.isIdentity)
    }
    
    private func applyPresetScale(_ scale: CGFloat) {
        let clamped = max(self.scaleBounds.lowerBound, min(self.scaleBounds.upperBound, scale))
        let applied = self.onScaleChange(clamped, false)
        self.currentScale = applied.scale
        self.slider.doubleValue = Double(max(self.scaleBounds.lowerBound, min(self.scaleBounds.upperBound, applied.scale)))
        self.syncSelectionIndicators(scale: applied.scale, isIdentity: applied.isIdentity)
    }
    
    private func handleResetClicked() {
        guard self.resetButton.isEnabled else { return }
        self.onReset()
        let clamped = max(self.scaleBounds.lowerBound, min(self.scaleBounds.upperBound, 1.0))
        self.currentScale = clamped
        self.slider.doubleValue = Double(clamped)
        self.syncSelectionIndicators(scale: 1.0, isIdentity: true)
    }
    
    private func syncSelectionIndicators(scale: CGFloat, isIdentity: Bool) {
        self.percentLabel.stringValue = "\(Int((scale * 100).rounded()))%"
        self.resetButton.isEnabled = !isIdentity
        self.resetButton.alphaValue = isIdentity ? 0.35 : 1.0
        for entry in self.presetButtons {
            entry.button.isActive = abs(entry.scale - scale) < 0.035
        }
    }
}


private final class ZoomPresetPillButton: NSControl {
    
    private let title: String
    private let onClick: () -> Void
    private var isHovered = false
    private var isPressed = false
    var isActive: Bool = false {
        didSet {
            if isActive != oldValue {
                self.needsDisplay = true
            }
        }
    }
    
    init(title: String, onClick: @escaping () -> Void) {
        self.title = title
        self.onClick = onClick
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.isHovered = true
        self.needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        self.isHovered = false
        self.isPressed = false
        self.needsDisplay = true
    }
    
    override func mouseDown(with event: NSEvent) {
        self.isPressed = true
        self.needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        let local = self.convert(event.locationInWindow, from: nil)
        self.isPressed = false
        self.needsDisplay = true
        if self.bounds.contains(local) {
            self.onClick()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let path = NSBezierPath(roundedRect: self.bounds, xRadius: 5.5, yRadius: 5.5)
        
        let fill: NSColor
        if self.isActive {
            fill = isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.11)
        } else if self.isPressed {
            fill = isDark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.09)
        } else if self.isHovered {
            fill = isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.065)
        } else {
            fill = isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.03)
        }
        fill.setFill()
        path.fill()
        
        let border = isDark
            ? NSColor.white.withAlphaComponent(self.isActive || self.isHovered ? 0.20 : 0.08)
            : NSColor.black.withAlphaComponent(self.isActive || self.isHovered ? 0.16 : 0.06)
        border.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: self.isActive ? .semibold : .medium),
            .foregroundColor: self.isActive ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let str = NSAttributedString(string: self.title, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(
            x: round((self.bounds.width - sz.width) * 0.5),
            y: round((self.bounds.height - sz.height) * 0.5)
        ))
    }
}


// MARK: - Inline 1-Click Highlight Swatch Row for Context Menu

final class ContextMenuQuickHighlightRowView: NSView {
    
    private let onSelectColorIndex: (Int) -> Void
    private let onOpenPalette: () -> Void
    private let onClearHighlight: () -> Void
    
    init(
        target: AnyObject?,
        onSelectColorIndex: @escaping (Int) -> Void,
        onOpenPalette: @escaping () -> Void,
        onClearHighlight: @escaping () -> Void
    ) {
        self.onSelectColorIndex = onSelectColorIndex
        self.onOpenPalette = onOpenPalette
        self.onClearHighlight = onClearHighlight
        
        let presets = Array(HighlightColor.allCases.prefix(QuickHighlightRowMetrics.maxQuickSwatches))
        let minWidth = max(
            EditorContextMenuMetrics.menuWidth,
            QuickHighlightRowMetrics.minimumWidth(swatchCount: presets.count)
        )
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(minWidth), height: QuickHighlightRowMetrics.height))
        self.autoresizingMask = [.width]
        
        let iconView = NSImageView()
        iconView.image = EditorContextMenuSymbols.image(named: "highlighter", pointSize: 12.5, weight: .medium)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleNone
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        var swatchButtons: [NSView] = []
        swatchButtons.reserveCapacity(presets.count)
        for (idx, color) in presets.enumerated() {
            let btn = QuickSwatchDotButton(color: color.swatchColor, toolTipText: color.localizedName) { [weak self] in
                self?.onSelectColorIndex(idx)
            }
            swatchButtons.append(btn)
        }
        
        let swatchStack = NSStackView(views: swatchButtons)
        swatchStack.orientation = .horizontal
        swatchStack.alignment = .centerY
        swatchStack.spacing = QuickHighlightRowMetrics.swatchSpacing
        swatchStack.translatesAutoresizingMaskIntoConstraints = false
        
        let separator = QuickMenuHairlineDividerView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        
        let paletteBtn = QuickMenuIconButton(
            symbolName: "paintpalette",
            toolTipText: AppLanguage.text("自定义颜色…", en: "Custom Color…")
        ) { [weak self] in
            self?.onOpenPalette()
        }
        
        let clearBtn = QuickMenuIconButton(
            symbolName: "eraser",
            toolTipText: AppLanguage.text("清除高亮", en: "Clear Highlight")
        ) { [weak self] in
            self?.onClearHighlight()
        }
        
        let toolsStack = NSStackView(views: [paletteBtn, clearBtn])
        toolsStack.orientation = .horizontal
        toolsStack.alignment = .centerY
        toolsStack.spacing = QuickHighlightRowMetrics.toolsSpacing
        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubview(iconView)
        self.addSubview(swatchStack)
        self.addSubview(separator)
        self.addSubview(toolsStack)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: QuickHighlightRowMetrics.leadingPadding),
            iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: QuickHighlightRowMetrics.leadingIconWidth),
            iconView.heightAnchor.constraint(equalToConstant: QuickHighlightRowMetrics.leadingIconWidth),
            
            swatchStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: QuickHighlightRowMetrics.iconToSwatchesGap),
            swatchStack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            
            separator.leadingAnchor.constraint(greaterThanOrEqualTo: swatchStack.trailingAnchor, constant: QuickHighlightRowMetrics.swatchesToSeparatorMinGap),
            separator.trailingAnchor.constraint(equalTo: toolsStack.leadingAnchor, constant: -QuickHighlightRowMetrics.separatorToToolsGap),
            separator.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: QuickHighlightRowMetrics.separatorWidth),
            separator.heightAnchor.constraint(equalToConstant: QuickHighlightRowMetrics.separatorHeight),
            
            toolsStack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -QuickHighlightRowMetrics.trailingPadding),
            toolsStack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
        _ = target
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class QuickMenuHairlineDividerView: NSView {
    
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: self.bounds, xRadius: 0.5, yRadius: 0.5).fill()
    }
}


final class QuickMenuIconButton: NSControl {
    
    private let iconImage: NSImage?
    private let onClick: () -> Void
    private var isHovered = false
    
    init(symbolName: String, toolTipText: String, onClick: @escaping () -> Void) {
        self.iconImage = EditorContextMenuSymbols.image(named: symbolName, pointSize: 12, weight: .medium)
        self.onClick = onClick
        let side = QuickHighlightRowMetrics.toolButtonSize
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        self.toolTip = toolTipText
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: side),
            self.heightAnchor.constraint(equalToConstant: side),
        ])
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard self.isEnabled else { return }
        self.isHovered = true
        self.needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        self.isHovered = false
        self.needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard self.isEnabled else { return }
        let local = self.convert(event.locationInWindow, from: nil)
        if self.bounds.contains(local) {
            self.onClick()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if self.isEnabled && self.isHovered {
            NSColor.labelColor.withAlphaComponent(0.085).setFill()
            NSBezierPath(roundedRect: self.bounds, xRadius: 5.5, yRadius: 5.5).fill()
        }
        guard let image = self.iconImage else { return }
        let tint: NSColor = (self.isEnabled && self.isHovered) ? .labelColor : .secondaryLabelColor
        let imgSize = image.size
        let drawRect = NSRect(
            x: (self.bounds.width - imgSize.width) * 0.5,
            y: (self.bounds.height - imgSize.height) * 0.5,
            width: imgSize.width,
            height: imgSize.height
        )
        drawTintedTemplate(image, color: tint, in: drawRect)
    }
}


private final class QuickSwatchDotButton: NSControl {
    
    private let swatchColor: NSColor
    private let onClick: () -> Void
    private var isHovered = false
    
    init(color: NSColor, toolTipText: String, onClick: @escaping () -> Void) {
        self.swatchColor = color
        self.onClick = onClick
        let side = QuickHighlightRowMetrics.swatchSize
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        self.toolTip = toolTipText
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.widthAnchor.constraint(equalToConstant: side),
            self.heightAnchor.constraint(equalToConstant: side),
        ])
        self.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseEntered(with event: NSEvent) {
        self.isHovered = true
        self.needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        self.isHovered = false
        self.needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        let local = self.convert(event.locationInWindow, from: nil)
        if self.bounds.contains(local) {
            self.onClick()
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if self.isHovered {
            let ringRect = self.bounds.insetBy(dx: 1.0, dy: 1.0)
            let ringPath = NSBezierPath(ovalIn: ringRect)
            ringPath.lineWidth = 1.15
            NSColor.labelColor.withAlphaComponent(0.32).setStroke()
            ringPath.stroke()
        }
        let dotRect = self.bounds.insetBy(dx: 3.0, dy: 3.0)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        self.swatchColor.setFill()
        dotPath.fill()
        
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.16)).setStroke()
        dotPath.lineWidth = 0.5
        dotPath.stroke()
    }
}


// MARK: - Shared Template Tint Drawing Helper

@MainActor
private func drawTintedTemplate(_ image: NSImage, color: NSColor, in drawRect: NSRect) {
    let tinted = NSImage(size: image.size, flipped: false) { rect in
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: drawRect)
}
