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
import CoreText
import Defaults
import QuartzCore

/// Ready-made typing effect presets inspired by `activate-power-mode` / `vscode-power-mode`,
/// balanced for crisp, tactile typing feedback without visual clutter.
enum TypingEffectPreset: String, CaseIterable, Identifiable, Sendable {
    
    case powerMode = "powerMode"
    case fireworks = "fireworks"
    case magicStars = "magicStars"
    case neonPop = "neonPop"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
            case .powerMode: "律动粒子 + 连击 (Power Mode)"
            case .fireworks: "灵动花火 (Fireworks)"
            case .magicStars: "微芒星尘 (Magic Sparkles)"
            case .neonPop: "极简波纹 (Neon Pop)"
        }
    }
    
    /// Resolves both current and legacy stored preference strings cleanly.
    static func resolve(_ raw: String) -> TypingEffectPreset {
        if let exact = TypingEffectPreset(rawValue: raw) {
            return exact
        }
        return switch raw {
            case "luxeGlow": .powerMode
            case "silkRipple": .neonPop
            case "stardust": .magicStars
            default: .powerMode
        }
    }
    
    @MainActor static var current: TypingEffectPreset {
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.typewriterEffectStyle, default: "powerMode")
        return Self.resolve(raw)
    }
}


/// Built-in CoreAnimation visual effects for tactile typing feedback,
/// inline habit ghost-completion micro-animations, and Neovide-inspired 4-corner spring Vim cursor physics.
@MainActor final class EditorFunEffectsController {
    
    // MARK: Public State
    
    /// `true` while our persistent GPU-composited Vim cursor layer owns cursor rendering
    /// (Normal / Visual / Replace modes when focused and enabled), suppressing AppKit's
    /// blinking/2pt-clipped `drawInsertionPoint` so there is never double-cursor overlap or flicker.
    var ownsVimCursorDrawing: Bool {
        guard UserDefaults.standard[.vimMode],
              VimState.shared.mode != .insert,
              let textView = self.textView,
              textView.window?.isKeyWindow == true,
              textView.window?.firstResponder === textView
        else { return false }
        return UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
    }
    
    /// Legacy alias kept for compatibility.
    var isVimCursorInFlight: Bool { self.ownsVimCursorDrawing }
    
    
    // MARK: Private Types
    
    private struct FluidCursorState {
        var center: CGPoint
        var centerVelocity: CGPoint
        var size: CGSize
        var sizeVelocity: CGSize
        var omega: CGFloat
        var zeta: CGFloat
    }
    
    private final class DisplayLinkProxy: NSObject {
        weak var owner: EditorFunEffectsController?
        init(owner: EditorFunEffectsController) { self.owner = owner }
        @objc func step(_ link: CADisplayLink) {
            MainActor.assumeIsolated {
                self.owner?.stepVimCursorDisplayLink(link)
            }
        }
    }
    
    
    // MARK: Private Properties
    
    private weak var textView: EditorTextView?
    
    // Tactile typing combo streak state
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
    
    // Subtle Combo HUD (anchored in the scroll view viewport, never scrolls with text)
    private weak var hostedScrollLayer: CALayer?
    private var comboHudContainer: CALayer?
    private var comboHudBadgeLayer: CALayer?
    private var comboHudBarTrackLayer: CALayer?
    private var comboHudBarFillLayer: CALayer?
    
    // Inline ghost completion layers & acceptance sweep
    private var ghostRootLayer: CALayer?
    private var ghostContainerLayer: CALayer?
    private var ghostSweepLayer: CALayer?
    
    // Persistent 120Hz Apple-style fluid spring Vim cursor + luminous wake trail
    private var vimRootLayer: CALayer?
    private var vimCursorLayer: CAShapeLayer?
    private var vimTrailLayers: [CAShapeLayer] = []
    private var trailRects: [NSRect] = []
    private var fluidCursor: FluidCursorState?
    private var currentTargetRect: NSRect?
    private var vimDisplayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var lastStepTime: CFTimeInterval = 0
    private var currentTrailColor: NSColor = .controlAccentColor
    private var currentCursorAlpha: CGFloat = 0.56
    private static let trailLayerCount = 4
    
    
    init(textView: EditorTextView) {
        
        self.textView = textView
    }
    
    
    isolated deinit {
        
        self.vimDisplayLink?.invalidate()
        self.vimDisplayLink = nil
    }
    
    
    // MARK: Public API
    
