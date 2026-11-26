//
//  FlowPresentationWindowController.swift
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
import UniformTypeIdentifiers
import WebKit

/// Dedicated wide presentation window for one-click interactive workflow/architecture diagrams.
@MainActor
final class FlowPresentationWindowController: NSWindowController, WKScriptMessageHandler {
    
    private let webView: WKWebView
    private var currentBlueprint: FlowPresentationBlueprint
    private var upgradeTask: Task<Void, Never>?
    
    
    init(sourceText: String, appearance: NSAppearance? = nil) {
        let initial = FlowPresentationParser.parseOffline(from: sourceText)
        self.currentBlueprint = initial
        
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1120, height: 720), configuration: config)
        self.webView = webView
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = initial.title
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 780, height: 520)
        window.contentView = webView
        window.center()
        
        super.init(window: window)
        
        config.userContentController.add(self, name: "cotFlowPre")
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let html = FlowPresentationRenderer.renderHTML(
            blueprint: initial,
            initialTheme: isDark ? .studioDark : .keynoteLight
        )
        webView.loadHTMLString(html, baseURL: nil)
        
        self.upgradeTask = Task { @MainActor [weak self] in
            let upgraded = await FlowPresentationService.generateBlueprint(from: sourceText)
            guard let self, !Task.isCancelled else { return }
            self.currentBlueprint = upgraded
            self.window?.title = upgraded.title
            if let data = try? JSONEncoder().encode(upgraded),
               let json = String(data: data, encoding: .utf8)
            {
                self.webView.evaluateJavaScript("window.setBlueprint && window.setBlueprint(\(json));", completionHandler: nil)
            }
        }
    }
    
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    isolated deinit {
        self.upgradeTask?.cancel()
        self.webView.configuration.userContentController.removeScriptMessageHandler(forName: "cotFlowPre")
    }
    
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cotFlowPre",
              let dict = message.body as? [String: Any],
              let action = dict["action"] as? String
        else { return }
        
        switch action {
            case "copyPath":
                if let path = dict["path"] as? String {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
                
            case "toggleFullscreen":
                self.window?.toggleFullScreen(nil)
                
            case "exportPNG":
                self.exportSnapshotPNG()
                
            case "exportHTML":
                let html = (dict["html"] as? String) ?? FlowPresentationRenderer.renderHTML(blueprint: self.currentBlueprint)
                self.exportStandaloneHTML(html)
                
            default:
                break
        }
    }
    
    
    private func exportSnapshotPNG() {
        let config = WKSnapshotConfiguration()
        self.webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self, let image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "\(self.currentBlueprint.title).png"
            panel.beginSheetModal(for: self.window!) { response in
                if response == .OK, let url = panel.url {
                    try? png.write(to: url, options: .atomic)
                }
            }
        }
    }
    
    
    private func exportStandaloneHTML(_ html: String) {
        guard let window = self.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(self.currentBlueprint.title).html"
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                try? html.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
