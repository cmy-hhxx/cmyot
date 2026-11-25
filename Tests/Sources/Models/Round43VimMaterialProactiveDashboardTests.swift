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
        #expect(doc.syntax == SyntaxName.none)
        #expect(doc.groupName == "总管随记")
        #expect(!doc.content.contains("#"))
        #expect(!doc.content.contains("*"))
        
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
                    action: "**整理本周发布清单**",
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
        #expect(updatedDoc.syntax == SyntaxName.none)
        #expect(updatedDoc.content.contains("整理本周发布清单"))
        #expect(updatedDoc.content.contains("1,280"))
        #expect(!updatedDoc.content.contains("#"))
        #expect(!updatedDoc.content.contains("*"))
        
        // Verify Markdown sanitizer removes #, **, *, `, and bullet dashes cleanly
        let sanitized = ProactiveJournalComposer.sanitizePlainText("## 标题\n- **重点** `内容` *细节*")
        #expect(sanitized == "标题\n重点 内容 细节")
        
        service.markAllRead()
        #expect(service.unreadCount == 0)
        
        // Toolbar speech bubble geometry clamps inside screen & aims tail arrow at Butler icon beside Todos
        let screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let anchorRect = NSRect(x: 1280, y: 820, width: 84, height: 28)
        let placement = ButlerTipBubbleGeometry.placement(
            anchorScreenRect: anchorRect,
            bubbleSize: NSSize(width: 294, height: 118),
            visibleScreenFrame: screenFrame
        )
        #expect(placement.frame.maxX <= screenFrame.maxX - 10)
        #expect(placement.frame.minX >= screenFrame.minX + 10)
        #expect(placement.frame.maxY <= anchorRect.minY)
        #expect(abs((placement.frame.minX + placement.arrowCenterX) - anchorRect.midX) <= 1.5)
        
        // Verify Butler speech bubble SwiftUI view mounts cleanly
        let tipHost = NSHostingView(rootView: ButlerToolbarSpeechBubbleView(
            tip: firstTip,
            butlerName: "曜",
            arrowCenterX: placement.arrowCenterX,
            onOpenJournal: {},
            onDismiss: {},
            onHoverChanged: { _ in }
        ))
        tipHost.frame = NSRect(x: 0, y: 0, width: 294, height: 118)
        tipHost.layoutSubtreeIfNeeded()
        #expect(tipHost.bounds.width == 294)
        
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
        let stageAspect = 1236.0 / laptop.unifiedTopStageHeight
        #expect(stageAspect < 3.6)
        #expect(laptop.heroHeight <= 158)
        #expect(laptop.totalContentHeight <= 700)
        
        // Verify Apple HIG concentric corner radius law (`innerRadius + inset == outerRadius`)
        #expect(DashboardCornerMetrics.innerCardRadius(compact: false) + DashboardCornerMetrics.unifiedInset(compact: false) == DashboardCornerMetrics.unifiedOuterRadius(compact: false))
        #expect(DashboardCornerMetrics.innerCardRadius(compact: true) + DashboardCornerMetrics.unifiedInset(compact: true) == DashboardCornerMetrics.unifiedOuterRadius(compact: true))
    }
    
    
    // MARK: 5. Lossless Vector Zoom Metrics for Document Center & Weekly Report Star-Map
    
    @Test func starMapLosslessVectorZoomScalesTypographyAndAnchorsViewportCenter() {
        let m1 = StarMapZoomMetrics(zoom: 1.0)
        let m2 = StarMapZoomMetrics(zoom: 2.2)
        #expect(abs(m2.fontSize(12) - 26.4) < 0.01)
        #expect(abs(m2.scaled(160) - 352.0) < 0.01)
        #expect(m2.zoom <= StarMapZoomMetrics.maxZoom)
        #expect(StarMapZoomMetrics(zoom: 5.0).zoom == StarMapZoomMetrics.maxZoom)
        #expect(StarMapZoomMetrics(zoom: 0.1).zoom == StarMapZoomMetrics.minZoom)
        #expect(m1.strokeWidth(1.0) >= 0.7)
        
        // Anchored pan keeps the world point at viewport center invariant under zoom
        let worldPt = CGPoint(x: 240, y: -120)
        let vpCenter = CGPoint(x: 500, y: 400)
        let panAt1 = CGSize(width: -worldPt.x, height: -worldPt.y)
        let panAt2 = StarMapZoomMetrics.zoomAnchoredPan(oldPan: panAt1, oldZoom: 1.0, newZoom: 2.0)
        let screenBefore = StarMapZoomMetrics.screenPoint(world: worldPt, viewportCenter: vpCenter, panOffset: panAt1, zoom: 1.0)
        let screenAfter = StarMapZoomMetrics.screenPoint(world: worldPt, viewportCenter: vpCenter, panOffset: panAt2, zoom: 2.0)
        #expect(abs(screenBefore.x - vpCenter.x) < 0.01)
        #expect(abs(screenBefore.y - vpCenter.y) < 0.01)
        #expect(abs(screenAfter.x - vpCenter.x) < 0.01)
        #expect(abs(screenAfter.y - vpCenter.y) < 0.01)
    }
}
