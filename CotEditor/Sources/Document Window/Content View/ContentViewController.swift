//
//  ContentViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-05-04.
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
import ControlUI
import SwiftUI

enum WorkspaceCenterKind: String, CaseIterable, Identifiable {
    case weeklyReports = "周报中心"
    case documents = "文档中心"
    case dashboard = "数据看板"
    
    var id: String { self.rawValue }
}


enum WorkspaceCenterIcons {
    
    private static let defaultSize = NSSize(width: 18, height: 18)
    
    
    /// Helper to draw crisp, pixel-aligned vector toolbar icons with unified stroke weight & optical balance.
    @MainActor
    private static func vectorIcon(
        size: NSSize = defaultSize,
        isTemplate: Bool,
        draw: @escaping (NSRect) -> Void
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.shouldAntialias = true
            draw(rect)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }
    
    
    /// Custom vector icon for 编辑 / 只读 (`editable` toolbar item): sleek stylus nib + writing baseline.
    @MainActor
    static func editableIcon(isEditable: Bool, size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            
            // Angled sleek stylus body
            let pen = NSBezierPath()
            pen.lineWidth = 1.45
            pen.lineCapStyle = .round
            pen.lineJoinStyle = .round
            pen.move(to: NSPoint(x: 4.0, y: 4.0))
            pen.line(to: NSPoint(x: 5.1, y: 7.4))
            pen.line(to: NSPoint(x: 12.6, y: 14.9))
            pen.curve(to: NSPoint(x: 14.9, y: 12.6), controlPoint1: NSPoint(x: 13.7, y: 16.0), controlPoint2: NSPoint(x: 16.0, y: 13.7))
            pen.line(to: NSPoint(x: 7.4, y: 5.1))
            pen.close()
            pen.stroke()
            
            // Subtle nib collar accent
            let collar = NSBezierPath()
            collar.lineWidth = 1.25
            collar.lineCapStyle = .round
            collar.move(to: NSPoint(x: 10.9, y: 13.2))
            collar.line(to: NSPoint(x: 13.2, y: 10.9))
            collar.stroke()
            
            // Crisp writing baseline
            let baseline = NSBezierPath()
            baseline.lineWidth = 1.4
            baseline.lineCapStyle = .round
            baseline.move(to: NSPoint(x: 3.5, y: 2.3))
            baseline.line(to: NSPoint(x: 14.5, y: 2.3))
            baseline.stroke()
            
            if !isEditable {
                // Diagonal read-only slash
                let slash = NSBezierPath()
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                slash.move(to: NSPoint(x: 3.2, y: 14.8))
                slash.line(to: NSPoint(x: 14.8, y: 3.2))
                slash.stroke()
            }
        }
    }
    
    
    /// Custom vector icon for Emoji (`quickEmoji` toolbar item): soft modern geometric smile with happy arcs.
    @MainActor
    static func quickEmojiIcon(size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            
            let face = NSBezierPath(ovalIn: NSRect(x: 2.4, y: 2.4, width: 13.2, height: 13.2))
            face.lineWidth = 1.45
            face.stroke()
            
            // Happy crescent eyes
            let leftEye = NSBezierPath()
            leftEye.lineWidth = 1.35
            leftEye.lineCapStyle = .round
            leftEye.move(to: NSPoint(x: 5.8, y: 10.1))
            leftEye.curve(to: NSPoint(x: 7.7, y: 10.1), controlPoint1: NSPoint(x: 6.3, y: 11.3), controlPoint2: NSPoint(x: 7.2, y: 11.3))
            leftEye.stroke()
            
            let rightEye = NSBezierPath()
            rightEye.lineWidth = 1.35
            rightEye.lineCapStyle = .round
            rightEye.move(to: NSPoint(x: 10.3, y: 10.1))
            rightEye.curve(to: NSPoint(x: 12.2, y: 10.1), controlPoint1: NSPoint(x: 10.8, y: 11.3), controlPoint2: NSPoint(x: 11.7, y: 11.3))
            rightEye.stroke()
            
            // Warm smile curve
            let smile = NSBezierPath()
            smile.lineWidth = 1.4
            smile.lineCapStyle = .round
            smile.move(to: NSPoint(x: 6.1, y: 7.2))
            smile.curve(to: NSPoint(x: 11.9, y: 7.2), controlPoint1: NSPoint(x: 7.4, y: 5.0), controlPoint2: NSPoint(x: 10.6, y: 5.0))
            smile.stroke()
        }
    }
    
    
    /// Custom vector icon for 数据看板: sleek rounded Bento frame with rising bar columns + highlight dot.
    @MainActor
    static func analyticsDashboardIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        
        let strokeColor: NSColor = isActive ? .controlAccentColor : .labelColor
        return self.vectorIcon(size: size, isTemplate: !isActive) { _ in
            let frameRect = NSRect(x: 2.3, y: 2.5, width: 13.4, height: 13.0)
            let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 3.4, yRadius: 3.4)
            if isActive {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                framePath.fill()
            }
            strokeColor.setStroke()
            framePath.lineWidth = 1.45
            framePath.stroke()
            
            // Three crisp ascending rounded bars
            strokeColor.setFill()
            let bars: [(x: CGFloat, h: CGFloat)] = [
                (5.2, 3.8),
                (8.2, 6.2),
                (11.2, 8.2),
            ]
            for bar in bars {
                let rect = NSRect(x: bar.x, y: 4.8, width: 1.75, height: bar.h)
                NSBezierPath(roundedRect: rect, xRadius: 0.85, yRadius: 0.85).fill()
            }
            
            // Small live telemetry dot top-left inside card
            let dot = NSBezierPath(ovalIn: NSRect(x: 4.9, y: 11.4, width: 2.1, height: 2.1))
            dot.fill()
        }
    }
    
    
    /// Custom vector icon for 深浅外观: minimalist geometric sun (light) and sculpted crescent + twin stars (dark).
    @MainActor
    static func appearanceModeIcon(isDark: Bool, size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            
            if isDark {
                // Sculpted crescent moon
                let moon = NSBezierPath()
                moon.lineWidth = 1.45
                moon.lineCapStyle = .round
                moon.lineJoinStyle = .round
                moon.move(to: NSPoint(x: 11.4, y: 14.3))
                moon.curve(to: NSPoint(x: 3.4, y: 8.6), controlPoint1: NSPoint(x: 6.5, y: 15.1), controlPoint2: NSPoint(x: 3.0, y: 11.9))
                moon.curve(to: NSPoint(x: 13.7, y: 5.8), controlPoint1: NSPoint(x: 3.9, y: 4.4), controlPoint2: NSPoint(x: 9.7, y: 2.2))
                moon.curve(to: NSPoint(x: 8.4, y: 9.2), controlPoint1: NSPoint(x: 10.6, y: 5.7), controlPoint2: NSPoint(x: 8.3, y: 6.9))
                moon.curve(to: NSPoint(x: 11.4, y: 14.3), controlPoint1: NSPoint(x: 8.5, y: 11.6), controlPoint2: NSPoint(x: 9.6, y: 13.4))
                moon.close()
                moon.stroke()
                
                // Crisp 4-point companion star
                Self.drawFourPointStar(center: NSPoint(x: 13.6, y: 13.0), outerRadius: 2.1, innerRadius: 0.65)
                NSBezierPath(ovalIn: NSRect(x: 13.8, y: 8.8, width: 1.5, height: 1.5)).fill()
            } else {
                // Central sun orb
                let center = NSPoint(x: 9.0, y: 9.0)
                let core = NSBezierPath(ovalIn: NSRect(x: 6.1, y: 6.1, width: 5.8, height: 5.8))
                core.lineWidth = 1.45
                core.stroke()
                
                // 8 balanced short rays
                let rays = NSBezierPath()
                rays.lineWidth = 1.4
                rays.lineCapStyle = .round
                for i in 0..<8 {
                    let angle = CGFloat(i) * (.pi / 4.0)
                    let innerR: CGFloat = 4.9
                    let outerR: CGFloat = 6.7
                    rays.move(to: NSPoint(x: center.x + cos(angle) * innerR, y: center.y + sin(angle) * innerR))
                    rays.line(to: NSPoint(x: center.x + cos(angle) * outerR, y: center.y + sin(angle) * outerR))
                }
                rays.stroke()
            }
        }
    }
    
    
    /// Custom vector icon for 周报中心: modern calendar card with twin rings & structured weekly lines.
    @MainActor
    static func weeklyReportIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        
        let strokeColor: NSColor = isActive ? .controlAccentColor : .labelColor
        return self.vectorIcon(size: size, isTemplate: !isActive) { _ in
            let bodyRect = NSRect(x: 2.4, y: 2.4, width: 13.2, height: 11.6)
            let body = NSBezierPath(roundedRect: bodyRect, xRadius: 3.0, yRadius: 3.0)
            if isActive {
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                body.fill()
            }
            strokeColor.setStroke()
            body.lineWidth = 1.45
            body.stroke()
            
            // Top binding rings
            let rings = NSBezierPath()
            rings.lineWidth = 1.5
            rings.lineCapStyle = .round
            rings.move(to: NSPoint(x: 6.0, y: 15.5))
            rings.line(to: NSPoint(x: 6.0, y: 12.8))
            rings.move(to: NSPoint(x: 12.0, y: 15.5))
            rings.line(to: NSPoint(x: 12.0, y: 12.8))
            rings.stroke()
            
            // Header divider
            let header = NSBezierPath()
            header.lineWidth = 1.2
            header.move(to: NSPoint(x: 2.7, y: 10.8))
            header.line(to: NSPoint(x: 15.3, y: 10.8))
            header.stroke()
            
            // Weekly highlight lines + check accent
            let lines = NSBezierPath()
            lines.lineWidth = 1.35
            lines.lineCapStyle = .round
            lines.move(to: NSPoint(x: 5.3, y: 8.1))
            lines.line(to: NSPoint(x: 12.6, y: 8.1))
            lines.move(to: NSPoint(x: 5.3, y: 5.4))
            lines.line(to: NSPoint(x: 9.8, y: 5.4))
            lines.stroke()
            
            strokeColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.3, y: 4.5, width: 1.9, height: 1.9)).fill()
        }
    }
    
    
    /// Custom vector icon for 文档中心: layered floating document stack with crisp lines.
    @MainActor
    static func documentCenterIcon(isActive: Bool, size: NSSize = defaultSize) -> NSImage {
        
        let strokeColor: NSColor = isActive ? .controlAccentColor : .labelColor
        return self.vectorIcon(size: size, isTemplate: !isActive) { _ in
            strokeColor.setStroke()
            
            // Back stacked card peek (top-right offset)
            let back = NSBezierPath()
            back.lineWidth = 1.35
            back.lineCapStyle = .round
            back.lineJoinStyle = .round
            back.move(to: NSPoint(x: 6.2, y: 13.7))
            back.line(to: NSPoint(x: 6.2, y: 14.3))
            back.curve(to: NSPoint(x: 8.1, y: 15.8), controlPoint1: NSPoint(x: 6.2, y: 15.2), controlPoint2: NSPoint(x: 7.0, y: 15.8))
            back.line(to: NSPoint(x: 13.6, y: 15.8))
            back.curve(to: NSPoint(x: 15.4, y: 14.0), controlPoint1: NSPoint(x: 14.6, y: 15.8), controlPoint2: NSPoint(x: 15.4, y: 15.0))
            back.line(to: NSPoint(x: 15.4, y: 7.2))
            back.curve(to: NSPoint(x: 13.9, y: 5.5), controlPoint1: NSPoint(x: 15.4, y: 6.3), controlPoint2: NSPoint(x: 14.7, y: 5.6))
            back.stroke()
            
            // Front document card
            let frontRect = NSRect(x: 2.8, y: 2.3, width: 10.2, height: 11.4)
            let front = NSBezierPath(roundedRect: frontRect, xRadius: 2.5, yRadius: 2.5)
            if isActive {
                NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
                front.fill()
            }
            front.lineWidth = 1.45
            front.stroke()
            
            // Crisp document content lines
            let textLines = NSBezierPath()
            textLines.lineWidth = 1.35
            textLines.lineCapStyle = .round
            textLines.move(to: NSPoint(x: 5.3, y: 10.4))
            textLines.line(to: NSPoint(x: 10.5, y: 10.4))
            textLines.move(to: NSPoint(x: 5.3, y: 7.9))
            textLines.line(to: NSPoint(x: 10.5, y: 7.9))
            textLines.move(to: NSPoint(x: 5.3, y: 5.4))
            textLines.line(to: NSPoint(x: 8.4, y: 5.4))
            textLines.stroke()
        }
    }
    
    
    /// Custom vector icon for 终端 (`terminal`): rounded console frame with crisp `>_` glyph.
    @MainActor
    static func terminalIcon(size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setStroke()
            
            let bezel = NSBezierPath(roundedRect: NSRect(x: 2.1, y: 3.1, width: 13.8, height: 11.8), xRadius: 3.1, yRadius: 3.1)
            bezel.lineWidth = 1.45
            bezel.stroke()
            
            let prompt = NSBezierPath()
            prompt.lineWidth = 1.45
            prompt.lineCapStyle = .round
            prompt.lineJoinStyle = .round
            prompt.move(to: NSPoint(x: 5.3, y: 11.2))
            prompt.line(to: NSPoint(x: 7.9, y: 9.0))
            prompt.line(to: NSPoint(x: 5.3, y: 6.8))
            prompt.move(to: NSPoint(x: 9.4, y: 6.8))
            prompt.line(to: NSPoint(x: 12.6, y: 6.8))
            prompt.stroke()
        }
    }
    
    
    /// Custom vector icon for AI 设置 (`aiSettings`): graceful curved 4-point starlight constellation.
    @MainActor
    static func aiSettingsIcon(size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setFill()
            Self.drawFourPointStar(center: NSPoint(x: 8.2, y: 8.6), outerRadius: 5.6, innerRadius: 1.55)
            Self.drawFourPointStar(center: NSPoint(x: 13.9, y: 13.6), outerRadius: 2.4, innerRadius: 0.72)
            Self.drawFourPointStar(center: NSPoint(x: 14.3, y: 5.0), outerRadius: 1.7, innerRadius: 0.52)
        }
    }
    
    
    /// Custom vector icon for 右侧检查器 (`inspector`): rounded window with right sidebar detail ticks.
    @MainActor
    static func inspectorIcon(size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setStroke()
            
            let frame = NSBezierPath(roundedRect: NSRect(x: 2.1, y: 3.0, width: 13.8, height: 12.0), xRadius: 3.0, yRadius: 3.0)
            frame.lineWidth = 1.45
            frame.stroke()
            
            let divider = NSBezierPath()
            divider.lineWidth = 1.35
            divider.move(to: NSPoint(x: 10.6, y: 3.2))
            divider.line(to: NSPoint(x: 10.6, y: 14.8))
            divider.stroke()
            
            let ticks = NSBezierPath()
            ticks.lineWidth = 1.25
            ticks.lineCapStyle = .round
            for y in [11.6, 9.0, 6.4] as [CGFloat] {
                ticks.move(to: NSPoint(x: 12.2, y: y))
                ticks.line(to: NSPoint(x: 14.0, y: y))
            }
            ticks.stroke()
        }
    }
    
    
    /// Custom vector icon for 更多 (`more`): clean geometric triad inside a delicate ring.
    @MainActor
    static func moreIcon(size: NSSize = defaultSize) -> NSImage {
        
        self.vectorIcon(size: size, isTemplate: true) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            
            let ring = NSBezierPath(roundedRect: NSRect(x: 2.3, y: 2.3, width: 13.4, height: 13.4), xRadius: 4.6, yRadius: 4.6)
            ring.lineWidth = 1.4
            ring.stroke()
            
            for x in [5.4, 8.25, 11.1] as [CGFloat] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 8.25, width: 1.55, height: 1.55)).fill()
            }
        }
    }
    
    
    /// Draws a smooth curved 4-point diamond sparkle centered at `center`.
    private static func drawFourPointStar(center: NSPoint, outerRadius r: CGFloat, innerRadius ir: CGFloat) {
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x, y: center.y + r))
        path.curve(
            to: NSPoint(x: center.x + r, y: center.y),
            controlPoint1: NSPoint(x: center.x + ir * 0.4, y: center.y + ir),
            controlPoint2: NSPoint(x: center.x + ir, y: center.y + ir * 0.4)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y - r),
            controlPoint1: NSPoint(x: center.x + ir, y: center.y - ir * 0.4),
            controlPoint2: NSPoint(x: center.x + ir * 0.4, y: center.y - ir)
        )
        path.curve(
            to: NSPoint(x: center.x - r, y: center.y),
            controlPoint1: NSPoint(x: center.x - ir * 0.4, y: center.y - ir),
            controlPoint2: NSPoint(x: center.x - ir, y: center.y - ir * 0.4)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y + r),
            controlPoint1: NSPoint(x: center.x - ir, y: center.y + ir * 0.4),
            controlPoint2: NSPoint(x: center.x - ir * 0.4, y: center.y + ir)
        )
        path.close()
        path.fill()
    }
}


