//
//  MediaAssetCropEditorSheet.swift
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
import SwiftUI

/// Interactive Apple-style crop, zoom, pan, aspect-ratio, rotate & flip studio for both Avatars and Backgrounds.
struct MediaAssetCropEditorSheet: View {
    
    let asset: UserMediaAsset
    let onDismiss: () -> Void
    let onSaved: (UserMediaAsset) -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var library: UserMediaLibraryStore
    @State private var titleDraft: String
    @State private var spec: UserMediaEditSpec
    @State private var sourceImage: NSImage?
    @State private var dragStartSpec: UserMediaEditSpec?
    @State private var isInteracting = false
    @State private var previewCircularMask: Bool
    
    private static let stageHeight: CGFloat = 286
    
    init(
        asset: UserMediaAsset,
        library: UserMediaLibraryStore = .shared,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping (UserMediaAsset) -> Void
    ) {
        self.asset = asset
        self._library = State(initialValue: library)
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        self._titleDraft = State(initialValue: asset.title)
        let defaultPreset: MediaAspectPreset = (asset.kind == .avatar) ? .square : .original
        let initial = asset.editSpec ?? UserMediaEditSpec(aspectPreset: defaultPreset)
        self._spec = State(initialValue: initial.clamped())
        self._previewCircularMask = State(initialValue: asset.kind == .avatar)
    }
    
    
    private var orientedSourceSize: CGSize {
        guard let img = self.sourceImage, img.size.width > 0, img.size.height > 0 else {
            return CGSize(width: max(1, self.asset.pixelWidth), height: max(1, self.asset.pixelHeight))
        }
        return (self.spec.quarterTurns % 2 == 1)
            ? CGSize(width: img.size.height, height: img.size.width)
            : img.size
    }
    
    private var targetAspectRatio: CGFloat {
        if let presetRatio = self.spec.aspectPreset.aspectRatio {
            return presetRatio
        }
        let s = self.orientedSourceSize
        return max(0.35, min(3.2, s.width / max(1, s.height)))
    }
    
    private var effectiveCircularMask: Bool {
        self.asset.kind == .avatar && self.spec.aspectPreset == .square && self.previewCircularMask
    }
    
