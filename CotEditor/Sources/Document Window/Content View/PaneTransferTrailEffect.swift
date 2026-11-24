//
//  PaneTransferTrailEffect.swift
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

/// Non-interactive window-spanning overlay hosting cross-pane document transfer trail animations.
final class PaneTransferTrailOverlayView: NSView {
    
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.wantsLayer = true
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}


/// CoreAnimation luminous comet + tapered wake trail played when moving a document across panes or windows.
@MainActor
enum PaneTransferTrailEffect {
    
    static var shouldAnimate: Bool {
        
        !AnimationConstants.isReducedMotionEnabled
    }
    
    
    /// Computes the flight origin: uses `sourceTabCenter` when dropped onto the target tab bar,
    /// otherwise starts from `dropPoint`, clamped within `maxDistance` of `targetTabCenter`.
    static func computeFlightStart(
        sourceTabCenter: CGPoint?,
        dropPoint: CGPoint,
        targetTabCenter: CGPoint,
        maxDistance: CGFloat = 460
    ) -> CGPoint {
        
        let baseOrigin: CGPoint
        if let sourceTabCenter,
           hypot(dropPoint.x - targetTabCenter.x, dropPoint.y - targetTabCenter.y) < 64
        {
            baseOrigin = sourceTabCenter
        } else {
            baseOrigin = dropPoint
        }
        
        var dx = baseOrigin.x - targetTabCenter.x
        var dy = baseOrigin.y - targetTabCenter.y
        var distance = hypot(dx, dy)
        
        if distance > maxDistance {
            let scale = maxDistance / distance
            dx *= scale
            dy *= scale
            distance = maxDistance
        }
        
        if distance < 20 {
            if let sourceTabCenter {
                let sdx = sourceTabCenter.x - targetTabCenter.x
                let sdy = sourceTabCenter.y - targetTabCenter.y
                let sDist = hypot(sdx, sdy)
                if sDist >= 1 {
                    return CGPoint(
                        x: targetTabCenter.x + (sdx / sDist) * 36,
                        y: targetTabCenter.y + (sdy / sDist) * 36
                    )
                }
            }
            if distance >= 1 {
                return CGPoint(
                    x: targetTabCenter.x + (dx / distance) * 36,
                    y: targetTabCenter.y + (dy / distance) * 36
                )
            }
            return CGPoint(x: targetTabCenter.x - 36, y: targetTabCenter.y + 18)
        }
        
        return CGPoint(x: targetTabCenter.x + dx, y: targetTabCenter.y + dy)
    }
    
    
    /// Computes an upward-arcing quadratic Bezier control point in flipped top-left coordinates.
    static func quadraticBezierControlPoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        
        let mid = CGPoint(x: (start.x + end.x) * 0.5, y: (start.y + end.y) * 0.5)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let bow = min(56, max(20, distance * 0.20))
        
        guard distance > 0.5 else {
            return CGPoint(x: mid.x, y: mid.y - bow)
        }
        
        var perpX = -dy / distance
        var perpY = dx / distance
        if perpY > 0 {
            perpX = -perpX
            perpY = -perpY
        } else if abs(perpY) < 0.001, perpX < 0 {
            perpX = -perpX
        }
        
