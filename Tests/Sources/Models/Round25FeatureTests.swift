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
}
