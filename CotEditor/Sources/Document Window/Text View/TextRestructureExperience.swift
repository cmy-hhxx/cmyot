//
//  TextRestructureExperience.swift
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
import SwiftUI

// MARK: - Pure Domain Models & Regret-Proof State Machine

nonisolated enum TextRestructureMode: String, Equatable, Sendable {
    
    case formatClean
    case semanticRestructure
    
    var displayTitle: String {
        switch self {
            case .formatClean:
                AppLanguage.text("清洗规整", en: "Clean & Structure")
            case .semanticRestructure:
                AppLanguage.text("语义规整", en: "Semantic Restructure")
        }
    }
    
    var completedBadgeTitle: String {
        switch self {
            case .formatClean:
                AppLanguage.text("已清洗", en: "Cleaned")
            case .semanticRestructure:
                AppLanguage.text("已规整", en: "Restructured")
        }
    }
    
    var symbolName: String {
        switch self {
            case .formatClean: "list.bullet.indent"
            case .semanticRestructure: "doc.plaintext"
        }
    }
}


/// Pure deterministic metrics describing what changed during format cleaning or semantic restructuring.
nonisolated struct TextRestructureMetrics: Equatable, Sendable {
    
    let removedMarkerCount: Int
    let tabIndentedLineCount: Int
    let originalCharCount: Int
    let resultCharCount: Int
    
    var reductionPercent: Int {
        guard self.originalCharCount > 0, self.resultCharCount < self.originalCharCount else { return 0 }
        return Int((Double(self.originalCharCount - self.resultCharCount) / Double(self.originalCharCount) * 100.0).rounded())
    }
    
    
    static func compute(original: String, result: String) -> Self {
        let origMarkers = Self.countMarkdownNoiseTokens(in: original)
        let resMarkers = Self.countMarkdownNoiseTokens(in: result)
        let removed = max(0, origMarkers - resMarkers)
        let tabLines = result
            .components(separatedBy: "\n")
            .count { $0.hasPrefix("\t") }
        let origChars = original.trimmingCharacters(in: .whitespacesAndNewlines).count
        let resChars = result.trimmingCharacters(in: .whitespacesAndNewlines).count
        
        return TextRestructureMetrics(
            removedMarkerCount: removed,
            tabIndentedLineCount: tabLines,
            originalCharCount: origChars,
            resultCharCount: resChars
        )
    }
    
    
    func summaryText(for mode: TextRestructureMode) -> String {
        switch mode {
            case .formatClean:
                var parts: [String] = []
                if self.removedMarkerCount > 0 {
                    parts.append(AppLanguage.text("清除 \(self.removedMarkerCount) 处符号", en: "\(self.removedMarkerCount) markers"))
                }
                if self.tabIndentedLineCount > 0 {
                    parts.append(AppLanguage.text("\(self.tabIndentedLineCount) 行分层", en: "\(self.tabIndentedLineCount) indented"))
                }
                if parts.isEmpty {
                    return AppLanguage.text("\(self.originalCharCount)→\(self.resultCharCount) 字", en: "\(self.originalCharCount)→\(self.resultCharCount)")
                }
                return parts.joined(separator: " · ")
                
            case .semanticRestructure:
                if self.reductionPercent >= 5 {
                    return AppLanguage.text(
                        "精简 \(self.reductionPercent)% · \(self.originalCharCount)→\(self.resultCharCount) 字",
                        en: "-\(self.reductionPercent)% · \(self.originalCharCount)→\(self.resultCharCount)"
                    )
                }
                return AppLanguage.text(
                    "\(self.originalCharCount)→\(self.resultCharCount) 字",
                    en: "\(self.originalCharCount)→\(self.resultCharCount)"
                )
        }
    }
    
    
    private static let noiseTokenRegex = try! NSRegularExpression(
        pattern: #"(?:\*{1,3}|__|~~|`|^[ \t]*#{1,6}[ \t]+|^[ \t]*>[ \t]?)"#,
        options: .anchorsMatchLines
    )
    
    private static func countMarkdownNoiseTokens(in text: String) -> Int {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return Self.noiseTokenRegex.numberOfMatches(in: text, range: range)
    }
}


