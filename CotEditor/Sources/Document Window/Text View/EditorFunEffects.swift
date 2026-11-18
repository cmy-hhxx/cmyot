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

/// Ready-made typing effect presets inspired by `activate-power-mode` / `vscode-power-mode`.
enum TypingEffectPreset: String, CaseIterable, Identifiable, Sendable {
    
    case powerMode = "powerMode"
    case fireworks = "fireworks"
    case magicStars = "magicStars"
    case neonPop = "neonPop"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .powerMode: "Power Mode 重力粒子 + 连击"
            case .fireworks: "绚烂烟花 (Fireworks)"
            case .magicStars: "魔法星尘 (Magic Sparkles)"
            case .neonPop: "极简霓虹波纹 (Neon Pop)"
        }
    }
    
    @MainActor static var current: TypingEffectPreset {
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: "powerMode")
        return TypingEffectPreset(rawValue: raw) ?? .powerMode
    }
}


/// Built-in CoreAnimation visual effects for `activate-power-mode` typing presets,
/// inline habit ghost-completion micro-animations, and Neovide-inspired Vim cursor motion trails.
@MainActor final class EditorFunEffectsController {
    
    // MARK: Private Properties
    
    private weak var textView: EditorTextView?
    
    // Power Mode combo streak state
    private var lastKeystrokeTime: CFTimeInterval = 0
    private var comboCount: Int = 0
    private var comboResetTask: Task<Void, Never>?
    
    // Pre-allocated GPU-composited particle & ripple pools
    private weak var hostedLayer: CALayer?
    private var typewriterRootLayer: CALayer?
    private var caretPulseLayer: CALayer?
    private var ripplePool: [CAShapeLayer] = []
    private var ripplePoolIndex = 0
    private var particlePool: [CALayer] = []
    private var particlePoolIndex = 0
    
