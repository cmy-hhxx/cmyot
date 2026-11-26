//
//  OnlineStickerSearchSheet.swift
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

struct OnlineStickerSearchSheet: View {
    
    let onImported: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var isSearching = false
    @State private var candidates: [OnlineStickerCandidate] = []
    @State private var importedIDs: Set<String> = []
    @State private var importingIDs: Set<String> = []
    @State private var autoExpandEnabled = OnlineStickerSearchService.isAutoExpansionEnabled
    @State private var enabledSources = Set(OnlineStickerSearchService.enabledSources)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppLanguage.text("在线表情包扩展", en: "Online Sticker Search"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Toggle(AppLanguage.text("Bot 自动扩库", en: "Bot Auto-Expand"), isOn: self.$autoExpandEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: self.autoExpandEnabled) { _, next in
                        OnlineStickerSearchService.isAutoExpansionEnabled = next
                    }
            }
            
            HStack(spacing: 8) {
                TextField(AppLanguage.text("关键词", en: "Keyword"), text: self.$query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.runSearch() }
                
                Button(AppLanguage.text("搜索", en: "Search")) {
                    self.runSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.isSearching || self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            HStack(spacing: 8) {
                ForEach(OnlineStickerSourceID.allCases) { source in
                    let active = self.enabledSources.contains(source)
                    Button {
                        if active, self.enabledSources.count > 1 {
                            self.enabledSources.remove(source)
                        } else {
                            self.enabledSources.insert(source)
                        }
                        OnlineStickerSearchService.enabledSources = Array(self.enabledSources)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                            Text(source.displayName)
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(active ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(active ? 0.10 : 0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            if self.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if self.candidates.isEmpty {
                Text(AppLanguage.text("输入关键词检索表情包", en: "Enter a keyword to search"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 116, maximum: 136), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(self.candidates) { item in
                            OnlineStickerCandidateCard(
                                candidate: item,
                                isImported: self.importedIDs.contains(item.id),
                                isImporting: self.importingIDs.contains(item.id)
                            ) {
                                self.importCandidate(item)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 260, maxHeight: 340)
            }
            
            HStack {
                Spacer()
                Button(AppLanguage.text("完成", en: "Done")) {
                    self.onImported(self.importedIDs.count)
                    self.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 560)
    }
    
    
    private func runSearch() {
        let q = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        self.isSearching = true
        let activeSources = Array(self.enabledSources)
        Task {
            let results = await OnlineStickerSearchService.search(query: q, sources: activeSources, limitPerSource: 8)
            await MainActor.run {
                self.candidates = results
                self.isSearching = false
            }
        }
    }
    
    
    private func importCandidate(_ candidate: OnlineStickerCandidate) {
        guard !self.importedIDs.contains(candidate.id), !self.importingIDs.contains(candidate.id) else { return }
        self.importingIDs.insert(candidate.id)
        Task {
            let asset = await OnlineStickerSearchService.downloadAndImport(candidate: candidate)
            await MainActor.run {
                self.importingIDs.remove(candidate.id)
                if asset != nil {
                    self.importedIDs.insert(candidate.id)
                }
            }
        }
    }
}


private struct OnlineStickerCandidateCard: View {
    
    let candidate: OnlineStickerCandidate
    let isImported: Bool
    let isImporting: Bool
    let onImport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: self.candidate.imageURL)) { phase in
                switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    default:
                        Color.primary.opacity(0.05)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .clipped()
            
            Text(self.candidate.sourceSite)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Button {
                self.onImport()
            } label: {
                Text(
                    self.isImported
                        ? AppLanguage.text("已入库", en: "Added")
                        : (self.isImporting ? AppLanguage.text("下载中", en: "Adding") : AppLanguage.text("入库", en: "Add"))
                )
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(self.isImported || self.isImporting)
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
