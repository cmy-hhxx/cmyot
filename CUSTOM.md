# Personal build notes

This is a **frozen personal fork** of [CotEditor](https://github.com/coteditor/CotEditor),
not intended to track upstream. Base: tag `7.0.9` (the last release whose project file
opens in Xcode 26; upstream `main` already requires Xcode 27.2 + macOS 27).

## Patches on top of 7.0.9

| Area | Change | Files |
|---|---|---|
| Font | `FontType.systemFont(size:)` always returns the system monospaced font (SF Mono), ignoring the system-wide `userFont` / `userFixedPitchFont` preferences, which resolve to Helvetica (proportional) or Menlo. Ligatures default off. | `CotEditor/Sources/Application/Defaults/DefaultKey+FontType.swift`, `DefaultSettings.swift` |
| Tabs | `New` (⌘N) now calls `newDocumentAsTab:`, and the default `windowTabbing` is `always`, so a new document joins the front window as a tab. `New Window` (⇧⌘N) still forces a separate window. The action stays enabled with no document open so ⌘N can create the first window. | `CotEditor/Storyboards/Base.lproj/Main.storyboard`, `DocumentController.swift`, `DefaultSettings.swift` |
| Line numbers | View ▸ Show Line Numbers gets a shortcut and now persists: the toggle writes the shared `showLineNumbers` default, keeping it in sync with Settings ▸ Window. | `Main.storyboard`, `DocumentViewController.swift` |
| Identity | Bundle id `local.cmy.Cot` (coexists with the App Store CotEditor), `CFBundleDisplayName = Cot`, new app icon generated from `~/Desktop/avata1.jpg` as a classic `AppIcon.appiconset` (the upstream Icon Composer `AppIcon.icon` bundle was removed). | `project.pbxproj`, `Info.plist`, `Assets.xcassets/AppIcon.appiconset` |
| Distribution | Ad-hoc code signing (`CodeSigning-AdHoc.xcconfig`); the non-Sparkle `CotEditor` scheme/config is used, so auto-update is absent and cannot replace this build. | `Configurations/CodeSigning.xcconfig` |

## Second round: minimal editing experience

| Area | Change | Files |
|---|---|---|
| Vim mode | New minimal modal editing layer, **on by default** (`vimMode` default). Normal/insert/visual modes, motions `h j k l w b e W B E 0 ^ $ gg G`, operators `d c y` (incl. `dd cc yy`), `x X D C p P u ⌃R`, insert entries `i a I A o O`, visual `v` + `d y c`. A `:` command line is shown in the status bar and supports `set number` / `set nonumber`, `w`, `q`, `wq`. | `Sources/Document Window/Text View/VimEngine.swift`, `EditorTextView.swift`, `StatusBar.swift`, `DefaultKeys.swift`, `DefaultSettings.swift` |
| Spell checking | Removed the whole *Spelling and Grammar* and *Substitutions* menu groups (plus *Speech*); spell-check toolbar item dropped. | `Main.storyboard`, toolbar identifiers |
| Top bar | Toolbar style `.unifiedCompact`, allowed/default items reduced to just *Emoji & Symbols*. | `DocumentWindowController.swift` |
| Title rename | Window now publishes `representedURL`, so the title bar offers the proxy icon and rename-on-double-click; added File ▸ 重命名… wired to the native `moveDocument:` panel. | `DocumentWindowController.swift`, `Main.storyboard` |
| Inspector | Single pane (document only); file attributes, tags and per-character sections removed, keeping encoding / line ending / counts. | `InspectorViewController.swift`, `DocumentInspectorView.swift` |
| Language | App pinned to Simplified Chinese via `AppleLanguages` in the app's own defaults (`defaults write local.cmy.Cot AppleLanguages -array zh-Hans`). No translations were added — the shipped `zh-Hans` string catalogs are used. | user defaults |

Known limits of the vim layer: single register, no macros/marks/text objects/visual block,
no `/` search, no `.` repeat, no `f t %`. Registers/undo go through the standard
`NSTextView` editing path, so undo works but interleaves with CotEditor's own undo steps.

## Not implemented

Full Vim fidelity. Upstream has rejected vim support four times
([#574](https://github.com/coteditor/CotEditor/issues/574) et al.), and no reusable
NSTextView-based vim engine exists in Swift, so the in-app layer above is deliberately
small. For parity, run an OS-level vim layer
([VimMode.spoon](https://github.com/dbalatero/VimMode.spoon), or
[KindaVim](https://kindavim.app), which the CotEditor maintainer recommends) and turn
`vimMode` off (`defaults write local.cmy.Cot vimMode 0`).

## Build & install

```sh
./Scripts/install-personal.sh          # build, install, clean, relaunch
./Scripts/install-personal.sh --check  # report only
```

**One copy only.** `Scripts/install-personal.sh` is the supported way to build and install:
it builds into Xcode's default DerivedData (`~/Library/Developer/Xcode/DerivedData`, outside
Spotlight's index), installs to `/Applications/Cot.app`, moves any other bundle with the same
bundle id (`local.cmy.Cot`, `com.coteditor.CotEditor`) to the Trash, and fails unless exactly
one copy is left. Do **not** build with `-derivedDataPath` inside the repo — an `.app` under
`~/Desktop` is indexed by Spotlight and shows up as a second, stale editor.

The ad-hoc signature means macOS re-asks for formerly granted permissions
(Automation, Full Disk Access, …) after each rebuild.

## Installed state

- `/Applications/Cot.app` — the single installed build (`local.cmy.Cot`, display name `Cot`).
- The App Store CotEditor (version 7.1.3) was moved to the Trash; it can be restored from
  there or re-downloaded from the App Store if ever needed.
