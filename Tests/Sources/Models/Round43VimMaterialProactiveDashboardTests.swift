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
        #expect(laptop.heroHeight <= 146)
        #expect(laptop.outerPadV <= 9)
        #expect(laptop.row2Height <= 238)
        #expect(laptop.totalContentHeight <= 700)
        
        // Tall display (1440×900) avoids giant top/bottom dead margins and keeps Row 2 compact & void-free
        let desktop = DashboardViewportLayout.resolve(
            viewportSize: CGSize(width: 1440, height: 900),
            isEmbeddedInSettings: false,
            hasHeroPhoto: true
        )
        #expect(desktop.needsVerticalScroll == false)
        #expect(desktop.outerPadV <= 10)
        #expect(desktop.row2Height <= 238)
        #expect(desktop.row1Height >= 320)
        
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
    
    
    // MARK: 12. One-Click Star-Map Organize (Whimsical Name Recognition, Monolith Split & Atomic DB Preservation)
    
    @Test func oneClickOrganizeRenamesGeneratedWhimsicalDocsAndSplitsBloatedMonolith() async throws {
        // 1. Every whimsical placeholder generated by GeneratedDocumentName must be recognized as untitled.
        let whimsicalTitles = [
            "啃瓜的小浣熊", "晚风的熊猫", "泡茶的烤冷面", "口袋里的风铃",
            "写诗的柴犬", "晒太阳的章鱼", "躲雨的柯基", "潜艇里的柴犬",
            "机房里的袋鼠", "拼图的狐狸", "海底的洗衣机", "写诗的冻柠茶",
            "练舞的纸船", "吹哨的松鼠", "盘核桃的闹钟", "小浣熊2",
        ]
        for title in whimsicalTitles {
            #expect(GeneratedDocumentName.isGeneratedName(title), "Expected generated name: \(title)")
            #expect(DocumentCenterAgentOrganizer.isGenericUntitled(title, hasFilePath: false))
            #expect(!DocumentCenterAgentOrganizer.isGenericUntitled(title, hasFilePath: true))
        }
        
        // Real user-authored titles must NOT be treated as generated placeholders.
        for realTitle in ["AIME 数据梳理与统计", "P0-P4 评级口径与案例", "评测看板全站优化与文档", "项目需求方案"] {
            #expect(!GeneratedDocumentName.isGeneratedName(realTitle))
            #expect(!DocumentCenterAgentOrganizer.isGenericUntitled(realTitle, hasFilePath: false))
        }
        
        // 2. Simulate 10 documents all piled into one bloated group ("技术笔记") with whimsical names.
        let now = Date()
        let rawSamples: [(id: String, title: String, content: String)] = [
            ("doc:1", "啃瓜的小浣熊", "# 评测看板全站优化\n整理评测看板 badcase 分布与重评口径。"),
            ("doc:2", "晚风的熊猫", "# 归因逻辑误报分析\n对比 r533 重评前后的 badcase 与 goldencase 变化。"),
            ("doc:3", "泡茶的烤冷面", "# AIME 聚类指标统计\n汇总全量 trace 数据梳理与大盘口径波动。"),
            ("doc:4", "口袋里的风铃", "# 数据集增量合并报表\n按日期核对聚类统计指标与覆盖率。"),
            ("doc:5", "写诗的柴犬", "# 新版星图产品设计方案\n明确核心架构规划与 PRD 需求拆分。"),
            ("doc:6", "晒太阳的章鱼", "# 权限体系架构设计\n规划多角色隔离方案与接口协议。"),
            ("doc:7", "躲雨的柯基", "# 周三产品评审会议纪要\n对齐上线排期与会议同步事项。"),
            ("doc:8", "潜艇里的柴犬", "# 本周工作周报与待办清单\n总结已完成里程碑并列出下周 todo。"),
            ("doc:9", "机房里的袋鼠", "import Foundation\nfunc deployWorker() { /* worker 部署脚本与 docker 配置 */ }"),
            ("doc:10", "拼图的狐狸", "测试一下"),
        ]
        let inputs = rawSamples.map { sample in
            OrganizeFunnelInput(
                id: sample.id,
                dbRecordID: sample.id,
                title: sample.title,
                filePath: nil,
                syntax: sample.id == "doc:9" ? "Swift" : "Markdown",
                currentGroup: "技术笔记",
                content: sample.content,
                updatedAt: now,
                isOpenNow: false,
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(sample.title, hasFilePath: false)
            )
        }
        
        let plan = await DocumentOrganizeFunnel.runFullPipeline(
            items: inputs,
            existingGroups: ["技术笔记"],
            allowRemoteAI: false
        )
        
        // Trivial test doc under a generated whimsical title ("拼图的狐狸" / "测试一下") is purged by Stage 1.
        #expect(plan.funnel.junkToDelete.map(\.item.id) == ["doc:10"])
        #expect(plan.assignments.count == 9)
        
        // Bloated group ("技术笔记") MUST be split into crisp, balanced pillars (not 1 wall, not over-fragmented).
        let groups = Dictionary(grouping: plan.assignments, by: \.group)
        #expect(groups.count >= 2 && groups.count <= DocumentOrganizeFunnel.targetMaxGroups(for: plan.assignments.count))
        #expect((groups.values.map(\.count).max() ?? 99) <= 5)
        
        // Every surviving whimsical-named doc MUST get a crisp, non-generated, unique suggestedTitle.
        var seenTitles = Set<String>()
        for assignment in plan.assignments {
            let newTitle = try #require(assignment.suggestedTitle)
            #expect(!GeneratedDocumentName.isGeneratedName(newTitle))
            #expect(!DocumentCenterAgentOrganizer.isGenericUntitled(newTitle, hasFilePath: false))
            #expect(seenTitles.insert(newTitle).inserted)
        }
        
        // parsePlan must reject an AI echoing back a generated placeholder name.
        let echoedJSON = #"{"assignments":[{"id":"doc:1","group":"评测分析","suggestedTitle":"啃瓜的小浣熊"}]}"#
        let parsed = try #require(DocumentCenterAgentOrganizer.parsePlan(from: echoedJSON, validIDs: ["doc:1"]))
        #expect(parsed.assignments[0].suggestedTitle == nil)
        let finalized = DocumentOrganizeFunnel.finalizeAssignments(
            parsed.assignments,
            survivors: Array(inputs.prefix(1)),
            existingGroups: ["技术笔记"]
        )
        #expect(finalized[0].suggestedTitle == "评测看板全站优化")
    }
    
    
    @Test func semanticMergeConsolidatesSameTopicFragmentsWithoutOverMergingDistinctDocs() async throws {
        let now = Date()
        let inputs: [OrganizeFunnelInput] = [
            // Thread A: 3 fragmented scratch notes about AIME r533 re-eval & incremental clustering (SHOULD merge into 1)
            OrganizeFunnelInput(
                id: "doc:aime-1",
                dbRecordID: "doc:aime-1",
                title: "啃瓜的小浣熊",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# AIME r533 重评范围与聚类回写\n本次第一批重评约 4.5 万条，包含 aime_fast 与 aime_expert，写入 0_daily_eval_reeval_r533 后按 trace_id 回写聚类。",
                updatedAt: now.addingTimeInterval(-600),
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:aime-2",
                dbRecordID: "doc:aime-2",
                title: "晚风的熊猫",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# AIME 增量聚类备份状态\naime_expert delta=0 合并后 157,601，aime_fast delta=0 合并后 460,501，verify.json errors=0，run_merged 完整保留，0_daily_eval_reeval_r533 待回写。",
                updatedAt: now.addingTimeInterval(-300),
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:aime-3",
                dbRecordID: "doc:aime-3",
                title: "泡茶的烤冷面",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# AIME r533 聚类口径核对\n确认 aime_fast 与 aime_expert 的 r533 重评结果按 trace_id 覆盖回写，verify.json 校验通过。",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            // Thread B: 2 fragmented notes about Worker OOM pressure testing (SHOULD merge into 1)
            OrganizeFunnelInput(
                id: "doc:worker-1",
                dbRecordID: "doc:worker-1",
                title: "口袋里的风铃",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# 评测 Worker 压测与内存监控\nworker_runner 并发 32 压测，anon 内存峰值 10.5 GB，oom_kill 计数升至 23。",
                updatedAt: now.addingTimeInterval(-200),
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:worker-2",
                dbRecordID: "doc:worker-2",
                title: "写诗的柴犬",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# 评测 Worker OOM 排查步骤\n定位 worker_runner 压测期间触发 oom_kill 的内存泄露点，调整并发上限并复测。",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            // Independent distinct topics (MUST NOT merge with each other or with AIME / Worker!)
            OrganizeFunnelInput(
                id: "doc:prd",
                dbRecordID: "doc:prd",
                title: "晒太阳的章鱼",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# 权限中心多租户角色方案\n规划组织架构、RBAC 角色继承、审批流与前端菜单可见性控制。",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:meeting",
                dbRecordID: "doc:meeting",
                title: "躲雨的柯基",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# 周三视觉改版评审会议纪要\n确定图标圆角规范、深浅色对比度标准以及周五提测窗口。",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
            OrganizeFunnelInput(
                id: "doc:weekly",
                dbRecordID: "doc:weekly",
                title: "潜艇里的柴犬",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "技术笔记",
                content: "# 本周工作周报与下周排期\n汇总个人交付进度、跨团队协调事项以及下周里程碑 todo。",
                updatedAt: now,
                isOpenNow: false,
                isUntitled: true
            ),
        ]
        
        let plan = await DocumentOrganizeFunnel.runFullPipeline(
            items: inputs,
            existingGroups: ["技术笔记"],
            allowRemoteAI: false
        )
        
        // 8 fragmented notes consolidate cleanly to 5 meaningful standalone documents (3 merged away, NOT collapsed into 1!).
        #expect(plan.funnel.survivors.count == 5)
        #expect(plan.funnel.deletedDuplicateCount == 3)
        #expect(plan.funnel.mergeClusters.count == 2)
        
        let aimeCluster = try #require(plan.funnel.mergeClusters.first(where: { $0.primary.id.hasPrefix("doc:aime") }))
        #expect(aimeCluster.duplicates.count == 2)
        #expect(aimeCluster.mergedContent.contains("157,601"))
        #expect(aimeCluster.mergedContent.contains("4.5 万条"))
        
        let workerCluster = try #require(plan.funnel.mergeClusters.first(where: { $0.primary.id.hasPrefix("doc:worker") }))
        #expect(workerCluster.duplicates.count == 1)
        #expect(workerCluster.mergedContent.contains("oom_kill"))
        
        // Independent topics stayed separate and groups compacted cleanly to <= 3 pillars.
        let survivorIDs = Set(plan.funnel.survivors.map(\.id))
        #expect(survivorIDs.contains("doc:prd"))
        #expect(survivorIDs.contains("doc:meeting"))
        #expect(survivorIDs.contains("doc:weekly"))
        let finalGroups = Set(plan.assignments.map(\.group))
        #expect(finalGroups.count >= 2 && finalGroups.count <= 3)
        
        // AI merge guardrails: accept a sane 2-doc semantic merge, reject mega-dump (>60%) & saved-file-to-saved-file merge.
        let baseSurvivors: [OrganizeFunnelInput] = [
            OrganizeFunnelInput(id: "s1", dbRecordID: "s1", title: "草稿一", filePath: nil, syntax: "Markdown", currentGroup: "", content: "接口鉴权方案背景与目标说明。", updatedAt: now, isOpenNow: false, isUntitled: true),
            OrganizeFunnelInput(id: "s2", dbRecordID: "s2", title: "草稿二", filePath: nil, syntax: "Markdown", currentGroup: "", content: "接口鉴权 Token 刷新流程补充。", updatedAt: now, isOpenNow: false, isUntitled: true),
            OrganizeFunnelInput(id: "s3", dbRecordID: "s3", title: "fileA.md", filePath: "/tmp/fileA.md", syntax: "Markdown", currentGroup: "", content: "本地磁盘文件 A 内容。", updatedAt: now, isOpenNow: false, isUntitled: false),
            OrganizeFunnelInput(id: "s4", dbRecordID: "s4", title: "fileB.md", filePath: "/tmp/fileB.md", syntax: "Markdown", currentGroup: "", content: "本地磁盘文件 B 内容。", updatedAt: now, isOpenNow: false, isUntitled: false),
            OrganizeFunnelInput(id: "s5", dbRecordID: "s5", title: "周报", filePath: nil, syntax: "Markdown", currentGroup: "", content: "本周总结。", updatedAt: now, isOpenNow: false, isUntitled: false),
            OrganizeFunnelInput(id: "s6", dbRecordID: "s6", title: "备忘", filePath: nil, syntax: "Markdown", currentGroup: "", content: "个人购物清单。", updatedAt: now, isOpenNow: false, isUntitled: false),
        ]
        let baseFunnel = OrganizeFunnelStageResult(junkToDelete: [], mergeClusters: [], survivors: baseSurvivors)
        let baseAssignments = baseSurvivors.map {
            DocumentCenterAgentOrganizer.Assignment(id: $0.id, group: "工程与开发", suggestedTitle: nil)
        }
        
        // 1) Over-merge proposal (5 of 6 docs > 60%) MUST be rejected.
        let overMergeOutcome = DocumentOrganizeFunnel.applyValidatedAIMerges(
            [.init(primaryId: "s1", mergeIds: ["s2", "s3", "s5", "s6"], mergedTitle: "全部文档大合集", group: "综合", reason: "全部合并")],
            baseFunnel: baseFunnel,
            rawAssignments: baseAssignments
        )
        #expect(overMergeOutcome.funnel.survivors.count == 6)
        
        // 2) Two saved disk files (s3 + s4) MUST NOT be merged, while valid scratch pair (s1 + s2) IS merged cleanly!
        let mixedOutcome = DocumentOrganizeFunnel.applyValidatedAIMerges(
            [
                .init(primaryId: "s1", mergeIds: ["s2"], mergedTitle: "接口鉴权方案汇总", group: "工程与开发", reason: "同属接口鉴权草稿"),
                .init(primaryId: "s3", mergeIds: ["s4"], mergedTitle: "合并磁盘文件", group: "工程与开发", reason: "测试保护"),
            ],
            baseFunnel: baseFunnel,
            rawAssignments: baseAssignments
        )
        #expect(mixedOutcome.funnel.survivors.count == 5)
        #expect(mixedOutcome.funnel.mergeClusters.count == 1)
        #expect(mixedOutcome.funnel.mergeClusters[0].bestTitle == "接口鉴权方案汇总")
        #expect(mixedOutcome.funnel.mergeClusters[0].mergedContent.contains("Token 刷新流程补充"))
        #expect(mixedOutcome.funnel.survivors.contains(where: { $0.id == "s3" }))
        #expect(mixedOutcome.funnel.survivors.contains(where: { $0.id == "s4" }))
    }
    
    
    @Test func databaseBatchAssignGroupThenRenamePreservesNewGroupAndPrunesEmptyGroups() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-organize-db-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "organize.sqlite3"))
        db.createDocumentGroup(named: "旧杂项")
        db.saveDocument(
            id: "doc:whim-1",
            title: "啃瓜的小浣熊",
            filePath: nil,
            syntax: "Markdown",
            content: "# 评测看板数据口径梳理\n核心指标对齐。",
            groupName: "旧杂项"
        )
        db.reloadDocuments()
        
        // Even if assignDocumentGroup runs BEFORE renameDocument inside a single transaction without
        // intermediate reload, renameDocument must NEVER revert group_name back to stale "旧杂项".
        db.withTransaction {
            db.assignDocumentGroup(
                id: "doc:whim-1",
                filePath: nil,
                groupName: "评测分析",
                fallbackTitle: "啃瓜的小浣熊",
                fallbackSyntax: "Markdown",
                fallbackContent: "# 评测看板数据口径梳理\n核心指标对齐。",
                reloadAfter: false
            )
            db.renameDocument(
                oldID: "doc:whim-1",
                oldFilePath: nil,
                newID: "doc:whim-1",
                newTitle: "评测看板数据口径梳理",
                newFilePath: nil,
                reloadAfter: false
            )
        }
        let pruned = db.pruneEmptyDocumentGroups(reloadAfter: false)
        db.reloadDocuments()
        
        let updated = try #require(db.documents.first(where: { $0.id == "doc:whim-1" }))
        #expect(updated.title == "评测看板数据口径梳理")
        #expect(updated.groupName == "评测分析")
        #expect(pruned.contains("旧杂项"))
        #expect(!db.documentGroups.contains("旧杂项"))
        #expect(db.documentGroups.contains("评测分析"))
    }
    
    
    // MARK: 13. Apple-Style Spacebar Quick Look Spatial Geometry & Interruptible Lifecycle
    
    @Test func quickLookSpatialGeometryAnchorsToSourceCardAndInterruptibleControllerReversesCleanly() async throws {
        let container = CGSize(width: 1280, height: 800)
        let compactSize = StarMapQuickLookGeometry.panelSize(in: container, isExpanded: false)
        let expandedSize = StarMapQuickLookGeometry.panelSize(in: container, isExpanded: true)
        #expect(compactSize.width == 780)
        #expect(compactSize.height == 580)
        #expect(expandedSize.width > compactSize.width)
        #expect(expandedSize.height > compactSize.height)
        
        // Left-top card anchors zoom origin directly over the source card (negative X/Y offset, card-matched scale).
        let leftCard = CGRect(x: 120, y: 150, width: 188, height: 50)
        let anchored = StarMapQuickLookGeometry.collapsedTransform(from: leftCard, panelSize: compactSize, in: container)
        #expect(anchored.offset.width < -350)
        #expect(anchored.offset.height < -180)
        #expect(anchored.scale >= 0.24 && anchored.scale <= 0.46)
        
        // Off-screen card clamps gracefully inside viewport margins instead of flying wildly off-screen.
        let farOffscreen = CGRect(x: -900, y: 2400, width: 188, height: 50)
        let clamped = StarMapQuickLookGeometry.collapsedTransform(from: farOffscreen, panelSize: compactSize, in: container)
        #expect(clamped.offset.width >= -(container.width * 0.5))
        #expect(clamped.offset.height <= (container.height * 0.5))
        
        // Missing anchor falls back to crisp Apple center-lift transform.
        let fallback = StarMapQuickLookGeometry.collapsedTransform(from: nil, panelSize: compactSize, in: container)
        #expect(fallback.offset.width == 0)
        #expect(fallback.scale == 0.88)
        
        // Drag offset stays reachable within window bounds.
        let extremeDrag = StarMapQuickLookGeometry.clampedDragOffset(
            CGSize(width: 5000, height: -5000),
            panelSize: compactSize,
            in: container
        )
        #expect(extremeDrag.width < 1000)
        #expect(extremeDrag.height > -500)
        
        // Interruptible presentation controller: open -> step -> close retains mountedID during retract -> rapid re-toggle cancels dismiss cleanly!
        let controller = StarMapQuickLookController()
        controller.open("doc:a", anchorRect: leftCard)
        #expect(controller.isOpen)
        #expect(controller.mountedID == "doc:a")
        
        controller.step(to: "doc:b")
        #expect(controller.isOpen)
        #expect(controller.mountedID == "doc:b")
        
        controller.close(animated: true)
        #expect(!controller.isOpen)
        #expect(controller.mountedID == "doc:b") // Retained for smooth retract animation!
        
        // Rapid Spacebar tap mid-retract smoothly reverses back open without unmounting!
        controller.toggle("doc:b")
        #expect(controller.isOpen)
        #expect(controller.mountedID == "doc:b")
        
        // Full animated close unmounts cleanly after retract window.
        controller.close(animated: true)
        try await Task.sleep(for: .milliseconds(StarMapQuickLookGeometry.dismissRetractDurationMs + 80))
        #expect(!controller.isOpen)
        #expect(controller.mountedID == nil)
    }
    
    
    // MARK: 14. Inline Image Stepless Zoom, Plain Text + Markdown Support & Categorized Context Menus
    
    @Test func inlineImagesSupportPlainTextAndMarkdownAndSteplessZoomHasZeroDeadZone() throws {
        // 1. Both Plain Text and Markdown allow inline images; unrelated code syntaxes stay excluded.
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: SyntaxName.none) == true)
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: "Plain Text") == true)
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: "Markdown") == true)
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: "markdown") == true)
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: "Swift") == false)
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: "Python") == false)
        #expect(PlainTextInlineImageStore.supportsInlineImages(syntaxName: "JSON") == false)
        
        // 2. Stepless zoom math: zero dead zone on pinch saturation & exact aspect preservation across ratios.
        let wideNatural = NSSize(width: 1200, height: 800)
        let bounds = InlineImageZoomMath.scaleBounds(naturalSize: wideNatural, containerWidth: 900)
        #expect(bounds.lowerBound < 0.5)
        #expect(bounds.upperBound > 1.8)
        
        // Over-pinch clamps scale strictly to achieved width ratio so the very first pinch-in shrinks immediately.
        let saturated = InlineImageZoomMath.transformForTargetScale(
            4.0,
            baseTransform: .identity,
            naturalSize: wideNatural,
            containerWidth: 900
        )
        #expect(abs(saturated.scale - bounds.upperBound) < 0.03)
        let saturatedW = try #require(saturated.customWidth)
        let afterOnePinchIn = InlineImageZoomMath.transformForMagnify(
            current: saturated,
            currentDrawSize: NSSize(width: saturatedW, height: saturated.customHeight ?? 400),
            naturalSize: wideNatural,
            factor: 0.9,
            containerWidth: 900
        )
        #expect((afterOnePinchIn.customWidth ?? saturatedW) < saturatedW)
        #expect(afterOnePinchIn.scale < saturated.scale)
        
        // Portrait & ultra-wide images preserve aspect ratio when scaled down without squishing.
        let portraitSize = InlineImageZoomMath.clampedAspectSize(
            desiredWidth: 90,
            naturalSize: NSSize(width: 300, height: 900),
            maxWidth: 800
        )
        #expect(abs((portraitSize.width / portraitSize.height) - (300.0 / 900.0)) < 0.02)
        
        let ultraWideSize = InlineImageZoomMath.clampedAspectSize(
            desiredWidth: 200,
            naturalSize: NSSize(width: 2000, height: 300),
            maxWidth: 800
        )
        #expect(abs((ultraWideSize.width / ultraWideSize.height) - (2000.0 / 300.0)) < 0.15)
        
        // Quick scale presets never emit duplicate labels even in tight panes.
        let tightBounds = InlineImageZoomMath.scaleBounds(naturalSize: wideNatural, containerWidth: 420)
        let tightPresets = InlineImageZoomMath.quickScalePresets(for: tightBounds, fitLabel: "适配宽")
        #expect(Set(tightPresets.map(\.label)).count == tightPresets.count)
        
        // 3. South-handle drag resize expands freely (regression for `maxYBound == startFrame.minY` collapse bug).
        let startFrame = NSRect(x: 20, y: 120, width: 300, height: 200)
        let expandedFrame = BoundingBoxResizeMath.aspectPreservingResizedFrame(
            startFrame: startFrame,
            naturalAspectRatio: 1.5,
            handle: .bottomRight,
            delta: NSPoint(x: 150, y: 100),
            minXBound: 8,
            minYBound: startFrame.minY - InlineImageZoomMath.maxCardHeight,
            maxXBound: 860,
            maxYBound: startFrame.minY + InlineImageZoomMath.maxCardHeight
        )
        #expect(expandedFrame.width > 420)
        #expect(expandedFrame.height > 280)
        
        // 4. End-to-end live stepless scale + inline image context menu zoom rail on EditorTextView.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot_r43_inline_zoom_\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let mdURL = tempDir.appending(path: "notes.md")
        try Data().write(to: mdURL)
        
        let img = NSImage(size: NSSize(width: 320, height: 200))
        img.lockFocus()
        NSColor.systemIndigo.setFill()
        NSRect(x: 0, y: 0, width: 320, height: 200).fill()
        img.unlockFocus()
        let stored = try #require(PlainTextInlineImageStore.shared.store(image: img, for: mdURL))
        let identifier = stored.token
            .replacingOccurrences(of: "⟦🖼 ", with: "")
            .replacingOccurrences(of: "⟧", with: "")
        
        let doc = Document()
        doc.fileURL = mdURL
        doc.setSyntax(name: "Markdown")
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 820, height: 500), textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        (textView.layoutManager as? LayoutManager)?.inlineImageDocumentURL = mdURL
        (textView.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages = true
        textView.insertInlineImageTokenCleanly(stored.token)
        
        let tokenRange = NSRange(location: 0, length: (stored.token as NSString).length)
        let scaled = textView.applyInlineImageSteplessScale(1.75, for: identifier, tokenRange: tokenRange)
        #expect(scaled.scale > 1.65)
        #expect((scaled.customWidth ?? 0) > 500)
        
        let reset = textView.applyInlineImageSteplessScale(1.0, for: identifier, tokenRange: tokenRange)
        #expect(reset.isIdentity == true)
        
        let imgMenu = textView.makeInlineImageContextMenu(for: identifier, tokenRange: tokenRange)
        #expect(imgMenu.items.contains(where: { $0.view is ContextMenuActionDockView }))
        #expect(imgMenu.items.contains(where: { $0.view is ContextMenuInlineImageZoomView }))
        
        // Read-only editor hides the editable live zoom rail cleanly.
        textView.isEditable = false
        let readOnlyImgMenu = textView.makeInlineImageContextMenu(for: identifier, tokenRange: tokenRange)
        #expect(!readOnlyImgMenu.items.contains(where: { $0.view is ContextMenuInlineImageZoomView }))
    }
    
    
    @Test func categorizedEditorContextMenuRespectsAllEdgeCasesAndMountsCleanly() {
        // Empty document edge case
        let emptyState = EditorContextMenuState(
            isEditable: true,
            isEmptyDocument: true,
            hasSelection: false,
            selectedCharacterCount: 0,
            canHighlightSelection: false,
            hasClipboardText: false,
            hasClipboardImage: false,
            supportsInlineImages: true,
            hasTable: false,
            splitPaneCount: 1,
            showsLineNumber: true,
            hasDocumentController: true
        )
        #expect(emptyState.canCut == false)
        #expect(emptyState.canCopy == false)
        #expect(emptyState.canPaste == false)
        #expect(emptyState.canSelectAll == false)
        #expect(emptyState.canCleanStructure == false)
        #expect(emptyState.canSemanticRestructure == false)
        #expect(emptyState.canInsertInlineImage == true)
        #expect(emptyState.butlerContextBadge(isEnglish: false) == "空文档")
        
        // Read-only document with active selection
        let readOnlySelected = EditorContextMenuState(
            isEditable: false,
            isEmptyDocument: false,
            hasSelection: true,
            selectedCharacterCount: 18,
            canHighlightSelection: true,
            hasClipboardText: true,
            hasClipboardImage: true,
            supportsInlineImages: true,
            hasTable: true,
            splitPaneCount: 2,
            showsLineNumber: false,
            hasDocumentController: true
        )
        #expect(readOnlySelected.canCut == false)
        #expect(readOnlySelected.canCopy == true)
        #expect(readOnlySelected.canPaste == false)
        #expect(readOnlySelected.showsHighlightBar == false)
        #expect(readOnlySelected.canCleanStructure == false)
        #expect(readOnlySelected.canSemanticRestructure == true)
        #expect(readOnlySelected.canInsertInlineImage == false)
        #expect(readOnlySelected.butlerContextBadge(isEnglish: false) == "18 字")
        
        // Clipboard image enables paste ONLY when inline images are supported (Plain Text / Markdown)
        let mdClipboardImg = EditorContextMenuState(
            isEditable: true,
            isEmptyDocument: true,
            hasSelection: false,
            selectedCharacterCount: 0,
            canHighlightSelection: false,
            hasClipboardText: false,
            hasClipboardImage: true,
            supportsInlineImages: true,
            hasTable: false,
            splitPaneCount: 1,
            showsLineNumber: true,
            hasDocumentController: true
        )
        #expect(mdClipboardImg.canPaste == true)
        #expect(mdClipboardImg.showsClipboardImageHint == true)
        
        let swiftClipboardImg = EditorContextMenuState(
            isEditable: true,
            isEmptyDocument: true,
            hasSelection: false,
            selectedCharacterCount: 0,
            canHighlightSelection: false,
            hasClipboardText: false,
            hasClipboardImage: true,
            supportsInlineImages: false,
            hasTable: false,
            splitPaneCount: 1,
            showsLineNumber: true,
            hasDocumentController: true
        )
        #expect(swiftClipboardImg.canPaste == false)
        #expect(swiftClipboardImg.canInsertInlineImage == false)
        
        // Mount & lay out all custom context menu rows cleanly with zero geometry collapse
        let dock = ContextMenuActionDockView(actions: [
            ContextMenuDockAction(title: "剪切", symbolName: "scissors", toolTip: "⌘X", isEnabled: true) {},
            ContextMenuDockAction(title: "拷贝", symbolName: "doc.on.doc", toolTip: "⌘C", isEnabled: true) {},
            ContextMenuDockAction(title: "粘贴", symbolName: "doc.on.clipboard", toolTip: "⌘V", isEnabled: true) {},
            ContextMenuDockAction(title: "全选", symbolName: "selection.pin.in.out", toolTip: "⌘A", isEnabled: true) {},
        ])
        dock.layoutSubtreeIfNeeded()
        #expect(dock.bounds.width == EditorContextMenuMetrics.menuWidth)
        #expect(dock.bounds.height == EditorContextMenuMetrics.dockHeight)
        
        let butlerRow = ContextMenuFeaturedActionRowView(
            title: "问总管",
            symbolName: "bubble.left.and.text.bubble.right",
            badgeText: "18 字"
        ) {}
        butlerRow.layoutSubtreeIfNeeded()
        #expect(butlerRow.bounds.height == EditorContextMenuMetrics.featuredRowHeight)
        
        let chips = ContextMenuChipStripView(chips: [
            ContextMenuChipAction(title: "翻译", symbolName: "character.bubble", isEnabled: true) {},
            ContextMenuChipAction(title: "总结", symbolName: "text.alignleft", isEnabled: true) {},
            ContextMenuChipAction(title: "解释", symbolName: "lightbulb", isEnabled: true) {},
        ])
        chips.layoutSubtreeIfNeeded()
        #expect(chips.bounds.height == EditorContextMenuMetrics.chipStripHeight)
        
        let doc = Document()
        let textView = EditorTextView(textStorage: doc.textStorage, lineEndingScanner: doc.lineEndingScanner)
        textView.string = "Alpha\nBeta\n"
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        let menu = textView.makeContextMenu()
        #expect(menu.items.first?.view is ContextMenuActionDockView)
        #expect(menu.minimumWidth == EditorContextMenuMetrics.menuWidth)
    }
    
    
    // MARK: 15. High-Precision Series Merging (`cot优化roadmap 7` + `CoTEditor Roadmap 3`) & Title-Group Coherence
    
    @Test func oneClickOrganizeMergesLongSameSeriesRoadmapsAndEnforcesTitleGroupCoherence() async throws {
        let now = Date()
        let longRoadmap7Body = "# CotEditor 优化 Roadmap 7\n"
            + String(repeating: "性能优化、右键菜单升级、无极缩放修复与评测看板展示案例。\n", count: 360)
        let longRoadmap3Body = "# CoTEditor Roadmap 3\n"
            + String(repeating: "文档星图重构、双指缩放与空格预览演进里程碑。\n", count: 220)
        let aimeBoardBody = "# AIME 评测看板与归因优化\n"
            + String(repeating: "badcase 聚类、误报率统计与大盘口径校准。\n", count: 400)
        let aimeStatsBody = "# AIME 数据梳理与统计\n梳理全量 cases_aime.jsonl 统计口径与去重逻辑。"
        
        // Verify sizes match the real 11K / 6.2K / 13K char scale from user's workspace!
        #expect(longRoadmap7Body.count > 10_000)
        #expect(longRoadmap3Body.count > 5_000)
        
        // 1. Entity stem & series detection recognizes `cot` <-> `CoTEditor` + `roadmap` across version numbers.
        let sig7 = OrganizeTopicSignature.extract(title: "cot优化roadmap 7", content: longRoadmap7Body, isUntitled: false)
        let sig3 = OrganizeTopicSignature.extract(title: "CoTEditor Roadmap 3", content: longRoadmap3Body, isUntitled: false)
        #expect(sig7.titleProjectStems.contains("cot"))
        #expect(sig3.titleProjectStems.contains("cot"))
        #expect(sig7.artifactRole == "roadmap")
        #expect(sig3.artifactRole == "roadmap")
        #expect(OrganizeTopicSignature.isSameSeries(sig7, sig3) == true)
        
        // Guardrail: Distinct dated reports NEVER falsely merge even with shared project stem.
        let reportA = OrganizeTopicSignature.extract(title: "AIME 周报 2026-11-18", content: "第46周总结", isUntitled: false)
        let reportB = OrganizeTopicSignature.extract(title: "AIME 周报 2026-11-25", content: "第47周总结", isUntitled: false)
        #expect(OrganizeTopicSignature.isSameSeries(reportA, reportB) == false)
        
        // 2. Full organize pipeline merges the 11K + 6.2K roadmaps into ONE clean doc in `cot优化`,
        //    never leaves `cot优化roadmap 7` stranded inside `评测与数据`, and preserves AIME docs separately!
        let inputs: [OrganizeFunnelInput] = [
            OrganizeFunnelInput(
                id: "doc:aime-board",
                dbRecordID: "doc:aime-board",
                title: "AIME 评测看板与归因优化",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "评测与数据",
                content: aimeBoardBody,
                updatedAt: now,
                isOpenNow: true,
                isUntitled: false
            ),
            OrganizeFunnelInput(
                id: "doc:cot-r7",
                dbRecordID: "doc:cot-r7",
                title: "cot优化roadmap 7",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "评测与数据", // Misplaced initially, just like screenshot!
                content: longRoadmap7Body,
                updatedAt: now.addingTimeInterval(-180),
                isOpenNow: false,
                isUntitled: false
            ),
            OrganizeFunnelInput(
                id: "doc:aime-stats",
                dbRecordID: "doc:aime-stats",
                title: "AIME 数据梳理与统计",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "评测与数据",
                content: aimeStatsBody,
                updatedAt: now.addingTimeInterval(-5 * 86_400),
                isOpenNow: false,
                isUntitled: false
            ),
            OrganizeFunnelInput(
                id: "doc:cot-r3",
                dbRecordID: "doc:cot-r3",
                title: "CoTEditor Roadmap 3",
                filePath: nil,
                syntax: "Markdown",
                currentGroup: "cot优化",
                content: longRoadmap3Body,
                updatedAt: now.addingTimeInterval(-3600),
                isOpenNow: true,
                isUntitled: false
            ),
        ]
        
        let plan = await DocumentOrganizeFunnel.runFullPipeline(
            items: inputs,
            existingGroups: ["评测与数据", "cot优化"],
            allowRemoteAI: false
        )
        
        // The two CotEditor roadmaps MUST merge into 1 cluster with clean version-stripped title & `cot优化` group!
        let cotCluster = try #require(plan.funnel.mergeClusters.first(where: { cluster in
            let allIDs = Set([cluster.primary.id] + cluster.duplicates.map(\.id))
            return allIDs.contains("doc:cot-r7") && allIDs.contains("doc:cot-r3")
        }))
        #expect(cotCluster.bestGroup == "cot优化")
        #expect(!cotCluster.bestTitle.hasSuffix("7"))
        #expect(!cotCluster.bestTitle.hasSuffix("3"))
        #expect(cotCluster.mergedContent.contains("无极缩放修复"))
        #expect(cotCluster.mergedContent.contains("空格预览演进里程碑"))
        
        let cotAssignment = try #require(plan.assignments.first(where: { $0.id == cotCluster.primary.id }))
        #expect(cotAssignment.group == "cot优化")
        
        // 3. Title-group coherence reconciler pulls a misgrouped doc into its matching active group automatically.
        let misgrouped = [
            DocumentCenterAgentOrganizer.Assignment(id: "doc:cot-r7", group: "评测与数据", suggestedTitle: nil),
            DocumentCenterAgentOrganizer.Assignment(id: "doc:cot-r3", group: "cot优化", suggestedTitle: nil),
            DocumentCenterAgentOrganizer.Assignment(id: "doc:aime-board", group: "评测与数据", suggestedTitle: nil),
        ]
        let survivorMap = Dictionary(uniqueKeysWithValues: inputs.map { ($0.id, $0) })
        let reconciled = DocumentOrganizeFunnel.reconcileTitleGroupCoherence(misgrouped, survivorByID: survivorMap)
        let fixedR7 = try #require(reconciled.first(where: { $0.id == "doc:cot-r7" }))
        #expect(fixedR7.group == "cot优化")
        
        // 4. Smart manual merge candidate ranking puts `CoTEditor Roadmap 3` #1 with "同系列" badge for `cot优化roadmap 7`!
        let rankedTargets = OrganizeTopicSignature.rankedMergeCandidates(for: inputs[1], in: inputs)
        #expect(rankedTargets.first?.item.id == "doc:cot-r3")
        #expect(rankedTargets.first?.badge == "同系列")
    }
    
    
    // MARK: 16. Deep Substance Hollow-Doc Purge, Workstream Discovery, AI Delete Guardrails & Lossless Synthesis
    
    @Test func oneClickOrganizePurgesTitleOnlyAndEmptyTemplatesAndProtectsRealNotes() {
        // 1. Title-only / empty-template / title-echo scratch docs MUST be classified as junk.
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "啃瓜的小浣熊", content: "# 新版星图设计方案\n") == .titleOnly)
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "架构重构计划", content: "架构重构计划") == .titleOnly)
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "晚风的熊猫", content: "文档中心重构方案") == .titleOnly)
        
        let longEmptyTemplate = """
        # Q4 架构升级方案

        ## 一、背景
        待补充

        ## 二、目标
        - [ ] 
        - [ ] 待定

        ## 三、里程碑排期
        | 阶段 | 负责人 | 截止日期 |
        |---|---|---|
        | | | |
        | TBD | 暂无 | 待填写 |
        """
        #expect(longEmptyTemplate.count > 120)
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "Q4 架构升级方案", content: longEmptyTemplate) == .emptyTemplate)
        
        // 2. Real concise notes, URLs, code, populated tables, and saved disk files MUST be preserved.
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "啃瓜的小浣熊", content: "明天下午3点找张三对齐接口") == nil)
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "啃瓜的小浣熊", content: "https://github.com/coteditor/CotEditor") == nil)
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "啃瓜的小浣熊", content: "import Foundation\nfunc run() { print(1) }") == nil)
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "readme.md", content: "# Project Title", filePath: "/tmp/readme.md") == nil)
        
        let populatedTable = """
        | 模块 | 耗时 |
        |---|---|
        | StarMap | 12ms |
        """
        #expect(DocumentOrganizeFunnel.classifyJunk(title: "性能数据", content: populatedTable) == nil)
    }
    
    
    @Test func aiDeleteValidationAndLosslessSynthesisGuardrailsAnd30DocWorkspaceOrganize() async throws {
        let now = Date()
        
        // 1. Parse AI JSON with deletes + merges + assignments, then enforce strict delete guardrails.
        let aiJSON = """
        {
          "deletes": [
            {"id": "d-stub", "reason": "未展开的临时占位"},
            {"id": "d-real", "reason": "误删测试"},
            {"id": "d-file", "reason": "误删磁盘文件"}
          ],
          "merges": [],
          "assignments": [
            {"id": "d-real", "group": "CotEditor 研发", "suggestedTitle": "星图性能调优记录"}
          ]
        }
        """
        let parsed = try #require(DocumentCenterAgentOrganizer.parsePlan(from: aiJSON, validIDs: ["d-stub", "d-real", "d-file"]))
        #expect(parsed.deletes.count == 3)
        
        let guardDocs: [OrganizeFunnelInput] = [
            OrganizeFunnelInput(id: "d-stub", dbRecordID: "d-stub", title: "想法", filePath: nil, syntax: "Markdown", currentGroup: "", content: "回头想想怎么做。", updatedAt: now, isOpenNow: false, isUntitled: false),
            OrganizeFunnelInput(id: "d-real", dbRecordID: "d-real", title: "笔记1", filePath: nil, syntax: "Markdown", currentGroup: "", content: String(repeating: "星图布局渲染耗时从 48ms 压降到 11ms，缓存命中率提升至 96%。\n", count: 6), updatedAt: now, isOpenNow: false, isUntitled: false),
            OrganizeFunnelInput(id: "d-file", dbRecordID: "d-file", title: "stub.md", filePath: "/tmp/stub.md", syntax: "Markdown", currentGroup: "", content: "回头想想。", updatedAt: now, isOpenNow: false, isUntitled: false),
        ]
        let baseFunnel = OrganizeFunnelStageResult(junkToDelete: [], mergeClusters: [], survivors: guardDocs)
        let deleteOutcome = DocumentOrganizeFunnel.applyValidatedAIDeletes(
            parsed.deletes,
            baseFunnel: baseFunnel,
            rawAssignments: parsed.assignments
        )
        // Sparse stub IS deleted with AI's reason; substantive doc & saved disk file are strictly protected!
        #expect(deleteOutcome.funnel.junkToDelete.map(\.item.id) == ["d-stub"])
        #expect(deleteOutcome.funnel.junkToDelete.first?.displayReason == "未展开的临时占位")
        #expect(Set(deleteOutcome.funnel.survivors.map(\.id)) == ["d-real", "d-file"])
        
        // 2. Weak scratch titles are recognized while real user titles & saved files stay untouched.
        #expect(DocumentCenterAgentOrganizer.isWeakScratchTitle("笔记1", hasFilePath: false))
        #expect(DocumentCenterAgentOrganizer.isWeakScratchTitle("方案 2", hasFilePath: false))
        #expect(DocumentCenterAgentOrganizer.isWeakScratchTitle("想法", hasFilePath: false))
        #expect(!DocumentCenterAgentOrganizer.isWeakScratchTitle("AIME r533 重评方案", hasFilePath: false))
        #expect(!DocumentCenterAgentOrganizer.isWeakScratchTitle("笔记1", hasFilePath: true))
        
        // 3. Multi-section AI dossier includes full body for short docs and head/mid/tail for long docs.
        let longBody = "HEAD_ANCHOR " + String(repeating: "中间迭代讨论内容。", count: 160) + " TAIL_ANCHOR"
        let dossier = OrganizeDocumentAnalyzer.buildAIDossier(
            for: OrganizeFunnelInput(id: "d-long", dbRecordID: "d-long", title: "长文档", filePath: nil, syntax: "Markdown", currentGroup: "", content: longBody, updatedAt: now, isOpenNow: false, isUntitled: false),
            index: 1,
            totalInBatch: 30,
            bloatedGroups: []
        )
        #expect(dossier.contains("HEAD_ANCHOR"))
        #expect(dossier.contains("[中段]"))
        #expect(dossier.contains("TAIL_ANCHOR"))
        
        // 4. Lossless synthesis factual-retention verifier accepts faithful merges and rejects fact loss.
        let baseline = """
        # AIME r533 重评与聚类回写
        - aime_expert 合并后 157,601 条，verify.json errors=0。
        - aime_fast 合并后 460,501 条，产物写入 /mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval_reeval_r533/。
        - 内存峰值 10.5 GB，oom_kill 计数 23。
        """
        let goodSynth = """
        以下是合并后的文档：
        # AIME r533 重评与聚类回写
        本次 r533 重评产物写入 /mnt/aime_eval_ssd/1_aime/eval_output/0_daily_eval_reeval_r533/，verify.json 校验 errors=0：
        - aime_expert：157,601 条；aime_fast：460,501 条。
        - 资源监控：内存峰值 10.5 GB，oom_kill 23 次。
        """
        let validated = try #require(OrganizeDocumentAnalyzer.validateSynthesizedContent(goodSynth, localBaseline: baseline))
        #expect(!validated.hasPrefix("以下是合并"))
        #expect(validated.contains("157,601"))
        #expect(validated.contains("460,501"))
        
        let lossySummary = "本次重评已完成，整体运行正常，无报错。"
        #expect(OrganizeDocumentAnalyzer.validateSynthesizedContent(lossySummary, localBaseline: baseline) == nil)
        
        // 5. Realistic 30-document messy workspace: hollow docs purged, untitled + named same-series docs merged,
        //    weak scratch titles renamed, and workstream groups discovered from inside content!
        var workspace: [OrganizeFunnelInput] = [
            // 6 meaningless/hollow docs (MUST ALL BE DELETED)
            .init(id: "j1", dbRecordID: "j1", title: "啃瓜的小浣熊", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# 新建想法\n", updatedAt: now, isOpenNow: false, isUntitled: true),
            .init(id: "j2", dbRecordID: "j2", title: "项目规划", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "项目规划", updatedAt: now, isOpenNow: false, isUntitled: false),
            .init(id: "j3", dbRecordID: "j3", title: "晚风的熊猫", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# 周会模板\n## 议题\n待补充\n## 结论\n- [ ] \n", updatedAt: now, isOpenNow: false, isUntitled: true),
            .init(id: "j4", dbRecordID: "j4", title: "泡茶的烤冷面", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "文档中心优化方案", updatedAt: now, isOpenNow: false, isUntitled: true),
            .init(id: "j5", dbRecordID: "j5", title: "test", filePath: nil, syntax: "Plain Text", currentGroup: "技术笔记", content: "asdfghjkl", updatedAt: now, isOpenNow: false, isUntitled: true),
            .init(id: "j6", dbRecordID: "j6", title: "空白", filePath: nil, syntax: "Plain Text", currentGroup: "技术笔记", content: "   \n---\n   ", updatedAt: now, isOpenNow: false, isUntitled: true),
            // CotEditor same-series iterations (including an UNTITLED scratch doc whose H1 is `# CotEditor Roadmap 5`!)
            .init(id: "c1", dbRecordID: "c1", title: "CoTEditor Roadmap 3", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# CoTEditor Roadmap 3\n完成星图双指缩放与空格 Quick Look 交互体验升级。", updatedAt: now.addingTimeInterval(-900), isOpenNow: false, isUntitled: false),
            .init(id: "c2", dbRecordID: "c2", title: "cot优化roadmap 7", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# CotEditor 优化 Roadmap 7\n升级文档中心一键整合，清理仅标题文档并按工作主线自动归组。", updatedAt: now.addingTimeInterval(-300), isOpenNow: false, isUntitled: false),
            .init(id: "c3", dbRecordID: "c3", title: "口袋里的风铃", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# CotEditor Roadmap 5\n补齐右键菜单无极缩放与内联图片尺寸持久化能力。", updatedAt: now.addingTimeInterval(-600), isOpenNow: false, isUntitled: true),
            .init(id: "c4", dbRecordID: "c4", title: "CotEditor 内联图片缩放记录", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# CotEditor 内联图片缩放记录\n记录 EditorTextView 双指手势缩放与边界拖拽数学推导。", updatedAt: now, isOpenNow: false, isUntitled: false),
            .init(id: "c5", dbRecordID: "c5", title: "CotEditor 表格对齐协议", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# CotEditor 表格对齐协议\n基于 NSLayoutManager 实测列宽对齐到像素级 Tab Stop。", updatedAt: now, isOpenNow: false, isUntitled: false),
            // AIME workstream docs (including overlapping r533 fragments)
            .init(id: "a1", dbRecordID: "a1", title: "笔记1", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# AIME r533 重评与回写\n第一批重评 4.5 万条覆盖 aime_fast 与 aime_expert，写入 0_daily_eval_reeval_r533。", updatedAt: now.addingTimeInterval(-500), isOpenNow: false, isUntitled: false),
            .init(id: "a2", dbRecordID: "a2", title: "写诗的柴犬", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# AIME r533 增量聚类核对\naime_fast 460,501 与 aime_expert 157,601 均通过 verify.json 校验，待回写 0_daily_eval_reeval_r533。", updatedAt: now.addingTimeInterval(-200), isOpenNow: false, isUntitled: true),
            .init(id: "a3", dbRecordID: "a3", title: "AIME Badcase 归因分析", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# AIME Badcase 归因分析\n统计误报率下降幅度并抽检高优 badcase 类别分布。", updatedAt: now, isOpenNow: false, isUntitled: false),
            .init(id: "a4", dbRecordID: "a4", title: "AIME 数据大盘口径文档", filePath: nil, syntax: "Markdown", currentGroup: "技术笔记", content: "# AIME 数据大盘口径文档\n明确日活 trace 去重规则与新旧口径切换日期。", updatedAt: now, isOpenNow: false, isUntitled: false),
        ]
        // Add 15 more realistic distinct docs across Weekly/Meetings/Infra to hit exactly 30 documents.
        let extraTopics: [(id: String, title: String, content: String)] = [
            ("w1", "2026-11-18 周报", "# 2026-11-18 周报\n本周完成权限中心联调与接口压测。"),
            ("w2", "2026-11-25 周报", "# 2026-11-25 周报\n本周上线文档星图与表格对齐能力。"),
            ("w3", "下周排期与待办清单", "# 下周排期与待办清单\n整理核心里程碑与风险点 todo。"),
            ("m1", "周三产品评审会议纪要", "# 周三产品评审会议纪要\n对齐深浅色对比度与弹窗交互细节。"),
            ("m2", "周五架构评审例会纪要", "# 周五架构评审例会纪要\n确定 SQLite 批量事务提交方案。"),
            ("m3", "客户端性能专项同步会", "# 客户端性能专项同步会\n评审帧率监控与内存占用基线。"),
            ("p1", "权限中心 RBAC 设计方案", "# 权限中心 RBAC 设计方案\n规划多租户角色继承与菜单权限隔离。"),
            ("p2", "权限中心审批流接口文档", "# 权限中心审批流接口文档\n定义回调签名、幂等键与重试策略。"),
            ("p3", "权限中心灰度发布清单", "# 权限中心灰度发布清单\n按租户分批放量并监控鉴权延迟。"),
            ("s1", "部署脚本与 Docker 配置", "import Foundation\nfunc deployWorker() { /* docker compose 发布脚本 */ }"),
            ("s2", "压测环境 Nginx 调优参数", "# Nginx 调优\n调整 keepalive_timeout 与 worker_connections 应对高并发。"),
            ("s3", "SQLite 索引优化备忘", "# SQLite 索引优化\n为 documents(group_name, updated_at) 建立复合索引。"),
            ("r1", "方案2", "# 新手引导精简方案\n去掉冗余浮层，直接通过空间层级传达交互。"),
            ("r2", "想法", "# 快捷键面板检索优化\n支持拼音首字母与命令模糊匹配。"),
            ("r3", "读书摘录：信息架构原则", "# 信息架构原则\n按用户心智任务组织层级，避免按文件类型机械切分。"),
        ]
        for entry in extraTopics {
            workspace.append(.init(
                id: entry.id,
                dbRecordID: entry.id,
                title: entry.title,
                filePath: nil,
                syntax: entry.id == "s1" ? "Swift" : "Markdown",
                currentGroup: "技术笔记",
                content: entry.content,
                updatedAt: now,
                isOpenNow: false,
                isUntitled: DocumentCenterAgentOrganizer.isGenericUntitled(entry.title, hasFilePath: false)
            ))
        }
        #expect(workspace.count == 30)
        
        let plan = await DocumentOrganizeFunnel.runFullPipeline(
            items: workspace,
            existingGroups: ["技术笔记"],
            allowRemoteAI: false
        )
        
        // All 6 hollow/meaningless docs purged automatically!
        #expect(Set(plan.funnel.junkToDelete.map(\.item.id)) == ["j1", "j2", "j3", "j4", "j5", "j6"])
        
        // All 3 CotEditor roadmaps (including the untitled "口袋里的风铃"!) merged into ONE clean cluster!
        let cotRoadmapCluster = try #require(plan.funnel.mergeClusters.first { cluster in
            let ids = Set([cluster.primary.id] + cluster.duplicates.map(\.id))
            return ids.contains("c1") && ids.contains("c2") && ids.contains("c3")
        })
        #expect(cotRoadmapCluster.mergedContent.contains("双指缩放"))
        #expect(cotRoadmapCluster.mergedContent.contains("一键整合"))
        #expect(cotRoadmapCluster.mergedContent.contains("无极缩放"))
        
        // AIME r533 fragments merged into 1!
        #expect(plan.funnel.mergeClusters.contains { cluster in
            let ids = Set([cluster.primary.id] + cluster.duplicates.map(\.id))
            return ids.contains("a1") && ids.contains("a2")
        })
        
        // Weak scratch titles ("方案2", "想法") upgraded to crisp content-accurate titles!
        let r1Assign = try #require(plan.assignments.first(where: { $0.id == "r1" }))
        let r2Assign = try #require(plan.assignments.first(where: { $0.id == "r2" }))
        #expect(r1Assign.suggestedTitle == "新手引导精简方案")
        #expect(r2Assign.suggestedTitle == "快捷键面板检索优化")
        
        // Monolithic "技术笔记" cleanly decomposed into real workstreams (CotEditor, AIME, 权限中心, etc.) within target budget!
        let finalGroupSet = Set(plan.assignments.map(\.group))
        #expect(finalGroupSet.count >= 3 && finalGroupSet.count <= DocumentOrganizeFunnel.targetMaxGroups(for: plan.assignments.count))
        #expect(finalGroupSet.contains(where: { $0.lowercased().contains("cot") }))
        #expect(finalGroupSet.contains(where: { $0.lowercased().contains("aime") }))
    }
    
    
    // MARK: 17. Butler Tab Conversion Crash Fix, Zero-Loss Backing Doc Persistence & Refined Market/Podcast Boards
    
    @Test func butlerTabConversionMountsWithoutAttributeGraphRecursionAndPreservesBackingDraft() throws {
        // 1. Butler tab icon uses clean restrained SF Symbol (never cliché "sparkles").
        #expect(PaneBoardKind.butler.symbolName != "sparkles")
        
        // 2. PaneBoardControllerModel.setStateFromHost never triggers re-entrant onStateChanged echo loops.
        let model = PaneBoardControllerModel(state: PaneBoardState(kind: .butler, query: "初始问题"))
        var echoCount = 0
        model.onStateChanged = { _ in echoCount += 1 }
        model.setStateFromHost(PaneBoardState(kind: .butler, query: "宿主刷新"))
        #expect(echoCount == 0)
        #expect(model.state.query == "宿主刷新")
        model.state.query = "用户修改"
        #expect(echoCount == 1)
        
        // 3. Mounting & repeatedly updating PaneBoardHostView in `.butler` mode inside NSHostingView
        //    must NEVER stack-overflow in SwiftUI's AG::LayoutDescriptor::compare_heap_objects.
        let hostView = PaneBoardHostView(
            model: model,
            onRevertToDocument: {},
            onOpenNote: { _, _ in }
        )
        let hosting = NSHostingView(rootView: hostView)
        hosting.frame = NSRect(x: 0, y: 0, width: 820, height: 540)
        hosting.layoutSubtreeIfNeeded()
        model.setStateFromHost(PaneBoardState(kind: .market, query: "NVDA"))
        hosting.layoutSubtreeIfNeeded()
        model.setStateFromHost(PaneBoardState(kind: .podcast, query: "大模型训练"))
        hosting.layoutSubtreeIfNeeded()
        model.setStateFromHost(PaneBoardState(kind: .butler, query: "再次切回总管"))
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.bounds.width == 820)
        #expect(hosting.bounds.height == 540)
        
        // 4. BeautifulAgentWebView conforms to Equatable without storing closure graphs.
        let ctrl = BeautifulAgentWebController()
        let baseState = BeautifulAgentHostStatePayload(
            mode: "butler",
            isDark: false,
            locale: "zh",
            botName: "总管",
            botNickname: "butler",
            botAvatarDataURL: nil,
            piAvailable: false,
            piStatusLabel: nil,
            isPinnedPanel: false,
            isDockedPane: true,
            showSidebar: true,
            sessions: [],
            activeSessionID: "s1",
            messages: [],
            isStreaming: false,
            streamingStatusLabel: nil,
            errorMessage: nil,
            placeholder: "Ask",
            greetingName: "Test",
            greetingSubtitle: nil,
            articleTitle: nil,
            articleSource: nil,
            quotedExcerpt: nil,
            availableModels: [],
            selectedModelID: "m1",
            selectedModelTitle: "m1",
            effort: nil,
            suggestions: [],
            contextSources: [],
            slashCommands: []
        )
        let v1 = BeautifulAgentWebView(state: baseState, controller: ctrl, callbacks: .init(), cornerRadius: 0)
        let v2 = BeautifulAgentWebView(state: baseState, controller: ctrl, callbacks: .init(), cornerRadius: 0)
        #expect(v1 == v2)
        
        // 5. Unsaved backing document persisted before converting to a board tab is cleanly recoverable from SQLite.
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-board-draft-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "drafts.sqlite3"))
        let docID = "doc:unsaved-before-butler"
        db.saveDocument(
            id: docID,
            title: "核心草稿文档",
            filePath: nil,
            syntax: "Markdown",
            content: "# 核心草稿\n这是一份尚未保存到磁盘但绝不能丢失的重要内容。",
            groupName: ""
        )
        let recovered = try #require(db.fetchDocumentRecord(id: "unsaved-before-butler", filePath: nil))
        #expect(recovered.title == "核心草稿文档")
        #expect(recovered.content.contains("绝不能丢失的重要内容"))
    }
    
    
    @Test func localDatabaseInspectorReportsStorageTablesTokensAndMasksSecrets() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-db-inspector-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "vault.sqlite3"))
        db.saveDocument(
            id: "doc:inspect-1",
            title: "数据库架构设计",
            filePath: nil,
            syntax: "Markdown",
            content: "# 数据库设计\n所有用户资产统一持久化到本地 SQLite 文件中，方便随时跨机迁移。",
            groupName: "架构"
        )
        db.set("sk-secret-api-key-value", forKey: CotLocalDatabase.ConfigKey.syncAIProfileAPIKeys)
        db.executeSQL("""
        INSERT INTO ai_usage_events (date_key, timestamp, feature, model, provider, input_tokens, output_tokens, latency_ms, success)
        VALUES ('2026-11-25', 1795610000, 'butler_chat', 'claude-sonnet-4', 'anthropic', 1200, 480, 920, 1);
        INSERT INTO ai_usage_events (date_key, timestamp, feature, model, provider, input_tokens, output_tokens, latency_ms, success)
        VALUES ('2026-11-25', 1795610600, 'organize', 'gpt-4.1', 'openai', 2400, 620, 1180, 1);
        """)
        
        let snapshot = db.inspectDatabaseSnapshot()
        #expect(snapshot.totalBytes > 0)
        #expect(snapshot.tables.count >= 15)
        #expect(snapshot.tables.contains(where: { $0.name == "documents" && $0.rowCount == 1 }))
        #expect(snapshot.tables.contains(where: { $0.name == "ai_usage_events" && $0.rowCount == 2 }))
        #expect(snapshot.assets.activeDocuments == 1)
        #expect(snapshot.tokenSummary.totalRequests == 2)
        #expect(snapshot.tokenSummary.totalInputTokens == 3600)
        #expect(snapshot.tokenSummary.totalOutputTokens == 1100)
        #expect(snapshot.tokenSummary.totalTokens == 4700)
        #expect(snapshot.tokenSummary.byModel.count == 2)
        #expect(snapshot.tokenSummary.byFeature.count == 2)
        #expect(snapshot.tokenSummary.dailyTrend.count == 1)
        #expect(snapshot.tokenSummary.recentEvents.count == 2)
        
        // Table preview masks sensitive API keys and rejects unknown/malicious table names safely
        let configPreview = db.inspectTablePreview(tableName: "configs", limit: 50)
        let keyIdx = try #require(configPreview.columns.firstIndex(of: "key"))
        let valIdx = try #require(configPreview.columns.firstIndex(of: "value"))
        let secretRow = try #require(configPreview.rows.first(where: { $0[keyIdx] == CotLocalDatabase.ConfigKey.syncAIProfileAPIKeys }))
        #expect(secretRow[valIdx] == "••••••••")
        
        let invalidPreview = db.inspectTablePreview(tableName: "documents; DROP TABLE documents;", limit: 10)
        #expect(invalidPreview.rows.isEmpty)
        #expect(db.inspectDatabaseSnapshot().assets.activeDocuments == 1)
        
        // Compact succeeds without losing data
        _ = db.compactDatabase()
        #expect(db.inspectDatabaseSnapshot().assets.activeDocuments == 1)
        
        // Sidebar item exists and view mounts cleanly
        #expect(SidebarSettingsItem.allCases.contains(.database))
        #expect(!SidebarSettingsItem.database.title.contains("与"))
        #expect(NSImage(systemSymbolName: SidebarSettingsItem.database.symbolName, accessibilityDescription: nil) != nil)
        
        let host = NSHostingView(rootView: LocalDatabaseSettingsView(onExportDatabase: {}, onImportDatabase: {}))
        host.frame = NSRect(x: 0, y: 0, width: 575, height: 520)
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.width == 575)
    }
    
    
    @Test func butlerMeetingRoomSupportsStandupDirectAtUpdatesAndButlerGovernanceInIsolation() async throws {
        // 1. Natural language & slash triggers from normal Butler chat
        #expect(MeetingRoomRouter.isMeetingTriggerInButlerChat("汇总一下信息"))
        #expect(MeetingRoomRouter.isMeetingTriggerInButlerChat("/meeting 今天复盘"))
        #expect(!MeetingRoomRouter.isMeetingTriggerInButlerChat("帮我解释一下 Swift concurrency"))
        
        // 2. Routing modes: all-hands standup, direct @Bot callout with refresh, and Butler governance
        let enabled = AIBotID.allCases
        let standupPlan = MeetingRoomRouter.parsePrompt(
            "汇总一下今天的信息",
            availableBots: enabled,
            activeTodayBots: [.translate]
        )
        if case .allHandsStandup(let participants) = standupPlan.mode {
            #expect(participants.contains(.organizeAndMerge))
            #expect(participants.contains(.persona))
            #expect(participants.contains(.translate))
            #expect(!participants.contains(.butler))
        } else {
            Issue.record("Expected allHandsStandup mode")
        }
        
        let directPlan = MeetingRoomRouter.parsePrompt(
            "@整理 更新一下当前文档状态",
            availableBots: enabled
        )
        #expect(directPlan.mode == .directCallout(targets: [.organizeAndMerge], shouldRefresh: true))
        
        let govPlan = MeetingRoomRouter.parsePrompt(
            "@总管 让整理师和周报搭子更新一下",
            availableBots: enabled
        )
        if case .butlerGoverned(let subs, let shouldRefresh) = govPlan.mode {
            #expect(shouldRefresh)
            #expect(subs.contains(.organizeAndMerge))
            #expect(subs.contains(.weeklyReport))
        } else {
            Issue.record("Expected butlerGoverned mode")
        }
        
        // 3. End-to-end Meeting Room execution stays 100% isolated from butler_messages
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "cot-meeting-room-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "meeting.sqlite3"))
        db.saveDocument(
            id: "doc:standup-1",
            title: "今日会议室开发记录",
            filePath: nil,
            syntax: "Markdown",
            content: "# 会议室\n完成了独立 Meeting Room 与总管统筹调度。",
            groupName: "工程"
        )
        let manager = ButlerMeetingRoomManager(database: db)
        
        // All-hands standup
        await manager.submitPrompt("汇总一下今天的信息", allowRemoteAI: false)
        let botReplies = manager.messages.filter { $0.role == "bot" }
        #expect(botReplies.count >= 4)
        #expect(botReplies.last?.botID == AIBotID.butler.rawValue)
        #expect(db.inspectDatabaseSnapshot().assets.butlerMessages == 0)
        
        // Direct @Bot refresh callout
        let beforeCount = manager.messages.count
        await manager.submitPrompt("@观察 更新一下对我的印象", allowRemoteAI: false)
        let added = Array(manager.messages.dropFirst(beforeCount))
        let addedBots = added.filter { $0.role == "bot" }
        #expect(addedBots.count == 1)
        #expect(addedBots[0].botID == AIBotID.persona.rawValue)
        #expect(!addedBots[0].receipts.isEmpty)
        
        // Butler governance: user manages Butler, Butler dispatches subordinate and wraps up
        let beforeGov = manager.messages.count
        await manager.submitPrompt("@总管 让整理师更新一下", allowRemoteAI: false)
        let govBots = manager.messages.dropFirst(beforeGov).filter { $0.role == "bot" }
        #expect(govBots.count == 2)
        #expect(govBots[0].botID == AIBotID.organizeAndMerge.rawValue)
        #expect(govBots[0].delegatedFromButler == true)
        #expect(!govBots[0].receipts.isEmpty)
        #expect(govBots[1].botID == AIBotID.butler.rawValue)
        
        // Persistence survives reload in its own isolated config key
        let reloaded = ButlerMeetingRoomManager(database: db)
        #expect(reloaded.messages.count == manager.messages.count)
    }
}