    private var isModifiedFromDefault: Bool {
        let defaultPreset: MediaAspectPreset = (self.asset.kind == .avatar) ? .square : .original
        let baseline = UserMediaEditSpec(aspectPreset: defaultPreset)
        return self.spec != baseline
    }
    
    
    var body: some View {
        VStack(spacing: 0) {
            self.headerBar
            Divider()
            self.cropStudioStage
            Divider()
            self.controlsToolbar
        }
        .frame(width: 548)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            self.sourceImage = self.library.originalImage(for: self.asset) ?? self.library.fullImage(for: self.asset)
        }
    }
    
    
    // MARK: Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 10) {
            TextField(AppLanguage.text("名称", en: "Title"), text: self.$titleDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12.5, weight: .medium))
                .frame(maxWidth: 210)
            
            Text(self.aspectReadoutText)
                .font(.system(size: 11, design: .monospaced).monospacedDigit())
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 8)
            
            if self.isModifiedFromDefault {
                Button(AppLanguage.text("重置", en: "Reset")) {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        let defaultPreset: MediaAspectPreset = (self.asset.kind == .avatar) ? .square : .original
                        self.spec = UserMediaEditSpec(aspectPreset: defaultPreset)
                    }
                }
                .controlSize(.small)
            }
            
            Button(AppLanguage.text("取消", en: "Cancel")) {
                self.onDismiss()
            }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
            
            Button(AppLanguage.text("保存", en: "Save")) {
                self.commitSave()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    
    private var aspectReadoutText: String {
        let pct = Int((self.spec.scale * 100).rounded())
        return "\(self.spec.aspectPreset.label) · \(pct)%"
    }
    
    
    // MARK: Interactive Crop Studio Stage
    
    private var cropStudioStage: some View {
        GeometryReader { outerGeo in
            let cropRect = Self.fittedCropRect(in: outerGeo.size, aspect: self.targetAspectRatio, inset: 22)
            let imgSize = self.orientedSourceSize
            let drawInCrop = UserMediaLibraryStore.cropDrawRect(
                imageSize: imgSize,
                viewportSize: cropRect.size,
                scale: self.spec.scale,
                panX: self.spec.panX,
                panY: self.spec.panY,
                isFlippedY: true
            )
            let globalCenter = CGPoint(
                x: cropRect.minX + drawInCrop.midX,
                y: cropRect.minY + drawInCrop.midY
            )
            
            ZStack(alignment: .topLeading) {
                Color(red: 0.08, green: 0.085, blue: 0.10)
                
                if let image = self.sourceImage {
                    // Dimmed out-of-frame ghost image so the user sees the entire source while dragging.
                    self.transformedImage(image, size: drawInCrop.size, center: globalCenter)
                        .opacity(self.isInteracting ? 0.30 : 0.18)
                    
                    // Sharp active crop region clipped to the target frame / circle.
                    self.transformedImage(image, size: drawInCrop.size, center: globalCenter)
                        .mask(alignment: .topLeading) {
                            Group {
                                if self.effectiveCircularMask {
                                    Circle()
                                        .frame(width: cropRect.width, height: cropRect.height)
                                } else {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .frame(width: cropRect.width, height: cropRect.height)
                                }
                            }
                            .offset(x: cropRect.minX, y: cropRect.minY)
                        }
                }
                
                // Crisp Apple-style crop bezel + rule-of-thirds grid during drag/zoom.
                self.cropBezelOverlay(cropRect: cropRect)
                    .allowsHitTesting(false)
                
                // Direct AppKit pan / pinch / scroll-zoom / double-click surface.
                WallpaperFramingInteractionOverlay(
                    isInteractive: self.sourceImage != nil,
                    onDragStart: {
                        self.dragStartSpec = self.spec
                        self.isInteracting = true
                    },
                    onDragChanged: { translation in
                        let start = self.dragStartSpec ?? self.spec
                        self.spec = Self.dragUpdatedSpec(
                            start: start,
                            imageSize: imgSize,
                            cropSize: cropRect.size,
                            translation: translation
                        )
                    },
                    onDragEnd: {
                        self.dragStartSpec = nil
                        withAnimation(.easeOut(duration: 0.18)) {
                            self.isInteracting = false
                        }
                    },
                    onMagnify: { delta, phase in
                        if phase == .began { self.isInteracting = true }
                        self.spec.scale = max(1.0, min(4.0, self.spec.scale * (1.0 + Double(delta))))
                        if phase == .ended || phase == .cancelled {
                            withAnimation(.easeOut(duration: 0.18)) { self.isInteracting = false }
                        }
                    },
                    onScrollZoom: { delta in
                        self.spec.scale = max(1.0, min(4.0, self.spec.scale * (1.0 + Double(delta))))
                    },
                    onDoubleClick: {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.20)) {
                            if self.spec.scale > 1.05 || abs(self.spec.panX) > 0.02 || abs(self.spec.panY) > 0.02 {
                                self.spec.scale = 1.0
                                self.spec.panX = 0.0
                                self.spec.panY = 0.0
                            } else {
                                self.spec.scale = 1.65
                            }
                        }
                    }
                )
            }
            .clipped()
        }
        .frame(height: Self.stageHeight)
    }
    
    
    @ViewBuilder
    private func transformedImage(_ image: NSImage, size: CGSize, center: CGPoint) -> some View {
        let swapped = (self.spec.quarterTurns % 2 == 1)
        let rawW = swapped ? max(1, size.height) : max(1, size.width)
        let rawH = swapped ? max(1, size.width) : max(1, size.height)
        
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: rawW, height: rawH)
            .rotationEffect(.degrees(Double(self.spec.quarterTurns) * 90.0))
            .scaleEffect(x: self.spec.flipHorizontal ? -1.0 : 1.0, y: 1.0)
            .position(x: center.x, y: center.y)
    }
    
    
    private func cropBezelOverlay(cropRect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            if self.isInteracting {
                Path { path in
                    for idx in 1...2 {
                        let x = cropRect.minX + cropRect.width * CGFloat(idx) / 3.0
                        path.move(to: CGPoint(x: x, y: cropRect.minY))
                        path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                        let y = cropRect.minY + cropRect.height * CGFloat(idx) / 3.0
                        path.move(to: CGPoint(x: cropRect.minX, y: y))
                        path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.38), lineWidth: 0.75)
                .mask(alignment: .topLeading) {
                    Group {
                        if self.effectiveCircularMask {
                            Circle().frame(width: cropRect.width, height: cropRect.height)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .frame(width: cropRect.width, height: cropRect.height)
                        }
                    }
                    .offset(x: cropRect.minX, y: cropRect.minY)
                }
            }
            
            Group {
                if self.effectiveCircularMask {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.88), lineWidth: 1.4)
                        .frame(width: cropRect.width, height: cropRect.height)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.88), lineWidth: 1.4)
                        .frame(width: cropRect.width, height: cropRect.height)
                }
            }
            .offset(x: cropRect.minX, y: cropRect.minY)
        }
    }
    
    
    // MARK: Controls Toolbar
    
    private var controlsToolbar: some View {
        let presets = MediaAspectPreset.presets(for: self.asset.kind)
        
        return VStack(spacing: 12) {
            // Row 1: Aspect Ratio Presets + Rotate / Flip / Circle Preview
            HStack(spacing: 6) {
                ForEach(presets) { preset in
                    let isSelected = (self.spec.aspectPreset == preset)
                    Button {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                            self.spec.aspectPreset = preset
                        }
                    } label: {
                        Text(preset.label)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.80))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(
                                isSelected
                                    ? StudioPaletteManager.shared.activeAccentColor
                                    : Color.primary.opacity(self.colorScheme == .dark ? 0.08 : 0.06),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                }
                
                Spacer(minLength: 6)
                
                if self.asset.kind == .avatar && self.spec.aspectPreset == .square {
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            self.previewCircularMask.toggle()
                        }
                    } label: {
                        Image(systemName: self.previewCircularMask ? "circle.dashed" : "square")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 26)
                    }
                    .controlSize(.small)
                    .help(AppLanguage.text("切换圆形/方形参考框", en: "Toggle Circle Guide"))
                }
                
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)) {
                        self.spec.quarterTurns = (self.spec.quarterTurns + 1) % 4
                    }
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 26)
                }
                .controlSize(.small)
                .help(AppLanguage.text("旋转 90°", en: "Rotate 90°"))
                
                Button {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)) {
                        self.spec.flipHorizontal.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 26)
                }
                .controlSize(.small)
                .help(AppLanguage.text("水平翻转", en: "Flip Horizontal"))
            }
            
            // Row 2: Precision Zoom Slider (100% - 400%)
            HStack(spacing: 10) {
                Button {
                    self.spec.scale = max(1.0, self.spec.scale - 0.15)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Slider(value: self.$spec.scale, in: 1.0...4.0)
                
                Button {
                    self.spec.scale = min(4.0, self.spec.scale + 0.15)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("\(Int((self.spec.scale * 100).rounded()))%")
                    .font(.system(size: 11.5, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    
    // MARK: Actions & Geometry Helpers
    
    private func commitSave() {
        if let updated = self.library.updateAssetEdit(
            id: self.asset.id,
            kind: self.asset.kind,
            title: self.titleDraft,
            editSpec: self.spec
        ) {
            self.onSaved(updated)
        } else {
            self.onDismiss()
        }
    }
    
    
    nonisolated static func fittedCropRect(in container: CGSize, aspect: CGFloat, inset: CGFloat) -> CGRect {
        let availW = max(40, container.width - inset * 2)
        let availH = max(40, container.height - inset * 2)
        let safeAspect = max(0.3, min(3.5, aspect))
        let w: CGFloat
        let h: CGFloat
        if availW / availH >= safeAspect {
            h = availH
            w = h * safeAspect
        } else {
            w = availW
            h = w / safeAspect
        }
        return CGRect(
            x: (container.width - w) * 0.5,
            y: (container.height - h) * 0.5,
            width: w,
            height: h
        )
    }
    
    
    nonisolated static func dragUpdatedSpec(
        start: UserMediaEditSpec,
        imageSize: CGSize,
        cropSize: CGSize,
        translation: CGSize
    ) -> UserMediaEditSpec {
        let clamped = start.clamped()
        guard imageSize.width > 0, imageSize.height > 0, cropSize.width > 0, cropSize.height > 0 else {
            return clamped
        }
        let baseScale = max(cropSize.width / imageSize.width, cropSize.height / imageSize.height)
        let baseW = imageSize.width * baseScale * CGFloat(clamped.scale)
        let baseH = imageSize.height * baseScale * CGFloat(clamped.scale)
        let baseSlackX = max(0, (baseW - cropSize.width) * 0.5)
        let baseSlackY = max(0, (baseH - cropSize.height) * 0.5)
        
        // Gently nudge scale when aspect matches viewport at 1.0x so dragging always works smoothly.
        let effScale = (baseSlackX < 3 && baseSlackY < 3) ? max(clamped.scale, 1.20) : clamped.scale
        let effW = imageSize.width * baseScale * CGFloat(effScale)
        let effH = imageSize.height * baseScale * CGFloat(effScale)
        let slackX = max(0, (effW - cropSize.width) * 0.5)
        let slackY = max(0, (effH - cropSize.height) * 0.5)
        
        var next = clamped
        next.scale = effScale
        if slackX > 1 {
            next.panX = clamped.panX - Double(translation.width / slackX)
        }
        if slackY > 1 {
            next.panY = clamped.panY - Double(translation.height / slackY)
        }
        return next.clamped()
    }
}
