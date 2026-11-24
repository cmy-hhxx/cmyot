//
//  Round18FeatureTests.swift
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
import Defaults
import Foundation
import LineEnding
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round18FeatureTests {
    
    // MARK: 1. Seamless Tab Inline Rename
    
    @Test func inlineTabRenameFieldIsSeamlessVerticallyCenteredAndDynamicallySized() throws {
        
        // Short title: stays compact (no abrupt 188pt jump), transparent field, exact font & alignment
        let shortDoc = Document()
        shortDoc.displayName = "待办"
        let shortTab = PaneTab(document: shortDoc)
        let state = PaneTabState()
        state.tabs = [shortTab]
        state.selectedTab = shortTab
        
        let strip = PaneTabStripNSView(frame: NSRect(x: 0, y: 0, width: 520, height: 24))
        strip.state = state
        strip.reloadTabs()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView?.addSubview(strip)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        
        strip.beginInlineRename(for: shortTab)
        window.layoutIfNeeded()
        
        let scrollView = try #require(strip.subviews.compactMap { $0 as? NSScrollView }.first)
        let itemView = try #require(scrollView.documentView?.subviews.compactMap { $0 as? PaneTabItemView }.first)
        let field = try #require(itemView.inlineTextFieldForTesting)
        
        #expect(field.drawsBackground == false)
        #expect(field.isBezeled == false)
        #expect(field.font == .systemFont(ofSize: 12, weight: .medium))
        #expect(field.frame.minX == itemView.titleLabelFrameForTesting.minX)
        #expect(field.cell is TabRenameTextFieldCell)
        #expect(itemView.layer?.borderWidth == 1.0)
        
        let initialRenameWidth = itemView.preferredWidth(minWidth: 80, maxWidth: 600)
        #expect(initialRenameWidth <= 140)
        
        // Typing a longer title dynamically expands preferred width
        field.stringValue = "这是一个正在逐渐变长的文档标题用于测试动态扩展"
        strip.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        let grownWidth = itemView.preferredWidth(minWidth: 80, maxWidth: 600)
        #expect(grownWidth > initialRenameWidth)
        
        itemView.exitRenameMode()
        #expect(itemView.inlineTextFieldForTesting == nil)
        
        // Long title: rename mode must never shrink below its pre-rename width
        let longDoc = Document()
        longDoc.displayName = "2026年第四季度产品架构优化与文档整理清单"
        let longTab = PaneTab(document: longDoc)
        let longItem = PaneTabItemView(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        longItem.configure(tab: longTab, isSelected: true, isRenaming: false)
        let preRenameWidth = longItem.preferredWidth(minWidth: 80, maxWidth: 600)
        _ = longItem.enterRenameMode(initialTitle: longTab.title, delegate: strip)
        let longRenameWidth = longItem.preferredWidth(minWidth: 80, maxWidth: 600)
        #expect(preRenameWidth > 188)
        #expect(longRenameWidth >= preRenameWidth)
    }
    
    
    // MARK: 2. Cross-Pane Transfer Trail Geometry & Wake Taper
    
    @Test func paneTransferTrailGeometryAndWakeTaper() {
        
        let sourceCenter = CGPoint(x: 80, y: 20)
        let targetCenter = CGPoint(x: 420, y: 20)
        
        // Tab-bar drop (near target tab center) originates from source tab center
        let tabBarStart = PaneTransferTrailEffect.computeFlightStart(
            sourceTabCenter: sourceCenter,
            dropPoint: CGPoint(x: 410, y: 24),
            targetTabCenter: targetCenter
        )
        #expect(tabBarStart == sourceCenter)
        
        // Extreme distance clamps cleanly along vector toward target
        let clampedStart = PaneTransferTrailEffect.computeFlightStart(
            sourceTabCenter: CGPoint(x: -400, y: 20),
            dropPoint: CGPoint(x: 420, y: 20),
            targetTabCenter: targetCenter,
            maxDistance: 460
        )
        let clampedDist = hypot(clampedStart.x - targetCenter.x, clampedStart.y - targetCenter.y)
        #expect(abs(clampedDist - 460) < 0.5)
        
        // Pane-body drop (far from target tab center) originates from drop point
        let bodyDrop = CGPoint(x: 380, y: 260)
        let bodyStart = PaneTransferTrailEffect.computeFlightStart(
            sourceTabCenter: sourceCenter,
            dropPoint: bodyDrop,
            targetTabCenter: targetCenter
        )
        #expect(bodyStart == bodyDrop)
        
        // Near-zero fallback ensures a visible swoop
        let shortStart = PaneTransferTrailEffect.computeFlightStart(
            sourceTabCenter: nil,
            dropPoint: targetCenter,
            targetTabCenter: targetCenter
        )
        #expect(hypot(shortStart.x - targetCenter.x, shortStart.y - targetCenter.y) >= 20)
        
        // Quadratic Bezier endpoints & upward arc
        let control = PaneTransferTrailEffect.quadraticBezierControlPoint(from: tabBarStart, to: targetCenter)
        let midY = (tabBarStart.y + targetCenter.y) * 0.5
        #expect(control.y <= midY)
        
        let p0 = PaneTransferTrailEffect.pointOnQuadraticBezier(from: tabBarStart, control: control, to: targetCenter, progress: 0)
        let p1 = PaneTransferTrailEffect.pointOnQuadraticBezier(from: tabBarStart, control: control, to: targetCenter, progress: 1)
        #expect(hypot(p0.x - tabBarStart.x, p0.y - tabBarStart.y) < 0.001)
        #expect(hypot(p1.x - targetCenter.x, p1.y - targetCenter.y) < 0.001)
        
        // 5-stage wake capsules taper monotonically in scale & alpha and stagger forward in delay
        var previous = PaneTransferTrailEffect.wakeCapsuleParameters(index: 0)
        for index in 1...4 {
            let current = PaneTransferTrailEffect.wakeCapsuleParameters(index: index)
            #expect(current.scale < previous.scale)
            #expect(current.alpha < previous.alpha)
            #expect(current.delay > previous.delay)
            previous = current
        }
        
        // Overlay never intercepts mouse events
        let overlay = PaneTransferTrailOverlayView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        #expect(overlay.hitTest(NSPoint(x: 100, y: 100)) == nil)
    }
    
    
    // MARK: 3. Vim Visual Mode Scrolling
    
    @Test func vimVisualModeScrollsViewportDownUpAndOnPageJumps() throws {
        
        let previousVimMode = UserDefaults.standard[.vimMode]
        let previousMode = VimState.shared.mode
        let previousActive = VimState.shared.visualActiveLocation
        let previousOwner = VimState.shared.visualOwnerID
        defer {
            UserDefaults.standard[.vimMode] = previousVimMode
            VimState.shared.mode = previousMode
            VimState.shared.visualActiveLocation = previousActive
            VimState.shared.visualOwnerID = previousOwner
        }
        
        UserDefaults.standard[.vimMode] = true
        VimState.shared.mode = .normal
        VimState.shared.visualActiveLocation = nil
        VimState.shared.visualOwnerID = nil
        
        let lines = (1...120).map { String(format: "Line %03d: vim visual mode scroll check", $0) }
        let content = lines.joined(separator: "\n")
        
        let (window, scrollView, textView) = try Self.makeScrollableEditor(content: content, viewportSize: NSSize(width: 480, height: 180))
        defer { window.orderOut(nil) }
        
        let engine = textView.vimEngine
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        
        // Enter `v` at line 1 and step down 25 lines
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "v", keyCode: 9, timestamp: 1.0)))
        #expect(VimState.shared.mode == .visual)
        
        for step in 0..<25 {
            let ts = 2.0 + Double(step) * 0.25
            #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: ts)))
        }
        
        #expect(scrollView.documentVisibleRect.origin.y > 0)
        let activeAfterJ = try #require(VimState.shared.visualActiveLocation)
        let rectAfterJ = try #require(textView.vimCursorRect(at: activeAfterJ))
        #expect(textView.visibleRect.contains(rectAfterJ))
        
        // `G` jumps to bottom and scrolls viewport
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "G", keyCode: 5, modifiers: [.shift], timestamp: 10.0)))
        let yAtBottom = scrollView.documentVisibleRect.origin.y
        #expect(yAtBottom > 400)
        let activeAtBottom = try #require(VimState.shared.visualActiveLocation)
        let rectAtBottom = try #require(textView.vimCursorRect(at: activeAtBottom))
        #expect(textView.visibleRect.contains(rectAtBottom))
        
        // `o` swaps active end back to top anchor and scrolls back near top
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "o", keyCode: 31, timestamp: 11.0)))
        #expect(scrollView.documentVisibleRect.origin.y < 30)
        let activeAfterO = try #require(VimState.shared.visualActiveLocation)
        let rectAfterO = try #require(textView.vimCursorRect(at: activeAfterO))
        #expect(textView.visibleRect.contains(rectAfterO))
        
        // Exit visual mode, jump to line 100, enter `V` and move upward 30 lines
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "\u{1b}", keyCode: 53, timestamp: 12.0)))
        #expect(VimState.shared.mode == .normal)
        
        let line100Offset = (content as NSString).range(of: "Line 100:").location
        textView.setSelectedRange(NSRange(location: line100Offset, length: 0))
        textView.scrollRangeToVisible(NSRange(location: line100Offset, length: 0))
        
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "V", keyCode: 9, modifiers: [.shift], timestamp: 13.0)))
        let yBeforeUp = scrollView.documentVisibleRect.origin.y
        
        for step in 0..<30 {
            let ts = 14.0 + Double(step) * 0.25
            #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "k", keyCode: 40, timestamp: ts)))
        }
        #expect(scrollView.documentVisibleRect.origin.y < yBeforeUp)
        let activeAfterK = try #require(VimState.shared.visualActiveLocation)
        let rectAfterK = try #require(textView.vimCursorRect(at: activeAfterK))
        #expect(textView.visibleRect.contains(rectAfterK))
        
        // ⌃D in `v` mode stays in visual mode, grows selection, and scrolls viewport
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "\u{1b}", keyCode: 53, timestamp: 25.0)))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "v", keyCode: 9, timestamp: 26.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "d", keyCode: 2, modifiers: [.control], timestamp: 27.0)))
        #expect(VimState.shared.mode == .visual)
        #expect(textView.selectedRange().length > 1)
        #expect(scrollView.documentVisibleRect.origin.y > 0)
        let activeAfterCtrlD = try #require(VimState.shared.visualActiveLocation)
        let rectAfterCtrlD = try #require(textView.vimCursorRect(at: activeAfterCtrlD))
        #expect(textView.visibleRect.contains(rectAfterCtrlD))
    }
    
    
    @Test func vimVisualUpwardAndDownwardCharacterwiseMovesKeepAnchorRowStationary() throws {
        let previousVimMode = UserDefaults.standard[.vimMode]
        let previousMode = VimState.shared.mode
        let previousActive = VimState.shared.visualActiveLocation
        let previousOwner = VimState.shared.visualOwnerID
        defer {
            UserDefaults.standard[.vimMode] = previousVimMode
            VimState.shared.mode = previousMode
            VimState.shared.visualActiveLocation = previousActive
            VimState.shared.visualOwnerID = previousOwner
        }
        
        UserDefaults.standard[.vimMode] = true
        VimState.shared.mode = .normal
        VimState.shared.visualActiveLocation = nil
        VimState.shared.visualOwnerID = nil
        
        let content = [
            "Line 01: short",
            "Line 02: medium length line here",
            "Line 03: very long line for horizontal span verification",
            "Line 04: anchor line where visual selection starts",
            "Line 05: trailing line below anchor",
        ].joined(separator: "\n")
        
        let (window, _, textView) = try Self.makeScrollableEditor(content: content, viewportSize: NSSize(width: 560, height: 240))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        
        let nsContent = content as NSString
        let line4Start = nsContent.range(of: "Line 04:").location + 9
        textView.setSelectedRange(NSRange(location: line4Start, length: 0))
        
        let engine = textView.vimEngine
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "v", keyCode: 9, timestamp: 1.0)))
        #expect(VimState.shared.mode == .visual)
        
        let initialBandY = textView.funEffects.activeVisualBandRects.last?.minY
        
        // Move UP 2 lines with `k` (`Line 04` -> `Line 03` -> `Line 02`)
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "k", keyCode: 40, timestamp: 1.3)))
        let bandsAfterFirstK = textView.funEffects.activeVisualBandRects
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "k", keyCode: 40, timestamp: 1.6)))
        let bandsAfterSecondK = textView.funEffects.activeVisualBandRects
        
        if textView.funEffects.ownsVimCursorDrawing, let initialBandY {
            #expect(bandsAfterFirstK.count == 2)
            #expect(bandsAfterSecondK.count == 3)
            // Bottom anchor row (Line 04) must remain locked to its exact vertical row without jumping up!
            #expect(abs((bandsAfterFirstK.last?.minY ?? -999) - initialBandY) < 0.5)
            #expect(abs((bandsAfterSecondK.last?.minY ?? -999) - initialBandY) < 0.5)
            // Adjacent multi-line bands must be vertically flush (zero gap between rows on Frame 0)
            #expect(abs(bandsAfterSecondK[1].minY - bandsAfterSecondK[0].maxY) <= 1.0)
            #expect(abs(bandsAfterSecondK[2].minY - bandsAfterSecondK[1].maxY) <= 1.0)
            // Native sharp selection background must stay suppressed during GPU visual overlay
            #expect(textView.selectedTextAttributes[.backgroundColor] as? NSColor == .clear)
        }
        
        // Move DOWN 1 line with `j` (`Line 02` -> `Line 03`) and exit cleanly with `Esc`
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 1.9)))
        if textView.funEffects.ownsVimCursorDrawing, let initialBandY {
            let bandsAfterJ = textView.funEffects.activeVisualBandRects
            #expect(bandsAfterJ.count == 2)
            #expect(abs((bandsAfterJ.last?.minY ?? -999) - initialBandY) < 0.5)
        }
        
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "\u{1b}", keyCode: 53, timestamp: 2.2)))
        #expect(VimState.shared.mode == .normal)
        #expect(textView.selectedRange().length == 0)
        #expect(textView.funEffects.activeVisualBandRects.isEmpty)
    }
    
    
    // MARK: 4. Vim Cursor Jump & Stale State Prevention
    
    @Test func vimCursorPreventsErraticJumpsFromStaleCountsMouseClicksAndRapidTaps() throws {
        
        let previousVimMode = UserDefaults.standard[.vimMode]
        let previousMode = VimState.shared.mode
        let previousActive = VimState.shared.visualActiveLocation
        let previousOwner = VimState.shared.visualOwnerID
        defer {
            UserDefaults.standard[.vimMode] = previousVimMode
            VimState.shared.mode = previousMode
            VimState.shared.visualActiveLocation = previousActive
            VimState.shared.visualOwnerID = previousOwner
        }
        
        UserDefaults.standard[.vimMode] = true
        VimState.shared.mode = .normal
        VimState.shared.visualActiveLocation = nil
        VimState.shared.visualOwnerID = nil
        
        // 1. Discrete manual taps never accelerate regardless of streak/elapsed
        #expect(VimEngine.acceleratedRepeatStep(for: .lineDown, streak: 15, elapsed: 2.0, fromKeyRepeat: false) == 1)
        #expect(VimEngine.acceleratedRepeatStep(for: .wordForward, streak: 20, elapsed: 2.0, fromKeyRepeat: false) == 1)
        
        let lines = (1...80).map { String(format: "L%02d alpha beta", $0) }
        let content = lines.joined(separator: "\n")
        let (window, _, textView) = try Self.makeScrollableEditor(content: content, viewportSize: NSSize(width: 480, height: 220))
        defer { window.orderOut(nil) }
        
        let engine = textView.vimEngine
        let nsContent = content as NSString
        func lineNumber(at offset: Int) -> Int {
            let prefix = nsContent.substring(to: min(max(0, offset), nsContent.length))
            return prefix.components(separatedBy: "\n").count
        }
        func offsetOfLine(_ oneBased: Int) -> Int {
            let prefix = String(format: "L%02d", oneBased)
            return nsContent.range(of: prefix).location
        }
        
        // 2. Rapid discrete `j` taps (0.05s apart, isARepeat: false) move strictly 1 line per tap
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        for step in 0..<10 {
            #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 1.0 + Double(step) * 0.05)))
        }
        #expect(lineNumber(at: textView.selectedRange().location) == 11)
        
        // 3. Mouse interaction clears stray count digits
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "2", keyCode: 19, timestamp: 5.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "5", keyCode: 23, timestamp: 5.05)))
        engine.handleExternalMouseInteraction()
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 5.2)))
        #expect(lineNumber(at: textView.selectedRange().location) == 2)
        
        // 4. Focus loss clears stray count digits
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "2", keyCode: 19, timestamp: 6.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "5", keyCode: 23, timestamp: 6.05)))
        engine.handleFocusLost()
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 6.2)))
        #expect(lineNumber(at: textView.selectedRange().location) == 2)
        
        // 5. Native arrow key and Ctrl-D clear stray count digits
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "2", keyCode: 19, timestamp: 7.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "5", keyCode: 23, timestamp: 7.05)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "", keyCode: 125, timestamp: 7.1)) == false)
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 7.2)))
        #expect(lineNumber(at: textView.selectedRange().location) == 2)
        
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "2", keyCode: 19, timestamp: 8.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "5", keyCode: 23, timestamp: 8.05)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "d", keyCode: 2, modifiers: [.control], timestamp: 8.1)))
        let lineAfterCtrlD = lineNumber(at: textView.selectedRange().location)
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 8.2)))
        #expect(lineNumber(at: textView.selectedRange().location) == lineAfterCtrlD + 1)
        
        // 6. Stale count expires after 3.0s while fresh count within 3.0s works as expected
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "5", keyCode: 23, timestamp: 10.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "0", keyCode: 29, timestamp: 10.05)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 14.0)))
        #expect(lineNumber(at: textView.selectedRange().location) == 2)
        
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "5", keyCode: 23, timestamp: 20.0)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "0", keyCode: 29, timestamp: 20.05)))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 21.0)))
        #expect(lineNumber(at: textView.selectedRange().location) == 51)
        
        // 7. Visual mode at line 50 + mouse click to line 2 + handleExternalMouseInteraction does not teleport back to 51
        textView.setSelectedRange(NSRange(location: offsetOfLine(50), length: 0))
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "v", keyCode: 9, timestamp: 25.0)))
        #expect(VimState.shared.mode == .visual)
        engine.handleExternalMouseInteraction()
        textView.setSelectedRange(NSRange(location: offsetOfLine(2), length: 0))
        #expect(VimState.shared.mode == .normal)
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 25.2)))
        #expect(lineNumber(at: textView.selectedRange().location) == 3)
        
        // 8. Foreign visualOwnerID exits visual cleanly on `j` instead of using foreign offset
        let otherTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        textView.setSelectedRange(NSRange(location: offsetOfLine(1), length: 0))
        VimState.shared.mode = .visual
        VimState.shared.visualOwnerID = ObjectIdentifier(otherTextView)
        VimState.shared.visualActiveLocation = offsetOfLine(40)
        #expect(engine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38, timestamp: 30.0)))
        #expect(VimState.shared.mode == .normal)
        #expect(lineNumber(at: textView.selectedRange().location) == 2)
    }
    
    
    // MARK: Helpers
    
    private static func makeScrollableEditor(
        content: String,
        viewportSize: NSSize
    ) throws -> (window: NSWindow, scrollView: NSScrollView, textView: EditorTextView) {
        
        let storage = NSTextStorage(string: content)
        let scanner = LineEndingScanner(textStorage: storage, lineEnding: .lf)
        let textView = EditorTextView(textStorage: storage, lineEndingScanner: scanner)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.frame = NSRect(origin: .zero, size: viewportSize)
        textView.textContainer?.containerSize = NSSize(width: viewportSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: viewportSize))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: viewportSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.contentView = scrollView
        window.orderFront(nil)
        window.makeFirstResponder(textView)
        
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.sizeToFit()
        window.layoutIfNeeded()
        textView.scroll(.zero)
        
        return (window, scrollView, textView)
    }
    
    
    private static func makeKeyEvent(
        char: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false,
        timestamp: TimeInterval
    ) throws -> NSEvent {
        
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: isRepeat,
            keyCode: keyCode
        ))
    }
}
