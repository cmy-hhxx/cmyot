# Round 8 — AI configuration, inspector file details, language switch

Personal fork of CotEditor (`local.cmy.Cot`, display name `Cot`), Base 7.0.9.
This document is the shared spec for the three parallel workstreams. Read it fully
before touching any file. The Lead owns integration, the build, the install and
`CUSTOM.md`; do not edit those.

## User request (verbatim intent)

1. AI model configuration must fetch the model list instead of asking the user to type a model name.
2. Keep configuration as simple as possible.
3. Decouple the AI module; many future features will depend on AI, so the layering must be clear.
4. Rework the file-details inspector exactly as the annotated screenshot says:
   delete the *Text Settings* section (encoding / line endings / mode) and the
   *Position* block (位置 / 行 / 列); add **创建时间**, **最后更新时间**, **复制文件路径**, **文件作者**.
5. Add a language setting in Settings supporting 简体中文 and English.

## Hard rules (all tracks)

- **Do not run `xcodebuild`.** The Lead builds. Running it in parallel corrupts DerivedData and
  the sandbox blocks Xcode's caches. For syntax checking use
  `xcrun swiftc -parse <file>.swift` (single file, syntax only) — no type checking is possible
  without the full build.
- Use `rg` / `fd`, never `grep` / `find` / `cat`.
- Match the existing code style: 4-space indent, file header comment block (copy an existing
  file's header, `© 2026 1024jp`), doc comments (`///`) on every non-obvious declaration,
  no trailing whitespace, `nonisolated` where the existing code uses it.
- Every user-facing string you add or touch must be localized through a String Catalog,
  never a hard-coded Chinese literal. English is the source language (`defaultValue`), and
  the catalog must also contain a `zh-Hans` translation. Keep keys stable and dotted
  (`ai.service.label`, `chrome.toolbar.more`).
- New `.xcstrings` files are picked up automatically: the whole `CotEditor/` folder is a
  file-system-synchronized group of the app target. The catalog file name is the lookup
  table name: `Foo.xcstrings` → `String(localized: "key", defaultValue: "…", table: "Foo")`.
  Create the file with this shape (2-space indent, `" : "` separator, trailing newline —
  match the existing catalogs):

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "some.key" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "English text"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "中文"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

- Stay strictly inside your write scope. If a change seems to need another track's file,
  report it instead of editing it.
- Write scope is advisory, not a lock: several agents share this working tree. Re-read a file
  before editing if it may have changed.

## Track A — `ai-config`

Write scope: `CotEditor/Sources/AI/**`,
`CotEditor/Sources/Settings Window/Panes/AISettingsView.swift`,
new `CotEditor/Localizables/AI/AI.xcstrings`.

### A1. Layering (decoupling)

Restructure `CotEditor/Sources/AI/` into four folders with `git mv`-like moves (plain file
moves are fine; the Xcode project is file-system-synchronized):

```
Sources/AI/Core/    AIEndpoint.swift, AIProvider.swift (new), AIConfiguration.swift,
                    AIMessage.swift, AIError.swift (new)
Sources/AI/Wire/    AIClient.swift, AIModel.swift (new), AIModelCatalog.swift (new), AIKeychain.swift
Sources/AI/Features/AIAction.swift (new, moved out of AIService.swift), AIService.swift
Sources/AI/UI/      AIResultPanelController.swift
```

- `AIError` moves verbatim out of `AIClient.swift`, plus a new `noModels` case.
- `AIAction` moves verbatim out of `AIService.swift`. Keep `AIAction.title`,
  `systemPrompt`, `prompt(for:context:)` working. **`title` is now localized** through the
  `AI` catalog ("翻译"/"Translate" etc.).
- Public API used by the rest of the app must stay source-compatible:
  `AIService.shared`, `AIService.isConfigured`, `AIService.isRunning`,
  `AIService.run(_:on:context:images:)`, `AIService.testConnection()`,
  `AIResultPanelController(action:)`, `AIResultPanelController.present(on:)`,
  `present(result:)`, `present(error:)`, `onReplace`, `onInsert`,
  `AIConfiguration.current`, `AIProvider`, `AIEndpoint`.
  (`DocumentViewController` and `EditorTextView` must compile unchanged.)
- Add the doc comment to `AIService`/`AIClient` explaining the layering and the extension
  point for new features (the Lead copies the final description into `CUSTOM.md`; report the
  one-paragraph summary in your completion note).

### A2. Providers (simple configuration)

New `AIProvider` enum (`String, CaseIterable, Sendable, Codable`) with cases and defaults:

| case | display label | endpoint | default base URL |
|---|---|---|---|
| `openAI` | OpenAI | `.openAIChatCompletions` | `https://api.openai.com/v1` |
| `deepSeek` | DeepSeek | `.openAIChatCompletions` | `https://api.deepseek.com/v1` |
| `moonshot` | Moonshot (Kimi) | `.openAIChatCompletions` | `https://api.moonshot.cn/v1` |
| `qwen` | 通义千问 | `.openAIChatCompletions` | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| `openRouter` | OpenRouter | `.openAIChatCompletions` | `https://openrouter.ai/api/v1` |
| `anthropic` | Anthropic | `.anthropicMessages` | `https://api.anthropic.com/v1` |
| `google` | Google Gemini | `.googleGemini` | `https://generativelanguage.googleapis.com/v1beta` |
| `ollama` | Ollama (Local) | `.ollama` | `http://localhost:11434` |
| `custom` | Custom (OpenAI-compatible) | `.openAIChatCompletions` | `""` |

Brand names are not translated; `custom` and `ollama`'s "(Local)" are localized.
`AIProvider.detect(endpoint:baseURL:)` derives the current provider:
normalize the base URL (trim, drop trailing `/`); empty input means "the endpoint default";
match against the table above; return `.custom` when nothing matches. No new preference key
is stored — the existing `aiEndpoint` / `aiBaseURL` / `aiModel` keys stay the only storage
(`AIConfiguration.save()` unchanged), and `AIConfiguration.provider` is computed.

`AIConfiguration` gains: `provider`, `modelsRequestURL: URL?` (see A3), and a shared
`requestHeaders` (moved from `AIClient.headers`, including Anthropic's `anthropic-version`;
used by both the chat client and the model catalog). Keep `isUsable`, `resolvedBaseURL`,
`requestURL` behavior. For `modelsRequestURL`, strip a pasted full operation path
(`…/chat/completions`, `…/responses`, `…/messages`) before appending the models path.

### A3. Model listing

New `AIModel` (`Sendable, Hashable, Identifiable`): `id` (wire id), `name` (display name,
usually == id).

New `AIModelCatalog.fetch(configuration:) async throws -> [AIModel]`:

| endpoint | request | parse |
|---|---|---|
| OpenAI Chat / Responses | `GET {base}/models` | `data[].id`, display = id |
| Anthropic | `GET {base}/models?limit=1000` | `data[].id`, display = `display_name ?? id` |
| Gemini | `GET {base}/models?pageSize=1000` | `models[]`; keep only entries whose `supportedGenerationMethods` contains `generateContent`; strip the `models/` prefix for the id; display = `displayName ?? id` |
| Ollama | `GET {base}/api/tags` | `models[].name` (fall back to `model`) |

Use the shared request headers, `timeoutInterval` 30, throw `AIError.http` / `.transport` /
`.decoding` / new `.noModels` (empty list) like `AIClient`. `AIService` gets
`func fetchModels() async throws -> [AIModel]` (MainActor, reads `AIConfiguration.current`).

### A4. New AI settings pane

Rewrite `AISettingsView` around the user's "simple" requirement. Suggested layout
(Grid, `scenePadding()`, `frame(width: 620)`, same save-on-change pattern):

1. **Service** (`AIProvider` picker) — brand labels, no protocol/URL fields in the main flow.
   A one-line caption under it may state that compatible services all work (localized).
2. **API Key** (`SecureField`, keychain note caption; disabled for endpoints that need no key).
3. **Model** — a menu `Picker` of the fetched `AIModel`s, with a trailing "Fetch Models"
   (`arrow.triangle.2.circlepath`) button and a small progress indicator while loading.
   - The picker must show the currently stored model even before any list was fetched.
   - When the list is empty show a disabled placeholder item ("Fetch models first").
   - Show the fetch error inline in red/secondary text (localized via `AIError`).
   - Auto-fetch on `.task` when the configuration has an API key (or is Ollama), and after
     switching the service. Do not refetch on every keystroke of the key.
4. A **Test Connection** row with the existing success/failure presentation.
5. A **Advanced** `DisclosureGroup` (collapsed by default; force-expanded when
   `provider == .custom` or a custom base URL is set) containing:
   - Protocol picker (`AIEndpoint`) — only when `provider == .custom`; the protocol follows
     the preset otherwise.
   - Base URL text field with the provider default as placeholder and the existing
     "paste a full API address is fine" caption.
6. Footer caption explaining that this one configuration is shared by every AI feature
   (context menu translate/summarize/explain today; screenshot summary, completion,
   checklist later). Localized.

Behavior details:
- Changing the service resets the model and the fetched list; for presets set
  `endpoint = provider.endpoint` and `baseURL = ""` (meaning "provider default"); for
  `.custom` keep the current endpoint/base URL editable.
- Editing the base URL produces `provider == .custom` automatically; the Advanced group
  must stay open in that case.
- Persist on every change (`AIConfiguration(...).save()`), as the current view does.
- The pane must not crash on a clean profile (registered defaults already exist).

### A5. AI catalog

Create `CotEditor/Localizables/AI/AI.xcstrings` with en + zh-Hans for every string in the
pane, provider labels/hints, endpoint labels/hints (the custom-protocol picker), AI action
titles (翻译 / 总结 / 说人话 ↔ Translate / Summarize / Explain), result-sheet buttons and
status strings (`替换选中`, `插入`, `拷贝`, `取消`, `正在请求「%@」…`, `「%@」没有完成`), and
every `AIError.errorDescription` message. Keep AI prompt bodies (systemPrompt) as-is —
they are instructions to the model, not UI.

Also localize `AIResultPanelController` (it currently hard-codes Chinese button titles and
status lines) using the same `AI` table.

## Track B — `inspector-lang`

Write scope: `CotEditor/Sources/Document Window/Inspector/DocumentInspectorView.swift`,
`CotEditor/Sources/Settings Window/Panes/GeneralSettingsView.swift`,
new `CotEditor/Sources/Application/AppLanguage.swift`,
new `CotEditor/Localizables/Application/Personal.xcstrings`.

### B1. Document inspector (file details)

Reference screenshot: the inspector currently shows *Text Settings* (文本设定: 编码/行尾/模式),
*Count* (计数: 行/字符/字), *Position* (位置/行/列). Required end state:

- Remove the whole Text Settings section and the `TextSettings` struct/observer plumbing
  (encoding, line endings, mode) from the view model and previews.
- Keep Count, but only the `CountType.countCases` rows (lines / characters / words). Drop the
  `positionCases` block entirely.
- Add a **File** section (disclosure, same styling as the other sections, included as the
  first section in the body) with exactly these four rows:
  1. 创建时间 / Created — `attributes.creationDate` formatted `.abbreviated` + `.shortened`
  2. 最后更新时间 / Last Modified — `attributes.modificationDate` likewise
  3. 复制文件路径 / Copy File Path — a row that copies `fileURL.path` to
     `NSPasteboard.general` when clicked; show brief confirmation feedback
     (checkmark + 已复制/Copied for ~1.5 s), disabled with no URL; `.help` with the path.
     Use a `Button` styled to sit as a form row (borderless/plain).
  4. 文件作者 / File Author — `attributes.owner`
- Missing values render as `Text.none` / the existing optional `LabeledContent` helpers.
  Untitled documents therefore show the section with empty values.
- Reuse `DocumentFileView` by rewriting it; do not leave dead code behind.
- Also remove the now-unused `TextSettingsView` and preview data for it.
- The section/row labels must be localized through the **`Personal`** table
  (`Personal.xcstrings`) so the Lead can check both languages. Do not edit the upstream
  `Document.xcstrings`.

### B2. Language setting

- New `AppLanguage` type (raw values `zh-Hans` and `en`):
  - `current`: read `UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first`;
    `zh*` → Simplified Chinese, everything else → English. (The app is currently pinned to
    `zh-Hans` in its own defaults; that key is also what makes the per-app language work.)
  - `apply()`: write `[rawValue]` to `AppleLanguages` in the app's preferences and
    synchronize.
  - Self-named labels: 简体中文 / English (not translated per current UI language).
- `GeneralSettingsView`: add a **Language** row at the top of the settings Grid
  (before "On startup:") with a menu-style `Picker`; label "语言：" / "Language:".
  Selecting another language applies it and shows a confirmation dialog: the change takes
  effect after restart, with **Restart Now** / **Later** buttons. Restart Now uses the
  existing app relaunch path: `(NSApp.delegate as? AppDelegate)?.needsRelaunch = true;
  NSApp.terminate(nil)` (see the Auto Save confirmation in the same file).
- Do not switch languages live inside the running process; the restart is intentional and
  must be explained in the dialog.
- All new strings go to the same `Personal` catalog (en + zh-Hans).

## Track C — `ui-strings`

Write scope: `CotEditor/Sources/Document Window/DocumentWindowController.swift`,
`CotEditor/Sources/Document Window/Content View/NavigationBar.swift`,
`CotEditor/Sources/Document Window/Text View/EditorTextView.swift`,
`CotEditor/Sources/Models/Highlight/TextHighlight.swift`,
`CotEditor/Sources/Document Window/Content View/DocumentViewController.swift`,
`CotEditor/Sources/Application/AppDelegate.swift`,
and the new catalog `CotEditor/Localizables/Application/Chrome.xcstrings`.
Do not touch AI files, the inspector, the General settings pane, or `CUSTOM.md`.

Goal: with the app switched to English, the custom chrome added by this fork must not show
Chinese. Enumerate every hard-coded user-visible Chinese string in the files above
(`rg -n '[\p{Han}]' <file>`) and replace it with a localized string in the `Chrome` table
(en + zh-Hans), e.g.:

```swift
NSMenuItem(title: String(localized: "chrome.more", defaultValue: "More", table: "Chrome"), …)
```

Scope highlights (walk the files, there may be more):

- `DocumentWindowController`: toolbar labels/tooltips (text scale, emoji, more, AI, terminal),
  the 更多 menu, the 外观 submenu (跟随系统/浅色/深色), emoji section titles
  (进度/优先级/状态/标记/流程), the pinned-tab alert, the AI settings toolbar tooltip.
- `NavigationBar`: tab context menu (固定标签页/取消固定/关闭标签页), tooltips
  (已固定…/关闭标签页/新建标签页).
- `EditorTextView`: context menu — AI actions (翻译/总结/说人话), 拷贝/粘贴/全部选择,
  清除高亮.
- `TextHighlight`: the five color names (黄色/绿色/蓝色/粉色/橙色) — these are shown in the
  context menu and must follow the UI language.
- `DocumentViewController`: the "AI not configured" alert (message, informative text,
  打开 AI 设置/取消) and the pinned-tab alert.
- `AppDelegate`: the three menu items that this fork added to the storyboard with Chinese
  Base titles — `重命名…` (action `moveDocument:`), `向下分割`
  (`splitEditorHorizontally:`), `向右分割` (`splitEditorVertically:`). The storyboard's Base
  localization is English, so a Chinese Base title would leak into English UI. Set those
  three titles programmatically in `prepareMainMenu()` from the `Chrome` table (find the
  items by action selector, or by searching the File/View menus) so both languages get the
  right title. Do not edit the storyboard or its string catalog.
- Leave comments/doc comments and `GeneratedDocumentName`'s Chinese name pool alone (the
  made-up document names are an intentional Chinese feature; do not translate them).

For interpolated strings use a format key with `%@` (or `String(localized:)` with
`String(format:)`) so both languages stay grammatical.

## Reporting (each track)

When done, report to the Lead: files changed, the public API you added, the catalog
file/keys you created, anything you could not do, and any integration risk. The Lead runs
the real build; expect a follow-up if the compiler disagrees.
