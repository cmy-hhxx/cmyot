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
| Split panes | Panes can now be nested: splitting the focused pane in the other direction wraps it into an inner `SplitGroupViewController`, so tmux-like layouts are possible (e.g. a row of two stacked panes beside a full-height pane). Closings collapse containers left with a single pane. Menu: 向下分割 / 向右分割 next to Split Editor; the existing toggle flips only the focused container. | `DocumentViewController.swift`, `Main.storyboard` |
| Vim motions | Fixed a real bug: visual-mode motions started from the selection *start* instead of the active end, so `v` then `w` jumped around. Added `f F t T` (+ `;` `,`), text objects (`iw aw i" a" i( a( i[ {`), `/` search with `n N`. | `VimEngine.swift` |
| Navigation bar | The per-pane bar now collapses automatically when it has nothing to show (no split, no outline). It reappears as soon as a pane is split or the document gets headings. | `EditorViewController.swift`, `DocumentViewController.swift` |
| Navigation bar | Removed the redundant split button from the per-pane navigation bar (splitting now lives in the toolbar and the View menu); the pane keeps its close button and outline navigation. | `NavigationBar.swift` |
| Toolbar | Rebuilt around six left-aligned items: readonly (`editable`), curated emoji menu, syntax popup, continuous text-size slider, 向右分割, 向下分割, Inspector (document info); everything else lives behind a 更多 menu on the right. The toolbar identifier was bumped so the old saved layout is not restored. | `DocumentWindowController.swift`, `DocumentViewController.swift` |
| Encodings | Default encoding list trimmed from ~70 entries to five: UTF-8, GB18030 (covers GBK/GB2312), Big 5, UTF-16, Windows Latin 1. This is the list behind the encoding menu at the bottom of the window and the encoding candidates used when opening files. | `DefaultSettings+Encodings.swift` |
| Toolbar placement | Back to the single-row `.unifiedCompact` style (`.expanded` added an ugly second row). The six leading controls are flagged `isNavigational`, which is the documented way to have the system place them outside the normal (trailing) item run. | `DocumentWindowController.swift` |
| Emoji menu | Curated emoji are laid out as five category rows of six buttons (grid) instead of one long column. | `DocumentWindowController.swift`, `DocumentViewController.swift` |
| Windows | 更多 ▸ 并排两个窗口 tiles the two frontmost document windows side by side. | `DocumentController.swift` |
| Appearance | 更多 ▸ 外观 submenu (跟随系统 / 浅色 / 深色) writes the existing `documentAppearance` default; CotEditor already swaps the theme's light/dark variant live, so no new theme code was needed. Checkmark state is kept in sync. | `DocumentWindowController.swift`, `DocumentViewController.swift` |
| Vim motions (2) | `.` repeat, `%`, `J`, `>>` / `<<`, `*` / `#`, `⌃d` / `⌃u`, and counts for `5G` / `5gg`. | `VimEngine.swift` |
| Toolbar | 向右分割 / 向下分割 buttons added to the window toolbar. | `DocumentWindowController.swift` |
| Vim crash | `:` then Backspace on an empty command buffer called `removeLast()` on an empty string and crashed the app (EXC_BREAKPOINT). Deleting past the colon now cancels command mode. Digit handling no longer force-unwraps non-ASCII digits. | `VimEngine.swift` |
| Syntaxes | Bundled syntax list trimmed from 70 to 5: Plain Text, Markdown, Python, JavaScript, TypeScript (the other `.cotsyntax` bundles and their `SyntaxMap.json` entries were removed). | `Resources/Syntaxes/`, `Resources/SyntaxMap.json` |
| Vim visual mode | The selection hides the caret, so the active end now gets its own block cursor drawn in `draw(_:)`. | `EditorTextView.swift`, `VimEngine.swift` |
| Line numbers | Font changed from AvenirNextCondensed to the system monospaced face (SF Mono), so the numbers form an even column. | `NSFont+Name.swift` |
| Vim mode | Block cursor in normal/visual mode, mode label in the window subtitle (and the `:` command echo), so the current mode is always visible. | `EditorTextView.swift`, `VimEngine.swift` |
| Vim mode | New minimal modal editing layer, **on by default** (`vimMode` default). Normal/insert/visual modes, motions `h j k l w b e W B E 0 ^ $ gg G`, operators `d c y` (incl. `dd cc yy`), `x X D C p P u ⌃R`, insert entries `i a I A o O`, visual `v` + `d y c`. A `:` command line is shown in the status bar and supports `set number` / `set nonumber`, `w`, `q`, `wq`. | `Sources/Document Window/Text View/VimEngine.swift`, `EditorTextView.swift`, `StatusBar.swift`, `DefaultKeys.swift`, `DefaultSettings.swift` |
| Spell checking | Removed the whole *Spelling and Grammar* and *Substitutions* menu groups (plus *Speech*); spell-check toolbar item dropped. | `Main.storyboard`, toolbar identifiers |
| Top bar | Toolbar style `.unifiedCompact`, allowed/default items reduced to just *Emoji & Symbols*. | `DocumentWindowController.swift` |
| Title rename | Window now publishes `representedURL`, so the title bar offers the proxy icon and rename-on-double-click; added File ▸ 重命名… wired to the native `moveDocument:` panel. | `DocumentWindowController.swift`, `Main.storyboard` |
| Inspector | Single pane (document only); file attributes, tags and per-character sections removed, keeping encoding / line ending / counts. | `InspectorViewController.swift`, `DocumentInspectorView.swift` |
| Language | App pinned to Simplified Chinese via `AppleLanguages` in the app's own defaults (`defaults write local.cmy.Cot AppleLanguages -array zh-Hans`). No translations were added — the shipped `zh-Hans` string catalogs are used. | user defaults |

