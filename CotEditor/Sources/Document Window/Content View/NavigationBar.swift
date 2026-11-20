//
//  NavigationBar.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-02-04.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2026 1024jp
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
import StringUtils
import SyntaxParsers

/// Pure AppKit host for the pane navigation bar so `PaneTabStripNSView` and its inline rename field
/// live outside `NSHostingView`, preventing SwiftUI focus churn from cancelling inline tab renames.
@MainActor final class PaneNavigationBarViewController: NSViewController {
    
    let outlineNavigator: OutlineNavigator
    let splitState: SplitState
    let tabs: PaneTabState
    
    let tabStripView = PaneTabStripNSView()
    
    private var trailingHostingView: NSHostingView<NavigationBarTrailingControls>?
    private var backgroundContainer: PaneNavigationBarBackgroundView?
    
    var isRenamingTab: Bool { self.tabStripView.isRenaming }
    
    
    init(outlineNavigator: OutlineNavigator, splitState: SplitState, tabs: PaneTabState) {
        
        self.outlineNavigator = outlineNavigator
        self.splitState = splitState
        self.tabs = tabs
        super.init(nibName: nil, bundle: nil)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func loadView() {
        
        let container = PaneNavigationBarBackgroundView()
        let horizontalInset: CGFloat = isLiquidGlass ? 6 : 4
        
        self.tabStripView.translatesAutoresizingMaskIntoConstraints = false
        self.tabStripView.state = self.tabs
        self.tabStripView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.tabStripView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.tabs.onRequestInlineRename = { [weak strip = self.tabStripView] tab in
            strip?.beginInlineRename(for: tab)
        }
        container.addSubview(self.tabStripView)
        
        let trailingControls = NavigationBarTrailingControls(
            outlineNavigator: self.outlineNavigator,
            tabs: self.tabs
        )
        let trailingHost = NSHostingView(rootView: trailingControls)
        trailingHost.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.sizingOptions = [.intrinsicContentSize]
        trailingHost.setContentHuggingPriority(.required, for: .horizontal)
        trailingHost.setContentCompressionResistancePriority(.required, for: .horizontal)
        container.addSubview(trailingHost)
        self.trailingHostingView = trailingHost
        
        NSLayoutConstraint.activate([
            self.tabStripView.leadingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.leadingAnchor, constant: horizontalInset),
            self.tabStripView.centerYAnchor.constraint(equalTo: container.safeAreaLayoutGuide.centerYAnchor),
            self.tabStripView.heightAnchor.constraint(equalToConstant: 24),
            self.tabStripView.trailingAnchor.constraint(equalTo: trailingHost.leadingAnchor, constant: -2),
            
            trailingHost.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -horizontalInset),
            trailingHost.centerYAnchor.constraint(equalTo: container.safeAreaLayoutGuide.centerYAnchor),
            trailingHost.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
        ])
        
        container.setAccessibilityElement(false)
        container.setAccessibilityLabel(String(localized: "Navigation Bar", table: "Document", comment: "accessibility label"))
        
        self.backgroundContainer = container
        self.view = container
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        self.tabStripView.reloadTabs()
    }
    
    
    func reloadTabs() {
        
        guard self.isViewLoaded else { return }
        self.tabStripView.state = self.tabs
        self.tabs.onRequestInlineRename = { [weak strip = self.tabStripView] tab in
            strip?.beginInlineRename(for: tab)
        }
        self.tabStripView.reloadTabs()
    }
}


private final class PaneNavigationBarBackgroundView: NSView {
    
    private let separatorLayer = CALayer()
    
    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }
    
    
    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.addSublayer(self.separatorLayer)
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func updateLayer() {
        
        self.effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            self.separatorLayer.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
    
    
    override func layout() {
        
        super.layout()
        let scale = max(self.window?.backingScaleFactor ?? 2, 1)
        let lineHeight = 1.0 / scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.separatorLayer.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: lineHeight)
        CATransaction.commit()
    }
}


private struct NavigationBarTrailingControls: View {
    
    @State var outlineNavigator: OutlineNavigator
    @State var tabs: PaneTabState
    
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 2) {
            if self.outlineNavigator.items?.isEmpty == false {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)
                
                OutlineNavigationView(navigator: self.$outlineNavigator)
                    .frame(maxWidth: 220)
            }
            
            if self.tabs.canClosePane {
                ClosePaneAnimatedButton(action: self.tabs.onClosePane)
                    .frame(width: 22, height: 24, alignment: .center)
                    .help(String(localized: "Close split editor", table: "Document", comment: "tooltip for button"))
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}


/// The tab bar of a pane, listing the documents the pane shows.
struct NavigationBar: View {
    
    @State var outlineNavigator: OutlineNavigator
    var splitState: SplitState
    @State var tabs: PaneTabState
    
    
    var body: some View {
        
        HStack(alignment: .center, spacing: 2) {
            PaneTabStripView(state: self.tabs)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
            
            if self.outlineNavigator.items?.isEmpty == false {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)
                
                OutlineNavigationView(navigator: $outlineNavigator)
            }
            
            if self.tabs.canClosePane {
                self.closePaneButton
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, isLiquidGlass ? 6 : 4)
        .frame(height: isLiquidGlass ? 30 : 28)
        .background(.windowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1 / max(NSScreen.main?.backingScaleFactor ?? 2, 1))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Navigation Bar", table: "Document", comment: "accessibility label"))
    }
    
    
    // MARK: Private Views
    