/// Pure deterministic state machine managing multi-revision A/B comparison, revert, keep-both, and upgrade flows.
/// Guarantees `untouchedOriginalText` is always preserved so the user can always roll back completely.
nonisolated struct TextRestructureReviewMachine: Equatable, Sendable {
    
    struct Revision: Equatable, Sendable {
        let mode: TextRestructureMode
        let text: String
        let metrics: TextRestructureMetrics
    }
    
    struct MutationPlan: Equatable, Sendable {
        let replacement: String
        let replaceRange: NSRange
        let actionName: String
        let isRevertingOrOriginal: Bool
    }
    
    let untouchedOriginalText: String
    let isWholeDocument: Bool
    private(set) var revisions: [Revision]
    private(set) var selectedRevisionIndex: Int
    private(set) var activeRange: NSRange
    private(set) var showingOriginal: Bool
    
    var currentRevision: Revision {
        self.revisions[self.selectedRevisionIndex]
    }
    
    var activeDisplayedText: String {
        self.showingOriginal ? self.untouchedOriginalText : self.currentRevision.text
    }
    
    var canStepPreviousRevision: Bool {
        self.selectedRevisionIndex > 0
    }
    
    var canStepNextRevision: Bool {
        self.selectedRevisionIndex + 1 < self.revisions.count
    }
    
    
    init(
        mode: TextRestructureMode,
        originalText: String,
        transformedText: String,
        originLocation: Int,
        isWholeDocument: Bool
    ) {
        self.untouchedOriginalText = originalText
        self.isWholeDocument = isWholeDocument
        let rev = Revision(
            mode: mode,
            text: transformedText,
            metrics: TextRestructureMetrics.compute(original: originalText, result: transformedText)
        )
        self.revisions = [rev]
        self.selectedRevisionIndex = 0
        self.activeRange = NSRange(location: originLocation, length: (transformedText as NSString).length)
        self.showingOriginal = false
    }
    
    
    /// Toggles live in-place A/B comparison between `untouchedOriginalText` and `currentRevision.text`.
    mutating func toggleCompare() -> MutationPlan {
        let oldRange = self.activeRange
        self.showingOriginal.toggle()
        let nextText = self.activeDisplayedText
        self.activeRange = NSRange(location: oldRange.location, length: (nextText as NSString).length)
        return MutationPlan(
            replacement: nextText,
            replaceRange: oldRange,
            actionName: self.showingOriginal
                ? AppLanguage.text("对比原文", en: "Compare Original")
                : AppLanguage.text("查看规整结果", en: "Show Restructured"),
            isRevertingOrOriginal: self.showingOriginal
        )
    }
    
    
    /// Appends a new transformed revision (e.g. upgrading `formatClean` -> `semanticRestructure` or clicking Retry)
    /// while keeping `untouchedOriginalText` and all earlier revisions intact.
    mutating func appendRevision(mode: TextRestructureMode, transformedText: String) -> MutationPlan {
        let oldRange = self.activeRange
        let rev = Revision(
            mode: mode,
            text: transformedText,
            metrics: TextRestructureMetrics.compute(original: self.untouchedOriginalText, result: transformedText)
        )
        self.revisions.append(rev)
        self.selectedRevisionIndex = self.revisions.count - 1
        self.showingOriginal = false
        self.activeRange = NSRange(location: oldRange.location, length: (transformedText as NSString).length)
        return MutationPlan(
            replacement: transformedText,
            replaceRange: oldRange,
            actionName: mode.displayTitle,
            isRevertingOrOriginal: false
        )
    }
    
    
    /// Switches to an earlier or later revision (`delta = -1` or `+1`) when multiple versions exist.
    mutating func stepRevision(delta: Int) -> MutationPlan? {
        let targetIndex = self.selectedRevisionIndex + delta
        guard self.revisions.indices.contains(targetIndex) else { return nil }
        let oldRange = self.activeRange
        self.selectedRevisionIndex = targetIndex
        self.showingOriginal = false
        let nextText = self.currentRevision.text
        self.activeRange = NSRange(location: oldRange.location, length: (nextText as NSString).length)
        return MutationPlan(
            replacement: nextText,
            replaceRange: oldRange,
            actionName: self.currentRevision.mode.displayTitle,
            isRevertingOrOriginal: delta < 0
        )
    }
    
    
    /// Produces the mutation to restore `untouchedOriginalText` (nil if already displaying original).
    func revertPlan() -> MutationPlan? {
        guard !self.showingOriginal else { return nil }
        return MutationPlan(
            replacement: self.untouchedOriginalText,
            replaceRange: self.activeRange,
            actionName: AppLanguage.text("撤销规整", en: "Revert Restructure"),
            isRevertingOrOriginal: true
        )
    }
    
    
    /// Produces the mutation to commit the current transformed text (nil if already displaying it).
    func acceptPlan() -> MutationPlan? {
        guard self.showingOriginal else { return nil }
        return MutationPlan(
            replacement: self.currentRevision.text,
            replaceRange: self.activeRange,
            actionName: self.currentRevision.mode.displayTitle,
            isRevertingOrOriginal: false
        )
    }
    
    
    /// Produces the mutation that preserves BOTH the untouched original and the restructured version cleanly separated.
    func keepBothPlan() -> MutationPlan {
        let hadTrailingNewline = self.untouchedOriginalText.hasSuffix("\n")
        let cleanOrig = self.untouchedOriginalText.trimmingCharacters(in: .newlines)
        let cleanResult = self.currentRevision.text.trimmingCharacters(in: .newlines)
        var combined = cleanOrig + "\n\n" + cleanResult
        if hadTrailingNewline {
            combined += "\n"
        }
        return MutationPlan(
            replacement: combined,
            replaceRange: self.activeRange,
            actionName: AppLanguage.text("保留原文与规整结果", en: "Keep Both Original and Restructured"),
            isRevertingOrOriginal: false
        )
    }
}


// MARK: - Core Animation Inline Canvas Effects (120Hz GPU, Zero Layout Jitter)

@MainActor
final class EditorRestructureEffectOverlay {
    
    enum SweepDirection {
        case down
        case up
    }
    
    private weak var textView: EditorTextView?
    private var rootLayer: CALayer?
    private var washLayer: CALayer?
    private var scanMaskLayer: CALayer?
    private var scanBeamLayer: CAGradientLayer?
    private var railLayer: CALayer?
    
