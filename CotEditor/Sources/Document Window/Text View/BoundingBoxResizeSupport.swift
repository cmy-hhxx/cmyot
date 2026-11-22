//
//  BoundingBoxResizeSupport.swift
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

/// The eight perimeter control handles for the `bounding-box-resize` selection frame.
nonisolated enum BoundingBoxHandle: Int, CaseIterable, Sendable {
    
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight
    
    
    var isCorner: Bool {
        switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: true
            default: false
        }
    }
    
    var isHorizontalEdge: Bool {
        self == .middleLeft || self == .middleRight
    }
    
    var isVerticalEdge: Bool {
        self == .topCenter || self == .bottomCenter
    }
    
    var isWest: Bool {
        self == .topLeft || self == .middleLeft || self == .bottomLeft
    }
    
    var isEast: Bool {
        self == .topRight || self == .middleRight || self == .bottomRight
    }
    
    var isNorth: Bool {
        self == .topLeft || self == .topCenter || self == .topRight
    }
    
    var isSouth: Bool {
        self == .bottomLeft || self == .bottomCenter || self == .bottomRight
    }
    
    /// Base arrow rotation angle matching the Bounding Box Resize specification.
    var arrowAngleDegrees: CGFloat {
        switch self {
            case .middleLeft, .middleRight: 0
            case .topCenter, .bottomCenter: 90
            case .topLeft, .bottomRight: 45
            case .topRight, .bottomLeft: -45
        }
    }
    
    /// Center coordinate relative to the selection box center `(0, 0)` in flipped view space.
    func localPoint(size: NSSize) -> NSPoint {
        let hw = size.width * 0.5
        let hh = size.height * 0.5
        return switch self {
            case .topLeft:      NSPoint(x: -hw, y: -hh)
            case .topCenter:    NSPoint(x: 0, y: -hh)
            case .topRight:     NSPoint(x: hw, y: -hh)
            case .middleLeft:   NSPoint(x: -hw, y: 0)
            case .middleRight:  NSPoint(x: hw, y: 0)
            case .bottomLeft:   NSPoint(x: -hw, y: hh)
            case .bottomCenter: NSPoint(x: 0, y: hh)
            case .bottomRight:  NSPoint(x: hw, y: hh)
        }
    }
}


/// Exact 10-vertex morphing geometry between a `10×10pt` square handle and a directional double-arrow.
nonisolated enum BoundingBoxHandleMorph {
    
    static let squareVertices: [NSPoint] = [
        NSPoint(x: -5,   y: 0),
        NSPoint(x: -5,   y: -5),
        NSPoint(x: -2.5, y: -5),
        NSPoint(x: 2.5,  y: -5),
        NSPoint(x: 5,    y: -5),
        NSPoint(x: 5,    y: 0),
        NSPoint(x: 5,    y: 5),
        NSPoint(x: 2.5,  y: 5),
        NSPoint(x: -2.5, y: 5),
        NSPoint(x: -5,   y: 5),
    ]
    
    static let horizontalArrowVertices: [NSPoint] = [
        NSPoint(x: -11, y: 0),
        NSPoint(x: -4,  y: -7),
        NSPoint(x: -4,  y: -3),
        NSPoint(x: 4,   y: -3),
        NSPoint(x: 4,   y: -7),
        NSPoint(x: 11,  y: 0),
        NSPoint(x: 4,   y: 7),
        NSPoint(x: 4,   y: 3),
        NSPoint(x: -4,  y: 3),
        NSPoint(x: -4,  y: 7),
    ]
    
    
    /// Rotates the directional arrow vertices first and interpolates vertex-by-vertex from square -> arrow.
    static func interpolatedVertices(
        for handle: BoundingBoxHandle,
        progress: CGFloat,
        extraRotationDegrees: CGFloat = 0
    ) -> [NSPoint] {
        
        let t = max(0, min(1, progress))
        let totalDeg = handle.arrowAngleDegrees + extraRotationDegrees
        let rad = totalDeg * .pi / 180.0
        let cosA = cos(rad)
        let sinA = sin(rad)
        
        return zip(Self.squareVertices, Self.horizontalArrowVertices).map { sq, arrow in
            let rotX = arrow.x * cosA - arrow.y * sinA
            let rotY = arrow.x * sinA + arrow.y * cosA
            return NSPoint(
                x: sq.x + (rotX - sq.x) * t,
                y: sq.y + (rotY - sq.y) * t
            )
        }
    }
    
    
    static func bezierPath(
        for handle: BoundingBoxHandle,
        center: NSPoint,
        progress: CGFloat,
        extraRotationDegrees: CGFloat = 0
    ) -> NSBezierPath {
        
        let verts = Self.interpolatedVertices(
            for: handle,
            progress: progress,
            extraRotationDegrees: extraRotationDegrees
        )
        let path = NSBezierPath()
        guard let first = verts.first else { return path }
        path.move(to: NSPoint(x: center.x + first.x, y: center.y + first.y))
        for pt in verts.dropFirst() {
            path.line(to: NSPoint(x: center.x + pt.x, y: center.y + pt.y))
        }
        path.close()
        return path
    }
}


