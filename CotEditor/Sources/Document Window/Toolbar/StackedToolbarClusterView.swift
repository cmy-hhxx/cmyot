//
//  StackedToolbarClusterView.swift
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

/// Analytical underdamped spring (`m=1, k=175, c=20`) matching `stacked-metadata`.
///
/// Reversal preserves exact position and velocity in mid-flight without clamping so rapid
/// hover enter/exit never snaps back or stalls.
nonisolated struct StackedMetadataSpring: Sendable {
    
    static let stiffness: Double = 175.0
    static let dampingCoeff: Double = 20.0
    private static let a: Double = 10.0                  // c / (2m)
    private static let omega: Double = sqrt(75.0)        // sqrt(k/m - a^2)
    
    var position: Double = 0
    var velocity: Double = 0
    var target: Double = 0
    
    
    mutating func step(dt: Double) -> Bool {
        
        guard dt > 0 else {
            return abs(self.position - self.target) >= 0.0001 || abs(self.velocity) >= 0.001
        }
        
        let e = exp(-Self.a * dt)
        let cVal = cos(Self.omega * dt)
        let sVal = sin(Self.omega * dt)
        let x = self.position - self.target
        let oldV = self.velocity
        
        let newPos = self.target + e * (x * cVal + (oldV + Self.a * x) / Self.omega * sVal)
        let newVel = e * (oldV * cVal - (Self.a * oldV + Self.stiffness * x) / Self.omega * sVal)
        
        if abs(newPos - self.target) < 0.0001 && abs(newVel) < 0.001 {
            self.position = self.target
            self.velocity = 0
            return false
        }
        
        self.position = newPos
        self.velocity = newVel
        return true
    }
}


struct StackedToolbarCapsuleItem {
    
    let id: String
    let titleProvider: @MainActor (Bool) -> String
    let tooltipProvider: @MainActor (Bool) -> String
    let imageProvider: @MainActor (Bool) -> NSImage
    let isActiveProvider: @MainActor () -> Bool
    let menuProvider: (@MainActor () -> NSMenu)?
    let action: (@MainActor () -> Void)?
    
    init(
        id: String,
        title: @escaping @MainActor (Bool) -> String,
        tooltip: @escaping @MainActor (Bool) -> String,
        image: @escaping @MainActor (Bool) -> NSImage,
        isActive: @escaping @MainActor () -> Bool = { false },
        menu: (@MainActor () -> NSMenu)? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.id = id
        self.titleProvider = title
        self.tooltipProvider = tooltip
        self.imageProvider = image
        self.isActiveProvider = isActive
        self.menuProvider = menu
        self.action = action
    }
}


/// Overlapping right-anchored capsule strip matching `stacked-metadata`:
/// stacked pills tuck left edges with a crisp 3pt halo cutout when idle and fan out smoothly
/// to expose full `[icon + label]` capsules on pointer hover.
@MainActor
final class StackedToolbarClusterView: NSView {
    
    private static let pillHeight: CGFloat = 28
    private static let haloPadding: CGFloat = 3
    private static let expandedGap: CGFloat = 5
    private static let iconPeekWidth: CGFloat = 27
    
    private let items: [StackedToolbarCapsuleItem]
    private var pillButtons: [StackedCapsulePillButton] = []
    private var spring = StackedMetadataSpring(position: 0, velocity: 0, target: 0)
    private var springTimer: Timer?
    private var lastStepTimestamp: TimeInterval = 0
    private var clusterTrackingArea: NSTrackingArea?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var isHoveredInside = false
    private var isMenuOpen = false
    
    var currentProgress: Double { self.spring.position }
    
    var collapsedWidth: CGFloat {
        guard let last = self.pillButtons.last else { return 40 }
        let peeks = CGFloat(max(0, self.pillButtons.count - 1)) * Self.iconPeekWidth
        return peeks + last.naturalWidth
    }
    
    var expandedWidth: CGFloat {
        let sumWidths = self.pillButtons.reduce(CGFloat(0)) { $0 + $1.naturalWidth }
        let gaps = CGFloat(max(0, self.pillButtons.count - 1)) * Self.expandedGap
        return sumWidths + gaps
    }
    
