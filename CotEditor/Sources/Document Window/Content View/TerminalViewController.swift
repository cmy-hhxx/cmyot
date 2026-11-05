//
//  TerminalViewController.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-11-05.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 1024jp
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
import Combine
import Darwin
import Defaults
import SwiftTerm

/// The terminal panel at the bottom of a document window.
///
/// The controller owns exactly one shell process. Starting is idempotent, and `shutdown()`
/// terminates the shell together with its process group and is safe to call more than once;
/// the panel is discarded afterwards, so showing it again always starts a fresh session.
final class TerminalViewController: NSViewController {
    
    // MARK: Public Properties
    
    /// Called when the shell exited on its own (for example after the user typed `exit`).
    var onProcessTerminated: (() -> Void)?
    
    /// Provides the theme the terminal mirrors, so the panel reads as part of the editor.
    var themeProvider: (() -> Theme?)?
    
    /// Provides the editor's font, so the terminal uses the same face and size.
    var fontProvider: (() -> NSFont?)?
    
    
    /// The colors a terminal is painted with when no theme is available.
    private enum Palette {
        
        /// ANSI colors that stay legible on a dark background.
        static let dark: [(CGFloat, CGFloat, CGFloat)] = [
            (0.29, 0.29, 0.29), (0.88, 0.42, 0.46), (0.60, 0.76, 0.47), (0.90, 0.75, 0.48),
            (0.38, 0.69, 0.94), (0.78, 0.47, 0.87), (0.34, 0.71, 0.76), (0.75, 0.75, 0.75),
            (0.48, 0.48, 0.48), (1.00, 0.48, 0.53), (0.70, 0.88, 0.56), (0.94, 0.81, 0.58),
            (0.51, 0.77, 1.00), (0.85, 0.61, 0.92), (0.47, 0.81, 0.85), (0.90, 0.90, 0.90),
        ]
        
        /// ANSI colors that stay legible on a light background.
        static let light: [(CGFloat, CGFloat, CGFloat)] = [
            (0.23, 0.23, 0.23), (0.75, 0.22, 0.17), (0.18, 0.49, 0.20), (0.72, 0.53, 0.04),
            (0.08, 0.40, 0.75), (0.56, 0.14, 0.67), (0.00, 0.51, 0.56), (0.42, 0.42, 0.42),
            (0.42, 0.42, 0.42), (0.91, 0.30, 0.24), (0.26, 0.63, 0.28), (0.83, 0.63, 0.09),
            (0.12, 0.53, 0.90), (0.67, 0.28, 0.74), (0.00, 0.67, 0.76), (0.10, 0.10, 0.10),
        ]
    }
    
    /// The process identifier of the running shell, if any.
    private(set) var shellProcessIdentifier: pid_t?
    
    
    // MARK: Private Properties
    
    private var terminalView: LocalProcessTerminalView?
    private var processSource: DispatchSourceProcess?
    private var hasStarted = false
    private var isShutDown = false
    private var themeObservers: Set<AnyCancellable> = []
    
    
    // MARK: Lifecycle
    
