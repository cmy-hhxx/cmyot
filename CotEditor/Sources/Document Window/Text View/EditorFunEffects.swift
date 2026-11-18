//
//  EditorFunEffects.swift
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
import QuartzCore

/// Minimalist, refined typing effect presets.
enum TypingEffectPreset: String, CaseIterable, Identifiable, Sendable {
    
    case luxeGlow
    case silkRipple
    case stardust
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .luxeGlow: "微光粒子 (Luxe Glow)"
            case .silkRipple: "静谧波纹 (Silk Ripple)"
            case .stardust: "轻盈星尘 (Fine Stardust)"
        }
    }
    
    /// Resolves both current and legacy stored preference strings cleanly.
    static func resolve(_ raw: String) -> TypingEffectPreset {
        if let exact = TypingEffectPreset(rawValue: raw) {
            return exact
        }
        return switch raw {
            case "neonPop": .silkRipple
            case "magicStars": .stardust
            default: .luxeGlow
        }
    }
    
    @MainActor static var current: TypingEffectPreset {
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: "luxeGlow")
        return Self.resolve(raw)
    }
}


/// Built-in CoreAnimation visual effects for refined typing feedback,
/// inline habit ghost-completion micro-animations, and Neovide-inspired jelly Vim cursor motion.
@MainActor final class EditorFunEffectsController {
    
    // MARK: Public State
    
    /// `true` while the jelly Vim cursor layer is actively gliding to its destination.
    private(set) var isVimCursorInFlight = false
    
    
    // MARK: Private Properties
    
    private weak var textView: EditorTextView?
    
    // Pooled GPU-composited typing effect layers
    private weak var hostedLayer: CALayer?
    private var typewriterRootLayer: CALayer?
    private var caretPulseLayer: CALayer?
    private var ripplePool: [CAShapeLayer] = []
    private var ripplePoolIndex = 0
    private var particlePool: [CALayer] = []
    private var particlePoolIndex = 0
    
    // Inline ghost completion layers & acceptance sweep
    private var ghostRootLayer: CALayer?
    private var ghostContainerLayer: CALayer?
    private var ghostSweepLayer: CALayer?
    
    // Jelly Vim cursor animation state
    private var vimRootLayer: CALayer?
    private var jellyCursorLayer: CAShapeLayer?
    private var lastCursorRect: NSRect?
    private var lastTargetRect: NSRect?
    private var lastTriggerTime: CFTimeInterval = 0
    private var activeFlightStartTime: CFTimeInterval = 0
    private var activeFlightDuration: CFTimeInterval = 0
    private var activeFlightFromRect: NSRect = .zero
    private var activeFlightToRect: NSRect = .zero
    private var hideOverlayTask: Task<Void, Never>?
    
    
    init(textView: EditorTextView) {
        
        self.textView = textView
    }
    
    
    // MARK: Public API
    
    /// Clears cached cursor tracking and hides transient overlays (e.g. on focus loss or zoom).
    func resetCursorTracking() {
        
        self.hideOverlayTask?.cancel()
        self.hideOverlayTask = nil
        self.isVimCursorInFlight = false
        self.lastCursorRect = nil
        self.lastTargetRect = nil
        self.hideGhostSuggestion(animated: false)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.jellyCursorLayer?.removeAllAnimations()
        self.jellyCursorLayer?.opacity = 0
        CATransaction.commit()
        
        self.textView?.needsDisplay = true
    }
    
    
    /// Triggers the selected minimalist typing feedback at `rect`.
    func triggerTypewriterBurst(at rect: NSRect, color: NSColor? = nil, intensityScale: CGFloat = 1.0) {
        
        let isEnabled = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
        guard isEnabled else { return }
        guard let textView = self.textView, textView.window?.isKeyWindow == true else { return }
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        
        self.ensureTypewriterLayers(in: hostLayer)
        
        let preset = TypingEffectPreset.current
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let accent = self.resolvedAccentColor(for: textView, fallback: color ?? textView.effectiveCursorColor)
        
        switch preset {
            case .luxeGlow:
                self.emitLuxeGlowBurst(at: center, rect: rect, accent: accent, intensityScale: intensityScale)
            case .silkRipple:
                self.emitSilkRippleBurst(at: center, rect: rect, accent: accent, intensityScale: intensityScale)
            case .stardust:
                self.emitFineStardustBurst(at: center, accent: accent, intensityScale: intensityScale)
        }
    }
    
    
    // MARK: Minimalist Typing Presets
    
