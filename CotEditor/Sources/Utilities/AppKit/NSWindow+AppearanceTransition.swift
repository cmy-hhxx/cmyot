//
//  NSWindow+AppearanceTransition.swift
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
import QuartzCore

@MainActor private final class AppearanceTransitionOverlayView: NSView {
    
    static let viewIdentifier = NSUserInterfaceItemIdentifier("AppearanceTransitionOverlay")
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        
        // Pass all pointer/scroll interaction through immediately during crossfade.
        nil
    }
}


extension NSWindow {
    
    /// Whether an appearance/theme transition crossfade overlay is currently active on this window.
    @MainActor var isAppearanceTransitionActive: Bool {
        
        self.contentView?.subviews.contains(where: { $0.identifier == AppearanceTransitionOverlayView.viewIdentifier }) == true
    }
    
    
    /// Crossfades the window content smoothly across Light/Dark mode or theme updates
    /// by snapshotting the previous appearance into a non-interactive overlay and dissolving it.
    @MainActor func performSmoothAppearanceTransition(
        duration: TimeInterval = 0.28,
        updates: () -> Void
    ) {
        guard
            self.isVisible,
            !self.isAppearanceTransitionActive,
            !AnimationConstants.isReducedMotionEnabled,
            let contentView = self.contentView,
            contentView.bounds.width > 1,
            contentView.bounds.height > 1,
            let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        else {
            updates()
            return
        }
        
        contentView.cacheDisplay(in: contentView.bounds, to: bitmapRep)
        guard let cgImage = bitmapRep.cgImage else {
            updates()
            return
        }
        
        let overlay = AppearanceTransitionOverlayView(frame: contentView.bounds)
        overlay.identifier = AppearanceTransitionOverlayView.viewIdentifier
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.contents = cgImage
        overlay.layer?.contentsGravity = .resize
        overlay.layer?.contentsScale = self.backingScaleFactor
        overlay.layer?.zPosition = 10_000
        
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        
        updates()
        self.displayIfNeeded()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            overlay.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                overlay.removeFromSuperview()
            }
        }
    }
}