    var currentClusterWidth: CGFloat {
        guard let last = self.pillButtons.last else { return 40 }
        let p = self.spring.position
        var total = last.naturalWidth
        for index in 0..<max(0, self.pillButtons.count - 1) {
            let fullStep = self.pillButtons[index].naturalWidth + Self.expandedGap
            let stepDist = fullStep * CGFloat(p) + Self.iconPeekWidth * CGFloat(1.0 - p)
            total += max(18, stepDist)
        }
        return ceil(total)
    }
    
    
    init(items: [StackedToolbarCapsuleItem]) {
        
        self.items = items
        super.init(frame: .zero)
        
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.setContentHuggingPriority(.required, for: .horizontal)
        self.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        for (index, item) in items.enumerated() {
            let btn = StackedCapsulePillButton(item: item, zOrder: index) { [weak self] pill in
                self?.handlePillPressed(pill)
            } onHoverChange: { [weak self] _ in
                self?.refreshAppearanceAndLabels()
            }
            self.addSubview(btn)
            self.pillButtons.append(btn)
        }
        
        self.refreshAppearanceAndLabels()
        let initialWidth = self.currentClusterWidth
        let wc = self.widthAnchor.constraint(equalToConstant: initialWidth)
        let hc = self.heightAnchor.constraint(equalToConstant: Self.pillHeight)
        NSLayoutConstraint.activate([wc, hc])
        self.widthConstraint = wc
        self.heightConstraint = hc
        self.layoutPills()
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        self.springTimer?.invalidate()
        self.springTimer = nil
    }
    
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: self.currentClusterWidth, height: Self.pillHeight)
    }
    
    
    override func layout() {
        super.layout()
        self.layoutPills()
    }
    
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.refreshAppearanceAndLabels()
    }
    
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = self.clusterTrackingArea {
            self.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.clusterTrackingArea = area
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        self.isHoveredInside = true
        self.setExpanded(true, animated: true)
    }
    
    
    override func mouseExited(with event: NSEvent) {
        self.isHoveredInside = false
        guard !self.isMenuOpen else { return }
        self.setExpanded(false, animated: true)
    }
    
    
    func setExpanded(_ expanded: Bool, animated: Bool) {
        self.spring.target = expanded ? 1.0 : 0.0
        if !animated {
            self.spring.position = self.spring.target
            self.spring.velocity = 0
            self.springTimer?.invalidate()
            self.springTimer = nil
            self.syncWidthAndLayout()
            return
        }
        self.startSpringTimerIfNeeded()
    }
    
    
    func refreshState() {
        self.refreshAppearanceAndLabels()
        self.syncWidthAndLayout()
    }
    
    
    // MARK: Private Layout & Spring Loop
    
    private func startSpringTimerIfNeeded() {
        guard self.springTimer == nil else { return }
        self.lastStepTimestamp = ProcessInfo.processInfo.systemUptime
        self.springTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickSpring()
            }
        }
    }
    
    
    private func tickSpring() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.032, max(0.001, now - self.lastStepTimestamp))
        self.lastStepTimestamp = now
        
        let moving = self.spring.step(dt: dt)
        self.syncWidthAndLayout()
        
        if !moving {
            self.springTimer?.invalidate()
            self.springTimer = nil
        }
    }
    
    
    private func syncWidthAndLayout() {
        let nextWidth = self.currentClusterWidth
        if abs((self.widthConstraint?.constant ?? 0) - nextWidth) > 0.25 {
            self.widthConstraint?.constant = nextWidth
            self.invalidateIntrinsicContentSize()
        }
        self.layoutPills()
    }
    
    
    private func layoutPills() {
        guard !self.pillButtons.isEmpty else { return }
        
        let p = self.spring.position
        let viewW = max(self.bounds.width, self.currentClusterWidth)
        var rightEdge = viewW
        
        // Anchor rightmost pill flush right; each preceding pill slides leftward cleanly from under its neighbor.
        let lastIdx = self.pillButtons.count - 1
        let lastBtn = self.pillButtons[lastIdx]
        let lastW = lastBtn.naturalWidth
        lastBtn.frame = NSRect(x: rightEdge - lastW, y: 0, width: lastW, height: Self.pillHeight)
        var nextLeftX = lastBtn.frame.minX
        
        for index in stride(from: lastIdx - 1, through: 0, by: -1) {
            let btn = self.pillButtons[index]
            let w = btn.naturalWidth
            let fullStep = w + Self.expandedGap
            let stepDist = fullStep * CGFloat(p) + Self.iconPeekWidth * CGFloat(1.0 - p)
            let x = nextLeftX - max(18, stepDist)
            btn.frame = NSRect(x: x, y: 0, width: w, height: Self.pillHeight)
            nextLeftX = x
        }
    }
    
    
    private func refreshAppearanceAndLabels() {
        let isDark = self.effectiveAppearance.isDark
        let accent = StudioPaletteManager.shared.activeNSAccentColor
        let halo = self.titlebarCutoutColor(isDark: isDark)
        for btn in self.pillButtons {
            btn.refreshStyle(isDark: isDark, accent: accent, haloColor: halo)
        }
    }
    
    
    private func titlebarCutoutColor(isDark: Bool) -> NSColor {
        if let bg = self.window?.backgroundColor, bg != .clear {
            return bg.usingColorSpace(.sRGB) ?? (isDark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.94, alpha: 1))
        }
        return isDark
            ? NSColor(srgbRed: 0.145, green: 0.145, blue: 0.155, alpha: 1)
            : NSColor(srgbRed: 0.945, green: 0.945, blue: 0.953, alpha: 1)
    }
    
    
    private func handlePillPressed(_ pill: StackedCapsulePillButton) {
        if let menu = pill.item.menuProvider?() {
            self.isMenuOpen = true
            let origin = NSPoint(x: 0, y: pill.isFlipped ? pill.bounds.maxY + 4 : -4)
            menu.popUp(positioning: nil, at: origin, in: pill)
            self.isMenuOpen = false
            self.refreshState()
            if !self.isHoveredInside {
                self.setExpanded(false, animated: true)
            }
            return
        }
        
        pill.item.action?()
        self.refreshState()
    }
}


