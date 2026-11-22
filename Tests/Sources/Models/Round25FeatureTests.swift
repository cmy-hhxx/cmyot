//
//  Round25FeatureTests.swift
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

@MainActor
struct Round25FeatureTests {
    
    // MARK: 1. Settings Fixed Proportion & Non-Resizability
    
    @Test func settingsWindowIsFixedSizeNonResizable780x560() throws {
        
        let controller = SidebarSettingsWindowController()
        let window = try #require(controller.window)
        
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.zoomButton)?.isEnabled == false)
        #expect(abs(window.frame.width - 780) <= 2)
        #expect(abs(window.frame.height - 560) <= 2)
        #expect(abs(window.contentLayoutRect.width - 780) <= 2)
        #expect(abs(window.contentMinSize.width - 780) <= 2)
        #expect(abs(window.contentMaxSize.width - 780) <= 2)
        #expect(abs(window.contentMinSize.height - 560) <= 2)
        #expect(abs(window.contentMaxSize.height - 560) <= 2)
        #expect(window.minSize == window.maxSize)
        
        window.close()
    }
    
    
    // MARK: 2. Inline Image Auto Aspect Restoration & Adaptive Caret Geometry
    
    @Test func optimalRestoredSizeFixesDistortedDimensionsAutomatically() {
        
        let natural = NSSize(width: 1600, height: 900)  // 16:9
        let distorted = NSSize(width: 320, height: 320)  // distorted 1:1
        let restored = BoundingBoxResizeMath.optimalRestoredSize(
            currentSize: distorted,
            naturalSize: natural,
            maxWidth: 600,
            maxHeight: 1600
        )
        
        let restoredAspect = restored.width / restored.height
        let expectedAspect = natural.width / natural.height
        #expect(abs(restoredAspect - expectedAspect) < 0.03)
        #expect(restored.width <= 600)
        #expect(restored.height >= BoundingBoxResizeMath.minHeight)
    }
    
    
    @Test func aspectPreservingResizeMaintainsProportionsAcrossHandles() {
        
        let start = NSRect(x: 40, y: 80, width: 320, height: 180)  // 16:9
        let ratio = CGFloat(16.0 / 9.0)
        
        let corner = BoundingBoxResizeMath.aspectPreservingResizedFrame(
            startFrame: start,
            naturalAspectRatio: ratio,
            handle: .bottomRight,
            delta: NSPoint(x: 80, y: 120),
            minXBound: 16,
            minYBound: 16,
            maxXBound: 600,
            maxYBound: 1600
        )
        #expect(abs((corner.width / corner.height) - ratio) < 0.04)
        #expect(abs(corner.minX - start.minX) < 1)
        #expect(abs(corner.minY - start.minY) < 1)
        
        let east = BoundingBoxResizeMath.aspectPreservingResizedFrame(
            startFrame: start,
            naturalAspectRatio: ratio,
            handle: .middleRight,
            delta: NSPoint(x: -80, y: 0),
            minXBound: 16,
            minYBound: 16,
            maxXBound: 600,
            maxYBound: 1600
        )
        #expect(abs((east.width / east.height) - ratio) < 0.04)
        
        let south = BoundingBoxResizeMath.aspectPreservingResizedFrame(
            startFrame: start,
            naturalAspectRatio: ratio,
            handle: .bottomCenter,
            delta: NSPoint(x: 0, y: 90),
            minXBound: 16,
            minYBound: 16,
            maxXBound: 600,
            maxYBound: 1600
        )
        #expect(abs((south.width / south.height) - ratio) < 0.04)
    }
    
    
    @Test func adaptiveCaretTracksImageHeightAndSideEdges() {
        
        let cardRect = NSRect(x: 48, y: 120, width: 280, height: 168)
        let leadingCaret = BoundingBoxResizeMath.adaptiveCaretRect(
            forImageCardRect: cardRect,
            edge: .leading,
            singleLineHeight: 18,
            textContainerMinX: 12
        )
        let trailingCaret = BoundingBoxResizeMath.adaptiveCaretRect(
            forImageCardRect: cardRect,
            edge: .trailing,
            singleLineHeight: 18,
            textContainerMinX: 12
        )
        
        #expect(abs(leadingCaret.height - (cardRect.height - 8)) <= 1)
        #expect(abs(trailingCaret.height - (cardRect.height - 8)) <= 1)
        #expect(leadingCaret.minX < cardRect.minX)
        #expect(trailingCaret.minX > cardRect.maxX)
        #expect(abs(leadingCaret.midY - cardRect.midY) <= 1)
    }
    
    
    // MARK: 3. Cmd-Key Link Detection Ranges
    
    @Test func urlDetectorExtractsCleanLinkRangesAndTrimsDelimiters() {
        
        let sample = "Check https://aihot.news/agent, and also (https://coteditor.com/docs?q=1)."
        let nsSample = sample as NSString
        let ranges = URLDetector.detectedLinkRanges(in: sample)
        
        #expect(ranges.count == 2)
        #expect(nsSample.substring(with: ranges[0]) == "https://aihot.news/agent")
        #expect(nsSample.substring(with: ranges[1]) == "https://coteditor.com/docs?q=1")
    }
    
    
    // MARK: 4. Unified Window Chrome Palette Synchronization
    
    @Test func chromePaletteHarmonizesDarkAndLightThemes() {
        
        let darkChrome = StudioPaletteManager.shared.chromePalette(for: nil, isDark: true)
        let lightChrome = StudioPaletteManager.shared.chromePalette(for: nil, isDark: false)
        
        #expect(darkChrome.isDark)
        #expect(!lightChrome.isDark)
        #expect(darkChrome.tabBarBackground != lightChrome.tabBarBackground)
        #expect(darkChrome.activeTabFill != darkChrome.tabBarBackground)
        #expect(lightChrome.activeTabFill != lightChrome.tabBarBackground)
        #expect(darkChrome.toolbarPillText != darkChrome.toolbarPillFill)
        #expect(lightChrome.toolbarPillText != lightChrome.toolbarPillFill)
    }
    
    
    // MARK: 5. Dashboard Rose, Sunburst, Done-Today & AIHotNews Parsers
    
    @Test func analyticsProvidesBusynessMoodAndDoneTodayMetrics() {
        
        let busyness = AnalyticsManager.shared.busynessMetrics
        #expect(busyness.slices.count == 12)
        #expect((0...100).contains(busyness.score))
        #expect(!busyness.peakHourLabel.isEmpty)
        
        let mood = AnalyticsManager.shared.moodMetrics
        #expect(mood.segments.count == 4)
        #expect((0...100).contains(mood.score))
        #expect(!mood.dominantLabel.isEmpty)
        #expect(mood.segments.allSatisfy { !$0.children.isEmpty })
        
        let done = AnalyticsManager.shared.doneTodayPoints
        #expect(!done.isEmpty)
    }
    
    
    @Test func aiHotNewsParsesJSONMarkdownAndRSS() {
        
        let jsonSample = Data("""
        {
          "items": [
            {
              "id": "n1",
              "title": "Claude 4 Agent SDK Released",
              "source": "Anthropic",
              "url": "https://aihot.news/agent/n1",
              "score": 98,
              "tag": "Agent"
            },
            {
              "id": "n2",
              "title": "Open Weights Reasoning Benchmark",
              "url": "/items/reasoning-bench"
            },
            {
              "id": "n3",
              "title": "Malicious File Scheme Link",
              "url": "file:///etc/passwd"
            }
          ]
        }
        """.utf8)
        
        let fromJSON = AIHotNewsService.parseJSON(jsonSample)
        #expect(fromJSON.count == 3)
        #expect(fromJSON[0].title == "Claude 4 Agent SDK Released")
        #expect(fromJSON[0].source == "Anthropic")
        #expect(fromJSON[0].heatScore == 98)
        #expect(fromJSON[1].urlString == "https://aihot.news/items/reasoning-bench")
        // Unsafe `file://` URL must be sanitized away (falls back to safe https URL)
        #expect(fromJSON[2].url?.scheme == "https")
        #expect(AIHotNewsService.sanitizedHTTPURLString("file:///etc/passwd") == nil)
        #expect(AIHotNewsService.sanitizedHTTPURLString("smb://internal/share") == nil)
        
        let markdownSample = """
        # AI Hot News
        - [MCP App Ecosystem Grows Rapidly](https://aihot.news/items/mcp-apps) · GitHub · 12m · 96🔥
        - [Local LLM Quantization Guide](https://arxiv.org/abs/2501.00001)
        """
        let fromMD = AIHotNewsService.parseAgentMarkdown(markdownSample)
        #expect(fromMD.count == 2)
        #expect(fromMD[0].title == "MCP App Ecosystem Grows Rapidly")
        #expect(fromMD[0].source == "GitHub")
        #expect(fromMD[0].heatScore == 96)
        #expect(fromMD[1].urlString == "https://arxiv.org/abs/2501.00001")
        
        let rssSample = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>AI Hot News</title>
            <item>
              <title><![CDATA[Swift 6.2 Concurrency Updates]]></title>
              <link>https://swift.org/blog/concurrency</link>
              <source>Swift.org</source>
              <category>Swift</category>
              <category>Concurrency</category>
            </item>
          </channel>
        </rss>
        """.utf8)
        let fromRSS = AIHotNewsService.parseRSS(rssSample)
        #expect(fromRSS.count == 1)
        #expect(fromRSS[0].title == "Swift 6.2 Concurrency Updates")
        #expect(fromRSS[0].source == "Swift.org")
        #expect(fromRSS[0].tag == "Swift")
        #expect(fromRSS[0].url?.absoluteString == "https://swift.org/blog/concurrency")
    }
    
    
    // MARK: 6. Regression: Inline Image Insertion at EOF Never Jumps to Index 0
    
    @Test func insertInlineImageAtEndOfDocumentAppendsInsteadOfPrepending() {
        
        let storage = NSTextStorage(string: "Hello world")
        let scanner = LineEndingScanner(textStorage: storage, lineEnding: .lf)
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), textStorage: storage, lineEndingScanner: scanner)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        
        textView.insertInlineImageTokenCleanly("⟦🖼 test-eof.png⟧")
        
        #expect(textView.string.hasPrefix("Hello world\n⟦🖼 test-eof.png⟧"))
    }
    
    
    // MARK: 7. Heatmap Strict 1:1 Square Proportions, AI Document Predictions, News Covers & Avatar Accent
    
    @Test func heatmapLayoutAlwaysMaintainsStrictSquareCells() {
        for weeks in [18, 36, 53] {
            let layout = HeatmapGridLayout.compute(size: CGSize(width: 560, height: 240), weekCount: weeks)
            let rect = layout.cellRect(col: 0, row: 0)
            #expect(abs(rect.width - rect.height) < 0.001)
            #expect(rect.width >= 9.5 && rect.width <= 15.0)
        }
    }
    
    
    @Test func aiActionPredictionsParseJSONAndInferFromDocuments() {
        let doc = StoredDocumentRecord(
            id: "doc-auth",
            title: "认证重构方案.md",
            filePath: nil,
            syntax: "Markdown",
            content: "# 认证重构\n- [ ] 补完 OAuth 超时重试逻辑\n是否需要支持多租户隔离？\n## 待补充压测数据",
            highlightsJSON: "[]",
            updatedAt: Date(),
            createdAt: Date()
        )
        
        let aiJSON = """
        ```json
        [{"action":"补齐 OAuth 刷新失败的重试退避","reason":"方案中尚未覆盖网络抖动场景","doc_title":"认证重构方案.md","urgency":"高"}]
        ```
        """
        let parsed = AnalyticsManager.parseActionPredictions(from: aiJSON, documents: [doc])
        #expect(parsed.count == 1)
        #expect(parsed[0].sourceDocumentID == "doc-auth")
        #expect(parsed[0].urgency == "高")
        
        let heuristic = AnalyticsManager.buildHeuristicActionPredictions(
            documents: [doc],
            weeklyReports: [],
            reminders: []
        )
        #expect(!heuristic.isEmpty)
        #expect(heuristic.contains { $0.sourceDocumentID == "doc-auth" })
    }
    
    
    @Test func aiHotNewsExtractsRealCoversFromJSONRSSAndOpenGraph() throws {
        let jsonData = Data("""
        {"items":[{"id":"c1","title":"Vision Model Release","url":"https://example.com/post/1","image":"https://cdn.example.com/cover.webp"}]}
        """.utf8)
        let parsedJSON = AIHotNewsService.parseJSON(jsonData)
        #expect(parsedJSON.first?.coverURLString == "https://cdn.example.com/cover.webp")
        
        let rssData = Data("""
        <rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">
          <channel><item>
            <title>Agent Post</title>
            <link>https://example.com/agent</link>
            <media:thumbnail url="https://cdn.example.com/thumb.png" />
          </item></channel>
        </rss>
        """.utf8)
        let parsedRSS = AIHotNewsService.parseRSS(rssData)
        #expect(parsedRSS.first?.coverURLString == "https://cdn.example.com/thumb.png")
        
        let pageURL = try #require(URL(string: "https://blog.example.com/articles/42"))
        let html = """
        <html><head><meta property="og:image" content="/assets/hero-42.jpg" /></head></html>
        """
        let og = AIHotNewsService.extractOpenGraphImageURL(from: html, pageURL: pageURL)
        #expect(og == "https://blog.example.com/assets/hero-42.jpg")
    }
    
    
    @Test func avatarColorExtractorIgnoresWhiteBackgroundAndPicksTrueBlueAccent() throws {
        let img = NSImage(size: NSSize(width: 64, height: 64))
        img.lockFocus()
        // White background covering 75% of canvas (previously polluted red bucket 0!)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        // Blue subject in center
        NSColor(srgbRed: 0.10, green: 0.48, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: 32, height: 32)).fill()
        img.unlockFocus()
        
        let profile = UserProfile(
            id: "blue-on-white-\(UUID().uuidString)",
            displayName: "Blue",
            avatarData: nil,
            avatarColorHex: "#FF0000",
            dbFilename: "test.sqlite3",
            accountKind: "local",
            email: nil,
            remoteUserID: nil,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        let palette = AvatarColorExtractor.extractPalette(for: profile, image: img)
        let accentNS = try #require(NSColor(palette.accent).usingColorSpace(.sRGB))
        // Hue of blue is around 0.55...0.67 (far from red 0.0 / 1.0!)
        #expect(accentNS.hueComponent >= 0.50 && accentNS.hueComponent <= 0.72)
    }
    
    
    // MARK: 8. Vim Normal Mode Navigation onto Inline Image Lines
    
    @Test func vimNormalModeMovesCleanlyOntoAndAcrossInlineImageLines() throws {
        // Store a real inline image so `LayoutManager` renders `.controlCharacter` + `.null` glyphs
        let sampleImg = NSImage(size: NSSize(width: 120, height: 80))
        sampleImg.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        sampleImg.unlockFocus()
        let stored = try #require(PlainTextInlineImageStore.shared.store(image: sampleImg, for: nil))
        let tokenStr = stored.token
        
        let doc = "First text line\n\(tokenStr)\nThird text line"
        let storage = NSTextStorage(string: doc)
        let scanner = LineEndingScanner(textStorage: storage, lineEnding: .lf)
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 420), textStorage: storage, lineEndingScanner: scanner)
        (textView.layoutManager as? LayoutManager)?.rendersPlainTextInlineImages = true
        textView.layoutManager?.ensureLayout(forCharacterRange: NSRange(location: 0, length: (doc as NSString).length))
        
        let line1Start = ("First text line\n" as NSString).length
        let line2Start = ("First text line\n\(tokenStr)\n" as NSString).length
        
        VimState.shared.mode = .normal
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        
        let engine = VimEngine(textView: textView)
        let jEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "j", charactersIgnoringModifiers: "j",
            isARepeat: false, keyCode: 38
        ))
        let kEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: 40
        ))
        
        // Press `j` from Line 0 -> MUST land cleanly at start of image token on Line 1!
        #expect(engine.handleKeyDown(jEvent))
        #expect(textView.selectedRange().location == line1Start)
        #expect(textView.vimCursorRect(at: line1Start) != nil)
        
        // Press `j` again -> advances cleanly to Line 2!
        #expect(engine.handleKeyDown(jEvent))
        #expect(textView.selectedRange().location >= line2Start)
        
        // Press `k` from Line 2 -> MUST land cleanly back on the image line (Line 1)!
        #expect(engine.handleKeyDown(kEvent))
        #expect(textView.selectedRange().location == line1Start)
        
        // Press `k` again -> returns to Line 0!
        #expect(engine.handleKeyDown(kEvent))
        #expect(textView.selectedRange().location < line1Start)
    }
    
    
    // MARK: 9. Unified 10-Palette Light/Dark Pairing & Multi-Category News (Finance + X + AI)
    
    @Test func unifiedTenPalettesStayPairedAcrossLightAndDarkModes() throws {
        #expect(StudioPaletteID.allCases.count == 10)
        #expect(StudioPaletteID.resolve(rawValue: "custom") == .pineCeladon)
        
        let manager = StudioPaletteManager.shared
        for preset in StudioPaletteID.allCases {
            let lightThemeName = StudioPaletteManager.themeName(for: preset, preferDark: false)
            let darkThemeName = StudioPaletteManager.themeName(for: preset, preferDark: true)
            
            // Switching Light <-> Dark always stays on the EXACT SAME palette
            let toDark = ThemeManager.shared.equivalentSettingName(to: lightThemeName, forDark: true)
            let toLight = ThemeManager.shared.equivalentSettingName(to: darkThemeName, forDark: false)
            #expect(toDark == darkThemeName)
            #expect(toLight == lightThemeName)
            
            let lightTokens = manager.tokens(isDark: false, id: preset)
            let darkTokens = manager.tokens(isDark: true, id: preset)
            #expect(!lightTokens.isDark && darkTokens.isDark)
        }
    }
    
    
    @Test func multiCategoryNewsSupportsFinanceAndXWhileScrubbingAIHot() throws {
        let hnXJSON = Data("""
        {
          "hits": [
            {
              "objectID": "42001",
              "title": "Fed signals steady rates while AI capex surges",
              "url": "https://x.com/markets_desk/status/1234567890",
              "points": 185,
              "created_at": "2026-11-22T09:30:00Z"
            }
          ]
        }
        """.utf8)
        let parsed = AIHotNewsService.parseHackerNewsAlgoliaJSON(hnXJSON, defaultSource: "X 热议", category: .xSocial)
        #expect(parsed.count == 1)
        #expect(parsed[0].resolvedCategory == .xSocial)
        #expect(parsed[0].source.contains("@markets_desk"))
        #expect(parsed[0].heatScore == 185)
        
        let financeItem = AIHotNewsItem(
            id: "fin-1",
            title: "美股科技板块领涨，美联储释放鸽派信号",
            source: "CNBC 财经",
            urlString: "https://www.cnbc.com/2026/11/22/markets.html",
            publishedAt: Date(),
            heatScore: nil,
            tag: "金融",
            category: .finance
        )
        #expect(financeItem.resolvedCategory == .finance)
        
        let blocked = AIHotNewsItem(
            id: "old-1",
            title: "Old cached item",
            source: "aihot.news",
            urlString: "https://aihot.news/items/1",
            publishedAt: nil,
            heatScore: nil,
            tag: nil
        )
        #expect(AIHotNewsService.containsBlockedBrand(blocked))
        #expect(!AIHotNewsService.sanitizedDisplaySource("ai.hot").lowercased().contains("ai"))
    }
}
