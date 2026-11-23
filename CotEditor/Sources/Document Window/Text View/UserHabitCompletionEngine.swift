//
//  UserHabitCompletionEngine.swift
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

/// High-confidence, single-best-candidate inline completion predictor tailored to the user's typing habits
/// and live document context.
///
/// Never presents a popup menu or multiple candidates — always selects at most one highest-probability
/// continuation when confidence is strong, staying completely silent otherwise.
@MainActor final class UserHabitPredictor {
    
    static let shared = UserHabitPredictor()
    
    struct HabitRule {
        let triggers: [String]
        let candidate: String
    }
    
    nonisolated struct LearnedHabitChain: Identifiable, Sendable, Equatable {
        
        var id: String
        var trigger: String
        var candidate: String
        var count: Int
    }
    
    /// Built-in high-confidence workflow & writing habits (short, natural next-phrase completions).
    private static let builtInHabits: [HabitRule] = [
        HabitRule(
            triggers: [
                "这些都搞定了以后",
                "这些都搞定以后",
                "都搞定了以后",
                "都搞定以后",
                "搞定了以后",
                "搞定以后",
                "这些搞定了以后",
                "全部搞定了以后",
                "快点搞定",
                "全部搞定",
            ],
            candidate: "进行一次commit"
        ),
        HabitRule(
            triggers: [
                "代码",
                "把代码",
                "将代码",
                "然后代码",
                "修改代码",
                "改动代码",
            ],
            candidate: "推送到远程仓库"
        ),
        HabitRule(
            triggers: [
                "进行一次commit，然后",
                "进行一次commit,然后",
                "进行一次commit",
                "commit后",
                "commit以后",
                "commit之后",
                "提交代码",
                "完成commit",
            ],
            candidate: "推送到远程仓库"
        ),
        HabitRule(
            triggers: [
                "推送到远程仓库，然后",
                "推送到远程仓库,然后",
                "推送到远程仓库",
                "推送到远程",
            ],
            candidate: "本地重新编译一下"
        ),
        HabitRule(
            triggers: [
                "本周主要",
                "这周主要",
            ],
            candidate: "干了以下几件事："
        ),
        HabitRule(
            triggers: [
                "下周计划",
                "下周主要",
            ],
            candidate: "推进以下工作："
        ),
        HabitRule(
            triggers: [
                "存在的问题",
                "风险与问题",
                "当前风险",
            ],
            candidate: "及解决方案："
        ),
        HabitRule(
            triggers: [
                "下周重点",
                "后续计划",
            ],
            candidate: "如下："
        ),
        HabitRule(
            triggers: [
                "单元测试",
                "跑一遍测试",
                "测试通过后",
            ],
            candidate: "提交并推送代码"
        ),
    ]
    
    private struct PersistedHabitModel: Codable {
        let transitions: [String: [String: Int]]
        let compoundTransitions: [String: [String: Int]]
        let prefixFrequencies: [String: Int]?
    }
    
    /// Single-step transition frequency table: `contextSuffix -> [nextTokenOrClause: count]`.
    private(set) var transitions: [String: [String: Int]] = [:]
    
    /// Two-token cohesive next-phrase frequency table: `contextSuffix -> [nextTwoTokens: count]`.
    private(set) var compoundTransitions: [String: [String: Int]] = [:]
    
    /// Personal vocabulary / phrase frequency table learned from user documents and accepted completions.
    private(set) var vocabularyFrequencies: [String: Int] = [:]
    