final class ContentViewController: NSSplitViewController {
    
    // MARK: Public Properties
    
    var document: DataDocument?  { didSet { self.updateDocument(from: oldValue) } }
    
    /// Whether the terminal panel is currently part of the window.
    var isTerminalVisible: Bool  { self.terminalItem != nil }
    
    /// Which in-window workspace center (if any) is currently open.
    private(set) var activeCenter: WorkspaceCenterKind?
    
    var documentViewController: DocumentViewController? {
        
        self.splitViewItems.first?.viewController as? DocumentViewController
    }
    
    
    // MARK: Private Properties
    
    private var terminalItem: NSSplitViewItem?
    private var terminalViewController: TerminalViewController?
    private var windowCloseObserver: NSObjectProtocol?
    private var centerEscMonitor: Any?
    private var centerHostView: NSHostingView<WorkspaceCenterHostView>?
    private let centerHostModel = WorkspaceCenterHostModel()
    private let weeklyReportState = WeeklyReportCenterState()
    private let documentCenterState = DocumentCenterState()
    
    
    // MARK: Lifecycle
    
    init(document: DataDocument?) {
        
        self.document = document
        
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder: NSCoder) {
        
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func loadView() {
        
        let container = NSView()
        container.frame.size = NSSize(width: 640, height: 600)
        self.view = container
        
        let splitView = self.splitView
        splitView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: container.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.splitView.isVertical = false
        self.splitViewItems = [
            NSSplitViewItem(viewController: .viewController(document: self.document)),
        ]
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        if self.windowCloseObserver == nil, let window = self.view.window {
            self.windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                             object: window,
                                                                             queue: .main)
            { [weak self] _ in
                self?.hideTerminal()
            }
        }
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        if let observer = self.windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            self.windowCloseObserver = nil
        }
        
