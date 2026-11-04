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
import Observation

/// The editing mode shared with the status bar.
enum VimMode: Equatable {
    
    case normal
    case insert
    case visual
    
    var label: String {
        switch self {
            case .normal: "NORMAL"
            case .insert: "INSERT"
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
        case lineDown, lineUp  // linewise counterparts of j / k
    }
    
    private enum CharacterClass {
        case whitespace, word, punctuation
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
    private var visualLinewise = false
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
        
        // Control combinations: only ⌃R (redo) is claimed.
        if flags.contains(.control) {
            guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "r" else { return false }
            textView.undoManager?.redo()
            return true
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
        
        // Resolve the `g` prefix (only `gg` is supported).
        if self.pendingPrefix == "g" {
            self.pendingPrefix = nil
            if character == "g" { self.move(.documentStart) }
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
            case "^": self.move(.firstNonBlank)
            case "$": self.move(.lineEnd)
            case "g": self.pendingPrefix = "g"
            case "G": self.move(.documentEnd)
                
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
                
            case "d", "c", "y":
                self.pendingOperator = OperatorKind(rawValue: character)
                
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
                
            case "p":
                self.paste(after: true)
            case "P":
                self.paste(after: false)
                
            case "u":
                self.textView?.undoManager?.undo()
            case "v":
                let location = textView.selectedRange().location
                self.visualAnchor = location
                VimState.shared.visualActiveLocation = location
                self.enter(mode: .visual)
                
            case "i":
                self.enter(mode: .insert)
            case "a":
                let end = NSMaxRange(textView.selectedRange())
                self.setCursor(end)
                self.enter(mode: .insert)
            case "I":
                self.move(.firstNonBlank)
                self.enter(mode: .insert)
            case "A":
                self.move(.lineEnd)
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
        
        self.count = self.pendingOperator == nil ? nil : self.count
        return true
    }
    
    
    private func handleVisual(character: Character) -> Bool {
        
        guard let textView else { return false }
        switch character {
            case "h": self.move(.left)
            case "j": self.move(.lineDown)
            case "k": self.move(.lineUp)
            case "l": self.move(.right)
            case "w": self.move(.wordForward)
            case "b": self.move(.wordBackward)
            case "e": self.move(.wordEnd)
            case "0": self.move(.lineStart)
            case "$": self.move(.lineEnd)
            case "y":
                let range = self.visualRange()
                self.register = (textView.string as NSString).substring(with: range)
                self.registerIsLinewise = false
                self.endVisual()
            case "d", "x":
                self.delete(self.visualRange())
                self.endVisual()
            case "c":
                self.delete(self.visualRange())
                self.endVisual()
                self.enter(mode: .insert)
            case "v":
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
        
        let parts = command.trimmingCharacters(in: .whitespaces).split(separator: " ").map(String.init)
        guard let head = parts.first else { return }
        
        switch head {
            case "set":
                for argument in parts.dropFirst() {
                    switch argument {
                        case "number", "nu", "rnu", "relativenumber":
                            UserDefaults.standard[.showLineNumbers] = true
                        case "nonumber", "nonu", "nornu", "norelativenumber":
                            UserDefaults.standard[.showLineNumbers] = false
                        default:
                            break
                    }
                }
            case "w":
                self.saveDocument()
            case "q":
                if let window = self.textView?.window { window.performClose(nil) }
            case "wq":
                self.saveDocument()
                if let window = self.textView?.window { window.performClose(nil) }
            case "noh", "nohlsearch":
                break
            default:
                break
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
            case "^": .firstNonBlank
            case "$": .lineEnd
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
                let range = self.lineRange(at: location)
                location = max(range?.location ?? 0, NSMaxRange(range ?? NSRange(location: 0, length: 0)) - 1)
            case .documentStart:
                location = 0
            case .documentEnd:
                let range = self.lineRange(at: max(0, string.length - 1))
                location = self.firstNonBlank(in: range, string: string)
        }
        
        if VimState.shared.mode == .visual, let anchor = self.visualAnchor {
            textView.setSelectedRange(NSRange(location: min(anchor, location),
                                              length: abs(location - anchor)))
            VimState.shared.visualActiveLocation = location
            self.refreshCursor()
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
                for _ in 0..<count { end = self.forwardWord(from: end, big: false) }
            case .wordBackward:
                end = start
                for _ in 0..<count { end = self.backwardWord(from: end, big: false) }
            case .wordEnd:
                end = self.wordEnd(from: start, big: false) + 1
            case .bigWordForward:
                end = start
                for _ in 0..<count { end = self.forwardWord(from: end, big: true) }
            case .bigWordBackward:
                end = start
                for _ in 0..<count { end = self.backwardWord(from: end, big: true) }
            case .bigWordEnd:
                end = self.wordEnd(from: start, big: true) + 1
            case .lineStart:
                end = self.lineRange(at: start)?.location ?? 0
            case .firstNonBlank:
                end = self.firstNonBlank(in: self.lineRange(at: start), string: string)
            case .lineEnd:
                end = NSMaxRange(self.lineRange(at: start) ?? NSRange(location: 0, length: 0))
                if end > 0, string.character(at: end - 1) == 10 { end -= 1 }
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
                self.delete(range)
            case .change:
                self.delete(range)
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
        let lineRange = self.lineRange(at: textView.selectedRange().location) ?? NSRange(location: 0, length: 0)
        let insertAt = below ? NSMaxRange(lineRange) : lineRange.location
        let text = "\n"
        let range = NSRange(location: insertAt, length: 0)
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        self.setCursor(below ? insertAt + 1 : insertAt)
        self.enter(mode: .insert)
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
            case "\"", "'", "`":
                return self.quoteTextObject(quote: character, inner: inner, at: caret, string: string)
            case "(", ")", "b":
                return self.bracketTextObject(open: "(", close: ")", inner: inner, at: caret, string: string)
            case "[", "]":
                return self.bracketTextObject(open: "[", close: "]", inner: inner, at: caret, string: string)
            case "{", "}", "B":
                return self.bracketTextObject(open: "{", close: "}", inner: inner, at: caret, string: string)
            default:
                return nil
        }
    }
    
    
    private func wordTextObject(inner: Bool, at caret: Int, string: NSString) -> NSRange? {
        
        var index = min(caret, string.length - 1)
        while index > 0, self.isWordSeparator(string.character(at: index)) { index -= 1 }
        guard !self.isWordSeparator(string.character(at: index)) else { return nil }
        
        var start = index
        while start > 0, !self.isWordSeparator(string.character(at: start - 1)) { start -= 1 }
        
        var end = index + 1
        while end < string.length, !self.isWordSeparator(string.character(at: end)) { end += 1 }
        
        guard !inner else { return NSRange(location: start, length: end - start) }
        
        var trailing = end
        while trailing < string.length,
              self.isWordSeparator(string.character(at: trailing)),
              string.character(at: trailing) != 10
        {
            trailing += 1
        }
        
        return NSRange(location: start, length: trailing - start)
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
    
    
    // MARK: Helpers
    
    private func saveDocument() {
        
        (self.textView?.window?.windowController?.document as? NSDocument)?.save(nil)
    }
    
    
    private func enter(mode: VimMode) {
        
        VimState.shared.mode = mode
        if mode == .insert { self.visualAnchor = nil }
        self.resetPending(keepCount: false)
        self.refreshCursor()
        self.updateStatus()
    }
    
    
    /// Redraws the caret so the block cursor appears/disappears with the mode.
    private func refreshCursor() {
        
        self.textView?.updateInsertionPointStateAndRestartTimer(true)
        self.textView?.setNeedsDisplay(self.textView?.visibleRect ?? .zero)
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
        VimState.shared.visualActiveLocation = nil
        self.enter(mode: .normal)
    }
    
    
    private func resetPending(keepCount: Bool = false) {
        
        self.pendingOperator = nil
        self.pendingPrefix = nil
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
        let length = (textView.string as NSString).length
        let clamped = max(0, min(location, length))
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
        textView.scrollRangeToVisible(NSRange(location: clamped, length: 0))
    }
    
    
    private func lineRange(at location: Int) -> NSRange? {
        
        guard let textView else { return nil }
        let string = textView.string as NSString
        guard string.length > 0 else { return NSRange(location: 0, length: 0) }
        return string.lineRange(for: NSRange(location: min(max(0, location), string.length - 1), length: 0))
    }
    
    
    private func firstNonBlank(in range: NSRange?, string: NSString) -> Int {
        
        guard let range else { return 0 }
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            let character = string.character(at: location)
            if character != 32 && character != 9 { break }
            location += 1
        }
        return min(location, max(0, end - 1))
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
            guard next >= 0, next < max(1, string.length) else { return location }
            target = self.lineRange(at: next) ?? target
        }
        
        let maxOffset = max(0, target.length - (target.length > 0 && string.character(at: NSMaxRange(target) - 1) == 10 ? 1 : 0))
        return min(target.location + column, target.location + maxOffset)
    }
    
    
    private func characterClass(_ character: unichar) -> CharacterClass {
        
        if character == 32 || character == 9 || character == 10 || character == 13 {
            return .whitespace
        }
        guard let scalar = Unicode.Scalar(character) else { return .punctuation }
        let isWord = CharacterSet.alphanumerics.contains(scalar) || character == 95
        return isWord ? .word : .punctuation
    }
    
    
    private func forwardWord(from location: Int, big: Bool) -> Int {
        
        guard let textView else { return location }
        let string = textView.string as NSString
        guard string.length > 0, location < string.length else { return string.length }
        
        var index = location
        let startClass = big ? (self.isWhitespace(string.character(at: index)) ? CharacterClass.whitespace : .word)
                             : self.characterClass(string.character(at: index))
        
        while index < string.length {
            let category = big
                ? (self.isWhitespace(string.character(at: index)) ? CharacterClass.whitespace : .word)
                : self.characterClass(string.character(at: index))
            if category != startClass { break }
            index += 1
        }
        while index < string.length {
            let category = big
                ? (self.isWhitespace(string.character(at: index)) ? CharacterClass.whitespace : .word)
                : self.characterClass(string.character(at: index))
            if category != .whitespace { break }
            index += 1
        }
        return index
    }
    
    
    private func backwardWord(from location: Int, big: Bool) -> Int {
        
        guard let textView else { return location }
        let string = textView.string as NSString
        guard string.length > 0, location > 0 else { return 0 }
        
        var index = location - 1
        func classAt(_ i: Int) -> CharacterClass {
            big ? (self.isWhitespace(string.character(at: i)) ? .whitespace : .word)
                : self.characterClass(string.character(at: i))
        }
        while index > 0, classAt(index) == .whitespace { index -= 1 }
        let target = classAt(index)
        while index > 0, classAt(index - 1) == target { index -= 1 }
        return index
    }
    
    
    private func wordEnd(from location: Int, big: Bool) -> Int {
        
        guard let textView else { return location }
        let string = textView.string as NSString
        guard string.length > 0 else { return 0 }
        
        var index = min(location + 1, string.length - 1)
        func classAt(_ i: Int) -> CharacterClass {
            big ? (self.isWhitespace(string.character(at: i)) ? .whitespace : .word)
                : self.characterClass(string.character(at: i))
        }
        while index < string.length - 1, classAt(index) == .whitespace { index += 1 }
        let target = classAt(index)
        while index < string.length - 1, classAt(index + 1) == target { index += 1 }
        return index
    }
    
    
    private func isWhitespace(_ character: unichar) -> Bool {
        
        character == 32 || character == 9 || character == 10 || character == 13
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
        let current = NSMaxRange(textView.selectedRange())
        let start = min(anchor, current)
        let end = max(anchor, current)
        let length = (textView.string as NSString).length
        return NSRange(location: start, length: min(end, length) - start)
    }
    
    
    private func isEscape(_ event: NSEvent) -> Bool {
        
        event.keyCode == 53
    }
    
    
    private func isControlC(_ event: NSEvent) -> Bool {
        
        event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers?.lowercased() == "c"
    }
}
