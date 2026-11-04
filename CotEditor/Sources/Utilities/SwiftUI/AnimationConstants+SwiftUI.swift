//
//  AnimationConstants+SwiftUI.swift
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

import SwiftUI

extension Animation {

    /// Standard transition animation (250ms, easeInOut).
    ///
    /// Matches `AnimationConstants.standard` on the AppKit side.
    static let cotStandard = Animation.easeInOut(duration: AnimationConstants.standard)

    /// Micro-interaction animation (150ms, easeOut).
    ///
    /// Matches `AnimationConstants.fast` on the AppKit side.
    static let cotFast = Animation.easeOut(duration: AnimationConstants.fast)

    /// Large layout transition animation (350ms, easeInOut).
    ///
    /// Matches `AnimationConstants.slow` on the AppKit side.
    static let cotSlow = Animation.easeInOut(duration: AnimationConstants.slow)

    /// Spring animation for drag and reorder interactions.
    ///
    /// Matches `AnimationConstants.reorderAnimation` on the AppKit side.
    static let cotReorder = AnimationConstants.reorderAnimation
}


extension View {

    /// Applies an animation that respects the user's reduced-motion preference.
    ///
    /// - Parameters:
    ///   - animation: The animation to apply when motion is allowed.
    ///   - value: The value that triggers the animation when it changes.
    func cotAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {

        self.animation(AnimationConstants.isReducedMotionEnabled ? .none : animation, value: value)
    }
}
