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
| Language | The app language is chosen in Settings ▸ General ▸ 语言 / Language (简体中文 or English), which writes `AppleLanguages` in the app's own defaults and applies on the next launch (the pane offers Restart Now). No translations were added for the shipped catalogs — the upstream `en` and `zh-Hans` string catalogs are used; the strings this fork adds have their own catalogs (see the eighth round). | `Sources/Application/AppLanguage.swift`, `GeneralSettingsView.swift`, user defaults |

## Third round: panes with their own documents

| Area | Change | Files |
|---|---|---|
| Split panes | 向右分割 / 向下分割 split instantly and give the new pane its own empty (untitled) `Document` — the same thing ⌘N does, without any dialog. Before, every pane was a second view of the same text storage, so all panes always showed the same content. | `DocumentViewController.swift`, `EditorViewController.swift` |
| Opening into a pane | With a blank split pane focused, ⌘O / 打开… loads the chosen file **into that pane** instead of creating a window: `DocumentController.openDocument(withContentsOf:display:)` asks the frontmost window for its `focusedBlankEditor` and hands the document over (`absorb`), which swaps the pane's document and closes the empty placeholder. Opening a file any other way keeps the usual window/tab behaviour. | `DocumentController.swift`, `DocumentViewController.swift` |
| Split ratios | Every structural change resets the dividers: each container divides its own thickness evenly among its direct children, so nested layouts are halved at every level. This is necessary because `NSSplitViewController` does **not** divide evenly on insert — it squeezes the existing pane (down to `minimumThickness` in the worst case) and hands the rest to the new item, which produced e.g. 166pt vs 832pt. The reset runs over three layout passes because freshly inserted views only get their size a pass later. | `DocumentViewController.swift` |
| Focus routing | `save:` / `saveAs:` / `changeSyntax:` are implemented on `EditorViewController`, so ⌘S, ⌘⇧S, the syntax menu and the toolbar popup act on the **focused** pane's document. The status bar follows the focused pane as well. | `EditorViewController.swift`, `DocumentWindowController.swift`, `WindowContentViewController.swift` |
| Document lifecycle | The extra document is opened with `display: false`, i.e. it never gets a window controller of its own; it is closed when its pane closes and when the window closes. `windowForSheet` falls back to the key window so save/revert sheets still have an anchor. Untitled-document reuse is suppressed while a document is being opened into a pane, otherwise the empty placeholder window would be repurposed and the file would appear twice in one window. | `DocumentViewController.swift`, `Document.swift`, `DocumentController.swift` |
| Parsing | Each pane document gets its own `setupParser()` call, theme, and edit observer; the syntax invalidation in `textStorageDidProcessEditing` is resolved by text storage instead of assuming the window's primary document. | `DocumentViewController.swift` |
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

## Eighth round: AI setup, file details, app language