    private var closePaneButton: some View {
        
        ClosePaneAnimatedButton(action: self.tabs.onClosePane)
            .frame(width: 22, height: 24, alignment: .center)
            .help(String(localized: "Close split editor", table: "Document", comment: "tooltip for button"))
    }
}


/// Close-pane button: a quarter turn and a soft red fill on hover, matching the tab close buttons.
private struct ClosePaneAnimatedButton: View {
    
    var action: () -> Void
    
    @State private var isHovered = false
    
    
    var body: some View {
        Button(action: self.action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(self.isHovered ? Color.red : Color.secondary)
                .rotationEffect(.degrees(self.isHovered ? 90 : 0))
                .frame(width: 18, height: 18, alignment: .center)
                .background(
                    Circle()
                        .fill(self.isHovered ? Color.red.opacity(0.12) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 0.22)) {
                self.isHovered = hovering
            }
        }
    }
}


private struct OutlineNavigationView: View {
    
    @Binding var navigator: OutlineNavigator
    
    @State private var isLongExtraction = false
    @State private var extractionDelayTask: Task<Void, any Error>?
    
    
    var body: some View {
        
        HStack {
            if let items = self.navigator.items {
                if !items.isEmpty {
                    HStack(spacing: 0) {
                        if self.navigator.isVerticalOrientation {
                            self.nextButton(systemImage: "chevron.left")
                            self.previousButton(systemImage: "chevron.right")
                        } else {
                            self.previousButton(systemImage: "chevron.up")
                            self.nextButton(systemImage: "chevron.down")
                        }
                    }
                    
                    // Use AppKit-based picker to open programmatically (2024-05, macOS 14).
                    OutlinePicker(items: items, selection: $navigator.selection, isPresented: $navigator.isOutlinePickerPresented) {
                        self.navigator.textView?.select(range: $0.range)
                    }
                    .accessibilityLabel(String(localized: "Outline Menu", table: "Document", comment: "accessibility label"))
                }
            } else if self.isLongExtraction {
                Text("Extracting Outline…", tableName: "Document")
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            self.extractionDelayTask?.cancel()
        }
        .onChange(of: self.navigator.items, initial: true) { _, newValue in
            // show message only when parse takes more than 1 second.
            self.extractionDelayTask?.cancel()
            if newValue == nil {
                self.extractionDelayTask = Task {
                    try await Task.sleep(for: .seconds(1))
                    self.isLongExtraction = true
                }
            } else {
                self.extractionDelayTask = nil
                self.isLongExtraction = false
            }
        }
    }
    
    
    // MARK: Private Methods
    
    @ViewBuilder private func previousButton(systemImage: String) -> some View {
        
        Button {
            self.navigator.selectPreviousItem()
        } label: {
            Label(String(localized: "Previous Outline Item", table: "Document", comment: "accessibility label for button"), systemImage: systemImage)
                .frame(width: 18)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .fontWeight(.medium)
        .labelStyle(.iconOnly)
        .disabled(!self.navigator.canSelectPreviousItem)
        .help(String(localized: "Jump to previous outline item", table: "Document", comment: "tooltip for button"))
    }
    
    
    @ViewBuilder private func nextButton(systemImage: String) -> some View {
        
        Button {
            self.navigator.selectNextItem()
        } label: {
            Label(String(localized: "Next Outline Item", table: "Document", comment: "accessibility label for button"), systemImage: systemImage)
                .frame(width: 18)
                .frame(maxHeight: .infinity, alignment: .center)
        }
        .fontWeight(.medium)
        .labelStyle(.iconOnly)
        .disabled(!self.navigator.canSelectNextItem)
        .help(String(localized: "Jump to next outline item", table: "Document", comment: "tooltip for button"))
    }
}


// MARK: - Preview

#Preview {
    let navigator = OutlineNavigator()
    navigator.items = [
        OutlineItem(title: "    Heading 1", range: .notFound),
        OutlineItem(title: "Heading 2", range: .notFound),
    ]
    
    return NavigationBar(outlineNavigator: navigator, splitState: SplitState(canClose: true), tabs: PaneTabState())
        .frame(width: 300)
}


/// A plain button style with a subtle rounded hover/pressed highlight.
struct HoverPlainButtonStyle: ButtonStyle {
    
    var cornerRadius: CGFloat = 6
    
    
    func makeBody(configuration: Configuration) -> some View {
        
        HoverPlainButtonBody(configuration: configuration, cornerRadius: self.cornerRadius)
    }
    
    
    private struct HoverPlainButtonBody: View {
        
        var configuration: ButtonStyleConfiguration
        var cornerRadius: CGFloat
        
        @State private var isHovered = false
        
        
        var body: some View {
            
            self.configuration.label
                .background(
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(self.configuration.isPressed ? 0.14 : (self.isHovered ? 0.07 : 0)))
                )
                .onHover { self.isHovered = $0 }
                .animation(.easeOut(duration: 0.12), value: self.isHovered)
        }
    }
}
