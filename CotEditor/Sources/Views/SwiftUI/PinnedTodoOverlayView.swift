//
//  PinnedTodoOverlayView.swift
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

import CoreGraphics
import Foundation

/// Computed visual urgency and lightweight typography metrics for a pinned todo capsule.
nonisolated struct PinnedTodoUrgencyMetrics: Sendable, Equatable {
    
    var fontSize: CGFloat
    var progress: Double
    var isOverdue: Bool
    var isWindowBursting: Bool
    var remainingText: String?
    var urgencyLevel: Int   // 0 = timeless, 1 = calm, 2 = approaching, 3 = imminent, 4 = critical/overdue
}


/// Featherweight urgency model that gently shifts capsule accent without obstructing the editor canvas.
nonisolated enum PinnedTodoUrgency {
    
    static func metrics(
        createdAt: Date,
        deadline: Date?,
        now: Date,
        containerSize: CGSize
    ) -> PinnedTodoUrgencyMetrics {
        
        guard let deadline else {
            return PinnedTodoUrgencyMetrics(
                fontSize: 12.2,
                progress: 0,
                isOverdue: false,
                isWindowBursting: false,
                remainingText: nil,
                urgencyLevel: 0
            )
        }
        
        let remaining = deadline.timeIntervalSince(now)
        let totalSpan = max(60.0, deadline.timeIntervalSince(createdAt))
        let spanRatio = min(1.0, max(0.0, now.timeIntervalSince(createdAt) / totalSpan))
        
        let timePressure: Double
        if remaining <= 0 {
            timePressure = 1.0
        } else if remaining <= 60 {
            timePressure = 0.92 + (1.0 - remaining / 60.0) * 0.08
        } else if remaining <= 600 {
            timePressure = 0.72 + (1.0 - (remaining - 60.0) / 540.0) * 0.20
        } else if remaining <= 1800 {
            timePressure = 0.52 + (1.0 - (remaining - 600.0) / 1200.0) * 0.20
        } else if remaining <= 7200 {
            timePressure = 0.26 + (1.0 - (remaining - 1800.0) / 5400.0) * 0.26
        } else {
            timePressure = max(0.02, 0.26 * (7200.0 / remaining))
        }
        
        let effectiveProgress = min(1.0, max(spanRatio * 0.85, timePressure))
        let isOverdue = (remaining <= 0)
        
        let fontSize: CGFloat
        let urgencyLevel: Int
        
        if remaining <= 0 {
            let overdueRatio = min(1.0, (-remaining) / 300.0)
            fontSize = 13.0 + CGFloat(overdueRatio) * 0.4
            urgencyLevel = 4
        } else if remaining <= 45 || effectiveProgress >= 0.96 {
            let countdownRatio = min(1.0, max(0.0, 1.0 - remaining / 45.0))
            fontSize = 12.8 + CGFloat(countdownRatio) * 0.3
            urgencyLevel = 4
        } else if effectiveProgress >= 0.72 {
            let localT = (effectiveProgress - 0.72) / 0.24
            fontSize = 12.6 + CGFloat(localT) * 0.3
            urgencyLevel = 3
        } else if effectiveProgress >= 0.45 {
            let localT = (effectiveProgress - 0.45) / 0.27
            fontSize = 12.4 + CGFloat(localT) * 0.2
            urgencyLevel = 2
        } else {
            let localT = effectiveProgress / 0.45
            fontSize = 12.2 + CGFloat(localT) * 0.2
            urgencyLevel = 1
        }
        
        return PinnedTodoUrgencyMetrics(
            fontSize: fontSize,
            progress: effectiveProgress,
            isOverdue: isOverdue,
            isWindowBursting: false,
            remainingText: Self.formatRemaining(remaining),
            urgencyLevel: urgencyLevel
        )
    }
    
    
    static func compactBadgeText(_ remaining: TimeInterval) -> String {
        
        let isEn = (AppLanguage.current == .english)
        let overduePrefix = isEn ? "Overdue " : "超时 "
        let absSeconds = Int(abs(remaining).rounded(.down))
        if remaining < 0 {
            if absSeconds < 60 {
                return "\(overduePrefix)\(max(1, absSeconds))s"
            }
            let minutes = absSeconds / 60
            if minutes < 60 {
                return "\(overduePrefix)\(minutes)m"
            }
            let hours = minutes / 60
            if hours < 24 {
                return "\(overduePrefix)\(hours)h"
            }
            return "\(overduePrefix)\(hours / 24)d"
        }
        
        if absSeconds < 60 {
            return "\(max(1, absSeconds))s"
        }
        let minutes = absSeconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if hours < 24 {
            return remMin > 0 ? "\(hours)h \(remMin)m" : "\(hours)h"
        }
        return "\(hours / 24)d"
    }
    
    
    static func formatRemaining(_ remaining: TimeInterval) -> String {
        
        let absSeconds = Int(abs(remaining).rounded(.down))
        let prefix = remaining < 0 ? "已超时 " : "还剩 "
        
        if absSeconds < 60 {
            return "\(prefix)\(max(1, absSeconds)) 秒"
        }
        let minutes = absSeconds / 60
        let seconds = absSeconds % 60
        if minutes < 60 {
            return remaining < 0 || minutes >= 10
                ? "\(prefix)\(minutes) 分钟"
                : "\(prefix)\(minutes) 分 \(seconds) 秒"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if hours < 24 {
            return remMin > 0 ? "\(prefix)\(hours) 小时 \(remMin) 分" : "\(prefix)\(hours) 小时"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? "\(prefix)\(days) 天 \(remHours) 小时" : "\(prefix)\(days) 天"
    }
}