    /// Clears cached cursor tracking and hides transient overlays (e.g. on focus loss or window change).
    func resetCursorTracking() {
        
        self.vimDisplayLink?.isPaused = true
        self.vimDisplayLink?.invalidate()
        self.vimDisplayLink = nil
        self.fluidCursor = nil
        self.currentTargetRect = nil
        self.trailRects.removeAll()
        self.hideGhostSuggestion(animated: false)
        self.hideComboHud(animated: false)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.vimCursorLayer?.removeAllAnimations()
        self.vimCursorLayer?.opacity = 0
        for layer in self.vimTrailLayers {
            layer.removeAllAnimations()
            layer.opacity = 0
        }
        CATransaction.commit()
    }
    
    
    /// Syncs the persistent GPU Vim cursor immediately (or smoothly when switching modes/colors/focus).
    func syncVimCursor(animated: Bool) {
        
        guard self.ownsVimCursorDrawing, let textView = self.textView else {
            self.hideVimCursorOnly()
            return
        }
        let loc: Int
        if VimState.shared.mode == .visual,
           VimState.shared.visualOwnerID == ObjectIdentifier(textView),
           let active = VimState.shared.visualActiveLocation
        {
            loc = active
        } else {
            loc = textView.selectedRange().location
        }
        guard let rect = textView.vimCursorRect(at: loc) else {
            self.hideVimCursorOnly()
            return
        }
        self.moveVimCursor(to: rect, color: textView.effectiveCursorColor, animated: animated)
    }
    
    
    /// Hides the persistent Vim cursor layer (e.g. when entering Insert mode).
    func hideVimCursorOnly() {
        
        self.vimDisplayLink?.isPaused = true
        self.fluidCursor = nil
        self.currentTargetRect = nil
        self.trailRects.removeAll()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.vimCursorLayer?.opacity = 0
        for layer in self.vimTrailLayers {
            layer.opacity = 0
        }
        CATransaction.commit()
    }
    
    
    /// Triggers tactile, balanced typing visual feedback at `rect`.
    func triggerTypewriterBurst(at rect: NSRect, color: NSColor? = nil, intensityScale: CGFloat = 1.0) {
        
        let isEnabled = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
        guard isEnabled else { return }
        guard let textView = self.textView, textView.window?.isKeyWindow == true else { return }
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        
        self.ensureTypewriterLayers(in: hostLayer)
        
        let now = CACurrentMediaTime()
        if now - self.lastKeystrokeTime < 1.6 {
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
    
    /// Balanced `powerMode` physics: crisp caret energy pop + 5–8 parabolic gravity particles + refined combo pill.
    private func emitPowerModeBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        
        // 1. Crisp caret tactile energy pop
        if let pulse = self.caretPulseLayer {
            let pulseSize = CGSize(width: max(8, rect.width + 7), height: max(18, rect.height + 3))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulse.removeAllAnimations()
            pulse.position = center
            pulse.bounds = CGRect(origin: .zero, size: pulseSize)
            pulse.backgroundColor = palette[0].withAlphaComponent(0.30).cgColor
            pulse.cornerRadius = 3.5
            pulse.opacity = 0
            CATransaction.commit()
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.85
            scaleAnim.toValue = 1.28
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.78, 0.0]
            alphaAnim.keyTimes = [0.0, 0.15, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, alphaAnim]
            group.duration = 0.17
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            pulse.add(group, forKey: "caretPulse")
        }
        
        // 2. Subtle shockwave ring on higher rhythm streaks
        if self.comboCount >= 5 {
            self.emitRippleRing(
                at: center,
                baseRadius: max(6.0, min(9.5, rect.height * 0.36)),
                toScale: 1.75,
                color: palette[0].withAlphaComponent(0.65),
                duration: 0.22
            )
        }
        
        // 3. Moderate gravity particles (5–8 particles: responsive and lively without cluttering the code)
        guard !self.particlePool.isEmpty else { return }
        let comboBoost = min(1.22, 1.0 + CGFloat(min(self.comboCount, 25)) * 0.009)
        let count = max(5, min(8, Int(round(CGFloat.random(in: 5.5...7.5) * intensityScale))))
        let gravity: CGFloat = 290.0  // downward in flipped coordinates (+y)
        
        for i in 0..<count {
            let particle = self.nextParticleLayer()
            let pColor = palette[i % palette.count]
            let size = CGFloat.random(in: 2.4...3.8)
            let isSquare = (i % 3 == 0)
            
            let duration = Double.random(in: 0.36...0.54)
            let vx = CGFloat.random(in: -78...78) * comboBoost
            let vy = CGFloat.random(in: -135 ... -48) * comboBoost
            
            let samples = 10
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let frac = CGFloat(step) / CGFloat(samples - 1)
                let t = CGFloat(duration) * frac
                let drag = 1.0 - 0.20 * frac
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
            scaleAnim.fromValue = 1.08
            scaleAnim.toValue = 0.18
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.90, 0.68, 0.0]
            alphaAnim.keyTimes = [0.0, 0.10, 0.60, 1.0]
            
            var animations: [CAAnimation] = [posAnim, scaleAnim, alphaAnim]
            if isSquare {
                let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
                rotAnim.fromValue = 0.0
                rotAnim.toValue = Double.random(in: -2.4...2.4)
                animations.append(rotAnim)
            }
            
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = duration
            group.isRemovedOnCompletion = true
            particle.add(group, forKey: "powerModeParticle")
        }
    }
    
    
    /// Refined Fireworks preset: radial ring + 8–10 crisp streaks and glowing embers.
    private func emitFireworksBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        self.emitRippleRing(at: center, baseRadius: max(5.5, rect.height * 0.32), toScale: 1.85, color: palette[0], duration: 0.22)
        
        guard !self.particlePool.isEmpty else { return }
        let count = max(7, min(11, Int(round(CGFloat.random(in: 8...10) * intensityScale))))
        let gravity: CGFloat = 175.0
        
        for i in 0..<count {
            let particle = self.nextParticleLayer()
            let pColor = palette[i % palette.count]
            let angle = (.pi * 2.0 / Double(count)) * Double(i) + Double.random(in: -0.20...0.20)
            let speed = CGFloat.random(in: 58...118) * min(1.2, intensityScale)
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed - 26
            let duration = Double.random(in: 0.38...0.56)
            let isStreak = (i % 2 == 0)
            
            let samples = 10
            var positions: [NSValue] = []
            positions.reserveCapacity(samples)
            for step in 0..<samples {
                let frac = CGFloat(step) / CGFloat(samples - 1)
                let t = CGFloat(duration) * frac
                let px = center.x + vx * t * (1.0 - 0.16 * frac)
                let py = center.y + vy * t + 0.5 * gravity * t * t
                positions.append(NSValue(point: CGPoint(x: px, y: py)))
            }
            
            let w: CGFloat = isStreak ? CGFloat.random(in: 6.5...10.0) : CGFloat.random(in: 3.0...4.5)
            let h: CGFloat = isStreak ? 1.8 : w
            
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
            scaleAnim.fromValue = 1.05
            scaleAnim.toValue = 0.14
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.92, 0.68, 0.0]
            alphaAnim.keyTimes = [0.0, 0.10, 0.58, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [posAnim, scaleAnim, alphaAnim]
            group.duration = duration
            group.isRemovedOnCompletion = true
            particle.add(group, forKey: "fireworkParticle")
        }
    }
    
    
    /// Magic Sparkles preset: 5–7 spinning 4-point twinkling star sparkles rising upward.
    private func emitMagicStarsBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        guard !self.particlePool.isEmpty else { return }
        let count = max(4, min(7, Int(round(CGFloat.random(in: 5...7) * intensityScale))))
        
        for i in 0..<count {
            let star = self.nextParticleLayer()
            let pColor = palette[i % palette.count]
            let size = CGFloat.random(in: 6.5...10.0)
            let duration = Double.random(in: 0.44...0.68)
            let dx = CGFloat.random(in: -32...32)
            let dy = CGFloat.random(in: -42 ... -14)
            let sway = CGFloat.random(in: -8...8)
            
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
            scaleAnim.values = [0.25, 1.15, 0.80, 1.05, 0.1]
            scaleAnim.keyTimes = [0.0, 0.22, 0.48, 0.72, 1.0]
            
            let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotAnim.fromValue = Double.random(in: -0.5...0.5)
            rotAnim.toValue = Double.random(in: 1.4...2.8) * (i.isMultiple(of: 2) ? 1.0 : -1.0)
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.92, 0.80, 0.0]
            alphaAnim.keyTimes = [0.0, 0.14, 0.68, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [posAnim, scaleAnim, rotAnim, alphaAnim]
            group.duration = duration
            group.isRemovedOnCompletion = true
            star.add(group, forKey: "magicStar")
        }
    }
    
    
    /// Clean shockwave ring + subtle caret flash.
    private func emitNeonPopBurst(at center: CGPoint, rect: NSRect, palette: [NSColor], intensityScale: CGFloat) {
        
        let baseRadius = max(6.0, min(9.5, rect.height * 0.38))
        self.emitRippleRing(
            at: center,
            baseRadius: baseRadius,
            toScale: 1.90 * min(1.25, intensityScale),
            color: palette[0],
            duration: 0.25
        )
        
        if let pulse = self.caretPulseLayer {
            let pulseSize = CGSize(width: max(9, rect.width + 8), height: max(18, rect.height + 4))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulse.removeAllAnimations()
            pulse.position = center
            pulse.bounds = CGRect(origin: .zero, size: pulseSize)
            pulse.backgroundColor = palette[1 % palette.count].withAlphaComponent(0.30).cgColor
            pulse.cornerRadius = 4.0
            pulse.opacity = 0
            CATransaction.commit()
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.82
            scaleAnim.toValue = 1.38
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.82, 0.0]
            alphaAnim.keyTimes = [0.0, 0.18, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, alphaAnim]
            group.duration = 0.20
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
        ripple.strokeColor = color.withAlphaComponent(0.68).cgColor
        ripple.fillColor = nil
        ripple.lineWidth = 1.4
        ripple.opacity = 0
        CATransaction.commit()
        
        let ringScale = CABasicAnimation(keyPath: "transform.scale")
        ringScale.fromValue = 0.45
        ringScale.toValue = toScale
        
        let ringWidth = CABasicAnimation(keyPath: "lineWidth")
        ringWidth.fromValue = 1.5
        ringWidth.toValue = 0.30
        
        let ringAlpha = CAKeyframeAnimation(keyPath: "opacity")
        ringAlpha.values = [0.0, 0.78, 0.0]
        ringAlpha.keyTimes = [0.0, 0.15, 1.0]
        
        let group = CAAnimationGroup()
        group.animations = [ringScale, ringWidth, ringAlpha]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        group.isRemovedOnCompletion = true
        ripple.add(group, forKey: "rippleRing")
    }
    
    
    // MARK: Compact Combo Feedback Pill
    
    private func updateComboHud(in textView: EditorTextView, combo: Int) {
        
        guard combo >= 5 else {
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
            case ..<18:
                tierTitle = "FLOW"
                accentColor = NSColor(srgbRed: 0.18, green: 0.68, blue: 0.96, alpha: 1.0)
            case 18..<40:
                tierTitle = "RHYTHM"
                accentColor = NSColor(srgbRed: 0.08, green: 0.82, blue: 0.72, alpha: 1.0)
            case 40..<80:
                tierTitle = "SURGE"
                accentColor = NSColor(srgbRed: 0.62, green: 0.44, blue: 0.96, alpha: 1.0)
            default:
                tierTitle = "MASTER"
                accentColor = NSColor(srgbRed: 0.96, green: 0.48, blue: 0.32, alpha: 1.0)
        }
        
        let scale = textView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let countText = "×\(combo)"
        let tierFont = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        let countFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        
        let tierAttr = NSAttributedString(string: tierTitle, attributes: [
            .font: tierFont,
            .foregroundColor: accentColor.withAlphaComponent(0.85),
            .kern: 0.8,
        ])
        let countAttr = NSAttributedString(string: countText, attributes: [
            .font: countFont,
            .foregroundColor: accentColor,
        ])
        
        let tierSize = tierAttr.size()
        let countSize = countAttr.size()
        let hudWidth = max(62, ceil(tierSize.width + countSize.width) + 20)
        let badgeHeight: CGFloat = 24
        let totalHeight: CGFloat = 28
        
        let rendered = NSImage(size: NSSize(width: hudWidth, height: badgeHeight), flipped: true) { _ in
            let pillRect = NSRect(x: 0.5, y: 0.5, width: hudWidth - 1, height: badgeHeight - 1)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
            accentColor.withAlphaComponent(0.10).setFill()
            pillPath.fill()
            accentColor.withAlphaComponent(0.24).setStroke()
            pillPath.lineWidth = 0.75
            pillPath.stroke()
            
            let totalTextW = tierSize.width + 5 + countSize.width
            let startX = max(6, (hudWidth - totalTextW) / 2)
            let tierY = (badgeHeight - tierSize.height) / 2 + 0.5
            let countY = (badgeHeight - countSize.height) / 2
            tierAttr.draw(at: NSPoint(x: startX, y: tierY))
            countAttr.draw(at: NSPoint(x: startX + tierSize.width + 5, y: countY))
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: NSSize(width: hudWidth, height: badgeHeight))
        let scaleTransform = NSAffineTransform()
        scaleTransform.scale(by: scale)
        let cgImage = rendered.cgImage(forProposedRect: &proposedRect, context: nil, hints: [.ctm: scaleTransform])
        
        let viewBounds = scrollView.bounds
        let marginRight: CGFloat = 16
        let marginTop: CGFloat = 12
        let originX = max(12, viewBounds.width - hudWidth - marginRight)
        let originY = scrollView.isFlipped ? marginTop : max(12, viewBounds.height - totalHeight - marginTop)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAllAnimations()
        container.bounds = CGRect(x: 0, y: 0, width: hudWidth, height: totalHeight)
        container.position = CGPoint(x: originX + hudWidth / 2, y: originY + totalHeight / 2)
        container.opacity = 0.92
        
        badgeLayer.frame = CGRect(x: 0, y: 0, width: hudWidth, height: badgeHeight)
        badgeLayer.contents = cgImage
        badgeLayer.contentsScale = scale
        badgeLayer.contentsGravity = .resize
        
        let trackWidth = hudWidth - 10
        let trackY = badgeHeight + 2
        trackLayer.frame = CGRect(x: 5, y: trackY, width: trackWidth, height: 2)
        trackLayer.backgroundColor = accentColor.withAlphaComponent(0.15).cgColor
        trackLayer.cornerRadius = 1.0
        
        fillLayer.removeAllAnimations()
        fillLayer.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: trackWidth, height: 2)
        fillLayer.position = CGPoint(x: trackWidth, y: 1.0)
        fillLayer.backgroundColor = accentColor.withAlphaComponent(0.80).cgColor
        fillLayer.cornerRadius = 1.0
        CATransaction.commit()
        
        // Gentle spring pop on container
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 1.08
        pop.toValue = 1.0
        pop.mass = 0.5
        pop.stiffness = 500
        pop.damping = 26
        pop.duration = min(0.18, pop.settlingDuration)
        container.add(pop, forKey: "comboPop")
        
        // Decaying timer bar (1.6s timeout)
        let decay = CABasicAnimation(keyPath: "transform.scale.x")
        decay.fromValue = 1.0
        decay.toValue = 0.0
        decay.duration = 1.6
        decay.fillMode = .forwards
        decay.isRemovedOnCompletion = false
        fillLayer.add(decay, forKey: "comboDecay")
        
        self.comboResetTask?.cancel()
        self.comboResetTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
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
        CATransaction.setAnimationDuration(0.20)
        container.opacity = 0
        CATransaction.commit()
    }
    
    
    // MARK: Inline Ghost Completion Overlay & Micro-Animation
    
    /// Shows an inline gray next-phrase candidate beside the caret aligned precisely with the text baseline,
    /// returning the horizontal advance width (from `caretRect.minX`) required for any trailing text shift.
    @discardableResult
    func showGhostSuggestion(
        _ text: String,
        at caretRect: NSRect,
        font: NSFont,
        lineHeight: CGFloat,
        baselineOffset: CGFloat,
        trailingLineAdvance: CGFloat = 0,
        animateEntrance: Bool = true
    ) -> CGFloat {
        
        guard !text.isEmpty,
              let textView = self.textView,
              textView.window?.isKeyWindow == true,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return 0 }
        
        self.ensureGhostLayers(in: hostLayer)
        guard let container = self.ghostContainerLayer else { return 0 }
        
        let scale = textView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let ghostTextColor = (textView.theme?.text.color ?? NSColor.labelColor).withAlphaComponent(0.42)
        let attrText = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: ghostTextColor,
        ])
        let fullCTLine = CTLineCreateWithAttributedString(attrText)
        let rawTextWidth = ceil(CGFloat(CTLineGetTypographicBounds(fullCTLine, nil, nil, nil)))
        let rowHeight = max(lineHeight, ceil(font.ascender - font.descender + 2))
        
        let startX = caretRect.maxX + 1.5
        let availableWidth = max(28, textView.bounds.width - startX - 10)
        let trailingReserve = trailingLineAdvance > 0 ? ceil(trailingLineAdvance) : 0
        
        let badgeFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let badgeText = "Tab"
        let badgeTextSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
        let badgeWidth = ceil(badgeTextSize.width) + 9
        let badgeHeight = min(14.5, max(12.5, rowHeight - 4))
        
        let maxTextWidth = max(24, availableWidth - (trailingReserve > 0 ? 4 : badgeWidth + 10))
        let drawnTextWidth = min(rawTextWidth, maxTextWidth)
        let ghostAdvanceFromStartX = drawnTextWidth + 2
        
        let badgeGapAfterGhost: CGFloat = trailingReserve > 0 ? (trailingReserve + 6) : 5
        let badgeX = ghostAdvanceFromStartX + badgeGapAfterGhost
        let showsBadge = (trailingReserve <= 120) && (badgeX + badgeWidth <= availableWidth)
        let containerWidth = ceil(showsBadge ? (badgeX + badgeWidth + 2) : ghostAdvanceFromStartX)
        
        let cgBaselineY = max(2, rowHeight - baselineOffset)
        let imageSize = NSSize(width: containerWidth, height: rowHeight)
        
        let badgeBgColor = NSColor.controlAccentColor.withAlphaComponent(0.10)
        let badgeBorderColor = NSColor.controlAccentColor.withAlphaComponent(0.28)
        let badgeFgColor = NSColor.controlAccentColor.withAlphaComponent(0.85)
        
        let renderedImage = NSImage(size: imageSize, flipped: false) { _ in
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 0, width: drawnTextWidth + 1, height: rowHeight))
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: 0, y: cgBaselineY)
                if rawTextWidth > maxTextWidth {
                    let ellipsis = NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: ghostTextColor])
                    let truncToken = CTLineCreateWithAttributedString(ellipsis)
                    if let truncated = CTLineCreateTruncatedLine(fullCTLine, Double(maxTextWidth), .end, truncToken) {
                        CTLineDraw(truncated, ctx)
                    } else {
                        CTLineDraw(fullCTLine, ctx)
                    }
                } else {
                    CTLineDraw(fullCTLine, ctx)
                }
                ctx.restoreGState()
            }
            
            if showsBadge {
                let capMidY = cgBaselineY + max(4, font.capHeight / 2)
                let badgeY = min(max(1, capMidY - badgeHeight / 2), max(1, rowHeight - badgeHeight - 1))
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
                let by = badgeRect.minY + (badgeHeight - badgeTextSize.height) / 2
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
        
        if animateEntrance && !AnimationConstants.isReducedMotionEnabled {
            let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0.0
            fadeIn.toValue = 1.0
            
            let slideIn = CABasicAnimation(keyPath: "transform.translation.x")
            slideIn.fromValue = 4.0
            slideIn.toValue = 0.0
            
            let group = CAAnimationGroup()
            group.animations = [fadeIn, slideIn]
            group.duration = 0.11
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            container.add(group, forKey: "ghostEnter")
        }
        
        return (startX - caretRect.minX) + drawnTextWidth + 2
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
            group.duration = 0.24
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            sweep.add(group, forKey: "ghostSweep")
        }
        
        self.triggerTypewriterBurst(at: endRect, color: NSColor.controlAccentColor, intensityScale: 0.95)
    }
    
    
    // MARK: Apple-Inspired Fluid Spring Vim Cursor (120Hz DisplayLink, Zero-Wobble Glide)
    
    /// Transitions the single persistent GPU Vim cursor to `newRect` using an interruptible,
    /// near-critically damped spring with subtle velocity-coupled axial elongation (no jelly wobble).
    func animateVimCursorTransition(
        from oldRect: NSRect?,
        to newRect: NSRect,
        color: NSColor,
        isContinuous: Bool = false
    ) {
        
        guard self.ownsVimCursorDrawing else {
            self.hideVimCursorOnly()
            return
        }
        self.moveVimCursor(
            to: newRect,
            color: color,
            animated: true,
            fallbackFrom: oldRect,
            isContinuous: isContinuous
        )
    }
    
    
    private func moveVimCursor(
        to rawRect: NSRect,
        color: NSColor,
        animated: Bool,
        fallbackFrom: NSRect? = nil,
        isContinuous: Bool = false
    ) {
        guard let textView = self.textView,
              rawRect.width > 0, rawRect.height > 0, rawRect.height < 80,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return }
        
        self.ensureVimLayers(in: hostLayer)
        guard let cursorLayer = self.vimCursorLayer else { return }
        
        let mode = VimState.shared.mode
        let visualRect: NSRect
        if mode == .replace {
            let barH = max(3, round(rawRect.height * 0.22))
            visualRect = NSRect(x: rawRect.minX, y: rawRect.maxY - barH, width: rawRect.width, height: barH)
        } else {
            visualRect = rawRect
        }
        
        let cursorAlpha: CGFloat = switch mode {
            case .replace: 0.86
            case .visual: 0.64
            default: 0.56
        }
        let cornerRadius = Self.cursorCornerRadius(for: visualRect)
        self.currentTrailColor = color
        self.currentCursorAlpha = cursorAlpha
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.fillColor = color.withAlphaComponent(cursorAlpha).cgColor
        cursorLayer.shadowColor = color.cgColor
        cursorLayer.shadowOpacity = 0.22
        cursorLayer.shadowRadius = 2.6
        cursorLayer.shadowOffset = .zero
        cursorLayer.opacity = 1.0
        for layer in self.vimTrailLayers {
            layer.fillColor = color.cgColor
        }
        CATransaction.commit()
        
        // Deduplicate back-to-back identical target calls within the same event
        if self.fluidCursor != nil,
           let lastTarget = self.currentTargetRect,
           abs(lastTarget.minX - visualRect.minX) < 0.35,
           abs(lastTarget.minY - visualRect.minY) < 0.35,
           abs(lastTarget.width - visualRect.width) < 0.35,
           abs(lastTarget.height - visualRect.height) < 0.35
        {
            return
        }
        
        if self.fluidCursor == nil, let fallbackFrom,
           fallbackFrom.width > 0, fallbackFrom.height > 0, fallbackFrom.height < 80,
           textView.visibleRect.insetBy(dx: -80, dy: -100).intersects(fallbackFrom)
        {
            self.fluidCursor = FluidCursorState(
                center: CGPoint(x: fallbackFrom.midX, y: fallbackFrom.midY),
                centerVelocity: .zero,
                size: fallbackFrom.size,
                sizeVelocity: .zero,
                omega: 40,
                zeta: 0.86
            )
            self.trailRects = Array(repeating: fallbackFrom, count: Self.trailLayerCount)
        }
        
        guard animated, var cursorState = self.fluidCursor, textView.window != nil else {
            self.fluidCursor = FluidCursorState(
                center: CGPoint(x: visualRect.midX, y: visualRect.midY),
                centerVelocity: .zero,
                size: visualRect.size,
                sizeVelocity: .zero,
                omega: 40,
                zeta: 0.86
            )
            self.trailRects = Array(repeating: visualRect, count: Self.trailLayerCount)
            self.currentTargetRect = visualRect
            self.vimDisplayLink?.isPaused = true
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.path = CGPath(roundedRect: visualRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            for layer in self.vimTrailLayers {
                layer.opacity = 0
            }
            CATransaction.commit()
            return
        }
        
        if self.trailRects.count != Self.trailLayerCount {
            let curRect = NSRect(
                x: cursorState.center.x - cursorState.size.width * 0.5,
                y: cursorState.center.y - cursorState.size.height * 0.5,
                width: cursorState.size.width,
                height: cursorState.size.height
            )
            self.trailRects = Array(repeating: curRect, count: Self.trailLayerCount)
        }
        
        let targetCenter = CGPoint(x: visualRect.midX, y: visualRect.midY)
        var dx = targetCenter.x - cursorState.center.x
        var dy = targetCenter.y - cursorState.center.y
        var distance = hypot(dx, dy)
        
        if distance < 0.4 && abs(cursorState.size.width - visualRect.width) < 0.4 && self.vimDisplayLink?.isPaused != false {
            cursorState.center = targetCenter
            cursorState.centerVelocity = .zero
            cursorState.size = visualRect.size
            cursorState.sizeVelocity = .zero
            self.fluidCursor = cursorState
            self.currentTargetRect = visualRect
            self.trailRects = Array(repeating: visualRect, count: Self.trailLayerCount)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.path = CGPath(roundedRect: visualRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            for layer in self.vimTrailLayers {
                layer.opacity = 0
            }
            CATransaction.commit()
            return
        }
        
        // For huge jumps (gg / G / Ctrl-D), bring the offscreen origin within a clean ProMotion swoop range
        // without injecting oscillation.
        let maxJump: CGFloat = 240
        if distance > maxJump {
            let clampedOriginDist: CGFloat = 120
            let shiftX = dx - (dx / distance) * clampedOriginDist
            let shiftY = dy - (dy / distance) * clampedOriginDist
            cursorState.center.x += shiftX
            cursorState.center.y += shiftY
            cursorState.centerVelocity = .zero
            for i in self.trailRects.indices {
                self.trailRects[i].origin.x += shiftX
                self.trailRects[i].origin.y += shiftY
            }
            dx = (dx / distance) * clampedOriginDist
            dy = (dy / distance) * clampedOriginDist
            distance = clampedOriginDist
        }
        
        let params = Self.fluidSpringParameters(distance: distance, isContinuous: isContinuous)
        cursorState.omega = params.omega
        cursorState.zeta = params.zeta
        
        self.fluidCursor = cursorState
        self.currentTargetRect = visualRect
        self.startOrResumeDisplayLink(for: textView)
    }
    
    
    /// Apple Fluid Interface spring tuning (`response` fast & responsive, `zeta` ~0.85–0.91 for crisp
    /// settled poise with a subtle, satisfying breath and zero harsh ringing).
    static func fluidSpringParameters(distance: CGFloat, isContinuous: Bool) -> (omega: CGFloat, zeta: CGFloat) {
        
        if isContinuous {
            return (omega: 45.0, zeta: 0.90)
        }
        if distance < 28 {
            return (omega: 42.0, zeta: 0.85)
        }
        return (omega: 36.0, zeta: 0.85)
    }
    
    
    /// Tapered frosted-glow trail parameters for index `0...3` (0 = closest wake, 3 = faintest tail).
    static func trailFrameParameters(layerIndex: Int, activity: CGFloat, cursorAlpha: CGFloat) -> (scale: CGFloat, alpha: CGFloat) {
        
        let scales: [CGFloat] = [0.92, 0.80, 0.66, 0.52]
        let weights: [CGFloat] = [0.34, 0.22, 0.12, 0.055]
        let idx = max(0, min(scales.count - 1, layerIndex))
        let clampedActivity = max(0, min(1, activity))
        return (scale: scales[idx], alpha: FloatCompat.clampAlpha(weights[idx] * clampedActivity * cursorAlpha))
    }
    
    
    private enum FloatCompat {
        static func clampAlpha(_ v: CGFloat) -> CGFloat { max(0, min(1, v)) }
    }
    
    
    /// Computes a subtle, strictly rectangular velocity-stretched frame during motion so rapid glides
    /// feel fluid while preserving crisp geometric edges with zero wobble or corner skewing.
    static func fluidStretchedRect(center: CGPoint, baseSize: CGSize, velocity: CGPoint) -> NSRect {
        
        let speedX = abs(velocity.x)
        let speedY = abs(velocity.y)
        
        let extraW = min(baseSize.width * 0.50, speedX * 0.0085)
        let extraH = min(baseSize.height * 0.42, speedY * 0.0065)
        
        let squeezeH = min(baseSize.height * 0.08, extraW * 0.14)
        let squeezeW = min(baseSize.width * 0.08, extraH * 0.14)
        
        let w = max(2, baseSize.width + extraW - squeezeW)
        let h = max(3, baseSize.height + extraH - squeezeH)
        return NSRect(x: center.x - w * 0.5, y: center.y - h * 0.5, width: w, height: h)
    }
    
    
    private static func cursorCornerRadius(for rect: NSRect) -> CGFloat {
        
        min(2.6, max(1.6, rect.height * 0.14))
    }
    
    
    private func startOrResumeDisplayLink(for textView: EditorTextView) {
        
        if self.vimDisplayLink == nil {
            let proxy = DisplayLinkProxy(owner: self)
            self.displayLinkProxy = proxy
            let link = textView.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
            link.add(to: .main, forMode: .common)
            self.vimDisplayLink = link
        }
        self.lastStepTime = CACurrentMediaTime()
        self.vimDisplayLink?.isPaused = false
    }
    
    
    private func stepVimCursorDisplayLink(_ link: CADisplayLink) {
        
        guard self.ownsVimCursorDrawing,
              let cursorLayer = self.vimCursorLayer,
              var state = self.fluidCursor,
              let targetRect = self.currentTargetRect
        else {
            link.isPaused = true
            return
        }
        
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - self.lastStepTime, 1.0 / 240.0), 1.0 / 24.0))
        self.lastStepTime = now
        
        let targetCenter = CGPoint(x: targetRect.midX, y: targetRect.midY)
        let (nx, nvx) = Self.stepUnderdampedSpring(
            pos: state.center.x,
            vel: state.centerVelocity.x,
            target: targetCenter.x,
            omega: state.omega,
            zeta: state.zeta,
            dt: dt
        )
        let (ny, nvy) = Self.stepUnderdampedSpring(
            pos: state.center.y,
            vel: state.centerVelocity.y,
            target: targetCenter.y,
            omega: state.omega,
            zeta: state.zeta,
            dt: dt
        )
        let (nw, nvw) = Self.stepUnderdampedSpring(
            pos: state.size.width,
            vel: state.sizeVelocity.width,
            target: targetRect.width,
            omega: 42.0,
            zeta: 0.94,
            dt: dt
        )
        let (nh, nvh) = Self.stepUnderdampedSpring(
            pos: state.size.height,
            vel: state.sizeVelocity.height,
            target: targetRect.height,
            omega: 42.0,
            zeta: 0.94,
            dt: dt
        )
        
        state.center = CGPoint(x: nx, y: ny)
        state.centerVelocity = CGPoint(x: nvx, y: nvy)
        state.size = CGSize(width: nw, height: nh)
        state.sizeVelocity = CGSize(width: nvw, height: nvh)
        self.fluidCursor = state
        
        let posError = hypot(nx - targetCenter.x, ny - targetCenter.y)
        let sizeError = max(abs(nw - targetRect.width), abs(nh - targetRect.height))
        let speed = hypot(nvx, nvy)
        
        if self.trailRects.count != Self.trailLayerCount {
            self.trailRects = Array(repeating: targetRect, count: Self.trailLayerCount)
        }
        
        let renderedRect = Self.fluidStretchedRect(
            center: state.center,
            baseSize: state.size,
            velocity: state.centerVelocity
        )
        
        // Update 4-tap frame-rate-independent lagged wake behind the active cursor capsule.
        let trailFollowRates: [CGFloat] = [34.0, 26.0, 20.0, 15.0]
        var leadRect = renderedRect
        var maxTrailGap: CGFloat = 0
        for idx in 0..<Self.trailLayerCount {
            let alpha = 1.0 - exp(-trailFollowRates[idx] * dt)
            let prev = self.trailRects[idx]
            let nextRect = NSRect(
                x: prev.origin.x + (leadRect.origin.x - prev.origin.x) * alpha,
                y: prev.origin.y + (leadRect.origin.y - prev.origin.y) * alpha,
                width: prev.width + (leadRect.width - prev.width) * alpha,
                height: prev.height + (leadRect.height - prev.height) * alpha
            )
            self.trailRects[idx] = nextRect
            maxTrailGap = max(maxTrailGap, hypot(nextRect.midX - renderedRect.midX, nextRect.midY - renderedRect.midY))
            leadRect = nextRect
        }
        
        if posError < 0.12 && sizeError < 0.12 && speed < 1.5 && maxTrailGap < 0.25 {
            state.center = targetCenter
            state.centerVelocity = .zero
            state.size = targetRect.size
            state.sizeVelocity = .zero
            self.fluidCursor = state
            self.trailRects = Array(repeating: targetRect, count: Self.trailLayerCount)
            
            let radius = Self.cursorCornerRadius(for: targetRect)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cursorLayer.path = CGPath(roundedRect: targetRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            for layer in self.vimTrailLayers {
                layer.opacity = 0
            }
            CATransaction.commit()
            link.isPaused = true
            return
        }
        
        let radius = Self.cursorCornerRadius(for: renderedRect)
        let path = CGPath(roundedRect: renderedRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let motionActivity = min(1.0, max(speed / 240.0, max(posError, maxTrailGap) / 14.0))
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (idx, layer) in self.vimTrailLayers.enumerated() where idx < self.trailRects.count {
            let base = self.trailRects[idx]
            let tailParams = Self.trailFrameParameters(
                layerIndex: idx,
                activity: motionActivity,
                cursorAlpha: self.currentCursorAlpha
            )
            let insetX = base.width * (1.0 - tailParams.scale) * 0.5
            let insetY = base.height * (1.0 - tailParams.scale) * 0.5
            let scaledRect = base.insetBy(dx: insetX, dy: insetY)
            let tailRadius = Self.cursorCornerRadius(for: scaledRect)
            layer.path = CGPath(roundedRect: scaledRect, cornerWidth: tailRadius, cornerHeight: tailRadius, transform: nil)
            layer.opacity = Float(tailParams.alpha)
        }
        cursorLayer.path = path
        CATransaction.commit()
    }
    
    
    /// Exact analytical closed-form integration for a damped harmonic oscillator (`0 < zeta < 1`).
    private static func stepUnderdampedSpring(
        pos: CGFloat,
        vel: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        zeta: CGFloat,
        dt: CGFloat
    ) -> (CGFloat, CGFloat) {
        
        let x0 = pos - target
        let omegaZeta = omega * zeta
        let omegaD = omega * sqrt(max(0.0001, 1.0 - zeta * zeta))
        let decay = exp(-omegaZeta * dt)
        let cosTerm = cos(omegaD * dt)
        let sinTerm = sin(omegaD * dt)
        let c2 = (vel + omegaZeta * x0) / omegaD
        
        let newX = target + decay * (x0 * cosTerm + c2 * sinTerm)
        let newV = decay * ((c2 * omegaD - x0 * omegaZeta) * cosTerm - (x0 * omegaD + c2 * omegaZeta) * sinTerm)
        return (newX, newV)
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
                    NSColor(srgbRed: 1.00, green: 0.35, blue: 0.37, alpha: 1.0),
                    NSColor(srgbRed: 1.00, green: 0.79, blue: 0.23, alpha: 1.0),
                    NSColor(srgbRed: 0.54, green: 0.79, blue: 0.15, alpha: 1.0),
                    NSColor(srgbRed: 0.10, green: 0.51, blue: 0.77, alpha: 1.0),
                    NSColor(srgbRed: 1.00, green: 0.57, blue: 0.30, alpha: 1.0),
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
        self.vimCursorLayer = nil
        self.vimTrailLayers.removeAll()
        self.trailRects.removeAll()
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
        pool.reserveCapacity(64)
        for _ in 0..<64 {
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
        
        var trails: [CAShapeLayer] = []
        for _ in 0..<Self.trailLayerCount {
            let trail = CAShapeLayer()
            trail.opacity = 0
            trails.append(trail)
        }
        // Insert farthest tail first so index 0 rests closest underneath the primary cursor.
        for trail in trails.reversed() {
            root.addSublayer(trail)
        }
        self.vimTrailLayers = trails
        
        let cursor = CAShapeLayer()
        cursor.opacity = 0
        root.addSublayer(cursor)
        self.vimCursorLayer = cursor
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
