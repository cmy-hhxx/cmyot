//
//  WorkspaceOrganizeProgressController.swift
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

import AppKit
import Observation
import SwiftUI

/// Live progress model for "一键整合并规整全部文档".
@MainActor @Observable final class WorkspaceOrganizeProgressState {
    
    enum StepStatus: Equatable {
        case pending
        case active
        case completed
        case failed
    }
    
    struct StepItem: Identifiable, Equatable {
        let id: Int
        let title: String
        var detail: String
        var status: StepStatus
    }
    
    var endpointDescription: String
    var totalDocumentCount: Int
    var progress: Double = 0.08
    var streamedCharacters: Int = 0
    var elapsedSeconds: Int = 0
    var statusHeadline: String = "正在准备整理工作区文档…"
    var summaryMessage: String?
    var errorMessage: String?
    var isFinished: Bool = false
    
    var steps: [StepItem] = [
        StepItem(id: 0, title: "1. 备份当前文档快照", detail: "等待开始", status: .pending),
        StepItem(id: 1, title: "2. AI 归类分析与内容提炼", detail: "等待开始", status: .pending),
        StepItem(id: 2, title: "3. 原位重命名并规整正文（保留分屏 Pane）", detail: "等待开始", status: .pending),
        StepItem(id: 3, title: "4. 生成《整理合并 Map》总览", detail: "等待开始", status: .pending),
    ]
    
    init(totalDocumentCount: Int, endpointDescription: String) {
        self.totalDocumentCount = totalDocumentCount
        self.endpointDescription = endpointDescription
    }
    
    
    func markStepActive(_ index: Int, detail: String, progress: Double, headline: String) {
        for idx in self.steps.indices {
            if idx < index, self.steps[idx].status != .failed {
                self.steps[idx].status = .completed
            } else if idx == index {
                self.steps[idx].status = .active
                self.steps[idx].detail = detail
            }
        }
        self.progress = max(self.progress, min(1.0, progress))
        self.statusHeadline = headline
    }
    
    
    func markStepCompleted(_ index: Int, detail: String) {
        guard self.steps.indices.contains(index) else { return }
        self.steps[index].status = .completed
        self.steps[index].detail = detail
    }
    
    
    func markCompleted(summary: String) {
        for idx in self.steps.indices {
            self.steps[idx].status = .completed
        }
        self.progress = 1.0
        self.statusHeadline = "全部文档已规整完毕"
        self.summaryMessage = summary
        self.isFinished = true
    }
    
    
    func markFailed(message: String) {
        if let activeIndex = self.steps.firstIndex(where: { $0.status == .active }) {
            self.steps[activeIndex].status = .failed
            self.steps[activeIndex].detail = "执行失败"
        }
        self.statusHeadline = "整理过程中遇到错误"
        self.errorMessage = message
        self.isFinished = true
    }
}


/// Window/sheet controller displaying transparent step-by-step progress while organizing all documents.
@MainActor final class WorkspaceOrganizeProgressController: NSWindowController {
    
    let state: WorkspaceOrganizeProgressState
    var onCancel: (() -> Void)?
    
    private var timerTask: Task<Void, Never>?
    
    init(totalDocumentCount: Int, endpointDescription: String) {
        let state = WorkspaceOrganizeProgressState(
            totalDocumentCount: totalDocumentCount,
            endpointDescription: endpointDescription
        )
        self.state = state
        
        let rootView = WorkspaceOrganizeProgressView(
            state: state,
            onCancelOrClose: { },
            onOpenLog: {
                (NSApp.delegate as? AppDelegate)?.openTodayErrorLog(nil)
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(contentViewController: hostingController)
        panel.styleMask = [.titled]
        panel.title = "一键整合并规整全部文档"
        panel.setContentSize(NSSize(width: 500, height: 356))
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        
        super.init(window: panel)
        
        hostingController.rootView = WorkspaceOrganizeProgressView(
            state: state,
            onCancelOrClose: { [weak self] in
                self?.handleCancelOrClose()
            },
            onOpenLog: {
                (NSApp.delegate as? AppDelegate)?.openTodayErrorLog(nil)
            }
        )
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func present(on parent: NSWindow?) {
        guard let window else { return }
        self.startElapsedTimer()
        if let parent {
            parent.beginSheet(window)
        } else {
            self.showWindow(nil)
        }
    }
    
    
    func dismissSheet() {
        self.timerTask?.cancel()
        self.timerTask = nil
        guard let window else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
    }
    
    
    private func startElapsedTimer() {
        self.timerTask?.cancel()
        self.timerTask = Task { @MainActor [weak self] in
            let start = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.state.isFinished else { break }
                self.state.elapsedSeconds = max(1, Int(Date().timeIntervalSince(start)))
            }
        }
    }
    
    
    private func handleCancelOrClose() {
        if !self.state.isFinished {
            self.onCancel?()
        }
        self.dismissSheet()
    }
}


private struct WorkspaceOrganizeProgressView: View {
    
    var state: WorkspaceOrganizeProgressState
    var onCancelOrClose: () -> Void
    var onOpenLog: () -> Void
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: self.state.errorMessage != nil
                      ? "exclamationmark.triangle.fill"
                      : (self.state.isFinished ? "checkmark.seal.fill" : "sparkles"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(self.state.errorMessage != nil
                                     ? AnyShapeStyle(.orange)
                                     : (self.state.isFinished ? AnyShapeStyle(.green) : AnyShapeStyle(Color.accentColor)))
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.state.statusHeadline)
                        .font(.headline)
                    Text("共 \(self.state.totalDocumentCount) 份非空文档 · \(self.state.endpointDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: self.state.progress)
                    .progressViewStyle(.linear)
                    .tint(self.state.errorMessage != nil ? .orange : (self.state.isFinished ? .green : .accentColor))
                
                HStack {
                    Text("\(Int((self.state.progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    if self.state.streamedCharacters > 0 {
                        Text("· 已接收模型方案 \(self.state.streamedCharacters) 字")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("已用时 \(self.state.elapsedSeconds)s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(self.state.steps) { step in
                    HStack(alignment: .center, spacing: 10) {
                        self.stepIcon(for: step.status)
                            .frame(width: 16, height: 16)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title)
                                .font(.callout.weight(step.status == .active ? .semibold : .regular))
                                .foregroundStyle(step.status == .pending ? .secondary : .primary)
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.45)))
            
            if let summary = self.state.summaryMessage {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let errorMessage = self.state.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack {
                if self.state.errorMessage != nil {
                    Button("查看今日错误日志") {
                        self.onOpenLog()
                    }
                }
                
                Spacer()
                
                Button(self.state.isFinished ? "完成" : "取消") {
                    self.onCancelOrClose()
                }
                .keyboardShortcut(self.state.isFinished ? .defaultAction : .cancelAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
    
    
    @ViewBuilder
    private func stepIcon(for status: WorkspaceOrganizeProgressState.StepStatus) -> some View {
        switch status {
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            case .active:
                ProgressView()
                    .controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
        }
    }
}