| Area | Change | Files |
|---|---|---|
| AI setup | The AI pane now does what the user asked: pick the **service**, paste its key, **fetch the model list** and choose a model — the model name is no longer typed. The list comes from the service itself (`AIModelCatalog`): OpenAI chat/responses `GET {base}/models`, Anthropic `GET {base}/models?limit=1000`, Gemini `GET {base}/models?pageSize=1000` (only models with `generateContent`), Ollama `GET {base}/api/tags`. A refresh button re-reads it, an inline message explains a failed fetch, and the stored model stays visible until a list arrives. The pane carries no captions under its rows: the rows are the structure, and the three facts a label cannot carry (keychain storage, what a protocol is for, how much of the base URL to paste) are tooltips on the fields and the protocol picker. Every row sits in one grid: labels right-aligned in an 80 pt column, all controls on one leading edge, 12 pt between rows and 24 pt between the form and the advanced section. The text fields and the status lines are 460 pt wide, so the form fills the pane and an error or test message cannot push the layout sideways. Advanced opens its rows in place; a `DisclosureGroup` would indent them into a second label column. | `Sources/AI/Wire/AIModelCatalog.swift`, `AISettingsView.swift` |
| AI providers | Nine presets replace the protocol dropdown: OpenAI, DeepSeek, Moonshot (Kimi), 通义千问, OpenRouter, Anthropic, Google Gemini, Ollama (Local), Custom. A preset bundles a wire protocol and a base URL, so the normal flow is three fields. The existing `aiEndpoint` / `aiBaseURL` / `aiModel` preferences stay the only storage: the preset is derived from them (`AIProvider.detect`), and no new key was added. The protocol picker and the base URL field moved into an **Advanced** disclosure, which opens by itself only for a custom service. This also fixes the old trap where the base URL was compared with the endpoint default, so DeepSeek/Moonshot/Qwen/OpenRouter stored their own URL rather than silently falling back to OpenAI. | `Sources/AI/Core/AIProvider.swift`, `AIConfiguration.swift`, `AISettingsView.swift` |
| AI layering | The module is split into four layers, bottom-up: **Core** (value types that never touch the network — `AIEndpoint`, `AIProvider`, `AIConfiguration`, `AIMessage`, `AIError`), **Wire** (`AIClient` chat requests, `AIModelCatalog` model lists, `AIKeychain` secret; both HTTP calls share `AIConfiguration.requestHeaders`), **Features** (`AIAction` owns prompts, `AIService` is the single MainActor facade) and **UI** (`AIResultPanelController`). A new AI feature adds an `AIAction` case (or a feature type in Features) and calls `AIService`; it never edits protocol code and shares the one configuration set up here. | `Sources/AI/Core/`, `Wire/`, `Features/`, `UI/` |
| AI localization | Every AI string is localized through a new `AI` catalog: settings pane, provider/endpoint labels and hints, action titles, result sheet buttons and status lines, and all `AIError` messages (en + zh-Hans). | `Localizables/AI/AI.xcstrings` |
| Inspector | The document inspector now shows only what the annotated screenshot asked for. The whole **Text Settings** section (encoding / line endings / mode) and the **Position** block (位置 / 行 / 列) are gone; a **File** section was restored at the top with **创建时间** (Created), **最后更新时间** (Last Modified), **复制文件路径** (Copy File Path — one click copies `fileURL.path`, flashes ✓ 已复制 for 1.5 s, disabled without a URL, tooltip carries the path) and **文件作者** (File Author). **Count** keeps lines / characters / words. Untitled documents show the rows with “–”. | `Sources/Document Window/Inspector/DocumentInspectorView.swift`, `Localizables/Application/Personal.xcstrings` |
| App language | Settings ▸ General now starts with a **语言 / Language** picker offering 简体中文 and English. It writes the app's own `AppleLanguages` default (the key the fork already used to pin Chinese) and explains that a relaunch applies it, with **Restart Now** / **Later**; Restart Now uses the existing `needsRelaunch` path, which relaunches the app when it terminates. The current language is read back from the same default, so the picker reflects the running app. | `Sources/Application/AppLanguage.swift`, `GeneralSettingsView.swift`, `Localizables/Application/Personal.xcstrings` |
| English completeness | All user-visible strings this fork added outside the AI module were localized into a `Chrome` catalog: toolbar labels/tooltips, the 更多 menu and the 外观 submenu, emoji section names, tab context menu and tooltips, text-view context menu, the five highlight color names, and the three custom alerts. The three Chinese Base storyboard menu items this fork added (重命名… / 向下分割 / 向右分割) are retitled at launch from the same catalog instead of touching the storyboard. | `Localizables/Application/Chrome.xcstrings`, `DocumentWindowController.swift`, `NavigationBar.swift`, `EditorTextView.swift`, `TextHighlight.swift`, `DocumentViewController.swift`, `AppDelegate.swift` |
| Untitled documents | Editing a new document no longer turns it into a file. AppKit was autosaving every untitled document into the iCloud Drive folder declared by `NSUbiquitousContainers`; a document that gains a file URL is renamed after it, so the made-up name was replaced with "Untitled" and a file the user never asked to save appeared in iCloud Drive. The declaration is gone (this build is not sandboxed and holds no ubiquity-container entitlement, so nothing ever synced) and untitled documents now autosave to the app's own local location, keeping their name. | `CotEditor/Info.plist`, `Tests/Sources/Application/AppBundleInfoPlistTests.swift` |
| Verify hooks | DEBUG builds accept `--settings-pane <pane>` (for example `general` or `ai`) and `--show-inspector [file]` next to `--ai-settings`, `--show-terminal` and `--ui-demo`, so the panes can be screenshotted without clicking; inert in Release. | `AppDelegate.swift` |

Known limits of this round:

