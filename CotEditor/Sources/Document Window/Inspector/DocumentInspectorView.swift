//
//  DocumentInspectorView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2016-05-31.
//
//  ---------------------------------------------------------------------------
//
//  © 2016-2026 1024jp
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
import Combine
import CharacterInfo
import DocumentFile

@MainActor @Observable private final class DocumentInspectorViewModel: DocumentInspectorView.ModelProtocol {
    
    var isPresented = false  { didSet { self.invalidateObservation() } }
    var document: DataDocument?  { willSet { self.cancelObservation() } didSet { self.didUpdateDocument() } }
    
    var attributes: FileAttributes?  { self.document?.fileAttributes }
    var fileURL: URL?
    var countResult: EditorCounter.Result?  { (self.document as? Document)?.counter.result }
    
    private var urlObserver: AnyCancellable?
    
    
    // MARK: Private Methods
    
    /// Updates observations.
    private func didUpdateDocument() {
        
        self.fileURL = self.document?.fileURL
        
        if self.isPresented {
            self.startObservation()
        }
    }
    
    
    /// Invalidates observation on the document depending on the current view visibility state.
    private func invalidateObservation() {
        
        if self.isPresented {
            self.startObservation()
        } else {
            self.cancelObservation()
        }
    }
    
    
    /// Starts observations on the document.
    private func startObservation() {
        
        (document as? Document)?.counter.updatesAll = true
        
        self.urlObserver = document?.publisher(for: \.fileURL, options: .initial)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.fileURL = $0 }
    }
    
    
    /// Cancels the observations on the document.
    private func cancelObservation() {
        
        (self.document as? Document)?.counter.updatesAll = false
        self.urlObserver = nil
    }
}


// MARK: - View

struct DocumentInspectorView: View, HostedPaneView {
    
    @MainActor protocol ModelProtocol {
        
        var document: DataDocument? { get set }
        var isPresented: Bool { get set }
        
        var attributes: FileAttributes? { get }
        var fileURL: URL? { get }
        var countResult: EditorCounter.Result? { get }
    }
    
    
    var document: DataDocument?
    var isPresented: Bool = false
    
    @State var model: any ModelProtocol = DocumentInspectorViewModel()
    
    
    var body: some View {
        
        ScrollView(.vertical) {
            VStack(spacing: 8) {
                DocumentFileView(attributes: self.model.attributes, fileURL: self.model.fileURL)
                
                if let countResult = self.model.countResult {
                    if !isLiquidGlass { Divider() }
                    EditorCountView(result: countResult)
                }
            }
            .padding(EdgeInsets(top: isLiquidGlass ? 12 : 4, leading: 12, bottom: 12, trailing: 12))
            .modifier { content in
                if #available(macOS 26, *) {
                    content
                        .disclosureGroupStyle(InspectorDisclosureGroupStyle())
                        .labeledContentStyle(InspectorLabeledContentStyle())
                        .formStyle(.grouped)
                } else {
                    content
                        .disclosureGroupStyle(LegacyInspectorDisclosureGroupStyle())
                        .labeledContentStyle(LegacyInspectorLabeledContentStyle())
                }
            }
        }
        .onChange(of: self.document, initial: true) { _, newValue in
            self.model.document = newValue
        }
        .onChange(of: self.isPresented, initial: true) { _, newValue in
            self.model.isPresented = newValue
        }
        .accessibilityLabel(String(localized: "InspectorPane.document.label",
                                   defaultValue: "Document Inspector", table: "Document"))
        .controlSize(.small)
    }
}


private struct DocumentFileView: View {
    
    var attributes: FileAttributes?
    var fileURL: URL?
    
    @State private var isExpanded = true
    @State private var isCopied = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    
    