    override func loadView() {
        
        // Give the view a real size up front: the PTY is sized from the view's bounds,
        // and a 0×0 terminal would start the shell with no room to print a prompt.
        let terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 220))
        terminalView.font = Self.fallbackFont
        self.terminalView = terminalView
        self.view = terminalView
    }
    
    
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.applyTheme()
        
        // follow the editor's theme and appearance, including live switches
        self.themeObservers = [
            UserDefaults.standard.publisher(for: .theme, initial: false)
                .sink { [weak self] _ in self?.applyTheme() },
            NotificationCenter.default.publisher(for: .didUpdateSettingNotification, object: ThemeManager.shared)
                .sink { [weak self] _ in self?.applyTheme() },
            self.view.publisher(for: \.effectiveAppearance, options: .initial)
                .dropFirst()
                .sink { [weak self] _ in self?.applyTheme() },
        ]
    }
    
    
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        self.startIfNeeded()
        self.applyTheme()
    }
    
    
    override func viewDidDisappear() {
        
        super.viewDidDisappear()
        
        self.themeObservers.removeAll()
    }
    
    
    isolated deinit {
        
        self.stopProcess()
    }
    
    
    // MARK: Public Methods
    
    /// Launches the login shell, starting in the given directory when possible.
    ///
    /// - Parameter directory: The directory the shell starts in, or `nil` for the home folder.
    func start(in directory: URL?) {
        
        self.startIfNeeded(directory: directory?.path)
    }
    
    
    /// Terminates the shell and everything it spawned, and releases the terminal view.
    ///
    /// Safe to call repeatedly; the second call is a no-op.
    func shutdown() {
        
        guard !self.isShutDown else { return }
        
        self.isShutDown = true
        self.hasStarted = false
        
        self.stopProcess()
        
        self.terminalView?.processDelegate = nil
        self.terminalView = nil
    }
    
    
    /// Gives the keyboard focus to the terminal.
    func focus() {
        
        guard let terminalView = self.terminalView else { return }
        
        self.view.window?.makeFirstResponder(terminalView)
    }
    
    
    /// Paints the terminal with the editor's theme, so the panel matches the text around it.
    func applyTheme() {
        
        guard let terminalView = self.terminalView else { return }
        
        let theme = self.themeProvider?()
        let isDark = theme?.isDarkTheme ?? self.view.effectiveAppearance.isDark
        
        terminalView.nativeBackgroundColor = theme?.background.color ?? .textBackgroundColor
        terminalView.nativeForegroundColor = theme?.text.color ?? .textColor
        terminalView.caretColor = theme?.insertionPointColor ?? .textInsertionPointColor
        terminalView.selectedTextBackgroundColor = (theme?.selectionColor ?? .selectedTextBackgroundColor)
            .withAlphaComponent(0.35)
        
        terminalView.font = self.fontProvider?() ?? Self.fallbackFont
        
        let palette = isDark ? Palette.dark : Palette.light
        terminalView.installColors(palette.map { Color(red: UInt16($0.0 * 65535),
                                                       green: UInt16($0.1 * 65535),
                                                       blue: UInt16($0.2 * 65535)) })
        
        terminalView.needsDisplay = true
    }
    
    
    // MARK: Private Methods
    
    /// Starts the shell once, when the view is on screen and nothing ran yet.
    ///
    /// - Parameter directory: The directory the shell starts in.
    private func startIfNeeded(directory: String? = nil) {
        
        guard
            !self.hasStarted,
            !self.isShutDown,
            self.view.window != nil,
            let terminalView = self.terminalView
        else { return }
        
        self.hasStarted = true
        
        terminalView.startProcess(executable: Self.shellPath,
                                  args: ["-i", "-l"],
                                  currentDirectory: directory)
        
        let pid = terminalView.process?.shellPid ?? 0
        self.shellProcessIdentifier = pid > 0 ? pid : nil
        
        if pid > 0 {
            self.observeProcessExit(pid: pid)
        }
        
        self.focus()
    }
    
    
    /// Watches the shell so the panel can go away when the user ends the session.
    ///
    /// - Parameter pid: The shell's process identifier.
    private func observeProcessExit(pid: pid_t) {
        
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, !self.isShutDown else { return }
            
            self.onProcessTerminated?()
        }
        source.resume()
        
        self.processSource = source
    }
    
    
    /// Sends SIGTERM to the shell's process group and, if it does not go away, SIGKILL.
    private func stopProcess() {
        
        self.processSource?.cancel()
        self.processSource = nil
        
        guard let pid = self.shellProcessIdentifier else { return }
        
        self.shellProcessIdentifier = nil
        
        // The shell runs as the leader of its own terminal session, so signaling the group
        // also reaches whatever command it was running at the time. SIGHUP is what an
        // interactive zsh (and bash) actually honors as "terminal closed"; SIGTERM alone
        // may be ignored by an interactive shell.
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
        
        self.terminalView?.terminate()
        
        // Reap the child ourselves: once the terminal view is gone nobody else waits for
        // it, and a shell that was just killed would otherwise stay around as a zombie
        // until the app quits.
        DispatchQueue.global(qos: .utility).async {
            Self.reapProcess(pid: pid)
        }
    }
    
    
    /// Waits for the shell to exit, escalates to SIGKILL after a grace period, and reaps it.
    ///
    /// - Parameter pid: The shell's process identifier.
    private nonisolated static func reapProcess(pid: pid_t) {
        
        var status: Int32 = 0
        
        for _ in 0..<8 {
            let result = waitpid(pid, &status, WNOHANG)
            if result != 0 {
                return  // reaped here, or already reaped by SwiftTerm
            }
            usleep(50_000)
        }
        
        kill(-pid, SIGKILL)
        kill(pid, SIGKILL)
        
        for _ in 0..<20 {
            if waitpid(pid, &status, WNOHANG) != 0 {
                return
            }
            usleep(50_000)
        }
        
        _ = waitpid(pid, &status, 0)
    }
    
    
    // MARK: Private Types
    
    /// The font used when the editor does not provide one.
    private static var fallbackFont: NSFont {
        
        NSFont(name: "SFMono-Regular", size: 12)
            ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    }
    
    
    /// The user's login shell, or zsh when it cannot be determined.
    private static var shellPath: String {
        
        if let shell = getpwuid(getuid())?.pointee.pw_shell {
            return String(cString: shell)
        }
        
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}