    private var activeRange: NSRange?
    private var isScanning = false
    private var isShowingReviewRail = false
    private var reviewShowingOriginal = false
    
    
    func attach(to textView: EditorTextView) {
        if self.textView !== textView {
            self.clearAll()
            self.textView = textView
        }
        self.ensureLayers()
    }
    
    
    /// Starts a calm, Apple-restrained ambient top-to-bottom scan shimmer over `range` while AI restructures.
    func startAmbientScan(in textView: EditorTextView, range: NSRange) {
        self.attach(to: textView)
        self.activeRange = range
        self.isScanning = true
        self.isShowingReviewRail = false
        
        guard let rect = self.clampedVisualRect(for: range, in: textView),
              let wash = self.washLayer,
              let scanMask = self.scanMaskLayer,
              let beam = self.scanBeamLayer,
              let rail = self.railLayer
        else { return }
        
        let accent = NSColor.controlAccentColor
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.removeAllAnimations()
        beam.removeAllAnimations()
        rail.removeAllAnimations()
        
        wash.frame = rect
        wash.cornerRadius = 6
        wash.backgroundColor = accent.withAlphaComponent(0.065).cgColor
        wash.opacity = 1
        
        rail.frame = CGRect(x: max(2, rect.minX - 6), y: rect.minY + 2, width: 2.5, height: max(12, rect.height - 4))
        rail.cornerRadius = 1.25
        rail.backgroundColor = accent.withAlphaComponent(0.72).cgColor
        rail.opacity = 1
        
        scanMask.frame = rect
        scanMask.cornerRadius = 6
        scanMask.masksToBounds = true
        scanMask.opacity = reduceMotion ? 0 : 1
        
        let beamH = max(36, min(72, rect.height * 0.42))
        beam.frame = CGRect(x: 0, y: -beamH, width: rect.width, height: beamH)
        beam.startPoint = CGPoint(x: 0.5, y: 0.0)
        beam.endPoint = CGPoint(x: 0.5, y: 1.0)
        beam.colors = [
            accent.withAlphaComponent(0.0).cgColor,
            accent.withAlphaComponent(0.14).cgColor,
            accent.withAlphaComponent(0.24).cgColor,
            accent.withAlphaComponent(0.14).cgColor,
            accent.withAlphaComponent(0.0).cgColor,
        ]
        beam.locations = [0.0, 0.25, 0.5, 0.75, 1.0]
        CATransaction.commit()
        
        guard !reduceMotion else { return }
        
        let travel = CABasicAnimation(keyPath: "position.y")
        travel.fromValue = -beamH * 0.5
        travel.toValue = rect.height + beamH * 0.5
        travel.duration = 1.45
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        beam.add(travel, forKey: "ambientScan")
        
        let railPulse = CABasicAnimation(keyPath: "opacity")
        railPulse.fromValue = 0.42
        railPulse.toValue = 0.92
        railPulse.duration = 0.9
        railPulse.autoreverses = true
        railPulse.repeatCount = .infinity
        railPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rail.add(railPulse, forKey: "railPulse")
    }
    
    
    /// Plays a crisp one-shot luminous sweep across `range` and optionally settles into a calm review rail.
    func playSweep(
        in textView: EditorTextView,
        range: NSRange,
        direction: SweepDirection,
        keepReviewRail: Bool,
        showingOriginal: Bool = false
    ) {
        self.attach(to: textView)
        self.activeRange = keepReviewRail ? range : nil
        self.isScanning = false
        self.isShowingReviewRail = keepReviewRail
        self.reviewShowingOriginal = showingOriginal
        
        guard let rect = self.clampedVisualRect(for: range, in: textView),
              let wash = self.washLayer,
              let scanMask = self.scanMaskLayer,
              let beam = self.scanBeamLayer,
              let rail = self.railLayer
        else { return }
        
        let tint: NSColor = showingOriginal ? .systemOrange : .controlAccentColor
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration: CFTimeInterval = (direction == .down) ? 0.48 : 0.32
        let restingWashOpacity: Float = keepReviewRail ? 1.0 : 0.0
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.removeAllAnimations()
        beam.removeAllAnimations()
        rail.removeAllAnimations()
        
        wash.frame = rect
        wash.cornerRadius = 6
        wash.backgroundColor = tint.withAlphaComponent(keepReviewRail ? 0.045 : 0.095).cgColor
        wash.opacity = restingWashOpacity
        
        rail.frame = CGRect(x: max(2, rect.minX - 6), y: rect.minY + 2, width: 2.5, height: max(12, rect.height - 4))
        rail.cornerRadius = 1.25
        rail.backgroundColor = tint.withAlphaComponent(showingOriginal ? 0.58 : 0.68).cgColor
        rail.opacity = keepReviewRail ? 1.0 : 0.0
        
        scanMask.frame = rect
        scanMask.cornerRadius = 6
        scanMask.masksToBounds = true
        scanMask.opacity = 1
        
        let beamH = max(34, min(68, rect.height * 0.45))
        beam.frame = CGRect(x: 0, y: -beamH, width: rect.width, height: beamH)
        beam.startPoint = CGPoint(x: 0.5, y: 0.0)
        beam.endPoint = CGPoint(x: 0.5, y: 1.0)
        beam.colors = [
            tint.withAlphaComponent(0.0).cgColor,
            tint.withAlphaComponent(0.18).cgColor,
            tint.withAlphaComponent(0.32).cgColor,
            tint.withAlphaComponent(0.18).cgColor,
            tint.withAlphaComponent(0.0).cgColor,
        ]
        beam.locations = [0.0, 0.25, 0.5, 0.75, 1.0]
        beam.opacity = 0
        CATransaction.commit()
        
        let easeOut = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
        
        // Soft highlight pulse settling cleanly into resting state
        let washFlash = CAKeyframeAnimation(keyPath: "opacity")
        washFlash.values = keepReviewRail ? [0.0, 1.0, 1.0] : [0.0, 1.0, 0.0]
        washFlash.keyTimes = [0.0, 0.22, 1.0]
        washFlash.duration = keepReviewRail ? 0.42 : 0.58
        washFlash.timingFunction = easeOut
        wash.add(washFlash, forKey: "washFlash")
        
        if !reduceMotion {
            let startY: CGFloat = (direction == .down) ? (-beamH * 0.5) : (rect.height + beamH * 0.5)
            let endY: CGFloat = (direction == .down) ? (rect.height + beamH * 0.5) : (-beamH * 0.5)
            
            let pos = CABasicAnimation(keyPath: "position.y")
            pos.fromValue = startY
            pos.toValue = endY
            
            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = [0.0, 1.0, 0.85, 0.0]
            alpha.keyTimes = [0.0, 0.16, 0.72, 1.0]
            
            let group = CAAnimationGroup()
            group.animations = [pos, alpha]
            group.duration = duration
            group.timingFunction = easeOut
            group.isRemovedOnCompletion = true
            beam.add(group, forKey: "completionSweep")
        }
    }
    
    
    /// Re-syncs the overlay frame when the editor scrolls during scan or review.
    func resyncLayout() {
        guard let textView = self.textView,
              let range = self.activeRange,
              self.isScanning || self.isShowingReviewRail,
              let rect = self.clampedVisualRect(for: range, in: textView)
        else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.washLayer?.frame = rect
        self.scanMaskLayer?.frame = rect
        self.railLayer?.frame = CGRect(x: max(2, rect.minX - 6), y: rect.minY + 2, width: 2.5, height: max(12, rect.height - 4))
        CATransaction.commit()
    }
    
    
    func clearAll() {
        self.isScanning = false
        self.isShowingReviewRail = false
        self.activeRange = nil
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.washLayer?.removeAllAnimations()
        self.beamLayerCleanup()
        self.railLayer?.removeAllAnimations()
        self.rootLayer?.removeFromSuperlayer()
        CATransaction.commit()
        
        self.rootLayer = nil
        self.washLayer = nil
        self.scanMaskLayer = nil
        self.scanBeamLayer = nil
        self.railLayer = nil
    }
    
    
    private func beamLayerCleanup() {
        self.scanBeamLayer?.removeAllAnimations()
        self.scanBeamLayer?.opacity = 0
    }
    
    
    private func ensureLayers() {
        guard let textView = self.textView, let hostLayer = textView.layer else { return }
        if let root = self.rootLayer, root.superlayer === hostLayer {
            return
        }
        self.clearAll()
        
        let root = CALayer()
        root.zPosition = 165
        hostLayer.addSublayer(root)
        self.rootLayer = root
        
        let wash = CALayer()
        wash.opacity = 0
        root.addSublayer(wash)
        self.washLayer = wash
        
        let mask = CALayer()
        mask.masksToBounds = true
        mask.opacity = 0
        root.addSublayer(mask)
        self.scanMaskLayer = mask
        
        let beam = CAGradientLayer()
        beam.opacity = 0
        mask.addSublayer(beam)
        self.scanBeamLayer = beam
        
        let rail = CALayer()
        rail.opacity = 0
        root.addSublayer(rail)
        self.railLayer = rail
    }
    
    
    private func clampedVisualRect(for range: NSRange, in textView: EditorTextView) -> CGRect? {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return nil }
        
