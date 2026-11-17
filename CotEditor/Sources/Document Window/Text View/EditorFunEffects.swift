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

/// Built-in CoreAnimation visual effects for rhythmic, immersive typing feedback,
/// inline habit ghost-completion micro-animations, and Neovide-inspired Vim cursor motion trails.
@MainActor final class EditorFunEffectsController {
    
    // MARK: Private Properties
    
    private weak var textView: EditorTextView?
    
    // Typing rhythm state (no audio — pure visual kinetic rhythm)
    private var lastKeystrokeTime: CFTimeInterval = 0
    private var rhythmStreak: Int = 0
    
    // Pre-allocated GPU-composited typewriter layers
    private weak var hostedLayer: CALayer?
    private var typewriterRootLayer: CALayer?
    private var caretPulseLayer: CALayer?
    private var rippleRingLayer: CAShapeLayer?
    private var sparkPool: [CALayer] = []
    private var sparkPoolIndex = 0
    
    // Inline ghost completion layers & acceptance sweep
    private var ghostRootLayer: CALayer?
    private var ghostContainerLayer: CALayer?
    private var ghostSweepLayer: CALayer?
    
    // Reusable Vim cursor trail & glide layers
    private var vimRootLayer: CALayer?
    private var cursorOverlayLayer: CALayer?
    private var trailLayer: CAShapeLayer?
    private var lastCursorRect: NSRect?
    private var hideOverlayTask: Task<Void, Never>?
    
    
    init(textView: EditorTextView) {
        
        self.textView = textView
    }
    
    
    // MARK: Public API
    
    /// Clears cached cursor tracking and hides any transient overlays (e.g. on focus loss, scroll, or zoom).
    func resetCursorTracking() {
        
        self.hideOverlayTask?.cancel()
        self.hideOverlayTask = nil
        self.lastCursorRect = nil
        self.hideGhostSuggestion(animated: false)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.cursorOverlayLayer?.removeAllAnimations()
        self.cursorOverlayLayer?.opacity = 0
        self.trailLayer?.removeAllAnimations()
        self.trailLayer?.opacity = 0
        CATransaction.commit()
    }
    
    
    /// Triggers rhythmic kinetic typing feedback (caret pulse + expanding wave ring + glowing particles).
    func triggerTypewriterBurst(at rect: NSRect, color: NSColor? = nil, intensityScale: CGFloat = 1.0) {
        
        let isEnabled = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
        guard isEnabled else { return }
        guard let textView = self.textView, textView.window?.isKeyWindow == true else { return }
        
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        self.ensureTypewriterLayers(in: hostLayer)
        
        let now = CACurrentMediaTime()
        if now - self.lastKeystrokeTime < 0.42 {
            self.rhythmStreak = min(self.rhythmStreak + 1, 14)
        } else {
            self.rhythmStreak = 0
        }
        self.lastKeystrokeTime = now
        
        let rhythmFactor = (1.0 + CGFloat(self.rhythmStreak) * 0.048) * intensityScale
        let baseColor = color ?? textView.effectiveCursorColor
        let accentHighlight = NSColor.controlAccentColor.blended(withFraction: 0.35, of: baseColor) ?? baseColor
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        // 1. Caret kinetic glow pop
        if let pulse = self.caretPulseLayer {
            let pulseSize = CGSize(width: max(10, rect.width + 10), height: max(20, rect.height + 6))
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulse.removeAllAnimations()
            pulse.position = center
            pulse.bounds = CGRect(origin: .zero, size: pulseSize)
            pulse.backgroundColor = baseColor.withAlphaComponent(0.38).cgColor
            pulse.cornerRadius = 4.5
            pulse.opacity = 0
            CATransaction.commit()
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.72
            scaleAnim.toValue = 1.48 * min(1.3, rhythmFactor)
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.92, 0.0]
            alphaAnim.keyTimes = [0.0, 0.16, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, alphaAnim]
            group.duration = 0.21
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            pulse.add(group, forKey: "caretPulse")
        }
        
