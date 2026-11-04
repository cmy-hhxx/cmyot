//
//  TreeSitterSyntax.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-01-23.
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

public import SyntaxFormat

import TreeSitterBash
import TreeSitterJavaScript
import TreeSitterMarkdown
import TreeSitterPython
import TreeSitterTypeScript

public enum TreeSitterSyntax: String, CaseIterable, Sendable {
    
    case bash = "Bash"
    case javaScript = "JavaScript"
    case markdown = "Markdown"
    case python = "Python"
    case typeScript = "TypeScript"
    
    var name: String  { self.rawValue }
    
    
    /// Supported features.
    public var features: ParserFeatures {
        
        switch self {
            case .markdown: [.outline]
            default: [.highlight, .outline]
        }
    }
    
    
    /// The provider/injection name.
    var providerName: String {
        
        self.rawValue.lowercased()
    }
    
    
    /// The tree-sitter language pointer.
    var language: OpaquePointer {
        
        switch self {
            case .bash: unsafe tree_sitter_bash()
            case .javaScript: unsafe tree_sitter_javascript()
            case .markdown: unsafe tree_sitter_markdown()
            case .python: unsafe tree_sitter_python()
            case .typeScript: unsafe tree_sitter_typescript()
        }
    }
}
