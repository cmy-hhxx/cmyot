//
//  DashboardVisualRefinementTests.swift
//
//  CotEditor
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

import CoreGraphics
import Foundation
import Testing
@testable import CotEditor

@Suite(.serialized)
struct DashboardVisualRefinementTests {
    
    @Test
    func newsCompactCardMetricsPreservesBalancedThumbnailAspect() {
        let standard = NewsCompactCardMetrics.resolve(cardWidth: 240, cardHeight: 104)
        #expect(standard.showsThumbnail)
        let standardAspect = standard.thumbnailWidth / standard.thumbnailHeight
        #expect(standardAspect >= 0.95 && standardAspect <= 1.32)
        
        let compact = NewsCompactCardMetrics.resolve(cardWidth: 180, cardHeight: 74)
        #expect(compact.showsThumbnail)
        let compactAspect = compact.thumbnailWidth / compact.thumbnailHeight
        #expect(compactAspect >= 0.95 && compactAspect <= 1.32)
        
        let narrow = NewsCompactCardMetrics.resolve(cardWidth: 140, cardHeight: 96)
        #expect(!narrow.showsThumbnail)
        #expect(narrow.thumbnailWidth == 0)
        #expect(narrow.thumbnailHeight == 0)
    }
    
    
    @Test
    func colorExtractorAvoidsMuddyOliveAndFindsDistinctSecondaryHue() throws {
        let side = 64
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        // 65% dark foliage green, 20% vivid meadow green, 15% sky blue
        let total = side * side
        for idx in 0..<total {
            let offset = idx * 4
            let frac = Double(idx) / Double(total)
            if frac < 0.65 {
                bytes[offset] = UInt8(0.14 * 255)
                bytes[offset + 1] = UInt8(0.24 * 255)
                bytes[offset + 2] = UInt8(0.12 * 255)
            } else if frac < 0.85 {
                bytes[offset] = UInt8(0.26 * 255)
                bytes[offset + 1] = UInt8(0.68 * 255)
                bytes[offset + 2] = UInt8(0.34 * 255)
            } else {
                bytes[offset] = UInt8(0.22 * 255)
                bytes[offset + 1] = UInt8(0.64 * 255)
                bytes[offset + 2] = UInt8(0.94 * 255)
            }
            bytes[offset + 3] = 255
        }
        
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try #require(CGContext(
            data: &bytes,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        let image = try #require(ctx.makeImage())
        let extracted = try #require(DashboardImageColorExtractor.extract(from: image))
        
        #expect(extracted.dominant.green > extracted.dominant.red)
        #expect(extracted.dominant.saturation > 0.35)
        #expect(extracted.dominant.luminance > 0.14)
        
        let secondary = try #require(extracted.secondary)
        #expect(secondary.blue > secondary.red)
        
        let lightCard = (0.988, 0.990, 0.994)
        let harmonized = try #require(
            DashboardImageColorExtractor.harmonizedAccentRGB(from: extracted.dominant, against: lightCard, isDark: false)
        )
        let harmonizedTone = HeroRegionTone(red: harmonized.0, green: harmonized.1, blue: harmonized.2)
        let cardTone = HeroRegionTone(red: lightCard.0, green: lightCard.1, blue: lightCard.2)
        #expect(DashboardImageColorExtractor.contrastRatio(harmonizedTone, cardTone) >= 3.4)
        #expect(harmonizedTone.saturation >= 0.35)
        
        let series = DashboardImageColorExtractor.harmonicSeriesRGB(
            from: harmonized,
            secondary: secondary,
            against: lightCard,
            isDark: false
        )
        #expect(series.count == 4)
        // Series[1] should carry the sky-blue secondary channel rather than clustering in green.
        #expect(series[1].2 > series[1].0)
    }
    
    
    @MainActor
    @Test
    func heroCoverStorePersistsBlurStyleAndResetsOnClear() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appending(path: "cot_hero_blur_test_\(UUID().uuidString).sqlite3")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let tempDB = CotLocalDatabase(customURL: tempURL)
        let store = DashboardHeroCoverStore(database: tempDB)
        #expect(store.blurStyle == .crisp)
        
        store.blurStyle = .frosted
        let reloaded = DashboardHeroCoverStore(database: tempDB)
        #expect(reloaded.blurStyle == .frosted)
        
        reloaded.blurStyle = .soft
        let reloadedSoft = DashboardHeroCoverStore(database: tempDB)
        #expect(reloadedSoft.blurStyle == .soft)
        
        reloadedSoft.clearCoverImage()
        #expect(reloadedSoft.blurStyle == .crisp)
        let afterClear = DashboardHeroCoverStore(database: tempDB)
        #expect(afterClear.blurStyle == .crisp)
    }
    
    
    @Test
    func aiTokenUsageLabelsAndCompactCountsContainNoEnglish() {
        let samples = ["deepseek-reasoner", "claude-3-5-sonnet", "gpt-4o-mini", "glm-5-plus", "gemini-2.5-pro", "qwen-max"]
        for raw in samples {
            let display = AnalyticsManager.chineseModelDisplayName(raw)
            #expect(!display.isEmpty)
            #expect(display.range(of: "[A-Za-z]", options: .regularExpression) == nil)
        }
        let compact1 = AnalyticsManager.chineseCompactTokenCount(25_600)
        #expect(compact1 == "2.6万")
        let compact2 = AnalyticsManager.chineseCompactTokenCount(120_000_000)
        #expect(compact2 == "1.2亿")
    }
}
