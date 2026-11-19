//
//  AINextTokenPredictor.swift
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
import StringUtils
import SyntaxFormat

/// Tier-2 asynchronous Fill-in-the-Middle (FIM) Next Token predictor powered by the active AI endpoint.
///
/// Sits seamlessly behind Tier-1 local habit prediction: when local heuristics stay silent and the user
/// pauses mid-thought or mid-line, it sends a compact `<PREFIX>` + `<SUFFIX>` prompt (capped to low token
/// budget and strict timeout) with speculative caching so typing forward hits in 0ms.
@MainActor final class AINextTokenPredictor {
    
    static let shared = AINextTokenPredictor()
    
    private struct CacheEntry {
        let anchorLinePrefix: String
        let anchorLineSuffix: String
        let completion: String
        let createdAt: Date
    }
    
    private var cache: [CacheEntry] = []
    private var pendingTask: Task<Void, Never>?
    private var errorCooldownUntil: Date?
    
    
    // MARK: Settings Helpers
    
    static var isInlineCompletionEnabled: Bool {
        
        if let obj = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled) as? Bool {
            return obj
        }
        return CotLocalDatabase.shared.bool(forKey: CotLocalDatabase.ConfigKey.inlineCompletionEnabled, default: true)
    }
    
    
    static var isAINextTokenEnabled: Bool {
        
        if let obj = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled) as? Bool {
            return obj
        }
        return CotLocalDatabase.shared.bool(forKey: CotLocalDatabase.ConfigKey.aiNextTokenEnabled, default: true)
    }
    
    
    static var modelOverride: String {
        
        let raw = UserDefaults.standard.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride)
            ?? CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenModelOverride, default: "")
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    
    static var debounceMilliseconds: Int {
        
        let val = UserDefaults.standard.object(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs) as? Int
            ?? Int(CotLocalDatabase.shared.string(forKey: CotLocalDatabase.ConfigKey.aiNextTokenDebounceMs, default: "420"))
            ?? 420
        return min(1500, max(180, val))
    }
    
    
    static var effectiveConfiguration: AIConfiguration {
        
        var config = AIConfiguration.current
        let override = Self.modelOverride
        if !override.isEmpty {
            config.model = override
        }
        config.temperature = 0.15
        config.reasoningEffort = "low"
        return config
    }
    
    
    // MARK: Public API
    
    func cancel() {
        
        self.pendingTask?.cancel()
        self.pendingTask = nil
    }
    
    
    /// Checks the short-lived speculative cache for an instant 0ms hit or type-through continuation.
    func lookupCachedContinuation(linePrefix: String, lineSuffix: String) -> String? {
        
        let now = Date()
        let cleanSuffix = lineSuffix.trimmingCharacters(in: .newlines)
        
        for entry in self.cache.reversed() {
            guard now.timeIntervalSince(entry.createdAt) < 90 else { continue }
            guard entry.anchorLineSuffix == cleanSuffix else { continue }
            guard linePrefix.hasPrefix(entry.anchorLinePrefix) else { continue }
            
            let typedSinceAnchor = String(linePrefix.dropFirst(entry.anchorLinePrefix.count))
            if typedSinceAnchor.isEmpty {
                return entry.completion
            }
            if entry.completion.hasPrefix(typedSinceAnchor),
               entry.completion.count > typedSinceAnchor.count
            {
                return String(entry.completion.dropFirst(typedSinceAnchor.count))
            }
        }
        return nil
    }
    
    
    /// Schedules a debounced AI Fill-in-the-Middle completion for `textView` at its current caret.
    func schedulePrediction(
        for textView: EditorTextView,
        syntaxName: String = SyntaxName.none,
        documentTitle: String = ""
    ) {
        self.cancel()
        
        guard
            Self.isInlineCompletionEnabled,
            Self.isAINextTokenEnabled,
            textView.isEditable,
            textView.window?.isKeyWindow == true,
            !textView.hasMarkedText(),
            !textView.hasMultipleInsertions,
            textView.selectedRange.isEmpty
        else { return }
        
        if let cooldown = self.errorCooldownUntil, Date() < cooldown {
            return
        }
        
        let config = Self.effectiveConfiguration
        guard config.isUsable else { return }
        
        let nsText = textView.string as NSString
        let expectedRange = textView.selectedRange
        let caret = expectedRange.location
        guard caret >= 0, caret <= nsText.length else { return }
        
        let lineRange = nsText.lineRange(for: NSRange(location: min(caret, max(0, nsText.length - 1)), length: 0))
        let linePrefix = nsText.substring(with: NSRange(location: lineRange.location, length: max(0, caret - lineRange.location)))
        let lineEnd = NSMaxRange(lineRange)
        let lineSuffix = (caret < lineEnd)
            ? nsText.substring(with: NSRange(location: caret, length: lineEnd - caret)).trimmingCharacters(in: .newlines)
            : ""
        
        let trimmedPrefix = linePrefix.trimmingCharacters(in: .whitespaces)
        guard trimmedPrefix.count >= 4 else { return }
        
        // Avoid mid-word guesses when next char is alphanumeric
        if let firstSuffixScalar = lineSuffix.unicodeScalars.first,
           CharacterSet.alphanumerics.contains(firstSuffixScalar) || firstSuffixScalar == "_"
        {
            return
        }
        
        let prefixStart = max(0, caret - 1_000)
        let prefixContext = nsText.substring(with: NSRange(location: prefixStart, length: caret - prefixStart))
        let suffixLength = min(320, nsText.length - caret)
        let suffixContext = suffixLength > 0
            ? nsText.substring(with: NSRange(location: caret, length: suffixLength))
            : ""
        
        let isCode = (syntaxName != SyntaxName.none && syntaxName != "Plain Text")
        let debounceMs = Self.debounceMilliseconds
        
        let messages = Self.buildMessages(
            prefix: prefixContext,
            suffix: suffixContext,
            syntaxName: syntaxName,
            documentTitle: documentTitle,
            isCode: isCode
        )
        
        self.pendingTask = Task { [weak self, weak textView] in
            do {
                try await Task.sleep(for: .milliseconds(debounceMs))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, let textView else { return }
            guard textView.window?.isKeyWindow == true,
                  !textView.hasMarkedText(),
                  textView.selectedRange == expectedRange
            else { return }
            
            do {
                let client = AIClient(configuration: config, maxOutputTokens: 48, timeoutInterval: 8)
                let raw = try await client.send(messages)
                guard !Task.isCancelled else { return }
                guard let completion = Self.sanitizeCompletion(
                    raw: raw,
                    linePrefix: linePrefix,
                    lineSuffix: lineSuffix,
                    isCode: isCode
                ) else { return }
                
                self.storeCache(linePrefix: linePrefix, lineSuffix: lineSuffix, completion: completion)
                
                guard
                    textView.isEditable,
                    textView.window?.isKeyWindow == true,
                    !textView.hasMarkedText(),
                    textView.selectedRange == expectedRange,
                    textView.activeGhostSuggestion == nil
                else { return }
                
                textView.applyAIGhostSuggestion(completion)
            } catch is CancellationError {
                return
            } catch {
                // Quietly back off on failure so offline/invalid gateways never cause UI noise or spam
                self.errorCooldownUntil = Date().addingTimeInterval(15)
            }
        }
    }
    
    
    // MARK: Prompt & Sanitization (Testable)
    
    static func buildMessages(
        prefix: String,
        suffix: String,
        syntaxName: String,
        documentTitle: String,
        isCode: Bool
    ) -> [AIMessage] {
        
        let styleRule = isCode
            ? "Complete the code naturally at <CURSOR>. Output a single short line or token tail (max 45 chars)."
            : "Continue the user's sentence or note naturally at <CURSOR> in the same language and tone (max 24 chars)."
        
        let system = """
        You are an ultra-fast inline Fill-in-the-Middle autocomplete engine inside a text editor.
        Rules:
        1. Output ONLY the exact text to insert at <CURSOR>. Never explain, wrap in markdown fences, or repeat text from <PREFIX> or <SUFFIX>.
        2. Pay strict attention to <SUFFIX>: if <SUFFIX> already begins with closing punctuation like ), ], }, or trailing words, do NOT duplicate them.
        3. \(styleRule)
        4. If context is too ambiguous to predict with high confidence, output exactly: EMPTY
        """
        
        let meta = [
            documentTitle.isEmpty ? nil : "File: \(documentTitle)",
            "Syntax: \(syntaxName)",
        ].compactMap(\.self).joined(separator: " | ")
        
        let user = """
        \(meta)
        <PREFIX>\(prefix)</PREFIX><CURSOR><SUFFIX>\(suffix)</SUFFIX>
        """
        
        return [.system(system), .user(user)]
    }
    
    
    /// Cleans a raw AI FIM response into a crisp single-line inline ghost insertion,
    /// stripping prefix echo, code fences, chatter, and `lineSuffix` overlap.
    static func sanitizeCompletion(
        raw: String,
        linePrefix: String,
        lineSuffix: String,
        isCode: Bool = false
    ) -> String? {
        
        var text = raw.trimmingCharacters(in: .newlines)
        guard !text.isEmpty else { return nil }
        
        // Strip markdown code fences if the model wrapped its completion
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: .newlines)
            if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" { lines.removeLast() }
            text = lines.joined(separator: "\n")
        }
        
        // Strip XML tags if echoed
        for tag in ["<CURSOR>", "</CURSOR>", "<COMPLETION>", "</COMPLETION>"] {
            text = text.replacingOccurrences(of: tag, with: "")
        }
        
        // Take the first non-empty line
        guard let firstLine = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        
        var clean = firstLine
        let trimmedUpper = clean.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmedUpper == "EMPTY" || trimmedUpper == "NONE" || trimmedUpper == "[EMPTY]" || trimmedUpper == "N/A" {
            return nil
        }
        
        // Strip accidental prefix echo (e.g. prefix ends with "进行" and completion starts with "进行一次commit")
        let maxEcho = min(24, linePrefix.count, clean.count)
        if maxEcho >= 2 {
            for len in stride(from: maxEcho, through: 2, by: -1) {
                let candidateEcho = String(clean.prefix(len))
                if linePrefix.hasSuffix(candidateEcho), clean.count > len {
                    clean.removeFirst(len)
                    break
                }
            }
        }
        if linePrefix.hasSuffix(" ") && clean.hasPrefix(" ") {
            while clean.hasPrefix(" ") {
                clean.removeFirst()
            }
        }
        
        // Reject leading conversational meta-replies
        let lowerClean = clean.trimmingCharacters(in: .whitespaces).lowercased()
        if lowerClean.hasPrefix("here is") || lowerClean.hasPrefix("sure,") || lowerClean.hasPrefix("certainly") {
            return nil
        }
        
        // Strip suffix overlap (e.g. trailing `)` already right after the cursor)
        guard let trimmedSuffix = UserHabitPredictor.trimOverlapWithLineSuffix(clean, lineSuffix: lineSuffix) else {
            return nil
        }
        clean = trimmedSuffix
        
        let maxLength = isCode ? 72 : 42
        if clean.count > maxLength {
            let capped = String(clean.prefix(maxLength))
            if let breakIdx = capped.lastIndex(where: { $0 == " " || $0 == "，" || $0 == "," || $0 == "。" || $0 == ";" }),
               capped.distance(from: capped.startIndex, to: breakIdx) >= maxLength / 2
            {
                clean = String(capped[..<breakIdx])
            } else {
                clean = capped
            }
        }
        
        return clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : clean
    }
    
    
    // MARK: Private Helpers
    
    private func storeCache(linePrefix: String, lineSuffix: String, completion: String) {
        
        let cleanSuffix = lineSuffix.trimmingCharacters(in: .newlines)
        self.cache.removeAll { $0.anchorLinePrefix == linePrefix && $0.anchorLineSuffix == cleanSuffix }
        self.cache.append(CacheEntry(
            anchorLinePrefix: linePrefix,
            anchorLineSuffix: cleanSuffix,
            completion: completion,
            createdAt: Date()
        ))
        if self.cache.count > 48 {
            self.cache.removeFirst(self.cache.count - 48)
        }
    }
}
