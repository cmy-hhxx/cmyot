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
    
    
    @Test func heatmapScopeBorderNeverClipsAcrossTightAndWideViewports() {
        let testSizes: [(CGSize, Int)] = [
            (CGSize(width: 480, height: 78), 48),
            (CGSize(width: 560, height: 88), 52),
            (CGSize(width: 640, height: 106), 53),
            (CGSize(width: 720, height: 140), 20),
            (CGSize(width: 560, height: 240), 53),
        ]
        for (size, weeksCount) in testSizes {
            let layout = HeatmapGridLayout.compute(size: size, weekCount: weeksCount)
            let strokeHalf = layout.scopeStrokeWidth * 0.5
            let dragStrokeHalf = layout.scopeStrokeWidth(isDragging: true) * 0.5
            let scope = layout.scopeRect(minCol: max(0, weeksCount - 2), maxCol: weeksCount - 1)
            #expect(scope.minX - dragStrokeHalf >= 1.5)
            #expect(scope.maxX + dragStrokeHalf <= layout.canvasWidth - 1.5)
            #expect(scope.minY - dragStrokeHalf >= 10.0)
            #expect(scope.maxY + dragStrokeHalf <= layout.canvasHeight - 1.5)
            #expect(layout.canvasHeight <= size.height + 1.0)
            // Gutter clearance: half-gutter outset minus half-stroke leaves strictly positive air gap before neighbor cells
            #expect(layout.scopeOutset == layout.gap * 0.5)
            #expect(layout.scopeOutset - strokeHalf >= 0.45)
            #expect(layout.scopeOutset - dragStrokeHalf >= 0.30)
        }
        
        // Verify upright 2-week window engine: latest mid-week slice + dragging left/right + heatmap scrub clamping
        let weeks: [[HeatmapDayCell]] = (0..<12).map { col in
            (0..<7).map { row in
                let isFuture = (col == 11 && row > 2)
                return HeatmapDayCell(
                    dateKey: "c\(col)r\(row)",
                    date: Date(timeIntervalSince1970: Double((col * 7 + row) * 86_400)),
                    typedChars: (col + 1) * 100 + row * 10,
                    aiCompletedChars: row * 5,
                    filesCreated: 0,
                    aiRequests: 0,
                    level: 1,
                    isFuture: isFuture,
                    isOutOfYear: false
                )
            }
        }
        
        // Default latest 2-week window frames exact upright columns 10...11 (7 + 3 = 10 active days, excluding 4 future slots)
        let latest = HeatmapTrendWindowEngine.slice(weeks: weeks, requestedEndWeek: nil)
        #expect(latest.range.startWeek == 10)
        #expect(latest.range.endWeek == 11)
        #expect(latest.range.isLatest == true)
        #expect(latest.range.canStepBackward == true)
        #expect(latest.range.canStepForward == false)
        #expect(latest.days.count == 10)
        #expect(latest.days.first?.id == "c10r0")
        #expect(latest.days.last?.id == "c11r2")
        
        // Dragging trend chart right pulls earlier history into view (decreases endWeek)
        let draggedBackEnd = HeatmapTrendWindowEngine.endWeekForTrendDrag(
            anchorEndWeek: 11,
            translationX: 120,
            plotWidth: 360,
            weekCount: 12
        )
        #expect(draggedBackEnd < 11)
        let earlierSlice = HeatmapTrendWindowEngine.slice(weeks: weeks, requestedEndWeek: draggedBackEnd)
        #expect(earlierSlice.range.isLatest == false)
        #expect(earlierSlice.range.endWeek - earlierSlice.range.startWeek == 1)
        #expect(earlierSlice.days.count == 14)
        
        // Dragging past year boundaries clamps cleanly to [1, weekCount - 1]
        let clampedLeft = HeatmapTrendWindowEngine.endWeekForTrendDrag(
            anchorEndWeek: 11,
            translationX: 2000,
            plotWidth: 360,
            weekCount: 12
        )
        #expect(clampedLeft == 1)
        let clampedRight = HeatmapTrendWindowEngine.endWeekForTrendDrag(
            anchorEndWeek: 3,
            translationX: -2000,
            plotWidth: 360,
            weekCount: 12
        )
        #expect(clampedRight == 11)
        
        // Heatmap direct drag slides viewport in pointer direction (left drag -> earlier weeks, right drag -> later weeks)
        let layout = HeatmapGridLayout.compute(size: CGSize(width: 560, height: 106), weekCount: 12)
        let heatBack = HeatmapTrendWindowEngine.endWeekForHeatmapDrag(
            anchorEndWeek: 11,
            translationX: -layout.pitch * 3,
            pitch: layout.pitch,
            weekCount: 12
        )
        #expect(heatBack == 8)
        let heatTapCol0 = HeatmapTrendWindowEngine.endWeekForHeatmapTap(
            locationX: layout.gridOriginX + 2,
            layout: layout,
            weekCount: 12
        )
        #expect(heatTapCol0 == 1)
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
    
    
    // MARK: 6. Right-Click Format Clean (`清洗规整`) & Semantic Restructure (`语义规整`)
    
    @Test func structuredPlainTextCleanerStripsBrokenStarsAndIndentsWithTabs() {
        let messyAIPaste = """
        2. **本次重评范围（第一批约 4.5 万条）*
           - **全部 `both`（问句错位 + 缺前序历史）**：全日期约 **3.38 万条**（`aime_fast` ~3.24 万 + `aime_expert` ~0.13 万，主要集中在 `10-28`–`11-22`）。
           - **`2026-11-12` 起全部 `only_prior`（问句对但原缺前序历史）**：约 **1.11 万条**（主要为近期 `aime_expert`）。
           - *注：`2026-11-11` 及更早的 `only_prior`（约 7.4 万条）暂未纳入第一批重评。*

        3. **产物路径与对聚类的影响**
           - 重评结果先独立写入 **`/mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval_reeval_r533/`**，待跑完验收后，再通过脚本按 `(session_id, trace_id)` 原子替换回 **`/mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval/`**（替换前会保留原文件备份）。
           - 这 ~4.5 万条 case 替换后，其 `turns[].problem` 会整体更新（预期误报率明显下降）。

        4. **需要聚类侧配合的动作**
           - **等待回写通知**：建议等这批重评跑完并合入 `0_daily_eval/` 后，再做正式聚类出数或大盘口径更新。
           - **按 `(session_id, trace_id)` 覆盖或重聚，切勿增量直接相加**：这批 case 在替换后属于同一批 trace 的新判词；如果增量聚类直接追加，会导致同一 trace 新旧两套 problem 重复统计。建议：
             - 要么按 `(session_id, trace_id)` 删除旧 `item_index` 中对应条目后再重新归类这批更新后的 case；
             - 要么直接对受影响日期（至少 **`2026-11-12`–`2026-11-22`**，以及包含 `v1_traces` 回填的 **`2026-10-28`–`2026-11-07`**）重跑聚类。
           - **口径标注**：合入后，`2026-11-12` 及之后全量为 `r533` 口径；`11-11` 之前仅 `both` 样本为 `r533`、`only_prior` 仍为旧口径（如需全历史拉齐可后续安排第二批）。
        """
        
        let cleaned = AIDocumentTextCleaner.cleanStructuredPlainText(messyAIPaste)
        let lines = cleaned.components(separatedBy: "\n")
        
        // Zero leftover Markdown bold/italic/backtick noise
        #expect(!cleaned.contains("**"))
        #expect(!cleaned.contains("`"))
        #expect(!cleaned.contains("*注："))
        #expect(!cleaned.contains("）*"))
        
        // Section headings stay flush left with sequential numbers preserved
        #expect(lines.contains("2. 本次重评范围（第一批约 4.5 万条）"))
        #expect(lines.contains("3. 产物路径与对聚类的影响"))
        #expect(lines.contains("4. 需要聚类侧配合的动作"))
        
        // Level-1 points use single Tab, Level-2 nested options use double Tab
        #expect(lines.contains("\t- 全部 both（问句错位 + 缺前序历史）：全日期约 3.38 万条（aime_fast ~3.24 万 + aime_expert ~0.13 万，主要集中在 10-28–11-22）。"))
        #expect(lines.contains("\t- 注：2026-11-11 及更早的 only_prior（约 7.4 万条）暂未纳入第一批重评。"))
        #expect(lines.contains("\t- 重评结果先独立写入 /mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval_reeval_r533/，待跑完验收后，再通过脚本按 (session_id, trace_id) 原子替换回 /mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval/（替换前会保留原文件备份）。"))
        #expect(lines.contains("\t\t- 要么按 (session_id, trace_id) 删除旧 item_index 中对应条目后再重新归类这批更新后的 case；"))
        #expect(lines.contains("\t\t- 要么直接对受影响日期（至少 2026-11-12–2026-11-22，以及包含 v1_traces 回填的 2026-10-28–2026-11-07）重跑聚类。"))
        
        // Preserve legitimate math, globs, and ATX sub-lists properly
        let edgeCase = """
        ## 操作步骤
        1. **扫描** `*.py` 和 `dir/*`（计算 `2 * 3` 与 `turns[*]`）
           - 保留 `file_*.json`
        """
        let edgeCleaned = AIDocumentTextCleaner.cleanStructuredPlainText(edgeCase)
        #expect(edgeCleaned == "操作步骤\n\t1. 扫描 *.py 和 dir/*（计算 2 * 3 与 turns[*]）\n\t\t- 保留 file_*.json")
        
        // Semantic restructure action metadata & prompt wiring
        #expect(AIAction.semanticRestructure.outputsStructuredPlainText == true)
        #expect(AIBotID(action: .semanticRestructure) == .explain)
        #expect(AIAction.semanticRestructure.defaultSystemPrompt.contains("Tab"))
    }
    
    
    @Test func restructureReviewMachinePreservesUntouchedOriginalAcrossCompareUpgradeRetryAndKeepBoth() {
        let untouched = "2. **重评范围*\n   - **全部 `both`**：约 **3.38 万条**。\n"
        let cleaned = AIDocumentTextCleaner.cleanStructuredPlainText(untouched) + "\n"
        let semanticV1 = "1. 重评范围\n\t- both 全量约 3.38 万条。\n"
        let semanticV2 = "1. 范围结论\n\t- 第一批覆盖 both 约 3.38 万条。\n"
        
        // Metrics count stripped Markdown noise & Tab-indented lines accurately
        let cleanMetrics = TextRestructureMetrics.compute(original: untouched, result: cleaned)
        #expect(cleanMetrics.removedMarkerCount >= 6)
        #expect(cleanMetrics.tabIndentedLineCount == 1)
        #expect(cleanMetrics.summaryText(for: .formatClean).contains("清除"))
        
        // Start with format clean at offset 10
        var machine = TextRestructureReviewMachine(
            mode: .formatClean,
            originalText: untouched,
            transformedText: cleaned,
            originLocation: 10,
            isWholeDocument: false
        )
        #expect(machine.showingOriginal == false)
        #expect(machine.activeDisplayedText == cleaned)
        #expect(machine.activeRange == NSRange(location: 10, length: (cleaned as NSString).length))
        
        // Toggle A/B compare -> shows untouched original cleanly, then flips back
        let toOriginal = machine.toggleCompare()
        #expect(toOriginal.replacement == untouched)
        #expect(toOriginal.isRevertingOrOriginal == true)
        #expect(machine.showingOriginal == true)
        #expect(machine.activeRange.length == (untouched as NSString).length)
        
        let backToClean = machine.toggleCompare()
        #expect(backToClean.replacement == cleaned)
        #expect(backToClean.isRevertingOrOriginal == false)
        #expect(machine.showingOriginal == false)
        
        // Seamless upgrade from formatClean -> semanticRestructure v1, then Retry -> v2
        let upgradePlan = machine.appendRevision(mode: .semanticRestructure, transformedText: semanticV1)
        #expect(upgradePlan.replacement == semanticV1)
        #expect(machine.revisions.count == 2)
        #expect(machine.selectedRevisionIndex == 1)
        #expect(machine.untouchedOriginalText == untouched)
        
        let retryPlan = machine.appendRevision(mode: .semanticRestructure, transformedText: semanticV2)
        #expect(retryPlan.replacement == semanticV2)
        #expect(machine.revisions.count == 3)
        #expect(machine.selectedRevisionIndex == 2)
        #expect(machine.canStepPreviousRevision == true)
        #expect(machine.canStepNextRevision == false)
        
        // Step back to v1 and forward to v2
        let backStep = machine.stepRevision(delta: -1)
        #expect(backStep?.replacement == semanticV1)
        #expect(machine.selectedRevisionIndex == 1)
        let fwdStep = machine.stepRevision(delta: 1)
        #expect(fwdStep?.replacement == semanticV2)
        #expect(machine.selectedRevisionIndex == 2)
        
        // Keep Both preserves untouched original + blank line + selected restructured version
        let keepBoth = machine.keepBothPlan()
        #expect(keepBoth.replacement.hasPrefix(untouched.trimmingCharacters(in: .newlines)))
        #expect(keepBoth.replacement.contains("\n\n"))
        #expect(keepBoth.replacement.hasSuffix(semanticV2))
        
        // Revert STILL restores the very first untouched original even after clean -> semantic -> retry
        let revert = machine.revertPlan()
        #expect(revert?.replacement == untouched)
        #expect(revert?.isRevertingOrOriginal == true)
        
        // Accept while viewing original restores the active transformed revision
        _ = machine.toggleCompare()
        #expect(machine.showingOriginal == true)
        let accept = machine.acceptPlan()
        #expect(accept?.replacement == semanticV2)
    }
    
    
    // MARK: 7. Pixel-Exact Tab-Stop Table Alignment & Quick AI Fast Lane Wire Payloads
    
    @Test func structuredTableCleanerAlignsMultiColumnTablesToExactTabStopsAndFlattensWideKeyValueTables() throws {
        let sample = """
        ## 先备份：最后一轮没有待处理数据

        我先停掉守护进程（避免它在自动轮次运行时和我的手动轮次冲突），然后手动跑一轮 `--incremental --no-full-fallback`：

        | 树 | delta | 合并后 | verify | 耗时 | 时间 |
        |---|---|---|---|---|---|
        | aime_expert | **0** | 157,601 | noop | 45s | 15:22 |
        | aime_fast | **0** | 460,501 | noop | 97s | 15:24 |

        **两棵树均为 noop，说明截至 15:24 没有任何待聚类数据。** 我 13:00 预测的 fast 剩余回补，已在 14:29 那轮被完全吸收（当时 +1,429），没有留下尾巴。

        附带刷新：`cases=211,339`、`traces_missing_case=0`、badcase **37,773**、goldencase **22,541**。

        ## 状态干净性检查

        | 检查项 | 结果 |
        |---|---|
        | `runs/*/run_new`、`run_delta` 残留 | 无 |
        | `verify.json` errors、locator_mismatch | 0 / 0（两棵树） |
        | 交付物 | expert 11 个文件、fast 11 个文件，完整 |
        | `run_merged` | expert 1.2 GB、fast 2.7 GB 完整保留 |
        | case 身份索引 | `cases_aime.jsonl` 173 MB 和 `state.json`，均在 |
        | 内存 | anon 10.5 GB，`oom_kill` 仍为 23 |
        """
        
        // Simulate a proportional CJK + Latin font (e.g. PingFang SC / SF Pro) where CJK != 2x space
        let propMetrics = AIDocumentTextCleaner.TableLayoutMetrics(
            tabInterval: 28.0,
            minColumnGap: 10.0,
            measureWidth: { text in
                text.unicodeScalars.reduce(CGFloat(0)) { acc, s in
                    if s.isASCII {
                        return acc + (s == " " ? 3.5 : 7.2)
                    }
                    return acc + 13.0
                }
            }
        )
        
        let cleaned = AIDocumentTextCleaner.cleanStructuredPlainText(sample, tableMetrics: propMetrics)
        let lines = cleaned.components(separatedBy: "\n")
        
        // Zero Markdown decoration noise, glob path preserved intact
        #expect(!cleaned.contains("**"))
        #expect(!cleaned.contains("`"))
        #expect(!cleaned.contains("|"))
        #expect(cleaned.contains("runs/*/run_new、run_delta 残留：无"))
        #expect(cleaned.contains("数据。我 13:00"))
        
        // Section headings sit flush left directly above Tab-indented content (no awkward blank line after heading)
        let firstIdx = try #require(lines.firstIndex(of: "先备份：最后一轮没有待处理数据"))
        #expect(lines[firstIdx + 1].hasPrefix("\t我先停掉守护进程"))
        
        // Verify EVERY column of the 6-column table lands on the EXACT same pixel Tab-stop X across all 3 rows!
        let headerRow = try #require(lines.first { $0.contains("delta") && $0.contains("verify") })
        let expertRow = try #require(lines.first { $0.contains("aime_expert") })
        let fastRow = try #require(lines.first { $0.contains("aime_fast") })
        
        func columnStartPositions(for line: String, metrics: AIDocumentTextCleaner.TableLayoutMetrics) -> [CGFloat] {
            var x: CGFloat = 0
            var starts: [CGFloat] = []
            var currentCell = ""
            var inCell = false
            for ch in line {
                if ch == "\t" {
                    if inCell {
                        x += metrics.measureWidth(currentCell)
                        currentCell = ""
                        inCell = false
                    }
                    let nextStop = (floor((x + 0.01) / metrics.tabInterval) + 1) * metrics.tabInterval
                    x = nextStop
                } else {
                    if !inCell {
                        starts.append(x)
                        inCell = true
                    }
                    currentCell.append(ch)
                }
            }
            return starts
        }
        
        let headerCols = columnStartPositions(for: headerRow, metrics: propMetrics)
        let expertCols = columnStartPositions(for: expertRow, metrics: propMetrics)
        let fastCols = columnStartPositions(for: fastRow, metrics: propMetrics)
        #expect(headerCols.count == 6)
        #expect(headerCols == expertCols)
        #expect(headerCols == fastCols)
        
        // Wide 2-column key-value table converts cleanly into structured Tab-indented `- Key：Value` list
        #expect(lines.contains("\t- runs/*/run_new、run_delta 残留：无"))
        #expect(lines.contains("\t- verify.json errors、locator_mismatch：0 / 0（两棵树）"))
        #expect(lines.contains("\t- 内存：anon 10.5 GB，oom_kill 仍为 23"))
    }
    
    
    @Test func quickActionsUseFastLaneAndDisableThinkingAcrossProviders() throws {
        // Quick editor actions enable fast lane; heavy multi-doc/report actions keep full reasoning
        #expect(AIAction.translate.isQuickAction == true)
        #expect(AIAction.summarize.isQuickAction == true)
        #expect(AIAction.explain.isQuickAction == true)
        #expect(AIAction.semanticRestructure.isQuickAction == true)
        #expect(AIAction.weeklyReportItem.isQuickAction == true)
        #expect(AIAction.interactiveChart.isQuickAction == true)
        #expect(AIAction.interactiveChart.fastLaneMaxOutputTokens(forInputLength: 1000) == 512)
        #expect(AIAction.weeklyReport.isQuickAction == false)
        #expect(AIAction.organizeAndMerge.isQuickAction == false)
        
        let msgs: [AIMessage] = [.system("sys"), .user("hello")]
        
        // DeepSeek-v4.1-flash on OpenCode Go with disablesThinking -> thinking.type = disabled
        let dsFlashCfg = AIConfiguration(endpoint: .openAIChatCompletions, baseURL: "https://opencode.ai/zen/go/v1", model: "deepseek-v4.1-flash", apiKey: "k")
        let dsFlashBody = AIClient(configuration: dsFlashCfg, disablesThinking: true).debugRequestBody(for: msgs)
        let dsFlashThinking = try #require(dsFlashBody["thinking"] as? [String: String])
        #expect(dsFlashThinking["type"] == "disabled")
        
        // GLM-5 on OpenAI Chat Completions with disablesThinking -> thinking.type = disabled
        let glmCfg = AIConfiguration(endpoint: .openAIChatCompletions, baseURL: "https://opencode.ai/zen/go/v1", model: "glm-5", apiKey: "k")
        let glmBody = AIClient(configuration: glmCfg, disablesThinking: true).debugRequestBody(for: msgs)
        let glmThinking = try #require(glmBody["thinking"] as? [String: String])
        #expect(glmThinking["type"] == "disabled")
        
        // Qwen3 on OpenAI Chat Completions with disablesThinking -> enable_thinking = false
        let qwenCfg = AIConfiguration(endpoint: .openAIChatCompletions, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen3-235b", apiKey: "k")
        let qwenBody = AIClient(configuration: qwenCfg, disablesThinking: true).debugRequestBody(for: msgs)
        #expect(qwenBody["enable_thinking"] as? Bool == false)
        
        // GPT-5 on OpenAI Responses with disablesThinking -> reasoning.effort = minimal + stream = true
        let gpt5Cfg = AIConfiguration(endpoint: .openAIResponses, baseURL: "https://api.openai.com/v1", model: "gpt-5", apiKey: "k")
        let gpt5Body = AIClient(configuration: gpt5Cfg, disablesThinking: true).debugRequestBody(for: msgs, stream: true)
        let gpt5Reasoning = try #require(gpt5Body["reasoning"] as? [String: String])
        #expect(gpt5Reasoning["effort"] == "minimal")
        #expect(gpt5Body["stream"] as? Bool == true)
        
        // Anthropic Claude with disablesThinking -> thinking.type = disabled
        let claudeCfg = AIConfiguration(endpoint: .anthropicMessages, baseURL: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5", apiKey: "k")
        let claudeBody = AIClient(configuration: claudeCfg, disablesThinking: true).debugRequestBody(for: msgs)
        let claudeThinking = try #require(claudeBody["thinking"] as? [String: String])
        #expect(claudeThinking["type"] == "disabled")
        
        // Gemini with disablesThinking -> thinkingBudget = 0
        let geminiCfg = AIConfiguration(endpoint: .googleGemini, baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-2.5-flash", apiKey: "k")
        let geminiBody = AIClient(configuration: geminiCfg, disablesThinking: true).debugRequestBody(for: msgs)
        let genCfg = try #require(geminiBody["generationConfig"] as? [String: Any])
        let tCfg = try #require(genCfg["thinkingConfig"] as? [String: Any])
        #expect(tCfg["thinkingBudget"] as? Int == 0)
        
        // Ollama with disablesThinking -> think = false
        let ollamaCfg = AIConfiguration(endpoint: .ollama, baseURL: "http://localhost:11434", model: "qwen3:8b", apiKey: "")
        let ollamaBody = AIClient(configuration: ollamaCfg, disablesThinking: true).debugRequestBody(for: msgs)
        #expect(ollamaBody["think"] as? Bool == false)
    }
    
    
    @Test func realTextKitProportionalFontTableAlignmentAndInteractiveTableExtraction() throws {
        // Real AppKit NSLayoutManager alignment test using proportional systemFont (reproducing Screenshot 1!)
        let storage = NSTextStorage()
        let scanner = LineEndingScanner(textStorage: storage, lineEnding: .lf)
        let textView = EditorTextView(textStorage: storage, lineEndingScanner: scanner)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.tabWidth = 4
        
        let mdTable = """
        | 树 | delta | 合并后 | verify | 耗时 | 时间 |
        |---|---|---|---|---|---|
        | aime_expert | **0** | 157,601 | noop | 45s | 15:22 |
        | aime_fast | **0** | 460,501 | noop | 97s | 15:24 |
        """
        
        let liveMetrics = TextRestructureSessionController.liveTableMetrics(for: textView)
        let cleaned = AIDocumentTextCleaner.cleanStructuredPlainText(mdTable, tableMetrics: liveMetrics)
        let rows = cleaned.components(separatedBy: "\n")
        #expect(rows.count == 3)
        
        // Measure ACTUAL rendered glyph X of every column start in NSLayoutManager (must match to < 0.05pt with >= 16pt gap!)
        let probeEndX = try #require(liveMetrics.measureLineEndX)
        func realColumnBounds(for line: String) -> [(startX: CGFloat, endX: CGFloat)] {
            var results: [(CGFloat, CGFloat)] = []
            var prefix = ""
            var cell = ""
            var cellStartPrefix = ""
            var inCell = false
            for ch in line {
                if ch == "\t" {
                    if inCell {
                        results.append((probeEndX(cellStartPrefix), probeEndX(cellStartPrefix + cell)))
                        prefix += cell
                        cell = ""
                        inCell = false
                    }
                    prefix.append(ch)
                } else {
                    if !inCell {
                        cellStartPrefix = prefix
                        inCell = true
                    }
                    cell.append(ch)
                }
            }
            if inCell {
                results.append((probeEndX(cellStartPrefix), probeEndX(cellStartPrefix + cell)))
            }
            return results
        }
        
        let headerBounds = realColumnBounds(for: rows[0])
        let expertBounds = realColumnBounds(for: rows[1])
        let fastBounds = realColumnBounds(for: rows[2])
        #expect(headerBounds.count == 6)
        #expect(expertBounds.count == 6)
        #expect(fastBounds.count == 6)
        
        for c in 0..<6 {
            #expect(abs(headerBounds[c].startX - expertBounds[c].startX) < 0.05)
            #expect(abs(headerBounds[c].startX - fastBounds[c].startX) < 0.05)
            if c > 0 {
                let prevMaxEnd = max(headerBounds[c - 1].endX, max(expertBounds[c - 1].endX, fastBounds[c - 1].endX))
                #expect(headerBounds[c].startX - prevMaxEnd >= 16.0)
            }
        }
        
        // One-click Align Table works on BOTH Markdown pipe tables AND cleaned Tab-separated plain tables!
        let messyTabTable = "树\tdelta\t合并后\naime_expert\t0\t157,601\naime_fast\t0\t460,501"
        let alignedTab = MarkdownTableFormatter.formatTables(in: messyTabTable, metrics: liveMetrics)
        #expect(alignedTab != messyTabTable)
        #expect(MarkdownTableFormatter.containsAnyTable(cleaned) == true)
        
        // Interactive Table & Chart Studio extracts cleanly from cleaned Tab-separated tables (zero blank chart!)
        let extractedFromTabs = try #require(MarkdownTableFormatter.extractTable(from: cleaned))
        #expect(extractedFromTabs.headers == ["树", "delta", "合并后", "verify", "耗时", "时间"])
        #expect(extractedFromTabs.rows.count == 2)
        #expect(extractedFromTabs.rows[0][0] == "aime_expert")
        #expect(extractedFromTabs.rows[0][2] == "157,601")
        
        let html = MarkdownTableFormatter.generateInstantChartHTML(from: cleaned)
        #expect(html.contains("studio-grid"))
        #expect(html.contains("aime_expert"))
        #expect(html.contains("157,601"))
        #expect(!html.contains("**0**"))
    }
    
    
    @Test func contextMenuQuickHighlightRowFitsAllIconsWithBalancedDividerClearance() {
        let count = min(QuickHighlightRowMetrics.maxQuickSwatches, HighlightColor.allCases.count)
        let minW = QuickHighlightRowMetrics.minimumWidth(swatchCount: count)
        #expect(count == 7)
        #expect(minW <= 260)
        #expect(QuickHighlightRowMetrics.swatchesToSeparatorMinGap >= 8)
        #expect(QuickHighlightRowMetrics.separatorToToolsGap >= 8)
    }
}
