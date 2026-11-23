//
//  Round33FeatureTests.swift
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
import Foundation
import Shortcut
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round33FeatureTests {
    
    // MARK: 1. KeyBindingModel Single-Click Recorder State Machine
    
    @Test func keyBindingModelSingleClickRecordingCancelAndClearLifecycle() throws {
        let model = KeyBindingModel()
        let initialShortcut = Shortcut(keySpecChars: "@k")
        let item = KeyBindingItem(
            action: NSSelectorFromString("dummyTestAction:"),
            tag: 0,
            shortcut: initialShortcut,
            defaultShortcut: initialShortcut
        )
        defer { model.stopRecording() }
        
        // Single-click toggle enters and exits recording cleanly
        #expect(!model.isRecording(item))
        model.toggleRecording(item)
        #expect(model.isRecording(item))
        #expect(model.recordingItemID == ObjectIdentifier(item))
        
        model.toggleRecording(item)
        #expect(!model.isRecording(item))
        #expect(model.recordingItemID == nil)
        
        // Esc cancels recording without altering shortcut
        model.startRecording(item)
        let escEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        ))
        #expect(model.handleRecordedKeyEvent(escEvent) == true)
        #expect(!model.isRecording(item))
        #expect(item.shortcut == initialShortcut)
        
        // Backspace clears shortcut and exits recording cleanly
        model.startRecording(item)
        let deleteEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{7F}",
            charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false,
            keyCode: 51
        ))
        #expect(model.handleRecordedKeyEvent(deleteEvent) == true)
        #expect(!model.isRecording(item))
        #expect(item.shortcut == nil)
    }
    
    
    // MARK: 2. Star-Map Document Center Mounts & Lays Out Cleanly
    
    @Test func starMapDocumentCenterMountsAndComputesCleanConstellation() throws {
        let state = DocumentCenterState()
        let view = DocumentCenterView(
            state: state,
            onOpenDocument: { _, _ in },
            onCreateNewDocument: { },
            onDismiss: { }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
        
        // Verify StarMapLayoutEngine keeps cluster & leaf nodes well-separated
        let layout = StarMapLayoutEngine.compute(
            clusterIDs: ["g1", "g2", "g3"],
            leafCountsByCluster: ["g1": 3, "g2": 2, "g3": 1],
            collapsedClusterIDs: [],
            leafIDsByCluster: ["g1": ["d1", "d2", "d3"], "g2": ["d4", "d5"], "g3": ["d6"]]
        )
        #expect(layout.clusters.count == 3)
        #expect(layout.leaves.count == 6)
        #expect(layout.bounds.width > 360)
        #expect(layout.bounds.height > 280)
    }
    
    
    // MARK: 3. Star-Map Weekly Report Center Mounts & Lays Out Cleanly
    
    @Test func starMapWeeklyReportCenterMountsCleanly() throws {
        let state = WeeklyReportCenterState()
        let view = WeeklyReportCenterView(
            state: state,
            onOpenReport: { _ in },
            onDismiss: { }
        )
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 720))
        
        let contentView = try #require(window.contentView)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        contentView.layoutSubtreeIfNeeded()
        
        #expect(abs(contentView.bounds.width - 1120) <= 2)
        #expect(abs(contentView.bounds.height - 720) <= 2)
    }
}