    var body: some View {
        
        DisclosureGroup(String(localized: "inspector.file.section", defaultValue: "File", table: "Personal", comment: "section title in inspector"), isExpanded: $isExpanded) {
            Form {
                LabeledContent(String(localized: "inspector.file.created", defaultValue: "Created", table: "Personal", comment: "label in document inspector"),
                               optional: self.attributes?.creationDate?.formatted(date: .abbreviated, time: .shortened))
                LabeledContent(String(localized: "inspector.file.modified", defaultValue: "Last Modified", table: "Personal", comment: "label in document inspector"),
                               optional: self.attributes?.modificationDate?.formatted(date: .abbreviated, time: .shortened))
                
                LabeledContent(String(localized: "inspector.file.copyPath", defaultValue: "Copy File Path", table: "Personal", comment: "label in document inspector")) {
                    Button {
                        self.copyFilePath()
                    } label: {
                        if self.isCopied {
                            Label(String(localized: "inspector.file.copied", defaultValue: "Copied", table: "Personal", comment: "feedback after copying the file path"),
                                  systemImage: "checkmark")
                                .foregroundStyle(.secondary)
                        } else {
                            Label(String(localized: "inspector.file.copyPath", defaultValue: "Copy File Path", table: "Personal", comment: "label in document inspector"),
                                  systemImage: "document.on.document")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(self.fileURL == nil)
                    .help(self.fileURL?.path ?? "")
                }
                
                LabeledContent(String(localized: "inspector.file.author", defaultValue: "File Author", table: "Personal", comment: "label in document inspector"),
                               optional: self.attributes?.owner)
            }
        }
        .onDisappear {
            self.copyFeedbackTask?.cancel()
        }
    }
    
    
    // MARK: Private Methods
    
    /// Copies the document file path to the pasteboard and shows a brief confirmation.
    @MainActor
    private func copyFilePath() {
        
        guard let path = self.fileURL?.path else { return }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        
        self.isCopied = true
        self.copyFeedbackTask?.cancel()
        self.copyFeedbackTask = Task {
            // a cancelled sleep falls through to the reset, so the feedback cannot stick
            try? await Task.sleep(for: .seconds(1.5))
            self.isCopied = false
        }
    }
}


private struct EditorCountView: View {
    
    var result: EditorCounter.Result
    
    @State private var isExpanded = true
    
    
    var body: some View {
        
        DisclosureGroup(String(localized: "Count", table: "Document", comment: "section title in inspector"), isExpanded: $isExpanded) {
            Form {
                Section {
                    ForEach(CountType.countCases, id: \.self) { type in
                        LabeledContent(type.label, optional: self.result.formattedValue(type: type))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
            .monospacedDigit()
        }
    }
}


@available(macOS 26, *)
private struct InspectorDisclosureGroupStyle: DisclosureGroupStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        
        DisclosureGroup(isExpanded: configuration.$isExpanded) {
            // specify negative paddings to cancel paddings implicitly added to Form.formStyle(.grouped)
            // (2026-04, macOS 26.4)
            configuration.content
                .padding(.top, -6)
                .padding(.horizontal, -12)
        } label: {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}


@available(macOS 26, *)
private struct InspectorLabeledContentStyle: LabeledContentStyle {
    
    @Environment(\.controlSize) private var controlSize
    
    
    func makeBody(configuration: Configuration) -> some View {
        
        LabeledContent {
            configuration.content
        } label: {
            configuration.label
                // forcibly set font size since the label in grouped form ignores the controlSize (2026-04, macOS 26.4)
                .font(.system(size: NSFont.systemFontSize(for: self.controlSize.nsControlSize)))
        }
    }
}


@available(macOS 26, *)
private extension ControlSize {
    
    var nsControlSize: NSControl.ControlSize {
        
        switch self {
            case .mini: .mini
            case .small: .small
            case .regular: .regular
            case .large: .large
            case .extraLarge: .extraLarge
            @unknown default: .regular
        }
    }
}


@available(macOS, deprecated: 26)
private struct LegacyInspectorDisclosureGroupStyle: DisclosureGroupStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        
        DisclosureGroup(isExpanded: configuration.$isExpanded) {
            configuration.content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}


@available(macOS, deprecated: 26)
private struct LegacyInspectorLabeledContentStyle: LabeledContentStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        
        LabeledContent {
            configuration.content
        } label: {
            configuration.label
                // keep specific width for short labels, such as Chinese
                .frame(minWidth: 48, alignment: .trailing)
        }.padding(.bottom, 1)
    }
}


// MARK: - Preview

@MainActor private struct MockedModel: DocumentInspectorView.ModelProtocol {
    
    var document: DataDocument?
    var isPresented: Bool = true
    
    var attributes: FileAttributes?
    var fileURL: URL?
    var countResult: EditorCounter.Result?
}


#Preview(traits: .fixedLayout(width: 240, height: 520)) {
    let model = MockedModel(
        attributes: .init(
            creationDate: .now,
            modificationDate: .now,
            size: 1024,
            permissions: FilePermissions(mask: 0o644),
            owner: "clarus",
            tags: [FinderTag(name: "Green", color: .green),
                   FinderTag(name: "Blue", color: .blue),
                   FinderTag(name: "None")]
        ),
        fileURL: URL(filePath: "/Users/clarus/Desktop/My Script.py"),
        countResult: .init())
    model.countResult?.characters = .init(entire: 1024, selected: 4)
    model.countResult?.lines = .init(entire: 10, selected: 1)
    
    return DocumentInspectorView(model: model)
}


#Preview("Empty", traits: .fixedLayout(width: 240, height: 520)) {
    DocumentInspectorView(isPresented: true, model: MockedModel())
}