        let nsLen = (textView.string as NSString).length
        guard nsLen > 0 else { return nil }
        
        let safeLoc = min(max(0, range.location), nsLen)
        let safeLen = min(max(0, range.length), nsLen - safeLoc)
        let clampedCharRange = NSRange(location: safeLoc, length: max(1, min(safeLen, nsLen - safeLoc)))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: clampedCharRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return nil }
        
        var bounding = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        bounding.origin.x += textView.textContainerOrigin.x
        bounding.origin.y += textView.textContainerOrigin.y
        
        // Expand cleanly across the text container width for neat full-width paragraph framing.
        let containerLeft = textView.textContainerOrigin.x + textContainer.lineFragmentPadding
        let containerWidth = max(120, textContainer.containerSize.width - textContainer.lineFragmentPadding * 2)
        let fullBlock = CGRect(
            x: containerLeft - 4,
            y: bounding.minY - 3,
            width: min(containerWidth + 8, max(bounding.width + 12, textView.visibleRect.width - 28)),
            height: max(22, bounding.height + 6)
        )
        
        let visible = textView.visibleRect
        guard !visible.isEmpty else { return fullBlock }
        let intersected = fullBlock.intersection(visible.insetBy(dx: 0, dy: -24))
        return intersected.isNull ? fullBlock : intersected
    }
}


// MARK: - Inline Session Controller (Bridges TextView, AI Streaming & Frosted Floating Bar)

@MainActor
final class TextRestructureSessionController {
    
    fileprivate enum BarPhase: Equatable {
        case loading(generatedChars: Int)
        case review(
            mode: TextRestructureMode,
            showingOriginal: Bool,
            summaryText: String,
            revisionIndex: Int,
            revisionCount: Int
        )
        case notice(message: String)
        case error(message: String)
    }
    
