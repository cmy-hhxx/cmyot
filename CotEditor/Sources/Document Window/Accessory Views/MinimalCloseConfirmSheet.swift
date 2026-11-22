//
//  MinimalCloseConfirmSheet.swift
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

enum MinimalCloseConfirmOutcome: Sendable {
    
    case save(targetURL: URL?)
    case discard
    case cancel
}


@MainActor
enum MinimalCloseConfirmController {
    
    private static let lastDirectoryDefaultsKey = "cot.quickSave.lastDirectoryPath"
    
    
    static func defaultSaveDirectory() -> URL {
        if let savedPath = UserDefaults.standard.string(forKey: Self.lastDirectoryDefaultsKey),
           !savedPath.isEmpty
        {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: savedPath, isDirectory: &isDir), isDir.boolValue {
                return URL(filePath: savedPath, directoryHint: .isDirectory)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }
    
    
    static func rememberSaveDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.lastDirectoryDefaultsKey)
    }
    
    
    static func uniqueDestinationURL(in directory: URL, baseName: String, pathExtension: String) -> URL {
        let sanitizedBase = baseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let stem = sanitizedBase.isEmpty ? AppLanguage.text("未命名", en: "Untitled") : sanitizedBase
        let ext = pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let resolvedExt = ext.isEmpty ? "txt" : ext
        
        var candidate = directory.appending(path: "\(stem).\(resolvedExt)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(stem) \(suffix).\(resolvedExt)")
            suffix += 1
        }
        return candidate
    }
    
    
    static func presentSheet(
        documentTitle: String,
        isUntitled: Bool,
        suggestedExtension: String,
        on hostWindow: NSWindow,
        completion: @escaping @MainActor (MinimalCloseConfirmOutcome) -> Void
    ) {
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: isUntitled ? 176 : 124),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.identifier = .contentDependentAlert
        sheetWindow.isReleasedWhenClosed = false
        sheetWindow.backgroundColor = .clear
        
        var didComplete = false
        let finish: @MainActor (MinimalCloseConfirmOutcome) -> Void = { outcome in
            guard !didComplete else { return }
            didComplete = true
            hostWindow.endSheet(sheetWindow)
            completion(outcome)
        }
        
        let view = MinimalCloseConfirmCardView(
            documentTitle: documentTitle,
            isUntitled: isUntitled,
            suggestedExtension: suggestedExtension,
            initialDirectory: Self.defaultSaveDirectory(),
            onOutcome: finish
        )
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        sheetWindow.contentViewController = hosting
        
        hostWindow.beginSheet(sheetWindow) { _ in
            if !didComplete {
                didComplete = true
                completion(.cancel)
            }
        }
    }
}


private struct MinimalCloseConfirmCardView: View {
    
    let documentTitle: String
    let isUntitled: Bool
    let suggestedExtension: String
    let initialDirectory: URL
    let onOutcome: (MinimalCloseConfirmOutcome) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var fileName: String
    @State private var directory: URL
    @State private var isEditingFileName = false
    
    init(
        documentTitle: String,
        isUntitled: Bool,
        suggestedExtension: String,
        initialDirectory: URL,
        onOutcome: @escaping (MinimalCloseConfirmOutcome) -> Void
    ) {
        self.documentTitle = documentTitle
        self.isUntitled = isUntitled
        self.suggestedExtension = suggestedExtension
        self.initialDirectory = initialDirectory
        self.onOutcome = onOutcome
        self._fileName = State(initialValue: (documentTitle as NSString).deletingPathExtension.isEmpty ? documentTitle : (documentTitle as NSString).deletingPathExtension)
        self._directory = State(initialValue: initialDirectory)
    }
    
    
    var body: some View {
        let extLabel = self.suggestedExtension.isEmpty ? "txt" : self.suggestedExtension
        let folderName = self.directory.lastPathComponent
        
        VStack(alignment: .leading, spacing: 14) {
            // Single clean headline — zero heavy warning copy
            Text(AppLanguage.text("要保存「\(self.documentTitle)」吗？", en: "Save “\(self.documentTitle)”?"))
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            // For untitled docs: lightweight 1-row quick destination + optional inline filename
            if self.isUntitled {
                HStack(spacing: 8) {
                    if self.isEditingFileName {
                        TextField(AppLanguage.text("文件名", en: "Name"), text: self.$fileName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit {
                                self.commitSave()
                            }
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                self.isEditingFileName = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(self.fileName).\(extLabel)")
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "pencil")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(self.pillFill, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help(AppLanguage.text("点击修改文件名", en: "Rename"))
                    }
                    
                    Spacer(minLength: 4)
                    
                    Menu {
                        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
                            Button(AppLanguage.text("桌面", en: "Desktop")) {
                                self.selectDirectory(desktop)
                            }
                        }
                        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            Button(AppLanguage.text("文稿", en: "Documents")) {
                                self.selectDirectory(docs)
                            }
                        }
                        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                            Button(AppLanguage.text("下载", en: "Downloads")) {
                                self.selectDirectory(downloads)
                            }
                        }
                        Divider()
                        Button(AppLanguage.text("选择文件夹…", en: "Choose Folder…")) {
                            self.pickCustomFolder()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Text(Self.localizedFolderName(folderName))
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(self.pillFill, in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            
            // Comfortable 1-click action strip
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    self.onOutcome(.discard)
                } label: {
                    Text(AppLanguage.text("不保存", en: "Don’t Save"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(red: 0.86, green: 0.24, blue: 0.24))
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            Color(red: 0.86, green: 0.24, blue: 0.24).opacity(self.colorScheme == .dark ? 0.16 : 0.09),
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .keyboardShortcut("d", modifiers: .command)
                
                Spacer(minLength: 4)
                
                Button {
                    self.onOutcome(.cancel)
                } label: {
                    Text(AppLanguage.text("取消", en: "Cancel"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(self.pillFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .keyboardShortcut(.cancelAction)
                
                Button {
                    self.commitSave()
                } label: {
                    Text(AppLanguage.text("保存", en: "Save"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(StudioPaletteManager.shared.activeAccentColor, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(width: 344)
        .background(.regularMaterial)
    }
    
    
    private var pillFill: Color {
        self.colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }
    
    
    private static func localizedFolderName(_ raw: String) -> String {
        switch raw {
            case "Desktop": AppLanguage.text("桌面", en: "Desktop")
            case "Documents": AppLanguage.text("文稿", en: "Documents")
            case "Downloads": AppLanguage.text("下载", en: "Downloads")
            default: raw
        }
    }
    
    
    private func selectDirectory(_ url: URL) {
        self.directory = url
        MinimalCloseConfirmController.rememberSaveDirectory(url)
    }
    
    
    private func pickCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = self.directory
        if panel.runModal() == .OK, let url = panel.url {
            self.selectDirectory(url)
        }
    }
    
    
    private func commitSave() {
        if self.isUntitled {
            MinimalCloseConfirmController.rememberSaveDirectory(self.directory)
            let target = MinimalCloseConfirmController.uniqueDestinationURL(
                in: self.directory,
                baseName: self.fileName,
                pathExtension: self.suggestedExtension
            )
            self.onOutcome(.save(targetURL: target))
        } else {
            self.onOutcome(.save(targetURL: nil))
        }
    }
}
