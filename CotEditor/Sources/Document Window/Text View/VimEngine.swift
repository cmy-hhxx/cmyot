//
//  VimEngine.swift
//
//  CotEditor (personal build)
//
//  A deliberately small, self-contained Vim-style modal editing layer.
//  Scope: normal / insert / visual modes, the common motions and operators,
//  one register, undo/redo, and a `:` command line supporting `set number`.
//  Registers, macros, marks, text objects and visual-block are out of scope.
//

import AppKit
import Defaults
import LineEnding
import Observation

/// The editing mode shared with the status bar.
enum VimMode: Equatable {
    
    case normal
    case insert
    case replace
    case visual
    
    var label: String {
        switch self {
            case .normal: "NORMAL"
            case .insert: "INSERT"
            case .replace: "REPLACE"
            case .visual: "VISUAL"
        }
    }
}


/// Small observable bridge so the status bar can show the current mode.
@MainActor @Observable
final class VimState {
    
    static let shared = VimState()
    
    var mode: VimMode = .normal
    var commandLine: String?  // non-nil while a `:` command is being typed
    var visualActiveLocation: Int?  // caret position to draw in visual mode
    var visualOwnerID: ObjectIdentifier?  // text view owning `visualActiveLocation`
}


/// Enables modal (Vim-style) editing in an `NSTextView`.
@MainActor
final class VimEngine {
    
    private enum OperatorKind: Character {
        case delete = "d"
        case change = "c"
        case yank = "y"
    }
    
    private enum Motion {
        case left, right, down, up
        case wordForward, wordBackward, wordEnd
        case bigWordForward, bigWordBackward, bigWordEnd
        case lineStart, firstNonBlank, lineEnd
        case documentStart, documentEnd
        case paragraphBackward, paragraphForward
        case lineDown, lineUp  // linewise counterparts of j / k
    }
    
    private enum CaseTransformMode {
        case toggle, lower, upper
    }
    
    private enum ScreenLinePosition {
        case top, middle, bottom
    }
    
    private enum FindKind {
        case forward, backward, tillForward, tillBackward
    }
    
    weak var textView: NSTextView?
    
    private var count: Int?
    private var pendingOperator: OperatorKind?
    private var pendingPrefix: Character?      // for `gg`
    private var visualAnchor: Int?
    private var register: String = ""
    private var registerIsLinewise = false
    private var commandBuffer: String?
    private var searchBuffer: String?
    private var lastSearch: String?
    private var pendingFindKind: FindKind?
    private var lastFind: (character: Character, kind: FindKind)?
    private var pendingTextObject: (operator: OperatorKind, inner: Bool)?
    private var pendingReplaceChar = false
    private var pendingMarkAction: Character?  // 'm', "'", or "`"
    private var marks: [Character: Int] = [:]
    private var visualLinewise = false
    private var lastChange: (op: OperatorKind, motion: Motion, count: Int)?
    private var lastReplaceChar: (character: Character, count: Int)?
    private var lastStatus: String?
    
    init(textView: NSTextView) {
        
        self.textView = textView
    }
    
    
    // MARK: Key handling
    
    /// Handles a key event. Returns `true` when the event was consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        
        guard let textView else { return false }
        
        let state = VimState.shared
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Command combinations stay native (⌘S, ⌘F, …).
        if flags.contains(.command) { return false }
        
        // The `:` command line is handled before anything else.
        if self.commandBuffer != nil {
            let characters = event.characters ?? ""
            return self.handleCommandKey(characters, event: event)
        }

        // The `/` search line behaves the same way.
        if self.searchBuffer != nil {
            let characters = event.characters ?? ""
            return self.handleSearchKey(characters, event: event)
        }
        