    private weak var textView: EditorTextView?
    private weak var hostContainerView: NSView?
    private var barHostView: NSHostingView<TextRestructureReviewBarView>?
    private let effectOverlay = EditorRestructureEffectOverlay()
    
    private var machine: TextRestructureReviewMachine?
    private var activeTask: Task<Void, Never>?
    private var noticeDismissTask: Task<Void, Never>?
    private var isApplyingProgrammaticEdit = false
    
    private var textChangeObserver: NSObjectProtocol?
    private var scrollObserver: NSObjectProtocol?
    
    var onFallbackToPanel: ((AIAction, String, String) -> Void)?
    
    
    /// Runs instant local format cleaning (`清洗规整`) with luminous sweep + regret-proof floating review bar.
    func runFormatClean(in textView: EditorTextView, hostView: NSView) {
        self.cancelInFlightTask()
        
        let nsText = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let isWholeDocument = (selectedRange.length == 0)
        let targetRange = isWholeDocument ? NSRange(location: 0, length: nsText.length) : selectedRange
        guard targetRange.length > 0 else {
            NSSound.beep()
            return
        }
        
        let original = nsText.substring(with: targetRange)
        let cleaned = Self.preserveTrailingNewline(
            AIDocumentTextCleaner.cleanStructuredPlainText(original),
            matching: original
        )
        
        guard cleaned != original else {
            self.bind(textView: textView, hostView: hostView)
            self.effectOverlay.playSweep(in: textView, range: targetRange, direction: .down, keepReviewRail: false)
            self.presentTransientNotice(AppLanguage.text("格式已规整", en: "Already Clean"))
            return
        }
        
        self.bind(textView: textView, hostView: hostView)
        
        let machine = TextRestructureReviewMachine(
            mode: .formatClean,
            originalText: original,
            transformedText: cleaned,
            originLocation: targetRange.location,
            isWholeDocument: isWholeDocument
        )
        self.machine = machine
        
        self.applyTextMutation(
            replacement: cleaned,
            range: targetRange,
            actionName: TextRestructureMode.formatClean.displayTitle,
            in: textView
        )
        self.effectOverlay.playSweep(
            in: textView,
            range: machine.activeRange,
            direction: .down,
            keepReviewRail: true,
            showingOriginal: false
        )
        self.refreshReviewBar()
    }
    
    
    /// Runs AI semantic restructure (`语义规整`) directly inline with live ambient scan shimmer + regret-proof review bar.
    func runSemanticRestructure(
        in textView: EditorTextView,
        hostView: NSView,
        reusingExistingMachine: Bool = false
    ) {
        self.cancelInFlightTask()
        
        let nsText = textView.string as NSString
        let targetRange: NSRange
        let sourceOriginal: String
        let isWholeDocument: Bool
        
        if reusingExistingMachine, let existing = self.machine {
            targetRange = existing.activeRange
            sourceOriginal = existing.untouchedOriginalText
            isWholeDocument = existing.isWholeDocument
        } else {
            let selectedRange = textView.selectedRange()
            isWholeDocument = (selectedRange.length == 0)
            targetRange = isWholeDocument ? NSRange(location: 0, length: nsText.length) : selectedRange
            guard targetRange.length > 0 else {
                NSSound.beep()
                return
            }
            sourceOriginal = nsText.substring(with: targetRange)
            self.machine = nil
        }
        
        guard !sourceOriginal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        
        let expectedCurrentBufferText: String = if targetRange.upperBound <= nsText.length {
            nsText.substring(with: targetRange)
        } else {
            ""
        }
        
        self.bind(textView: textView, hostView: hostView)
        self.effectOverlay.startAmbientScan(in: textView, range: targetRange)
        self.presentBar(phase: .loading(generatedChars: 0))
        
        self.activeTask = Task { @MainActor [weak self, weak textView] in
            do {
                let rawResult = try await AIService.shared.run(.semanticRestructure, on: sourceOriginal) { [weak self] partial in
                    guard let self, self.activeTask != nil else { return }
                    let count = partial.trimmingCharacters(in: .whitespacesAndNewlines).count
                    self.presentBar(phase: .loading(generatedChars: count))
                }
                try Task.checkCancellation()
                guard let self, let textView else { return }
                self.activeTask = nil
                
                let finalResult = Self.preserveTrailingNewline(
                    AIDocumentTextCleaner.cleanStructuredPlainText(rawResult),
                    matching: sourceOriginal
                )
                guard !finalResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.effectOverlay.clearAll()
                    self.presentBar(phase: .error(message: AppLanguage.text("未生成有效内容", en: "Empty result")))
                    return
                }
                
                // Guard: verify the user did not manually edit the target block while AI was streaming.
                let latestNS = textView.string as NSString
                let rangeUnchanged = targetRange.upperBound <= latestNS.length
                    && latestNS.substring(with: targetRange) == expectedCurrentBufferText
                
                guard rangeUnchanged, textView.isEditable else {
                    self.dismiss()
                    self.onFallbackToPanel?(.semanticRestructure, sourceOriginal, finalResult)
                    return
                }
                
                if var existing = self.machine {
                    let plan = existing.appendRevision(mode: .semanticRestructure, transformedText: finalResult)
                    self.machine = existing
                    self.applyTextMutation(
                        replacement: plan.replacement,
                        range: plan.replaceRange,
                        actionName: plan.actionName,
                        in: textView
                    )
                    self.effectOverlay.playSweep(
                        in: textView,
                        range: existing.activeRange,
                        direction: .down,
                        keepReviewRail: true,
                        showingOriginal: false
                    )
                } else {
                    let machine = TextRestructureReviewMachine(
                        mode: .semanticRestructure,
                        originalText: sourceOriginal,
                        transformedText: finalResult,
                        originLocation: targetRange.location,
                        isWholeDocument: isWholeDocument
                    )
                    self.machine = machine
                    self.applyTextMutation(
                        replacement: finalResult,
                        range: targetRange,
                        actionName: TextRestructureMode.semanticRestructure.displayTitle,
                        in: textView
                    )
                    self.effectOverlay.playSweep(
                        in: textView,
                        range: machine.activeRange,
                        direction: .down,
                        keepReviewRail: true,
                        showingOriginal: false
                    )
                }
                self.refreshReviewBar()
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.activeTask = nil
                self.effectOverlay.clearAll()
                let msg = Self.conciseErrorText(error)
                self.presentBar(phase: .error(message: msg))
            }
        }
    }
    
    
    func dismiss() {
        self.cancelInFlightTask()
        self.noticeDismissTask?.cancel()
        self.noticeDismissTask = nil
        self.machine = nil
        self.effectOverlay.clearAll()
        self.removeBarView()
        self.removeObservers()
    }
    
    
    // MARK: Review Bar Actions
    
    private func handleToggleCompare() {
        guard let textView = self.textView, var machine = self.machine else { return }
        let plan = machine.toggleCompare()
        self.machine = machine
        
        self.applyTextMutation(
            replacement: plan.replacement,
            range: plan.replaceRange,
            actionName: plan.actionName,
            in: textView
        )
        self.effectOverlay.playSweep(
            in: textView,
            range: machine.activeRange,
            direction: plan.isRevertingOrOriginal ? .up : .down,
            keepReviewRail: true,
            showingOriginal: machine.showingOriginal
        )
        self.refreshReviewBar()
    }
    
    
    private func handleStepRevision(_ delta: Int) {
        guard let textView = self.textView,
              var machine = self.machine,
              let plan = machine.stepRevision(delta: delta)
        else { return }
        self.machine = machine
        
        self.applyTextMutation(
            replacement: plan.replacement,
            range: plan.replaceRange,
            actionName: plan.actionName,
            in: textView
        )
        self.effectOverlay.playSweep(
            in: textView,
            range: machine.activeRange,
            direction: plan.isRevertingOrOriginal ? .up : .down,
            keepReviewRail: true,
            showingOriginal: false
        )
        self.refreshReviewBar()
    }
    
    
    private func handleUpgradeOrRetrySemantic() {
        guard let textView = self.textView, let hostView = self.hostContainerView else { return }
        guard AIService.shared.isConfigured(for: AIBotID(action: .semanticRestructure)) else {
            self.presentBar(phase: .error(message: AppLanguage.text("请先在设置中配置 AI 模型", en: "Configure AI in Settings")))
            return
        }
        self.runSemanticRestructure(
            in: textView,
            hostView: hostView,
            reusingExistingMachine: self.machine != nil
        )
    }
    
    
    private func handleKeepBoth() {
        guard let textView = self.textView, let machine = self.machine else {
            self.dismiss()
            return
        }
        let plan = machine.keepBothPlan()
        self.applyTextMutation(
            replacement: plan.replacement,
            range: plan.replaceRange,
            actionName: plan.actionName,
            in: textView
        )
        let newRange = NSRange(location: plan.replaceRange.location, length: (plan.replacement as NSString).length)
        self.machine = nil
        self.removeBarView()
        self.removeObservers()
        self.effectOverlay.playSweep(
            in: textView,
            range: newRange,
            direction: .down,
            keepReviewRail: false
        )
    }
    
    
    private func handleRevert() {
        guard let textView = self.textView, let machine = self.machine else {
            self.dismiss()
            return
        }
        let targetRange: NSRange
        if let plan = machine.revertPlan() {
            self.applyTextMutation(
                replacement: plan.replacement,
                range: plan.replaceRange,
                actionName: plan.actionName,
                in: textView
            )
            targetRange = NSRange(location: plan.replaceRange.location, length: (plan.replacement as NSString).length)
        } else {
            targetRange = machine.activeRange
        }
        self.machine = nil
        self.removeBarView()
        self.removeObservers()
        self.effectOverlay.playSweep(
            in: textView,
            range: targetRange,
            direction: .up,
            keepReviewRail: false,
            showingOriginal: true
        )
    }
    
    
    private func handleAccept() {
        guard let textView = self.textView, let machine = self.machine else {
            self.dismiss()
            return
        }
        if let plan = machine.acceptPlan() {
            self.applyTextMutation(
                replacement: plan.replacement,
                range: plan.replaceRange,
                actionName: plan.actionName,
                in: textView
            )
        }
        self.dismiss()
    }
    
    
    private func handleCancelLoading() {
        self.cancelInFlightTask()
        if self.machine != nil, let textView = self.textView, let machine = self.machine {
            self.effectOverlay.playSweep(
                in: textView,
                range: machine.activeRange,
                direction: .up,
                keepReviewRail: true,
                showingOriginal: machine.showingOriginal
            )
            self.refreshReviewBar()
        } else {
            self.dismiss()
        }
    }
    
    
    // MARK: Internals
    
    private func bind(textView: EditorTextView, hostView: NSView) {
        self.noticeDismissTask?.cancel()
        self.noticeDismissTask = nil
        if self.textView !== textView || self.hostContainerView !== hostView {
            self.removeObservers()
            self.removeBarView()
            self.textView = textView
            self.hostContainerView = hostView
            self.installObservers(for: textView)
        }
    }
    
    
    private func installObservers(for textView: EditorTextView) {
        self.textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isApplyingProgrammaticEdit else { return }
                // The user manually typed or invoked ⌘Z — gracefully step aside without fighting their edit.
                if self.activeTask == nil {
                    self.dismiss()
                }
            }
        }
        
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            self.scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.effectOverlay.resyncLayout()
                }
            }
        }
    }
    
    
    private func removeObservers() {
        if let obs = self.textChangeObserver {
            NotificationCenter.default.removeObserver(obs)
            self.textChangeObserver = nil
        }
        if let obs = self.scrollObserver {
            NotificationCenter.default.removeObserver(obs)
            self.scrollObserver = nil
        }
    }
    
    
    private func cancelInFlightTask() {
        self.activeTask?.cancel()
        self.activeTask = nil
    }
    
    
    private func applyTextMutation(
        replacement: String,
        range: NSRange,
        actionName: String,
        in textView: EditorTextView
    ) {
        let nsLen = (textView.string as NSString).length
        let clampedLoc = min(max(0, range.location), nsLen)
        let clampedLen = min(max(0, range.length), nsLen - clampedLoc)
        let safeRange = NSRange(location: clampedLoc, length: clampedLen)
        
        self.isApplyingProgrammaticEdit = true
        textView.insertText(replacement, replacementRange: safeRange)
        textView.undoManager?.setActionName(actionName)
        textView.window?.makeFirstResponder(textView)
        self.isApplyingProgrammaticEdit = false
    }
    
    
    private func refreshReviewBar() {
        guard let machine = self.machine else {
            self.removeBarView()
            return
        }
        let rev = machine.currentRevision
        self.presentBar(phase: .review(
            mode: rev.mode,
            showingOriginal: machine.showingOriginal,
            summaryText: rev.metrics.summaryText(for: rev.mode),
            revisionIndex: machine.selectedRevisionIndex,
            revisionCount: machine.revisions.count
        ))
    }
    
    
    private func presentTransientNotice(_ message: String) {
        self.presentBar(phase: .notice(message: message))
        self.noticeDismissTask?.cancel()
        self.noticeDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            guard let self, !Task.isCancelled else { return }
            self.dismiss()
        }
    }
    
    
    private func presentBar(phase: BarPhase) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let hostView = self.hostContainerView
        else { return }
        
        let rootView = TextRestructureReviewBarView(
            phase: phase,
            onToggleCompare: { [weak self] in self?.handleToggleCompare() },
            onStepRevision: { [weak self] delta in self?.handleStepRevision(delta) },
            onUpgradeOrRetry: { [weak self] in self?.handleUpgradeOrRetrySemantic() },
            onKeepBoth: { [weak self] in self?.handleKeepBoth() },
            onRevert: { [weak self] in self?.handleRevert() },
            onAccept: { [weak self] in self?.handleAccept() },
            onCancelLoading: { [weak self] in self?.handleCancelLoading() },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        
        if let existing = self.barHostView, existing.superview === hostView {
            existing.rootView = rootView
            return
        }
        
        self.removeBarView()
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.alphaValue = 0
        hostView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            hosting.bottomAnchor.constraint(equalTo: hostView.bottomAnchor, constant: -16),
            hosting.leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: 14),
            hosting.trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -14),
        ])
        self.barHostView = hosting
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.01 : 0.20
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            hosting.animator().alphaValue = 1
        }
    }
    
    
    private func removeBarView() {
        guard let bar = self.barHostView else { return }
        self.barHostView = nil
        bar.removeFromSuperview()
    }
    
    
    private static func preserveTrailingNewline(_ cleaned: String, matching original: String) -> String {
        if original.hasSuffix("\n"), !cleaned.isEmpty, !cleaned.hasSuffix("\n") {
            return cleaned + "\n"
        }
        return cleaned
    }
    
    
    private static func conciseErrorText(_ error: any Error) -> String {
        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return AppLanguage.text("语义规整失败", en: "Restructure failed")
        }
        return raw.count > 42 ? String(raw.prefix(42)) + "…" : raw
    }
}


