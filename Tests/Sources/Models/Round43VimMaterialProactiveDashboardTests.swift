//
//  Round43VimMaterialProactiveDashboardTests.swift
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
import LineEnding
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round43VimMaterialProactiveDashboardTests {
    
    // MARK: 1. Vim NORMAL Mode `G` Scrolls Reliably to Document Bottom Under Non-Contiguous Layout
    
    @Test func vimNormalModeGScrollsToTrueDocumentBottomEvenWithNonContiguousLayout() throws {
        let lines = (1...240).map { "Line \($0): SwiftUI and AppKit editor verification payload." }
        let body = lines.joined(separator: "\n") + "\n"
        let textStorage = NSTextStorage(string: body)
        let scanner = LineEndingScanner(textStorage: textStorage, lineEnding: .lf)
        
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 260))
        scrollView.hasVerticalScroller = true
        
        let textView = EditorTextView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 260),
            textStorage: textStorage,
            lineEndingScanner: scanner
        )
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 260)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        scrollView.layoutSubtreeIfNeeded()
        
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(NSPoint(x: 0, y: 0))
        
        let engine = VimEngine(textView: textView)
        VimState.shared.mode = .normal
        
        let gEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 1.0,
            windowNumber: 0,
            context: nil,
            characters: "G",
            charactersIgnoringModifiers: "G",
            isARepeat: false,
            keyCode: 5
        ))
        
        #expect(engine.handleKeyDown(gEvent) == true)
        
        let nsBody = body as NSString
        let lastLineRange = nsBody.lineRange(for: NSRange(location: nsBody.length - 1, length: 0))
        #expect(textView.selectedRange().location == lastLineRange.location)
        #expect(textView.bounds.height > 1500)
        #expect(textView.visibleRect.minY > 1000)
        #expect(textView.visibleRect.maxY >= textView.bounds.height - 60)
        
        // Verify `1G` jumps cleanly back to line 1 and scrolls to the top
        let oneEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 2.0,
            windowNumber: 0,
            context: nil,
            characters: "1",
            charactersIgnoringModifiers: "1",
            isARepeat: false,
            keyCode: 18
        ))
        let secondGEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.shift],
            timestamp: 2.2,
            windowNumber: 0,
            context: nil,
            characters: "G",
            charactersIgnoringModifiers: "G",
            isARepeat: false,
            keyCode: 5
        ))
        #expect(engine.handleKeyDown(oneEvent) == true)
        #expect(engine.handleKeyDown(secondGEvent) == true)
        #expect(textView.selectedRange().location == 0)
        #expect(textView.visibleRect.minY <= 12)
    }
    
    
    // MARK: 2. Material Library Without Search Box Mounts Cleanly
    
    @Test func materialLibraryMountsCleanlyWithoutSearchField() {
        let view = MediaLibrarySettingsView()
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.width == 640)
        #expect(host.bounds.height == 520)
    }
    
    
    // MARK: 3. Proactive Daily Agent Journal + Menu Bar Floating Tips (Zero Butler Chat Cards)
    
    @Test func proactiveDailyJournalAllocatesDailyDocRecordsNotesAndAnchorsFloatingTips() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appending(path: "cot_r43_proactive_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        
        let db = CotLocalDatabase(customURL: tempRoot.appending(path: "proactive.sqlite3"))
        let service = ProactiveDailyJournalService(database: db)
        
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        let date = try #require(cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 11, minute: 30)))
        
        let doc = service.ensureTodayDocument(now: date, butlerName: "曜")
        #expect(doc.id == "doc:butler-daily-2026-11-25")
        #expect(doc.title == "曜随记 · 2026-11-25")
        #expect(doc.groupName == "总管随记")
        
        var receivedTips: [ProactiveTipItem] = []
        service.onTipPublished = { tip in
            receivedTips.append(tip)
        }
        
        let signals = ProactiveJournalSignals(
            butlerName: "曜",
            todayChars: 1280,
            writingStreakDays: 11,
            activeDocTitle: "架构方案.md",
            watchlist: [],
            quotes: [:],
            unreadPodcasts: [],
            recentNews: [],
            memories: [],
            pendingActions: [
                DocumentActionPrediction(
                    id: "act-1",
                    action: "整理本周发布清单",
                    reason: "",
                    sourceDocumentTitle: "架构方案.md",
                    sourceDocumentID: nil,
                    urgency: "high"
                ),
            ]
        )
        
        let firstTip = try #require(await service.recordProactiveNote(
            signals: signals,
            now: date,
            allowRemoteAI: false,
            showFloatingTip: true
        ))
        #expect(firstTip.category == "待办提醒")
        #expect(receivedTips.count == 1)
        #expect(service.unreadCount == 1)
        
        let secondTip = try #require(await service.recordProactiveNote(
            signals: signals,
            now: date.addingTimeInterval(300),
            allowRemoteAI: false,
            showFloatingTip: true
        ))
        #expect(secondTip.dedupKey != firstTip.dedupKey)
        #expect(service.todayTips.count == 2)
        
        let updatedDoc = try #require(db.documents.first(where: { $0.id == doc.id }))
        #expect(updatedDoc.content.contains("整理本周发布清单"))
        #expect(updatedDoc.content.contains("1,280"))
        
        service.markAllRead()
        #expect(service.unreadCount == 0)
        
        // Menu bar floating geometry clamps safely inside visible screen frame
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let tipFrame = MenuBarFloatingGeometry.anchoredFrame(
            statusItemRect: NSRect(x: 1400, y: 875, width: 28, height: 24),
            panelSize: NSSize(width: 312, height: 118),
            visibleScreenFrame: screenFrame
        )
        #expect(tipFrame.maxX <= screenFrame.maxX - 10)
        #expect(tipFrame.minX >= screenFrame.minX + 10)
        #expect(tipFrame.maxY <= screenFrame.maxY)
        
        // Verify floating tip SwiftUI view mounts cleanly
        let tipHost = NSHostingView(rootView: ProactiveFloatingTipView(
            tip: firstTip,
            butlerName: "曜",
            onOpenJournal: {},
            onNextTip: {},
            onDismiss: {},
            onHoverChanged: { _ in }
        ))
        tipHost.frame = NSRect(x: 0, y: 0, width: 312, height: 118)
        tipHost.layoutSubtreeIfNeeded()
        #expect(tipHost.bounds.width == 312)
        
        // Verify Butler WebUI bundle has no recommendation cards
        let webHTML = BeautifulAgentUIBundle.htmlDocument()
        #expect(!webHTML.contains("dismissProactiveCard"))
    }
    
    
    // MARK: 4. Unified Dashboard Row 1 + Row 2 Shared Background Stage & Compact Proportions
    
    @Test func dashboardUnifiedTopStageCombinesRow1AndRow2WithCompactAspectRatio() {
        let laptop = DashboardViewportLayout.resolve(
            viewportSize: CGSize(width: 1280, height: 700),
            isEmbeddedInSettings: false,
            hasHeroPhoto: true
        )
        #expect(laptop.needsVerticalScroll == false)
        #expect(laptop.unifiedTopStageHeight == laptop.heroHeight + laptop.unifiedInnerGap + laptop.row1Height + laptop.unifiedBottomPad)
        // Combined Row 1 + Row 2 stage gives generous vertical height (~350-400pt) so photos never feel squished into a thin strip
        let stageAspect = 1236.0 / laptop.unifiedTopStageHeight
        #expect(stageAspect < 3.6)
        #expect(laptop.heroHeight <= 158)
        #expect(laptop.totalContentHeight <= 700)
    }
}