        switch state.mode {
            case .insert:
                if self.isEscape(event) || self.isControlC(event) {
                    // Commit any marked (IME) text before leaving insert mode.
                    if textView.hasMarkedText() {
                        textView.unmarkText()
                    }
                    self.enter(mode: .normal)
                    return true
                }
                return false  // normal typing, IME and shortcuts keep working
                
            case .replace:
                if self.isEscape(event) || self.isControlC(event) {
                    if textView.hasMarkedText() {
                        textView.unmarkText()
                    }
                    self.enter(mode: .normal)
                    return true
                }
                return self.handleReplaceModeKey(event)
                
            case .normal, .visual:
                // Let the IME compose when it is active (Chinese input).
                if textView.hasMarkedText() { return false }
                return self.handleNormalKey(event)
        }
    }
    
    
    private func handleNormalKey(_ event: NSEvent) -> Bool {
        
        guard let textView else { return false }
        let state = VimState.shared
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        if self.isEscape(event) {
            if state.mode == .visual {
                self.visualAnchor = nil
                self.enter(mode: .normal)
            }
            self.resetPending()
            return true
        }
        
        // Control combinations: ⌃R (redo), ⌃D / ⌃U (half-page), ⌃F / ⌃B (full-page).
        if flags.contains(.control) {
            switch event.charactersIgnoringModifiers?.lowercased() {
                case "r":
                    textView.undoManager?.redo()
                    return true
                case "d":
                    self.moveHalfPage(down: true)
                    return true
                case "u":
                    self.moveHalfPage(down: false)
                    return true
                case "f":
                    self.moveFullPage(down: true)
                    return true
                case "b":
                    self.moveFullPage(down: false)
                    return true
                default:
                    return false
            }
        }
        if flags.contains(.option) { return false }
        
        // Special keys such as arrows keep their native behaviour.
        switch event.keyCode {
            case 123, 124, 125, 126:  // ← → ↓ ↑
                return false
            default:
                break
        }
        
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            if self.pendingOperator != nil {
                _ = self.swallowPending()
                return true
            }
            return false
        }
        
        for character in characters {
            guard self.handle(character: character) else { return true }
        }
        return true
    }
    
    
    /// Returns `false` when the character was not a Vim key (so the caller can swallow it anyway in normal mode).
    private func handle(character: Character) -> Bool {
        
        let state = VimState.shared
        guard let textView = self.textView else { return false }
        
        // Resolve a pending `r<char>` single-character replacement (in normal or visual mode).
        if self.pendingReplaceChar {
            self.pendingReplaceChar = false
            if state.mode == .visual {
                self.replaceVisualSelection(with: character)
            } else {
                let count = self.takeCount()
                self.replaceCharactersUnderCursor(with: character, count: count)
                self.lastReplaceChar = (character, count)
                self.lastChange = nil
            }
            return true
        }
        
        // Resolve a pending mark operation (`ma`, `'a`, `` `a ``).
        if let markAction = self.pendingMarkAction {
            self.pendingMarkAction = nil
            if markAction == "m" {
                self.marks[character] = textView.selectedRange().location
            } else if let target = self.marks[character] {
                if markAction == "'" {
                    let nsString = textView.string as NSString
                    let lineLoc = self.firstNonBlank(in: self.lineRange(at: target), string: nsString)
                    self.setCursor(lineLoc)
                } else {
                    self.setCursor(target)
                }
            }
            return true
        }
        
        // Digit prefixes build up the count ("0" alone is a motion).
        if let digit = character.wholeNumberValue, digit >= 0, digit <= 9,
           character != "0" || self.count != nil
        {
            self.count = (self.count ?? 0) * 10 + digit
            return true
        }
        
        // Resolve a pending f / t with the next character.
        if let findKind = self.pendingFindKind {
            self.pendingFindKind = nil
            self.lastFind = (character, findKind)
            self.performFind(findKind, character: character)
            return true
        }
        
        // Resolve a pending text object (iw, a", i( …).
        if let textObject = self.pendingTextObject {
            self.pendingTextObject = nil
            if let range = self.textObjectRange(inner: textObject.inner, character: character) {
                self.apply(textObject.operator, range: range)
            }
            self.count = nil
            return true
        }
        
        // Resolve a pending operator with the next motion.
        if let op = self.pendingOperator {
            if character == "i" || character == "a" {
                self.pendingTextObject = (op, character == "i")
                return true
            }
            if let doubled = self.operatorKey(character), doubled == op {
                self.pendingOperator = nil
                self.applyLinewiseOperator(op)
                return true
            }
            if let motion = self.motion(for: character) {
                self.pendingOperator = nil
                self.apply(op, motion: motion)
                return true
            }
            self.resetPending()
            return true
        }
        
        // Resolve the `g` prefix (`gg`, `ge`, `gE`, `g_`, `gi`).
        if self.pendingPrefix == "g" {
            self.pendingPrefix = nil
            switch character {
                case "g": self.move(.documentStart)
                case "e": self.moveBackwardWordEnd(big: false)
                case "E": self.moveBackwardWordEnd(big: true)
                case "_": self.moveLastNonBlankOfLine()
                case "i": self.enter(mode: .insert)
                default: break
            }
            return true
        }
        
        // Resolve `z` prefix (`zz`, `zt`, `zb`) and `Z` prefix (`ZZ`, `ZQ`).
        if self.pendingPrefix == "z" {
            self.pendingPrefix = nil
            self.scrollCursorLine(mode: character)
            return true
        }
        if self.pendingPrefix == "Z" {
            self.pendingPrefix = nil
            if character == "Z" {
                self.saveDocument()
                self.textView?.window?.performClose(nil)
            } else if character == "Q" {
                self.textView?.window?.performClose(nil)
            }
            return true
        }
        
        // Resolve `>>` / `<<`.
        if let prefix = self.pendingPrefix, prefix == ">" || prefix == "<" {
            self.pendingPrefix = nil
            if character == prefix { self.indentLines(outdent: prefix == "<") }
            return true
        }
        
        if state.mode == .visual {
            return self.handleVisual(character: character)
        }
        
        switch character {
            case "h": self.move(.left)
            case "j": self.move(.lineDown)
            case "k": self.move(.lineUp)
            case "l": self.move(.right)
            case "w": self.move(.wordForward)
            case "b": self.move(.wordBackward)
            case "e": self.move(.wordEnd)
            case "W": self.move(.bigWordForward)
            case "B": self.move(.bigWordBackward)
            case "E": self.move(.bigWordEnd)
            case "0": self.move(.lineStart)
            case "^", "_": self.move(.firstNonBlank)
            case "$": self.move(.lineEnd)
            case "+":
                self.move(.lineDown)
                self.move(.firstNonBlank)
            case "-":
                self.move(.lineUp)
                self.move(.firstNonBlank)
            case "{": self.moveParagraph(forward: false)
            case "}": self.moveParagraph(forward: true)
            case "H": self.moveToScreenLine(position: .top)
            case "M": self.moveToScreenLine(position: .middle)
            case "L": self.moveToScreenLine(position: .bottom)
            case "g": self.pendingPrefix = "g"
            case "z": self.pendingPrefix = "z"
            case "Z": self.pendingPrefix = "Z"
            case "G": self.move(.documentEnd)
            case "m", "'", "`":
                self.pendingMarkAction = character
                
            case "f": self.pendingFindKind = .forward
            case "F": self.pendingFindKind = .backward
            case "t": self.pendingFindKind = .tillForward
            case "T": self.pendingFindKind = .tillBackward
            case ";": if let last = self.lastFind { self.performFind(last.kind, character: last.character) }
            case ",": if let last = self.lastFind { self.performFind(Self.reversed(last.kind), character: last.character) }
                
            case "/":
                self.searchBuffer = ""
                VimState.shared.commandLine = "/"
                self.updateStatus()
            case "n": self.findSearch(backward: false)
            case "N": self.findSearch(backward: true)
            case "*": self.searchWordUnderCursor(forward: true)
            case "#": self.searchWordUnderCursor(forward: false)
            case "%": self.jumpToMatchingBracket()
            case "J": self.joinLines()
            case "~": self.toggleCaseUnderCursor(count: self.takeCount())
            case ">": self.pendingPrefix = ">"
            case "<": self.pendingPrefix = "<"
            case ".":
                if let lastReplace = self.lastReplaceChar {
                    self.replaceCharactersUnderCursor(with: lastReplace.character, count: lastReplace.count)
                } else if let lastChange = self.lastChange {
                    self.count = lastChange.count
                    self.apply(lastChange.op, motion: lastChange.motion)
                }
                
            case "r":
                self.pendingReplaceChar = true
                return true
            case "R":
                self.enter(mode: .replace)
                
            case "d", "c", "y":
                self.pendingOperator = OperatorKind(rawValue: character)
                
            case "s":
                let range = self.characterRange(count: self.takeCount())
                self.delete(range)
                self.enter(mode: .insert)
            case "S":
                self.substituteWholeLine()
                
            case "x":
                let range = self.characterRange(count: self.takeCount())
                self.delete(range)
                
            case "X":
                let end = textView.selectedRange().location
                let start = max(0, end - self.takeCount())
                self.delete(NSRange(location: start, length: end - start))
                
            case "D":
                let range = self.toLineEnd(from: textView.selectedRange().location)
                self.delete(range)
                
            case "C":
                let range = self.toLineEnd(from: textView.selectedRange().location)
                self.delete(range)
                self.enter(mode: .insert)
                
            case "Y":
                self.applyLinewiseOperator(.yank)
                
            case "p":
                self.paste(after: true)
            case "P":
                self.paste(after: false)
                
            case "u":
                self.textView?.undoManager?.undo()
            case "U":
                self.textView?.undoManager?.undo()
            case "v":
                let location = textView.selectedRange().location
                self.visualAnchor = location
                self.visualLinewise = false
                VimState.shared.visualActiveLocation = location
                VimState.shared.visualOwnerID = ObjectIdentifier(textView)
                self.enter(mode: .visual)
            case "V":
                let location = textView.selectedRange().location
                let lineRange = self.lineRange(at: location) ?? NSRange(location: location, length: 0)
                self.visualAnchor = lineRange.location
                self.visualLinewise = true
                VimState.shared.visualActiveLocation = max(lineRange.location, NSMaxRange(lineRange) - 1)
                VimState.shared.visualOwnerID = ObjectIdentifier(textView)
                textView.setSelectedRange(lineRange)
                self.enter(mode: .visual)
                
            case "i":
                self.enter(mode: .insert)
            case "a":
                let string = textView.string as NSString
                let loc = textView.selectedRange().location
                let next = (loc < string.length && string.character(at: loc) != 10) ? loc + 1 : loc
                self.setCursor(next)
                self.enter(mode: .insert)
            case "I":
                self.move(.firstNonBlank)
                self.enter(mode: .insert)
            case "A":
                let lineRange = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
                let string = textView.string as NSString
                var end = NSMaxRange(lineRange)
                if end > lineRange.location, string.character(at: end - 1) == 10 { end -= 1 }
                self.setCursor(end)
                self.enter(mode: .insert)
            case "o":
                self.openLine(below: true)
            case "O":
                self.openLine(below: false)
                
            case ":":
                self.commandBuffer = ""
                VimState.shared.commandLine = ""
                self.updateStatus()
            default:
                break
        }
        
        self.count = (self.pendingOperator == nil && !self.pendingReplaceChar) ? nil : self.count
        return true
    }
    
    
    private func handleVisual(character: Character) -> Bool {
        
        guard let textView else { return false }
        if let pendingTextObj = self.pendingTextObject {
            self.pendingTextObject = nil
            if let range = self.textObjectRange(inner: pendingTextObj.inner, character: character), range.length > 0 {
                self.visualAnchor = range.location
                VimState.shared.visualActiveLocation = NSMaxRange(range) - 1
                textView.setSelectedRange(range)
                self.refreshCursor()
            }
            return true
        }
        
        switch character {
            case "h": self.move(.left)
            case "j": self.move(.lineDown)
            case "k": self.move(.lineUp)
            case "l": self.move(.right)
            case "w": self.move(.wordForward)
            case "b": self.move(.wordBackward)
            case "e": self.move(.wordEnd)
            case "W": self.move(.bigWordForward)
            case "B": self.move(.bigWordBackward)
            case "E": self.move(.bigWordEnd)
            case "0": self.move(.lineStart)
            case "^", "_": self.move(.firstNonBlank)
            case "$": self.move(.lineEnd)
            case "{": self.move(.paragraphBackward)
            case "}": self.move(.paragraphForward)
            case "g": self.pendingPrefix = "g"
            case "G": self.move(.documentEnd)
            case "%": self.jumpToMatchingBracket()
            case "i", "a":
                self.pendingTextObject = (.yank, character == "i")
                return true
            case "o", "O":
                if let anchor = self.visualAnchor, let active = VimState.shared.visualActiveLocation {
                    self.visualAnchor = active
                    VimState.shared.visualActiveLocation = anchor
                    self.refreshCursor()
                }
            case "r":
                self.pendingReplaceChar = true
                return true
            case "~":
                self.transformVisualCase(mode: .toggle)
            case "u":
                self.transformVisualCase(mode: .lower)
            case "U":
                self.transformVisualCase(mode: .upper)
            case ">":
                self.indentVisualSelection(outdent: false)
            case "<":
                self.indentVisualSelection(outdent: true)
            case "J":
                self.joinLines()
                self.endVisual()
            case "y", "Y":
                let range = self.visualRange()
                self.register = (textView.string as NSString).substring(with: range)
                self.registerIsLinewise = self.visualLinewise
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.register, forType: .string)
                self.endVisual()
            case "d", "D", "x", "X":
                let range = self.visualRange()
                self.register = (textView.string as NSString).substring(with: range)
                self.registerIsLinewise = self.visualLinewise
                self.delete(range)
                self.endVisual()
            case "c", "C", "s", "S":
                let range = self.visualRange()
                self.register = (textView.string as NSString).substring(with: range)
                self.registerIsLinewise = self.visualLinewise
                self.delete(range)
                self.endVisual()
                self.enter(mode: .insert)
            case "p", "P":
                let range = self.visualRange()
                self.replace(range, with: self.register)
                self.endVisual()
            case "v", "V":
                self.endVisual()
            default:
                break
        }
        self.count = nil
        return true
    }
    
    
    private func handleCommandKey(_ characters: String, event: NSEvent) -> Bool {
        
        let state = VimState.shared
        if self.isEscape(event) {
            self.commandBuffer = nil
            state.commandLine = nil
            self.updateStatus()
            return true
        }
        if event.keyCode == 36 {  // Return
            let command = self.commandBuffer ?? ""
            self.commandBuffer = nil
            state.commandLine = nil
            self.updateStatus()
            self.execute(command: command)
            return true
        }
        if event.keyCode == 51 {  // Delete
            guard let buffer = self.commandBuffer, !buffer.isEmpty else {
                // deleting past the colon leaves command mode
                self.commandBuffer = nil
                state.commandLine = nil
                self.updateStatus()
                return true
            }
            self.commandBuffer = String(buffer.dropLast())
            state.commandLine = ":" + (self.commandBuffer ?? "")
            self.updateStatus()
            return true
        }
        self.commandBuffer?.append(characters)
        state.commandLine = ":" + (self.commandBuffer ?? "")
        return true
    }
    
    
    // MARK: Command line
    
    private func execute(command: String) {
        
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        if let lineNumber = Int(trimmed), lineNumber > 0 {
            self.setCursor(self.lineLocation(number: lineNumber))
            return
        }
        
        if trimmed.hasPrefix("s/") || trimmed.hasPrefix("%s/") {
            self.executeSubstitute(command: trimmed)
            return
        }
        
        let parts = trimmed.split(separator: " ").map(String.init)
        guard let head = parts.first else { return }
        
        switch head {
            case "set":
                for argument in parts.dropFirst() {
                    switch argument {
                        case "number", "nu", "rnu", "relativenumber":
                            self.setShowsLineNumbers(true)
                        case "nonumber", "nonu", "nornu", "norelativenumber":
                            self.setShowsLineNumbers(false)
                        default:
                            break
                    }
                }
            case "w", "w!":
                self.saveDocument()
            case "q", "q!":
                if let window = self.textView?.window { window.performClose(nil) }
            case "wq", "wq!", "x":
                self.saveDocument()
                if let window = self.textView?.window { window.performClose(nil) }
            case "noh", "nohlsearch":
                break
            default:
                break
        }
    }
    
    
    /// Executes `:s/pattern/replacement/[g]` or `:%s/pattern/replacement/[g]`.
    private func executeSubstitute(command: String) {
        
        guard let textView else { return }
        let isGlobalFile = command.hasPrefix("%s/")
        let body = String(command.dropFirst(isGlobalFile ? 3 : 2))
        let segments = body.components(separatedBy: "/")
        guard segments.count >= 2 else { return }
        
        let pattern = segments[0]
        guard !pattern.isEmpty else { return }
        let replacement = segments[1]
        let flags = segments.count >= 3 ? segments[2] : ""
        let replaceAllInLine = flags.contains("g")
        let caseInsensitive = flags.contains("i")
        
        let nsString = textView.string as NSString
        let targetRange: NSRange
        if isGlobalFile {
            targetRange = NSRange(location: 0, length: nsString.length)
        } else {
            targetRange = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
        }
        guard targetRange.length > 0 else { return }
        
        let subText = nsString.substring(with: targetRange)
        let updated: String
        if replaceAllInLine {
            var options: String.CompareOptions = []
            if caseInsensitive { options.insert(.caseInsensitive) }
            updated = subText.replacingOccurrences(of: pattern, with: replacement, options: options)
        } else {
            var options: NSString.CompareOptions = []
            if caseInsensitive { options.insert(.caseInsensitive) }
            let firstRange = (subText as NSString).range(of: pattern, options: options)
            guard firstRange.location != NSNotFound else { return }
            updated = (subText as NSString).replacingCharacters(in: firstRange, with: replacement)
        }
        
        guard updated != subText else { return }
        self.replace(targetRange, with: updated)
    }
    
    
    /// Shows or hides the line numbers of the pane this command runs in.
    ///
    /// The value belongs to the pane (see `EditorViewController.showsLineNumber`), which is what
    /// makes `:set nu` in one pane leave the panes and windows beside it as they are.
    ///
    /// - Parameter shows: Whether line numbers should be visible.
    private func setShowsLineNumbers(_ shows: Bool) {
        
        guard let textView = self.textView else { return }
        
        var responder: NSResponder? = textView
        
        while let current = responder {
            if let documentViewController = current as? DocumentViewController {
                documentViewController.setShowsLineNumber(shows, inPaneContaining: textView)
                return
            }
            responder = current.nextResponder
        }
    }
    
    
    // MARK: Motions
    
    private func motion(for character: Character) -> Motion? {
        
        switch character {
            case "h": .left
            case "l": .right
            case "j": .lineDown
            case "k": .lineUp
            case "w": .wordForward
            case "b": .wordBackward
            case "e": .wordEnd
            case "W": .bigWordForward
            case "B": .bigWordBackward
            case "E": .bigWordEnd
            case "0": .lineStart
            case "^", "_": .firstNonBlank
            case "$": .lineEnd
            case "{": .paragraphBackward
            case "}": .paragraphForward
            case "G": .documentEnd
            default: nil
        }
    }
    
    
    private func move(_ motion: Motion) {
        
        guard let textView else { return }
        let count = self.takeCount()
        let string = textView.string as NSString
        // In visual mode the motion must continue from the active end of the
        // selection, not from its start — otherwise `v` followed by `w` jumps around.
        var location: Int
        if VimState.shared.mode == .visual, let activeLocation = VimState.shared.visualActiveLocation {
            location = activeLocation
        } else {
            location = textView.selectedRange().location
        }
        
        switch motion {
            case .left:
                location = max(0, location - count)
            case .right:
                location = min(string.length, location + count)
            case .down, .lineDown:
                location = self.verticalLocation(from: location, direction: count)
            case .up, .lineUp:
                location = self.verticalLocation(from: location, direction: -count)
            case .wordForward:
                for _ in 0..<count { location = self.forwardWord(from: location, big: false) }
            case .wordBackward:
                for _ in 0..<count { location = self.backwardWord(from: location, big: false) }
            case .wordEnd:
                for _ in 0..<count { location = self.wordEnd(from: location, big: false) }
            case .bigWordForward:
                for _ in 0..<count { location = self.forwardWord(from: location, big: true) }
            case .bigWordBackward:
                for _ in 0..<count { location = self.backwardWord(from: location, big: true) }
            case .bigWordEnd:
                for _ in 0..<count { location = self.wordEnd(from: location, big: true) }
            case .lineStart:
                location = self.lineRange(at: location)?.location ?? 0
            case .firstNonBlank:
                location = self.firstNonBlank(in: self.lineRange(at: location), string: string)
            case .lineEnd:
                if let range = self.lineRange(at: location) {
                    var end = NSMaxRange(range)
                    if end > range.location, string.character(at: end - 1) == 10 {
                        end -= 1
                        if end > range.location, string.character(at: end - 1) == 13 {
                            end -= 1
                        }
                    }
                    location = max(range.location, end - 1)
                } else {
                    location = 0
                }
            case .paragraphBackward:
                for _ in 0..<count { location = self.paragraphLocation(from: location, forward: false, string: string) }
            case .paragraphForward:
                for _ in 0..<count { location = self.paragraphLocation(from: location, forward: true, string: string) }
            case .documentStart:
                location = count > 1 ? self.lineLocation(number: count) : 0
            case .documentEnd:
                if count > 1 {
                    location = self.lineLocation(number: count)
                } else {
                    let range = self.lineRange(at: max(0, string.length - 1))
                    location = self.firstNonBlank(in: range, string: string)
                }
        }
        
        if VimState.shared.mode == .visual, let anchor = self.visualAnchor {
            // Vim's visual selection includes the character under the cursor. Without it
            // the block cursor is drawn one character outside the highlighted range,
            // which reads as a stray highlight below the selection.
            let oldRect = VimState.shared.visualActiveLocation.flatMap { (textView as? EditorTextView)?.vimCursorRect(at: $0) }
            let selectionRange: NSRange
            if self.visualLinewise {
                let anchorLine = self.lineRange(at: anchor) ?? NSRange(location: anchor, length: 0)
                let activeLine = self.lineRange(at: location) ?? NSRange(location: location, length: 0)
                let lower = min(anchorLine.location, activeLine.location)
                let upper = min(max(NSMaxRange(anchorLine), NSMaxRange(activeLine)), string.length)
                selectionRange = NSRange(location: lower, length: max(0, upper - lower))
            } else {
                let lower = min(anchor, location)
                let upper = min(max(anchor, location) + 1, string.length)
                selectionRange = NSRange(location: lower, length: max(0, upper - lower))
            }
            textView.setSelectedRange(selectionRange)
            VimState.shared.visualActiveLocation = location
            VimState.shared.visualOwnerID = ObjectIdentifier(textView)
            self.refreshCursor()
            if let editorTextView = textView as? EditorTextView,
               let newRect = editorTextView.vimCursorRect(at: location)
            {
                editorTextView.funEffects.animateVimCursorTransition(
                    from: oldRect,
                    to: newRect,
                    color: editorTextView.effectiveCursorColor
                )
            }
        } else {
            self.setCursor(location)
        }
        self.count = nil
    }
    
    
    // MARK: Operators
    
    private func operatorKey(_ character: Character) -> OperatorKind? {
        
        OperatorKind(rawValue: character)
    }
    
    
    private func apply(_ op: OperatorKind, motion: Motion) {
        
        guard let textView else { return }
        let count = self.takeCount()
        let start = textView.selectedRange().location
        let string = textView.string as NSString
        
        var end = start
        var linewise = false
        
        switch motion {
            case .left:
                end = max(0, start - count)
            case .right:
                end = min(string.length, start + count)
            case .down, .lineDown:
                end = self.verticalLocation(from: start, direction: count)
                linewise = true
            case .up, .lineUp:
                end = self.verticalLocation(from: start, direction: -count)
                linewise = true
            case .wordForward:
                end = start
                for _ in 0..<count { end = Self.forwardWordLocation(in: string, from: end, big: false, forOperator: true) }
            case .wordBackward:
                end = start
                for _ in 0..<count { end = Self.backwardWordLocation(in: string, from: end, big: false) }
            case .wordEnd:
                end = start
                for _ in 0..<count { end = Self.wordEndLocation(in: string, from: end, big: false) }
                if end < string.length {
                    let seq = string.rangeOfComposedCharacterSequence(at: end)
                    end = NSMaxRange(seq)
                }
            case .bigWordForward:
                end = start
                for _ in 0..<count { end = Self.forwardWordLocation(in: string, from: end, big: true, forOperator: true) }
            case .bigWordBackward:
                end = start
                for _ in 0..<count { end = Self.backwardWordLocation(in: string, from: end, big: true) }
            case .bigWordEnd:
                end = start
                for _ in 0..<count { end = Self.wordEndLocation(in: string, from: end, big: true) }
                if end < string.length {
                    let seq = string.rangeOfComposedCharacterSequence(at: end)
                    end = NSMaxRange(seq)
                }
            case .lineStart:
                end = self.lineRange(at: start)?.location ?? 0
            case .firstNonBlank:
                end = self.firstNonBlank(in: self.lineRange(at: start), string: string)
            case .lineEnd:
                end = NSMaxRange(self.lineRange(at: start) ?? NSRange(location: 0, length: 0))
                if end > 0, string.character(at: end - 1) == 10 { end -= 1 }
            case .paragraphBackward:
                end = start
                for _ in 0..<count { end = self.paragraphLocation(from: end, forward: false, string: string) }
            case .paragraphForward:
                end = start
                for _ in 0..<count { end = self.paragraphLocation(from: end, forward: true, string: string) }
            case .documentStart:
                end = 0
                linewise = true
            case .documentEnd:
                end = string.length
                linewise = true
        }
        
        let range: NSRange
        if linewise {
            let first = self.lineRange(at: min(start, min(end, max(0, string.length - 1)))) ?? NSRange(location: 0, length: 0)
            let second = self.lineRange(at: min(end, max(0, string.length - 1))) ?? first
            range = NSRange(location: first.location,
                            length: max(0, NSMaxRange(second) - first.location))
        } else {
            range = NSRange(location: min(start, end), length: abs(end - start))
        }
        
        guard range.length > 0 else {
            if op == .change { self.enter(mode: .insert) }
            return
        }
        
        switch op {
            case .delete:
                self.register = string.substring(with: range)
                self.registerIsLinewise = linewise
                self.delete(range)
                self.lastChange = (op, motion, count)
                self.lastReplaceChar = nil
            case .change:
                self.register = string.substring(with: range)
                self.registerIsLinewise = linewise
                self.delete(range)
                self.lastChange = (op, motion, count)
                self.lastReplaceChar = nil
                self.enter(mode: .insert)
            case .yank:
                self.register = string.substring(with: range)
                self.registerIsLinewise = linewise
                self.setCursor(range.location)
        }
    }
    
    
    private func applyLinewiseOperator(_ op: OperatorKind) {
        
        guard let textView else { return }
        var range = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
        
        let extra = self.takeCount() - 1
        for _ in 0..<max(0, extra) {
            let next = NSMaxRange(range)
            guard next < (textView.string as NSString).length else { break }
            if let nextRange = self.lineRange(at: next) {
                range = NSRange(location: range.location, length: NSMaxRange(nextRange) - range.location)
            }
        }
        
        switch op {
            case .delete:
                self.delete(range)
            case .change:
                self.delete(range)
                self.enter(mode: .insert)
            case .yank:
                self.register = (textView.string as NSString).substring(with: range)
                self.registerIsLinewise = true
                self.setCursor(range.location)
        }
    }
    
    
    // MARK: Editing
    
    private func delete(_ range: NSRange) {
        
        guard let textView, range.length > 0 else { return }
        guard textView.shouldChangeText(in: range, replacementString: "") else { return }
        textView.textStorage?.replaceCharacters(in: range, with: "")
        textView.didChangeText()
        self.setCursor(min(range.location, (textView.string as NSString).length))
    }
    
    
    private func paste(after: Bool) {
        
        guard let textView, !self.register.isEmpty else { return }
        let string = textView.string as NSString
        var insertAt = textView.selectedRange().location
        
        if self.registerIsLinewise {
            if after {
                let lineRange = self.lineRange(at: insertAt) ?? NSRange(location: 0, length: 0)
                insertAt = NSMaxRange(lineRange)
            } else {
                insertAt = self.lineRange(at: insertAt)?.location ?? 0
            }
        } else if after {
            insertAt = min(string.length, insertAt + 1)
        }
        
        let text = self.registerIsLinewise ? self.register + "\n" : self.register
        let range = NSRange(location: insertAt, length: 0)
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        self.setCursor(range.location)
    }
    
    
    private func openLine(below: Bool) {
        
        guard let textView else { return }
        let nsString = textView.string as NSString
        let caret = textView.selectedRange().location
        let lineRange = self.lineRange(at: caret) ?? NSRange(location: 0, length: 0)
        let newline = (textView as? EditorTextView)?.lineEnding.string ?? "\n"
        let newlineLen = (newline as NSString).length
        
        if below {
            var lineEnd = NSMaxRange(lineRange)
            if lineEnd > lineRange.location, nsString.character(at: lineEnd - 1) == 10 {
                lineEnd -= 1
                if lineEnd > lineRange.location, nsString.character(at: lineEnd - 1) == 13 {
                    lineEnd -= 1
                }
            }
            let range = NSRange(location: lineEnd, length: 0)
            guard textView.shouldChangeText(in: range, replacementString: newline) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: newline)
            textView.didChangeText()
            self.setCursor(lineEnd + newlineLen)
            self.enter(mode: .insert)
        } else {
            let insertAt = lineRange.location
            let range = NSRange(location: insertAt, length: 0)
            guard textView.shouldChangeText(in: range, replacementString: newline) else { return }
            textView.textStorage?.replaceCharacters(in: range, with: newline)
            textView.didChangeText()
            self.setCursor(insertAt)
            self.enter(mode: .insert)
        }
    }
    
    
    // MARK: f / t, text objects, search
    
    private static func reversed(_ kind: FindKind) -> FindKind {
        
        switch kind {
            case .forward: .backward
            case .backward: .forward
            case .tillForward: .tillBackward
            case .tillBackward: .tillForward
        }
    }
    
    
    /// Moves to the next/previous occurrence of a character (`f F t T`).
    private func performFind(_ kind: FindKind, character: Character) {
        
        guard let textView, let target = character.utf16.first else { return }
        let string = textView.string as NSString
        guard string.length > 0 else { return }
        
        let count = self.takeCount()
        var location = textView.selectedRange().location
        
        for _ in 0..<count {
            switch kind {
                case .forward, .tillForward:
                    var index = location + 1
                    var found = -1
                    while index < string.length {
                        if string.character(at: index) == target { found = index; break }
                        index += 1
                    }
                    guard found >= 0 else { self.count = nil; return }
                    location = kind == .tillForward ? max(0, found - 1) : found
                case .backward, .tillBackward:
                    var index = location - 1
                    var found = -1
                    while index >= 0 {
                        if string.character(at: index) == target { found = index; break }
                        index -= 1
                    }
                    guard found >= 0 else { self.count = nil; return }
                    location = kind == .tillBackward ? min(string.length - 1, found + 1) : found
            }
        }
        
        self.setCursor(location)
        self.count = nil
    }
    
    
    /// Resolves `iw`, `aw`, `i"`, `a(`, … to a range.
    private func textObjectRange(inner: Bool, character: Character) -> NSRange? {
        
        guard let textView else { return nil }
        let string = textView.string as NSString
        guard string.length > 0 else { return nil }
        let caret = textView.selectedRange().location
        
        switch character {
            case "w", "W":
                return self.wordTextObject(inner: inner, at: caret, string: string)
            case "p":
                return self.paragraphTextObject(inner: inner, at: caret, string: string)
            case "\"", "'", "`":
                return self.quoteTextObject(quote: character, inner: inner, at: caret, string: string)
            case "(", ")", "b":
                return self.bracketTextObject(open: "(", close: ")", inner: inner, at: caret, string: string)
            case "[", "]":
                return self.bracketTextObject(open: "[", close: "]", inner: inner, at: caret, string: string)
            case "{", "}", "B":
                return self.bracketTextObject(open: "{", close: "}", inner: inner, at: caret, string: string)
            case "<", ">":
                return self.bracketTextObject(open: "<", close: ">", inner: inner, at: caret, string: string)
            default:
                return nil
        }
    }
    
    
    private func paragraphTextObject(inner: Bool, at caret: Int, string: NSString) -> NSRange? {
        
        guard string.length > 0 else { return nil }
        let currentLine = self.lineRange(at: min(caret, string.length - 1)) ?? NSRange(location: 0, length: 0)
        var start = currentLine.location
        while start > 0 {
            let prevLine = self.lineRange(at: start - 1) ?? NSRange(location: 0, length: 0)
            if self.isBlankLine(prevLine, string: string) { break }
            start = prevLine.location
        }
        
        var end = NSMaxRange(currentLine)
        while end < string.length {
            let nextLine = self.lineRange(at: end) ?? NSRange(location: end, length: 0)
            if self.isBlankLine(nextLine, string: string) {
                if !inner {
                    end = NSMaxRange(nextLine)
                }
                break
            }
            end = NSMaxRange(nextLine)
        }
        return NSRange(location: start, length: max(0, end - start))
    }
    
    
    private func wordTextObject(inner: Bool, at caret: Int, string: NSString) -> NSRange? {
        
        guard string.length > 0 else { return nil }
        let lineRange = string.lineRange(for: NSRange(location: min(max(0, caret), string.length), length: 0))
        let contentRange = Self.lineContentRange(in: string, lineRange: lineRange)
        let tokens = Self.vimTokens(in: string, range: contentRange, big: false)
        guard !tokens.isEmpty else { return nil }
        
        let targetToken = tokens.first(where: { caret >= $0.location && caret < NSMaxRange($0) })
            ?? tokens.first(where: { $0.location >= caret })
            ?? tokens.last
        guard let token = targetToken else { return nil }
        
        guard !inner else { return token }
        
        var trailing = NSMaxRange(token)
        while trailing < NSMaxRange(contentRange), Self.isHorizontalWhitespace(string.character(at: trailing)) {
            trailing += 1
        }
        return NSRange(location: token.location, length: trailing - token.location)
    }
    
    
    private func quoteTextObject(quote: Character, inner: Bool, at caret: Int, string: NSString) -> NSRange? {
        
        guard let unit = quote.utf16.first else { return nil }
        let lineRange = self.lineRange(at: min(caret, string.length - 1)) ?? NSRange(location: 0, length: 0)
        
        var positions: [Int] = []
        var index = lineRange.location
        while index < NSMaxRange(lineRange) {
            if string.character(at: index) == unit { positions.append(index) }
            index += 1
        }
        
        var openIndex: Int?
        var positionIndex = 0
        while positionIndex + 1 < positions.count {
            if caret >= positions[positionIndex], caret <= positions[positionIndex + 1] {
                openIndex = positions[positionIndex]
                break
            }
            positionIndex += 2
        }
        
        if openIndex == nil {
            positionIndex = 0
            while positionIndex + 1 < positions.count {
                if positions[positionIndex] > caret {
                    openIndex = positions[positionIndex]
                    break
                }
                positionIndex += 2
            }
        }
        
        guard let open = openIndex, let close = positions[safe: (positions.firstIndex(of: open) ?? 0) + 1] else { return nil }
        
        return inner
            ? NSRange(location: open + 1, length: max(0, close - open - 1))
            : NSRange(location: open, length: close - open + 1)
    }
    
    
    private func bracketTextObject(open: Character, close: Character, inner: Bool, at caret: Int, string: NSString) -> NSRange? {
        
        guard let openUnit = open.utf16.first, let closeUnit = close.utf16.first else { return nil }
        
        var depth = 0
        var openIndex: Int?
        var index = min(caret, string.length - 1)
        while index >= 0 {
            let character = string.character(at: index)
            if character == closeUnit { depth += 1 }
            if character == openUnit {
                if depth == 0 { openIndex = index; break }
                depth -= 1
            }
            index -= 1
        }
        guard let openIndex else { return nil }
        
        depth = 0
        var closeIndex: Int?
        index = openIndex + 1
        while index < string.length {
            let character = string.character(at: index)
            if character == openUnit { depth += 1 }
            if character == closeUnit {
                if depth == 0 { closeIndex = index; break }
                depth -= 1
            }
            index += 1
        }
        guard let closeIndex else { return nil }
        
        return inner
            ? NSRange(location: openIndex + 1, length: max(0, closeIndex - openIndex - 1))
            : NSRange(location: openIndex, length: closeIndex - openIndex + 1)
    }
    
    
    /// Applies an operator to an explicit range (used by text objects).
    private func apply(_ op: OperatorKind, range: NSRange) {
        
        guard let textView else { return }
        guard range.length > 0 else {
            if op == .change { self.enter(mode: .insert) }
            return
        }
        
        switch op {
            case .delete:
                self.delete(range)
            case .change:
                self.delete(range)
                self.enter(mode: .insert)
            case .yank:
                self.register = (textView.string as NSString).substring(with: range)
                self.registerIsLinewise = false
                self.setCursor(range.location)
        }
    }
    
    
    private func isWordSeparator(_ character: unichar) -> Bool {
        
        character == 32 || character == 9 || character == 10 || character == 13
    }
    
    
    // MARK: Search
    
    private func handleSearchKey(_ characters: String, event: NSEvent) -> Bool {
        
        let state = VimState.shared
        
        if self.isEscape(event) {
            self.searchBuffer = nil
            state.commandLine = nil
            self.updateStatus()
            return true
        }
        if event.keyCode == 36 {  // Return
            let query = self.searchBuffer ?? ""
            self.searchBuffer = nil
            state.commandLine = nil
            self.updateStatus()
            if !query.isEmpty {
                self.lastSearch = query
                self.findSearch(backward: false)
            }
            return true
        }
        if event.keyCode == 51 {  // Delete
            guard let buffer = self.searchBuffer, !buffer.isEmpty else {
                self.searchBuffer = nil
                state.commandLine = nil
                self.updateStatus()
                return true
            }
            self.searchBuffer = String(buffer.dropLast())
            state.commandLine = "/" + (self.searchBuffer ?? "")
            self.updateStatus()
            return true
        }
        
        self.searchBuffer?.append(characters)
        state.commandLine = "/" + (self.searchBuffer ?? "")
        self.updateStatus()
        
        return true
    }
    
    
    /// Finds the next/previous occurrence of the last search pattern.
    private func findSearch(backward: Bool) {
        
        guard let query = self.lastSearch, !query.isEmpty, let textView else { return }
        let string = textView.string as NSString
        guard string.length > 0 else { return }
        
        let caret = textView.selectedRange().location
        var found = NSRange(location: NSNotFound, length: 0)
        
        if backward {
            found = string.range(of: query, options: [.backwards],
                                 range: NSRange(location: 0, length: min(caret, string.length)))
            if found.location == NSNotFound {
                found = string.range(of: query, options: [.backwards],
                                     range: NSRange(location: 0, length: string.length))
            }
        } else {
            let start = min(caret + 1, string.length)
            found = string.range(of: query, range: NSRange(location: start, length: string.length - start))
            if found.location == NSNotFound {
                found = string.range(of: query, range: NSRange(location: 0, length: string.length))
            }
        }
        
        guard found.location != NSNotFound else { return }
        self.setCursor(found.location)
    }
    
    
    // MARK: Practical extras
    
    /// Handles keystrokes while in `.replace` (`R`) mode: printable characters overwrite in-place.
    private func handleReplaceModeKey(_ event: NSEvent) -> Bool {
        
        guard let textView else { return false }
        switch event.keyCode {
            case 123, 124, 125, 126:  // Arrow keys
                return false
            case 51:  // Backspace moves cursor left in Replace mode
                let current = textView.selectedRange().location
                if current > 0 {
                    self.setCursor(current - 1)
                }
                return true
            case 36:  // Return inserts a newline
                return false
            default:
                break
        }
        
        guard let characters = event.characters, !characters.isEmpty else { return false }
        let nsString = textView.string as NSString
        var cursor = textView.selectedRange().location
        
        for character in characters {
            let charString = String(character)
            if cursor < nsString.length, (textView.string as NSString).character(at: cursor) != 10 {
                self.replace(NSRange(location: cursor, length: 1), with: charString)
            } else {
                self.replace(NSRange(location: cursor, length: 0), with: charString)
            }
            cursor += (charString as NSString).length
        }
        self.setCursor(cursor)
        return true
    }
    
    
    /// `r<char>`: replaces `count` characters starting at the cursor on the current line with `character`.
    private func replaceCharactersUnderCursor(with character: Character, count: Int) {
        
        guard let textView else { return }
        let nsString = textView.string as NSString
        let cursor = textView.selectedRange().location
        guard cursor < nsString.length else { return }
        
        if character == "\r" || character == "\n" {
            let replaceLen = min(count, max(1, nsString.length - cursor))
            self.replace(NSRange(location: cursor, length: replaceLen), with: "\n")
            let nextLoc = self.firstNonBlank(in: self.lineRange(at: cursor + 1), string: textView.string as NSString)
            self.setCursor(nextLoc)
            return
        }
        
        guard let lineRange = self.lineRange(at: cursor) else { return }
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineRange.location, nsString.character(at: lineEnd - 1) == 10 {
            lineEnd -= 1
        }
        let available = lineEnd - cursor
        guard available >= count, count > 0 else { return }
        
        let replacement = String(repeating: String(character), count: count)
        let targetRange = NSRange(location: cursor, length: count)
        self.replace(targetRange, with: replacement)
        let finalOffset = cursor + max(0, (replacement as NSString).length - (String(character) as NSString).length)
        self.setCursor(finalOffset)
    }
    
    
    /// Visual `r<char>`: replaces every non-newline character in the visual selection with `character`.
    private func replaceVisualSelection(with character: Character) {
        
        guard let textView else { return }
        let range = self.visualRange()
        guard range.length > 0 else {
            self.endVisual()
            return
        }
        let selected = (textView.string as NSString).substring(with: range)
        let transformed = String(selected.map { existing in
            (existing == "\n" || existing == "\r") ? existing : character
        })
        self.replace(range, with: transformed)
        self.endVisual()
        self.setCursor(range.location)
    }
    
    
    /// `S`: deletes the contents of the current line (preserving indentation) and enters insert mode.
    private func substituteWholeLine() {
        
        guard let textView else { return }
        let nsString = textView.string as NSString
        guard let lineRange = self.lineRange(at: textView.selectedRange().location) else {
            self.enter(mode: .insert)
            return
        }
        let nonBlankStart = self.firstNonBlank(in: lineRange, string: nsString)
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineRange.location, nsString.character(at: lineEnd - 1) == 10 {
            lineEnd -= 1
        }
        let targetRange = NSRange(location: nonBlankStart, length: max(0, lineEnd - nonBlankStart))
        if targetRange.length > 0 {
            self.register = nsString.substring(with: targetRange)
            self.registerIsLinewise = false
            self.delete(targetRange)
        } else {
            self.setCursor(nonBlankStart)
        }
        self.enter(mode: .insert)
    }
    
    
    /// `~`: toggles the case of `count` characters starting at the cursor and advances the cursor.
    private func toggleCaseUnderCursor(count: Int) {
        
        guard let textView else { return }
        let nsString = textView.string as NSString
        let cursor = textView.selectedRange().location
        guard cursor < nsString.length else { return }
        
        guard let lineRange = self.lineRange(at: cursor) else { return }
        var lineEnd = NSMaxRange(lineRange)
        if lineEnd > lineRange.location, nsString.character(at: lineEnd - 1) == 10 {
            lineEnd -= 1
        }
        let length = min(count, max(0, lineEnd - cursor))
        guard length > 0 else { return }
        
        let range = NSRange(location: cursor, length: length)
        let original = nsString.substring(with: range)
        let toggled = Self.transformCase(original, mode: .toggle)
        self.replace(range, with: toggled)
        let nextCursor = min(max(lineRange.location, lineEnd - 1), cursor + length)
        self.setCursor(nextCursor)
    }
    
    
    /// Visual `~`, `u`, `U`: transforms the case of the visual selection.
    private func transformVisualCase(mode: CaseTransformMode) {
        
        guard let textView else { return }
        let range = self.visualRange()
        guard range.length > 0 else {
            self.endVisual()
            return
        }
        let original = (textView.string as NSString).substring(with: range)
        let transformed = Self.transformCase(original, mode: mode)
        self.replace(range, with: transformed)
        self.endVisual()
        self.setCursor(range.location)
    }
    
    
    private static func transformCase(_ text: String, mode: CaseTransformMode) -> String {
        
        switch mode {
            case .lower:
                return text.lowercased()
            case .upper:
                return text.uppercased()
            case .toggle:
                return String(text.map { char in
                    let str = String(char)
                    let upper = str.uppercased()
                    let lower = str.lowercased()
                    if str == upper && str != lower {
                        return Character(lower)
                    } else if str == lower && str != upper {
                        return Character(upper)
                    }
                    return char
                })
        }
    }
    
    
    /// Visual `>` / `<`: indents or outdents all lines covered by the visual selection.
    private func indentVisualSelection(outdent: Bool) {
        
        guard let textView else { return }
        let range = self.visualRange()
        let nsString = textView.string as NSString
        guard range.length > 0, nsString.length > 0 else {
            self.endVisual()
            return
        }
        let fullLineRange = nsString.lineRange(for: range)
        let block = nsString.substring(with: fullLineRange)
        let lines = block.components(separatedBy: "\n")
        
        let transformedLines = lines.enumerated().map { idx, line -> String in
            if idx == lines.count - 1 && line.isEmpty { return line }
            if outdent {
                var dropCount = 0
                for char in line {
                    if char == " " && dropCount < 4 {
                        dropCount += 1
                    } else if char == "\t" && dropCount == 0 {
                        dropCount = 1
                        break
                    } else {
                        break
                    }
                }
                return String(line.dropFirst(dropCount))
            } else {
                return line.isEmpty ? line : "    " + line
            }
        }
        let replacement = transformedLines.joined(separator: "\n")
        self.replace(fullLineRange, with: replacement)
        self.endVisual()
        let newCaret = self.firstNonBlank(in: self.lineRange(at: fullLineRange.location), string: textView.string as NSString)
        self.setCursor(newCaret)
    }
    
    
    /// Half-page jump used by ⌃D / ⌃U.
    private func moveHalfPage(down: Bool) {
        
        guard let textView else { return }
        let lineHeight = max(1, (textView.font?.pointSize ?? 13) * 1.3)
        let lines = max(1, Int(textView.visibleRect.height / lineHeight / 2))
        let string = textView.string as NSString
        let location = self.verticalLocation(from: textView.selectedRange().location,
                                             direction: down ? lines : -lines)
        let clamped = max(0, min(location, string.length))
        
        self.setCursor(clamped)
        textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }
    
    
    /// Full-page jump used by ⌃F / ⌃B.
    private func moveFullPage(down: Bool) {
        
        guard let textView else { return }
        let lineHeight = max(1, (textView.font?.pointSize ?? 13) * 1.3)
        let lines = max(1, Int(textView.visibleRect.height / lineHeight) - 2)
        let string = textView.string as NSString
        let location = self.verticalLocation(from: textView.selectedRange().location,
                                             direction: down ? lines : -lines)
        let clamped = max(0, min(location, string.length))
        
        self.setCursor(clamped)
        textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }
    
    
    /// `{` / `}`: jumps to the previous or next blank-line paragraph boundary.
    private func moveParagraph(forward: Bool) {
        
        guard let textView else { return }
        let count = self.takeCount()
        let nsString = textView.string as NSString
        var location = textView.selectedRange().location
        for _ in 0..<count {
            location = self.paragraphLocation(from: location, forward: forward, string: nsString)
        }
        self.setCursor(location)
    }
    
    
    private func paragraphLocation(from location: Int, forward: Bool, string: NSString) -> Int {
        
        guard string.length > 0 else { return 0 }
        var current = min(max(0, location), string.length - 1)
        if forward {
            var lineRange = self.lineRange(at: current) ?? NSRange(location: current, length: 0)
            // Skip any initial blank lines
            while NSMaxRange(lineRange) < string.length, self.isBlankLine(lineRange, string: string) {
                current = NSMaxRange(lineRange)
                lineRange = self.lineRange(at: current) ?? NSRange(location: current, length: 0)
            }
            // Advance until the next blank line or end of document
            while NSMaxRange(lineRange) < string.length {
                current = NSMaxRange(lineRange)
                lineRange = self.lineRange(at: current) ?? NSRange(location: current, length: 0)
                if self.isBlankLine(lineRange, string: string) {
                    return lineRange.location
                }
            }
            return string.length
        } else {
            var lineRange = self.lineRange(at: current) ?? NSRange(location: current, length: 0)
            if lineRange.location == 0 { return 0 }
            current = max(0, lineRange.location - 1)
            lineRange = self.lineRange(at: current) ?? NSRange(location: current, length: 0)
            while lineRange.location > 0, self.isBlankLine(lineRange, string: string) {
                current = lineRange.location - 1
                lineRange = self.lineRange(at: current) ?? NSRange(location: current, length: 0)
            }
            while lineRange.location > 0 {
                let prev = lineRange.location - 1
                let prevRange = self.lineRange(at: prev) ?? NSRange(location: prev, length: 0)
                if self.isBlankLine(prevRange, string: string) {
                    return prevRange.location
                }
                lineRange = prevRange
            }
            return 0
        }
    }
    
    
    private func isBlankLine(_ range: NSRange, string: NSString) -> Bool {
        
        var idx = range.location
        let end = NSMaxRange(range)
        while idx < end {
            let char = string.character(at: idx)
            if char != 32 && char != 9 && char != 10 && char != 13 {
                return false
            }
            idx += 1
        }
        return true
    }
    
    
    /// `H`, `M`, `L`: jumps to the top, middle, or bottom visible line on screen.
    private func moveToScreenLine(position: ScreenLinePosition) {
        
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin
        let targetY: CGFloat
        switch position {
            case .top:
                targetY = visible.minY + 8 - origin.y
            case .middle:
                targetY = visible.midY - origin.y
            case .bottom:
                targetY = max(visible.minY, visible.maxY - 20) - origin.y
        }
        let point = NSPoint(x: max(0, visible.minX - origin.x + 4), y: max(0, targetY))
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let nsString = textView.string as NSString
        let target = self.firstNonBlank(in: self.lineRange(at: charIndex), string: nsString)
        self.setCursor(target)
    }
    
    
    /// `zz`, `zt`, `zb`: scrolls the viewport so the cursor line is centered, at top, or at bottom.
    private func scrollCursorLine(mode: Character) {
        
        guard let textView,
              let scrollView = textView.enclosingScrollView,
              let editorTextView = textView as? EditorTextView,
              let cursorRect = editorTextView.vimCursorRect(at: textView.selectedRange().location)
        else { return }
        
        let visibleHeight = scrollView.contentView.bounds.height
        let targetOriginY: CGFloat
        switch mode {
            case "z", ".":
                targetOriginY = max(0, cursorRect.midY - visibleHeight / 2)
            case "t":
                targetOriginY = max(0, cursorRect.minY - 8)
            case "b":
                targetOriginY = max(0, cursorRect.maxY - visibleHeight + 8)
            default:
                return
        }
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: targetOriginY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    
    /// `ge` / `gE`: moves backward to the end of the previous word.
    private func moveBackwardWordEnd(big: Bool) {
        
        guard let textView else { return }
        let count = self.takeCount()
        let string = textView.string as NSString
        guard string.length > 0 else { return }
        var index = textView.selectedRange().location
        
        for _ in 0..<count {
            guard index > 0 else { break }
            let loc = min(max(0, index), string.length)
            let currentLine = string.lineRange(for: NSRange(location: loc, length: 0))
            let contentRange = Self.lineContentRange(in: string, lineRange: currentLine)
            let tokens = Self.vimTokens(in: string, range: contentRange, big: big)
            
            if let currentToken = tokens.first(where: { loc > $0.location && loc < NSMaxRange($0) }) {
                if let prev = tokens.last(where: { NSMaxRange($0) <= currentToken.location }) {
                    index = string.rangeOfComposedCharacterSequence(at: NSMaxRange(prev) - 1).location
                    continue
                }
            } else if let prev = tokens.last(where: { NSMaxRange($0) <= loc }) {
                index = string.rangeOfComposedCharacterSequence(at: NSMaxRange(prev) - 1).location
                continue
            }
            
            var searchPos = currentLine.location - 1
            var found = 0
            while searchPos >= 0 {
                let prevLine = string.lineRange(for: NSRange(location: searchPos, length: 0))
                let prevContent = Self.lineContentRange(in: string, lineRange: prevLine)
                let prevTokens = Self.vimTokens(in: string, range: prevContent, big: big)
                if let last = prevTokens.last {
                    found = string.rangeOfComposedCharacterSequence(at: NSMaxRange(last) - 1).location
                    break
                }
                searchPos = prevLine.location - 1
            }
            index = found
        }
        self.setCursor(index)
    }
    
    
    /// `g_`: moves to the last non-blank character on the current line.
    private func moveLastNonBlankOfLine() {
        
        guard let textView else { return }
        let nsString = textView.string as NSString
        guard let lineRange = self.lineRange(at: textView.selectedRange().location) else { return }
        var index = NSMaxRange(lineRange) - 1
        while index > lineRange.location {
            let char = nsString.character(at: index)
            if char != 32 && char != 9 && char != 10 && char != 13 {
                break
            }
            index -= 1
        }
        self.setCursor(max(lineRange.location, index))
    }
    
    
    /// `*` / `#`: searches for the word under the caret.
    private func searchWordUnderCursor(forward: Bool) {
        
        guard let textView else { return }
        let string = textView.string as NSString
        guard string.length > 0 else { return }
        
        let caret = min(textView.selectedRange().location, string.length - 1)
        var start = caret
        while start > 0, !self.isWordSeparator(string.character(at: start - 1)) { start -= 1 }
        var end = caret
        while end < string.length, !self.isWordSeparator(string.character(at: end)) { end += 1 }
        guard end > start else { return }
        
        self.lastSearch = string.substring(with: NSRange(location: start, length: end - start))
        self.findSearch(backward: !forward)
    }
    
    
    /// `%`: jumps to the matching bracket.
    private func jumpToMatchingBracket() {
        
        guard let textView else { return }
        let string = textView.string as NSString
        guard string.length > 0 else { return }
        
        let opens: Set<unichar> = [40, 91, 123]   // ( [ {
        let lineRange = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
        let caret = min(textView.selectedRange().location, string.length - 1)
        
        var start: Int?
        var index = caret
        while index < NSMaxRange(lineRange) {
            let character = string.character(at: index)
            if opens.contains(character) || [41, 93, 125].contains(character) { start = index; break }
            index += 1
        }
        if start == nil {
            index = caret - 1
            while index >= lineRange.location {
                let character = string.character(at: index)
                if opens.contains(character) || [41, 93, 125].contains(character) { start = index; break }
                index -= 1
            }
        }
        guard let start else { return }
        
        let pairs: [unichar: unichar] = [40: 41, 91: 93, 123: 125, 41: 40, 93: 91, 125: 123]
        let character = string.character(at: start)
        guard let mate = pairs[character] else { return }
        let forward = opens.contains(character)
        
        var depth = 0
        var cursor = start
        while cursor >= 0, cursor < string.length {
            let current = string.character(at: cursor)
            if current == character {
                depth += 1
            } else if current == mate {
                depth -= 1
                if depth == 0 { self.setCursor(cursor); return }
            }
            cursor += forward ? 1 : -1
        }
    }
    
    
    /// `J`: joins the current line with the next one.
    private func joinLines() {
        
        guard let textView else { return }
        let string = textView.string as NSString
        let lineRange = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
        let end = NSMaxRange(lineRange)
        guard end < string.length, string.character(at: max(0, end - 1)) == 10 else { return }
        
        var next = end
        while next < string.length,
              string.character(at: next) == 32 || string.character(at: next) == 9
        {
            next += 1
        }
        
        let range = NSRange(location: end - 1, length: next - (end - 1))
        self.replace(range, with: " ")
        self.setCursor(end - 1)
    }
    
    
    /// `>>` / `<<`: shifts the current line by one indent level.
    private func indentLines(outdent: Bool) {
        
        guard let textView else { return }
        let string = textView.string as NSString
        let lineRange = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
        
        if outdent {
            var index = lineRange.location
            var removed = 0
            while index < NSMaxRange(lineRange), removed < 4 {
                let character = string.character(at: index)
                if character == 32 {
                    index += 1
                    removed += 1
                } else if character == 9 {
                    index += 1
                    removed = 4
                } else {
                    break
                }
            }
            guard removed > 0 else { return }
            self.replace(NSRange(location: lineRange.location, length: removed), with: "")
        } else {
            self.replace(NSRange(location: lineRange.location, length: 0), with: "    ")
        }
    }
    
    
    private func replace(_ range: NSRange, with string: String) {
        
        guard let textView, textView.shouldChangeText(in: range, replacementString: string) else { return }
        
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }
    
    
    /// The caret location of the given 1-based line number.
    private func lineLocation(number: Int) -> Int {
        
        guard let textView else { return 0 }
        let string = textView.string as NSString
        var index = 0
        var line = 1
        while line < number, index < string.length {
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            line += 1
        }
        
        return min(index, max(0, string.length - 1))
    }
    
    
    // MARK: Helpers
    
    private func saveDocument() {
        
        if let textView = self.textView,
           let doc = NSDocumentController.shared.documents
            .compactMap({ $0 as? Document })
            .first(where: { $0.textStorage === textView.textStorage })
        {
            doc.performQuickSave(nil)
        } else if let doc = self.textView?.window?.windowController?.document as? Document {
            doc.performQuickSave(nil)
        } else {
            (self.textView?.window?.windowController?.document as? NSDocument)?.save(nil)
        }
    }
    
    
    private func enter(mode: VimMode) {
        
        VimState.shared.mode = mode
        if mode != .visual {
            self.visualAnchor = nil
            self.visualLinewise = false
            VimState.shared.visualActiveLocation = nil
            VimState.shared.visualOwnerID = nil
        }
        self.resetPending(keepCount: false)
        self.refreshCursor()
        self.updateStatus()
    }
    
    
    /// Clears visual mode cleanly when focus moves out of the owning text view.
    func clearVisualSelectionIfNeeded() {
        
        guard let textView else { return }
        if VimState.shared.visualOwnerID == ObjectIdentifier(textView), VimState.shared.mode == .visual {
            self.endVisual()
        }
    }
    
    
    /// Redraws/syncs the caret so the block cursor appears/disappears cleanly with the mode.
    private func refreshCursor() {
        
        if let editorTextView = self.textView as? EditorTextView {
            if VimState.shared.mode == .insert {
                editorTextView.funEffects.hideVimCursorOnly()
                editorTextView.updateInsertionPointStateAndRestartTimer(true)
            } else if editorTextView.funEffects.ownsVimCursorDrawing {
                editorTextView.funEffects.syncVimCursor(animated: true)
            } else {
                editorTextView.updateInsertionPointStateAndRestartTimer(true)
                editorTextView.setNeedsDisplay(editorTextView.visibleRect)
            }
        } else {
            self.textView?.updateInsertionPointStateAndRestartTimer(true)
            self.textView?.setNeedsDisplay(self.textView?.visibleRect ?? .zero)
        }
    }
    
    
    /// Publishes the current mode immediately, e.g. when a document window appears.
    func publishStatus() {
        
        self.lastStatus = nil
        self.updateStatus()
    }
    
    
    /// Shows the current mode (or the `:` command being typed) in the window subtitle,
    /// so it is always obvious which mode the editor is in.
    private func updateStatus() {
        
        guard let window = self.textView?.window else { return }
        let state = VimState.shared
        let text = state.commandLine ?? state.mode.label
        guard text != self.lastStatus else { return }
        
        self.lastStatus = text
        window.subtitle = text
    }
    
    
    private func endVisual() {
        
        self.visualAnchor = nil
        self.visualLinewise = false
        VimState.shared.visualActiveLocation = nil
        VimState.shared.visualOwnerID = nil
        self.enter(mode: .normal)
    }
    
    
    private func resetPending(keepCount: Bool = false) {
        
        self.pendingOperator = nil
        self.pendingPrefix = nil
        self.pendingReplaceChar = false
        self.pendingMarkAction = nil
        self.pendingFindKind = nil
        self.pendingTextObject = nil
        if !keepCount { self.count = nil }
    }
    
    
    private func swallowPending() -> Bool {
        
        self.resetPending()
        return true
    }
    
    
    private func takeCount() -> Int {
        
        let count = max(1, self.count ?? 1)
        self.count = nil
        return count
    }
    
    
    private func setCursor(_ location: Int) {
        
        guard let textView else { return }
        let oldLocation = textView.selectedRange().location
        let oldRect = (textView as? EditorTextView)?.vimCursorRect(at: oldLocation)
        let length = (textView.string as NSString).length
        let clamped = max(0, min(location, length))
        let targetRange = NSRange(location: clamped, length: 0)
        textView.setSelectedRange(targetRange)
        
        if let editorTextView = textView as? EditorTextView {
            if let probeRect = editorTextView.vimCursorRect(at: clamped) {
                let comfortableVisible = editorTextView.visibleRect.insetBy(dx: 0, dy: min(24, editorTextView.visibleRect.height * 0.15))
                if !comfortableVisible.contains(probeRect) {
                    editorTextView.scrollRangeToVisible(targetRange)
                }
            } else {
                editorTextView.scrollRangeToVisible(targetRange)
            }
            if let newRect = editorTextView.vimCursorRect(at: clamped) {
                editorTextView.funEffects.animateVimCursorTransition(
                    from: oldRect,
                    to: newRect,
                    color: editorTextView.effectiveCursorColor
                )
            }
        } else {
            textView.scrollRangeToVisible(targetRange)
        }
    }
    
    
    private func lineRange(at location: Int) -> NSRange? {
        
        guard let textView else { return nil }
        let string = textView.string as NSString
        guard string.length > 0 else { return NSRange(location: 0, length: 0) }
        return string.lineRange(for: NSRange(location: min(max(0, location), string.length), length: 0))
    }
    
    
    private func firstNonBlank(in range: NSRange?, string: NSString) -> Int {
        
        guard let range else { return 0 }
        var location = range.location
        var end = NSMaxRange(range)
        if end > range.location, string.character(at: end - 1) == 10 {
            end -= 1
            if end > range.location, string.character(at: end - 1) == 13 {
                end -= 1
            }
        }
        while location < end {
            let character = string.character(at: location)
            if character != 32 && character != 9 { break }
            location += 1
        }
        return min(location, max(range.location, end - 1))
    }
    
    
    private func verticalLocation(from location: Int, direction: Int) -> Int {
        
        guard let textView else { return location }
        let string = textView.string as NSString
        guard direction != 0 else { return location }
        
        let currentLine = self.lineRange(at: location) ?? NSRange(location: 0, length: 0)
        let column = location - currentLine.location
        
        var target = currentLine
        for _ in 0..<abs(direction) {
            let next: Int = direction > 0 ? NSMaxRange(target) : target.location - 1
            guard next >= 0, next <= string.length else { return location }
            if direction > 0, next == string.length {
                let endsWithNewline = target.length > 0 && string.character(at: target.location + target.length - 1) == 10
                if !endsWithNewline { return location }
            }
            target = self.lineRange(at: next) ?? target
        }
        
        var contentLength = target.length
        if contentLength > 0, string.character(at: target.location + contentLength - 1) == 10 {
            contentLength -= 1
            if contentLength > 0, string.character(at: target.location + contentLength - 1) == 13 {
                contentLength -= 1
            }
        }
        let maxOffset = max(0, contentLength - 1)
        return min(target.location + column, target.location + maxOffset)
    }
    
    
    private func forwardWord(from location: Int, big: Bool) -> Int {
        
        guard let textView else { return location }
        return Self.forwardWordLocation(in: textView.string as NSString, from: location, big: big, forOperator: false)
    }
    
    
    private func backwardWord(from location: Int, big: Bool) -> Int {
        
        guard let textView else { return location }
        return Self.backwardWordLocation(in: textView.string as NSString, from: location, big: big)
    }
    
    
    private func wordEnd(from location: Int, big: Bool) -> Int {
        
        guard let textView else { return location }
        return Self.wordEndLocation(in: textView.string as NSString, from: location, big: big)
    }
    
    
    // MARK: Word Segmentation Helpers (CJK + ASCII + Punctuation)
    
    static func lineContentRange(in string: NSString, lineRange: NSRange) -> NSRange {
        
        var end = NSMaxRange(lineRange)
        while end > lineRange.location {
            let ch = string.character(at: end - 1)
            if ch == 10 || ch == 13 {
                end -= 1
            } else {
                break
            }
        }
        return NSRange(location: lineRange.location, length: max(0, end - lineRange.location))
    }
    
    
    private static func isHorizontalWhitespace(_ ch: unichar) -> Bool {
        
        ch == 32 || ch == 9 || ch == 0x3000 || ch == 0x00A0
    }
    
    
    private static func isCJKCharacter(at index: Int, in string: NSString) -> Bool {
        
        let seq = string.rangeOfComposedCharacterSequence(at: index)
        let sub = string.substring(with: seq)
        guard let scalar = sub.unicodeScalars.first else { return false }
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2EBEF).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0x3040...0x309F).contains(v)
            || (0x30A0...0x30FF).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }
    
    
    private static func isASCIIWordUnit(_ ch: unichar) -> Bool {
        
        (ch >= 48 && ch <= 57)     // 0-9
            || (ch >= 65 && ch <= 90)  // A-Z
            || (ch >= 97 && ch <= 122) // a-z
            || ch == 95                // _
    }
    
    
    private static func isCJKSymbolOrPunctuation(_ ch: unichar) -> Bool {
        
        (0x3001...0x303F).contains(ch) || (0xFF01...0xFF65).contains(ch)
    }
    
    
    /// Splits `range` (a single line without trailing newline) into Vim word tokens.
    static func vimTokens(in string: NSString, range: NSRange, big: Bool) -> [NSRange] {
        
        let upper = NSMaxRange(range)
        guard range.length > 0, upper <= string.length else { return [] }
        
        var tokens: [NSRange] = []
        var idx = range.location
        
        if big {
            while idx < upper {
                let seq = string.rangeOfComposedCharacterSequence(at: idx)
                let ch = string.character(at: idx)
                if ch == 10 || ch == 13 || self.isHorizontalWhitespace(ch) {
                    idx = NSMaxRange(seq)
                    continue
                }
                let tokenStart = idx
                while idx < upper {
                    let cSeq = string.rangeOfComposedCharacterSequence(at: idx)
                    let cCh = string.character(at: idx)
                    if cCh == 10 || cCh == 13 || self.isHorizontalWhitespace(cCh) { break }
                    idx = NSMaxRange(cSeq)
                }
                tokens.append(NSRange(location: tokenStart, length: idx - tokenStart))
            }
            return tokens
        }
        
        while idx < upper {
            let seq = string.rangeOfComposedCharacterSequence(at: idx)
            let ch = string.character(at: idx)
            
            if ch == 10 || ch == 13 || self.isHorizontalWhitespace(ch) {
                idx = NSMaxRange(seq)
                continue
            }
            
            if self.isASCIIWordUnit(ch) {
                let start = idx
                idx = NSMaxRange(seq)
                while idx < upper {
                    let nextSeq = string.rangeOfComposedCharacterSequence(at: idx)
                    let nextCh = string.character(at: idx)
                    guard nextSeq.length == 1, self.isASCIIWordUnit(nextCh) else { break }
                    idx = NSMaxRange(nextSeq)
                }
                tokens.append(NSRange(location: start, length: idx - start))
                continue
            }
            
            if self.isCJKCharacter(at: idx, in: string) {
                let runStart = idx
                idx = NSMaxRange(seq)
                while idx < upper, self.isCJKCharacter(at: idx, in: string) {
                    let nextSeq = string.rangeOfComposedCharacterSequence(at: idx)
                    idx = NSMaxRange(nextSeq)
                }
                let runRange = NSRange(location: runStart, length: idx - runStart)
                var wordRanges: [NSRange] = []
                string.enumerateSubstrings(in: runRange, options: [.byWords, .substringNotRequired]) { _, subRange, _, _ in
                    if subRange.length > 0 {
                        wordRanges.append(subRange)
                    }
                }
                if wordRanges.isEmpty {
                    var cursor = runRange.location
                    while cursor < NSMaxRange(runRange) {
                        let cSeq = string.rangeOfComposedCharacterSequence(at: cursor)
                        wordRanges.append(cSeq)
                        cursor = NSMaxRange(cSeq)
                    }
                }
                tokens.append(contentsOf: wordRanges)
                continue
            }
            
            if self.isCJKSymbolOrPunctuation(ch) {
                tokens.append(seq)
                idx = NSMaxRange(seq)
                continue
            }
            
            // Group contiguous ASCII punctuation / symbols (e.g. `->`, `==`, `...`)
            let start = idx
            idx = NSMaxRange(seq)
            while idx < upper {
                let nextSeq = string.rangeOfComposedCharacterSequence(at: idx)
                let nextCh = string.character(at: idx)
                if nextCh == 10 || nextCh == 13
                    || self.isHorizontalWhitespace(nextCh)
                    || self.isASCIIWordUnit(nextCh)
                    || self.isCJKCharacter(at: idx, in: string)
                    || self.isCJKSymbolOrPunctuation(nextCh)
                {
                    break
                }
                idx = NSMaxRange(nextSeq)
            }
            tokens.append(NSRange(location: start, length: idx - start))
        }
        
        return tokens
    }
    
    
    /// Computes the target location of Vim `w` / `W`.
    static func forwardWordLocation(in string: NSString, from location: Int, big: Bool, forOperator: Bool = false) -> Int {
        
        guard string.length > 0 else { return 0 }
        let loc = min(max(0, location), string.length)
        let currentLine = string.lineRange(for: NSRange(location: loc, length: 0))
        let contentRange = self.lineContentRange(in: string, lineRange: currentLine)
        let tokens = self.vimTokens(in: string, range: contentRange, big: big)
        
        if let nextToken = tokens.first(where: { $0.location > loc }) {
            return nextToken.location
        }
        
        // No further token on the current line: advance to the next line if one exists.
        var nextLineStart = NSMaxRange(currentLine)
        let hasTrailingLine = (currentLine.length > 0 && string.character(at: NSMaxRange(currentLine) - 1) == 10)
        if nextLineStart < string.length || (nextLineStart == string.length && hasTrailingLine && !forOperator) {
            if forOperator {
                if let currentToken = tokens.first(where: { loc >= $0.location && loc < NSMaxRange($0) }) {
                    return NSMaxRange(currentToken)
                }
                if NSMaxRange(contentRange) > loc {
                    return NSMaxRange(contentRange)
                }
            }
            while nextLineStart < string.length {
                let nextLine = string.lineRange(for: NSRange(location: nextLineStart, length: 0))
                let nextContent = self.lineContentRange(in: string, lineRange: nextLine)
                let nextTokens = self.vimTokens(in: string, range: nextContent, big: big)
                if let first = nextTokens.first {
                    return first.location
                }
                if nextContent.length == 0 {
                    // Blank lines are valid `w` stops in Vim
                    return nextLine.location
                }
                nextLineStart = NSMaxRange(nextLine)
            }
            if hasTrailingLine && nextLineStart == string.length {
                return string.length
            }
        }
        
        // Last word on the last line of the document
        if forOperator {
            return NSMaxRange(contentRange)
        }
        guard contentRange.length > 0 else { return contentRange.location }
        if let lastToken = tokens.last {
            let lastCharStart = string.rangeOfComposedCharacterSequence(at: NSMaxRange(lastToken) - 1).location
            if loc < lastToken.location {
                return lastToken.location
            }
            return max(loc, lastCharStart)
        }
        return contentRange.location
    }
    
    
    /// Computes the target location of Vim `b` / `B`.
    static func backwardWordLocation(in string: NSString, from location: Int, big: Bool) -> Int {
        
        guard string.length > 0, location > 0 else { return 0 }
        let loc = min(max(0, location), string.length)
        let currentLine = string.lineRange(for: NSRange(location: loc, length: 0))
        let contentRange = self.lineContentRange(in: string, lineRange: currentLine)
        let tokens = self.vimTokens(in: string, range: contentRange, big: big)
        
        if let inside = tokens.first(where: { loc > $0.location && loc < NSMaxRange($0) }) {
            return inside.location
        }
        if let prevToken = tokens.last(where: { $0.location < loc }) {
            return prevToken.location
        }
        
        // Search previous lines
        var searchPos = currentLine.location - 1
        while searchPos >= 0 {
            let prevLine = string.lineRange(for: NSRange(location: searchPos, length: 0))
            let prevContent = self.lineContentRange(in: string, lineRange: prevLine)
            let prevTokens = self.vimTokens(in: string, range: prevContent, big: big)
            if let last = prevTokens.last {
                return last.location
            }
            if prevContent.length == 0 {
                return prevLine.location
            }
            searchPos = prevLine.location - 1
        }
        
        return 0
    }
    
    
    /// Computes the target location of Vim `e` / `E`.
    static func wordEndLocation(in string: NSString, from location: Int, big: Bool) -> Int {
        
        guard string.length > 0 else { return 0 }
        let loc = min(max(0, location), string.length - 1)
        let currentLine = string.lineRange(for: NSRange(location: loc, length: 0))
        let contentRange = self.lineContentRange(in: string, lineRange: currentLine)
        let tokens = self.vimTokens(in: string, range: contentRange, big: big)
        
        if let current = tokens.first(where: { loc >= $0.location && loc < NSMaxRange($0) }) {
            let endLoc = string.rangeOfComposedCharacterSequence(at: NSMaxRange(current) - 1).location
            if loc < endLoc {
                return endLoc
            }
        }
        if let next = tokens.first(where: { $0.location > loc }) {
            return string.rangeOfComposedCharacterSequence(at: NSMaxRange(next) - 1).location
        }
        
        var nextLineStart = NSMaxRange(currentLine)
        while nextLineStart < string.length {
            let nextLine = string.lineRange(for: NSRange(location: nextLineStart, length: 0))
            let nextContent = self.lineContentRange(in: string, lineRange: nextLine)
            let nextTokens = self.vimTokens(in: string, range: nextContent, big: big)
            if let first = nextTokens.first {
                return string.rangeOfComposedCharacterSequence(at: NSMaxRange(first) - 1).location
            }
            nextLineStart = NSMaxRange(nextLine)
        }
        
        if let last = tokens.last {
            return string.rangeOfComposedCharacterSequence(at: NSMaxRange(last) - 1).location
        }
        return loc
    }
    
    
    private func toLineEnd(from location: Int) -> NSRange {
        
        guard let textView else { return NSRange(location: location, length: 0) }
        let string = textView.string as NSString
        guard let lineRange = self.lineRange(at: location) else { return NSRange(location: location, length: 0) }
        var end = NSMaxRange(lineRange)
        if end > 0, string.character(at: end - 1) == 10 { end -= 1 }
        return NSRange(location: location, length: max(0, end - location))
    }
    
    
    private func characterRange(count: Int) -> NSRange {
        
        guard let textView else { return NSRange(location: 0, length: 0) }
        let location = textView.selectedRange().location
        let length = (textView.string as NSString).length
        return NSRange(location: location, length: min(count, max(0, length - location)))
    }
    
    
    private func visualRange() -> NSRange {
        
        guard let textView, let anchor = self.visualAnchor else { return NSRange(location: 0, length: 0) }
        // The active end is the caret, not the selection's upper bound: the selection is
        // built upwards when moving with `k`, so NSMaxRange would be the fixed end.
        let active = VimState.shared.visualActiveLocation ?? textView.selectedRange().location
        let length = (textView.string as NSString).length
        if self.visualLinewise {
            let anchorLine = self.lineRange(at: anchor) ?? NSRange(location: anchor, length: 0)
            let activeLine = self.lineRange(at: active) ?? NSRange(location: active, length: 0)
            let lower = min(anchorLine.location, activeLine.location)
            let upper = min(max(NSMaxRange(anchorLine), NSMaxRange(activeLine)), length)
            return NSRange(location: lower, length: max(0, upper - lower))
        }
        let lower = min(anchor, active)
        let upper = min(max(anchor, active) + 1, length)
        return NSRange(location: lower, length: upper - lower)
    }
    
    
    private func isEscape(_ event: NSEvent) -> Bool {
        
        event.keyCode == 53
    }
    
    
    private func isControlC(_ event: NSEvent) -> Bool {
        
        event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers?.lowercased() == "c"
    }
}