// MARK: - Frosted Glass Floating Review Bar (Apple-Native Restraint)

private struct TextRestructureReviewBarView: View {
    
    let phase: TextRestructureSessionController.BarPhase
    let onToggleCompare: () -> Void
    let onStepRevision: (Int) -> Void
    let onUpgradeOrRetry: () -> Void
    let onKeepBoth: () -> Void
    let onRevert: () -> Void
    let onAccept: () -> Void
    let onCancelLoading: () -> Void
    let onDismiss: () -> Void
    
    
    var body: some View {
        HStack(spacing: 8) {
            switch self.phase {
                case .loading(let generatedChars):
                    self.loadingContent(generatedChars: generatedChars)
                case .review(let mode, let showingOriginal, let summaryText, let revIdx, let revCount):
                    self.reviewContent(
                        mode: mode,
                        showingOriginal: showingOriginal,
                        summaryText: summaryText,
                        revisionIndex: revIdx,
                        revisionCount: revCount
                    )
                case .notice(let message):
                    self.noticeContent(message: message)
                case .error(let message):
                    self.errorContent(message: message)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6.5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 14, y: 4)
    }
    
    
    @ViewBuilder
    private func loadingContent(generatedChars: Int) -> some View {
        ProgressView()
            .controlSize(.small)
            .scaleEffect(0.75)
            .frame(width: 14, height: 14)
        
        Text(AppLanguage.text("语义规整中", en: "Restructuring"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
        
        if generatedChars > 0 {
            Text("\(generatedChars) 字")
                .font(.system(size: 11.5, weight: .regular).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        
        self.divider
        
        RestructurePillButton(
            title: AppLanguage.text("取消", en: "Cancel"),
            symbol: "xmark",
            emphasis: .neutral,
            action: self.onCancelLoading
        )
    }
    
    
    @ViewBuilder
    private func reviewContent(
        mode: TextRestructureMode,
        showingOriginal: Bool,
        summaryText: String,
        revisionIndex: Int,
        revisionCount: Int
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: showingOriginal ? "clock.arrow.circlepath" : mode.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(showingOriginal ? Color.orange : Color.accentColor)
            
            Text(showingOriginal ? AppLanguage.text("对比原文", en: "Original") : mode.completedBadgeTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
            
            if !showingOriginal, !summaryText.isEmpty {
                Text(summaryText)
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        
        if revisionCount > 1 {
            self.divider
            HStack(spacing: 2) {
                Button {
                    self.onStepRevision(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(revisionIndex > 0 ? .primary : .quaternary)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(revisionIndex <= 0)
                
                Text("\(revisionIndex + 1)/\(revisionCount)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                
                Button {
                    self.onStepRevision(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(revisionIndex + 1 < revisionCount ? .primary : .quaternary)
                        .frame(width: 18, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(revisionIndex + 1 >= revisionCount)
            }
        }
        
        self.divider
        
        RestructurePillButton(
            title: showingOriginal
                ? AppLanguage.text("查看规整", en: "Restructured")
                : AppLanguage.text("对比原文", en: "Compare"),
            symbol: "arrow.left.arrow.right",
            emphasis: showingOriginal ? .tinted : .neutral,
            action: self.onToggleCompare
        )
        
        if mode == .formatClean {
            RestructurePillButton(
                title: AppLanguage.text("语义规整", en: "Semantic"),
                symbol: "doc.plaintext",
                emphasis: .neutral,
                action: self.onUpgradeOrRetry
            )
        } else {
            RestructurePillButton(
                title: AppLanguage.text("重写", en: "Retry"),
                symbol: "arrow.clockwise",
                emphasis: .neutral,
                action: self.onUpgradeOrRetry
            )
            
            RestructurePillButton(
                title: AppLanguage.text("保留两者", en: "Keep Both"),
                symbol: "rectangle.stack",
                emphasis: .neutral,
                action: self.onKeepBoth
            )
        }
        
        RestructurePillButton(
            title: AppLanguage.text("撤销还原", en: "Revert"),
            symbol: "arrow.uturn.backward",
            emphasis: .neutral,
            action: self.onRevert
        )
        
        RestructurePillButton(
            title: AppLanguage.text("保留", en: "Keep"),
            symbol: "checkmark",
            emphasis: .primary,
            action: self.onAccept
        )
    }
    
    
    @ViewBuilder
    private func noticeContent(message: String) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.accentColor)
        
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
    }
    
    
    @ViewBuilder
    private func errorContent(message: String) -> some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.orange)
        
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
        
        self.divider
        
        RestructurePillButton(
            title: AppLanguage.text("重试", en: "Retry"),
            symbol: "arrow.clockwise",
            emphasis: .neutral,
            action: self.onUpgradeOrRetry
        )
        
        RestructurePillButton(
            title: AppLanguage.text("关闭", en: "Close"),
            symbol: "xmark",
            emphasis: .neutral,
            action: self.onDismiss
        )
    }
    
    
    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 0.75, height: 14)
    }
}


private struct RestructurePillButton: View {
    
    enum Emphasis {
        case neutral
        case tinted
        case primary
    }
    
    let title: String
    let symbol: String
    let emphasis: Emphasis
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 4) {
                Image(systemName: self.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(self.title)
                    .font(.system(size: 11.5, weight: self.emphasis == .primary ? .semibold : .medium))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(self.foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(self.backgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(self.borderColor, lineWidth: 0.65)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            self.isHovered = hovering
        }
    }
    
    private var foregroundColor: Color {
        switch self.emphasis {
            case .primary: .white
            case .tinted: Color.orange
            case .neutral: .primary
        }
    }
    
    private var backgroundColor: Color {
        switch self.emphasis {
            case .primary:
                Color.accentColor.opacity(self.isHovered ? 0.90 : 1.0)
            case .tinted:
                Color.orange.opacity(self.isHovered ? 0.18 : 0.12)
            case .neutral:
                Color.primary.opacity(self.isHovered ? 0.10 : 0.05)
        }
    }
    
    private var borderColor: Color {
        switch self.emphasis {
            case .primary: .clear
            case .tinted: Color.orange.opacity(0.25)
            case .neutral: Color.primary.opacity(self.isHovered ? 0.14 : 0.06)
        }
    }
}
