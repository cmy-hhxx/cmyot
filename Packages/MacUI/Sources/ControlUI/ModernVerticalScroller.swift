//
//  ModernVerticalScroller.swift
//  ControlUI
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

public import AppKit
private import QuartzCore

/// A sleek, modern floating overlay vertical scroller with smooth hover/scroll transitions
/// and adaptive light/dark styling that never falls back to a bulky legacy gutter.
public final class ModernVerticalScroller: NSScroller {
    
    // MARK: Constants
    
    public static let preferredThickness: CGFloat = 11
    private static let restingThumbWidth: CGFloat = 3.5
    private static let activeThumbWidth: CGFloat = 6.5
    private static let trailingInset: CGFloat = 2.5
    private static let minimumThumbLength: CGFloat = 28
    
    
    // MARK: Private Properties
    
    private let trackLayer = CALayer()
    private let thumbLayer = CALayer()
    
    private var isHovered = false
    private var isScrolling = false
    private var isDraggingKnob = false
    private var hoverArea: NSTrackingArea?
    private var idleFadeTask: Task<Void, Never>?
    
    
    // MARK: Lifecycle
    
    public override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.commonSetup()
    }
    
    
    required init?(coder: NSCoder) {
        
        super.init(coder: coder)
        self.commonSetup()
    }
    
    
    private func commonSetup() {
        
        self.wantsLayer = true
        self.layer?.backgroundColor = nil
        
        self.trackLayer.cornerCurve = .continuous
        self.trackLayer.opacity = 0
        self.trackLayer.zPosition = 1
        
        self.thumbLayer.cornerCurve = .continuous
        self.thumbLayer.opacity = 0
        self.thumbLayer.zPosition = 2
        
        self.layer?.addSublayer(self.trackLayer)
        self.layer?.addSublayer(self.thumbLayer)
    }
    
    
    // MARK: NSScroller Overrides
    
    public override class var isCompatibleWithOverlayScrollers: Bool { true }
    
    
    public override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        
        Self.preferredThickness
    }
    
    
    public override var isOpaque: Bool { false }
    
    
    public override var wantsUpdateLayer: Bool { true }
    
    
    public override var doubleValue: Double {
        
        didSet { self.refreshGeometry(animated: false) }
    }
    
    
    public override var knobProportion: CGFloat {
        
        didSet { self.refreshGeometry(animated: false) }
    }
    
    
    public override var knobStyle: NSScroller.KnobStyle {
        
        didSet { self.refreshAppearance() }
    }
    
    
    public override func viewDidChangeEffectiveAppearance() {
        
        super.viewDidChangeEffectiveAppearance()
        self.refreshAppearance()
    }
    
    
    public override func updateTrackingAreas() {
        
        super.updateTrackingAreas()
        
        if let hoverArea {
            self.removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.hoverArea = area
    }
    
    
    public override func mouseEntered(with event: NSEvent) {
        
        super.mouseEntered(with: event)
        self.isHovered = true
        self.idleFadeTask?.cancel()
        self.refreshAppearance()
        self.refreshGeometry(animated: true)
    }
    
    
    public override func mouseExited(with event: NSEvent) {
        
        super.mouseExited(with: event)
        self.isHovered = false
        self.scheduleIdleFade()
        self.refreshAppearance()
        self.refreshGeometry(animated: true)
    }
    
    
    public override func mouseDown(with event: NSEvent) {
        
        self.isDraggingKnob = true
        self.idleFadeTask?.cancel()
        self.refreshAppearance()
        self.refreshGeometry(animated: true)
        
        super.mouseDown(with: event)
        
        self.isDraggingKnob = false
        self.scheduleIdleFade()
        self.refreshAppearance()
        self.refreshGeometry(animated: true)
    }
    
    
    public override func hitTest(_ point: NSPoint) -> NSView? {
        
        guard self.isScrollable else { return nil }
        return super.hitTest(point)
    }
    
    
    public override func layout() {
        
        super.layout()
        self.hideForeignScrollerSublayers()
        self.refreshGeometry(animated: false)
    }
    
    
    public override func updateLayer() {
        
        self.layer?.backgroundColor = nil
        self.hideForeignScrollerSublayers()
        self.refreshAppearance()
        self.refreshGeometry(animated: false)
    }
    
    
    public override func draw(_ dirtyRect: NSRect) {
        
        // Intentionally suppress AppKit's legacy scroller drawing; CALayer renders the pill.
    }
    
    
    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        
        // Intentionally suppressed.
    }
    
    
    public override func drawKnob() {
        
        // Intentionally suppressed.
    }
    
    
    // MARK: Public Methods
    
    /// Marks scroll activity so the thumb briefly intensifies and expands smoothly.
    public func noteScrollActivity() {
        
        self.isScrolling = true
        self.refreshAppearance()
        self.refreshGeometry(animated: false)
        self.scheduleIdleFade()
    }
    
    
    /// Synchronizes thumb and track frames immediately with the current knob proportion and position.
    public func refreshGeometry(animated: Bool = false) {
        
        guard let rootLayer = self.layer else { return }
        self.hideForeignScrollerSublayers()
        
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0, self.isScrollable else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.thumbLayer.opacity = 0
            self.trackLayer.opacity = 0
            CATransaction.commit()
            return
        }
        
        let rawKnob = self.rect(for: .knob)
        let trackVerticalInset: CGFloat = 4
        let usableHeight = max(1, bounds.height - trackVerticalInset * 2)
        let knobHeight = max(Self.minimumThumbLength, min(usableHeight, rawKnob.height > 0 ? rawKnob.height : usableHeight * self.knobProportion))
        let maxKnobY = max(trackVerticalInset, bounds.height - trackVerticalInset - knobHeight)
        let normalizedY = rawKnob.height > 0
            ? min(max(trackVerticalInset, rawKnob.minY), maxKnobY)
            : trackVerticalInset + (maxKnobY - trackVerticalInset) * CGFloat(self.doubleValue)
        
        let isExpanded = self.isHovered || self.isDraggingKnob
        let thumbWidth = isExpanded ? Self.activeThumbWidth : Self.restingThumbWidth
        let thumbX = max(1, bounds.width - Self.trailingInset - thumbWidth)
        let thumbFrame = CGRect(x: thumbX, y: normalizedY, width: thumbWidth, height: knobHeight)
        
        let trackWidth = Self.activeThumbWidth
        let trackX = max(1, bounds.width - Self.trailingInset - trackWidth)
        let trackFrame = CGRect(x: trackX, y: trackVerticalInset, width: trackWidth, height: usableHeight)
        
        CATransaction.begin()
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            CATransaction.setAnimationDuration(0.16)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        
        rootLayer.backgroundColor = nil
        self.trackLayer.frame = trackFrame
        self.trackLayer.cornerRadius = trackWidth / 2
        self.thumbLayer.frame = thumbFrame
        self.thumbLayer.cornerRadius = thumbWidth / 2
        
        let targetThumbOpacity: Float
        if self.isDraggingKnob {
            targetThumbOpacity = 0.78
        } else if self.isHovered {
            targetThumbOpacity = 0.62
        } else if self.isScrolling {
            targetThumbOpacity = 0.44
        } else {
            targetThumbOpacity = 0.18
        }
        self.thumbLayer.opacity = targetThumbOpacity
        self.trackLayer.opacity = isExpanded ? 1.0 : 0.0
        CATransaction.commit()
    }
    
    
    // MARK: Private Helpers
    
    private var isScrollable: Bool {
        
        self.isEnabled && self.knobProportion > 0 && self.knobProportion < 0.999
    }
    
    
    private var usesLightThumbOnDarkBackground: Bool {
        
        switch self.knobStyle {
            case .light:
                return true
            case .dark:
                return false
            case .default:
                return self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            @unknown default:
                return false
        }
    }
    
    
    private func refreshAppearance() {
        
        let isDark = self.usesLightThumbOnDarkBackground
        let baseThumb = isDark ? NSColor.white : NSColor(calibratedWhite: 0.10, alpha: 1.0)
        let trackTint = isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.05)
        let borderTint = isDark ? NSColor.black.withAlphaComponent(0.22) : NSColor.white.withAlphaComponent(0.20)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.trackLayer.backgroundColor = trackTint.cgColor
        self.thumbLayer.backgroundColor = baseThumb.cgColor
        self.thumbLayer.borderWidth = 0.5
        self.thumbLayer.borderColor = borderTint.cgColor
        CATransaction.commit()
    }
    
    
    private func hideForeignScrollerSublayers() {
        
        guard let sublayers = self.layer?.sublayers else { return }
        for sublayer in sublayers where sublayer !== self.trackLayer && sublayer !== self.thumbLayer {
            sublayer.isHidden = true
            sublayer.opacity = 0
        }
    }
    
    
    private func scheduleIdleFade() {
        
        self.idleFadeTask?.cancel()
        guard !self.isHovered && !self.isDraggingKnob else { return }
        
        self.idleFadeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            self.isScrolling = false
            self.refreshGeometry(animated: true)
        }
    }
}