        // 2. Expanding rhythmic ripple wave around the caret
        if let ripple = self.rippleRingLayer {
            let baseRadius = max(7.0, min(11.0, rect.height * 0.42))
            let ringRect = CGRect(x: -baseRadius, y: -baseRadius, width: baseRadius * 2, height: baseRadius * 2)
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ripple.removeAllAnimations()
            ripple.position = center
            ripple.bounds = ringRect
            ripple.path = CGPath(ellipseIn: ringRect, transform: nil)
            ripple.strokeColor = accentHighlight.withAlphaComponent(0.72).cgColor
            ripple.fillColor = nil
            ripple.lineWidth = 1.6
            ripple.opacity = 0
            CATransaction.commit()
            
            let ringScale = CABasicAnimation(keyPath: "transform.scale")
            ringScale.fromValue = 0.35
            ringScale.toValue = 1.85 * min(1.35, rhythmFactor)
            
            let ringWidth = CABasicAnimation(keyPath: "lineWidth")
            ringWidth.fromValue = 1.8
            ringWidth.toValue = 0.35
            
            let ringAlpha = CAKeyframeAnimation(keyPath: "opacity")
            ringAlpha.values = [0.0, 0.78, 0.0]
            ringAlpha.keyTimes = [0.0, 0.15, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [ringScale, ringWidth, ringAlpha]
            group.duration = 0.25
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            ripple.add(group, forKey: "rhythmRipple")
        }
        
        // 3. Velocity sparks scaled by typing cadence
        guard !self.sparkPool.isEmpty else { return }
        let sparkCount = max(5, Int(round(CGFloat(7 + min(5, self.rhythmStreak / 2)) * intensityScale)))
        
        for i in 0..<sparkCount {
            let spark = self.sparkPool[self.sparkPoolIndex]
            self.sparkPoolIndex = (self.sparkPoolIndex + 1) % self.sparkPool.count
            
            let baseAngle = (.pi * 2.0 / Double(sparkCount)) * Double(i) + Double.random(in: -0.32...0.32)
            let travel = CGFloat.random(in: 15...34) * min(1.4, rhythmFactor)
            let dx = cos(baseAngle) * travel
            let dy = sin(baseAngle) * travel - CGFloat.random(in: 3...9)  // upward arc in flipped view
            let endPoint = CGPoint(x: center.x + dx, y: center.y + dy)
            let startScale = CGFloat.random(in: 0.85...1.32)
            let particleColor = (i % 3 == 0 ? accentHighlight : baseColor).cgColor
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spark.removeAllAnimations()
            spark.position = center
            spark.backgroundColor = particleColor
            spark.opacity = 0
            CATransaction.commit()
            
            let moveAnim = CABasicAnimation(keyPath: "position")
            moveAnim.fromValue = NSValue(point: center)
            moveAnim.toValue = NSValue(point: endPoint)
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = startScale
            scaleAnim.toValue = 0.08
            
            let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
            fadeAnim.values = [0.0, 0.96, 0.0]
            fadeAnim.keyTimes = [0.0, 0.14, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [moveAnim, scaleAnim, fadeAnim]
            group.duration = Double.random(in: 0.27...0.40)
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            spark.add(group, forKey: "sparkBurst")
        }
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
        
        // Subtle entrance micro-animation (glide in + fade + crisp settle)
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
        
        self.triggerTypewriterBurst(at: endRect, color: NSColor.controlAccentColor, intensityScale: 1.15)
    }
    
    
    // MARK: Vim Cursor Glide & Trail
    
    /// Animates a crisp, bounded Vim cursor glide + tapered comet trail strictly inside the pane.
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
        
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        self.ensureVimLayers(in: hostLayer)
        
        let targetCenter = CGPoint(x: newRect.midX, y: newRect.midY)
        
        // If an animation is already in flight, continue seamlessly from its current rendered center
        // so rapid `jjjjj` / `lllll` holds never snap backwards or stutter.
        let inFlightCenter: CGPoint? = if let overlay = self.cursorOverlayLayer,
                                          overlay.opacity > 0.05,
                                          let presentation = overlay.presentation(),
                                          presentation.position.x.isFinite, presentation.position.y.isFinite
        {
            presentation.position
        } else {
            nil
        }
        
        let rawSourceRect = oldRect ?? self.lastCursorRect ?? newRect
        self.lastCursorRect = newRect
        
        // Ignore stale source positions outside the current visible viewport (e.g. after scrolling)
        let visible = textView.visibleRect.insetBy(dx: -40, dy: -60)
        var startCenter = inFlightCenter ?? CGPoint(x: rawSourceRect.midX, y: rawSourceRect.midY)
        var startSize = rawSourceRect.size
        if !visible.contains(startCenter) || startSize.height > 80 {
            startCenter = targetCenter
            startSize = newRect.size
        }
        
        let dx = targetCenter.x - startCenter.x
        let dy = targetCenter.y - startCenter.y
        let distance = hypot(dx, dy)
        guard distance > 1.5 else { return }
        
        // Cap long-distance jumps (like `gg`, `G`, `⌃D`) so trails stay sleek and local,
        // never streaking across the entire window.
        let maxTrailDistance: CGFloat = 220
        if distance > maxTrailDistance {
            let ratio = 44.0 / distance
            startCenter = CGPoint(x: targetCenter.x - dx * ratio, y: targetCenter.y - dy * ratio)
        }
        
        // 1. Clean convex tapered comet trail (reused single CAShapeLayer)
        let effectiveDistance = hypot(targetCenter.x - startCenter.x, targetCenter.y - startCenter.y)
        if effectiveDistance > 5, let trail = self.trailLayer {
            let path = Self.sweptTrailPath(
                from: startCenter,
                fromSize: startSize,
                to: targetCenter,
                toSize: newRect.size
            )
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            trail.removeAllAnimations()
            trail.path = path
            trail.fillColor = color.withAlphaComponent(0.24).cgColor
            trail.opacity = 0
            CATransaction.commit()
            
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.9
            fade.toValue = 0.0
            fade.duration = 0.11
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.isRemovedOnCompletion = true
            trail.add(fade, forKey: "trailFade")
        }
        
        // 2. Critically-damped cursor glide (snappy, zero overshoot, zero drift)
        guard let cursorLayer = self.cursorOverlayLayer else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.removeAllAnimations()
        cursorLayer.backgroundColor = color.withAlphaComponent(0.55).cgColor
        cursorLayer.shadowColor = color.cgColor
        cursorLayer.shadowOpacity = 0.35
        cursorLayer.shadowRadius = 3.5
        cursorLayer.shadowOffset = .zero
        cursorLayer.position = targetCenter
        cursorLayer.bounds = CGRect(origin: .zero, size: newRect.size)
        cursorLayer.opacity = 1.0
        CATransaction.commit()
        
        let posAnim = CASpringAnimation(keyPath: "position")
        posAnim.fromValue = NSValue(point: startCenter)
        posAnim.toValue = NSValue(point: targetCenter)
        posAnim.mass = 0.45
        posAnim.stiffness = 780
        posAnim.damping = 56
        posAnim.initialVelocity = 0
        posAnim.duration = min(0.14, posAnim.settlingDuration)
        
        let boundsAnim = CASpringAnimation(keyPath: "bounds")
        boundsAnim.fromValue = NSValue(rect: CGRect(origin: .zero, size: startSize))
        boundsAnim.toValue = NSValue(rect: CGRect(origin: .zero, size: newRect.size))
        boundsAnim.mass = 0.45
        boundsAnim.stiffness = 780
        boundsAnim.damping = 56
        boundsAnim.duration = min(0.14, boundsAnim.settlingDuration)
        
        cursorLayer.add(posAnim, forKey: "springPosition")
        cursorLayer.add(boundsAnim, forKey: "springBounds")
        
        self.hideOverlayTask?.cancel()
        self.hideOverlayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(130))
            guard !Task.isCancelled, let overlay = self?.cursorOverlayLayer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            overlay.opacity = 0
            CATransaction.commit()
        }
    }
    
    
    // MARK: Private Helpers
    
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
        self.rippleRingLayer = nil
        self.sparkPool.removeAll()
        
        self.ghostRootLayer?.removeFromSuperlayer()
        self.ghostRootLayer = nil
        self.ghostContainerLayer = nil
        self.ghostSweepLayer = nil
        
        self.vimRootLayer?.removeFromSuperlayer()
        self.vimRootLayer = nil
        self.cursorOverlayLayer = nil
        self.trailLayer = nil
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
        
        let ripple = CAShapeLayer()
        ripple.opacity = 0
        root.addSublayer(ripple)
        self.rippleRingLayer = ripple
        
        let sparkImage = Self.sparkGlowCGImage
        var pool: [CALayer] = []
        pool.reserveCapacity(64)
        for index in 0..<64 {
            let size: CGFloat = (index % 3 == 0) ? 7.5 : 5.5
            let spark = CALayer()
            spark.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            spark.cornerRadius = size / 2
            spark.contents = sparkImage
            spark.opacity = 0
            root.addSublayer(spark)
            pool.append(spark)
        }
        self.sparkPool = pool
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
        
        let trail = CAShapeLayer()
        trail.opacity = 0
        root.addSublayer(trail)
        self.trailLayer = trail
        
        let overlay = CALayer()
        overlay.cornerRadius = 2.0
        overlay.opacity = 0
        root.addSublayer(overlay)
        self.cursorOverlayLayer = overlay
    }
    
    
    /// Builds a clean tapered quadrilateral connecting `startCenter` -> `endCenter` without self-intersection.
    private static func sweptTrailPath(
        from startCenter: CGPoint,
        fromSize: CGSize,
        to endCenter: CGPoint,
        toSize: CGSize
    ) -> CGPath {
        
        let dx = endCenter.x - startCenter.x
        let dy = endCenter.y - startCenter.y
        let len = max(1, hypot(dx, dy))
        let nx = -dy / len
        let ny = dx / len
        
        let startHalf = max(1.5, min(fromSize.width, fromSize.height) * 0.28)
        let endHalf = max(2.5, min(toSize.width, toSize.height) * 0.44)
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: startCenter.x + nx * startHalf, y: startCenter.y + ny * startHalf))
        path.addLine(to: CGPoint(x: endCenter.x + nx * endHalf, y: endCenter.y + ny * endHalf))
        path.addLine(to: CGPoint(x: endCenter.x - nx * endHalf, y: endCenter.y - ny * endHalf))
        path.addLine(to: CGPoint(x: startCenter.x - nx * startHalf, y: startCenter.y - ny * startHalf))
        path.closeSubpath()
        return path
    }
    
    
    private static let sparkGlowCGImage: CGImage? = {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.98),
                NSColor.white.withAlphaComponent(0.55),
                NSColor.white.withAlphaComponent(0.0),
            ])
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()
}