        return CGPoint(x: mid.x + perpX * bow, y: mid.y + perpY * bow)
    }
    
    
    /// Evaluates a point at parameter `progress` (`0...1`) along a quadratic Bezier curve.
    static func pointOnQuadraticBezier(from start: CGPoint, control: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        
        let clampedT = max(0, min(1, progress))
        let inv = 1 - clampedT
        let x = inv * inv * start.x + 2 * inv * clampedT * control.x + clampedT * clampedT * end.x
        let y = inv * inv * start.y + 2 * inv * clampedT * control.y + clampedT * clampedT * end.y
        return CGPoint(x: x, y: y)
    }
    
    
    /// Tapered wake capsule scale, opacity, and stagger delay for stage `0...4`.
    static func wakeCapsuleParameters(index: Int) -> (scale: CGFloat, alpha: CGFloat, delay: CFTimeInterval) {
        
        let scales: [CGFloat] = [1.0, 0.84, 0.68, 0.52, 0.36]
        let alphas: [CGFloat] = [0.76, 0.48, 0.30, 0.17, 0.085]
        let delays: [CFTimeInterval] = [0.0, 0.018, 0.036, 0.054, 0.072]
        let clamped = max(0, min(scales.count - 1, index))
        return (scale: scales[clamped], alpha: alphas[clamped], delay: delays[clamped])
    }
    
    
    /// Plays the luminous flight ribbon, tapered wake capsules, sparks, and landing halo across `window`.
    static func play(
        in window: NSWindow,
        sourceTabRectInWindow: NSRect?,
        dropPointInWindow: NSPoint,
        targetTabRectInWindow: NSRect,
        accentColor: NSColor = .controlAccentColor
    ) {
        guard self.shouldAnimate,
              window.isVisible,
              window.occlusionState.contains(.visible),
              NSApp?.isActive != false,
              let contentView = window.contentView
        else { return }
        
        let overlay = PaneTransferTrailOverlayView(frame: contentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        guard let rootLayer = overlay.layer else {
            overlay.removeFromSuperview()
            return
        }
        
        let targetTabRect = overlay.convert(targetTabRectInWindow, from: nil)
        let targetCenter = CGPoint(x: targetTabRect.midX, y: targetTabRect.midY)
        let dropPoint = overlay.convert(dropPointInWindow, from: nil)
        let sourceCenter = sourceTabRectInWindow.map { rect -> CGPoint in
            let converted = overlay.convert(rect, from: nil)
            return CGPoint(x: converted.midX, y: converted.midY)
        }
        
        let startPoint = self.computeFlightStart(
            sourceTabCenter: sourceCenter,
            dropPoint: dropPoint,
            targetTabCenter: targetCenter
        )
        let controlPoint = self.quadraticBezierControlPoint(from: startPoint, to: targetCenter)
        
        let bezierPath = CGMutablePath()
        bezierPath.move(to: startPoint)
        bezierPath.addQuadCurve(to: targetCenter, control: controlPoint)
        
        let now = rootLayer.convertTime(CACurrentMediaTime(), from: nil)
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
        
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor(cgColor: accentColor.cgColor) ?? accentColor
            
            // 0. Origin launch elastic pop ring at startPoint
            let launchRing = CAShapeLayer()
            let launchSize: CGFloat = 22
            launchRing.bounds = CGRect(x: 0, y: 0, width: launchSize, height: launchSize)
            launchRing.position = startPoint
            launchRing.path = CGPath(ellipseIn: launchRing.bounds.insetBy(dx: 1, dy: 1), transform: nil)
            launchRing.fillColor = nil
            launchRing.strokeColor = accent.withAlphaComponent(0.75).cgColor
            launchRing.lineWidth = 1.6
            launchRing.opacity = 0
            rootLayer.addSublayer(launchRing)
            
            let launchScale = CABasicAnimation(keyPath: "transform.scale")
            launchScale.fromValue = 0.5
            launchScale.toValue = 1.8
            let launchAlpha = CAKeyframeAnimation(keyPath: "opacity")
            launchAlpha.values = [0, 0.7, 0]
            launchAlpha.keyTimes = [0, 0.18, 1]
            let launchGroup = CAAnimationGroup()
            launchGroup.animations = [launchScale, launchAlpha]
            launchGroup.beginTime = now
            launchGroup.duration = 0.26
            launchGroup.timingFunction = easeOut
            launchGroup.fillMode = .both
            launchGroup.isRemovedOnCompletion = false
            launchRing.add(launchGroup, forKey: "launchRing")
            
            // 1. Outer luminous glow ribbon
            let glowLayer = CAShapeLayer()
            glowLayer.path = bezierPath
            glowLayer.fillColor = nil
            glowLayer.strokeColor = accent.withAlphaComponent(0.24).cgColor
            glowLayer.lineWidth = 8.5
            glowLayer.lineCap = .round
            glowLayer.shadowColor = accent.cgColor
            glowLayer.shadowRadius = 7
            glowLayer.shadowOpacity = 0.45
            glowLayer.shadowOffset = .zero
            glowLayer.strokeStart = 0
            glowLayer.strokeEnd = 0
            glowLayer.opacity = 0
            rootLayer.addSublayer(glowLayer)
            
            let glowEnd = CABasicAnimation(keyPath: "strokeEnd")
            glowEnd.fromValue = 0
            glowEnd.toValue = 1
            glowEnd.duration = 0.28
            glowEnd.timingFunction = easeOut
            glowEnd.fillMode = .forwards
            glowEnd.isRemovedOnCompletion = false
            glowLayer.add(glowEnd, forKey: "glowEnd")
            
            let glowStart = CABasicAnimation(keyPath: "strokeStart")
            glowStart.fromValue = 0
            glowStart.toValue = 1
            glowStart.beginTime = now + 0.06
            glowStart.duration = 0.30
            glowStart.timingFunction = easeInOut
            glowStart.fillMode = .both
            glowStart.isRemovedOnCompletion = false
            glowLayer.add(glowStart, forKey: "glowStart")
            
            let glowAlpha = CAKeyframeAnimation(keyPath: "opacity")
            glowAlpha.values = [0, 1, 0.85, 0]
            glowAlpha.keyTimes = [0, 0.14, 0.65, 1]
            glowAlpha.duration = 0.38
            glowAlpha.fillMode = .forwards
            glowAlpha.isRemovedOnCompletion = false
            glowLayer.add(glowAlpha, forKey: "glowAlpha")
            
            // 2. Inner bright comet core
            let coreLayer = CAShapeLayer()
            coreLayer.path = bezierPath
            coreLayer.fillColor = nil
            coreLayer.strokeColor = accent.withAlphaComponent(0.84).cgColor
            coreLayer.lineWidth = 2.4
            coreLayer.lineCap = .round
            coreLayer.strokeStart = 0
            coreLayer.strokeEnd = 0
            coreLayer.opacity = 0
            rootLayer.addSublayer(coreLayer)
            
            let coreEnd = CABasicAnimation(keyPath: "strokeEnd")
            coreEnd.fromValue = 0
            coreEnd.toValue = 1
            coreEnd.duration = 0.26
            coreEnd.timingFunction = easeOut
            coreEnd.fillMode = .forwards
            coreEnd.isRemovedOnCompletion = false
            coreLayer.add(coreEnd, forKey: "coreEnd")
            
            let coreStart = CABasicAnimation(keyPath: "strokeStart")
            coreStart.fromValue = 0
            coreStart.toValue = 1
            coreStart.beginTime = now + 0.055
            coreStart.duration = 0.28
            coreStart.timingFunction = easeInOut
            coreStart.fillMode = .both
            coreStart.isRemovedOnCompletion = false
            coreLayer.add(coreStart, forKey: "coreStart")
            
            let coreAlpha = CAKeyframeAnimation(keyPath: "opacity")
            coreAlpha.values = [0, 1, 0.9, 0]
            coreAlpha.keyTimes = [0, 0.14, 0.65, 1]
            coreAlpha.duration = 0.35
            coreAlpha.fillMode = .forwards
            coreAlpha.isRemovedOnCompletion = false
            coreLayer.add(coreAlpha, forKey: "coreAlpha")
            
            // 3. Five tapered trailing wake capsules
            for index in (0..<5).reversed() {
                let params = self.wakeCapsuleParameters(index: index)
                let capsule = CALayer()
                capsule.bounds = CGRect(x: 0, y: 0, width: 32, height: 9)
                capsule.cornerRadius = 4.5
                capsule.cornerCurve = .continuous
                capsule.position = startPoint
                capsule.opacity = 0
                let tint = index == 0 ? (NSColor.white.blended(withFraction: 0.45, of: accent) ?? accent) : accent
                capsule.backgroundColor = tint.cgColor
                if index == 0 {
                    capsule.shadowColor = accent.cgColor
                    capsule.shadowRadius = 5
                    capsule.shadowOpacity = 0.55
                    capsule.shadowOffset = .zero
                    capsule.shadowPath = CGPath(roundedRect: capsule.bounds, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
                }
                rootLayer.addSublayer(capsule)
                
                let flight = CAKeyframeAnimation(keyPath: "position")
                flight.path = bezierPath
                flight.calculationMode = .paced
                flight.rotationMode = .rotateAuto
                
                let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
                scaleX.values = [0.8, 1.35, 0.5].map { params.scale * $0 }
                scaleX.keyTimes = [0, 0.42, 1.0]
                
                let scaleY = CAKeyframeAnimation(keyPath: "transform.scale.y")
                scaleY.values = [1.15, 0.78, 0.5].map { params.scale * $0 }
                scaleY.keyTimes = [0, 0.42, 1.0]
                
                let alpha = CAKeyframeAnimation(keyPath: "opacity")
                alpha.values = [0, params.alpha, params.alpha * 0.7, 0]
                alpha.keyTimes = [0, 0.16, 0.70, 1.0]
                
                let group = CAAnimationGroup()
                group.animations = [flight, scaleX, scaleY, alpha]
                group.beginTime = now + params.delay
                group.duration = 0.27
                group.timingFunction = easeOut
                group.fillMode = .both
                group.isRemovedOnCompletion = false
                capsule.add(group, forKey: "wakeCapsule")
            }
            
            // 4. Five subtle wake micro-sparks along the flight arc
            let sparkTs: [CGFloat] = [0.22, 0.40, 0.58, 0.74, 0.88]
            for (idx, tValue) in sparkTs.enumerated() {
                let pt = self.pointOnQuadraticBezier(from: startPoint, control: controlPoint, to: targetCenter, progress: tValue)
                let ahead = self.pointOnQuadraticBezier(from: startPoint, control: controlPoint, to: targetCenter, progress: min(1, tValue + 0.04))
                let tx = ahead.x - pt.x
                let ty = ahead.y - pt.y
                let tLen = max(0.001, hypot(tx, ty))
                let normalSign: CGFloat = idx.isMultiple(of: 2) ? 1 : -1
                let driftDist: CGFloat = 10 + CGFloat(idx % 3) * 3
                let endPt = CGPoint(
                    x: pt.x + (-ty / tLen) * normalSign * driftDist - (tx / tLen) * 4,
                    y: pt.y + (tx / tLen) * normalSign * driftDist - (ty / tLen) * 4
                )
                
                let spark = CALayer()
                spark.bounds = CGRect(x: 0, y: 0, width: 2.8, height: 2.8)
                spark.cornerRadius = 1.4
                spark.position = pt
                spark.backgroundColor = accent.withAlphaComponent(0.9).cgColor
                spark.opacity = 0
                rootLayer.addSublayer(spark)
                
                let posAnim = CABasicAnimation(keyPath: "position")
                posAnim.fromValue = NSValue(point: pt)
                posAnim.toValue = NSValue(point: endPt)
                
                let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
                scaleAnim.fromValue = 1.0
                scaleAnim.toValue = 0.2
                
                let alphaAnim = CAKeyframeAnimation(keyPath: "opacity")
                alphaAnim.values = [0, 0.85, 0]
                alphaAnim.keyTimes = [0, 0.2, 1]
                
                let group = CAAnimationGroup()
                group.animations = [posAnim, scaleAnim, alphaAnim]
                group.beginTime = now + Double(tValue) * 0.24
                group.duration = 0.28
                group.timingFunction = easeOut
                group.fillMode = .both
                group.isRemovedOnCompletion = false
                spark.add(group, forKey: "wakeSpark")
            }
            
            // 5. Rounded landing halo ring around the target tab
            let ringRect = CGRect(origin: .zero, size: targetTabRect.size)
            let insetRect = ringRect.insetBy(dx: 0.5, dy: 0.5)
            if insetRect.width > 1, insetRect.height > 1 {
                let radius = min(6, insetRect.width * 0.5, insetRect.height * 0.5)
                let halo = CAShapeLayer()
                halo.bounds = ringRect
                halo.position = targetCenter
                halo.path = CGPath(roundedRect: insetRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                halo.fillColor = nil
                halo.strokeColor = accent.withAlphaComponent(0.85).cgColor
                halo.lineWidth = 1.6
                halo.opacity = 0
                rootLayer.addSublayer(halo)
                
                let haloScale = CABasicAnimation(keyPath: "transform.scale")
                haloScale.fromValue = 0.95
                haloScale.toValue = 1.09
                
                let haloAlpha = CAKeyframeAnimation(keyPath: "opacity")
                haloAlpha.values = [0, 0.80, 0]
                haloAlpha.keyTimes = [0, 0.15, 1]
                
                let haloGroup = CAAnimationGroup()
                haloGroup.animations = [haloScale, haloAlpha]
                haloGroup.beginTime = now + 0.20
                haloGroup.duration = 0.32
                haloGroup.timingFunction = easeOut
                haloGroup.fillMode = .both
                haloGroup.isRemovedOnCompletion = false
                halo.add(haloGroup, forKey: "landingHalo")
                
                // Second outer concentric elastic halo ring
                let outerHalo = CAShapeLayer()
                outerHalo.bounds = ringRect
                outerHalo.position = targetCenter
                outerHalo.path = CGPath(roundedRect: insetRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                outerHalo.fillColor = nil
                outerHalo.strokeColor = accent.withAlphaComponent(0.55).cgColor
                outerHalo.lineWidth = 1.2
                outerHalo.opacity = 0
                rootLayer.addSublayer(outerHalo)
                
                let outerScale = CABasicAnimation(keyPath: "transform.scale")
                outerScale.fromValue = 0.88
                outerScale.toValue = 1.24
                let outerAlpha = CAKeyframeAnimation(keyPath: "opacity")
                outerAlpha.values = [0, 0.55, 0]
                outerAlpha.keyTimes = [0, 0.20, 1]
                let outerGroup = CAAnimationGroup()
                outerGroup.animations = [outerScale, outerAlpha]
                outerGroup.beginTime = now + 0.23
                outerGroup.duration = 0.38
                outerGroup.timingFunction = easeOut
                outerGroup.fillMode = .both
                outerGroup.isRemovedOnCompletion = false
                outerHalo.add(outerGroup, forKey: "outerLandingHalo")
            }
            
            // 6. Six radial impact starburst sparks around targetCenter
            for idx in 0..<6 {
                let angle = (CGFloat(idx) / 6.0) * .pi * 2.0 + 0.25
                let dist: CGFloat = idx.isMultiple(of: 2) ? 24 : 18
                let endPt = CGPoint(
                    x: targetCenter.x + cos(angle) * dist,
                    y: targetCenter.y + sin(angle) * dist
                )
                let burstSpark = CALayer()
                burstSpark.bounds = CGRect(x: 0, y: 0, width: 3.2, height: 3.2)
                burstSpark.cornerRadius = 1.6
                burstSpark.position = targetCenter
                burstSpark.backgroundColor = (idx.isMultiple(of: 2)
                    ? (NSColor.white.blended(withFraction: 0.4, of: accent) ?? accent)
                    : accent).cgColor
                burstSpark.opacity = 0
                rootLayer.addSublayer(burstSpark)
                
                let pos = CABasicAnimation(keyPath: "position")
                pos.fromValue = NSValue(point: targetCenter)
                pos.toValue = NSValue(point: endPt)
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 1.2
                scale.toValue = 0.15
                let alpha = CAKeyframeAnimation(keyPath: "opacity")
                alpha.values = [0, 0.9, 0]
                alpha.keyTimes = [0, 0.15, 1]
                let burstGroup = CAAnimationGroup()
                burstGroup.animations = [pos, scale, alpha]
                burstGroup.beginTime = now + 0.22
                burstGroup.duration = 0.30
                burstGroup.timingFunction = easeOut
                burstGroup.fillMode = .both
                burstGroup.isRemovedOnCompletion = false
                burstSpark.add(burstGroup, forKey: "impactSpark")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { [weak overlay] in
            overlay?.removeFromSuperview()
        }
    }
}
