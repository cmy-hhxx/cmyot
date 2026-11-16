//
//  AppBundleInfoPlistTests.swift
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

import Foundation
import Testing
@testable import CotEditor

/// Checks on the app bundle's own Info.plist.
struct AppBundleInfoPlistTests {
    
    /// The app must not advertise an iCloud document scope.
    ///
    /// Declaring one made AppKit autosave every untitled document into the iCloud Drive
    /// folder, and a document that gains a file URL is renamed after it: editing a fresh
    /// document dropped its made-up name (see `GeneratedDocumentName`) and left the window
    /// titled "Untitled", with a file on the user's iCloud Drive nobody asked to save.
    ///
    /// The container could not work in this build anyway: it is not sandboxed and holds no
    /// ubiquity-container entitlement, so nothing ever synced.
    @Test func doesNotAdvertisePublicICloudDocumentScope() throws {
        
        let containers = Bundle.main.object(forInfoDictionaryKey: "NSUbiquitousContainers") as? [String: [String: Any]]
        
        let hasPublicScope = containers?.values.contains { container in
            container["NSUbiquitousContainerIsDocumentScopePublic"] as? Bool == true
        } ?? false
        
        #expect(!hasPublicScope,
                "A public iCloud document scope makes AppKit save untitled documents into iCloud Drive and rename them \"Untitled\".")
    }
}
