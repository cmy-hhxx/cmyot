//
//  AIMessage.swift
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

import Foundation

/// A picture attached to a message.
///
/// Reserved for the features that need to look at the screen or at an image file, such as
/// "summarize what is on screen" or "read the checklist out of this screenshot".
nonisolated struct AIImage: Sendable {
    
    var data: Data
    var mimeType: String
    
    
    init(data: Data, mimeType: String = "image/png") {
        
        self.data = data
        self.mimeType = mimeType
    }
    
    
    /// The bytes as a base64 string, as every protocol expects them.
    var base64: String {
        
        self.data.base64EncodedString()
    }
}


/// A single message sent to or received from the AI service.
nonisolated struct AIMessage: Sendable {
    
    nonisolated enum Role: String, Sendable {
        
        case system
        case user
        case assistant
    }
    
    
    var role: Role
    var text: String
    var images: [AIImage]
    
    
    init(role: Role, text: String, images: [AIImage] = []) {
        
        self.role = role
        self.text = text
        self.images = images
    }
    
    
    /// A system message.
    static func system(_ text: String) -> AIMessage {
        
        AIMessage(role: .system, text: text)
    }
    
    
    /// A user message.
    static func user(_ text: String, images: [AIImage] = []) -> AIMessage {
        
        AIMessage(role: .user, text: text, images: images)
    }
}