- The language applies on the next launch; the running process cannot swap AppKit's storyboard-localized menus in place.
- The fetched model list lives in memory only: reopening the AI pane or switching the service fetches it again. That keeps the preferences file free of provider-specific data.
- The made-up new-document names (`GeneratedDocumentName`) stay Chinese in English UI on purpose; they are a Chinese word-puzzle feature, not UI text.

Known limits of the independent panes:

- The window still has one tab group: tabs, `Window` menu entries and state restoration are per window, not per pane.
- ⌘O only lands in a pane while that pane is empty and untouched. Once it holds text of its own, ⌘O goes back to opening a window, so nothing typed is thrown away.
- Closing the window saves a dirty secondary pane through the standard autosave-in-place path (`enablesAutosaveInPlace` defaults to `true`). With autosave turned off, `NSDocument` falls back to its save prompt anchored at the key window.
- Saving the *same* file twice in one window is impossible: `NSDocumentController` returns the already-open document, and the split command then just brings that window forward.
- Toolbar text size, wrap, appearance and the read-only toggle stay window-wide; they are applied to every pane.

Known limits of the vim layer: a single unnamed register, no macros, no marks and no
visual block. Registers/undo go through the standard `NSTextView` editing path, so undo
works but interleaves with CotEditor's own undo steps.

## Ninth round: several AI endpoints

| Area | Change | Files |
|---|---|---|
| AI endpoints | The AI pane is a **list of endpoints** instead of one form, so a hosted service, a gateway on the local network and a fallback can sit side by side and the one in use is picked by clicking its row (the selection *is* the setting). A row shows the name (or the service/host when unnamed), the address and the model, an 使用中 badge, and buttons to test, edit and delete it. Editing happens in a sheet — one sheet for both adding and editing — because the list has to stay a list inside a fixed-width settings pane. | `AISettingsView.swift`, `AIEndpointEditorView.swift` (new) |
| AI endpoint storage | The single `aiEndpoint` / `aiBaseURL` / `aiModel` triple is replaced by one JSON blob under `aiProfiles` plus `aiActiveProfileID`, so any number of endpoints fits. Each profile's API key lives in its own keychain item keyed by the profile id, so switching endpoints switches secrets and deleting an endpoint deletes its secret; no key enters the preferences file or a settings export. The old single configuration is imported once on first read (with an empty name, so it shows as the service or the host), keeping the endpoint that was already set up. | `Sources/AI/Core/AIEndpointProfile.swift` (new), `AIEndpointStore.swift` (new), `Wire/AIKeychain.swift`, `AIConfiguration.swift`, `Application/Defaults/DefaultKeys.swift` |
| Testing without switching | `AIService` grew `testConnection(configuration:)` and `fetchModels(configuration:)`, so the sheet tests the values on screen instead of the stored ones: an endpoint proves itself (model list + a one-word reply) before it replaces the one in use. The list can test any row in place; the result shows as a ✓ or an orange warning whose tooltip carries the message. | `Sources/AI/Features/AIService.swift`, `AISettingsView.swift`, `AIEndpointEditorView.swift` |
| Model field | The model is a text field with the fetched list in a menu beside it, instead of a picker that only a successful fetch could fill. A service that answers `/models` badly or not at all (a gateway with a fixed model, a proxy) is usable by typing the id, which used to be a dead end: without a fetched list the field stayed empty and the test button stayed disabled. | `AIEndpointEditorView.swift` |
| Plain-HTTP endpoints | App Transport Security is off for this app (`NSAllowsArbitraryLoads`), because an endpoint is whatever address the user types and a good share of them are plain HTTP — a gateway on the local network, a container on another machine. ATS exception domains only accept domain names, never the IP addresses those gateways are reached by, so there was no narrower switch. Nothing is contacted by itself: every request goes to the address and the key the user entered. | `CotEditor/Info.plist` |
| AI localization | 17 new strings — list rows, buttons, sheet titles, the empty state, the delete confirmation and the model field — in en and zh-Hans. | `Localizables/AI/AI.xcstrings` |

Known limits of the endpoint list:

- The list lives in the preferences file, so it is not carried by a `.cotsettings` archive.
- There is no reordering and no per-endpoint temperature yet; rows stay in the order they were added.
- Switching endpoints does not cancel a request that is already running.

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
