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

/// Built-in CoreAnimation (`CAEmitterLayer` / `CASpringAnimation` / `NSSound`) visual and audio
/// effects for typewriter typing and Neovide-inspired Vim cursor motion trails.
@MainActor final class EditorFunEffectsController {
    
    private weak var textView: EditorTextView?
    private var cursorOverlayLayer: CALayer?
    private var lastCursorRect: NSRect?
    private var hideOverlayTask: Task<Void, Never>?
    
    init(textView: EditorTextView) {
        
        self.textView = textView
    }
    
    
    /// Plays the typewriter sound + micro-particle burst at the insertion point when enabled.
    func triggerTypewriterBurst(at rect: NSRect) {
        
        guard UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) else { return }
        guard let textView = self.textView else { return }
        
        // Play macOS built-in crisp mechanical click sound (`Tink`) at low latency
        if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.volume = 0.25
            sound.play()
        }
        
        textView.wantsLayer = true
        guard let hostLayer = textView.layer else { return }
        
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: rect.midX, y: rect.midY)
        emitter.emitterShape = .point
        emitter.emitterSize = CGSize(width: 2, height: 2)
        emitter.renderMode = .additive
        
        let cell = CAEmitterCell()
        cell.birthRate = 28
        cell.lifetime = 0.32
        cell.lifetimeRange = 0.1
        cell.velocity = 42
        cell.velocityRange = 18
        cell.emissionRange = .pi * 2
        cell.scale = 0.45
        cell.scaleSpeed = -1.1
        cell.alphaSpeed = -2.8
        cell.color = NSColor.controlAccentColor.cgColor
        cell.contents = Self.sparkDotCGImage
        
        emitter.emitterCells = [cell]
        hostLayer.addSublayer(emitter)
        
        // Stop emitting after a brief burst and remove the layer once particles fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            emitter.removeFromSuperlayer()
        }
    }
    
    
    /// Animates a Neovide-style elastic spring cursor block + motion comet trail between Vim cursor positions.
    func animateVimCursorTransition(from oldRect: NSRect?, to newRect: NSRect, color: NSColor) {
        
        let isEnabled = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.vimCursorEffectEnabled)
        guard isEnabled, let textView = self.textView else { return }
        
        let sourceRect = oldRect ?? self.lastCursorRect ?? newRect
        self.lastCursorRect = newRect
        
        let dx = newRect.midX - sourceRect.midX
        let dy = newRect.midY - sourceRect.midY
        let distance = hypot(dx, dy)
        guard distance > 2 else { return }
        
        textView.wantsLayer = true
        guard let hostLayer = textView.layer else { return }
        
        // 1. Comet trail polygon (`CAShapeLayer`) connecting old cursor corners to new cursor corners
        if distance > 8 {
            let trailLayer = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: sourceRect.minX, y: sourceRect.minY))
            path.addLine(to: CGPoint(x: sourceRect.maxX, y: sourceRect.minY))
            path.addLine(to: CGPoint(x: newRect.maxX, y: newRect.maxY))
            path.addLine(to: CGPoint(x: newRect.minX, y: newRect.maxY))
            path.closeSubpath()
            
            trailLayer.path = path
            trailLayer.fillColor = color.withAlphaComponent(0.28).cgColor
            hostLayer.addSublayer(trailLayer)
            
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0.0
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            trailLayer.add(fade, forKey: "trailFade")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) {
                trailLayer.removeFromSuperlayer()
            }
        }
        
        // 2. Elastic spring cursor block (`CASpringAnimation`)
        let cursorLayer: CALayer
        if let existing = self.cursorOverlayLayer {
            cursorLayer = existing
        } else {
            let layer = CALayer()
            layer.cornerRadius = 2.5
            hostLayer.addSublayer(layer)
            self.cursorOverlayLayer = layer
            cursorLayer = layer
        }
        
        cursorLayer.backgroundColor = color.withAlphaComponent(0.65).cgColor
        cursorLayer.shadowColor = color.cgColor
        cursorLayer.shadowOpacity = 0.55
        cursorLayer.shadowRadius = 5
        cursorLayer.shadowOffset = .zero
        cursorLayer.opacity = 1.0
        
        let posAnim = CASpringAnimation(keyPath: "position")
        posAnim.fromValue = NSValue(point: NSPoint(x: sourceRect.midX, y: sourceRect.midY))
        posAnim.toValue = NSValue(point: NSPoint(x: newRect.midX, y: newRect.midY))
        posAnim.mass = 0.7
        posAnim.stiffness = 380
        posAnim.damping = 24
        posAnim.initialVelocity = 6
        posAnim.duration = posAnim.settlingDuration
        
        let boundsAnim = CASpringAnimation(keyPath: "bounds")
        boundsAnim.fromValue = NSValue(rect: NSRect(origin: .zero, size: sourceRect.size))
        boundsAnim.toValue = NSValue(rect: NSRect(origin: .zero, size: newRect.size))
        boundsAnim.mass = 0.7
        boundsAnim.stiffness = 380
        boundsAnim.damping = 24
        boundsAnim.duration = boundsAnim.settlingDuration
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cursorLayer.position = CGPoint(x: newRect.midX, y: newRect.midY)
        cursorLayer.bounds = CGRect(origin: .zero, size: newRect.size)
        CATransaction.commit()
        
        cursorLayer.add(posAnim, forKey: "springPosition")
        cursorLayer.add(boundsAnim, forKey: "springBounds")
        
        self.hideOverlayTask?.cancel()
        self.hideOverlayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.cursorOverlayLayer?.opacity = 0
        }
    }
    
    
    // MARK: Private Helpers
    
    private static let sparkDotCGImage: CGImage? = {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()
}