    /// 3–4 delicate glowing micro-motes + soft caret breath.
    private func emitLuxeGlowBurst(at center: CGPoint, rect: NSRect, accent: NSColor, intensityScale: CGFloat) {
        
        self.emitSoftCaretBreath(at: center, rect: rect, color: accent)
        
        guard !self.particlePool.isEmpty else { return }
        let count = max(3, min(5, Int(round(3.5 * intensityScale))))
        let pearl = accent.blended(withFraction: 0.45, of: .white) ?? accent
        let gravity: CGFloat = 75.0
        
        for index in 0..<count {
            let particle = self.nextParticleLayer()
            let particleColor = index.isMultiple(of: 2) ? accent : pearl
            let size = CGFloat.random(in: 2.2...3.2)
            let duration = Double.random(in: 0.38...0.52)
            let vx = CGFloat.random(in: -34...34)
            let vy = CGFloat.random(in: -54 ... -22)
            
            let samples = 10
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let frac = CGFloat(step) / CGFloat(samples - 1)
                let elapsed = CGFloat(duration) * frac
                let px = center.x + vx * elapsed * (1.0 - 0.25 * frac)
                let py = center.y + vy * elapsed + 0.5 * gravity * elapsed * elapsed
                positions.append(NSValue(point: CGPoint(x: px, y: py)))
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particle.removeAllAnimations()
            particle.position = center
            particle.bounds = CGRect(x: 0, y: 0, width: size * 2.2, height: size * 2.2)
            particle.cornerRadius = 0
            particle.backgroundColor = nil
            particle.contents = Self.tintedGlowCGImage(color: particleColor)
            particle.transform = CATransform3DIdentity
            particle.opacity = 0
            CATransaction.commit()
            
            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.values = positions
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 1.0
            scaleAnim.toValue = 0.25
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.85, 0.45, 0.0]
            alphaAnim.keyTimes = [0.0, 0.14, 0.62, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [posAnim, scaleAnim, alphaAnim]
            group.duration = duration
            group.isRemovedOnCompletion = true
            particle.add(group, forKey: "luxeMote")
        }
    }
    
    
    /// Single ultra-fine translucent halo ring + subtle caret breath.
    private func emitSilkRippleBurst(at center: CGPoint, rect: NSRect, accent: NSColor, intensityScale: CGFloat) {
        
        self.emitSoftCaretBreath(at: center, rect: rect, color: accent)
        
        guard !self.ripplePool.isEmpty else { return }
        let ripple = self.ripplePool[self.ripplePoolIndex]
        self.ripplePoolIndex = (self.ripplePoolIndex + 1) % self.ripplePool.count
        
        let baseRadius = max(5.5, min(8.5, rect.height * 0.32))
        let ringRect = CGRect(x: -baseRadius, y: -baseRadius, width: baseRadius * 2, height: baseRadius * 2)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ripple.removeAllAnimations()
        ripple.position = center
        ripple.bounds = ringRect
        ripple.path = CGPath(ellipseIn: ringRect, transform: nil)
        ripple.strokeColor = accent.withAlphaComponent(0.55).cgColor
        ripple.fillColor = nil
        ripple.lineWidth = 0.9
        ripple.opacity = 0
        CATransaction.commit()
        
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.55
        scaleAnim.toValue = 1.75 * min(1.2, intensityScale)
        
        let widthAnim = CABasicAnimation(keyPath: "lineWidth")
        widthAnim.fromValue = 1.05
        widthAnim.toValue = 0.2
        
        let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
        alphaAnim.values = [0.0, 0.68, 0.0]
        alphaAnim.keyTimes = [0.0, 0.16, 1.0]
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnim, widthAnim, alphaAnim]
        group.duration = 0.30
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        group.isRemovedOnCompletion = true
        ripple.add(group, forKey: "silkRipple")
    }
    
    
    /// 2–3 tiny shimmering four-point glints rising gracefully near the caret.
    private func emitFineStardustBurst(at center: CGPoint, accent: NSColor, intensityScale: CGFloat) {
        
        guard !self.particlePool.isEmpty else { return }
        let count = max(2, min(4, Int(round(2.5 * intensityScale))))
        let champagne = accent.blended(withFraction: 0.50, of: .white) ?? accent
        
        for index in 0..<count {
            let star = self.nextParticleLayer()
            let starColor = index.isMultiple(of: 2) ? accent : champagne
            let size = CGFloat.random(in: 5.5...8.0)
            let duration = Double.random(in: 0.44...0.60)
            let dx = CGFloat.random(in: -22...22)
            let dy = CGFloat.random(in: -26 ... -10)
            let sway = CGFloat.random(in: -5...5)
            
            let samples = 10
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let frac = CGFloat(step) / CGFloat(samples - 1)
                let eased = 1.0 - pow(1.0 - frac, 2.2)
                let px = center.x + dx * eased + sin(frac * .pi * 2.0) * sway * 0.4
                let py = center.y + dy * eased
                positions.append(NSValue(point: CGPoint(x: px, y: py)))
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            star.removeAllAnimations()
            star.position = center
            star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            star.cornerRadius = 0
            star.backgroundColor = nil
            star.contents = Self.tintedStarCGImage(color: starColor)
            star.transform = CATransform3DIdentity
            star.opacity = 0
            CATransaction.commit()
            
            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.values = positions
            
            let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnim.values = [0.3, 1.05, 0.72, 0.1]
            scaleAnim.keyTimes = [0.0, 0.25, 0.65, 1.0]
            
            let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotAnim.fromValue = 0.0
            rotAnim.toValue = Double.random(in: 0.6...1.4) * (index.isMultiple(of: 2) ? 1.0 : -1.0)
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.78, 0.0]
            alphaAnim.keyTimes = [0.0, 0.20, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [posAnim, scaleAnim, rotAnim, alphaAnim]
            group.duration = duration
            group.isRemovedOnCompletion = true
            star.add(group, forKey: "fineStardust")
        }
    }
    
    
    private func emitSoftCaretBreath(at center: CGPoint, rect: NSRect, color: NSColor) {
        
        guard let pulse = self.caretPulseLayer else { return }
        let pulseSize = CGSize(width: max(6, rect.width + 6), height: max(16, rect.height + 2))
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pulse.removeAllAnimations()
        pulse.position = center
        pulse.bounds = CGRect(origin: .zero, size: pulseSize)
        pulse.backgroundColor = color.withAlphaComponent(0.22).cgColor
        pulse.cornerRadius = 3.0
        pulse.opacity = 0
        CATransaction.commit()
        
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.88
        scaleAnim.toValue = 1.18
        
        let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
        alphaAnim.values = [0.0, 0.52, 0.0]
        alphaAnim.keyTimes = [0.0, 0.18, 1.0]
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnim, alphaAnim]
        group.duration = 0.22
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        group.isRemovedOnCompletion = true
        pulse.add(group, forKey: "caretBreath")
    }
    
    
    // MARK: Inline Ghost Completion Overlay & Micro-Animation
    
    /// Shows an inline gray next-phrase candidate beside the caret with a crisp Tab micro-badge.
    func showGhostSuggestion(_ text: String, at caretRect: NSRect, font: NSFont, lineHeight: CGFloat) {
        
        guard !text.isEmpty,
              let textView = self.textView,
              textView.window?.isKeyWindow == true,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return }
        
        self.ensureGhostLayers(in: hostLayer)
        guard let container = self.ghostContainerLayer else { return }
        
        let scale = textView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: textAttributes)
        let rowHeight = max(lineHeight, ceil(textSize.height))
        
        let badgeFont = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let badgeText = "Tab"
        let badgeTextSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
        let badgeWidth = ceil(badgeTextSize.width) + 10
        let badgeHeight = min(15.0, max(13.0, rowHeight - 3))
        
        let startX = caretRect.maxX + 1.5
        let availableWidth = max(28, textView.bounds.width - startX - 10)
        let desiredWidth = ceil(textSize.width) + 6 + badgeWidth + 4
        let containerWidth = ceil(min(desiredWidth, availableWidth))
        let showsBadge = (ceil(textSize.width) + 6 + badgeWidth) <= availableWidth
        let textDrawWidth = showsBadge ? ceil(textSize.width) + 2 : max(20, containerWidth - 2)
        
        let verticalOffset = max(0, (rowHeight - ceil(textSize.height)) / 2)
        let ghostTextColor = (textView.theme?.text.color ?? NSColor.labelColor).withAlphaComponent(0.45)
        let badgeBgColor = NSColor.controlAccentColor.withAlphaComponent(0.14)
        let badgeBorderColor = NSColor.controlAccentColor.withAlphaComponent(0.35)
        let badgeFgColor = NSColor.controlAccentColor.withAlphaComponent(0.90)
        
        let imageSize = NSSize(width: containerWidth, height: rowHeight)
        let renderedImage = NSImage(size: imageSize, flipped: true) { _ in
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail
            let attrText = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: ghostTextColor,
                .paragraphStyle: paragraphStyle,
            ])
            attrText.draw(in: NSRect(x: 0, y: verticalOffset, width: textDrawWidth, height: ceil(textSize.height) + 2))
            
            if showsBadge {
                let badgeX = ceil(textSize.width) + 6
                let badgeY = max(0, (rowHeight - badgeHeight) / 2)
                let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
                let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 3.5, yRadius: 3.5)
                badgeBgColor.setFill()
                badgePath.fill()
                badgeBorderColor.setStroke()
                badgePath.lineWidth = 0.75
                badgePath.stroke()
                
                let badgeAttr = NSAttributedString(string: badgeText, attributes: [
                    .font: badgeFont,
                    .foregroundColor: badgeFgColor,
                ])
                let bx = badgeRect.minX + (badgeWidth - badgeTextSize.width) / 2
                let by = badgeRect.minY + (badgeHeight - badgeTextSize.height) / 2 - 0.5
                badgeAttr.draw(at: NSPoint(x: bx, y: by))
            }
            return true
        }
        
        var proposedRect = NSRect(origin: .zero, size: imageSize)
        let scaleTransform = NSAffineTransform()
        scaleTransform.scale(by: scale)
        let cgImage = renderedImage.cgImage(forProposedRect: &proposedRect, context: nil, hints: [.ctm: scaleTransform])
        
        let targetFrame = CGRect(x: startX, y: caretRect.minY, width: containerWidth, height: rowHeight)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAllAnimations()
        container.frame = targetFrame
        container.contentsScale = scale
        container.contentsGravity = .resize
        container.contents = cgImage
        container.opacity = 1.0
        CATransaction.commit()
        
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        
        let slideIn = CABasicAnimation(keyPath: "transform.translation.x")
        slideIn.fromValue = 6.0
        slideIn.toValue = 0.0
        
        let scaleIn = CABasicAnimation(keyPath: "transform.scale")
        scaleIn.fromValue = 0.97
        scaleIn.toValue = 1.0
        
        let group = CAAnimationGroup()
        group.animations = [fadeIn, slideIn, scaleIn]
        group.duration = 0.14
        group.timingFunction = easeOut
        group.isRemovedOnCompletion = true
        container.add(group, forKey: "ghostEnter")
    }
    
    
    /// Hides the inline ghost candidate cleanly.
    func hideGhostSuggestion(animated: Bool = false) {
        
        guard let container = self.ghostContainerLayer, container.opacity > 0.01 else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.08)
        container.removeAllAnimations()
        container.opacity = 0
        CATransaction.commit()
    }
    
    
    /// Plays a subtle luminous sweep + completion pulse when the user accepts a ghost candidate with Tab.
    func animateGhostCompletionAccept(from startRect: NSRect, to endRect: NSRect, color: NSColor) {
        
        guard let textView = self.textView,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return }
        self.ensureGhostLayers(in: hostLayer)
        
        if let sweep = self.ghostSweepLayer {
            let sweepRect: CGRect
            if abs(startRect.minY - endRect.minY) < max(8, startRect.height) && endRect.maxX >= startRect.minX {
                sweepRect = startRect.union(endRect).insetBy(dx: -3, dy: -2)
            } else {
                sweepRect = endRect.insetBy(dx: -8, dy: -2)
            }
            
            let accent = NSColor.controlAccentColor.blended(withFraction: 0.25, of: color) ?? color
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sweep.removeAllAnimations()
            sweep.frame = sweepRect
            sweep.backgroundColor = accent.withAlphaComponent(0.24).cgColor
            sweep.borderColor = accent.withAlphaComponent(0.42).cgColor
            sweep.borderWidth = 0.8
            sweep.cornerRadius = 4
            sweep.opacity = 0
            CATransaction.commit()
            
            let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.96
            scaleAnim.toValue = 1.02
            
            let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnim.values = [0.0, 0.95, 0.0]
            opacityAnim.keyTimes = [0.0, 0.22, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, opacityAnim]
            group.duration = 0.26
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            sweep.add(group, forKey: "ghostSweep")
        }
        
        self.triggerTypewriterBurst(at: endRect, color: NSColor.controlAccentColor, intensityScale: 1.0)
    }
    
    
    // MARK: Neovide-Style Jelly Vim Cursor
    
    /// Animates a continuous, elastic jelly Vim cursor with leading/trailing lag and volume-preserving landing squash.
    func animateVimCursorTransition(from oldRect: NSRect?, to newRect: NSRect, color: NSColor) {
        
        let isEnabled = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
        guard
            isEnabled,
            let textView = self.textView,
            textView.window?.isKeyWindow == true,
            newRect.width > 0, newRect.height > 0,
            newRect.height < 80
        else { return }
        
        let now = CACurrentMediaTime()
        if let lastTarget = self.lastTargetRect,
           now - self.lastTriggerTime < 0.02,
           abs(lastTarget.minX - newRect.minX) < 0.5,
           abs(lastTarget.minY - newRect.minY) < 0.5,
           abs(lastTarget.width - newRect.width) < 0.5
        {
            return
        }
        self.lastTargetRect = newRect
        self.lastTriggerTime = now
        
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        self.ensureVimLayers(in: hostLayer)
        guard let jellyLayer = self.jellyCursorLayer else { return }
        
        // Determine seamless source rect: if already mid-flight, capture current interpolated rect
        let sourceRect: NSRect
        if self.isVimCursorInFlight, self.activeFlightDuration > 0 {
            let elapsed = max(0, min(1, (now - self.activeFlightStartTime) / self.activeFlightDuration))
            let eased = 1.0 - pow(1.0 - elapsed, 2.5)
            sourceRect = Self.lerpRect(self.activeFlightFromRect, self.activeFlightToRect, fraction: eased)
        } else {
            sourceRect = oldRect ?? self.lastCursorRect ?? newRect
        }
        self.lastCursorRect = newRect
        
        // If source fell outside visible viewport (e.g. jump from offscreen), clamp start smoothly near destination
        let visible = textView.visibleRect.insetBy(dx: -48, dy: -64)
        var effectiveFrom = sourceRect
        if !visible.intersects(effectiveFrom) || effectiveFrom.height > 80 {
            effectiveFrom = newRect
        }
        
        let dx = newRect.midX - effectiveFrom.midX
        let dy = newRect.midY - effectiveFrom.midY
        let distance = hypot(dx, dy)
        guard distance >= 1.0 else { return }
        
        // Cap huge cross-document jumps (`gg`, `G`) so the jelly stretches cleanly into frame
        let maxVisualJump: CGFloat = 180
        if distance > maxVisualJump {
            let ratio = 64.0 / distance
            effectiveFrom = NSRect(
                x: newRect.midX - dx * ratio - effectiveFrom.width / 2,
                y: newRect.midY - dy * ratio - effectiveFrom.height / 2,
                width: effectiveFrom.width,
                height: effectiveFrom.height
            )
        }
        
        let duration: CFTimeInterval = distance < 22 ? 0.145 : 0.175
        self.activeFlightStartTime = now
        self.activeFlightDuration = duration
        self.activeFlightFromRect = effectiveFrom
        self.activeFlightToRect = newRect
        self.isVimCursorInFlight = true
        
        let keyframes = Self.buildJellyPathKeyframes(from: effectiveFrom, to: newRect, steps: 16)
        let cursorAlpha: CGFloat = (VimState.shared.mode == .visual) ? 0.68 : 0.58
        let finalPath = keyframes.last ?? CGPath(roundedRect: newRect, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        jellyLayer.removeAllAnimations()
        jellyLayer.fillColor = color.withAlphaComponent(cursorAlpha).cgColor
        jellyLayer.shadowColor = color.cgColor
        jellyLayer.shadowOpacity = 0.32
        jellyLayer.shadowRadius = 4.0
        jellyLayer.shadowOffset = .zero
        jellyLayer.path = finalPath
        jellyLayer.opacity = 1.0
        CATransaction.commit()
        
        let pathAnim = CAKeyframeAnimation(keyPath: "path")
        pathAnim.values = keyframes
        pathAnim.calculationMode = .linear
        pathAnim.duration = duration
        pathAnim.isRemovedOnCompletion = true
        jellyLayer.add(pathAnim, forKey: "jellyMorph")
        
        // Suppress static destination block cursor only during the flight so there is no ghosting
        textView.needsDisplay = true
        
        let durationMs = Int(duration * 1000) + 10
        self.hideOverlayTask?.cancel()
        self.hideOverlayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(durationMs))
            guard !Task.isCancelled, let self else { return }
            self.isVimCursorInFlight = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.jellyCursorLayer?.opacity = 0
            CATransaction.commit()
            self.textView?.needsDisplay = true
        }
    }
    
    
    // MARK: Jelly Geometry Builders
    
    /// Generates `steps` sequential `CGPath` keyframes:
    /// leading corners race ahead (`0...0.70`), trailing corners catch up elastically,
    /// followed by a volume-preserving jelly landing squash-and-rebound (`0.70...1.0`).
    private static func buildJellyPathKeyframes(from fromRect: NSRect, to toRect: NSRect, steps: Int) -> [CGPath] {
        
        var paths: [CGPath] = []
        paths.reserveCapacity(steps)
        
        let dx = toRect.midX - fromRect.midX
        let dy = toRect.midY - fromRect.midY
        let mostlyHorizontal = abs(dx) >= abs(dy)
        let flightPhaseEnd: CGFloat = 0.70
        
        for step in 0..<steps {
            let progress = CGFloat(step) / CGFloat(max(1, steps - 1))
            
            if progress < flightPhaseEnd {
                let flightU = progress / flightPhaseEnd
                let leadFraction = 1.0 - pow(1.0 - flightU, 3.2)
                let rawTrail = max(0.0, (flightU - 0.14) / 0.86)
                let trailFraction = 1.0 - pow(1.0 - rawTrail, 2.2)
                
                // Subtle mid-flight waist thinning for liquid stretch feel
                let stretchBell = sin(flightU * .pi)
                let thinScale = 1.0 - 0.12 * stretchBell
                
                var leadRect = Self.lerpRect(fromRect, toRect, fraction: leadFraction)
                var trailRect = Self.lerpRect(fromRect, toRect, fraction: trailFraction)
                if mostlyHorizontal {
                    leadRect = leadRect.insetBy(dx: 0, dy: leadRect.height * (1.0 - thinScale) * 0.5)
                    trailRect = trailRect.insetBy(dx: 0, dy: trailRect.height * (1.0 - thinScale) * 0.5)
                } else {
                    leadRect = leadRect.insetBy(dx: leadRect.width * (1.0 - thinScale) * 0.5, dy: 0)
                    trailRect = trailRect.insetBy(dx: trailRect.width * (1.0 - thinScale) * 0.5, dy: 0)
                }
                
                let hull = Self.roundedConvexHullPath(of: [
                    NSPoint(x: trailRect.minX, y: trailRect.minY),
                    NSPoint(x: trailRect.maxX, y: trailRect.minY),
                    NSPoint(x: trailRect.maxX, y: trailRect.maxY),
                    NSPoint(x: trailRect.minX, y: trailRect.maxY),
                    NSPoint(x: leadRect.minX, y: leadRect.minY),
                    NSPoint(x: leadRect.maxX, y: leadRect.minY),
                    NSPoint(x: leadRect.maxX, y: leadRect.maxY),
                    NSPoint(x: leadRect.minX, y: leadRect.maxY),
                ], cornerRadius: 2.0)
                paths.append(hull)
            } else {
                let bounceU = (progress - flightPhaseEnd) / (1.0 - flightPhaseEnd)
                let wobble = sin(bounceU * .pi * 2.0) * exp(-2.6 * bounceU) * 0.20
                
                let scaleX = mostlyHorizontal ? (1.0 - wobble) : (1.0 + wobble * 0.65)
                let scaleY = mostlyHorizontal ? (1.0 + wobble * 0.65) : (1.0 - wobble)
                
                let scaledWidth = toRect.width * scaleX
                let scaledHeight = toRect.height * scaleY
                let squashed = CGRect(
                    x: toRect.midX - scaledWidth / 2,
                    y: toRect.midY - scaledHeight / 2,
                    width: scaledWidth,
                    height: scaledHeight
                )
                paths.append(CGPath(roundedRect: squashed, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil))
            }
        }
        
        return paths
    }
    
    
    private static func lerpRect(_ start: NSRect, _ end: NSRect, fraction: CGFloat) -> NSRect {
        
        NSRect(
            x: start.origin.x + (end.origin.x - start.origin.x) * fraction,
            y: start.origin.y + (end.origin.y - start.origin.y) * fraction,
            width: start.size.width + (end.size.width - start.size.width) * fraction,
            height: start.size.height + (end.size.height - start.size.height) * fraction
        )
    }
    
    
    /// Computes the convex hull of `points` (Andrew's monotone chain) and rounds all corners smoothly.
    private static func roundedConvexHullPath(of points: [NSPoint], cornerRadius: CGFloat) -> CGPath {
        
        let sorted = points.sorted { lhs, rhs in
            if abs(lhs.x - rhs.x) > 0.01 { return lhs.x < rhs.x }
            return lhs.y < rhs.y
        }
        guard sorted.count >= 3 else {
            return CGPath(rect: .zero, transform: nil)
        }
        
        func cross(_ origin: NSPoint, _ first: NSPoint, _ second: NSPoint) -> CGFloat {
            (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
        }
        
        var lower: [NSPoint] = []
        for point in sorted {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0.001 {
                lower.removeLast()
            }
            lower.append(point)
        }
        
        var upper: [NSPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0.001 {
                upper.removeLast()
            }
            upper.append(point)
        }
        
        let hull = Array(lower.dropLast()) + Array(upper.dropLast())
        guard hull.count >= 3 else {
            return CGPath(rect: .zero, transform: nil)
        }
        
        let path = CGMutablePath()
        let count = hull.count
        let last = hull[count - 1]
        let first = hull[0]
        path.move(to: CGPoint(x: (last.x + first.x) * 0.5, y: (last.y + first.y) * 0.5))
        
        for idx in 0..<count {
            let current = hull[idx]
            let next = hull[(idx + 1) % count]
            path.addArc(tangent1End: current, tangent2End: next, radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }
    
    
    // MARK: Private Helpers
    
    private func nextParticleLayer() -> CALayer {
        
        let layer = self.particlePool[self.particlePoolIndex]
        self.particlePoolIndex = (self.particlePoolIndex + 1) % self.particlePool.count
        return layer
    }
    
    
    private func resolvedAccentColor(for textView: EditorTextView, fallback: NSColor) -> NSColor {
        
        let loc = textView.selectedRange().location
        if loc > 0, let lm = textView.layoutManager {
            let probeIndex = min(loc - 1, max(0, (textView.string as NSString).length - 1))
            if let attrColor = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: probeIndex, effectiveRange: nil) as? NSColor,
               let rgb = attrColor.usingColorSpace(.sRGB),
               rgb.saturationComponent > 0.25
            {
                return attrColor
            }
        }
        return NSColor.controlAccentColor.blended(withFraction: 0.35, of: fallback) ?? fallback
    }
    
    
    private func ensureClippedHostLayer(for textView: EditorTextView) -> CALayer? {
        
        if !textView.wantsLayer {
            textView.wantsLayer = true
        }
        textView.layer?.masksToBounds = true
        
        if let clipView = textView.enclosingScrollView?.contentView {
            if !clipView.wantsLayer {
                clipView.wantsLayer = true
            }
            clipView.layer?.masksToBounds = true
        }
        
        return textView.layer
    }
    
    
    private func resetHostedLayersIfNeeded(for hostLayer: CALayer) {
        
        guard self.hostedLayer !== hostLayer else { return }
        self.hostedLayer = hostLayer
        
        self.typewriterRootLayer?.removeFromSuperlayer()
        self.typewriterRootLayer = nil
        self.caretPulseLayer = nil
        self.ripplePool.removeAll()
        self.particlePool.removeAll()
        
        self.ghostRootLayer?.removeFromSuperlayer()
        self.ghostRootLayer = nil
        self.ghostContainerLayer = nil
        self.ghostSweepLayer = nil
        
        self.vimRootLayer?.removeFromSuperlayer()
        self.vimRootLayer = nil
        self.jellyCursorLayer = nil
    }
    
    
    private func ensureTypewriterLayers(in hostLayer: CALayer) {
        
        self.resetHostedLayersIfNeeded(for: hostLayer)
        guard self.typewriterRootLayer == nil else { return }
        
        let root = CALayer()
        root.zPosition = 200
        hostLayer.addSublayer(root)
        self.typewriterRootLayer = root
        
        let pulse = CALayer()
        pulse.opacity = 0
        root.addSublayer(pulse)
        self.caretPulseLayer = pulse
        
        var ripples: [CAShapeLayer] = []
        ripples.reserveCapacity(6)
        for _ in 0..<6 {
            let ripple = CAShapeLayer()
            ripple.opacity = 0
            root.addSublayer(ripple)
            ripples.append(ripple)
        }
        self.ripplePool = ripples
        
        var pool: [CALayer] = []
        pool.reserveCapacity(40)
        for _ in 0..<40 {
            let particle = CALayer()
            particle.opacity = 0
            root.addSublayer(particle)
            pool.append(particle)
        }
        self.particlePool = pool
    }
    
    
    private func ensureGhostLayers(in hostLayer: CALayer) {
        
        self.resetHostedLayersIfNeeded(for: hostLayer)
        guard self.ghostRootLayer == nil else { return }
        
        let root = CALayer()
        root.zPosition = 175
        hostLayer.addSublayer(root)
        self.ghostRootLayer = root
        
        let sweep = CALayer()
        sweep.opacity = 0
        root.addSublayer(sweep)
        self.ghostSweepLayer = sweep
        
        let container = CALayer()
        container.masksToBounds = true
        container.opacity = 0
        root.addSublayer(container)
        self.ghostContainerLayer = container
    }
    
    
    private func ensureVimLayers(in hostLayer: CALayer) {
        
        self.resetHostedLayersIfNeeded(for: hostLayer)
        guard self.vimRootLayer == nil else { return }
        
        let root = CALayer()
        root.zPosition = 180
        hostLayer.addSublayer(root)
        self.vimRootLayer = root
        
        let jelly = CAShapeLayer()
        jelly.opacity = 0
        root.addSublayer(jelly)
        self.jellyCursorLayer = jelly
    }
    
    
    private static var glowImageCache: [NSColor: CGImage] = [:]
    private static var starImageCache: [NSColor: CGImage] = [:]
    
    
    private static func tintedGlowCGImage(color: NSColor) -> CGImage? {
        
        if let cached = self.glowImageCache[color] {
            return cached
        }
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.95),
                color.withAlphaComponent(0.85),
                color.withAlphaComponent(0.0),
            ])
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            if self.glowImageCache.count > 32 {
                self.glowImageCache.removeAll()
            }
            self.glowImageCache[color] = cgImage
            return cgImage
        }
        return nil
    }
    
    
    private static func tintedStarCGImage(color: NSColor) -> CGImage? {
        
        if let cached = self.starImageCache[color] {
            return cached
        }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY
            let outer = rect.width * 0.45
            let inner = rect.width * 0.13
            
            let path = NSBezierPath()
            path.move(to: NSPoint(x: cx, y: cy + outer))
            path.line(to: NSPoint(x: cx + inner, y: cy + inner))
            path.line(to: NSPoint(x: cx + outer, y: cy))
            path.line(to: NSPoint(x: cx + inner, y: cy - inner))
            path.line(to: NSPoint(x: cx, y: cy - outer))
            path.line(to: NSPoint(x: cx - inner, y: cy - inner))
            path.line(to: NSPoint(x: cx - outer, y: cy))
            path.line(to: NSPoint(x: cx - inner, y: cy + inner))
            path.close()
            
            color.setFill()
            path.fill()
            return true
        }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            if self.starImageCache.count > 32 {
                self.starImageCache.removeAll()
            }
            self.starImageCache[color] = cgImage
            return cgImage
        }
        return nil
    }
}
