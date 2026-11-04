//
//  TreeSitterSyntax+Outline.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2026-02-16.
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

import SyntaxFormat

extension TreeSitterSyntax {
    
    /// The outline behavior policy for the syntax.
    var outlinePolicy: OutlinePolicy {
        
        switch self {
            case .javaScript:
                .init(ignoredDepthNodeTypes: [
                    "export_statement",
                    "variable_declarator",
                ])
            case .python:
                .init(ignoredDepthNodeTypes: [
                    "decorated_definition",
                    "expression_statement",
                ])
            case .typeScript:
                .init(ignoredDepthNodeTypes: [
                    "ambient_declaration",
                    "export_statement",
                    "variable_declarator",
                ])
            default:
                .init()
        }
    }
    
    
    /// The outline formatter type for the syntax.
    var outlineFormatter: any TreeSitterOutlineFormatting.Type {
        
        switch self {
            case .bash:
                BashOutlineFormatter.self
            case .javaScript:
                JavaScriptOutlineFormatter.self
            case .markdown:
                MarkdownOutlineFormatter.self
            case .python:
                PythonOutlineFormatter.self
            case .typeScript:
                TypeScriptOutlineFormatter.self
            default:
                DefaultOutlineFormatter.self
        }
    }
}