        // never leave a shell alive behind a closed or replaced window
        self.hideTerminal()
        self.removeCenterEscMonitor()
    }
    
    
    isolated deinit {
        
        if let observer = self.windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = self.centerEscMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    
    // MARK: Toolbar & UI Validation
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        
        if let toolbarItem = item as? NSToolbarItem,
           toolbarItem.action == #selector(toggleWeeklyReportCenter(_:))
            || toolbarItem.action == #selector(toggleDocumentCenter(_:))
            || toolbarItem.action == #selector(toggleAnalyticsDashboard(_:))
        {
            return self.validateCenterToolbarItem(toolbarItem)
        }
        return super.validateUserInterfaceItem(item)
    }
    
    
    /// Updates the toggle state of the in-window Weekly Report Center, Document Center, and Analytics Dashboard toolbar items.
    func validateCenterToolbarItem(_ item: NSToolbarItem) -> Bool {
        
        switch item.action {
            case #selector(toggleWeeklyReportCenter(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .weeklyReports) ? .on : .off
                return true
            case #selector(toggleDocumentCenter(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .documents) ? .on : .off
                return true
            case #selector(toggleAnalyticsDashboard(_:)):
                (item as? StatableToolbarItem)?.state = (self.activeCenter == .dashboard) ? .on : .off
                return true
            default:
                return true
        }
    }
    
    
    // MARK: In-Window Workspace Centers (Weekly Reports, Documents & Analytics Dashboard)
    
    @IBAction func toggleWeeklyReportCenter(_ sender: Any?) {
        
        if self.activeCenter == .weeklyReports {
            self.hideInWindowCenter()
        } else {
            self.showInWindowCenter(.weeklyReports)
        }
    }
    
    
    @IBAction func toggleDocumentCenter(_ sender: Any?) {
        
        if self.activeCenter == .documents {
            self.hideInWindowCenter()
        } else {
            self.showInWindowCenter(.documents)
        }
    }
    
    
    @IBAction func toggleAnalyticsDashboard(_ sender: Any?) {
        
        if self.activeCenter == .dashboard {
            self.hideInWindowCenter()
        } else {
            self.showInWindowCenter(.dashboard)
        }
    }
    
    
    /// Opens Weekly Report Center, Document Center, or Analytics Dashboard directly inside this window (no separate window).
    func showInWindowCenter(
        _ kind: WorkspaceCenterKind,
        weeklyMode: WeeklyReportWindowController.InitialMode = .history,
        selectingReportID: String? = nil
    ) {
        self.activeCenter = kind
        
        switch kind {
            case .weeklyReports:
                if CotLocalDatabase.shared.weeklyReports.isEmpty {
                    CotLocalDatabase.shared.reloadWeeklyReports()
                }
                self.weeklyReportState.isGeneratorActive = (weeklyMode == .generator)
                self.weeklyReportState.rebuildGroups()
                if let selectingReportID {
                    self.weeklyReportState.selectedReportID = selectingReportID
                } else if self.weeklyReportState.selectedReportID == nil {
                    self.weeklyReportState.selectedReportID = CotLocalDatabase.shared.weeklyReports.first?.id
                }
                self.weeklyReportState.refreshOpenSources()
            case .documents:
                self.documentCenterState.refresh()
            case .dashboard:
                AnalyticsManager.shared.flushPendingStats()
                AnalyticsManager.shared.reloadFromDatabase()
        }
        
        self.centerHostModel.selectedKind = kind
        if let existing = self.centerHostView {
            existing.alphaValue = 1
            existing.isHidden = false
        } else {
            let rootView = self.makeCenterHostView()
            let hostingView = NSHostingView(rootView: rootView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(hostingView, positioned: .above, relativeTo: self.splitView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            ])
            self.centerHostView = hostingView
        }
        
        self.splitView.isHidden = true
        self.view.window?.invalidateCursorRects(for: self.view)
        NSCursor.arrow.set()
        
        self.installCenterEscMonitor()
        self.view.window?.toolbar?.validateVisibleItems()
    }
    
    
    /// Closes any open in-window center and returns focus to the active editor pane.
    func hideInWindowCenter() {
        
        self.activeCenter = nil
        self.removeCenterEscMonitor()
        self.splitView.isHidden = false
        self.centerHostView?.isHidden = true
        self.view.window?.invalidateCursorRects(for: self.view)
        
        self.view.window?.toolbar?.validateVisibleItems()
        if let textView = self.documentViewController?.focusedTextView {
            self.view.window?.makeFirstResponderDiscardingMarkedText(textView)
        }
    }
    
    
    private func makeCenterHostView() -> WorkspaceCenterHostView {
        
        WorkspaceCenterHostView(
            hostModel: self.centerHostModel,
            weeklyReportState: self.weeklyReportState,
            documentCenterState: self.documentCenterState,
            onDismiss: { [weak self] in
                self?.hideInWindowCenter()
            },
            onOpenWeeklyReport: { [weak self] report in
                guard let self else { return }
                self.documentViewController?.openStoredWeeklyReport(report)
                self.hideInWindowCenter()
            },
            onOpenManagedDocument: { [weak self] liveDoc, record in
                guard let self, let docVC = self.documentViewController else { return }
                if let liveDoc {
                    docVC.openOrFocusDocument(liveDoc)
                } else if let record {
                    docVC.openStoredDocumentRecord(record)
                }
                self.hideInWindowCenter()
            },
            onOpenAllManagedDocuments: { [weak self] items in
                guard let self, let docVC = self.documentViewController else { return }
                let entries = items.map { item in
                    (liveDoc: self.documentCenterState.liveDocument(for: item.id), record: item.storedRecord)
                }
                let preferredRecordID = items.first(where: { $0.id == self.documentCenterState.selectedID })?.dbRecordID
                docVC.openAllManagedDocuments(entries, focusing: preferredRecordID)
                self.hideInWindowCenter()
            },
            onDeleteManagedDocument: { [weak self] item in
                self?.deleteManagedDocument(item)
            },
            onCreateNewDocument: { [weak self] in
                guard let self, let docVC = self.documentViewController else { return }
                if let created = try? (NSDocumentController.shared as? DocumentController)?.openUntitledDocumentAndDisplay(false) as? Document {
                    docVC.openOrFocusDocument(created, splitRight: false)
                    AnalyticsManager.shared.recordFileCreated()
                }
                self.hideInWindowCenter()
            }
        )
    }
    
    
    private func deleteManagedDocument(_ item: DocumentCenterState.ManagedDocumentItem) {
        
        let liveDoc = self.documentCenterState.liveDocument(for: item.id)
        
        let finishDeletion: () -> Void = { [weak self] in
            if let liveDoc {
                var closedInPane = false
                for window in NSApp.orderedWindows {
                    guard let docVC = (window.windowController as? DocumentWindowController)?.documentViewController else { continue }
                    if docVC.paneDocuments.contains(where: { $0 === liveDoc }) {
                        docVC.closeDocumentFromCenter(liveDoc)
                        closedInPane = true
                    }
                }
                if !closedInPane {
                    liveDoc.updateChangeCount(.changeCleared)
                    liveDoc.hasUncommittedChanges = false
                    liveDoc.close()
                }
            }
            
            CotLocalDatabase.shared.trashDocument(id: item.dbRecordID ?? item.id, filePath: item.filePath)
            self?.documentCenterState.refresh()
        }
        
        if let liveDoc, item.filePath != nil, item.isDirty, let docVC = self.documentViewController {
            docVC.reviewDocuments([liveDoc]) { canClose in
                guard canClose else { return }
                finishDeletion()
            }
        } else {
            finishDeletion()
        }
    }
    
    
    private func installCenterEscMonitor() {
        
        self.removeCenterEscMonitor()
        self.centerEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                self.activeCenter != nil,
                event.window === self.view.window,
                event.keyCode == 53  // Escape
            else { return event }
            
            if let responder = event.window?.firstResponder as? NSTextView, responder.hasMarkedText() {
                return event
            }
            self.hideInWindowCenter()
            return nil
        }
    }
    
    
    private func removeCenterEscMonitor() {
        
        if let monitor = self.centerEscMonitor {
            NSEvent.removeMonitor(monitor)
            self.centerEscMonitor = nil
        }
    }
    
    
    // MARK: Split View Controller Methods
    
    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        
        // The terminal panel is resizable; the status bar boundary is not.
        if let terminalItem = self.terminalItem,
           let index = self.splitViewItems.firstIndex(where: { $0 === terminalItem }),
           dividerIndex == index - 1
        {
            return proposedEffectiveRect
        }
        
        // avoid showing draggable cursor for the status bar boundary
        return .zero
    }
    
    
    // MARK: Terminal
    
    /// Shows the terminal panel when hidden, and hides (and terminates) it when shown.
    ///
    /// - Parameter sender: The action sender.
    @IBAction func toggleTerminal(_ sender: Any?) {
        
        if self.isTerminalVisible {
            self.hideTerminal()
        } else {
            self.showTerminal()
        }
    }
    
    
    /// Inserts the terminal panel below the editor and starts a fresh shell.
    func showTerminal() {
        
        guard
            self.terminalItem == nil,
            self.view.window != nil
        else { return }
        
        let viewController = TerminalViewController()
        viewController.onProcessTerminated = { [weak self] in
            self?.hideTerminal()
        }
        viewController.themeProvider = { [weak self] in
            self?.documentViewController?.currentTheme
        }
        viewController.fontProvider = { [weak self] in
            self?.documentViewController?.focusedTextView?.font
        }
        
        let item = NSSplitViewItem(viewController: viewController)
        item.canCollapse = false
        item.minimumThickness = 80
        // the editor takes the extra height when the window resizes; the panel keeps its own
        item.holdingPriority = NSLayoutConstraint.Priority(260)
        
        self.insertSplitViewItem(item, at: min(1, self.splitViewItems.count))

        self.terminalItem = item
        self.terminalViewController = viewController
        
        viewController.start(in: self.terminalWorkingDirectory)
        
        // The split view only knows the new item's size after a layout pass, so set the
        // divider on the next run loop turn and once more after the panel is drawn.
        DispatchQueue.main.async { [weak self] in
            self?.view.layoutSubtreeIfNeeded()
            self?.applyTerminalHeight()
            
            DispatchQueue.main.async {
                self?.view.layoutSubtreeIfNeeded()
                self?.applyTerminalHeight()
            }
        }
    }
    
    
    /// Removes the terminal panel and terminates its shell.
    func hideTerminal() {
        
        guard let item = self.terminalItem else { return }
        
        self.terminalItem = nil
        let viewController = self.terminalViewController
        self.terminalViewController = nil
        
        // terminate the shell before the view (and its PTY) goes away
        viewController?.shutdown()
        self.removeSplitViewItem(item)
        
        if let textView = self.documentViewController?.focusedTextView {
            self.view.window?.makeFirstResponder(textView)
        }
    }
    
    
    /// The process identifier of the terminal's shell, for tests and diagnostics.
    var terminalShellProcessIdentifier: pid_t? {
        
        self.terminalViewController?.shellProcessIdentifier
    }
    
    
    /// The folder a new terminal starts in: the document's folder, or the home folder.
    private var terminalWorkingDirectory: URL? {
        
        guard let fileURL = (self.document as? Document)?.fileURL else { return nil }
        
        return fileURL.deletingLastPathComponent()
    }
    
    
    /// Gives the terminal panel a sensible share of the window height.
    private func applyTerminalHeight() {
        
        guard
            let item = self.terminalItem,
            let index = self.splitViewItems.firstIndex(where: { $0 === item }),
            index > 0
        else { return }
        
        let height = self.splitView.bounds.height
        guard height > 0 else { return }
        
        let statusBarHeight = (self.parent as? WindowContentViewController)?.statusBarHeight ?? 0
        let panelHeight = min(240, max(140, height * 0.3))
        
        self.splitView.setPosition(max(0, height - statusBarHeight - panelHeight), ofDividerAt: index - 1)
    }
    
    
    // MARK: Private Methods
    
    /// Updates the document in children.
    ///
    /// - Parameter oldDocument: The previous document.
    private func updateDocument(from oldDocument: DataDocument?) {
        
        guard oldDocument != self.document else { return }
        
        if let existing = self.documentViewController,
           let newDocument = self.document as? Document,
           existing.document === newDocument || existing.paneDocuments.contains(where: { $0 === newDocument })
        {
            return
        }
        
        self.splitViewItems[0] = NSSplitViewItem(viewController: .viewController(document: self.document))
    }
}


