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
    
    private struct VisualBandSpringState {
        var minX: CGFloat
        var velMinX: CGFloat = 0
        var maxX: CGFloat
        var velMaxX: CGFloat = 0
        var minY: CGFloat
        var maxY: CGFloat
        var target: NSRect
        
        var isSettled: Bool {
            abs(self.minX - self.target.minX) < 0.15
                && abs(self.maxX - self.target.maxX) < 0.15
                && abs(self.velMinX) < 1.5
                && abs(self.velMaxX) < 1.5
        }
        
        var currentRect: NSRect {
            let loX = min(self.minX, self.maxX)
            let hiX = max(self.minX, self.maxX)
            return NSRect(
                x: loX,
                y: self.minY,
                width: max(2, hiX - loX),
                height: max(4, self.maxY - self.minY)
            )
        }
        
        init(rect: NSRect) {
            self.minX = rect.minX
            self.maxX = rect.maxX
            self.minY = rect.minY
            self.maxY = rect.maxY
            self.target = rect
        }
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
    private var lastBurstEmissionTime: CFTimeInterval = 0
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
    private var comboHudTierTextLayer: CATextLayer?
    private var comboHudCountTextLayer: CATextLayer?
    private var comboHudBarTrackLayer: CALayer?
    private var comboHudBarFillLayer: CALayer?
    private var comboHudLastTier: Int = -1
    private var comboHudLastWidth: CGFloat = 0
    
    // Inline ghost completion layers & acceptance sweep
    private var ghostRootLayer: CALayer?
    private var ghostContainerLayer: CALayer?
    private var ghostSweepLayer: CALayer?
    private var ghostThinkingLayer: CALayer?
    private var ghostThinkingBeamHostLayer: CALayer?
    private var ghostThinkingBeamLayer: CAGradientLayer?
    private var ghostThinkingBeamMaskLayer: CAShapeLayer?
    private var ghostThinkingDots: [CALayer] = []
    private var ghostThinkingLabelLayer: CALayer?
    private(set) var isShowingGhostThinking = false
    private(set) var lastGhostFrame: CGRect = .zero
    private(set) var lastTabBadgeXInContainer: CGFloat?
    private(set) var lastGhostShowsTabBadge = false
    
    // Persistent 120Hz Apple-style fluid spring Vim cursor + luminous wake trail
    private var vimRootLayer: CALayer?
    private var vimCursorLayer: CAShapeLayer?
    private var vimTrailLayers: [CAShapeLayer] = []
    private var trailRects: [NSRect] = []
    private var fluidCursor: FluidCursorState?
    private(set) var currentTargetRect: NSRect?
    private var vimDisplayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var lastStepTime: CFTimeInterval = 0
    private var currentTrailColor: NSColor = .controlAccentColor
    private var currentCursorAlpha: CGFloat = 0.56
    private static let trailLayerCount = 4
    
    // Elastic GPU-composited Vim Visual Selection bands (`v` / `V`)
    private var vimVisualRootLayer: CALayer?
    private var vimVisualBandLayers: [CAShapeLayer] = []
    private var vimVisualAnchorDotLayer: CAShapeLayer?
    private var vimVisualStates: [VisualBandSpringState] = []
    private var isVimVisualActive = false
    private var isPlayingVisualYankPulse = false
    private var visualSelectionColor: NSColor = .controlAccentColor
    private static let maxVisualBandLayers = 1
    
    /// Current rendered visual-mode row band rectangles (exposed for deterministic layout & motion tests).
    var activeVisualBandRects: [NSRect] {
        self.vimVisualStates.map(\.currentRect)
    }
    
    var isShowingVisualYankPulse: Bool {
        self.isPlayingVisualYankPulse
    }
    
    private var hasUnsettledVisualBands: Bool {
        self.isVimVisualActive && self.vimVisualStates.contains { !$0.isSettled }
    }
    
    
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
        self.hideVimVisualSelection(animated: false, withYankPulse: false)
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
            self.hideVimVisualSelection(animated: false, withYankPulse: false)
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
        if VimState.shared.mode == .visual,
           VimState.shared.visualOwnerID == ObjectIdentifier(textView)
        {
            textView.vimEngine.resyncVisualOverlayIfNeeded(animated: false)
        } else if !self.isPlayingVisualYankPulse {
            self.hideVimVisualSelection(animated: false, withYankPulse: false)
        }
    }
    
    
    /// Hides the persistent Vim cursor layer (e.g. when entering Insert mode).
    func hideVimCursorOnly() {
        
        self.vimDisplayLink?.isPaused = true
        self.fluidCursor = nil
        self.currentTargetRect = nil
        self.trailRects.removeAll()
        if !self.isPlayingVisualYankPulse {
            self.hideVimVisualSelection(animated: false, withYankPulse: false)
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.vimCursorLayer?.opacity = 0
        for layer in self.vimTrailLayers {
            layer.opacity = 0
        }
        CATransaction.commit()
    }
    
    
    /// Syncs seamless rounded selection bands for Vim `v` / `V` Visual mode.
    ///
    /// - Important: Bands are matched by **visual line `midY`** (never by array index) and locked to each
    ///   line fragment's exact `[minY, maxY]`, so moving upward (`k` / `↑`) or downward (`j` / `↓`) keeps
    ///   all previously selected lines 100% stationary with zero vertical bounce, seam splitting, or convulsion.
    func syncVimVisualSelection(
        range: NSRange,
        anchorLocation: Int?,
        activeLocation: Int?,
        isLinewise: Bool,
        animated: Bool,
        isContinuous: Bool = false
    ) {
        guard self.ownsVimCursorDrawing,
              VimState.shared.mode == .visual,
              let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else {
            if !self.isPlayingVisualYankPulse {
                self.hideVimVisualSelection(animated: false, withYankPulse: false)
            }
            return
        }
        
        self.ensureVimVisualLayers(in: hostLayer)
        let accent = NSColor.controlAccentColor.blended(withFraction: 0.25, of: textView.effectiveCursorColor)
            ?? textView.effectiveCursorColor
        self.visualSelectionColor = accent
        
        let stringLength = (textView.string as NSString).length
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: stringLength))
        var targetRects: [NSRect] = []
        
        if clampedRange.length > 0 {
            let containerOrigin = textView.textContainerOrigin
            let fullGlyphRange = layoutManager.glyphRange(forCharacterRange: clampedRange, actualCharacterRange: nil)
            let effectiveGlyphRange: NSRange
            let visible = textView.visibleRect
            if visible.width > 0 && visible.height > 0 {
                let padY = max(320, visible.height * 0.75)
                let queryInContainer = visible
                    .insetBy(dx: 0, dy: -padY)
                    .offsetBy(dx: -containerOrigin.x, dy: -containerOrigin.y)
                layoutManager.ensureLayout(forBoundingRect: queryInContainer, in: textContainer)
                let visibleGlyphs = layoutManager.glyphRange(forBoundingRectWithoutAdditionalLayout: queryInContainer, in: textContainer)
                let clipped = NSIntersectionRange(fullGlyphRange, visibleGlyphs)
                effectiveGlyphRange = clipped.length > 0 ? clipped : fullGlyphRange
            } else {
                layoutManager.ensureLayout(forGlyphRange: fullGlyphRange)
                effectiveGlyphRange = fullGlyphRange
            }
            
            if effectiveGlyphRange.length > 0 {
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: effectiveGlyphRange,
                    withinSelectedGlyphRange: fullGlyphRange,
                    in: textContainer
                ) { rect, _ in
                    var adjusted = rect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
                    if isLinewise {
                        let rawContainerW = textContainer.size.width
                        let finiteContainerW = (rawContainerW.isFinite && rawContainerW > 0 && rawContainerW <= 100_000)
                            ? rawContainerW
                            : (textView.enclosingScrollView?.documentVisibleRect.width ?? textView.bounds.width)
                        adjusted.size.width = max(adjusted.width, max(16, finiteContainerW - adjusted.minX))
                    } else {
                        adjusted.size.width = max(adjusted.width, 6)
                    }
                    adjusted = adjusted.insetBy(dx: -1, dy: 0)
                    if adjusted.width > 0, adjusted.height > 0 {
                        targetRects.append(adjusted)
                    }
                }
            }
        } else if let anchorLocation, let cursorRect = textView.vimCursorRect(at: anchorLocation) {
            targetRects.append(cursorRect.insetBy(dx: -1, dy: 0))
        }
        
        let previousStates = self.vimVisualStates
        let wasActive = self.isVimVisualActive && !previousStates.isEmpty
        self.isVimVisualActive = !targetRects.isEmpty
        
        if let anchorDot = self.vimVisualAnchorDotLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            anchorDot.opacity = 0
            CATransaction.commit()
        }
        
        let shouldAnimateHorizontally = animated
            && wasActive
            && !isContinuous
            && !AnimationConstants.isReducedMotionEnabled
            && textView.window != nil
            && !targetRects.isEmpty
        
        guard shouldAnimateHorizontally else {
            self.vimVisualStates = targetRects.map(VisualBandSpringState.init(rect:))
            self.applyVisualBandLayersImmediate()
            return
        }
        
        let prevTopMidY = previousStates.first?.target.midY ?? .greatestFiniteMagnitude
        var usedOldIndices = Set<Int>()
        var updatedStates: [VisualBandSpringState] = []
        updatedStates.reserveCapacity(targetRects.count)
        
        for target in targetRects {
            let toleranceY = max(4.0, target.height * 0.45)
            var bestIdx: Int?
            var bestDeltaY = CGFloat.greatestFiniteMagnitude
            for (oldIdx, oldState) in previousStates.enumerated() where !usedOldIndices.contains(oldIdx) {
                let dy = abs(oldState.target.midY - target.midY)
                if dy <= toleranceY && dy < bestDeltaY {
                    bestDeltaY = dy
                    bestIdx = oldIdx
                }
            }
            
            if let bestIdx {
                usedOldIndices.insert(bestIdx)
                var matched = previousStates[bestIdx]
                // Lock vertical coordinates strictly to the line fragment so adjacent rows never gap or bounce
                matched.minY = target.minY
                matched.maxY = target.maxY
                matched.target = target
                updatedStates.append(matched)
            } else if isLinewise {
                // Linewise (`V`) rows span full width cleanly on entry without partial-width horizontal wipe
                updatedStates.append(VisualBandSpringState(rect: target))
            } else {
                // Newly added characterwise (`v`) row: lock Y immediately flush with neighbor rows,
                // and do a short critically-damped horizontal sweep along the sweep direction.
                let isSweepingUpward = target.midY < prevTopMidY - 1.0
                let span = target.width
                let seedRect: NSRect
                if span <= 16 {
                    seedRect = target
                } else if isSweepingUpward {
                    let seedWidth = max(16, span * 0.72)
                    seedRect = NSRect(x: target.maxX - seedWidth, y: target.minY, width: seedWidth, height: target.height)
                } else {
                    let seedWidth = max(16, span * 0.72)
                    seedRect = NSRect(x: target.minX, y: target.minY, width: seedWidth, height: target.height)
                }
                var fresh = VisualBandSpringState(rect: seedRect)
                fresh.target = target
                updatedStates.append(fresh)
            }
        }
        
        self.vimVisualStates = updatedStates
        // Commit initial path immediately in the same CATransaction as scroll/selection so scrolling never lags 1 frame
        self.applyVisualBandLayersImmediate()
        if self.hasUnsettledVisualBands {
            self.startOrResumeDisplayLink(for: textView)
        }
    }
    
    
    /// Hides the elastic Vim visual selection bands, optionally playing a brief luminous confirm flash (e.g. on `y`).
    func hideVimVisualSelection(animated: Bool = false, withYankPulse: Bool) {
        
        let hadBands = self.isVimVisualActive || !self.vimVisualStates.isEmpty
        self.isVimVisualActive = false
        
        if withYankPulse, hadBands, let root = self.vimVisualRootLayer {
            self.isPlayingVisualYankPulse = true
            let accent = self.visualSelectionColor
            let targetRects = self.vimVisualStates.map(\.target)
            if let primaryLayer = self.vimVisualBandLayers.first, !targetRects.isEmpty {
                primaryLayer.fillColor = accent.withAlphaComponent(0.32).cgColor
                primaryLayer.strokeColor = nil
                primaryLayer.lineWidth = 0
                primaryLayer.path = Self.buildSeamlessVisualSelectionPath(rects: targetRects)
                primaryLayer.opacity = 1.0
            }
            for layer in self.vimVisualBandLayers.dropFirst() {
                layer.opacity = 0
            }
            self.vimVisualStates.removeAll()
            self.vimVisualAnchorDotLayer?.opacity = 0
            
            root.removeAllAnimations()
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [1.0, 1.0, 0.0]
            pulse.keyTimes = [0.0, 0.25, 1.0]
            pulse.duration = 0.24
            pulse.isRemovedOnCompletion = true
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPlayingVisualYankPulse = false
                    guard !self.isVimVisualActive else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    for layer in self.vimVisualBandLayers {
                        layer.opacity = 0
                    }
                    self.vimVisualRootLayer?.opacity = 1
                    CATransaction.commit()
                }
            }
            root.add(pulse, forKey: "visualYankPulse")
            CATransaction.commit()
            return
        }
        
        self.isPlayingVisualYankPulse = false
        self.vimVisualStates.removeAll()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.vimVisualAnchorDotLayer?.opacity = 0
        for layer in self.vimVisualBandLayers {
            layer.removeAllAnimations()
            layer.opacity = 0
        }
        CATransaction.commit()
    }
    
    
    /// Fast check for whether typing visual bursts are currently enabled, allowing callers to skip caret layout queries when off.
    var isTypewriterEffectEnabled: Bool {
        
        guard !AnimationConstants.isReducedMotionEnabled else { return false }
        return UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: CotLocalDatabase.ConfigKey.typewriterEffectEnabled)
    }
    
    
    /// Triggers tactile, balanced typing visual feedback at `rect`.
    func triggerTypewriterBurst(at rect: NSRect, color: NSColor? = nil, intensityScale: CGFloat = 1.0) {
        
        guard self.isTypewriterEffectEnabled else { return }
        guard let textView = self.textView, textView.window?.isKeyWindow == true else { return }
        guard let hostLayer = self.ensureClippedHostLayer(for: textView) else { return }
        
        let now = CACurrentMediaTime()
        if now - self.lastKeystrokeTime < 1.6 {
            self.comboCount += 1
        } else {
            self.comboCount = 1
        }
        self.lastKeystrokeTime = now
        
        // Coalesce ultra-rapid key-repeat storms (>40Hz) so CoreAnimation transactions never queue up behind typing.
        guard now - self.lastBurstEmissionTime >= 0.024 else { return }
        self.lastBurstEmissionTime = now
        
        self.ensureTypewriterLayers(in: hostLayer)
        
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
            let tierLayer = self.comboHudTierTextLayer,
            let countLayer = self.comboHudCountTextLayer,
            let trackLayer = self.comboHudBarTrackLayer,
            let fillLayer = self.comboHudBarFillLayer
        else { return }
        
        let tierIndex: Int
        let tierTitle: String
        let accentColor: NSColor
        switch combo {
            case ..<18:
                tierIndex = 0
                tierTitle = "FLOW"
                accentColor = NSColor(srgbRed: 0.18, green: 0.68, blue: 0.96, alpha: 1.0)
            case 18..<40:
                tierIndex = 1
                tierTitle = "RHYTHM"
                accentColor = NSColor(srgbRed: 0.08, green: 0.82, blue: 0.72, alpha: 1.0)
            case 40..<80:
                tierIndex = 2
                tierTitle = "SURGE"
                accentColor = NSColor(srgbRed: 0.62, green: 0.44, blue: 0.96, alpha: 1.0)
            default:
                tierIndex = 3
                tierTitle = "MASTER"
                accentColor = NSColor(srgbRed: 0.96, green: 0.48, blue: 0.32, alpha: 1.0)
        }
        
        let scale = textView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let countText = "×\(combo)"
        let tierW: CGFloat = switch tierIndex {
            case 0: 30
            case 1: 42
            case 2: 36
            default: 44
        }
        let digitCount = countText.count
        let countW = CGFloat(digitCount) * 9.5 + 4
        let hudWidth = max(68, ceil(tierW + 4 + countW) + 16)
        let badgeHeight: CGFloat = 24
        let totalHeight: CGFloat = 28
        
        let viewBounds = scrollView.bounds
        let marginRight: CGFloat = 16
        let marginTop: CGFloat = 12
        let originX = max(12, viewBounds.width - hudWidth - marginRight)
        let originY = scrollView.isFlipped ? marginTop : max(12, viewBounds.height - totalHeight - marginTop)
        
        let tierChanged = (self.comboHudLastTier != tierIndex)
        let widthChanged = abs(self.comboHudLastWidth - hudWidth) > 0.5
        self.comboHudLastTier = tierIndex
        self.comboHudLastWidth = hudWidth
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAllAnimations()
        container.bounds = CGRect(x: 0, y: 0, width: hudWidth, height: totalHeight)
        container.position = CGPoint(x: originX + hudWidth / 2, y: originY + totalHeight / 2)
        container.opacity = 0.92
        
        if tierChanged || widthChanged {
            badgeLayer.frame = CGRect(x: 0, y: 0, width: hudWidth, height: badgeHeight)
            badgeLayer.backgroundColor = accentColor.withAlphaComponent(0.11).cgColor
            badgeLayer.borderColor = accentColor.withAlphaComponent(0.26).cgColor
            badgeLayer.borderWidth = 0.75
            badgeLayer.cornerRadius = 6
            
            let startX = max(6, (hudWidth - (tierW + 4 + countW)) / 2)
            tierLayer.contentsScale = scale
            tierLayer.string = tierTitle
            tierLayer.foregroundColor = accentColor.withAlphaComponent(0.85).cgColor
            tierLayer.frame = CGRect(x: startX, y: 6.5, width: tierW, height: 12)
            
            countLayer.contentsScale = scale
            countLayer.foregroundColor = accentColor.cgColor
            countLayer.frame = CGRect(x: startX + tierW + 4, y: 2.5, width: countW, height: 19)
            
            let trackWidth = hudWidth - 10
            let trackY = badgeHeight + 2
            trackLayer.frame = CGRect(x: 5, y: trackY, width: trackWidth, height: 2)
            trackLayer.backgroundColor = accentColor.withAlphaComponent(0.15).cgColor
            trackLayer.cornerRadius = 1.0
            
            fillLayer.anchorPoint = CGPoint(x: 1.0, y: 0.5)
            fillLayer.bounds = CGRect(x: 0, y: 0, width: trackWidth, height: 2)
            fillLayer.position = CGPoint(x: trackWidth, y: 1.0)
            fillLayer.backgroundColor = accentColor.withAlphaComponent(0.80).cgColor
            fillLayer.cornerRadius = 1.0
        }
        
        countLayer.string = countText
        fillLayer.removeAllAnimations()
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
        
        _ = trailingLineAdvance
        guard !text.isEmpty,
              let textView = self.textView,
              textView.window != nil,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return 0 }
        
        self.ensureGhostLayers(in: hostLayer)
        guard let container = self.ghostContainerLayer else { return 0 }
        self.hideGhostThinkingLayer(animated: false)
        self.isShowingGhostThinking = false
        
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
        let visibleRight = textView.visibleRect.width > 0 ? min(textView.bounds.maxX, textView.visibleRect.maxX) : textView.bounds.maxX
        let availableWidth = max(28, visibleRight - startX - 10)
        
        let badgeFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let badgeText = "Tab"
        let badgeTextSize = (badgeText as NSString).size(withAttributes: [.font: badgeFont])
        let badgeWidth = ceil(badgeTextSize.width) + 9
        let badgeHeight = min(14.5, max(12.5, rowHeight - 4))
        let badgeGap: CGFloat = 5
        
        let showsBadge = availableWidth >= (badgeWidth + badgeGap + 18)
        let reservedBadgeSpace = showsBadge ? (badgeGap + badgeWidth + 2) : 2
        let maxTextWidth = max(16, availableWidth - reservedBadgeSpace)
        let drawnTextWidth = min(rawTextWidth, maxTextWidth)
        let badgeX = drawnTextWidth + badgeGap
        let containerWidth = ceil(showsBadge ? (badgeX + badgeWidth + 2) : (drawnTextWidth + 2))
        
        self.lastTabBadgeXInContainer = showsBadge ? badgeX : nil
        self.lastGhostShowsTabBadge = showsBadge
        
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
        self.lastGhostFrame = targetFrame
        
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
        
        return (startX - caretRect.minX) + containerWidth + 4
    }
    
    
    /// Shows a small breathing ink matrix next to the caret while an AI Next Token request is in flight.
    func showGhostThinkingIndicator(
        at caretRect: NSRect,
        font: NSFont,
        lineHeight: CGFloat,
        baselineOffset: CGFloat
    ) {
        _ = baselineOffset
        guard let textView = self.textView,
              textView.window?.isKeyWindow == true,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return }
        
        self.ensureGhostLayers(in: hostLayer)
        guard let holder = self.ghostThinkingLayer else { return }
        
        // A quiet 3×3 ink matrix in the caret's own color: it reads as "the cursor is thinking",
        // moves enough to notice, and carries no gradient, glow or badge.
        let ink = textView.effectiveCursorColor
        let rowHeight = max(lineHeight, ceil(font.ascender - font.descender + 2))
        let dot: CGFloat = max(2.0, min(2.6, font.pointSize * 0.17))
        let spacing: CGFloat = dot * 0.6
        let extent = dot * 3 + spacing * 2
        let frame = CGRect(
            x: caretRect.maxX + 4,
            y: caretRect.minY + ((rowHeight - extent) / 2).rounded(),
            width: extent,
            height: extent
        )
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.ghostContainerLayer?.removeAllAnimations()
        self.ghostContainerLayer?.opacity = 0
        self.ghostContainerLayer?.contents = nil
        
        holder.removeAllAnimations()
        holder.frame = frame
        holder.backgroundColor = nil
        holder.borderWidth = 0
        holder.shadowOpacity = 0
        holder.opacity = 1
        self.ghostThinkingBeamHostLayer?.isHidden = true
        self.ghostThinkingLabelLayer?.isHidden = true
        
        for (index, layer) in self.ghostThinkingDots.enumerated() {
            let row = index / 3
            let col = index % 3
            layer.removeAllAnimations()
            layer.frame = CGRect(
                x: CGFloat(col) * (dot + spacing),
                y: CGFloat(row) * (dot + spacing),
                width: dot,
                height: dot
            )
            layer.cornerRadius = dot / 2
            layer.backgroundColor = ink.cgColor
            layer.opacity = 0.25
            layer.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        
        self.isShowingGhostThinking = true
        
        guard !AnimationConstants.isReducedMotionEnabled else {
            for layer in self.ghostThinkingDots { layer.opacity = 0.55 }
            return
        }
        
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        holder.add(fade, forKey: "thinkingEnter")
        
        // Diagonal wave, top-left to bottom-right, one calm cycle per second.
        let cycle: CFTimeInterval = 1.0
        let start = CACurrentMediaTime()
        for (index, layer) in self.ghostThinkingDots.enumerated() {
            let diagonal = Double(index / 3 + index % 3)
            let wave = CAKeyframeAnimation(keyPath: "opacity")
            wave.values = [0.22, 0.9, 0.22, 0.22]
            wave.keyTimes = [0, 0.25, 0.55, 1]
            wave.duration = cycle
            wave.beginTime = start + diagonal * (cycle / 10)
            wave.repeatCount = .infinity
            wave.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(wave, forKey: "matrixWave")
        }
    }
    
    
    private func hideGhostThinkingLayer(animated: Bool) {
        
        guard let pill = self.ghostThinkingLayer else { return }
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pill.removeAllAnimations()
            pill.opacity = 0
            pill.frame = .zero
            self.ghostThinkingBeamLayer?.removeAllAnimations()
            self.ghostThinkingLabelLayer?.removeAllAnimations()
            for dot in self.ghostThinkingDots {
                dot.removeAllAnimations()
            }
            CATransaction.commit()
            return
        }
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.10)
        CATransaction.setCompletionBlock { [weak self, weak pill] in
            Task { @MainActor in
                guard let self, let pill, !self.isShowingGhostThinking else { return }
                self.hideGhostThinkingLayer(animated: false)
            }
        }
        pill.opacity = 0
        CATransaction.commit()
    }
    
    
    /// Hides the inline ghost candidate cleanly.
    func hideGhostSuggestion(animated: Bool = false) {
        
        let wasThinking = self.isShowingGhostThinking
        self.isShowingGhostThinking = false
        self.lastGhostFrame = .zero
        self.lastTabBadgeXInContainer = nil
        self.lastGhostShowsTabBadge = false
        self.hideGhostThinkingLayer(animated: animated && wasThinking)
        
        guard let container = self.ghostContainerLayer else { return }
        let sweep = self.ghostSweepLayer
        
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            container.removeAllAnimations()
            container.opacity = 0
            container.contents = nil
            container.frame = .zero
            sweep?.removeAllAnimations()
            sweep?.opacity = 0
            CATransaction.commit()
            return
        }
        
        guard container.opacity > 0.01 || wasThinking else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        CATransaction.setCompletionBlock { [weak self, weak container] in
            Task { @MainActor in
                guard let self, let container, container.opacity <= 0.01, !self.isShowingGhostThinking else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                container.contents = nil
                container.frame = .zero
                CATransaction.commit()
            }
        }
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
    
    
    func moveVimCursor(
        to rawRect: NSRect,
        color: NSColor,
        animated: Bool,
        fallbackFrom: NSRect? = nil,
        isContinuous: Bool = false
    ) {
        guard let textView = self.textView,
              rawRect.width > 0, rawRect.height > 0, rawRect.height < 2400,
              let hostLayer = self.ensureClippedHostLayer(for: textView)
        else { return }
        
        self.ensureVimLayers(in: hostLayer)
        guard let cursorLayer = self.vimCursorLayer else { return }
        
        let mode = VimState.shared.mode
        let visualRect: NSRect
        if mode == .replace {
            let barH = max(3, min(10, round(rawRect.height * 0.22)))
            visualRect = NSRect(x: rawRect.minX, y: rawRect.maxY - barH, width: rawRect.width, height: barH)
        } else if rawRect.height > 56 {
            // Inline image line: render a crisp, unmistakable vertical accent bar beside the image card
            let barW = max(3.5, min(5.0, rawRect.width))
            visualRect = NSRect(x: rawRect.minX, y: rawRect.minY, width: barW, height: rawRect.height)
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
            if self.vimDisplayLink?.isPaused != false {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for layer in self.vimTrailLayers {
                    layer.opacity = 0
                }
                CATransaction.commit()
            }
            return
        }
        
        if self.fluidCursor == nil, let fallbackFrom,
           fallbackFrom.width > 0, fallbackFrom.height > 0, fallbackFrom.height < 2400,
           textView.visibleRect.insetBy(dx: -80, dy: -160).intersects(fallbackFrom)
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
            if !self.hasUnsettledVisualBands {
                self.vimDisplayLink?.isPaused = true
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let snappedPath = CGPath(roundedRect: visualRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            cursorLayer.path = snappedPath
            cursorLayer.shadowPath = snappedPath
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
            let snappedPath = CGPath(roundedRect: visualRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            cursorLayer.path = snappedPath
            cursorLayer.shadowPath = snappedPath
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
        
        guard self.ownsVimCursorDrawing else {
            link.isPaused = true
            return
        }
        
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - self.lastStepTime, 1.0 / 240.0), 1.0 / 24.0))
        self.lastStepTime = now
        
        var visualSettled = true
        if self.isVimVisualActive && !self.vimVisualStates.isEmpty {
            visualSettled = self.stepVisualBands(dt: dt)
        }
        
        var cursorSettled = true
        if let cursorLayer = self.vimCursorLayer,
           var state = self.fluidCursor,
           let targetRect = self.currentTargetRect
        {
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
                let settledPath = CGPath(roundedRect: targetRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                cursorLayer.path = settledPath
                cursorLayer.shadowPath = settledPath
                for layer in self.vimTrailLayers {
                    layer.opacity = 0
                }
                CATransaction.commit()
                cursorSettled = true
            } else {
                cursorSettled = false
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
                cursorLayer.shadowPath = path
                CATransaction.commit()
            }
        }
        
        if cursorSettled && visualSettled {
            link.isPaused = true
        }
    }
    
    
    private func stepVisualBands(dt: CGFloat) -> Bool {
        
        var allSettled = true
        // Critically damped (`zeta = 1.0`, zero overshoot) fast horizontal glide; Y stays locked to true row bounds.
        let omega: CGFloat = 58.0
        
        for idx in self.vimVisualStates.indices {
            var s = self.vimVisualStates[idx]
            let t = s.target
            s.minY = t.minY
            s.maxY = t.maxY
            
            let (nMinX, vMinX) = Self.stepCriticallyDampedSpring(pos: s.minX, vel: s.velMinX, target: t.minX, omega: omega, dt: dt)
            let (nMaxX, vMaxX) = Self.stepCriticallyDampedSpring(pos: s.maxX, vel: s.velMaxX, target: t.maxX, omega: omega, dt: dt)
            
            let err = max(abs(nMinX - t.minX), abs(nMaxX - t.maxX))
            let vel = max(abs(vMinX), abs(vMaxX))
            
            if err < 0.15 && vel < 1.5 {
                s.minX = t.minX; s.velMinX = 0
                s.maxX = t.maxX; s.velMaxX = 0
            } else {
                s.minX = nMinX; s.velMinX = vMinX
                s.maxX = nMaxX; s.velMaxX = vMaxX
                allSettled = false
            }
            self.vimVisualStates[idx] = s
        }
        
        self.applyVisualBandLayersImmediate()
        return allSettled
    }
    
    
    private static func stepCriticallyDampedSpring(
        pos: CGFloat,
        vel: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        dt: CGFloat
    ) -> (CGFloat, CGFloat) {
        let x0 = pos - target
        let decay = exp(-omega * dt)
        let c2 = vel + omega * x0
        let newX = target + (x0 + c2 * dt) * decay
        let newV = (vel - c2 * omega * dt) * decay
        return (newX, newV)
    }
    
    
    private func applyVisualBandLayersImmediate() {
        
        let accent = self.visualSelectionColor
        let fill = accent.withAlphaComponent(0.20).cgColor
        let activeRects = self.vimVisualStates.map(\.currentRect)
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let primaryLayer = self.vimVisualBandLayers.first, !activeRects.isEmpty {
            primaryLayer.path = Self.buildSeamlessVisualSelectionPath(rects: activeRects)
            primaryLayer.fillColor = fill
            primaryLayer.strokeColor = nil
            primaryLayer.lineWidth = 0
            primaryLayer.fillRule = .nonZero
            primaryLayer.opacity = 1.0
        } else {
            self.vimVisualBandLayers.first?.opacity = 0
        }
        for layer in self.vimVisualBandLayers.dropFirst() {
            layer.opacity = 0
        }
        CATransaction.commit()
    }
    
    
    /// Builds one seamless multi-line selection path with per-corner smart rounding:
    /// adjacent lines flush along an edge share a razor-straight vertical seam (no `)(` V-notches
    /// and no double-alpha horizontal overlaps), while outer corners stay smoothly rounded.
    static func buildSeamlessVisualSelectionPath(rects rawRects: [NSRect]) -> CGPath {
        let path = CGMutablePath()
        guard !rawRects.isEmpty else { return path }
        
        // Sort top-to-bottom (flipped NSTextView coordinates: minY = top, maxY = bottom)
        var rects = rawRects
            .filter { $0.width > 0 && $0.height > 0 }
            .sorted { $0.minY < $1.minY }
        guard !rects.isEmpty else { return path }
        
        // Snap nearly-touching vertical seams cleanly so there is zero hairline gap or overlap
        if rects.count > 1 {
            for i in 1..<rects.count {
                let prevMaxY = rects[i - 1].maxY
                let delta = rects[i].minY - prevMaxY
                if abs(delta) <= 3.0 {
                    let bottom = max(prevMaxY + 1.0, rects[i].maxY)
                    rects[i] = NSRect(
                        x: rects[i].minX,
                        y: prevMaxY,
                        width: rects[i].width,
                        height: bottom - prevMaxY
                    )
                }
            }
        }
        
        for i in 0..<rects.count {
            let r = rects[i]
            let prev: NSRect? = (i > 0 && abs(r.minY - rects[i - 1].maxY) <= 1.0) ? rects[i - 1] : nil
            let next: NSRect? = (i + 1 < rects.count && abs(rects[i + 1].minY - r.maxY) <= 1.0) ? rects[i + 1] : nil
            
            let baseR = min(3.5, min(r.width * 0.45, r.height * 0.28))
            
            let rTL: CGFloat = if let prev {
                (r.minX < prev.minX - 1.5) ? min(baseR, (prev.minX - r.minX) * 0.5) : 0
            } else {
                baseR
            }
            let rTR: CGFloat = if let prev {
                (r.maxX > prev.maxX + 1.5) ? min(baseR, (r.maxX - prev.maxX) * 0.5) : 0
            } else {
                baseR
            }
            let rBL: CGFloat = if let next {
                (r.minX < next.minX - 1.5) ? min(baseR, (next.minX - r.minX) * 0.5) : 0
            } else {
                baseR
            }
            let rBR: CGFloat = if let next {
                (r.maxX > next.maxX + 1.5) ? min(baseR, (r.maxX - next.maxX) * 0.5) : 0
            } else {
                baseR
            }
            
            // Tiny 0.5pt overlap into touching next band eliminates Retina sub-pixel hairline seams
            // with zero double-alpha darkening because everything fills inside one unified .nonZero CGPath.
            let drawRect = (next != nil)
                ? NSRect(x: r.minX, y: r.minY, width: r.width, height: r.height + 0.5)
                : r
            
            Self.appendSelectiveRoundedRect(
                to: path,
                rect: drawRect,
                topLeft: rTL,
                topRight: rTR,
                bottomRight: rBR,
                bottomLeft: rBL
            )
        }
        return path
    }
    
    
    private static func appendSelectiveRoundedRect(
        to path: CGMutablePath,
        rect: NSRect,
        topLeft: CGFloat,
        topRight: CGFloat,
        bottomRight: CGFloat,
        bottomLeft: CGFloat
    ) {
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let halfW = rect.width * 0.5
        let halfH = rect.height * 0.5
        
        let tl = max(0, min(topLeft, min(halfW, halfH)))
        let tr = max(0, min(topRight, min(halfW, halfH)))
        let br = max(0, min(bottomRight, min(halfW, halfH)))
        let bl = max(0, min(bottomLeft, min(halfW, halfH)))
        
        path.move(to: CGPoint(x: minX + tl, y: minY))
        
        // Top-right corner
        if tr > 0 {
            path.addLine(to: CGPoint(x: maxX - tr, y: minY))
            path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: minY + tr), radius: tr)
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
        }
        
        // Bottom-right corner
        if br > 0 {
            path.addLine(to: CGPoint(x: maxX, y: maxY - br))
            path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX - br, y: maxY), radius: br)
        } else {
            path.addLine(to: CGPoint(x: maxX, y: maxY))
        }
        
        // Bottom-left corner
        if bl > 0 {
            path.addLine(to: CGPoint(x: minX + bl, y: maxY))
            path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY - bl), radius: bl)
        } else {
            path.addLine(to: CGPoint(x: minX, y: maxY))
        }
        
        // Top-left corner
        if tl > 0 {
            path.addLine(to: CGPoint(x: minX, y: minY + tl))
            path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX + tl, y: minY), radius: tl)
        } else {
            path.addLine(to: CGPoint(x: minX, y: minY))
        }
        
        path.closeSubpath()
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
        self.ghostThinkingLayer = nil
        self.ghostThinkingBeamHostLayer = nil
        self.ghostThinkingBeamLayer = nil
        self.ghostThinkingBeamMaskLayer = nil
        self.ghostThinkingDots.removeAll()
        self.ghostThinkingLabelLayer = nil
        
        self.vimRootLayer?.removeFromSuperlayer()
        self.vimRootLayer = nil
        self.vimCursorLayer = nil
        self.vimTrailLayers.removeAll()
        self.trailRects.removeAll()
        
        self.vimVisualRootLayer?.removeFromSuperlayer()
        self.vimVisualRootLayer = nil
        self.vimVisualBandLayers.removeAll()
        self.vimVisualAnchorDotLayer = nil
        self.vimVisualStates.removeAll()
        self.isVimVisualActive = false
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
            self.comboHudTierTextLayer = nil
            self.comboHudCountTextLayer = nil
            self.comboHudBarTrackLayer = nil
            self.comboHudBarFillLayer = nil
            self.comboHudLastTier = -1
            self.comboHudLastWidth = 0
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
        
        let tierText = CATextLayer()
        tierText.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
        tierText.fontSize = 8.5
        tierText.alignmentMode = .left
        tierText.isWrapped = false
        badge.addSublayer(tierText)
        self.comboHudTierTextLayer = tierText
        
        let countText = CATextLayer()
        countText.font = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        countText.fontSize = 15
        countText.alignmentMode = .left
        countText.isWrapped = false
        badge.addSublayer(countText)
        self.comboHudCountTextLayer = countText
        
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
        
        // LeiBox-inspired AI Thinking Pill (3×3 staggered wave matrix + rotating conic border-beam)
        let pill = CALayer()
        pill.opacity = 0
        pill.masksToBounds = false
        root.addSublayer(pill)
        self.ghostThinkingLayer = pill
        
        let beamHost = CALayer()
        beamHost.masksToBounds = true
        pill.addSublayer(beamHost)
        self.ghostThinkingBeamHostLayer = beamHost
        
        let beam = CAGradientLayer()
        beamHost.addSublayer(beam)
        self.ghostThinkingBeamLayer = beam
        
        let beamMask = CAShapeLayer()
        beamHost.mask = beamMask
        self.ghostThinkingBeamMaskLayer = beamMask
        
        var dots: [CALayer] = []
        dots.reserveCapacity(9)
        for _ in 0..<9 {
            let dot = CALayer()
            pill.addSublayer(dot)
            dots.append(dot)
        }
        self.ghostThinkingDots = dots
        
        let labelLayer = CALayer()
        pill.addSublayer(labelLayer)
        self.ghostThinkingLabelLayer = labelLayer
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
    
    
    private func ensureVimVisualLayers(in hostLayer: CALayer) {
        
        self.resetHostedLayersIfNeeded(for: hostLayer)
        guard self.vimVisualRootLayer == nil else { return }
        
        let root = CALayer()
        root.zPosition = 172
        hostLayer.addSublayer(root)
        self.vimVisualRootLayer = root
        
        var bands: [CAShapeLayer] = []
        bands.reserveCapacity(Self.maxVisualBandLayers)
        for _ in 0..<Self.maxVisualBandLayers {
            let band = CAShapeLayer()
            band.opacity = 0
            root.addSublayer(band)
            bands.append(band)
        }
        self.vimVisualBandLayers = bands
        
        let anchorDot = CAShapeLayer()
        anchorDot.opacity = 0
        root.addSublayer(anchorDot)
        self.vimVisualAnchorDotLayer = anchorDot
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
