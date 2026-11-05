//
//  LegacyContainerMigrator.swift
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

/// One-time migration out of the app sandbox container.
///
/// The editor used to be sandboxed, so its preferences and application support files lived
/// under `~/Library/Containers/<bundle id>/Data`. The sandbox is gone (the built-in terminal
/// needs a real shell), which moved those locations to the usual user library paths. This
/// copies the old data over once, so themes, scripts and every setting survive the switch.
enum LegacyContainerMigrator {
    
    private static let migrationKey = "didMigrateFromSandboxContainer"
    
    
    /// Migrates the sandboxed preferences and support files, unless that already happened.
    ///
    /// Safe to call on every launch: it does nothing after the first success.
    static func migrateIfNeeded() {
        
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }
        
        let containerRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers")
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "")
            .appendingPathComponent("Data/Library")
        
        guard FileManager.default.fileExists(atPath: containerRoot.path) else {
            defaults.set(true, forKey: migrationKey)
            return
        }
        
        migratePreferences(from: containerRoot)
        migrateApplicationSupport(from: containerRoot)
        
        defaults.set(true, forKey: migrationKey)
    }
    
    
    /// Copies the preference keys the sandboxed build wrote, keeping the current values.
    ///
    /// - Parameter libraryURL: The container's `Library` folder.
    private static func migratePreferences(from libraryURL: URL) {
        
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let legacyURL = libraryURL
            .appendingPathComponent("Preferences")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathExtension("plist")
        
        guard
            let legacy = NSDictionary(contentsOf: legacyURL),
            !legacy.allKeys.isEmpty
        else { return }
        
        let defaults = UserDefaults.standard
        let current = defaults.dictionaryRepresentation()
        
        // The migration must not overwrite anything the app has written since the sandbox
        // went away, so only missing keys are copied.
        for case let key as String in legacy.allKeys where current[key] == nil {
            defaults.set(legacy[key], forKey: key)
        }
    }
    
    
    /// Copies user files (themes, scripts, syntax definitions) out of the container.
    ///
    /// - Parameter libraryURL: The container's `Library` folder.
    private static func migrateApplicationSupport(from libraryURL: URL) {
        
        let fileManager = FileManager.default
        let legacyURL = libraryURL.appendingPathComponent("Application Support")
        let targetURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        
        guard
            let bundleIdentifier = Bundle.main.bundleIdentifier,
            fileManager.fileExists(atPath: legacyURL.appendingPathComponent(bundleIdentifier).path)
        else { return }
        
        guard let contents = try? fileManager.contentsOfDirectory(at: legacyURL, includingPropertiesForKeys: nil) else { return }
        
        for source in contents {
            let destination = targetURL.appendingPathComponent(source.lastPathComponent)
            
            // never clobber files that were created after the sandbox went away
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            
            try? fileManager.copyItem(at: source, to: destination)
        }
    }
}