## Third round: panes with their own documents

| Area | Change | Files |
|---|---|---|
| Split panes | 向右分割 / 向下分割 split instantly and give the new pane its own empty (untitled) `Document` — the same thing ⌘N does, without any dialog. Before, every pane was a second view of the same text storage, so all panes always showed the same content. | `DocumentViewController.swift`, `EditorViewController.swift` |
| Opening into a pane | With a blank split pane focused, ⌘O / 打开… loads the chosen file **into that pane** instead of creating a window: `DocumentController.openDocument(withContentsOf:display:)` asks the frontmost window for its `focusedBlankEditor` and hands the document over (`absorb`), which swaps the pane's document and closes the empty placeholder. Opening a file any other way keeps the usual window/tab behaviour. | `DocumentController.swift`, `DocumentViewController.swift` |
| Split ratios | Every structural change resets the dividers: each container divides its own thickness evenly among its direct children, so nested layouts are halved at every level. This is necessary because `NSSplitViewController` does **not** divide evenly on insert — it squeezes the existing pane (down to `minimumThickness` in the worst case) and hands the rest to the new item, which produced e.g. 166pt vs 832pt. The reset runs over three layout passes because freshly inserted views only get their size a pass later. | `DocumentViewController.swift` |
| Focus routing | `save:` / `saveAs:` / `changeSyntax:` are implemented on `EditorViewController`, so ⌘S, ⌘⇧S, the syntax menu and the toolbar popup act on the **focused** pane's document. The status bar follows the focused pane as well. | `EditorViewController.swift`, `DocumentWindowController.swift`, `WindowContentViewController.swift` |
| Document lifecycle | The extra document is opened with `display: false`, i.e. it never gets a window controller of its own; it is closed when its pane closes and when the window closes. `windowForSheet` falls back to the key window so save/revert sheets still have an anchor. Untitled-document reuse is suppressed while a document is being opened into a pane, otherwise the empty placeholder window would be repurposed and the file would appear twice in one window. | `DocumentViewController.swift`, `Document.swift`, `DocumentController.swift` |
| Parsing | Each pane document gets its own `setupParser()` call, theme, and edit observer; the syntax invalidation in `textStorageDidProcessEditing` is resolved by text storage instead of assuming the window's primary document. | `DocumentViewController.swift` |
| Pane identity | Every pane shows its document name at the left of its navigation bar (`PaneIdentity`), refreshed on rename/save-as, so three panes on three documents stay distinguishable. | `NavigationBar.swift`, `EditorViewController.swift` |
| Window title | The title, the tab label and the proxy icon follow the **window's own** document, so a tab keeps its name when focus moves between split panes; each pane names its own document in the navigation bar, and the subtitle keeps showing the focused pane's vim mode. (Before, the title followed the focused pane, which made the tab label flip between a split window's two documents.) | `DocumentWindowController.swift`, `NavigationBar.swift` |
| Unsaved state | The close button and tab indicator now light up when **any** pane has unsaved changes (`Document.DidUpdateChangeMessage` → merged `isDocumentEdited`), not just the primary document. | `DocumentWindowController.swift`, `DocumentViewController.swift` |
| Closing a pane | The pane is now only removed **after** its document was reviewed (`NSDocument.canClose`), not before. Previously a cancelled save prompt left an invisible, unsavable document behind, and a "don't save" threw the text away after the pane was already gone. The pane that shows the window's own document can no longer be closed at all (its × and the menu item are disabled), because the window has no way to display a different document. | `DocumentViewController.swift`, `EditorViewController.swift`, `NavigationBar.swift` |
| Closing a window | Pane documents are reviewed in `windowShouldClose(_:)` before the window goes away, instead of being closed from `windowWillClose` — the old order attached the save sheet to a window that was already closing and could leave documents stranded if the user cancelled. | `DocumentWindowController.swift` |
| New document names | New documents get a made-up name (`GeneratedDocumentName`, e.g. 打盹的橘猫, 摸鱼的水獭) instead of 未命名 / 未命名 2 / 未命名 3 …, and the name is reused as the suggested file name when saving. | `GeneratedDocumentName.swift`, `DocumentController.swift` |

| Context menu | The text view's right-click menu is now custom-built and minimal: three reserved AI slots (翻译 / 总结 / 说人话, kept disabled until their actions exist), copy / paste / select all, the five highlight colors as direct color-swatch items (one click paints, no submenu) and "清除高亮". The system's look-up / translate / search, share, spelling, substitutions, transformations, speech, auto-fill and services items are gone. The menu computes its own enabled states (`autoenablesItems = false`) so it behaves the same however it is opened. | `EditorTextView.swift`, `DocumentViewController.swift`, `HighlightColor+AppKit.swift`, `TextHighlight.swift` |

## Seventh round: crash and window-size fixes

| Area | Change | Files |
|---|---|---|
| Crash on the AI button | Opening the AI settings pane crashed on a fresh install: `DefaultKey<String>` force-unwraps when a key has no value, and the AI keys were only written once the user typed something, so the very first read trapped. The AI keys now have registered defaults like every other preference, which makes the pane open on a clean profile. | `DefaultSettings.swift` |
| Window opens small | AppKit's window restoration runs after `DocumentWindowController.init` and replaced the autosaved frame with its own older record, so windows reopened at the size of a throwaway test window instead of the user's last size. The autosaved frame is now remembered in `init` and put back once in `showWindow`, so windows open at the size they had last time. | `DocumentWindowController.swift` |
| Verify hook | `--ai-settings` opens the AI pane on launch, next to the existing `--ui-demo` and `--show-terminal` hooks, so the crash path can be re-checked from a clean profile. | `AppDelegate.swift` |

## Sixth round: AI groundwork

| Area | Change | Files |
|---|---|---|
| AI settings | A new **AI** pane in the settings window, plus a `✨` toolbar button that opens it directly. It holds the protocol, the base URL, the model name and the API key, with a one-click connection test. | `AISettingsView.swift`, `SettingsPane.swift`, `DocumentWindowController.swift`, `AppDelegate.swift` |
| Protocols | Five wire protocols behind one client: OpenAI Responses, OpenAI Chat Completions (covers DeepSeek / Moonshot / Qwen / OpenRouter / LM Studio and every other compatible endpoint), Anthropic Messages, Google Gemini, and local Ollama. The base URL, model and key are free-form, so a new provider never needs code. | `AIEndpoint.swift`, `AIClient.swift` |
| Secrets | The API key is stored in the login keychain, never in the preferences file, so it stays out of settings exports and out of plain-text backups. Everything else lives in ordinary defaults. | `AIKeychain.swift`, `AIConfiguration.swift` |
| Actions | The reserved context-menu entries now work: 翻译 (Chinese ⇄ English, other languages to Chinese, Markdown structure and identifiers preserved), 总结 (bullet summary, a quarter of the length), 说人话 (plain-language rewrite that keeps the facts). | `AIService.swift`, `DocumentViewController.swift`, `EditorTextView.swift` |
| Result sheet | Answers open in a sheet that shows the model's reply with 替换选中 / 插入 / 拷贝 / 取消. Nothing is written into the document until the user chooses, and the change goes through the text view's own insertion path so it stays undoable. An unconfigured AI explains itself and offers to open the AI settings. | `AIResultPanelController.swift` |
| Extension points | `AIAction` is the single place a feature is defined (system prompt + how to build the user turn), `AIImage` already carries pictures through every protocol, and `AIClient` is protocol-only. That leaves the architecture ready for: screenshot → summary ("what should I do next"), inline completion, checklist generation from selected material, and prompt polishing that calls out vague parts. | `AIService.swift`, `AIMessage.swift` |

## Fifth round: built-in terminal

| Area | Change | Files |
|---|---|---|
| Terminal panel | A toolbar button (the `>_` item, next to the other leading controls — not in the 更多 menu) opens a shell panel at the bottom of the current window. It starts the user's login shell (`zsh -i -l`) in the document's folder, is resizable by its divider, and closes with the same button. | `TerminalViewController.swift`, `ContentViewController.swift`, `DocumentWindowController.swift` |
| Terminal lifecycle | Exactly one shell per panel. Starting is idempotent; closing sends SIGHUP+SIGTERM to the shell's process group (interactive zsh ignores bare SIGTERM), escalates to SIGKILL after a grace period, waits/reaps the child itself so no zombie is left, and discards the panel — so reopening always starts a fresh session. Closing the window, replacing its document, or quitting terminates the shell too. | `TerminalViewController.swift`, `ContentViewController.swift` |
| Terminal look | The terminal mirrors the editor instead of using a fixed black theme: background, foreground, caret and selection come from the current editor theme, the font is the editor's font, and the 16 ANSI colors are a curated set chosen for light or dark backgrounds. It follows live theme and appearance switches. | `TerminalViewController.swift` |
| Sandbox removed | The app is no longer sandboxed (`com.apple.security.app-sandbox` dropped from the Ad-Hoc entitlements): a sandboxed shell can only see the app container, which makes an embedded terminal useless. | `CotEditor/CotEditor-AdHoc.entitlements` |
| Settings migration | Because the sandbox is gone, preferences and application support moved out of `~/Library/Containers/...`. On first launch the old container is migrated once (missing keys only, never overwriting current values), so themes, scripts and every setting survive. | `LegacyContainerMigrator.swift`, `AppDelegate.swift` |
| Dependency | Adds SwiftTerm 1.11.0 (pinned exact) for the terminal emulation and PTY handling. | `CotEditor.xcodeproj/project.pbxproj` |

## Fourth round: pane tabs, document pin, text highlights

| Area | Change | Files |
|---|---|---|
| Pane tabs | Every pane is now a tab group. The per-pane bar under the toolbar is a real tab strip: one tab per document, "+" adds a new untitled document tab to that pane, "×" closes a tab, and closing a pane's last tab closes the pane. Switching tabs swaps the text view inside the pane, so selection, scroll position and undo history survive; the window's own document keeps its unclosable tab. | `DocumentViewController.swift`, `EditorViewController.swift`, `NavigationBar.swift`, `PaneTab.swift` |
| Document pin | A tab can be pinned from its right-click menu ("固定标签页" / "取消固定"). Pinning only adds an accent pin icon and moves the tab to the front of the bar — the tab keeps its title and width, so it can still be clicked. Clicking the pin icon unpins it (the context menu works too). Pinned tabs cannot be closed (`×` disappears, close commands are refused). While any tab is pinned the window refuses to close and explains why. The previous window-level pin (toolbar item, File menu item, window tab badge, injected tab context menu) is gone. | `NavigationBar.swift`, `PaneTab.swift`, `DocumentWindowController.swift`, `DocumentWindow.swift` |
| tmux prefix | The toolbar's split buttons are gone; splitting now uses the tmux prefix on the focused pane: **⌃A %** splits to the right, **⌃A "** splits downwards (menu items still exist). The prefix also drives zoom. | `EditorTextView.swift`, `DocumentWindowController.swift` |
| Pane zoom | tmux-style zoom with no toolbar or menu entry: press **⌃A then Z** to expand the focused pane to the whole editing area (its siblings, including nested containers, collapse; the sidebar/inspector stay), and press **⌃A Z** again to restore the exact split layout. Splitting a pane or closing the zoomed pane's last tab zooms out automatically first. | `EditorTextView.swift`, `DocumentViewController.swift` |
| Tab reordering | Tabs can be dragged left/right (pinned ones included). A compact tab-shaped preview follows the cursor (the default snapshot doubled up with the tab underneath), the drop target gets a soft accent fill + outline with no transition delay, the dragged tab is inserted next to the tab it is dropped on (rightwards → after, leftwards → before) and the new order settles in one fast 150ms animation. Hover feedback is instant; the drop-target highlight appears immediately. | `NavigationBar.swift`, `EditorViewController.swift`, `PaneTab.swift` |
| ⌘W | Close (⌘W) closes exactly one document at a time: the focused tab. A pane disappears with its last tab, so other tabs and other panes are never taken down with it, and the window closes only once the window's own (unclosable) tab is the last one left. Pinned tabs refuse, and the window's own tab refuses while other documents still need the window. | `DocumentViewController.swift` |
| Window movement | `isMovableByWindowBackground` is on, so the chrome-like background areas (the tab bar's empty space, the gap under the toolbar) drag the window just like the toolbar does; the text editor and other controls keep their own mouse handling. | `DocumentWindowController.swift` |
| Window title | When the window is split, the title (and the vim-mode subtitle) is hidden: each pane's tab strip already names its documents, and a single window title would duplicate one of them. The title returns as soon as the window is a single pane again. | `DocumentWindowController.swift` |
| ⌘N | New now creates a document tab in the focused pane instead of a window tab; with no window open it still creates the first window. | `DocumentController.swift` |
| Text highlights | Selected text can be painted with five colors (yellow / green / blue / pink / purple) from the text view's context menu or the 高亮 submenu; "清除高亮" removes them. Highlights live in an extended attribute (`local.cmy.CotEditor.TextHighlights`) so the file stays plain text, and they follow edits while the document is open. | `Document+Highlight.swift`, `Models/Highlight/`, `DocumentViewController.swift`, `EditorTextView.swift` |
| Emoji menu | The toolbar emoji menu is grouped into sections (进度 / 优先级 / 状态 / 标记 / 流程); the geometric progress glyphs get a monospaced font so they line up with the emoji. | `DocumentWindowController.swift` |
| Verify hook | DEBUG builds accept `--ui-demo` (or the `COTUIDemo` default) to open a scripted three-pane layout with extra tabs and a pinned tab, `COTUIDemoTabs` for a single pane with three tabs, and `COTUIDemoZoom` (`1` = zoom the second pane, `2` = zoom then restore) — used for screenshots, inert in Release. | `DocumentViewController.swift`, `DocumentWindowController.swift` |

Known limits of the independent panes:

- The window still has one tab group: tabs, `Window` menu entries and state restoration are per window, not per pane. Title, proxy icon and dirty indicator follow the focused pane.
- ⌘O only lands in a pane while that pane is empty and untouched. Once it holds text of its own, ⌘O goes back to opening a window, so nothing typed is thrown away.
- Closing the window saves a dirty secondary pane through the standard autosave-in-place path (`enablesAutosaveInPlace` defaults to `true`). With autosave turned off, `NSDocument` falls back to its save prompt anchored at the key window.
- Saving the *same* file twice in one window is impossible: `NSDocumentController` returns the already-open document, and the split command then just brings that window forward.
- Toolbar text size, wrap, appearance and the read-only toggle stay window-wide; they are applied to every pane.

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

## Build slimming

The bundled syntax list was trimmed to five, but the package graph still pulled every
upstream tree-sitter grammar. The unused grammars are gone from `Packages/Syntax` now:
only Bash, JavaScript, Markdown, Python and TypeScript remain (`tree-sitter-bash`,
`-javascript`, `-markdown`, `-python`, `-typescript`), together with their parser enum
cases, outline formatters, queries, samples and tests. Bash is kept although no Shell
Script syntax ships, so the grammar stays ready for a user-installed one.

Measured after clearing DerivedData and the SwiftPM cache and doing a clean build:
SwiftPM checkouts 2.8 GB → 0.8 GB (SwiftPM cache 2.2 GB → 0.5 GB), app bundle
99 MB → 51 MB, binary 80 MB → 33 MB (tree-sitter symbols 112 → 30), `Package.resolved`
30 → 13 pins. The clean build installs and launches as before.

## Build & install

```sh
./install.command            # build, install, clean, relaunch
./install.command --check    # report only
```

`install.command` can also be double-clicked in Finder: it runs in Terminal and keeps the
window open with the result. `Scripts/install-personal.sh` holds the implementation.

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
