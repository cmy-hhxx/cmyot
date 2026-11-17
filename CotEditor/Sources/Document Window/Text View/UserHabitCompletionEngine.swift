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

/// High-confidence, non-intrusive inline completion predictor tailored to the user's typing habits.
///
/// Only emits short next-word / next-phrase candidates when confidence is high (`>= 65%` across
/// repeated user patterns or exact workflow triggers), staying completely silent otherwise.
@MainActor final class UserHabitPredictor {
    
    static let shared = UserHabitPredictor()
    
    struct HabitRule {
        let triggers: [String]
        let candidate: String
    }
    
    /// Built-in high-confidence workflow habits (short, natural next-phrase completions).
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
                "commit后",
                "commit以后",
                "commit之后",
            ],
            candidate: "推送到远程仓库"
        ),
        HabitRule(
            triggers: [
                "提交代码",
                "完成commit",
            ],
            candidate: "推送到远程仓库"
        ),
        HabitRule(
            triggers: [
                "本周主要",
                "这周主要",
            ],
            candidate: "干了以下几件事："
        ),
    ]
    
    private struct PersistedHabitModel: Codable {
        let transitions: [String: [String: Int]]
        let compoundTransitions: [String: [String: Int]]
    }
    
    /// Single-step transition frequency table: `contextSuffix -> [nextTokenOrClause: count]`.
    private(set) var transitions: [String: [String: Int]] = [:]
    
    /// Two-token cohesive next-phrase frequency table: `contextSuffix -> [nextTwoTokens: count]`.
    private(set) var compoundTransitions: [String: [String: Int]] = [:]
    
    private var persistenceKey: String?
    private var saveTask: Task<Void, Never>?
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
    
    /// Warms up habit transitions once from the user's stored documents in `CotLocalDatabase`.
    func warmUpFromDatabaseIfNeeded() {
        
        guard !self.didWarmUpFromDatabase else { return }
        self.didWarmUpFromDatabase = true
        
        for record in CotLocalDatabase.shared.documents.prefix(40) {
            self.learn(from: record.content, persist: false)
        }
        self.scheduleSave()
    }
    
    
    /// Predicts a high-confidence short next phrase for the current caret location, or `nil` when uncertain.
    func predictNextPhrase(in text: String, caretLocation: Int) -> String? {
        
        self.warmUpFromDatabaseIfNeeded()
        
        let nsText = text as NSString
        guard caretLocation > 0, caretLocation <= nsText.length else { return nil }
        
        // Do not suggest inline ghost text inside the middle of an existing word.
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
        let window = String(rawLinePrefix.suffix(48))
        
        // 1. Exact or partial match against high-confidence built-in workflow habits
        if let builtInMatch = self.matchBuiltInHabits(linePrefix: window) {
            return builtInMatch
        }
        
        // 2. Learned personal habit transitions (strictly high-confidence & short)
        return self.matchLearnedTransition(linePrefix: window)
    }
    
    
    /// Learns repeated short phrase transitions from user text (saved or actively edited).
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
                guard tokens.count >= 2 else { continue }
                
                // Record bigram transitions between adjacent meaningful chunks
                for i in 0..<(tokens.count - 1) {
                    let next = tokens[i + 1]
                    guard next.count >= 2, next.count <= 14 else { continue }
                    
                    var contextKeys: [String] = []
                    if tokens[i].count >= 2, tokens[i].count <= 12 {
                        contextKeys.append(tokens[i])
                    }
                    if i >= 1 {
                        let twoTokenKey = tokens[i - 1] + tokens[i]
                        if twoTokenKey.count >= 2, twoTokenKey.count <= 10 {
                            contextKeys.append(twoTokenKey)
                        }
                    }
                    if i >= 2 {
                        let threeTokenKey = tokens[i - 2] + tokens[i - 1] + tokens[i]
                        if threeTokenKey.count >= 3, threeTokenKey.count <= 10 {
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
    
    
    /// Learns an explicitly accepted or completed phrase transition right around the caret.
    func recordAcceptedCompletion(prefixContext: String, acceptedPhrase: String) {
        
        let key = self.normalizedContextSuffix(prefixContext)
        let candidate = acceptedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 2, candidate.count >= 2, candidate.count <= 14 else { return }
        
        self.recordTransition(from: key, to: candidate, in: \.compoundTransitions, weight: 2)
        self.scheduleSave()
    }
    
    
    /// Clears learned habit transitions (mostly for testing).
    func resetLearnedHabits() {
        
        self.transitions.removeAll()
        self.compoundTransitions.removeAll()
        if let persistenceKey {
            CotLocalDatabase.shared.removeConfig(forKey: persistenceKey)
        }
    }
    
    
    // MARK: Private Helpers
    
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
        
        let cleanPrefix = self.trimTrailingClausePunctuation(linePrefix)
        guard cleanPrefix.count >= 2 else { return nil }
        
        // 1. Direct lookup using longest matching trailing key (prefer longer, more specific context)
        let candidateKeys = self.candidateContextKeys(from: cleanPrefix)
        for key in candidateKeys {
            if let suggestion = self.highConfidenceCandidate(for: key) {
                return suggestion
            }
        }
        
        // 2. Partial continuation against learned high-confidence candidates
        for overlapLen in stride(from: min(6, cleanPrefix.count - 2), through: 1, by: -1) {
            let partial = String(cleanPrefix.suffix(overlapLen))
            let beforePartial = self.trimTrailingClausePunctuation(String(cleanPrefix.dropLast(overlapLen)))
            guard beforePartial.count >= 2 else { continue }
            for key in self.candidateContextKeys(from: beforePartial) {
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
        
        guard let best = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.count < rhs.key.count
        }) else { return nil }
        
        let confidence = Double(best.value) / Double(total)
        guard best.value >= 2, confidence >= 0.65, best.key.count <= 14 else { return nil }
        return best.key
    }
    
    
    private func candidateContextKeys(from cleanPrefix: String) -> [String] {
        
        var keys: [String] = []
        let tokens = self.tokenizeClause(cleanPrefix)
        if let lastToken = tokens.last, lastToken.count >= 2 {
            keys.append(lastToken)
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
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "，,：:、"))
        while let last = s.unicodeScalars.last, separators.contains(last) {
            s.removeLast()
        }
        return s
    }
    
    
    private func normalizedContextSuffix(_ string: String) -> String {
        
        let trimmed = self.trimTrailingClausePunctuation(string)
        return String(trimmed.suffix(10))
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
                compoundTransitions: self.compoundTransitions
            )
            if let data = try? JSONEncoder().encode(model),
               let json = String(data: data, encoding: .utf8)
            {
                CotLocalDatabase.shared.set(json, forKey: persistenceKey)
            }
        }
    }
}
