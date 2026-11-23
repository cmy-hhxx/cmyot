//
//  Round28FeatureTests.swift
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
import SwiftUI
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round28FeatureTests {
    
    // MARK: 1. Swiss-Gallery × Instant-Film Collector PASS Engine (7 Visual Principles)
    
    @Test func cotPassGalleryEngineSeparatesZonesAndSynthesizesAllSevenPrinciples() {
        let theme = CotPassTheme.resolve(index: 0)
        let fullSize = CGSize(width: 408, height: 246)
        let heroSize = CGSize(width: 304, height: 148)
        
        let stock1 = CotPassArtEngine.cachedStockImage(
            theme: theme,
            serialCode: "COT-2026-R28A",
            size: fullSize
        )
        let stock2 = CotPassArtEngine.cachedStockImage(
            theme: theme,
            serialCode: "COT-2026-R28A",
            size: fullSize
        )
        let heroStock = CotPassArtEngine.cachedStockImage(
            theme: theme,
            serialCode: "COT-2026-HERO",
            size: heroSize
        )
        
        #expect(stock1 != nil)
        #expect(heroStock != nil)
        if let cg1 = stock1, let cg2 = stock2, let cgHero = heroStock {
            #expect(cg1.width == 816 && cg1.height == 492)
            #expect(cgHero.width == 608 && cgHero.height == 296)
            #expect(cg1 === cg2)
        }
        
        // Verify strict perforation seam separation between left identity stub and right art window
        for size in [fullSize, heroSize] {
            let seamX = CotPassArtEngine.perforationX(in: size)
            let artRect = CotPassArtEngine.artWindowRect(in: size)
            #expect(artRect.minX > seamX + 6)
            #expect(artRect.maxX < size.width)
            #expect(artRect.height > size.height * 0.72)
        }
        
        // Volumetric morphing sculpture & soft core morph across phase
        let dA = CotPassArtEngine.morphingSculptureDensity(u: 0.60, v: 0.42, phase: 0.2)
        let dB = CotPassArtEngine.morphingSculptureDensity(u: 0.60, v: 0.42, phase: 2.4)
        #expect(dA != dB)
        #expect(dA > 0.0 && dA <= 1.0)
        
        let morphA = CotPassArtEngine.morphingObjectPath(center: CGPoint(x: 120, y: 120), baseRadius: 34, phase: 0.25)
        let morphB = CotPassArtEngine.morphingObjectPath(center: CGPoint(x: 120, y: 120), baseRadius: 34, phase: 1.85)
        #expect(!morphA.isEmpty && !morphB.isEmpty)
        #expect(morphA.boundingRect != morphB.boundingRect)
        
        // Generative curl-flow impressionist impasto mosaic
        let artRect = CotPassArtEngine.artWindowRect(in: fullSize)
        let tiles = CotPassArtEngine.computeImpastoTiles(seed: 77, in: artRect)
        #expect(tiles.count == 99)
        let tileDesc = String(describing: tiles)
        #expect(tileDesc.contains("porcelainHighlight"))
        #expect(tileDesc.contains("mineralAccent"))
        
        // Swiss-grid ASCII + Micro-Pixel plaque matrix
        let grid = BrandLinePassEngine.gridSize
        var contour = Array(repeating: Float(0.08), count: grid * grid)
        for row in 0..<grid {
            for col in 0..<grid {
                let nx = Float(col) / Float(max(1, grid - 1))
                let ny = Float(row) / Float(max(1, grid - 1))
                let dx = (nx - 0.70) / 0.22
                let dy = (ny - 0.50) / 0.30
                let dist = sqrt(dx * dx + dy * dy)
                contour[row * grid + col] = max(0.05, min(0.95, 1.0 - dist * 0.85))
            }
        }
        let matrix = CotPassArtEngine.buildASCIIPixelMatrix(from: contour, cols: 10, rows: 6)
        #expect(matrix.count == 6)
        #expect(matrix.flatMap { $0 }.count == 60)
        let summary = String(describing: matrix)
        #expect(summary.contains("pixelBlock"))
        #expect(summary.contains("ascii"))
        
        // Lithograph 45° shading & Polaroid-chin ink paraph
        let hatch = CotPassArtEngine.lithographHatchPath(in: artRect, seed: 42)
        let paraph = CotPassArtEngine.calligraphicParaphPath(in: CGRect(x: 0, y: 0, width: 46, height: 10.5), seed: 42)
        #expect(!hatch.isEmpty)
        #expect(!paraph.isEmpty)
    }
    
    
    // MARK: 2. Hero Danmaku Toggle Persistence & Zero-Overlap Sanctuary Scheduler
    
    @Test func heroDanmakuTogglePersistsAndSchedulerAvoidsCardBackAndToggleButtons() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotR28Danmaku-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "danmaku.sqlite3"))
        #expect(db.string(forKey: CotLocalDatabase.ConfigKey.dashboardDanmakuEnabled, default: "true") == "true")
        db.set("false", forKey: CotLocalDatabase.ConfigKey.dashboardDanmakuEnabled)
        #expect(db.string(forKey: CotLocalDatabase.ConfigKey.dashboardDanmakuEnabled, default: "true") == "false")
        
        let canvasSize = CGSize(width: 1140, height: 154)
        let cardRect = CGRect(x: 418, y: 3, width: 304, height: 148)
        let backRect = CGRect(x: 0, y: 0, width: 110, height: 36)
        let toggleRect = CGRect(x: 1036, y: 0, width: 104, height: 36)
        
        #expect(DashboardHeroDanmakuScheduler.estimatedPillSize(for: "高产创作者").width > 100)
        #expect(DashboardHeroDanmakuScheduler.estimatedPillSize(for: "长期主义者").width > 100)
        
        let items: [DashboardHeroDanmakuScheduler.Item] = [
            .init(id: "t1", text: "今日 1,569 字", tone: .calm),
            .init(id: "t2", text: "连更 8 天", tone: .sharp),
            .init(id: "t3", text: "年活跃 215 天", tone: .warm),
            .init(id: "t4", text: "日均 1,953 字", tone: .playful),
            .init(id: "t5", text: "峰值 4,120 字", tone: .calm),
            .init(id: "t6", text: "手写心流派", tone: .sharp),
            .init(id: "t7", text: "PRO 通行证", tone: .warm),
            .init(id: "t8", text: "长期主义者", tone: .playful),
            .init(id: "t9", text: "高产创作者", tone: .warm),
            .init(id: "t10", text: "沉稳推进", tone: .calm),
        ]
        
        var sawLeftWing = false
        var sawRightWing = false
        
        for elapsed in [0.0, 1.3, 2.9, 5.4, 8.7, 14.2] {
            let placements = DashboardHeroDanmakuScheduler.placements(
                canvasSize: canvasSize,
                cardRect: cardRect,
                reservedTopLeftRect: backRect,
                reservedTopRightRect: toggleRect,
                items: items,
                elapsed: elapsed
            )
            
            for idx in placements.indices {
                let placement = placements[idx]
                if placement.frame.midX < cardRect.minX { sawLeftWing = true }
                if placement.frame.midX > cardRect.maxX { sawRightWing = true }
                
                #expect(!placement.frame.intersects(cardRect.insetBy(dx: -16, dy: -8)))
                #expect(!placement.frame.intersects(backRect))
                #expect(!placement.frame.intersects(toggleRect))
                #expect(placement.opacity > 0.0 && placement.opacity <= 1.0)
                
                for nextIndex in (idx + 1)..<placements.count {
                    #expect(!placement.frame.intersects(placements[nextIndex].frame))
                }
            }
        }
        
        #expect(sawLeftWing)
        #expect(sawRightWing)
    }
    
    
    // MARK: 3. Retina High-DPI NEWS Cover Pipeline & URL Promotion
    
    @Test func newsCoverPipelinePromotesCDNURLsAndPreservesRetina2xResolution() throws {
        let promotedX = AIHotNewsService.upgradeCoverURLResolution("https://pbs.twimg.com/media/Abc123?format=jpg&name=small")
        #expect(promotedX.contains("name=large"))
        
        let promotedWidth = AIHotNewsService.upgradeCoverURLResolution("https://cdn.example.com/cover.png?w=320&fit=crop")
        #expect(promotedWidth.contains("w=1080"))
        
        // Prefer og_image over low-res thumbnail in JSON feed parsing
        let json = Data("""
        {"items":[{"id":"n1","title":"Compiler Breakthrough","url":"https://example.com/1","thumbnail":"https://cdn.example.com/tiny.jpg","og_image":"https://cdn.example.com/hd-og.png"}]}
        """.utf8)
        let parsed = AIHotNewsService.parseJSON(json)
        #expect(parsed.first?.coverURLString == "https://cdn.example.com/hd-og.png")
        
        // Synthesize a 1200 x 630 OG banner and verify Retina 1080px downsampling & 2x NSSize scaling
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1200,
            pixelsHigh: 630,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
        NSGraphicsContext.restoreGraphicsState()
        
        let pngData = try #require(rep.representation(using: .png, properties: [:]))
        let retinaThumb = try #require(AIHotNewsService.downsampledThumbnail(from: pngData))
        let cgThumb = try #require(retinaThumb.cgImage(forProposedRect: nil, context: nil, hints: nil))
        
        #expect(cgThumb.width == 1080)
        #expect(abs(retinaThumb.size.width - 540) < 0.5)
    }
    
    
    // MARK: 4. Todo Action Sanitization & Section Header Rejection
    
    @Test func actionSanitizerStripsNumberingAndColonHeadersAndHeuristicSkipsTodoHeaders() {
        #expect(!AnalyticsManager.hasMeaningfulActionSubstance("cot 优化todos"))
        #expect(!AnalyticsManager.hasMeaningfulActionSubstance("cot Editors"))
        #expect(AnalyticsManager.hasMeaningfulActionSubstance("完善通行证离线艺术纹理缓存"))
        
        let stripped = AnalyticsManager.sanitizeDashboardActionText(
            "2. 采样的逻辑涉及到 问题的发生模式",
            knownTitles: ["CotEditor Roadmap"]
        )
        #expect(stripped == "采样的逻辑涉及到 问题的发生模式")
        #expect(!stripped.hasPrefix("2."))
        
        let strippedCN = AnalyticsManager.sanitizeDashboardActionText(
            "（3）CoTEditor 优化 todos:",
            knownTitles: []
        )
        #expect(!strippedCN.hasSuffix(":"))
        
        let doc = StoredDocumentRecord(
            id: "doc-roadmap",
            title: "roadmap.md",
            filePath: nil,
            syntax: "Markdown",
            content: """
            # roadmap.md
            - [ ] CoTEditor 优化 todos:
            - [ ] cot 优化todos
            - [ ] cot Editors
            - [ ] 2. 采样的逻辑涉及到上下文窗口调度
            - [ ] 完善通行证离线艺术纹理缓存
            ## cot Editors
            """,
            highlightsJSON: "[]",
            updatedAt: Date(),
            createdAt: Date()
        )
        
        let heuristic = AnalyticsManager.buildHeuristicActionPredictions(
            documents: [doc],
            weeklyReports: [],
            reminders: []
        )
        let joined = heuristic.map(\.action).joined(separator: "\n")
        
        #expect(!joined.contains("CoTEditor 优化 todos:"))
        #expect(!joined.contains("cot 优化todos"))
        #expect(!joined.contains("cot Editors"))
        #expect(heuristic.contains { $0.action.contains("采样") || $0.action.contains("通行证") })
    }
}
