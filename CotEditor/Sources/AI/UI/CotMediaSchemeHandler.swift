//
//  CotMediaSchemeHandler.swift
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
import Foundation
import WebKit

/// Serves local managed stickers and Bot/User avatars directly to the WebUI over `cot-media://`
/// without base64 bloat in host state payloads.
final class CotMediaSchemeHandler: NSObject, WKURLSchemeHandler {
    
    static let scheme = "cot-media"
    
    
    static func stickerURLString(id: String) -> String {
        "\(Self.scheme)://sticker/\(id)"
    }
    
    
    static func botAvatarURLString(botID: String) -> String {
        "\(Self.scheme)://avatar/bot/\(botID)"
    }
    
    
    static func userAvatarURLString() -> String {
        "\(Self.scheme)://avatar/user"
    }
    
    
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "CotMedia", code: 400))
            return
        }
        let host = url.host() ?? ""
        let pathParts = url.pathComponents.filter { $0 != "/" }
        
        Task { @MainActor in
            let payload = Self.resolvePayload(host: host, pathParts: pathParts)
            guard let payload else {
                urlSchemeTask.didFailWithError(NSError(domain: "CotMedia", code: 404))
                return
            }
            let headers = [
                "Content-Type": payload.mimeType,
                "Cache-Control": host == "sticker" ? "max-age=31536000" : "max-age=60",
            ]
            if let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(payload.data)
                urlSchemeTask.didFinish()
            } else {
                urlSchemeTask.didFailWithError(NSError(domain: "CotMedia", code: 500))
            }
        }
    }
    
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Synchronous single-shot response; nothing in flight to cancel.
    }
    
    
    @MainActor
    private static func resolvePayload(host: String, pathParts: [String]) -> (data: Data, mimeType: String)? {
        switch host {
            case "sticker":
                guard let id = pathParts.first, !id.isEmpty else { return nil }
                return CotStickerLibraryStore.shared.imageData(for: id)
                
            case "avatar":
                if pathParts.first == "user" {
                    let mgr = UserProfileManager.shared
                    guard let img = mgr.avatarImage(for: mgr.activeProfile),
                          let png = Self.pngData(from: img)
                    else { return nil }
                    return (png, "image/png")
                }
                if pathParts.first == "bot", pathParts.count >= 2 {
                    let botID = pathParts[1]
                    guard let img = AIBotStore.shared.resolvedAvatarImage(forBotID: botID, pointSize: 96),
                          let png = Self.pngData(from: img)
                    else { return nil }
                    return (png, "image/png")
                }
                return nil
                
            default:
                return nil
        }
    }
    
    
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
