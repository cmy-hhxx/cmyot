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

import AppKit
import SwiftUI

/// Computed visual urgency and escalating typography metrics for a pinned todo item.
nonisolated struct PinnedTodoUrgencyMetrics: Sendable, Equatable {
    
    var fontSize: CGFloat
    var progress: Double
    var isOverdue: Bool
    var isWindowBursting: Bool
    var remainingText: String?
    var urgencyLevel: Int   // 0 = timeless, 1 = calm, 2 = approaching, 3 = imminent, 4 = bursting
}


/// Pure mathematical escalation model that scales a pinned todo's font size smoothly
/// as its deadline approaches until it visually bursts across the editor window.
nonisolated enum PinnedTodoUrgency {
    
    static func metrics(
        createdAt: Date,
        deadline: Date?,
        now: Date,
        containerSize: CGSize
    ) -> PinnedTodoUrgencyMetrics {
        
        guard let deadline else {
            return PinnedTodoUrgencyMetrics(
                fontSize: 12.5,
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
        
        // Combine elapsed lifetime ratio with absolute remaining-time pressure
        let timePressure: Double
        if remaining <= 0 {
            timePressure = 1.0
        } else if remaining <= 60 {
            timePressure = 0.92 + (1.0 - remaining / 60.0) * 0.08
        } else if remaining <= 600 { // <= 10 min
            timePressure = 0.72 + (1.0 - (remaining - 60.0) / 540.0) * 0.20
        } else if remaining <= 1800 { // <= 30 min
            timePressure = 0.52 + (1.0 - (remaining - 600.0) / 1200.0) * 0.20
        } else if remaining <= 7200 { // <= 2 hours
            timePressure = 0.26 + (1.0 - (remaining - 1800.0) / 5400.0) * 0.26
        } else {
            // Smooth early approach for distant deadlines (> 2h)
            timePressure = max(0.02, 0.26 * (7200.0 / remaining))
        }
        
        let effectiveProgress = min(1.0, max(spanRatio * 0.85, timePressure))
        let isOverdue = (remaining <= 0)
        
        let safeW = max(containerSize.width, 640)
        let safeH = max(containerSize.height, 420)
        let baseBurstSize = min(max(safeW * 0.16, 74), max(safeH * 0.24, 74), 148)
        let maxBurstSize = min(max(safeW * 0.19, 88), max(safeH * 0.28, 88), 172)
        
        let fontSize: CGFloat
        let urgencyLevel: Int
        let isWindowBursting: Bool
        
        if remaining <= 0 {
            let overdueProgress = min(1.0, (-remaining) / 300.0)
            fontSize = baseBurstSize + (maxBurstSize - baseBurstSize) * CGFloat(overdueProgress)
            urgencyLevel = 4
            isWindowBursting = true
        } else if remaining <= 45 || effectiveProgress >= 0.96 {
            let countdownRatio = min(1.0, max(0.0, 1.0 - remaining / 45.0))
            fontSize = 62.0 + (baseBurstSize - 62.0) * CGFloat(countdownRatio)
            urgencyLevel = 4
            isWindowBursting = true
        } else if effectiveProgress >= 0.72 {
            let localT = (effectiveProgress - 0.72) / 0.24
            fontSize = 33.0 + CGFloat(localT) * 27.0
            urgencyLevel = 3
            isWindowBursting = false
        } else if effectiveProgress >= 0.45 {
            let localT = (effectiveProgress - 0.45) / 0.27
            fontSize = 19.0 + CGFloat(localT) * 14.0
            urgencyLevel = 2
            isWindowBursting = false
        } else {
            let localT = effectiveProgress / 0.45
            fontSize = 13.0 + CGFloat(localT) * 6.0
            urgencyLevel = 1
            isWindowBursting = false
        }
        
        return PinnedTodoUrgencyMetrics(
            fontSize: fontSize,
            progress: effectiveProgress,
            isOverdue: isOverdue,
            isWindowBursting: isWindowBursting,
            remainingText: Self.formatRemaining(remaining),
            urgencyLevel: urgencyLevel
        )
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


// MARK: - Pass-Through Hit-Testing Infrastructure

@MainActor
final class PinnedTodoHitTestStore {
    
    var interactiveRects: [CGRect] = []
}


private struct PinnedTodoHitRectsPreferenceKey: PreferenceKey {
    
    static let defaultValue: [CGRect] = []
    
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}


private struct ReportInteractiveRectModifier: ViewModifier {
    
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: PinnedTodoHitRectsPreferenceKey.self,
                    value: [geo.frame(in: .named("PinnedTodoOverlaySpace"))]
                )
            }
        )
    }
}


