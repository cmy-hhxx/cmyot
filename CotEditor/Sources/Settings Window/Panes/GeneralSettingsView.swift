//
//  GeneralSettingsView.swift
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2023-01-25.
//
//  ---------------------------------------------------------------------------
//
//  © 2023-2025 1024jp
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
import Defaults

struct GeneralSettingsView: View {
    
    @Namespace private var accessibility
    
    @AppStorage(.quitAlwaysKeepsWindows) private var quitAlwaysKeepsWindows: Bool
    @AppStorage(.noDocumentOnLaunchOption) private var noDocumentOnLaunchOption: NoDocumentOnLaunchOption
    
    @AppStorage(.enablesAutosaveInPlace) private var enablesAutosaveInPlace: Bool
    
    @State private var initialEnablesAutosaveInPlace: Bool = false
    
    @State private var language: AppLanguage = .current
    
    @State private var isAutosaveChangeConfirmationPresented = false
    @State private var isLanguageChangeConfirmationPresented = false
    @State private var suppressesQuitAlwaysKeepsWindowsChangeConfirmation = false
    @State private var isQuitAlwaysKeepsWindowsChangeConfirmationPresented = false
    
    
    // MARK: View
    
    var body: some View {
        
        SettingsFormPane(helpAnchor: "settings_general") {
            Section {
                Picker(selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) {
                        Text(verbatim: $0.displayName)
                    }
                } label: {
                    Text("settings.language.label", tableName: "Personal")
                }
                .pickerStyle(.menu)
                .onChange(of: self.language) { _, newValue in
                    newValue.apply()
                    self.isLanguageChangeConfirmationPresented = true
                }
                .confirmationDialog(String(localized: "settings.language.restart.title", defaultValue: "Restart Required", table: "Personal"), isPresented: $isLanguageChangeConfirmationPresented) {
                    Button(String(localized: "Restart Now", table: "GeneralSettings", comment: "button label")) {
                        (NSApp.delegate as? AppDelegate)?.needsRelaunch = true
                        NSApp.terminate(nil)
                    }
                    Button(String(localized: "Later", table: "GeneralSettings", comment: "button label")) {
                        // do nothing
                    }
                } message: {
                    Text(String(localized: "settings.language.restart.message", defaultValue: "The language change will be applied after CotEditor restarts. Do you want to restart now?", table: "Personal"))
                }
            }
            
            Section {
                Toggle(String(localized: "Reopen windows from last session", table: "GeneralSettings"), isOn: $quitAlwaysKeepsWindows)
                    .onChange(of: self.quitAlwaysKeepsWindows) {
                        guard !self.suppressesQuitAlwaysKeepsWindowsChangeConfirmation else { return }
                        
                        self.isQuitAlwaysKeepsWindowsChangeConfirmationPresented = true
                        self.suppressesQuitAlwaysKeepsWindowsChangeConfirmation = true
                    }
                    .confirmationDialog(String(localized: "NextSessionApplicationConfirmation.title", defaultValue: "The change will be applied first on the next launch.", table: "GeneralSettings"), isPresented: $isQuitAlwaysKeepsWindowsChangeConfirmationPresented) {
                    } message: {
                        Text(String(localized: "NextSessionApplicationConfirmation.nextAfterNext.message", defaultValue: "The app’s behavior will change from the next launch after that one.", table: "GeneralSettings"))
                    }
                
                Picker(selection: $noDocumentOnLaunchOption) {
                    ForEach(NoDocumentOnLaunchOption.allCases, id: \.self) {
                        Text($0.label)
                    }
                } label: {
                    Text("When nothing else is open:", tableName: "GeneralSettings")
                        .accessibilityLabeledPair(role: .label, id: "noDocumentOnLaunchOption", in: self.accessibility)
                }
                .pickerStyle(.menu)
                .accessibilityLabeledPair(role: .content, id: "noDocumentOnLaunchOption", in: self.accessibility)
            } header: {
                Text("On startup:", tableName: "GeneralSettings")
            }
            
            Section {
                Toggle(String(localized: "Enable Auto Save with Versions", table: "GeneralSettings"), isOn: $enablesAutosaveInPlace)
                    .onChange(of: self.enablesAutosaveInPlace) { _, newValue in
                        if newValue != self.initialEnablesAutosaveInPlace {
                            self.isAutosaveChangeConfirmationPresented = true
                        }
                    }
                    .onAppear {
                        self.initialEnablesAutosaveInPlace = self.enablesAutosaveInPlace
                    }
                    .confirmationDialog(String(localized: "NextSessionApplicationConfirmation.title", defaultValue: "The change will be applied first on the next launch.", table: "GeneralSettings"), isPresented: $isAutosaveChangeConfirmationPresented) {
                        Button(String(localized: "Restart Now", table: "GeneralSettings", comment: "button label")) {
                            (NSApp.delegate as? AppDelegate)?.needsRelaunch = true
                            NSApp.terminate(self)
                        }
                        Button(String(localized: "Later", table: "GeneralSettings", comment: "button label")) {
                            // do nothing
                        }
                        Button(.cancel, role: .cancel) {
                            self.enablesAutosaveInPlace.toggle()
                        }
                    } message: {
                        Text(String(localized: "NextSessionApplicationConfirmation.message", defaultValue: "Do you want to restart CotEditor now?", table: "GeneralSettings"))
                    }
            } header: {
                Text("Document save:", tableName: "GeneralSettings")
            }
        }
    }
}


private extension NoDocumentOnLaunchOption {
    
    var label: String {
        
        switch self {
            case .untitledDocument:
                String(localized: "NoDocumentOnLaunchOption.untitledDocument.label",
                       defaultValue: "Create New Document",
                       table: "GeneralSettings")
            case .openPanel:
                String(localized: "NoDocumentOnLaunchOption.openPanel.label",
                       defaultValue: "Show Open Dialog",
                       table: "GeneralSettings")
            case .none:
                String(localized: "NoDocumentOnLaunchOption.none.label",
                       defaultValue: "Do Nothing",
                       table: "GeneralSettings")
        }
    }
}


// MARK: - Preview

#Preview {
    GeneralSettingsView()
}
