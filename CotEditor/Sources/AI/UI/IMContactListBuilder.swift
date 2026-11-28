//
//  IMContactListBuilder.swift
//
//  CotEditor
//  https://coteditor.com
//

import Foundation

/// Metadata describing an enabled Bot contact before merging live DM session summaries.
nonisolated struct IMContactSeed: Sendable, Equatable {
    var id: String
    var name: String
    var nickname: String
    var handle: String
    var tagline: String
    var accentHex: String
    var avatarURL: String?
    var isCustom: Bool
    var isButler: Bool
}


/// Pure helper that merges per-bot session state into the ordered IM contacts payload.
nonisolated enum IMContactListBuilder {
    
    static func build(
        sessions: [ButlerSessionRecord],
        bots: [IMContactSeed]
    ) -> [BeautifulAgentContactPayload] {
        var groupedSessions: [String: [ButlerSessionRecord]] = [:]
        for session in sessions {
            let normalized = session.botID.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalized.isEmpty ? "butler" : normalized
            groupedSessions[key, default: []].append(session)
        }
        
        let sortedSeeds = bots.enumerated().sorted { lhs, rhs in
            let leftRank = Self.bucketRank(for: lhs.element)
            let rightRank = Self.bucketRank(for: rhs.element)
            if leftRank != rightRank {
                return leftRank < rightRank
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        
        return sortedSeeds.map { seed in
            let matching = groupedSessions[seed.id] ?? []
            let latest = matching.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt < rhs.updatedAt
                }
                return lhs.createdAt < rhs.createdAt
            }
            let unread = matching.reduce(0) { $0 + $1.unreadCount }
            let isPinned = matching.contains(where: \.isPinned)
            let preview: String? = {
                guard let latest else { return nil }
                let raw = latest.lastMessagePreview.isEmpty ? latest.previewText : latest.lastMessagePreview
                let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? nil : clean
            }()
            return BeautifulAgentContactPayload(
                id: seed.id,
                name: seed.name,
                nickname: seed.nickname,
                handle: seed.handle,
                tagline: seed.tagline,
                accentHex: seed.accentHex,
                avatarURL: seed.avatarURL,
                isCustom: seed.isCustom,
                isButler: seed.isButler,
                sessionID: latest?.id,
                unreadCount: unread,
                lastMessagePreview: preview,
                updatedAt: latest.map { $0.updatedAt.timeIntervalSince1970 * 1000 },
                isPinned: isPinned
            )
        }
    }
    
    
    private static func bucketRank(for seed: IMContactSeed) -> Int {
        if seed.isButler { return 0 }
        if !seed.isCustom { return 1 }
        return 2
    }
}