@MainActor
private final class StackedCapsulePillButton: NSButton {
    
    let item: StackedToolbarCapsuleItem
    private let haloLayer = CAShapeLayer()
    private let fillLayer = CALayer()
    private let iconView = NSImageView()
    private let labelField = NSTextField(labelWithString: "")
    private let onPress: (StackedCapsulePillButton) -> Void
    private let onHoverChange: (Bool) -> Void
    private var hoverTrackingArea: NSTrackingArea?
    private var isPillHovered = false
    private(set) var naturalWidth: CGFloat = 68
    
    
    init(
        item: StackedToolbarCapsuleItem,
        zOrder: Int,
        onPress: @escaping (StackedCapsulePillButton) -> Void,
        onHoverChange: @escaping (Bool) -> Void
    ) {
        self.item = item
        self.onPress = onPress
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
        
        self.title = ""
        self.isBordered = false
        self.bezelStyle = .shadowlessSquare
        self.setButtonType(.momentaryChange)
        self.wantsLayer = true
        self.layer?.masksToBounds = false
        self.layer?.zPosition = CGFloat(zOrder)
        
        self.fillLayer.cornerRadius = 14
        self.fillLayer.masksToBounds = true
        self.layer?.addSublayer(self.fillLayer)
        
        self.haloLayer.fillColor = NSColor.clear.cgColor
        self.haloLayer.lineWidth = 3.0
        self.layer?.addSublayer(self.haloLayer)
        
        self.iconView.imageScaling = .scaleProportionallyUpOrDown
        self.iconView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.iconView)
        
        self.labelField.font = .systemFont(ofSize: 12, weight: .medium)
        self.labelField.lineBreakMode = .byTruncatingTail
        self.labelField.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.labelField)
        
        NSLayoutConstraint.activate([
            self.iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            self.iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconView.widthAnchor.constraint(equalToConstant: 14),
            self.iconView.heightAnchor.constraint(equalToConstant: 14),
            
            self.labelField.leadingAnchor.constraint(equalTo: self.iconView.trailingAnchor, constant: 4),
            self.labelField.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: -0.5),
            self.labelField.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -9),
        ])
        
        self.target = self
        self.action = #selector(didClick)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layout() {
        super.layout()
        self.fillLayer.frame = self.bounds
        let haloRect = self.bounds.insetBy(dx: -1.5, dy: -1.5)
        self.haloLayer.path = CGPath(roundedRect: haloRect, cornerWidth: 15.5, cornerHeight: 15.5, transform: nil)
    }
    
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = self.hoverTrackingArea {
            self.removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.hoverTrackingArea = area
    }
    
    
    override func mouseEntered(with event: NSEvent) {
        self.isPillHovered = true
        self.onHoverChange(true)
    }
    
    
    override func mouseExited(with event: NSEvent) {
        self.isPillHovered = false
        self.onHoverChange(false)
    }
    
    
    func refreshStyle(isDark: Bool, accent: NSColor, haloColor: NSColor) {
        let isActive = self.item.isActiveProvider()
        let nextTitle = self.item.titleProvider(isActive)
        self.labelField.stringValue = nextTitle
        self.toolTip = self.item.tooltipProvider(isActive)
        
        let textWidth = ceil((nextTitle as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ]).width)
        self.naturalWidth = max(56, min(110, 8 + 14 + 4 + textWidth + 10))
        
        // Colors follow stacked-metadata palette: dark #393939/#e7e7e7, light #dedede/#242424, active accent highlight
        let bgColor: NSColor
        let fgColor: NSColor
        if isActive {
            bgColor = self.isPillHovered
                ? accent.blended(withFraction: 0.14, of: .white) ?? accent
                : accent
            fgColor = .white
        } else if isDark {
            bgColor = self.isPillHovered
                ? NSColor(srgbRed: 0.275, green: 0.275, blue: 0.285, alpha: 1)
                : NSColor(srgbRed: 0.224, green: 0.224, blue: 0.231, alpha: 1)  // #393939
            fgColor = NSColor(srgbRed: 0.906, green: 0.906, blue: 0.906, alpha: 1) // #e7e7e7
        } else {
            bgColor = self.isPillHovered
                ? NSColor(srgbRed: 0.824, green: 0.824, blue: 0.835, alpha: 1)
                : NSColor(srgbRed: 0.871, green: 0.871, blue: 0.878, alpha: 1)  // #dedede
            fgColor = NSColor(srgbRed: 0.141, green: 0.141, blue: 0.141, alpha: 1) // #242424
        }
        
        let rawIcon = self.item.imageProvider(isActive)
        let tintedIcon = rawIcon.tinted(with: fgColor)
        tintedIcon.isTemplate = false
        self.iconView.image = tintedIcon
        self.labelField.textColor = fgColor
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.fillLayer.backgroundColor = bgColor.cgColor
        self.haloLayer.strokeColor = haloColor.cgColor
        CATransaction.commit()
    }
    
    
    @objc private func didClick() {
        self.onPress(self)
    }
}