private extension NSViewController {
    
    /// Creates a new view controller with the passed-in document.
    ///
    /// - Parameter document: The represented document.
    /// - Returns: A view controller.
    static func viewController(document: DataDocument?) -> sending NSViewController {
        
        switch document {
            case let document as Document:
                DocumentViewController(document: document)
            case let document as PreviewDocument:
                NSHostingController(rootView: FilePreviewView(item: document))
            case .none:
                NSHostingController(rootView: NoDocumentView())
            default:
                preconditionFailure()
        }
    }
}


@MainActor @Observable
private final class WorkspaceCenterHostModel {
    var selectedKind: WorkspaceCenterKind = .documents
}


private struct WorkspaceCenterHostView: View {
    
    let hostModel: WorkspaceCenterHostModel
    let weeklyReportState: WeeklyReportCenterState
    let documentCenterState: DocumentCenterState
    
    var onDismiss: () -> Void
    var onOpenWeeklyReport: (StoredWeeklyReport) -> Void
    var onOpenManagedDocument: (Document?, StoredDocumentRecord?) -> Void
    var onOpenAllManagedDocuments: ([DocumentCenterState.ManagedDocumentItem]) -> Void
    var onDeleteManagedDocument: (DocumentCenterState.ManagedDocumentItem) -> Void
    var onCreateNewDocument: () -> Void
    
    var body: some View {
        
        Group {
            switch self.hostModel.selectedKind {
                case .weeklyReports:
                    WeeklyReportCenterView(
                        state: self.weeklyReportState,
                        onOpenReport: self.onOpenWeeklyReport,
                        onDismiss: self.onDismiss
                    )
                case .documents:
                    DocumentCenterView(
                        state: self.documentCenterState,
                        onOpenDocument: self.onOpenManagedDocument,
                        onOpenAllDocuments: self.onOpenAllManagedDocuments,
                        onDeleteDocument: self.onDeleteManagedDocument,
                        onCreateNewDocument: self.onCreateNewDocument,
                        onDismiss: self.onDismiss
                    )
                case .dashboard:
                    AnalyticsDashboardView(
                        isEmbeddedInSettings: false,
                        onDismiss: self.onDismiss,
                        onOpenDocument: { record in
                            self.onOpenManagedDocument(nil, record)
                        },
                        onOpenWeeklyReport: self.onOpenWeeklyReport
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
