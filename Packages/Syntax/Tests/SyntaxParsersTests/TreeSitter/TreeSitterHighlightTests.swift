//
//  TreeSitterHighlightTests.swift
//  SyntaxParsersTests
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-02-23.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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
import StringUtils
import ValueRange
import SyntaxFormat
@testable import SyntaxParsers

struct TreeSitterHighlightTests {
    
    private let registry: LanguageRegistry = .shared
    
    
    @Test func incrementalParseUpdatesRange() async throws {
        
        let source = #"""
            def doSomething(string, range):
                item = registry.items[0]
                return storage.replace(item, range)
        """#
        
        let config = try self.registry.configuration(for: .python)
        let client = try TreeSitterClient(languageConfig: config, languageProvider: self.registry.languageProvider, syntax: .python)
        _ = try #require(await client.parseHighlights(in: source, range: source.nsRange))
        
        let locationRange = (source as NSString).range(of: "doSomething")
        let insertLocation = locationRange.location
        let insertedText = "abc"
        let editedRange = NSRange(location: insertLocation, length: insertedText.length)
        let editedSource = (source as NSString).replacingCharacters(in: NSRange(location: insertLocation, length: 0), with: insertedText)
        
        try await client.noteEdit(editedRange: editedRange, delta: insertedText.length, insertedText: insertedText)
        let requestedRange = NSRange(location: 0, length: 0)
        let result = try #require(await client.parseHighlights(in: editedSource, range: requestedRange))
        let updateRange = result.updateRange
        
        #expect(updateRange.lowerBound <= editedRange.lowerBound)
        #expect(updateRange.upperBound >= editedRange.upperBound)
        #expect(updateRange.upperBound > requestedRange.upperBound)
        #expect(!result.highlights.isEmpty)
    }
    
    
    @Test func highlightPythonAllCapsConstantsAndConstructorCalls() async throws {
        
        let source = #"""
            from typing import IO
            from pathlib import Path
            
            MAX_SIZE = 10
            TOKEN_RE = Path("demo.txt")
            custom = UUID()
            namespaced = pkg.UUID()
            
            def load(stream: IO, path: Path) -> IO:
                return TOKEN_RE
            """#
        
        let config = try self.registry.configuration(for: .python)
        let client = try TreeSitterClient(languageConfig: config, languageProvider: self.registry.languageProvider, syntax: .python)
        let captures = try #require(await client.parseHighlights(in: source, range: source.nsRange))
            .highlights
            .map { Capture(type: $0.value, text: (source as NSString).substring(with: $0.range)) }
        
        #expect(captures.contains { $0.type == .values && $0.text == "MAX_SIZE" })
        #expect(captures.contains { $0.type == .values && $0.text == "TOKEN_RE" })
        #expect(!captures.contains { $0.type == .types && $0.text == "MAX_SIZE" })
        #expect(!captures.contains { $0.type == .types && $0.text == "TOKEN_RE" })
        #expect(captures.filter { $0.type == .types && $0.text == "UUID" }.count == 2)
        #expect(captures.filter { $0.type == .types && $0.text == "IO" }.count == 2)
        #expect(captures.contains { $0.type == .types && $0.text == "Path" })
    }
    
    
    @Test func highlightJavaScriptShadowedRequireOnlyAtCallSite() async throws {
        
        let source = #"""
            const load = () => {}
            const require = load
            
            function demo() {
              return require
            }
            
            require("./demo.js")
            """#
        
        let config = try self.registry.configuration(for: .javaScript)
        let client = try TreeSitterClient(languageConfig: config, languageProvider: self.registry.languageProvider, syntax: .javaScript)
        let captures = try #require(await client.parseHighlights(in: source, range: source.nsRange))
            .highlights
            .map { Capture(type: $0.value, text: (source as NSString).substring(with: $0.range)) }
        
        #expect(captures.filter { $0.type == .commands && $0.text == "require" }.count == 1)
    }
    
    
    @Test func highlightTypeScriptShadowedRequireOnlyAtCallSite() async throws {
        
        let source = #"""
            const load = (path: string): string => path
            const require = load
            
            function demo(require: string): string {
              return require
            }
            
            require("./demo.ts")
            """#
        
        let config = try self.registry.configuration(for: .typeScript)
        let client = try TreeSitterClient(languageConfig: config, languageProvider: self.registry.languageProvider, syntax: .typeScript)
        let captures = try #require(await client.parseHighlights(in: source, range: source.nsRange))
            .highlights
            .map { Capture(type: $0.value, text: (source as NSString).substring(with: $0.range)) }
        
        #expect(captures.filter { $0.type == .commands && $0.text == "require" }.count == 1)
    }
    
    
    @Test func highlightTypeScriptOrdinaryVariables() async throws {
        
        let source = #"""
            type User = { name: string }
            
            function greet(user: User) {
              let message = user.name
              const items = [message]
              return items
            }
            """#
        
        let config = try self.registry.configuration(for: .typeScript)
        let client = try TreeSitterClient(languageConfig: config, languageProvider: self.registry.languageProvider, syntax: .typeScript)
        let captures = try #require(await client.parseHighlights(in: source, range: source.nsRange))
            .highlights
            .map { Capture(type: $0.value, text: (source as NSString).substring(with: $0.range)) }
        
        #expect(captures.contains { $0.type == .variables && $0.text == "message" })
        #expect(captures.contains { $0.type == .variables && $0.text == "items" })
        #expect(captures.contains { $0.type == .variables && $0.text == "user" })
        #expect(captures.contains { $0.type == .types && $0.text == "User" })
    }
}


private struct Capture: Equatable {
    
    var type: SyntaxType
    var text: String
}
