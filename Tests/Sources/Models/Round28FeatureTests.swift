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
    
    // MARK: 1. Collector PASS 7-Principle Art Engine
    
    @Test func cotPassArtEngineBuildsCachedStockMorphingSealAndAsciiPixelMatrix() {
        let theme = CotPassTheme.resolve(index: 0)
        let cardSize = CGSize(width: 408, height: 246)
        
        let stock1 = CotPassArtEngine.cachedStockImage(
            theme: theme,
            serialCode: "COT-2026-R28A",
            size: cardSize
        )
        let stock2 = CotPassArtEngine.cachedStockImage(
            theme: theme,
            serialCode: "COT-2026-R28A",
            size: cardSize
        )
        
        #expect(stock1 != nil)
        #expect(stock2 != nil)
        if let cg1 = stock1, let cg2 = stock2 {
            #expect(cg1.width >= 408)
            #expect(cg1.height >= 246)
            #expect(cg1 === cg2)
        }
        
        let morphA = CotPassArtEngine.morphingObjectPath(
            center: CGPoint(x: 120, y: 120),
            baseRadius: 34,
            phase: 0.25
        )
        let morphB = CotPassArtEngine.morphingObjectPath(
            center: CGPoint(x: 120, y: 120),
            baseRadius: 34,
            phase: 1.85
        )
        #expect(!morphA.isEmpty)
        #expect(!morphB.isEmpty)
        #expect(morphA.boundingRect != morphB.boundingRect)
        
        // Synthetic normalized luminance contour field sized to BrandLinePassEngine.gridSize^2
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
        let matrix = CotPassArtEngine.buildASCIIPixelMatrix(
            from: contour,
            cols: 14,
            rows: 14
        )
        #expect(matrix.count == 14)
        #expect(matrix.flatMap { $0 }.count == 196)
        let summary = String(describing: matrix)
        #expect(summary.contains("pixelBlock"))
        #expect(summary.contains("ascii"))
        
        let sketchOrbit = CotPassArtEngine.sketchOrbitPath(
            around: CGRect(x: 24, y: 24, width: 76, height: 76),
            seed: 42
        )
        let scribble = CotPassArtEngine.scribbleUnderlinePath(
            origin: CGPoint(x: 24, y: 120),
            width: 140,
            seed: 42
        )
        #expect(!sketchOrbit.isEmpty)
        #expect(!scribble.isEmpty)
    }
    
    
    // MARK: 2. Hero Achievement Danmaku Zero-Overlap Sanctuary Scheduler
    
    @Test func heroDanmakuSchedulerAvoidsCardBackButtonAndCollisionsAcrossTime() {
        let canvasSize = CGSize(width: 1380, height: 186)
        let cardRect = CGRect(x: 530, y: 12, width: 320, height: 162)
        let backRect = CGRect(x: 0, y: 0, width: 110, height: 36)
        
        let items: [DashboardHeroDanmakuScheduler.Item] = [
            .init(id: "t1", text: "今日 1,569 字", tone: .calm),
            .init(id: "t2", text: "连更 8 天", tone: .sharp),
            .init(id: "t3", text: "年活跃 215 天", tone: .warm),
            .init(id: "t4", text: "日均 1,953 字", tone: .playful),
            .init(id: "t5", text: "峰值 4,120 字", tone: .calm),
            .init(id: "t6", text: "手写心流派", tone: .sharp),
            .init(id: "t7", text: "PRO 典藏通行", tone: .warm),
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
                items: items,
                elapsed: elapsed
            )
            
            for idx in placements.indices {
                let placement = placements[idx]
                if placement.frame.midX < cardRect.minX { sawLeftWing = true }
                if placement.frame.midX > cardRect.maxX { sawRightWing = true }
                
                #expect(!placement.frame.intersects(cardRect.insetBy(dx: -16, dy: -8)))
                #expect(!placement.frame.intersects(backRect))
                #expect(placement.opacity > 0.0 && placement.opacity <= 1.0)
                
                for nextIndex in (idx + 1)..<placements.count {
                    #expect(!placement.frame.intersects(placements[nextIndex].frame))
                }
            }
        }
        
        #expect(sawLeftWing)
        #expect(sawRightWing)
    }
    
    
    // MARK: 3. Todo Action Sanitization & Section Header Rejection
    
    @Test func actionSanitizerStripsNumberingAndColonHeadersAndHeuristicSkipsTodoHeaders() {
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
            - [ ] cot 优化todos：
            - [ ] 2. 采样的逻辑涉及到上下文窗口调度
            - [ ] 完善通行证离线艺术纹理缓存
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
        #expect(heuristic.contains { $0.action.contains("采样") || $0.action.contains("通行证") })
    }
}
