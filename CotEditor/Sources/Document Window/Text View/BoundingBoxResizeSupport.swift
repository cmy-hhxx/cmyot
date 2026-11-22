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
}
