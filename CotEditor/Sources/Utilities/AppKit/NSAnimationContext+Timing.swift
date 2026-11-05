//
//  NSAnimationContext+Timing.swift
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

extension NSAnimationContext {

    /// Runs animations with the standard timing (250ms, easeInOut).
    ///
    /// Use this to make `animator()`-based animations match the timing table
    /// in `docs/handoff/editor-ui-motion/DESIGN.md`.
    ///
    /// Example:
    /// ```swift
    /// NSAnimationContext.withStandardTiming {
    ///     splitViewItem.animator().isCollapsed = true
    /// }
    /// ```
    static func withStandardTiming(_ animations: () -> Void) {

        self.withTiming(duration: AnimationConstants.standard, animations)
    }


    /// Runs animations with custom timing.
    ///
    /// - Parameters:
    ///   - duration: Animation duration in seconds.
    ///   - timingFunction: Timing curve (default: easeInOut).
    ///   - animations: The animations to perform.
    static func withTiming(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = AnimationConstants.easeInOut,
        _ animations: () -> Void
    ) {

        runAnimationGroup { context in
            context.duration = AnimationConstants.isReducedMotionEnabled ? AnimationConstants.instant : duration
            context.timingFunction = timingFunction
            animations()
        }
    }


    /// Runs animations with custom timing and a completion handler.
    ///
    /// - Parameters:
    ///   - duration: Animation duration in seconds.
    ///   - timingFunction: Timing curve (default: easeInOut).
    ///   - animations: The animations to perform.
    ///   - completionHandler: Called after the animation finishes.
    static func withTiming(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = AnimationConstants.easeInOut,
        animations: () -> Void,
        completionHandler: @escaping () -> Void
    ) {

        runAnimationGroup { context in
            context.duration = AnimationConstants.isReducedMotionEnabled ? AnimationConstants.instant : duration
            context.timingFunction = timingFunction
            context.completionHandler = completionHandler
            animations()
        }
    }
}
