//
//  Round29FeatureTests.swift
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

import Foundation
import Testing
@testable import CotEditor

@Suite(.serialized)
@MainActor
struct Round29FeatureTests {
    
    // MARK: 1. HTML Readability & JSON-LD Structured Article Extraction
    
    @Test func articleExtractorParsesSemanticArticleStripsNoiseAndSupportsJSONLD() {
        let html = """
        <!doctype html>
        <html>
        <head>
          <script>window.analytics = true;</script>
          <style>.ad { display:block; }</style>
        </head>
        <body>
          <nav><p>Sign up for our newsletter and accept cookies to continue.</p></nav>
          <article>
            <h2>Speculative Decoding &mdash; Architecture</h2>
            <p>Modern inference engines achieve 2.8x throughput by verifying draft tokens in parallel with <code>KV-cache</code> reuse.</p>
            <blockquote>Latency drops linearly when acceptance rate exceeds 78&#37; across long contexts.</blockquote>
            <pre><code>let accepted = verify(draftTokens, targetLogits)</code></pre>
            <ul>
              <li>Zero quality degradation relative to greedy sampling</li>
              <li>Memory bandwidth bound workloads benefit most</li>
            </ul>
            <p>Subscribe to our daily newsletter. All rights reserved.</p>
          </article>
          <footer><p>Privacy Policy &amp; Terms of Service</p></footer>
        </body>
        </html>
        """
        
        let extracted = NewsArticleExtractor.extractFromWebPageHTML(html)
        #expect(extracted.blocks.count == 5)
        
        let md = NewsArticleContent(
            blocks: extracted.blocks,
            leadExcerpt: nil,
            author: extracted.author,
            extractedAt: .now
        ).markdownBody
        
        #expect(md.contains("## Speculative Decoding — Architecture"))
        #expect(md.contains("`KV-cache`"))
        #expect(md.contains("> Latency drops linearly when acceptance rate exceeds 78%"))
        #expect(md.contains("let accepted = verify(draftTokens, targetLogits)"))
        #expect(md.contains("- Zero quality degradation"))
        #expect(!md.lowercased().contains("privacy policy"))
        #expect(!md.lowercased().contains("all rights reserved"))
        
        // JSON-LD fallback when DOM is an empty SPA shell
        let spaHTML = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"NewsArticle","author":{"name":"Dr. Lin"},"articleBody":"First detailed paragraph explaining sparse attention routing across 128k tokens in production.\\n\\nSecond detailed paragraph comparing hardware utilization on Apple Silicon unified memory."}
        </script>
        </head><body><div id="app"></div></body></html>
        """
        let spaExtracted = NewsArticleExtractor.extractFromWebPageHTML(spaHTML)
        #expect(spaExtracted.author == "Dr. Lin")
        #expect(spaExtracted.blocks.count == 2)
    }
    
    
    // MARK: 2. Feed-Level Full `<content:encoded>` & JSON Body Preservation
    
    @Test func rssAndJsonParsersPreserveFullStructuredContentBlocks() {
        let rssXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <item>
              <title>Formal Verification Milestone in Lean 4</title>
              <link>https://example.org/lean4-milestone</link>
              <content:encoded><![CDATA[
                <h2>Automated Proof Search</h2>
                <p>Researchers combined symbolic tactics with neural premise selection to close twelve open lemmas.</p>
                <p>The resulting proof artifact compiles deterministically in under four seconds on standard hardware.</p>
              ]]></content:encoded>
            </item>
          </channel>
        </rss>
        """.utf8)
        
        let rssItems = AIHotNewsService.parseRSS(rssXML)
        #expect(rssItems.count == 1)
        #expect((rssItems.first?.contentBlocks?.count ?? 0) == 3)
        
        let jsonFeed = Data("""
        {"items":[{
          "id":"j-full-1",
          "title":"Unified Memory Bandwidth Analysis",
          "url":"https://example.org/memory",
          "content_html":"<h3>Bandwidth Scaling</h3><p>Sustained memory bandwidth governs token generation speed at batch size one.</p><p>Quantizing weights to 4-bit doubles effective tokens per second without accuracy cliffs.</p>"
        }]}
        """.utf8)
        let jsonItems = AIHotNewsService.parseJSON(jsonFeed)
        #expect(jsonItems.count == 1)
        #expect((jsonItems.first?.contentBlocks?.count ?? 0) == 3)
    }
    
    
    // MARK: 3. SQLite Reader Persistence (Bookmarks, Read State, Notes, AI Briefs)
    
    @Test func newsServicePersistsBookmarksReadsNotesAndBriefsInSQLite() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CotR29News-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let db = CotLocalDatabase(customURL: tempDir.appending(path: "news.sqlite3"))
        let cacheDir = tempDir.appending(path: "Cache", directoryHint: .isDirectory)
        
        let item = AIHotNewsItem(
            id: "news-persist-1",
            title: "Compiler-Guided Kernel Fusion for Transformers",
            source: "Ars Technica",
            urlString: "https://example.com/kernel-fusion",
            publishedAt: Date(),
            heatScore: 91,
            tag: "AI",
            summary: "Kernel fusion reduces intermediate HBM roundtrips.",
            contentBlocks: [
                .heading(level: 2, text: "Fusion Graph"),
                .paragraph("Fusing layernorm and rotary embeddings eliminates two full tensor materializations."),
            ]
        )
        
        do {
            let service = AIHotNewsService(database: db, cacheRootDirectory: cacheDir)
            service.toggleBookmark(item)
            service.markRead(item)
            service.setNote("值得在推理优化周报中引用", for: item.id)
            service.setAIBrief("1. 消除中间张量写回\n2. 显著降低显存带宽瓶颈", for: item.id)
            
            #expect(service.isBookmarked(item))
            #expect(service.isRead(item))
            #expect(service.resolvedArticleBlocks(for: item).count == 2)
        }
        
        let reloaded = AIHotNewsService(database: db, cacheRootDirectory: cacheDir)
        #expect(reloaded.isBookmarked(item))
        #expect(reloaded.isRead(item))
        #expect(reloaded.note(for: item.id) == "值得在推理优化周报中引用")
        #expect(reloaded.aiBriefs[item.id]?.contains("显存带宽") == true)
        #expect(reloaded.savedBookmarkedItems.first?.contentBlocks?.count == 2)
    }
}
