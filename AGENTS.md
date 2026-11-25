# CotEditor Engineering & Design Contract

This repository enforces a strict engineering, UI/UX, performance, and formal verification contract. Every AI coding agent and contributor must follow these standards without exception.

## 1. Core Engineering Pillars
Great code in this repository always has three traits:
1. **结构清晰 (Clear Structure)**: Single-file view bloat or 300-line monolith functions are unacceptable. Decompose state, domain services, and UI subviews cleanly with shallow nesting.
2. **职责明确 (Explicit Responsibilities)**: Separate pure offline logic/parsers/layout engines (`nonisolated`, deterministic, unit-testable) from `@MainActor` observable state and SwiftUI presentation.
3. **运行高效 (High Runtime Speed & Frame Rate)**:
   - Never instantiate `DateFormatter`, `NumberFormatter`, `ByteCountFormatter`, or `NSRegularExpression` inside SwiftUI `var body:` or inside loops (`static let` once).
   - Never run synchronous file I/O (`Data(contentsOf:)`, `String(contentsOf:)`) on the main thread inside `var body:`.
   - Use `@ObservationIgnored` + coalesced timers / `requestAnimationFrame` on high-frequency streaming paths; avoid `AnyView` type erasure.

## 2. UI / UX / Typography / Motion Standards (Apple-Native Restraint)
- **Zero Tiny Explainers (严禁小字解释)**: Never add unsolicited tutorial copy, "点击即可…", "提示：…", or multi-sentence prose inside small (`<= 11.5pt`, `.caption`, `.footnote`) labels or empty states. Labels should be self-evident through layout hierarchy.
- **Concise Placeholders & Zero Emojis**: Placeholders must be crisp (`"搜索"` rather than `"搜索全文关键词（支持空格多词 · ⌘F）"`). Never put emojis (`✨`, `🚀`, `💡`, etc.) in UI buttons or headers.
- **Zero Cheap SVGs & Cliché Icons**: Do not use `sparkles`, `wand.and.stars`, `point.3.connected.*`, `brain`, or oversized (`>= 22pt`) decorative empty-state icons. Prefer clean macOS typography or restrained standard utility glyphs (`magnifyingglass`, `chevron.left`).
- **No Blue Hover Rings or Twitchy Motion**:
  - Card hover feedback must use neutral hairline strokes (`hairlineStrong`) and subtle surface tinting — never blue accent borders (`accentFill` / `Color.blue`) or blue glow shadows.
  - Never jump card coordinates or scale rings on hover (`.offset(y: isHovered ? -1.5 : 0)` / `.scaleEffect(isHovered ? ...)`), and never double-stack `withAnimation` inside `.onHover` with `.animation(..., value: isHovered)`.
- **Typography & Tabular Digits**: Dynamic counters, timestamps, prices, and percentages must use `.monospacedDigit()` and readable sizes (`>= 9.5pt`).

## 3. Sandbox & Networking Safety
- Unit tests under `Tests/` must NEVER read hardcoded `/Users/<name>/Desktop` or `/Users/<name>/Downloads` directories; synthesize temp files in `FileManager.default.temporaryDirectory`.
- Market clients must never use unstable `push2delay.eastmoney.com` or `push2.eastmoney.com` endpoints.

## 4. Mandatory Pre-Delivery Formal Verification Gate
Before presenting **any** code change as complete, you **MUST** run the formal verification gate:

```bash
./Scripts/verify.sh
```

For fast inner-loop checks during editing:
```bash
./Scripts/verify.sh --quick
```

If any `[ERROR]` is reported by `Scripts/formal-verify.py` or `Tests/FormalVerificationTests` fails, you must **rework the code immediately** and re-run until `./Scripts/verify.sh` exits `0`. Suppressing a rule is allowed only for genuine non-UI false positives using the documented syntax with an explicit reason:
```swift
// formal-verify: allow(<RULE_ID>): <concrete explanation>
```