// MARK: - AppKit Transparent Overlay Container

/// Transparent AppKit container hovering above the split editor whose `hitTest(_:)` passes
/// all pointer events through to `EditorTextView` outside active todo bounds.
@MainActor
final class PinnedTodoOverlayContainerView: NSView {
    
    private let hitTestStore = PinnedTodoHitTestStore()
    private let hostingView: NSHostingView<PinnedTodoOverlayView>
    
    override var isFlipped: Bool { true }
    
    
    override init(frame frameRect: NSRect) {
        
        let rootView = PinnedTodoOverlayView(hitTestStore: self.hitTestStore)
        self.hostingView = NSHostingView(rootView: rootView)
        
        super.init(frame: frameRect)
        
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        self.hostingView.translatesAutoresizingMaskIntoConstraints = false
        self.hostingView.wantsLayer = true
        self.hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        self.addSubview(self.hostingView)
        
        NSLayoutConstraint.activate([
            self.hostingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.hostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.hostingView.topAnchor.constraint(equalTo: self.topAnchor),
            self.hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        
        guard !AnalyticsManager.shared.pinnedTodos.isEmpty else { return nil }
        let localPoint = self.convert(point, from: self.superview)
        guard self.bounds.contains(localPoint) else { return nil }
        let isInsideTodo = self.hitTestStore.interactiveRects.contains { rect in
            rect.insetBy(dx: -2, dy: -2).contains(localPoint)
        }
        guard isInsideTodo else { return nil }
        return super.hitTest(point)
    }
}


// MARK: - SwiftUI Overlay Rendering

struct PinnedTodoOverlayView: View {
    
    let hitTestStore: PinnedTodoHitTestStore
    
    @State private var analytics = AnalyticsManager.shared
    @State private var hoveredID: String?
    @Environment(\.colorScheme) private var colorScheme
    
    
    var body: some View {
        let todos = self.analytics.pinnedTodos
        
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                if todos.isEmpty {
                    Color.clear
                } else if todos.contains(where: \.hasDeadline) {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        self.overlayContent(todos: todos, now: context.date, containerSize: geo.size)
                    }
                } else {
                    self.overlayContent(todos: todos, now: Date(), containerSize: geo.size)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
        }
        .coordinateSpace(name: "PinnedTodoOverlaySpace")
        .onPreferenceChange(PinnedTodoHitRectsPreferenceKey.self) { rects in
            self.hitTestStore.interactiveRects = rects
        }
        .onChange(of: todos.isEmpty) { _, isEmpty in
            if isEmpty {
                self.hitTestStore.interactiveRects = []
            }
        }
    }
    
    
    @ViewBuilder
    private func overlayContent(todos: [UserReminder], now: Date, containerSize: CGSize) -> some View {
        let evaluated = todos.map { item -> (UserReminder, PinnedTodoUrgencyMetrics) in
            let metrics = PinnedTodoUrgency.metrics(
                createdAt: item.createdAt,
                deadline: item.hasDeadline ? item.dueDate : nil,
                now: now,
                containerSize: containerSize
            )
            return (item, metrics)
        }
        
        let burstingItem = evaluated.first(where: { $0.1.isWindowBursting })
        let floatingItems = evaluated.filter { !$0.1.isWindowBursting }.prefix(3)
        
        ZStack(alignment: .topTrailing) {
            if !floatingItems.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(Array(floatingItems), id: \.0.id) { item, metrics in
                        self.floatingPill(item: item, metrics: metrics, containerSize: containerSize)
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, 14)
            }
            
            if let (burstItem, burstMetrics) = burstingItem {
                self.windowBurstingCard(item: burstItem, metrics: burstMetrics, containerSize: containerSize)
                    .padding(18)
            }
        }
    }
    
    
    @ViewBuilder
    private func floatingPill(
        item: UserReminder,
        metrics: PinnedTodoUrgencyMetrics,
        containerSize: CGSize
    ) -> some View {
        let isHovered = (self.hoveredID == item.id)
        let accent: Color = switch metrics.urgencyLevel {
            case 3: Color(red: 0.85, green: 0.24, blue: 0.18)
            case 2: Color(red: 0.88, green: 0.45, blue: 0.14)
            case 1: Color(red: 0.18, green: 0.56, blue: 0.40)
            default: Color.accentColor
        }
        
        HStack(alignment: .center, spacing: 8) {
            Button {
                self.analytics.toggleReminderCompleted(id: item.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: min(22, max(13, metrics.fontSize * 0.55)), weight: .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .help("标记已完成")
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.title)
                    .font(.system(size: metrics.fontSize, weight: metrics.urgencyLevel >= 2 ? .bold : .semibold))
                    .foregroundStyle(metrics.urgencyLevel >= 3 ? accent : .primary)
                    .lineLimit(metrics.urgencyLevel >= 2 ? 2 : 1)
                    .multilineTextAlignment(.trailing)
                    .minimumScaleFactor(0.65)
                
                if let remaining = metrics.remainingText {
                    Text(remaining)
                        .font(.system(size: max(10, min(14, metrics.fontSize * 0.44)), weight: .semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
            
            if isHovered || metrics.urgencyLevel >= 2 {
                HStack(spacing: 4) {
                    if item.hasDeadline {
                        Button("+15分") {
                            self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    
                    Button {
                        self.analytics.unpinReminder(id: item.id)
                    } label: {
                        Image(systemName: "pin.slash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("取消右上角置顶")
                }
            }
        }
        .padding(.horizontal, metrics.urgencyLevel >= 2 ? 14 : 11)
        .padding(.vertical, metrics.urgencyLevel >= 2 ? 10 : 7)
        .frame(maxWidth: min(containerSize.width * 0.72, max(280, metrics.fontSize * 12)), alignment: .trailing)
        .background(
            RoundedRectangle(cornerRadius: metrics.urgencyLevel >= 2 ? 14 : 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.urgencyLevel >= 2 ? 14 : 10, style: .continuous)
                        .fill(accent.opacity(self.colorScheme == .dark ? (0.10 + Double(metrics.urgencyLevel) * 0.04) : (0.05 + Double(metrics.urgencyLevel) * 0.03)))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.urgencyLevel >= 2 ? 14 : 10, style: .continuous)
                .strokeBorder(accent.opacity(metrics.urgencyLevel >= 2 ? 0.55 : 0.22), lineWidth: metrics.urgencyLevel >= 2 ? 1.5 : 1)
        )
        .shadow(color: .black.opacity(self.colorScheme == .dark ? 0.35 : 0.10), radius: 10, y: 4)
        .onHover { inside in
            self.hoveredID = inside ? item.id : (self.hoveredID == item.id ? nil : self.hoveredID)
        }
        .modifier(ReportInteractiveRectModifier())
    }
    
    
    @ViewBuilder
    private func windowBurstingCard(
        item: UserReminder,
        metrics: PinnedTodoUrgencyMetrics,
        containerSize: CGSize
    ) -> some View {
        let urgentRed = Color(red: 0.86, green: 0.20, blue: 0.16)
        
        VStack(alignment: .center, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(metrics.remainingText ?? "截止时间已到")
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(urgentRed))
            
            Text(item.title)
                .font(.system(size: metrics.fontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(self.colorScheme == .dark ? Color.white : urgentRed)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.35)
                .frame(maxWidth: .infinity)
            
            HStack(spacing: 12) {
                Button {
                    self.analytics.toggleReminderCompleted(id: item.id)
                } label: {
                    Label("现在完成", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(urgentRed)
                
                Button("+15 分钟") {
                    self.analytics.snoozeReminder(id: item.id, by: 15 * 60)
                }
                .buttonStyle(.bordered)
                
                Button("+1 小时") {
                    self.analytics.snoozeReminder(id: item.id, by: 3600)
                }
                .buttonStyle(.bordered)
                
                Button("取消置顶") {
                    self.analytics.unpinReminder(id: item.id)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(
            maxWidth: max(360, containerSize.width - 36),
            maxHeight: max(220, containerSize.height - 36)
        )
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(urgentRed.opacity(self.colorScheme == .dark ? 0.16 : 0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(urgentRed.opacity(0.85), lineWidth: 2.5)
        )
        .shadow(color: urgentRed.opacity(0.28), radius: 24, y: 8)
        .modifier(ReportInteractiveRectModifier())
    }
}
