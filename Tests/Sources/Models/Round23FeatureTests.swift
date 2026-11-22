//
//  Round23FeatureTests.swift
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
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round23FeatureTests {
    
    // MARK: 1. Dedicated Vim Setting Defaults to Off & Toggles Live
    
    @Test func vimModeDefaultsToOffAndToggleResetsModalState() throws {
        
        let previousVimMode = UserDefaults.standard[.vimMode]
        let previousMode = VimState.shared.mode
        let previousOwner = VimState.shared.visualOwnerID
        let previousActive = VimState.shared.visualActiveLocation
        let previousCommandLine = VimState.shared.commandLine
        defer {
            UserDefaults.standard[.vimMode] = previousVimMode
            VimState.shared.mode = previousMode
            VimState.shared.visualOwnerID = previousOwner
            VimState.shared.visualActiveLocation = previousActive
            VimState.shared.commandLine = previousCommandLine
        }
        
        #expect((DefaultSettings.defaults[.vimMode] as? Bool) == false)
        
        let doc = Document()
        doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: doc.textStorage.length), with: "abc")
        let wc = DocumentWindowController(document: doc)
        wc.showWindow(nil)
        defer { wc.close() }
        
        let textView = try #require(wc.documentViewController?.focusedTextView)
        textView.selectedRange = NSRange(location: 0, length: 0)
        
        UserDefaults.standard[.vimMode] = true
        VimState.shared.mode = .visual
        VimState.shared.visualOwnerID = ObjectIdentifier(textView)
        VimState.shared.commandLine = "/"
        textView.applyVimModeSetting(true)
        
        // Switching Vim OFF clears leftover visual/command state and stops intercepting keys
        UserDefaults.standard[.vimMode] = false
        textView.applyVimModeSetting(false)
        #expect(VimState.shared.mode == .normal)
        #expect(VimState.shared.visualOwnerID == nil)
        #expect(VimState.shared.commandLine == nil)
        #expect(textView.funEffects.ownsVimCursorDrawing == false)
        
        let plainKey = try Self.makeKeyEvent(char: "x", keyCode: 7)
        textView.keyDown(with: plainKey)
        #expect(textView.string == "xabc")
    }
    
    
    // MARK: 2. Hidden Document Title & No INSERT Window Subtitle
    
    @Test func documentWindowHidesTitleAndNeverShowsInsertSubtitle() async throws {
        
        let previousVimMode = UserDefaults.standard[.vimMode]
        let previousMode = VimState.shared.mode
        defer {
            UserDefaults.standard[.vimMode] = previousVimMode
            VimState.shared.mode = previousMode
        }
        
        let doc = Document()
        doc.displayName = "工作待办"
        doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: doc.textStorage.length), with: "hello\nworld")
        
        let wc = DocumentWindowController(document: doc)
        wc.showWindow(nil)
        defer { wc.close() }
        try await Task.sleep(for: .milliseconds(80))
        
        let window = try #require(wc.window)
        let textView = try #require(wc.documentViewController?.focusedTextView)
        
        #expect(window.titleVisibility == .hidden)
        #expect(window.subtitle.isEmpty)
        
        // Switching Vim into Insert mode and back to Normal mode must never populate window.subtitle
        UserDefaults.standard[.vimMode] = true
        VimState.shared.mode = .normal
        textView.selectedRange = NSRange(location: 0, length: 0)
        
        let insertKey = try Self.makeKeyEvent(char: "i", keyCode: 34)
        #expect(textView.vimEngine.handleKeyDown(insertKey) == true)
        #expect(VimState.shared.mode == .insert)
        #expect(window.titleVisibility == .hidden)
        #expect(window.subtitle.isEmpty)
        
        let escKey = try Self.makeKeyEvent(char: "\u{1B}", keyCode: 53)
        _ = textView.vimEngine.handleKeyDown(escKey)
        #expect(window.titleVisibility == .hidden)
        #expect(window.subtitle.isEmpty)
    }
    
    
    // MARK: 3. Presentation Read-Only Lock Mode
    
    @Test func presentationLockBlocksTypingPasteAndMutatingVimWhileAllowingNavigationAndYank() async throws {
        
        let previousVimMode = UserDefaults.standard[.vimMode]
        let previousMode = VimState.shared.mode
        defer {
            UserDefaults.standard[.vimMode] = previousVimMode
            VimState.shared.mode = previousMode
        }
        
        let doc = Document()
        doc.textStorage.replaceCharacters(in: NSRange(location: 0, length: doc.textStorage.length), with: "alpha\nbeta\ngamma")
        let wc = DocumentWindowController(document: doc)
        wc.showWindow(nil)
        defer { wc.close() }
        try await Task.sleep(for: .milliseconds(80))
        
        let docVC = try #require(wc.documentViewController)
        let textView = try #require(docVC.focusedTextView)
        textView.selectedRange = NSRange(location: 0, length: 0)
        
        // Lock the document
        docVC.toggleEditable(nil)
        try await Task.sleep(for: .milliseconds(50))
        
        #expect(doc.isEditable == false)
        #expect(textView.isEditable == false)
        #expect(textView.shouldDrawInsertionPoint == false)
        
        // Paste must be blocked in locked presentation mode
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("INJECTED", forType: .string)
        textView.paste(nil)
        #expect(textView.string == "alpha\nbeta\ngamma")
        
        // Mutating Vim commands (i / x / d) must be blocked, while j/v/y remain usable
        UserDefaults.standard[.vimMode] = true
        VimState.shared.mode = .normal
        
        #expect(textView.vimEngine.handleKeyDown(try Self.makeKeyEvent(char: "i", keyCode: 34)) == true)
        #expect(VimState.shared.mode == .normal)
        
        #expect(textView.vimEngine.handleKeyDown(try Self.makeKeyEvent(char: "x", keyCode: 7)) == true)
        #expect(textView.string == "alpha\nbeta\ngamma")
        
        #expect(textView.vimEngine.handleKeyDown(try Self.makeKeyEvent(char: "d", keyCode: 2)) == true)
        #expect(textView.string == "alpha\nbeta\ngamma")
        
        // Navigation (`j`) moves cursor to line 2 ("beta")
        _ = textView.vimEngine.handleKeyDown(try Self.makeKeyEvent(char: "j", keyCode: 38))
        #expect(textView.selectedRange().location >= 6)
        
        // Visual mode + Yank (`v` -> `y`) copies selected text without altering content
        _ = textView.vimEngine.handleKeyDown(try Self.makeKeyEvent(char: "v", keyCode: 9))
        #expect(VimState.shared.mode == .visual)
        _ = textView.vimEngine.handleKeyDown(try Self.makeKeyEvent(char: "y", keyCode: 16))
        #expect(VimState.shared.mode == .normal)
        #expect(NSPasteboard.general.string(forType: .string) == "b")
        #expect(textView.string == "alpha\nbeta\ngamma")
        
        // Unlock restores editable state
        docVC.toggleEditable(nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(doc.isEditable == true)
        #expect(textView.isEditable == true)
    }
    
    
    // MARK: 4. Inline Image Block Line Insertion & Clean Caret Placement
    
    @Test func insertInlineImageTokenCleanlyIsolatesBlockLineAndPlacesCaretBelow() {
        
        let doc = Document()
        let textView = EditorTextView(textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        textView.string = "hello world"
        textView.selectedRange = NSRange(location: 5, length: 0)
        
        textView.insertInlineImageTokenCleanly("[[COTIMG:test1234]]")
        
        #expect(textView.string == "hello\n[[COTIMG:test1234]]\n world")
        let expectedCaret = ("hello\n[[COTIMG:test1234]]\n" as NSString).length
        #expect(textView.selectedRange() == NSRange(location: expectedCaret, length: 0))
    }
    
    
    // MARK: 5. Stacked Metadata Underdamped Spring & Toolbar Cluster Geometry
    
    @Test func stackedMetadataSpringOvershootsReversesMidFlightAndExpandsCluster() {
        
        var spring = StackedMetadataSpring(position: 0, velocity: 0, target: 1)
        var peakPos = 0.0
        for _ in 0..<24 {
            _ = spring.step(dt: 1.0 / 60.0)
            peakPos = max(peakPos, spring.position)
        }
        // Underdamped spring (m=1, k=175, c=20) peaks above 1.01 before settling
        #expect(peakPos > 1.01)
        
        // Reverse target mid-flight and confirm continuous velocity settlement back to 0
        spring.target = 0
        let velocityBeforeFlip = spring.velocity
        _ = spring.step(dt: 1.0 / 60.0)
        #expect(spring.velocity != velocityBeforeFlip)
        
        for _ in 0..<180 {
            _ = spring.step(dt: 1.0 / 60.0)
        }
        #expect(abs(spring.position) < 0.001)
        
        let sampleImage = NSImage(systemSymbolName: "star", accessibilityDescription: nil) ?? NSImage()
        let items = [
            StackedToolbarCapsuleItem(
                id: "one",
                title: { _ in "看板" },
                tooltip: { _ in "数据看板" },
                image: { _ in sampleImage }
            ),
            StackedToolbarCapsuleItem(
                id: "two",
                title: { _ in "周报" },
                tooltip: { _ in "周报中心" },
                image: { _ in sampleImage }
            ),
            StackedToolbarCapsuleItem(
                id: "three",
                title: { _ in "文档" },
                tooltip: { _ in "文档中心" },
                image: { _ in sampleImage }
            ),
        ]
        
        let cluster = StackedToolbarClusterView(items: items)
        #expect(cluster.collapsedWidth < cluster.expandedWidth)
        let initialWidth = cluster.currentClusterWidth
        cluster.setExpanded(true, animated: false)
        #expect(cluster.currentProgress == 1.0)
        #expect(cluster.currentClusterWidth > initialWidth)
        #expect(abs(cluster.currentClusterWidth - cluster.expandedWidth) <= 1.0)
    }
    
    
    // MARK: 6. Glass Folder Procedural Textures & Weekly Report Refresh Signal
    
    @Test func glassFolderTexturesRenderAndWeeklyReportsNotificationFiresOnInPlaceUpdate() async throws {
        
        for theme in GlassFolderTheme.allCases {
            let image = GlassFolderTextureGenerator.textureImage(for: theme)
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_r23_weekly_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let db = CotLocalDatabase(customURL: tempURL)
        db.saveWeeklyReport(
            id: "202611/20261116-1122",
            periodLabel: "20261116-1122",
            yearMonth: "202611",
            title: "周报",
            content: "初版内容"
        )
        #expect(db.weeklyReports.count == 1)
        
        var didReceiveChange = false
        let token = NotificationCenter.default.addObserver(
            forName: CotLocalDatabase.weeklyReportsDidChangeNotification,
            object: db,
            queue: .main
        ) { _ in
            didReceiveChange = true
        }
        defer { NotificationCenter.default.removeObserver(token) }
        
        // Updating existing row in place keeps count == 1 and fires weeklyReportsDidChangeNotification
        db.saveWeeklyReport(
            id: "202611/20261116-1122",
            periodLabel: "20261116-1122",
            yearMonth: "202611",
            title: "周报",
            content: "修订后内容"
        )
        try await Task.sleep(for: .milliseconds(30))
        
        #expect(db.weeklyReports.count == 1)
        #expect(db.weeklyReports.first?.content == "修订后内容")
        #expect(didReceiveChange == true)
    }
    
    
    private static func makeKeyEvent(
        char: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: char,
            charactersIgnoringModifiers: char,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