/// Damped unit-mass spring (`a = 550 * (target - value) - 34 * velocity`) integrated over 4 substeps per frame.
nonisolated struct BoundingBoxMorphSpring: Sendable {
    
    var value: CGFloat = 0
    var velocity: CGFloat = 0
    var target: CGFloat = 0
    
    
    mutating func step(dt: CGFloat) -> Bool {
        let clampedDt = max(0, min(0.032, dt))
        guard clampedDt > 0 else {
            return (abs(self.target - self.value) + abs(self.velocity)) >= 0.002
        }
        
        let subDt = clampedDt / 4.0
        for _ in 0..<4 {
            let accel = 550.0 * (self.target - self.value) - 34.0 * self.velocity
            self.velocity += accel * subDt
            self.value += self.velocity * subDt
        }
        
        if abs(self.target - self.value) + abs(self.velocity) < 0.002 {
            self.value = self.target
            self.velocity = 0
            return false
        }
        return true
    }
}


/// Which horizontal side of an inline image card the text caret is positioned on.
nonisolated enum CaretImageEdge: Sendable {
    case leading
    case trailing
}


/// Opposite-edge-anchored clamped geometry math for 8-handle resizing.
nonisolated enum BoundingBoxResizeMath {
    
    static let minWidth: CGFloat = 64
    static let minHeight: CGFloat = 48
    
    
    static func resizedFrame(
        startFrame: NSRect,
        handle: BoundingBoxHandle,
        delta: NSPoint,
        minXBound: CGFloat = 16,
        minYBound: CGFloat = 16,
        maxXBound: CGFloat = 608,
        maxYBound: CGFloat = 1600
    ) -> NSRect {
        
        let startRight = startFrame.maxX
        let startBottom = startFrame.maxY
        
        var x = startFrame.minX
        var y = startFrame.minY
        var width = startFrame.width
        var height = startFrame.height
        
        if handle.isEast {
            let maxEastW = max(Self.minWidth, maxXBound - startFrame.minX)
            width = max(Self.minWidth, min(maxEastW, round(startFrame.width + delta.x)))
        } else if handle.isWest {
            let maxWestW = max(Self.minWidth, startRight - minXBound)
            width = max(Self.minWidth, min(maxWestW, round(startFrame.width - delta.x)))
            x = startRight - width
        }
        
        if handle.isSouth {
            let maxSouthH = max(Self.minHeight, maxYBound - startFrame.minY)
            height = max(Self.minHeight, min(maxSouthH, round(startFrame.height + delta.y)))
        } else if handle.isNorth {
            let maxNorthH = max(Self.minHeight, startBottom - minYBound)
            height = max(Self.minHeight, min(maxNorthH, round(startFrame.height - delta.y)))
            y = startBottom - height
        }
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    
    /// Automatically computes the closest visually balanced size restoring `naturalSize`'s exact aspect ratio
    /// while preserving the perceived area of `currentSize` whenever distortion occurs.
    static func optimalRestoredSize(
        currentSize: NSSize,
        naturalSize: NSSize,
        maxWidth: CGFloat,
        maxHeight: CGFloat = 1600
    ) -> NSSize {
        
        guard naturalSize.width > 0, naturalSize.height > 0 else {
            return NSSize(
                width: max(Self.minWidth, min(maxWidth, round(currentSize.width))),
                height: max(Self.minHeight, min(maxHeight, round(currentSize.height)))
            )
        }
        
        let aspect = naturalSize.width / naturalSize.height
        let safeMaxW = max(Self.minWidth, maxWidth)
        let safeMaxH = max(Self.minHeight, maxHeight)
        
        let idealWidth: CGFloat
        if currentSize.width > 0, currentSize.height > 0 {
            let currentAspect = currentSize.width / currentSize.height
            let drift = abs(currentAspect - aspect) / max(aspect, 0.001)
            if drift <= 0.015 {
                idealWidth = currentSize.width
            } else {
                let area = currentSize.width * currentSize.height
                idealWidth = sqrt(area * aspect)
            }
        } else {
            idealWidth = naturalSize.width
        }
        
        var w = max(Self.minWidth, min(safeMaxW, round(idealWidth)))
        var h = round(w / aspect)
        
        if h > safeMaxH {
            h = safeMaxH
            w = max(Self.minWidth, min(safeMaxW, round(h * aspect)))
        }
        if h < Self.minHeight {
            h = min(safeMaxH, Self.minHeight)
            w = max(Self.minWidth, min(safeMaxW, round(h * aspect)))
            h = max(Self.minHeight, min(safeMaxH, round(w / aspect)))
        }
        
        return NSSize(width: w, height: h)
    }
    
    
    /// Opposite-edge-anchored resize math that always preserves `naturalAspectRatio` across corner & edge handles.
    static func aspectPreservingResizedFrame(
        startFrame: NSRect,
        naturalAspectRatio: CGFloat,
        handle: BoundingBoxHandle,
        delta: NSPoint,
        minXBound: CGFloat = 16,
        minYBound: CGFloat = 16,
        maxXBound: CGFloat = 608,
        maxYBound: CGFloat = 1600
    ) -> NSRect {
        
        let raw = Self.resizedFrame(
            startFrame: startFrame,
            handle: handle,
            delta: delta,
            minXBound: minXBound,
            minYBound: minYBound,
            maxXBound: maxXBound,
            maxYBound: maxYBound
        )
        guard naturalAspectRatio.isFinite, naturalAspectRatio > 0.01 else {
            return raw
        }
        
        let startRight = startFrame.maxX
        let startBottom = startFrame.maxY
        
        if handle.isCorner {
            let availW = handle.isEast ? max(Self.minWidth, maxXBound - startFrame.minX) : max(Self.minWidth, startRight - minXBound)
            let availH = handle.isSouth ? max(Self.minHeight, maxYBound - startFrame.minY) : max(Self.minHeight, startBottom - minYBound)
            let relDx = abs(delta.x) / max(1, startFrame.width)
            let relDy = abs(delta.y) / max(1, startFrame.height)
            
            var w: CGFloat
            var h: CGFloat
            if relDx >= relDy {
                w = raw.width
                h = round(w / naturalAspectRatio)
            } else {
                h = raw.height
                w = round(h * naturalAspectRatio)
            }
            
            if w > availW {
                w = availW
                h = round(w / naturalAspectRatio)
            }
            if h > availH {
                h = availH
                w = round(h * naturalAspectRatio)
            }
            if w < Self.minWidth {
                w = min(availW, Self.minWidth)
                h = min(availH, round(w / naturalAspectRatio))
            }
            if h < Self.minHeight {
                h = min(availH, Self.minHeight)
                w = min(availW, round(h * naturalAspectRatio))
            }
            
            let x = handle.isWest ? (startRight - w) : startFrame.minX
            let y = handle.isNorth ? (startBottom - h) : startFrame.minY
            return NSRect(x: x, y: y, width: w, height: h)
        }
        
        if handle.isHorizontalEdge {
            let availW = handle.isEast ? max(Self.minWidth, maxXBound - startFrame.minX) : max(Self.minWidth, startRight - minXBound)
            let availH = max(Self.minHeight, maxYBound - minYBound)
            var w = min(availW, max(Self.minWidth, raw.width))
            var h = round(w / naturalAspectRatio)
            if h > availH {
                h = availH
                w = min(availW, max(Self.minWidth, round(h * naturalAspectRatio)))
            }
            if h < Self.minHeight {
                h = min(availH, Self.minHeight)
                w = min(availW, max(Self.minWidth, round(h * naturalAspectRatio)))
            }
            let x = handle.isWest ? (startRight - w) : startFrame.minX
            let y = max(minYBound, min(maxYBound - h, startFrame.minY))
            return NSRect(x: x, y: y, width: w, height: h)
        }
        
        // Vertical edge handles (.topCenter / .bottomCenter)
        let availH = handle.isSouth ? max(Self.minHeight, maxYBound - startFrame.minY) : max(Self.minHeight, startBottom - minYBound)
        let availW = max(Self.minWidth, maxXBound - minXBound)
        var h = min(availH, max(Self.minHeight, raw.height))
        var w = round(h * naturalAspectRatio)
        if w > availW {
            w = availW
            h = min(availH, max(Self.minHeight, round(w / naturalAspectRatio)))
        }
        if w < Self.minWidth {
            w = min(availW, Self.minWidth)
            h = min(availH, max(Self.minHeight, round(w / naturalAspectRatio)))
        }
        let x = max(minXBound, min(maxXBound - w, round(startFrame.midX - w * 0.5)))
        let y = handle.isNorth ? (startBottom - h) : startFrame.minY
        return NSRect(x: x, y: y, width: w, height: h)
    }
    
    
    /// Computes an insertion caret rect whose height and X/Y placement track the inline image card smoothly.
    static func adaptiveCaretRect(
        forImageCardRect cardRect: NSRect,
        edge: CaretImageEdge,
        singleLineHeight: CGFloat,
        textContainerMinX: CGFloat
    ) -> NSRect {
        
        let imageVisualHeight = max(singleLineHeight, cardRect.height - 8)
        let caretHeight = imageVisualHeight
        let caretWidth: CGFloat = caretHeight > 120 ? 2.5 : 2.0
        let caretY = round(cardRect.midY - caretHeight * 0.5)
        let caretX: CGFloat = (edge == .leading)
            ? max(textContainerMinX, round(cardRect.minX - 4))
            : round(cardRect.maxX + 4)
        return NSRect(x: caretX, y: caretY, width: caretWidth, height: caretHeight)
    }
}
