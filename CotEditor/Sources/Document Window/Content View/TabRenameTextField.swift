//
//  TabRenameTextField.swift
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

/// Borderless text cell that vertically centers single-line tab rename text without invoking `cellSize(forBounds:)`.
final class TabRenameTextFieldCell: NSTextFieldCell {
    
    var expectedLineHeight: CGFloat = 16
    
    
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        
        self.verticallyCenteredRect(for: super.drawingRect(forBounds: rect))
    }
    
    
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        
        self.verticallyCenteredRect(for: super.titleRect(forBounds: rect))
    }
    
    
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        
        super.edit(withFrame: self.verticallyCenteredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }
    
    
    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        
        super.select(withFrame: self.verticallyCenteredRect(for: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
    
    
    private func verticallyCenteredRect(for rect: NSRect) -> NSRect {
        
        let resolvedFont = self.font ?? .systemFont(ofSize: 12, weight: .medium)
        let fallbackHeight = ceil(resolvedFont.ascender - resolvedFont.descender + resolvedFont.leading)
        let lineHeight = self.expectedLineHeight > 0 ? self.expectedLineHeight : fallbackHeight
        let insetY = max(0, min(((rect.height - lineHeight) * 0.5).rounded(.down), rect.height * 0.35))
        return NSRect(x: rect.origin.x, y: rect.origin.y + insetY, width: rect.width, height: max(1, rect.height - insetY * 2))
    }
}


/// Inline tab title editor wired with `TabRenameTextFieldCell`.
final class TabRenameTextField: NSTextField {
    
    convenience init(initialTitle: String) {
        
        self.init(frame: .zero)
        let customCell = TabRenameTextFieldCell(textCell: initialTitle)
        customCell.isEditable = true
        customCell.isSelectable = true
        customCell.wraps = false
        customCell.isScrollable = true
        customCell.sendsActionOnEndEditing = false
        self.cell = customCell
        self.stringValue = initialTitle
    }
    
    
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}
