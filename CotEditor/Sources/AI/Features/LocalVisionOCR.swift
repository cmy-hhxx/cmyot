//
//  LocalVisionOCR.swift
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
import Vision

/// Runs Apple's on-device Vision neural OCR model (`VNRecognizeTextRequest` with `.accurate`
/// recognition and automatic Chinese/English language detection) and bridges the recognized text
/// + PNG image bytes into `AIService` for multimodal AI polishing.
enum LocalVisionOCR {
    
    struct OCRResult: Sendable {
        var text: String
        var pngData: Data?
    }
    
    
    /// Recognizes text in the given `NSImage` using the embedded on-device Vision OCR model.
    ///
    /// - Parameter image: The image to recognize text from.
    /// - Returns: The recognized lines joined in reading order, plus PNG bytes for AI vision.
    static func recognizeText(in image: NSImage) async throws -> OCRResult {
        
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        
        let pngData = bitmap.representation(using: .png, properties: [:])
        
        let recognizedText = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
        
        return OCRResult(text: recognizedText, pngData: pngData)
    }
}
