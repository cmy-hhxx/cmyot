//
//  AnimationConstants.swift
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
import QuartzCore
import SwiftUI

/// Centralized animation timing constants for consistent UI motion.
///
/// This is the single source of truth for animation durations and curves in
/// CotEditor. Both AppKit (`NSAnimationContext`) and SwiftUI (`.animation`)
/// sides read from here so that the two systems stay in sync.
///
/// See `docs/handoff/editor-ui-motion/DESIGN.md` §5 for the full motion table.
enum AnimationConstants {

    // MARK: - Durations

    /// Duration for immediate state changes that should not animate (0ms).
    static let instant: TimeInterval = 0.0

    /// Duration for micro-interactions such as hover states (150ms).
    static let fast: TimeInterval = 0.15

    /// Duration for standard transitions such as panel show/hide (250ms).
    ///
    /// - Note: This matches AppKit's `animator()` default duration, which is
    ///   the duration most existing call sites already rely on.
    static let standard: TimeInterval = 0.25

    /// Duration for larger layout transitions such as list reflow (350ms).
    ///
    /// - Note: This matches SwiftUI's default `.animation` duration, which is
    ///   what existing SwiftUI call sites already use.
    static let slow: TimeInterval = 0.35

    /// Duration for highlight flashes and other decaying effects (500ms).
    static let slower: TimeInterval = 0.5


    // MARK: - Timing Functions

    /// Standard easing for most transitions. Matches `CAMediaTimingFunctionName.easeInEaseOut`.
    static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)

    /// Decelerating easing for elements entering the screen.
    static let easeOut = CAMediaTimingFunction(name: .easeOut)

    /// Accelerating easing for elements leaving the screen.
    static let easeIn = CAMediaTimingFunction(name: .easeIn)

    /// Linear easing. Use only for continuous or looping animations.
    static let linear = CAMediaTimingFunction(name: .linear)


    // MARK: - SwiftUI Animations

    /// Standard SwiftUI animation for discrete transitions.
    static let standardAnimation = Animation.easeInOut(duration: standard)

    /// SwiftUI animation for micro-interactions.
    static let fastAnimation = Animation.easeOut(duration: fast)

    /// SwiftUI animation for larger layout transitions.
    static let slowAnimation = Animation.easeInOut(duration: slow)

    /// Spring animation for drag and reorder interactions.
    ///
    /// - Note: `dampingFraction: 0.8` keeps the overshoot subtle so that
    ///   reordering never feels bouncy. Do not lower this value without
    ///   updating the motion table in DESIGN.md.
    static let reorderAnimation = Animation.spring(response: slow, dampingFraction: 0.8)


    // MARK: - Reduced Motion

    /// Whether the user has requested reduced motion.
    static var isReducedMotionEnabled: Bool {

        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
