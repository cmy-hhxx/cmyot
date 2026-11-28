//
//  LocalDatabaseSettingsView.swift
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

import SwiftUI

/// Concise Storage & Migration card embedded in Profile Settings:
/// total occupied size, plain proportional breakdown bar, and async export/import/compact controls.
struct LocalDatabaseSettingsView: View {
    
    let onExportDatabase: () -> Void
    let onImportDatabase: () -> Void
    var refreshRevision: Int = 0
    var isMigrating: Bool = false
    var migrationStatus: String? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var database = CotLocalDatabase.shared
    @State private var snapshot: DatabaseInspectionSnapshot?
    @State private var compactStatusText: String?
    
    private var isDark: Bool { self.colorScheme == .dark }
    
    
    var body: some View {
        SettingsGroupCard(title: AppLanguage.text("存储与迁移", en: "Storage & Migration")) {
            if let snapshot = self.snapshot {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(StorageCardFormatters.bytes(snapshot.totalBytes))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                        
                        Spacer(minLength: 6)
                        
                        if self.isMigrating {
                            ProgressView()
                                .controlSize(.small)
                        } else if let status = self.migrationStatus ?? self.compactStatusText {
                            Text(status)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    
                    self.proportionalBar(categories: snapshot.categories)
                    
                    SettingsRowDivider()
                        .padding(.horizontal, -14)
                    
                    HStack(spacing: 8) {
                        Button(AppLanguage.text("导出迁移包", en: "Export")) {
                            self.onExportDatabase()
                        }
                        .controlSize(.small)
                        .disabled(self.isMigrating)
                        
                        Button(AppLanguage.text("导入还原", en: "Import")) {
                            self.onImportDatabase()
                        }
                        .controlSize(.small)
                        .disabled(self.isMigrating)
                        
                        Spacer()
                        
                        Button(AppLanguage.text("整理瘦身", en: "Compact")) {
                            self.runCompact()
                        }
                        .controlSize(.small)
                        .disabled(self.isMigrating)
                    }
                }
                .padding(14)
            }
        }
        .task(id: self.refreshRevision) {
            self.reloadSnapshot()
        }
    }
    
    
    private func proportionalBar(categories: [DatabaseStorageCategory]) -> some View {
        let totalEstimated = max(Int64(1), categories.reduce(Int64(0)) { $0 + $1.bytes })
        let nonZero = categories.filter { $0.bytes > 0 }
        
        return GeometryReader { geo in
            let spacing: CGFloat = nonZero.count > 1 ? 2.5 : 0
            let usableWidth = max(0, geo.size.width - spacing * CGFloat(max(0, nonZero.count - 1)))
            
            HStack(spacing: spacing) {
                if nonZero.isEmpty {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(self.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                } else {
                    ForEach(nonZero) { category in
                        let fraction = CGFloat(category.bytes) / CGFloat(totalEstimated)
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(StorageCardFormatters.categoryColor(category.kind, isDark: self.isDark).opacity(0.90))
                            .frame(width: max(8, usableWidth * fraction))
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
    
    
    private func reloadSnapshot() {
        self.snapshot = self.database.inspectDatabaseSnapshot()
    }
    
    
    private func runCompact() {
        let reclaimed = self.database.compactDatabase()
        self.reloadSnapshot()
        let text = reclaimed > 0
            ? AppLanguage.text("已释放 \(StorageCardFormatters.bytes(reclaimed))", en: "Freed \(StorageCardFormatters.bytes(reclaimed))")
            : AppLanguage.text("已整理", en: "Compacted")
        withAnimation(.easeOut(duration: 0.16)) {
            self.compactStatusText = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                if self.compactStatusText == text {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.compactStatusText = nil
                    }
                }
            }
        }
    }
}


private enum StorageCardFormatters {
    
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()
    
    static func bytes(_ count: Int64) -> String {
        if count <= 0 { return "0 B" }
        return self.byteFormatter.string(fromByteCount: count)
    }
    
    static func categoryColor(_ kind: DatabaseCategoryKind, isDark: Bool) -> Color {
        switch kind {
            case .documents:
                isDark ? Color(red: 0.36, green: 0.64, blue: 0.96) : Color(red: 0.18, green: 0.49, blue: 0.92)
            case .aiRecords:
                isDark ? Color(red: 0.64, green: 0.50, blue: 0.95) : Color(red: 0.48, green: 0.36, blue: 0.84)
            case .memory:
                isDark ? Color(red: 0.30, green: 0.78, blue: 0.58) : Color(red: 0.16, green: 0.62, blue: 0.44)
            case .feedsAndBoards:
                isDark ? Color(red: 0.92, green: 0.66, blue: 0.34) : Color(red: 0.84, green: 0.54, blue: 0.16)
            case .systemConfig:
                isDark ? Color(red: 0.56, green: 0.58, blue: 0.64) : Color(red: 0.52, green: 0.54, blue: 0.60)
        }
    }
}