    // Power Mode Combo HUD (anchored in the scroll view viewport, never scrolls with text)
    private weak var hostedScrollLayer: CALayer?
    private var comboHudContainer: CALayer?
    private var comboHudBadgeLayer: CALayer?
    private var comboHudBarTrackLayer: CALayer?
    private var comboHudBarFillLayer: CALayer?
    
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
        self.hideComboHud(animated: false)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.cursorOverlayLayer?.removeAllAnimations()
        self.cursorOverlayLayer?.opacity = 0
        self.trailLayer?.removeAllAnimations()
        self.trailLayer?.opacity = 0
        CATransaction.commit()
    }
    
    
    /// Triggers the user-selected ready-made typing visual preset at `rect`.
    func triggerTypewriterBurst(at rect: NSRect, color: NSColor? = nil, intensityScale: CGFloat = 1.0) {
        
        let isEnabled = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
        guard isEnabled else { return }
        guard let textView = self.textView, textView.window?.isKeyWindow == true else { return }
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        
        self.ensureTypewriterLayers(in: hostLayer)
        
        let now = CACurrentMediaTime()
        if now - self.lastKeystrokeTime < 1.8 {
            self.comboCount += 1
        } else {
            self.comboCount = 1
        }
        self.lastKeystrokeTime = now
        
        let preset = TypingEffectPreset.current
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let palette = self.resolvedPalette(for: textView, fallback: color ?? textView.effectiveCursorColor, preset: preset)
        
        switch preset {
            case .powerMode:
                self.emitPowerModeBurst(at: center, rect: rect, palette: palette, intensityScale: intensityScale)
                self.updateComboHud(in: textView, combo: self.comboCount)
            case .fireworks:
                self.emitFireworksBurst(at: center, rect: rect, palette: palette, intensityScale: intensityScale)
            case .magicStars:
                self.emitMagicStarsBurst(at: center, rect: rect, palette: palette, intensityScale: intensityScale)
            case .neonPop:
                self.emitNeonPopBurst(at: center, rect: rect, palette: palette, intensityScale: intensityScale)
        }
    }
    
    
    // MARK: Typing Effect Presets
    
    /// Authentic `activate-power-mode` / `vscode-power-mode` physics: parabolic gravity particles + combo meter.
    private func emitPowerModeBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        
        // Crisp caret energy flash
        if let pulse = self.caretPulseLayer {
            let pulseSize = CGSize(width: max(8, rect.width + 8), height: max(18, rect.height + 4))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulse.removeAllAnimations()
            pulse.position = center
            pulse.bounds = CGRect(origin: .zero, size: pulseSize)
            pulse.backgroundColor = palette[0].withAlphaComponent(0.32).cgColor
            pulse.cornerRadius = 3.5
            pulse.opacity = 0
            CATransaction.commit()
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.82
            scaleAnim.toValue = 1.32
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.85, 0.0]
            alphaAnim.keyTimes = [0.0, 0.16, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, alphaAnim]
            group.duration = 0.18
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            pulse.add(group, forKey: "caretPulse")
        }
        
        guard !self.particlePool.isEmpty else { return }
        let comboBoost = min(1.35, 1.0 + CGFloat(min(self.comboCount, 30)) * 0.012)
        let count = max(6, Int(round(CGFloat.random(in: 9...13) * intensityScale)))
        let gravity: CGFloat = 390.0  // downward in flipped coordinates (+y)
        
        for i in 0..<count {
            let particle = self.nextParticleLayer()
            let pColor = palette[i % palette.count]
            let size = CGFloat.random(in: 2.6...4.6)
            let isSquare = (i % 3 == 0)
            
            let duration = Double.random(in: 0.42...0.68)
            let vx = CGFloat.random(in: -125...125) * comboBoost
            let vy = CGFloat.random(in: -205 ... -75) * comboBoost
            
            let samples = 12
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let frac = CGFloat(step) / CGFloat(samples - 1)
                let t = CGFloat(duration) * frac
                let drag = 1.0 - 0.18 * frac
                let px = center.x + vx * t * drag
                let py = center.y + vy * t + 0.5 * gravity * t * t
                positions.append(NSValue(point: CGPoint(x: px, y: py)))
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particle.removeAllAnimations()
            particle.position = center
            particle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            particle.cornerRadius = isSquare ? 1.0 : size / 2
            particle.contents = isSquare ? nil : Self.tintedGlowCGImage(color: pColor)
            particle.backgroundColor = isSquare ? pColor.cgColor : nil
            particle.transform = CATransform3DIdentity
            particle.opacity = 0
            CATransaction.commit()
            
            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.values = positions
            posAnim.calculationMode = .linear
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 1.15
            scaleAnim.toValue = 0.18
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.98, 0.82, 0.0]
            alphaAnim.keyTimes = [0.0, 0.08, 0.62, 1.0]
            
            var animations: [CAAnimation] = [posAnim, scaleAnim, alphaAnim]
            if isSquare {
                let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
                rotAnim.fromValue = 0.0
                rotAnim.toValue = Double.random(in: -3.2...3.2)
                animations.append(rotAnim)
            }
            
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = duration
            group.isRemovedOnCompletion = true
            particle.add(group, forKey: "powerModeParticle")
        }
    }
    
    
    /// `vscode-power-mode` Fireworks preset: radiant multi-color streaks + glittering gravity embers.
    private func emitFireworksBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        // Central radial flash
        self.emitRippleRing(at: center, baseRadius: max(6, rect.height * 0.35), toScale: 2.1, color: palette[0], duration: 0.24)
        
        guard !self.particlePool.isEmpty else { return }
        let count = max(10, Int(round(CGFloat.random(in: 14...18) * intensityScale)))
        let gravity: CGFloat = 210.0
        
        for i in 0..<count {
            let particle = self.nextParticleLayer()
            let pColor = palette[i % palette.count]
            let angle = (.pi * 2.0 / Double(count)) * Double(i) + Double.random(in: -0.22...0.22)
            let speed = CGFloat.random(in: 85...185) * min(1.3, intensityScale)
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed - 40
            let duration = Double.random(in: 0.44...0.70)
            let isStreak = (i % 2 == 0)
            
            let samples = 10
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let frac = CGFloat(step) / CGFloat(samples - 1)
                let t = CGFloat(duration) * frac
                let px = center.x + vx * t * (1.0 - 0.14 * frac)
                let py = center.y + vy * t + 0.5 * gravity * t * t
                positions.append(NSValue(point: CGPoint(x: px, y: py)))
            }
            
            let w: CGFloat = isStreak ? CGFloat.random(in: 8...13) : CGFloat.random(in: 3.5...5.5)
            let h: CGFloat = isStreak ? 2.2 : w
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particle.removeAllAnimations()
            particle.position = center
            particle.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            particle.cornerRadius = h / 2
            particle.contents = isStreak ? nil : Self.tintedGlowCGImage(color: pColor)
            particle.backgroundColor = isStreak ? pColor.cgColor : nil
            particle.transform = isStreak ? CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1) : CATransform3DIdentity
            particle.opacity = 0
            CATransaction.commit()
            
            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.values = positions
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 1.1
            scaleAnim.toValue = 0.12
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 1.0, 0.78, 0.0]
            alphaAnim.keyTimes = [0.0, 0.08, 0.58, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [posAnim, scaleAnim, alphaAnim]
            group.duration = duration
            group.isRemovedOnCompletion = true
            particle.add(group, forKey: "fireworkParticle")
        }
    }
    
    
    /// `vscode-power-mode` Magic Sparkles preset: spinning 4-point twinkling star sparkles rising upward.
    private func emitMagicStarsBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        guard !self.particlePool.isEmpty else { return }
        let count = max(6, Int(round(CGFloat.random(in: 8...11) * intensityScale)))
        
        for i in 0..<count {
            let star = self.nextParticleLayer()
            let pColor = palette[i % palette.count]
            let size = CGFloat.random(in: 7.5...12.5)
            let duration = Double.random(in: 0.50...0.82)
            let dx = CGFloat.random(in: -44...44)
            let dy = CGFloat.random(in: -56 ... -16)
            let sway = CGFloat.random(in: -10...10)
            
            let samples = 10
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let t = CGFloat(step) / CGFloat(samples - 1)
                let ease = 1.0 - pow(1.0 - t, 2.2)
                let px = center.x + dx * ease + sin(t * .pi * 2.0) * sway * 0.45
                let py = center.y + dy * ease
                positions.append(NSValue(point: CGPoint(x: px, y: py)))
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            star.removeAllAnimations()
            star.position = center
            star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            star.cornerRadius = 0
            star.backgroundColor = nil
            star.contents = Self.tintedStarCGImage(color: pColor)
            star.transform = CATransform3DIdentity
            star.opacity = 0
            CATransaction.commit()
            
            let posAnim = CAKeyframeAnimation(keyPath: "position")
            posAnim.values = positions
            
            let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnim.values = [0.25, 1.25, 0.85, 1.15, 0.1]
            scaleAnim.keyTimes = [0.0, 0.22, 0.48, 0.72, 1.0]
            
            let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotAnim.fromValue = Double.random(in: -0.6...0.6)
            rotAnim.toValue = Double.random(in: 1.8...3.6) * (i.isMultiple(of: 2) ? 1.0 : -1.0)
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 1.0, 0.9, 0.0]
            alphaAnim.keyTimes = [0.0, 0.14, 0.68, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [posAnim, scaleAnim, rotAnim, alphaAnim]
            group.duration = duration
            group.isRemovedOnCompletion = true
            star.add(group, forKey: "magicStar")
        }
    }
    
    
    /// Clean overlapping shockwave rings + subtle caret flash.
    private func emitNeonPopBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        let baseRadius = max(6.5, min(10.5, rect.height * 0.4))
        self.emitRippleRing(
            at: center,
            baseRadius: baseRadius,
            toScale: 2.05 * min(1.3, intensityScale),
            color: palette[0],
            duration: 0.28
        )
        
        if let pulse = self.caretPulseLayer {
            let pulseSize = CGSize(width: max(10, rect.width + 10), height: max(20, rect.height + 6))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulse.removeAllAnimations()
            pulse.position = center
            pulse.bounds = CGRect(origin: .zero, size: pulseSize)
            pulse.backgroundColor = palette[1 % palette.count].withAlphaComponent(0.35).cgColor
            pulse.cornerRadius = 4.5
            pulse.opacity = 0
            CATransaction.commit()
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.78
            scaleAnim.toValue = 1.45
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.9, 0.0]
            alphaAnim.keyTimes = [0.0, 0.18, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, alphaAnim]
            group.duration = 0.21
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            group.isRemovedOnCompletion = true
            pulse.add(group, forKey: "neonCaret")
        }
    }
    
    
    private func emitRippleRing(at center: CGPoint, baseRadius: CGFloat, toScale: CGFloat, color: NSColor, duration: CFTimeInterval) {
        
        guard !self.ripplePool.isEmpty else { return }
        let ripple = self.ripplePool[self.ripplePoolIndex]
        self.ripplePoolIndex = (self.ripplePoolIndex + 1) % self.ripplePool.count
        
        let ringRect = CGRect(x: -baseRadius, y: -baseRadius, width: baseRadius * 2, height: baseRadius * 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ripple.removeAllAnimations()
        ripple.position = center
        ripple.bounds = ringRect
        ripple.path = CGPath(ellipseIn: ringRect, transform: nil)
        ripple.strokeColor = color.withAlphaComponent(0.75).cgColor
        ripple.fillColor = nil
        ripple.lineWidth = 1.7
        ripple.opacity = 0
        CATransaction.commit()
        
        let ringScale = CABasicAnimation(keyPath: "transform.scale")
        ringScale.fromValue = 0.4
        ringScale.toValue = toScale
        
        let ringWidth = CABasicAnimation(keyPath: "lineWidth")
        ringWidth.fromValue = 1.8
        ringWidth.toValue = 0.35
        
        let ringAlpha = CAKeyframeAnimation(keyPath: "opacity")
        ringAlpha.values = [0.0, 0.85, 0.0]
        ringAlpha.keyTimes = [0.0, 0.15, 1.0]
        
        let group = CAAnimationGroup()
        group.animations = [ringScale, ringWidth, ringAlpha]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        group.isRemovedOnCompletion = true
        ripple.add(group, forKey: "rippleRing")
    }
    
    
    // MARK: Power Mode Combo HUD
    
    private func updateComboHud(in textView: EditorTextView, combo: Int) {
        
        guard combo >= 3 else {
            self.hideComboHud(animated: true)
            return
        }
        guard let scrollView = textView.enclosingScrollView else { return }
        if !scrollView.wantsLayer {
            scrollView.wantsLayer = true
        }
        guard let scrollLayer = scrollView.layer else { return }
        self.ensureComboHudLayers(in: scrollLayer)
        
        guard
            let container = self.comboHudContainer,
            let badgeLayer = self.comboHudBadgeLayer,
            let trackLayer = self.comboHudBarTrackLayer,
            let fillLayer = self.comboHudBarFillLayer
        else { return }
        
        let tierTitle: String
        let accentColor: NSColor
        switch combo {
            case ..<15:
                tierTitle = "COMBO"
                accentColor = NSColor(srgbRed: 0.0, green: 0.73, blue: 0.98, alpha: 1.0)
            case 15..<30:
                tierTitle = "NICE!"
                accentColor = NSColor(srgbRed: 0.0, green: 0.96, blue: 0.83, alpha: 1.0)
            case 30..<60:
                tierTitle = "GREAT!"
                accentColor = NSColor(srgbRed: 0.95, green: 0.36, blue: 0.71, alpha: 1.0)
            case 60..<100:
                tierTitle = "UNSTOPPABLE!"
                accentColor = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.11, alpha: 1.0)
            default:
                tierTitle = "GODLIKE!"
                accentColor = NSColor(srgbRed: 1.0, green: 0.30, blue: 0.36, alpha: 1.0)
        }
        
        let scale = textView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let countText = "×\(combo)"
        let tierFont = NSFont.systemFont(ofSize: 9.5, weight: .heavy)
        let countFont = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .black)
        
        let tierAttr = NSAttributedString(string: tierTitle, attributes: [
            .font: tierFont,
            .foregroundColor: accentColor,
            .kern: 1.1,
        ])
        let countAttr = NSAttributedString(string: countText, attributes: [
            .font: countFont,
            .foregroundColor: accentColor,
        ])
        
        let tierSize = tierAttr.size()
        let countSize = countAttr.size()
        let hudWidth = max(78, ceil(max(tierSize.width, countSize.width)) + 16)
        let badgeHeight = ceil(tierSize.height + countSize.height) + 4
        let totalHeight = badgeHeight + 8
        
        let rendered = NSImage(size: NSSize(width: hudWidth, height: badgeHeight), flipped: true) { _ in
            tierAttr.draw(at: NSPoint(x: hudWidth - tierSize.width - 2, y: 0))
            countAttr.draw(at: NSPoint(x: hudWidth - countSize.width - 2, y: tierSize.height - 1))
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: NSSize(width: hudWidth, height: badgeHeight))
        let scaleTransform = NSAffineTransform()
        scaleTransform.scale(by: scale)
        let cgImage = rendered.cgImage(forProposedRect: &proposedRect, context: nil, hints: [.ctm: scaleTransform])
        
        let viewBounds = scrollView.bounds
        let marginRight: CGFloat = 18
        let marginTop: CGFloat = 14
        let originX = max(12, viewBounds.width - hudWidth - marginRight)
        let originY = scrollView.isFlipped ? marginTop : max(12, viewBounds.height - totalHeight - marginTop)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAllAnimations()
        container.bounds = CGRect(x: 0, y: 0, width: hudWidth, height: totalHeight)
        container.position = CGPoint(x: originX + hudWidth / 2, y: originY + totalHeight / 2)
        container.opacity = 1.0
        
        badgeLayer.frame = CGRect(x: 0, y: 0, width: hudWidth, height: badgeHeight)
        badgeLayer.contents = cgImage
        badgeLayer.contentsScale = scale
        badgeLayer.contentsGravity = .resize
        
        let trackWidth = min(hudWidth, max(58, countSize.width + 12))
        let trackY = badgeHeight + 2
        trackLayer.frame = CGRect(x: hudWidth - trackWidth, y: trackY, width: trackWidth, height: 3)
        trackLayer.backgroundColor = accentColor.withAlphaComponent(0.18).cgColor
        trackLayer.cornerRadius = 1.5
        
        fillLayer.removeAllAnimations()
        fillLayer.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: trackWidth, height: 3)
        fillLayer.position = CGPoint(x: trackWidth, y: 1.5)
        fillLayer.backgroundColor = accentColor.cgColor
        fillLayer.cornerRadius = 1.5
        CATransaction.commit()
        
        // Spring pop on container
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 1.18
        pop.toValue = 1.0
        pop.mass = 0.5
        pop.stiffness = 520
        pop.damping = 22
        pop.duration = min(0.24, pop.settlingDuration)
        container.add(pop, forKey: "comboPop")
        
        // Decaying timer bar (1.8s timeout)
        let decay = CABasicAnimation(keyPath: "transform.scale.x")
        decay.fromValue = 1.0
        decay.toValue = 0.0
        decay.duration = 1.8
        decay.fillMode = .forwards
        decay.isRemovedOnCompletion = false
        fillLayer.add(decay, forKey: "comboDecay")
        
        self.comboResetTask?.cancel()
        self.comboResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            self?.comboCount = 0
            self?.hideComboHud(animated: true)
        }
    }
    
    
    private func hideComboHud(animated: Bool) {
        
        self.comboResetTask?.cancel()
        self.comboResetTask = nil
        
        guard let container = self.comboHudContainer, container.opacity > 0.01 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.22)
        container.opacity = 0
        CATransaction.commit()
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
        
        let maxTrailDistance: CGFloat = 220
        if distance > maxTrailDistance {
            let ratio = 44.0 / distance
            startCenter = CGPoint(x: targetCenter.x - dx * ratio, y: targetCenter.y - dy * ratio)
        }
        
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
    
    private func nextParticleLayer() -> CALayer {
        
        let layer = self.particlePool[self.particlePoolIndex]
        self.particlePoolIndex = (self.particlePoolIndex + 1) % self.particlePool.count
        return layer
    }
    
    
    private func resolvedPalette(for textView: EditorTextView, fallback: NSColor, preset: TypingEffectPreset) -> [NSColor] {
        
        var syntaxColor: NSColor?
        let loc = textView.selectedRange().location
        if loc > 0, let lm = textView.layoutManager {
            let probeIndex = min(loc - 1, max(0, (textView.string as NSString).length - 1))
            if let attrColor = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: probeIndex, effectiveRange: nil) as? NSColor,
               let rgb = attrColor.usingColorSpace(.sRGB),
               rgb.saturationComponent > 0.25
            {
                syntaxColor = attrColor
            }
        }
        
        switch preset {
            case .powerMode:
                let base: [NSColor] = [
                    NSColor(srgbRed: 0.00, green: 0.73, blue: 0.98, alpha: 1.0), // #00BBF9
                    NSColor(srgbRed: 0.00, green: 0.96, blue: 0.83, alpha: 1.0), // #00F5D4
                    NSColor(srgbRed: 0.95, green: 0.36, blue: 0.71, alpha: 1.0), // #F15BB5
                    NSColor(srgbRed: 0.99, green: 0.89, blue: 0.25, alpha: 1.0), // #FEE440
                    NSColor(srgbRed: 0.61, green: 0.36, blue: 0.90, alpha: 1.0), // #9B5DE5
                ]
                if let syntaxColor {
                    return [syntaxColor] + base
                }
                return [fallback] + base
                
            case .fireworks:
                return [
                    NSColor(srgbRed: 1.00, green: 0.35, blue: 0.37, alpha: 1.0), // #FF595E
                    NSColor(srgbRed: 1.00, green: 0.79, blue: 0.23, alpha: 1.0), // #FFCA3A
                    NSColor(srgbRed: 0.54, green: 0.79, blue: 0.15, alpha: 1.0), // #8AC926
                    NSColor(srgbRed: 0.10, green: 0.51, blue: 0.77, alpha: 1.0), // #1982C4
                    NSColor(srgbRed: 1.00, green: 0.57, blue: 0.30, alpha: 1.0), // #FF924C
                ]
                
            case .magicStars:
                return [
                    NSColor(srgbRed: 0.75, green: 0.52, blue: 0.99, alpha: 1.0),
                    NSColor(srgbRed: 0.30, green: 0.79, blue: 0.94, alpha: 1.0),
                    NSColor(srgbRed: 1.00, green: 0.84, blue: 0.35, alpha: 1.0),
                    NSColor(srgbRed: 0.98, green: 0.52, blue: 0.78, alpha: 1.0),
                ]
                
            case .neonPop:
                let accent = NSColor.controlAccentColor.blended(withFraction: 0.35, of: fallback) ?? fallback
                return [syntaxColor ?? fallback, accent]
        }
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
        
        var ripples: [CAShapeLayer] = []
        ripples.reserveCapacity(8)
        for _ in 0..<8 {
            let ripple = CAShapeLayer()
            ripple.opacity = 0
            root.addSublayer(ripple)
            ripples.append(ripple)
        }
        self.ripplePool = ripples
        
        var pool: [CALayer] = []
        pool.reserveCapacity(96)
        for _ in 0..<96 {
            let particle = CALayer()
            particle.opacity = 0
            root.addSublayer(particle)
            pool.append(particle)
        }
        self.particlePool = pool
    }
    
    
    private func ensureComboHudLayers(in scrollLayer: CALayer) {
        
        if self.hostedScrollLayer !== scrollLayer {
            self.comboHudContainer?.removeFromSuperlayer()
            self.comboHudContainer = nil
            self.comboHudBadgeLayer = nil
            self.comboHudBarTrackLayer = nil
            self.comboHudBarFillLayer = nil
            self.hostedScrollLayer = scrollLayer
        }
        guard self.comboHudContainer == nil else { return }
        
        let container = CALayer()
        container.zPosition = 240
        container.opacity = 0
        scrollLayer.addSublayer(container)
        self.comboHudContainer = container
        
        let badge = CALayer()
        container.addSublayer(badge)
        self.comboHudBadgeLayer = badge
        
        let track = CALayer()
        track.masksToBounds = true
        container.addSublayer(track)
        self.comboHudBarTrackLayer = track
        
        let fill = CALayer()
        track.addSublayer(fill)
        self.comboHudBarFillLayer = fill
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
    
    
    private static var glowImageCache: [NSColor: CGImage] = [:]
    
    
    private static func tintedGlowCGImage(color: NSColor) -> CGImage? {
        
        if let cached = self.glowImageCache[color] {
            return cached
        }
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.95),
                color.withAlphaComponent(0.90),
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
    
    
    private static var starImageCache: [NSColor: CGImage] = [:]
    
    
    private static func tintedStarCGImage(color: NSColor) -> CGImage? {
        
        if let cached = self.starImageCache[color] {
            return cached
        }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY
            let outer = rect.width * 0.46
            let inner = rect.width * 0.14
            
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