    private static let identifierRegex: NSRegularExpression = try! NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]{3,28}")
    private static let listPrefixRegex: NSRegularExpression = try! NSRegularExpression(
        pattern: #"^\s*(?:\d{1,2}\s*[\.、\)）](?!\d)\s*|[(（]\d{1,2}[)）]\s*|[-*•·▪︎‣]\s+)"#
    )
    private static let clauseSeparatorSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "，,：:、"))
    private static let continuationTrimSet = CharacterSet(charactersIn: " ，,：:、")
    private static let continuationStopSet = CharacterSet.newlines.union(CharacterSet(charactersIn: "。！？；!?;，,：:（）()[]\"'"))
    
    private var persistenceKey: String?
    private var saveTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    private var learnTask: Task<Void, Never>?
    private var pendingLearnLines: [String] = []
    private var didWarmUpFromDatabase = false
    
    
    init(persistenceKey: String? = CotLocalDatabase.ConfigKey.userHabitModelJSON) {
        
        self.persistenceKey = persistenceKey
        if let persistenceKey {
            self.loadPersistedTransitions(forKey: persistenceKey)
        } else {
            self.didWarmUpFromDatabase = true
        }
    }
    
    
    // MARK: Public API
    
    /// Clears in-memory habit models and reloads them from the newly active user's database.
    func reloadFromDatabase() {
        
        self.saveTask?.cancel()
        self.saveTask = nil
        self.warmUpTask?.cancel()
        self.warmUpTask = nil
        self.learnTask?.cancel()
        self.learnTask = nil
        self.pendingLearnLines.removeAll()
        self.transitions.removeAll()
        self.compoundTransitions.removeAll()
        self.vocabularyFrequencies.removeAll()
        
        if let persistenceKey = self.persistenceKey {
            self.didWarmUpFromDatabase = false
            self.loadPersistedTransitions(forKey: persistenceKey)
            self.scheduleWarmUpFromDatabaseIfNeeded()
        } else {
            self.didWarmUpFromDatabase = true
        }
    }
    
    
    /// Warms up habit transitions asynchronously in tiny slices so the first keystroke never blocks the main thread.
    func scheduleWarmUpFromDatabaseIfNeeded() {
        
        guard !self.didWarmUpFromDatabase, self.warmUpTask == nil else { return }
        self.didWarmUpFromDatabase = true
        
        let docContents = CotLocalDatabase.shared.documents.prefix(40).map(\.content)
        let reportContents = CotLocalDatabase.shared.weeklyReports.prefix(20).map(\.content)
        guard !docContents.isEmpty || !reportContents.isEmpty else { return }
        
        self.warmUpTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            for content in docContents {
                guard let self, !Task.isCancelled else { return }
                self.learn(from: content, persist: false)
                await Task.yield()
            }
            for content in reportContents {
                guard let self, !Task.isCancelled else { return }
                self.learn(from: content, persist: false)
                await Task.yield()
            }
            guard let self, !Task.isCancelled else { return }
            self.warmUpTask = nil
            self.scheduleSave()
        }
    }
    
    
    /// Warms up habit transitions once from the user's stored documents in `CotLocalDatabase`.
    func warmUpFromDatabaseIfNeeded() {
        
        guard !self.didWarmUpFromDatabase else { return }
        self.didWarmUpFromDatabase = true
        
        for record in CotLocalDatabase.shared.documents.prefix(40) {
            self.learn(from: record.content, persist: false)
        }
        for report in CotLocalDatabase.shared.weeklyReports.prefix(20) {
            self.learn(from: report.content, persist: false)
        }
        self.scheduleSave()
    }
    
    
    /// Coalesces single-line learning off the Enter/typing hot path so pressing Return is always instant.
    func scheduleLearn(line: String) {
        
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6, trimmed.count <= 320 else { return }
        self.pendingLearnLines.append(trimmed)
        if self.pendingLearnLines.count > 24 {
            self.pendingLearnLines.removeFirst(self.pendingLearnLines.count - 24)
        }
        self.learnTask?.cancel()
        self.learnTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            let batch = self.pendingLearnLines
            self.pendingLearnLines.removeAll()
            guard !batch.isEmpty else { return }
            self.learn(from: batch.joined(separator: "\n"), persist: true)
        }
    }
    
    
    /// Returns the count of learned transition patterns, vocabulary entries, and highest-frequency habit chains.
    func habitSnapshot(limit: Int = 6) -> (transitionCount: Int, vocabularyCount: Int, topChains: [LearnedHabitChain]) {
        
        self.warmUpFromDatabaseIfNeeded()
        
        var candidates: [LearnedHabitChain] = []
        var seenPairs = Set<String>()
        
        for (trigger, targets) in self.compoundTransitions {
            let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanTrigger.count >= 2 else { continue }
            for (next, count) in targets where count >= 1 {
                let cleanNext = next.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanNext.count >= 2, cleanNext != cleanTrigger else { continue }
                let pairKey = "\(cleanTrigger)->\(cleanNext)"
                guard seenPairs.insert(pairKey).inserted else { continue }
                candidates.append(LearnedHabitChain(
                    id: pairKey,
                    trigger: cleanTrigger,
                    candidate: cleanNext,
                    count: count
                ))
            }
        }
        
        for (trigger, targets) in self.transitions {
            let cleanTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanTrigger.count >= 2 else { continue }
            for (next, count) in targets where count >= 2 {
                let cleanNext = next.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanNext.count >= 2, cleanNext != cleanTrigger else { continue }
                let pairKey = "\(cleanTrigger)->\(cleanNext)"
                guard seenPairs.insert(pairKey).inserted else { continue }
                candidates.append(LearnedHabitChain(
                    id: pairKey,
                    trigger: cleanTrigger,
                    candidate: cleanNext,
                    count: count
                ))
            }
        }
        
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.candidate.count > rhs.candidate.count
        }
        
        return (
            transitionCount: self.transitions.count + self.compoundTransitions.count,
            vocabularyCount: self.vocabularyFrequencies.count,
            topChains: Array(sorted.prefix(max(0, limit)))
        )
    }
    
    
    /// Predicts the single highest-probability short continuation for the current caret location,
    /// or `nil` when confidence is below threshold.
    func predictNextPhrase(
        in text: String,
        caretLocation: Int,
        syntaxWords: [String] = [],
        siblingTexts: [String] = []
    ) -> String? {
        
        self.scheduleWarmUpFromDatabaseIfNeeded()
        
        let nsText = text as NSString
        guard caretLocation > 0, caretLocation <= nsText.length else { return nil }
        
        // Do not suggest inline ghost text inside the middle of an existing word or identifier.
        if caretLocation < nsText.length {
            let nextChar = nsText.character(at: caretLocation)
            if !self.isBoundaryCharacter(nextChar) {
                return nil
            }
        }
        
        let lineRange = nsText.lineRange(for: NSRange(location: max(0, caretLocation - 1), length: 0))
        let prefixLength = caretLocation - lineRange.location
        guard prefixLength >= 2 else { return nil }
        
        let rawLinePrefix = nsText.substring(with: NSRange(location: lineRange.location, length: prefixLength))
        let lineEnd = NSMaxRange(lineRange)
        let rawLineSuffix = (caretLocation < lineEnd)
            ? nsText.substring(with: NSRange(location: caretLocation, length: lineEnd - caretLocation))
            : ""
        let lineSuffix = rawLineSuffix.trimmingCharacters(in: .newlines)
        let window = String(rawLinePrefix.suffix(56))
        
        // 1. Exact or partial match against high-confidence built-in workflow habits
        if let builtInMatch = self.matchBuiltInHabits(linePrefix: window),
           let sanitized = Self.trimOverlapWithLineSuffix(builtInMatch, lineSuffix: lineSuffix)
        {
            return sanitized
        }
        
        // 2. Learned personal habit transitions (n-gram & compound phrase transitions)
        if let learnedMatch = self.matchLearnedTransition(linePrefix: window),
           let sanitized = Self.trimOverlapWithLineSuffix(learnedMatch, lineSuffix: lineSuffix)
        {
            return sanitized
        }
        
        // 3. Live in-document and sibling-tab contextual n-gram / repeated phrase continuation
        if let docContextMatch = self.matchLiveDocumentContext(
            in: nsText,
            caretLocation: caretLocation,
            linePrefix: window,
            siblingTexts: siblingTexts
        ),
           let sanitized = Self.trimOverlapWithLineSuffix(docContextMatch, lineSuffix: lineSuffix)
        {
            return sanitized
        }
        
        // 4. Single best identifier / vocabulary prefix completion (replaces popup completion list)
        if let wordCompletion = self.matchBestWordPrefix(in: nsText, caretLocation: caretLocation, linePrefix: window, syntaxWords: syntaxWords),
           let sanitized = Self.trimOverlapWithLineSuffix(wordCompletion, lineSuffix: lineSuffix)
        {
            return sanitized
        }
        
        return nil
    }
    
    
    /// Strips any suffix of `candidate` that already duplicates the start of `lineSuffix`
    /// (for example closing `)` or trailing clause text already after the caret).
    static func trimOverlapWithLineSuffix(_ candidate: String, lineSuffix: String) -> String? {
        
        var trimmed = candidate
        guard !trimmed.isEmpty else { return nil }
        
        let cleanSuffix = lineSuffix.trimmingCharacters(in: .newlines)
        guard !cleanSuffix.isEmpty else { return trimmed }
        
        let maxOverlap = min(trimmed.count, cleanSuffix.count)
        if maxOverlap > 0 {
            for len in stride(from: maxOverlap, through: 1, by: -1) {
                let suffixPart = String(cleanSuffix.prefix(len))
                if trimmed.hasSuffix(suffixPart) {
                    trimmed.removeLast(len)
                    break
                }
            }
        }
        
        let trimmedNoTrailingSpace = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNoTrailingSpace.isEmpty ? nil : trimmed
    }
    
    
    /// Splits the first logical chunk (one ASCII word or short CJK clause unit) from a ghost suggestion
    /// for progressive `Option + Right Arrow` acceptance.
    static func splitFirstAcceptUnit(from suggestion: String) -> (accepted: String, remainder: String) {
        
        guard suggestion.count > 3 else {
            return (suggestion, "")
        }
        
        let chars = Array(suggestion)
        var index = 0
        
        // Consume any leading whitespace/punctuation
        while index < chars.count, chars[index].isWhitespace || chars[index].isPunctuation {
            index += 1
        }
        
        if index < chars.count {
            let first = chars[index]
            if first.isASCII && (first.isLetter || first.isNumber || first == "_") {
                while index < chars.count,
                      chars[index].isASCII && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_")
                {
                    index += 1
                }
                // Include one trailing space with the word
                if index < chars.count, chars[index] == " " {
                    index += 1
                }
            } else {
                // CJK or non-ASCII chunk: take a 2-character word unit up to boundary
                var taken = 0
                while index < chars.count, taken < 2,
                      !chars[index].isASCII, !chars[index].isWhitespace, !chars[index].isPunctuation
                {
                    index += 1
                    taken += 1
                }
                if taken == 0 {
                    index = min(chars.count, index + 1)
                }
            }
        }
        
        // Avoid leaving a tiny 1-char tail
        if chars.count - index <= 1 {
            return (suggestion, "")
        }
        
        let accepted = String(chars[..<index])
        let remainder = String(chars[index...])
        return (accepted, remainder)
    }
    
    
    /// Learns repeated short phrase transitions and vocabulary from user text (saved or actively edited).
    func learn(from text: String, persist: Bool = true) {
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return }
        
        let lines = trimmed.components(separatedBy: .newlines)
        var didUpdate = false
        
        for rawLine in lines.prefix(400) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.count >= 4, line.count <= 300 else { continue }
            
            // Split line into natural clauses at sentence boundaries
            let clauses = line.components(separatedBy: CharacterSet(charactersIn: "。！？；!?;"))
            for rawClause in clauses {
                let clause = rawClause.trimmingCharacters(in: .whitespaces)
                guard clause.count >= 4 else { continue }
                
                let tokens = self.tokenizeClause(clause)
                for token in tokens where token.count >= 4 && token.count <= 24 {
                    self.recordVocabulary(token, weight: 1)
                }
                guard tokens.count >= 2 else { continue }
                
                // Record bigram & trigram transitions between adjacent meaningful chunks
                for i in 0..<(tokens.count - 1) {
                    let next = tokens[i + 1]
                    guard next.count >= 2, next.count <= 14 else { continue }
                    
                    var contextKeys: [String] = []
                    if tokens[i].count >= 2, tokens[i].count <= 12 {
                        contextKeys.append(tokens[i])
                    }
                    if i >= 1 {
                        let twoTokenKey = tokens[i - 1] + tokens[i]
                        if twoTokenKey.count >= 2, twoTokenKey.count <= 12 {
                            contextKeys.append(twoTokenKey)
                        }
                    }
                    if i >= 2 {
                        let threeTokenKey = tokens[i - 2] + tokens[i - 1] + tokens[i]
                        if threeTokenKey.count >= 3, threeTokenKey.count <= 12 {
                            contextKeys.append(threeTokenKey)
                        }
                    }
                    
                    for key in contextKeys where key != next {
                        self.recordTransition(from: key, to: next, in: \.transitions)
                        didUpdate = true
                        
                        if i + 2 < tokens.count {
                            let combinedNext = tokens[i + 1] + tokens[i + 2]
                            if combinedNext.count <= 14 {
                                self.recordTransition(from: key, to: combinedNext, in: \.compoundTransitions)
                            }
                        }
                    }
                }
                
                // Record comma-separated clause continuation when concise
                let subClauses = clause.components(separatedBy: CharacterSet(charactersIn: "，,：:"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                if subClauses.count >= 2 {
                    for i in 0..<(subClauses.count - 1) {
                        let left = String(subClauses[i].suffix(10))
                        let right = subClauses[i + 1]
                        guard left.count >= 2, right.count >= 2, right.count <= 14, left != right else { continue }
                        self.recordTransition(from: left, to: right, in: \.compoundTransitions)
                        didUpdate = true
                    }
                }
            }
        }
        
        if didUpdate && persist {
            self.scheduleSave()
        }
    }
    
    
    /// Learns an explicitly accepted or completed phrase transition right around the caret with boosted weight.
    func recordAcceptedCompletion(prefixContext: String, acceptedPhrase: String) {
        
        let key = self.normalizedContextSuffix(prefixContext)
        let candidate = acceptedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count >= 1, candidate.count <= 24 else { return }
        
        if key.count >= 2, candidate.count >= 2, candidate.count <= 14 {
            self.recordTransition(from: key, to: candidate, in: \.compoundTransitions, weight: 3)
            let tokens = self.tokenizeClause(key)
            if let lastToken = tokens.last, lastToken.count >= 2 {
                self.recordTransition(from: lastToken, to: candidate, in: \.transitions, weight: 2)
            }
        }
        
        // If user completed the tail of an identifier/word, boost the full word in vocabulary
        if let partial = self.trailingIdentifierPrefix(in: prefixContext) {
            let fullWord = partial + candidate
            if fullWord.count >= 4, fullWord.count <= 28 {
                self.recordVocabulary(fullWord, weight: 4)
            }
        }
        
        self.scheduleSave()
    }
    
    
    /// Clears learned habit transitions (mostly for testing).
    func resetLearnedHabits() {
        
        self.transitions.removeAll()
        self.compoundTransitions.removeAll()
        self.vocabularyFrequencies.removeAll()
        if let persistenceKey {
            CotLocalDatabase.shared.removeConfig(forKey: persistenceKey)
        }
    }
    
    
    // MARK: Private Prediction Engines
    
    private func matchBuiltInHabits(linePrefix: String) -> String? {
        
        let trimmedTrailingPunctuation = self.trimTrailingClausePunctuation(linePrefix)
        
        // Check exact trigger match at the end of the typed prefix
        for rule in Self.builtInHabits {
            for trigger in rule.triggers {
                if trimmedTrailingPunctuation.hasSuffix(trigger) {
                    return rule.candidate
                }
            }
        }
        
        // Check partial continuation (e.g. user typed "这些都搞定了以后，进行" -> predict "一次commit")
        for rule in Self.builtInHabits {
            let candidate = rule.candidate
            let maxOverlap = min(candidate.count - 1, linePrefix.count)
            guard maxOverlap >= 1 else { continue }
            
            for overlapLen in stride(from: maxOverlap, through: 1, by: -1) {
                let typedSuffix = String(linePrefix.suffix(overlapLen))
                if candidate.hasPrefix(typedSuffix) {
                    let prefixBeforePartial = self.trimTrailingClausePunctuation(String(linePrefix.dropLast(overlapLen)))
                    if rule.triggers.contains(where: { prefixBeforePartial.hasSuffix($0) }) {
                        let remainder = String(candidate.dropFirst(overlapLen))
                        if !remainder.isEmpty {
                            return remainder
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    
    private func matchLearnedTransition(linePrefix: String) -> String? {
        
        guard !self.transitions.isEmpty || !self.compoundTransitions.isEmpty else { return nil }
        
        let cleanPrefix = self.trimTrailingClausePunctuation(linePrefix)
        guard cleanPrefix.count >= 2 else { return nil }
        
        // 1. Direct lookup using longest matching trailing key (prefer longer, more specific context)
        let candidateKeys = self.candidateContextKeys(from: cleanPrefix, includeTokenized: true)
        for key in candidateKeys {
            if let suggestion = self.highConfidenceCandidate(for: key) {
                return suggestion
            }
        }
        
        // 2. Partial continuation against learned high-confidence candidates (suffix-only keys avoid repeated CFStringTokenizer calls)
        for overlapLen in stride(from: min(6, cleanPrefix.count - 2), through: 1, by: -1) {
            let partial = String(cleanPrefix.suffix(overlapLen))
            let beforePartial = self.trimTrailingClausePunctuation(String(cleanPrefix.dropLast(overlapLen)))
            guard beforePartial.count >= 2 else { continue }
            for key in self.candidateContextKeys(from: beforePartial, includeTokenized: false) {
                if let candidate = self.highConfidenceCandidate(for: key),
                   candidate.hasPrefix(partial),
                   candidate.count > overlapLen
                {
                    return String(candidate.dropFirst(overlapLen))
                }
            }
        }
        
        return nil
    }
    
    
    /// Scans the nearby document window (`±8000` chars) and optional sibling open documents for
    /// contextual continuations following the exact phrase or CJK/word suffix the user just typed.
    private func matchLiveDocumentContext(
        in nsText: NSString,
        caretLocation: Int,
        linePrefix: String,
        siblingTexts: [String]
    ) -> String? {
        
        let cleanPrefix = self.trimTrailingClausePunctuation(linePrefix)
        guard cleanPrefix.count >= 3 else { return nil }
        
        let anchorLen = min(6, cleanPrefix.count)
        let anchor = String(cleanPrefix.suffix(anchorLen))
        guard anchor.count >= 3 else { return nil }
        
        let windowStart = max(0, caretLocation - 8_000)
        let precedingLength = max(0, caretLocation - anchor.count - windowStart)
        
        var continuations: [String: Int] = [:]
        var lastSeenRank: [String: Int] = [:]
        var occurrence = 0
        
        func scan(haystack: NSString, weight: Int) {
            var searchRange = NSRange(location: 0, length: haystack.length)
            while searchRange.length >= anchor.count {
                let found = haystack.range(of: anchor, options: [], range: searchRange)
                if found.location == NSNotFound { break }
                
                let afterIdx = NSMaxRange(found)
                let maxTake = min(14, haystack.length - afterIdx)
                if maxTake >= 2 {
                    let rawFollow = haystack.substring(with: NSRange(location: afterIdx, length: maxTake))
                    if let cleanCont = self.extractCleanContinuation(from: rawFollow),
                       cleanCont.count >= 2, cleanCont.count <= 12
                    {
                        occurrence += 1
                        continuations[cleanCont, default: 0] += weight
                        lastSeenRank[cleanCont] = occurrence
                    }
                }
                
                let nextStart = found.location + max(1, found.length)
                searchRange = NSRange(location: nextStart, length: haystack.length - nextStart)
            }
        }
        
        if precedingLength >= anchor.count {
            let searchSpace = nsText.substring(with: NSRange(location: windowStart, length: precedingLength)) as NSString
            scan(haystack: searchSpace, weight: 2)
        }
        
        for sibling in siblingTexts.prefix(5) where sibling.count >= anchor.count + 2 {
            let slice = String(sibling.prefix(4_000)) as NSString
            scan(haystack: slice, weight: 1)
        }
        
        guard !continuations.isEmpty else { return nil }
        let total = continuations.values.reduce(0, +)
        guard let best = continuations.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return (lastSeenRank[lhs.key] ?? 0) < (lastSeenRank[rhs.key] ?? 0)
        }) else { return nil }
        
        // Require >=2 weighted occurrences with >=50% consistency (or 1 exact match on >=6-char anchor).
        let isLongSpecificAnchor = anchor.count >= 6
        let minScore = isLongSpecificAnchor ? 2 : 3
        let confidence = Double(best.value) / Double(max(1, total))
        guard best.value >= minScore, confidence >= 0.50 else { return nil }
        return best.key
    }
    
    
    /// Single highest-probability identifier/word completion when the user is typing an ASCII/code token (`>= 3` chars).
    private func matchBestWordPrefix(
        in nsText: NSString,
        caretLocation: Int,
        linePrefix: String,
        syntaxWords: [String]
    ) -> String? {
        
        guard let partial = self.trailingIdentifierPrefix(in: linePrefix),
              partial.count >= 3, partial.count <= 20
        else { return nil }
        
        let lowerPartial = partial.lowercased()
        var scores: [String: Double] = [:]
        
        // 1. Scan nearby document identifiers (recency + frequency weighted)
        let scanStart = max(0, caretLocation - 12_000)
        let scanEnd = min(nsText.length, caretLocation + 4_000)
        let docSlice = nsText.substring(with: NSRange(location: scanStart, length: scanEnd - scanStart))
        let caretInSlice = caretLocation - scanStart
        
        let nsSlice = docSlice as NSString
        let matches = Self.identifierRegex.matches(in: docSlice, range: NSRange(location: 0, length: nsSlice.length))
        for match in matches {
            // Skip the token currently being typed at the caret
            if match.range.location <= caretInSlice && NSMaxRange(match.range) >= caretInSlice {
                continue
            }
            let word = nsSlice.substring(with: match.range)
            guard word.count > partial.count else { continue }
            
            if word.hasPrefix(partial) {
                let distance = abs(match.range.location - caretInSlice)
                let recencyBoost = distance < 600 ? 3.2 : (distance < 2500 ? 2.0 : 1.2)
                scores[word, default: 0] += recencyBoost
            } else if word.lowercased().hasPrefix(lowerPartial) {
                scores[word, default: 0] += 0.9
            }
        }
        
        // 2. Personal learned vocabulary
        for (vocabWord, freq) in self.vocabularyFrequencies where vocabWord.count > partial.count {
            if vocabWord.hasPrefix(partial) {
                scores[vocabWord, default: 0] += min(6.0, Double(freq) * 1.1)
            }
        }
        
        // 3. Syntax completion keywords (only exact case-prefix match)
        for kw in syntaxWords where kw.count > partial.count && kw.count <= 24 {
            if kw.hasPrefix(partial) {
                scores[kw, default: 0] += 2.2
            }
        }
        
        guard !scores.isEmpty else { return nil }
        let totalScore = scores.values.reduce(0, +)
        guard let best = scores.max(by: { lhs, rhs in
            if abs(lhs.value - rhs.value) > 0.01 { return lhs.value < rhs.value }
            return lhs.key.count > rhs.key.count  // prefer more concise completion on ties
        }) else { return nil }
        
        // Require clear winner score so we never guess randomly
        let share = best.value / max(1.0, totalScore)
        guard best.value >= 2.2, (share >= 0.45 || best.value >= 5.0) else { return nil }
        
        let remainder = String(best.key.dropFirst(partial.count))
        return remainder.isEmpty ? nil : remainder
    }
    
    
    // MARK: Private Helpers
    
    private func extractCleanContinuation(from rawFollow: String) -> String? {
        
        var trimmed = rawFollow
        while let first = trimmed.unicodeScalars.first,
              Self.continuationTrimSet.contains(first)
        {
            trimmed.removeFirst()
        }
        if let stopRange = trimmed.rangeOfCharacter(from: Self.continuationStopSet) {
            trimmed = String(trimmed[..<stopRange.lowerBound])
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nsTrimmed = trimmed as NSString
        if Self.listPrefixRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsTrimmed.length)) != nil {
            return nil
        }
        return trimmed
    }
    
    
    private func trailingIdentifierPrefix(in text: String) -> String? {
        
        var scalars: [UnicodeScalar] = []
        for scalar in text.unicodeScalars.reversed() {
            let isIdent = (scalar.value >= 65 && scalar.value <= 90)
                || (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57)
                || scalar.value == 95
            if isIdent {
                scalars.append(scalar)
            } else {
                break
            }
        }
        guard !scalars.isEmpty else { return nil }
        let ordered = scalars.reversed()
        guard let first = ordered.first, !(first.value >= 48 && first.value <= 57) else { return nil }
        return String(String.UnicodeScalarView(ordered))
    }
    
    
    private func highConfidenceCandidate(for key: String) -> String? {
        
        if let compound = self.topConfidentEntry(in: self.compoundTransitions[key]) {
            return compound
        }
        return self.topConfidentEntry(in: self.transitions[key])
    }
    
    
    private func topConfidentEntry(in counts: [String: Int]?) -> String? {
        
        guard let counts, !counts.isEmpty else { return nil }
        let total = counts.values.reduce(0, +)
        guard total >= 2 else { return nil }
        
        let sorted = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.count < rhs.key.count
        }
        let best = sorted[0]
        guard best.key.count <= 16 else { return nil }
        
        let secondCount = sorted.count > 1 ? sorted[1].value : 0
        let confidence = Double(best.value) / Double(total)
        let isConfident =
            (best.value >= 2 && confidence >= 0.55)
            || (best.value >= 5 && confidence >= 0.34 && Double(best.value) >= Double(secondCount) * 1.3)
            || (best.value >= 25 && confidence >= 0.28 && Double(best.value) >= Double(secondCount) * 1.2)
        
        guard isConfident else { return nil }
        return best.key
    }
    
    
    private func candidateContextKeys(from cleanPrefix: String, includeTokenized: Bool = true) -> [String] {
        
        var keys: [String] = []
        if includeTokenized {
            let tokens = self.tokenizeClause(cleanPrefix)
            if tokens.count >= 2 {
                let lastTwo = tokens[tokens.count - 2] + tokens[tokens.count - 1]
                if lastTwo.count >= 2, lastTwo.count <= 12 {
                    keys.append(lastTwo)
                }
            }
            if let lastToken = tokens.last, lastToken.count >= 2 {
                keys.append(lastToken)
            }
        }
        for length in stride(from: min(10, cleanPrefix.count), through: 2, by: -1) {
            let suffix = String(cleanPrefix.suffix(length))
            if !keys.contains(suffix) {
                keys.append(suffix)
            }
        }
        return keys
    }
    
    
    private func tokenizeClause(_ clause: String) -> [String] {
        
        let ns = clause as NSString
        var result: [String] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            let token = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                result.append(token)
            }
        }
        return result
    }
    
    
    private func trimTrailingClausePunctuation(_ string: String) -> String {
        
        var s = string
        while let last = s.unicodeScalars.last, Self.clauseSeparatorSet.contains(last) {
            s.removeLast()
        }
        return s
    }
    
    
    private func normalizedContextSuffix(_ string: String) -> String {
        
        let trimmed = self.trimTrailingClausePunctuation(string)
        return String(trimmed.suffix(10))
    }
    
    
    private func recordVocabulary(_ word: String, weight: Int) {
        
        self.vocabularyFrequencies[word, default: 0] += weight
        if self.vocabularyFrequencies.count > 800 {
            let kept = self.vocabularyFrequencies.sorted { $0.value > $1.value }.prefix(600)
            self.vocabularyFrequencies = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }
    
    
    private func recordTransition(
        from key: String,
        to next: String,
        in keyPath: ReferenceWritableKeyPath<UserHabitPredictor, [String: [String: Int]]>,
        weight: Int = 1
    ) {
        var table = self[keyPath: keyPath]
        var bucket = table[key] ?? [:]
        bucket[next, default: 0] += weight
        
        // Cap per-key and total dictionary size to keep lookup instant and memory tiny
        if bucket.count > 12 {
            let pruned = bucket.sorted(by: { $0.value > $1.value }).prefix(8)
            bucket = Dictionary(uniqueKeysWithValues: pruned.map { ($0.key, $0.value) })
        }
        table[key] = bucket
        
        if table.count > 600 {
            let kept = table
                .map { ($0.key, $0.value, $0.value.values.reduce(0, +)) }
                .sorted { $0.2 > $1.2 }
                .prefix(450)
            table = Dictionary(uniqueKeysWithValues: kept.map { ($0.0, $0.1) })
        }
        self[keyPath: keyPath] = table
    }
    
    
    private func isBoundaryCharacter(_ ch: unichar) -> Bool {
        
        if ch == 32 || ch == 9 || ch == 10 || ch == 13 { return true }
        guard let scalar = Unicode.Scalar(ch) else { return true }
        return !CharacterSet.alphanumerics.contains(scalar) && ch != 95
    }
    
    
    private func loadPersistedTransitions(forKey key: String) {
        
        let raw = CotLocalDatabase.shared.string(forKey: key)
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return }
        
        if let model = try? JSONDecoder().decode(PersistedHabitModel.self, from: data) {
            self.transitions = model.transitions
            self.compoundTransitions = model.compoundTransitions
            self.vocabularyFrequencies = model.prefixFrequencies ?? [:]
        } else if let decoded = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            self.transitions = decoded
        }
    }
    
    
    private func scheduleSave() {
        
        guard let persistenceKey = self.persistenceKey else { return }
        self.saveTask?.cancel()
        self.saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            let model = PersistedHabitModel(
                transitions: self.transitions,
                compoundTransitions: self.compoundTransitions,
                prefixFrequencies: self.vocabularyFrequencies
            )
            if let data = try? JSONEncoder().encode(model),
               let json = String(data: data, encoding: .utf8)
            {
                CotLocalDatabase.shared.set(json, forKey: persistenceKey)
            }
        }
    }
}
