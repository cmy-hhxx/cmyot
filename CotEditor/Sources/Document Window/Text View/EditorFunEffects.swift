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

/// Built-in CoreAnimation visual and audio effects for silky typewriter feedback
/// and zero-drift Neovide-inspired Vim cursor motion trails.
@MainActor final class EditorFunEffectsController {
    
    // MARK: Private Properties
    
    private weak var textView: EditorTextView?
    
    // Pre-allocated polyphonic audio pool so rapid typing never hits disk or stalls the main thread
    private var soundPool: [NSSound] = []
    private var soundPoolIndex = 0
    private var didPrepareSoundPool = false
    
    // Pre-allocated GPU-composited typewriter particle ring buffer
    private weak var hostedLayer: CALayer?
    private var typewriterRootLayer: CALayer?
    private var caretPulseLayer: CALayer?
    private var sparkPool: [CALayer] = []
    private var sparkPoolIndex = 0
    
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
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.cursorOverlayLayer?.removeAllAnimations()
        self.cursorOverlayLayer?.opacity = 0
        self.trailLayer?.removeAllAnimations()
        self.trailLayer?.opacity = 0
        CATransaction.commit()
    }
    
    
    /// Plays crisp low-latency typewriter audio + silky radial-glow micro-sparks at the caret.
    func triggerTypewriterBurst(at rect: NSRect, color: NSColor? = nil) {
        
        guard UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) else { return }
        guard let textView = self.textView, textView.window?.isKeyWindow == true else { return }
        
        self.playCrispKeystrokeSound()
        
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        self.ensureTypewriterLayers(in: hostLayer)
        
        let tintColor = (color ?? textView.effectiveCursorColor).cgColor
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        
        // 1. Subtle caret glow pulse (reused single layer, zero allocation)
        if let pulse = self.caretPulseLayer {
            let pulseSize = CGSize(width: max(8, rect.width + 8), height: max(18, rect.height + 4))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pulse.removeAllAnimations()
            pulse.position = center
            pulse.bounds = CGRect(origin: .zero, size: pulseSize)
            pulse.backgroundColor = (color ?? textView.effectiveCursorColor).withAlphaComponent(0.32).cgColor
            pulse.cornerRadius = 4
            pulse.opacity = 0
            CATransaction.commit()
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 0.72
            scaleAnim.toValue = 1.35
            
            let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
            alphaAnim.values = [0.0, 0.85, 0.0]
            alphaAnim.keyTimes = [0.0, 0.18, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [scaleAnim, alphaAnim]
            group.duration = 0.18
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            pulse.add(group, forKey: "caretPulse")
        }
        
        // 2. Silky deterministic ring-buffer micro-sparks (zero layer allocation per keystroke)
        guard !self.sparkPool.isEmpty else { return }
        let origin = CGPoint(x: rect.midX, y: rect.midY)
        let sparkCount = 5
        
        for i in 0..<sparkCount {
            let spark = self.sparkPool[self.sparkPoolIndex]
            self.sparkPoolIndex = (self.sparkPoolIndex + 1) % self.sparkPool.count
            
            let baseAngle = (.pi * 2.0 / Double(sparkCount)) * Double(i) + Double.random(in: -0.35...0.35)
            let travel = CGFloat.random(in: 12...26)
            let dx = cos(baseAngle) * travel
            let dy = sin(baseAngle) * travel - CGFloat.random(in: 2...7)  // gentle upward drift (flipped view: -y is up)
            let endPoint = CGPoint(x: origin.x + dx, y: origin.y + dy)
            let startScale = CGFloat.random(in: 0.75...1.15)
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            spark.removeAllAnimations()
            spark.position = origin
            spark.backgroundColor = tintColor
            spark.opacity = 0
            CATransaction.commit()
            
            let moveAnim = CABasicAnimation(keyPath: "position")
            moveAnim.fromValue = NSValue(point: origin)
            moveAnim.toValue = NSValue(point: endPoint)
            
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = startScale
            scaleAnim.toValue = 0.12
            
            let fadeAnim = CAKeyframeAnimation(keyPath: "opacity")
            fadeAnim.values = [0.0, 0.92, 0.0]
            fadeAnim.keyTimes = [0.0, 0.12, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [moveAnim, scaleAnim, fadeAnim]
            group.duration = Double.random(in: 0.26...0.36)
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            spark.add(group, forKey: "sparkBurst")
        }
    }
    
    
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
    
    private func playCrispKeystrokeSound() {
        
        if !self.didPrepareSoundPool {
            self.didPrepareSoundPool = true
            if let template = NSSound(named: NSSound.Name("Tink")) {
                template.volume = 0.22
                self.soundPool = (0..<8).compactMap { _ in
                    let copy = template.copy() as? NSSound
                    copy?.volume = 0.22
                    return copy
                }
            }
        }
        
        guard !self.soundPool.isEmpty else { return }
        if let freeSound = self.soundPool.first(where: { !$0.isPlaying }) {
            freeSound.play()
        } else {
            let slot = self.soundPool[self.soundPoolIndex]
            self.soundPoolIndex = (self.soundPoolIndex + 1) % self.soundPool.count
            slot.stop()
            slot.play()
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
    
    
    private func ensureTypewriterLayers(in hostLayer: CALayer) {
        
        if self.hostedLayer !== hostLayer {
            self.hostedLayer = hostLayer
            self.typewriterRootLayer?.removeFromSuperlayer()
            self.typewriterRootLayer = nil
            self.caretPulseLayer = nil
            self.sparkPool.removeAll()
            self.vimRootLayer?.removeFromSuperlayer()
            self.vimRootLayer = nil
            self.cursorOverlayLayer = nil
            self.trailLayer = nil
        }
        
        guard self.typewriterRootLayer == nil else { return }
        
        let root = CALayer()
        root.zPosition = 200
        hostLayer.addSublayer(root)
        self.typewriterRootLayer = root
        
        let pulse = CALayer()
        pulse.opacity = 0
        root.addSublayer(pulse)
        self.caretPulseLayer = pulse
        
        let sparkImage = Self.sparkGlowCGImage
        var pool: [CALayer] = []
        pool.reserveCapacity(40)
        for _ in 0..<40 {
            let spark = CALayer()
            spark.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
            spark.cornerRadius = 3
            spark.contents = sparkImage
            spark.opacity = 0
            root.addSublayer(spark)
            pool.append(spark)
        }
        self.sparkPool = pool
    }
    
    
    private func ensureVimLayers(in hostLayer: CALayer) {
        
        if self.hostedLayer !== hostLayer {
            self.hostedLayer = hostLayer
            self.vimRootLayer?.removeFromSuperlayer()
            self.vimRootLayer = nil
            self.cursorOverlayLayer = nil
            self.trailLayer = nil
            self.typewriterRootLayer?.removeFromSuperlayer()
            self.typewriterRootLayer = nil
            self.caretPulseLayer = nil
            self.sparkPool.removeAll()
        }
        
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
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.95),
                NSColor.white.withAlphaComponent(0.45),
                NSColor.white.withAlphaComponent(0.0),
            ])
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()
}
