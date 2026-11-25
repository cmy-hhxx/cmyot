#!/usr/bin/env python3
"""
CotEditor Formal Verification CLI (形式化验证工具)

Fast zero-dependency static verifier enforcing:
  1. UI/UX 极简与零小字解释 (UI_CLARITY)
  2. 零廉价 SVG 与装饰矢量 (SVG_CRAFT)
  3. 动效克制与排版精致 (MOTION_AND_TYPOGRAPHY)
  4. 结构清晰、职责明确、运行高效 (ARCHITECTURE_AND_PERF)

Suppression syntax (must include non-empty reason):
  // formal-verify: allow(<RULE_ID>): <reason>
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parent.parent

RULES: dict[str, tuple[str, str, str]] = {
    "NO_TINY_EXPLAINER": ("UI_CLARITY", "error", "Avoid tiny explanatory UI copy (<= 11.5pt/caption2/footnote prose)"),
    "NO_VERBOSE_PLACEHOLDER": ("UI_CLARITY", "error", "Keep input placeholders short and free of parenthetical tutorials"),
    "NO_EMOJI_IN_UI_CHROME": ("UI_CLARITY", "error", "Do not place decorative emojis in UI labels/buttons"),
    "NO_CHEAP_SF_SYMBOL": ("SVG_CRAFT", "error", "Avoid decorative/cliché SF Symbols in UI chrome"),
    "NO_CHEAP_INLINE_SVG": ("SVG_CRAFT", "error", "Avoid oversized or multi-primitive inline SVGs in WebUI"),
    "NO_DECORATIVE_EMPTY_ICON": ("SVG_CRAFT", "error", "Avoid oversized (>= 22pt) decorative empty-state icons"),
    "NO_BLUE_HOVER_RING": ("MOTION_AND_TYPOGRAPHY", "error", "Avoid cheap blue hover borders or accent glow shadows"),
    "NO_TWITCHY_HOVER_MOTION": ("MOTION_AND_TYPOGRAPHY", "error", "Avoid hover offset/scale jumps or double-stacked hover animations"),
    "TYPOGRAPHY_TABULAR_DIGITS": ("MOTION_AND_TYPOGRAPHY", "warning", "Use .monospacedDigit() on dynamic numeric readouts"),
    "TYPOGRAPHY_MIN_READABLE_SIZE": ("MOTION_AND_TYPOGRAPHY", "error", "Avoid unreadable micro-fonts (< 9.5pt / < 9px)"),
    "PERF_NO_FORMATTER_IN_BODY": ("ARCHITECTURE_AND_PERF", "error", "Never allocate Formatter/NSRegularExpression inside body or loops"),
    "PERF_NO_SYNC_IO_IN_BODY": ("ARCHITECTURE_AND_PERF", "error", "Never perform synchronous file I/O inside SwiftUI body"),
    "PERF_NO_ANYVIEW_ERASE": ("ARCHITECTURE_AND_PERF", "warning", "Prefer @ViewBuilder or concrete generics over AnyView"),
    "ARCH_FUNCTION_LENGTH": ("ARCHITECTURE_AND_PERF", "warning", "Keep functions concise (> 140 lines warn, > 260 lines error)"),
    "SAFETY_NO_BROKEN_ENDPOINTS_OR_SANDBOX_READ": ("ARCHITECTURE_AND_PERF", "error", "Block unstable endpoints and hardcoded Desktop/Downloads paths in Tests"),
}

ALLOW_RE = re.compile(r"formal-verify:\s*allow\((?P<rule>[A-Z0-9_]+)\)\s*:\s*(?P<reason>.+)")

EXPLAINER_PHRASES = (
    "点击即可",
    "点击上方",
    "你可以",
    "用于展示",
    "用于控制",
    "提示：",
    "说明：",
    "支持拖拽",
    "将自动",
    "会自动",
    "这里可以",
    "按空格",
    "空格多词",
    "Click to ",
    "You can ",
    "Tip:",
)

DECORATIVE_EMOJIS = ("✨", "🚀", "🔥", "💡", "🎉", "🤖", "📊", "📝", "⚡", "🌟", "💎", "🧠", "🎯")

CHEAP_SF_SYMBOLS = {
    "sparkles",
    "wand.and.stars",
    "wand.and.stars.inverse",
    "point.3.connected.trianglepath.dotted",
    "point.topleft.down.curvedto.point.bottomright.up",
    "brain",
    "brain.head.profile",
    "cpu",
    "cpu.fill",
    "lightbulb.max",
    "flame",
    "flame.fill",
    "bolt.circle",
    "bolt.circle.fill",
    "star.circle",
    "star.circle.fill",
    "lasso.badge.sparkles",
}

FORMATTER_CALL_RE = re.compile(
    r"\b(?:DateFormatter|ISO8601DateFormatter|NumberFormatter|ByteCountFormatter|NSRegularExpression)\s*\("
)
SYNC_IO_RE = re.compile(
    r"\b(?:Data|String)\s*\(\s*contentsOf:|FileManager\.default\.contentsOfDirectory\s*\(|NSImage\s*\(\s*contentsOfFile:"
)
FONT_SIZE_RE = re.compile(r"\.font\s*\(\s*\.system\s*\(\s*size:\s*([0-9]+(?:\.[0-9]+)?)")
TAILWIND_MICRO_RE = re.compile(r"\btext-\[(?:([0-9]+(?:\.[0-9]+)?)px)\]")
TAILWIND_TINY_PROSE_RE = re.compile(r"\btext-\[(?:9|9\.[0-9]+|10|10\.[0-9]+|11|11\.[0-9]+)px\]")
TEXT_LITERAL_RE = re.compile(r'\b(?:Text|Label|Button)\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
APP_LANG_LITERAL_RE = re.compile(r'AppLanguage\.text\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*,\s*en:\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
PLACEHOLDER_SWIFT_RE = re.compile(r'\b(?:TextField|SecureField)\s*\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
PLACEHOLDER_HTML_RE = re.compile(r'\bplaceholder\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
PLACEHOLDER_JSX_RE = re.compile(r'\bplaceholder\s*=\s*\{\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*\}')
SF_SYMBOL_RE = re.compile(r'\b(?:Image\s*\(\s*systemName:|systemImage:)\s*"([^"]+)"')
INTERPOLATION_RE = re.compile(r"\\\([^)]*\)")
CJK_RE = re.compile(r"[\u4e00-\u9fff]")
NUMERIC_VAR_HINT_RE = re.compile(
    r"(?:count|total|pct|percent|price|score|hits|remaining|duration|amount|peRatio|marketCap|turnover|zoomScale|words|chars|\.formatted\(|String\s*\(\s*format:)",
    re.IGNORECASE,
)
SWIFT_FUNC_DECL_RE = re.compile(
    r"^\s*(?:(?:private|fileprivate|internal|public|open|static|class|override|final|mutating|nonisolated|@MainActor|@ViewBuilder)\s+)*(?:func\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]+>)?\s*\(|var\s+(body)\s*:\s*some\s+View\b)"
)
TS_COMPONENT_DECL_RE = re.compile(
    r"^\s*(?:export\s+)?(?:function\s+([A-Z][A-Za-z0-9_]*)\s*\(|const\s+([A-Z][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*\()"
)
STRING_LITERAL_RE = re.compile(r'"([^"\\]*(?:\\.[^"\\]*)*)"')


@dataclass
class Finding:
    file: str
    line: int
    rule_id: str
    pillar: str
    severity: str
    message: str


def strip_inline_comment(line: str) -> str:
    in_str = False
    escaped = False
    i = 0
    while i < len(line):
        ch = line[i]
        if escaped:
            escaped = False
            i += 1
            continue
        if ch == "\\":
            escaped = True
            i += 1
            continue
        if ch == '"':
            in_str = not in_str
            i += 1
            continue
        if not in_str and ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            return line[:i]
        i += 1
    return line


def brace_delta(code_no_comment: str) -> int:
    # Strip double-quoted strings roughly so braces inside strings don't skew depth
    cleaned = STRING_LITERAL_RE.sub('""', code_no_comment)
    return cleaned.count("{") - cleaned.count("}")


def is_line_allowed(lines: list[str], line_idx_0: int, rule_id: str) -> bool:
    for probe in (line_idx_0, line_idx_0 - 1):
        if 0 <= probe < len(lines):
            m = ALLOW_RE.search(lines[probe])
            if m and m.group("rule") == rule_id and len(m.group("reason").strip()) >= 3:
                return True
    return False


def strip_interpolations(text: str) -> str:
    return INTERPOLATION_RE.sub("", text)


def looks_like_explainer_prose(raw_text: str) -> bool:
    plain = strip_interpolations(raw_text).strip()
    if not plain:
        return False
    for phrase in EXPLAINER_PHRASES:
        if phrase in plain:
            return True
    cjk_count = len(CJK_RE.findall(plain))
    if cjk_count >= 20:
        return True
    ascii_words = len([w for w in plain.split() if re.search(r"[A-Za-z]{2,}", w)])
    if len(plain) >= 65 and ascii_words >= 8:
        return True
    return False


def collect_file_scopes(lines: list[str], is_swift: bool) -> tuple[list[dict], list[tuple[str, int, int]]]:
    """Computes per-line brace depth, whether inside `var body` / loop, and enclosing function spans."""
    info: list[dict] = [{"depth": 0, "in_body": False, "in_loop": False} for _ in lines]
    depth = 0
    in_block_comment = False
    body_depth: int | None = None
    loop_depths: list[int] = []
    func_stack: list[tuple[str, int, int]] = []  # (name, start_line_1, entry_depth)
    func_spans: list[tuple[str, int, int]] = []

    for idx, raw in enumerate(lines):
        work = raw
        if in_block_comment:
            end = work.find("*/")
            if end == -1:
                info[idx] = {"depth": depth, "in_body": body_depth is not None, "in_loop": bool(loop_depths)}
                continue
            work = work[end + 2 :]
            in_block_comment = False

        while "/*" in work:
            s = work.find("/*")
            e = work.find("*/", s + 2)
            if e == -1:
                work = work[:s]
                in_block_comment = True
                break
            work = work[:s] + work[e + 2 :]

        code = strip_inline_comment(work)
        pre_depth = depth
        delta = brace_delta(code)
        inline_body = False
        inline_loop = False

        # Function & `var body` detection before updating depth
        if is_swift:
            if re.search(r"\bvar\s+body\s*:\s*some\s+View\b", code) and "{" in code:
                inline_body = True
                before_body = code.split("var", 1)[0]
                body_open_depth = pre_depth + brace_delta(before_body) + 1
                if pre_depth + delta >= body_open_depth:
                    body_depth = body_open_depth
            fm = SWIFT_FUNC_DECL_RE.match(code)
            if fm and "{" in code:
                fname = fm.group(1) or fm.group(2) or "func"
                if fname == "body" and body_depth is None:
                    body_depth = pre_depth + max(1, delta)
                if pre_depth + delta > pre_depth:
                    func_stack.append((fname, idx + 1, pre_depth))
        else:
            tm = TS_COMPONENT_DECL_RE.match(code)
            if tm and "{" in code and pre_depth + delta > pre_depth:
                cname = tm.group(1) or tm.group(2) or "Component"
                func_stack.append((cname, idx + 1, pre_depth))

        # Loop detection
        if re.search(r"\b(?:for|while|ForEach)\b", code) and "{" in code:
            inline_loop = True
            if pre_depth + delta > pre_depth:
                loop_depths.append(pre_depth)

        depth = max(0, pre_depth + delta)
        in_body_now = (body_depth is not None) or inline_body
        in_loop_now = bool(loop_depths) or inline_loop
        info[idx] = {"depth": depth, "in_body": in_body_now, "in_loop": in_loop_now}

        # Check closures
        if body_depth is not None and depth < body_depth:
            body_depth = None
        while loop_depths and depth <= loop_depths[-1]:
            loop_depths.pop()
        while func_stack and depth <= func_stack[-1][2]:
            fname, start_l, _ = func_stack.pop()
            func_spans.append((fname, start_l, idx + 1))

    return info, func_spans


def audit_file(
    rel_path: str,
    text: str,
    allowed_lines: set[int] | None,
    mode: str,
) -> list[Finding]:
    lines = text.splitlines()
    ext = Path(rel_path).suffix.lower()
    is_swift = ext == ".swift"
    is_webui_src = rel_path.startswith("WebUI/") and "/src/" in rel_path and ext in (".tsx", ".ts")
    is_test_file = rel_path.startswith("Tests/") or "/Tests/" in rel_path
    is_prod_ui = (rel_path.startswith("CotEditor/Sources/") and is_swift) or is_webui_src

    if not (is_swift or is_webui_src):
        return []

    findings: list[Finding] = []
    line_scopes, func_spans = collect_file_scopes(lines, is_swift=is_swift)

    def emit(line_1: int, rule_id: str, msg: str, severity_override: str | None = None) -> None:
        if allowed_lines is not None and line_1 not in allowed_lines:
            return
        if is_line_allowed(lines, line_1 - 1, rule_id):
            return
        pillar, default_sev, _ = RULES[rule_id]
        sev = severity_override or default_sev
        findings.append(
            Finding(
                file=rel_path,
                line=line_1,
                rule_id=rule_id,
                pillar=pillar,
                severity=sev,
                message=msg,
            )
        )

    # Track inline SVG blocks for WebUI
    if is_webui_src:
        in_svg = False
        svg_start_line = 0
        svg_lines: list[str] = []
        for idx, raw in enumerate(lines):
            line_1 = idx + 1
            if "<svg" in raw:
                in_svg = True
                svg_start_line = line_1
                svg_lines = [raw]
                if "</svg>" in raw:
                    in_svg = False
            elif in_svg:
                svg_lines.append(raw)
                if "</svg>" in raw:
                    in_svg = False
                else:
                    continue
            else:
                continue

            block = "\n".join(svg_lines)
            prim_count = len(re.findall(r"<(?:path|circle|rect|line|polygon|polyline|ellipse)\b", block))
            has_gradient = bool(re.search(r"<(?:linearGradient|radialGradient)\b", block))
            dim_match = re.search(r'(?:width|height)\s*=\s*["{]\s*([0-9]+)', block)
            tw_size_match = re.search(r'\b(?:size|w|h)-(?:([7-9]|[1-9][0-9]+)|\[([2-9][4-9]|[3-9][0-9]|[1-9][0-9]{2,})px\])', block)
            oversized = (dim_match and int(dim_match.group(1)) >= 24) or tw_size_match is not None
            if oversized or has_gradient or prim_count >= 7:
                emit(
                    svg_start_line,
                    "NO_CHEAP_INLINE_SVG",
                    f"Inline <svg> looks like custom/oversized decorative artwork (primitives={prim_count}); replace with native typography or Lucide/macOS symbol.",
                )

    for idx, raw in enumerate(lines):
        line_1 = idx + 1
        code = strip_inline_comment(raw)
        trimmed = code.strip()
        scope = line_scopes[idx]

        # Skip pure comments for pattern rules
        if not trimmed:
            continue

        # 15. SAFETY checks apply to production AND Tests
        if is_test_file:
            for m in STRING_LITERAL_RE.finditer(code):
                lit = m.group(1)
                if re.search(r"^/Users/[^/]+/(?:Desktop|Downloads)\b", lit):
                    emit(
                        line_1,
                        "SAFETY_NO_BROKEN_ENDPOINTS_OR_SANDBOX_READ",
                        "Tests must not read hardcoded ~/Desktop or ~/Downloads paths; synthesize fixtures in temporaryDirectory.",
                    )
            continue

        # Production source safety: broken Eastmoney endpoints in string literals
        if rel_path.startswith("CotEditor/Sources/") or is_webui_src:
            for m in STRING_LITERAL_RE.finditer(code):
                lit = m.group(1)
                if "push2delay.eastmoney.com" in lit or re.search(r"\bpush2\.eastmoney\.com\b", lit):
                    emit(
                        line_1,
                        "SAFETY_NO_BROKEN_ENDPOINTS_OR_SANDBOX_READ",
                        "Blocked unstable Eastmoney endpoint ('push2delay.eastmoney.com' / 'push2.eastmoney.com'); use verified gtimg/push2his cascade.",
                    )

        if not is_prod_ui:
            continue

        # 1. NO_TINY_EXPLAINER (SwiftUI & WebUI)
        if is_swift:
            window_after = "\n".join(lines[idx : min(len(lines), idx + 6)])
            is_tiny_font = False
            fm = FONT_SIZE_RE.search(window_after)
            if fm and float(fm.group(1)) <= 11.5:
                is_tiny_font = True
            elif re.search(r"\.font\s*\(\s*\.(?:caption2|footnote)\b", window_after):
                is_tiny_font = True
            elif re.search(r"\.font\s*\(\s*\.caption\b", window_after):
                is_tiny_font = True

            if is_tiny_font:
                texts_found: list[str] = []
                for m in TEXT_LITERAL_RE.finditer(code):
                    if code[m.start() : m.start() + 4] == "Text":
                        texts_found.append(m.group(1))
                for m in APP_LANG_LITERAL_RE.finditer(code):
                    texts_found.append(m.group(1))
                for lit in texts_found:
                    if looks_like_explainer_prose(lit):
                        emit(
                            line_1,
                            "NO_TINY_EXPLAINER",
                            f"Tiny UI font renders verbose/explanatory copy: \"{lit[:40]}\". Remove explainer prose.",
                        )
        else:
            if TAILWIND_TINY_PROSE_RE.search(raw):
                for m in re.finditer(r">([^<>{}\n]{6,})<", raw):
                    if looks_like_explainer_prose(m.group(1)):
                        emit(
                            line_1,
                            "NO_TINY_EXPLAINER",
                            f"Tiny JSX font renders explanatory copy: \"{m.group(1).strip()[:40]}\".",
                        )

        # 2. NO_VERBOSE_PLACEHOLDER
        placeholders: list[str] = []
        if is_swift:
            for m in PLACEHOLDER_SWIFT_RE.finditer(code):
                placeholders.append(m.group(1))
        else:
            for m in PLACEHOLDER_HTML_RE.finditer(code):
                placeholders.append(m.group(1))
            for m in PLACEHOLDER_JSX_RE.finditer(code):
                placeholders.append(m.group(1))
        for ph in placeholders:
            cjk_cnt = len(CJK_RE.findall(ph))
            if cjk_cnt >= 15 or len(ph) >= 38 or any(tok in ph for tok in ("（", "· ⌘", "空格多词", "例如：")):
                emit(
                    line_1,
                    "NO_VERBOSE_PLACEHOLDER",
                    f"Verbose placeholder text \"{ph[:36]}\". Use concise label like \"搜索\".",
                )

        # 3. NO_EMOJI_IN_UI_CHROME
        if is_swift:
            ui_lits = [m.group(1) for m in TEXT_LITERAL_RE.finditer(code)]
            if ".help(" in code:
                ui_lits.extend(STRING_LITERAL_RE.findall(code))
            for lit in ui_lits:
                if any(em in lit for em in DECORATIVE_EMOJIS):
                    emit(line_1, "NO_EMOJI_IN_UI_CHROME", f"Decorative emoji found in UI text: \"{lit[:32]}\".")
        else:
            if "<" in code and any(em in code for em in DECORATIVE_EMOJIS):
                emit(line_1, "NO_EMOJI_IN_UI_CHROME", "Decorative emoji found in WebUI JSX markup.")

        # 4. NO_CHEAP_SF_SYMBOL
        if is_swift:
            for m in SF_SYMBOL_RE.finditer(code):
                sym = m.group(1)
                if sym in CHEAP_SF_SYMBOLS:
                    emit(
                        line_1,
                        "NO_CHEAP_SF_SYMBOL",
                        f"Cheap/decorative SF Symbol \"{sym}\" found; replace with clean native typography or restraint symbol.",
                    )

        # 6. NO_DECORATIVE_EMPTY_ICON
        if is_swift and "Image(systemName:" in code:
            w = "\n".join(lines[idx : min(len(lines), idx + 4)])
            fm = FONT_SIZE_RE.search(w)
            if fm and float(fm.group(1)) >= 22.0:
                sev = "warning" if mode == "all" else "error"
                emit(
                    line_1,
                    "NO_DECORATIVE_EMPTY_ICON",
                    f"Oversized decorative SF Symbol icon ({fm.group(1)}pt); prefer calm Apple typography.",
                    severity_override=sev,
                )

        # 7. NO_BLUE_HOVER_RING
        if re.search(r"\b(?:isHovered|isHighlighted|isHover)\b", code):
            hover_win = "\n".join(lines[max(0, idx - 2) : min(len(lines), idx + 5)])
            if re.search(r"\b(?:accentFill|accentColor|Color\.blue|\.accent\b)\b", code):
                if re.search(r"\.(?:stroke|strokeBorder|shadow|overlay)\b", hover_win) or re.search(
                    r"(?:strokeColor|borderColor)\s*=", hover_win
                ):
                    emit(
                        line_1,
                        "NO_BLUE_HOVER_RING",
                        "Blue/accent hover border or shadow highlight detected; use neutral hairline instead.",
                    )
        if is_webui_src and re.search(r"hover:(?:border|ring)-(?:blue|sky|indigo|cyan)-", code):
            emit(line_1, "NO_BLUE_HOVER_RING", "Blue hover border/ring utility detected in WebUI.")

        # 8. NO_TWITCHY_HOVER_MOTION
        if is_swift:
            if re.search(r"\.offset\s*\([^)]*(?:isHovered|isHover)", code):
                emit(line_1, "NO_TWITCHY_HOVER_MOTION", "Twitchy hover .offset(...) jump detected; remove coordinate jump on hover.")
            if re.search(r"\.scaleEffect\s*\([^)]*(?:isHovered|isHover)", code):
                emit(line_1, "NO_TWITCHY_HOVER_MOTION", "Scale jump on hover (.scaleEffect) detected; keep hovered surfaces steady.")
            if ".onHover" in code:
                hover_block = "\n".join(lines[idx : min(len(lines), idx + 8)])
                around_block = "\n".join(lines[max(0, idx - 18) : min(len(lines), idx + 12)])
                if "withAnimation" in hover_block and re.search(
                    r"\.animation\s*\([^)]*value:\s*(?:self\.)?isHovered", around_block
                ):
                    emit(
                        line_1,
                        "NO_TWITCHY_HOVER_MOTION",
                        "Double-stacked hover animation (withAnimation inside .onHover + .animation(..., value: isHovered)).",
                    )

        # 9. TYPOGRAPHY_TABULAR_DIGITS (warning)
        if is_swift:
            for m in TEXT_LITERAL_RE.finditer(code):
                if code[m.start() : m.start() + 4] == "Text":
                    lit = m.group(1)
                    if "\\(" in lit and NUMERIC_VAR_HINT_RE.search(lit):
                        win = "\n".join(lines[idx : min(len(lines), idx + 7)])
                        if "monospacedDigit" not in win:
                            emit(
                                line_1,
                                "TYPOGRAPHY_TABULAR_DIGITS",
                                f"Numeric Text(\"{lit[:30]}\") should apply .monospacedDigit() to prevent layout jitter.",
                            )

        # 10. TYPOGRAPHY_MIN_READABLE_SIZE
        if is_swift:
            for fm in FONT_SIZE_RE.finditer(code):
                sz = float(fm.group(1))
                if sz < 9.5:
                    emit(line_1, "TYPOGRAPHY_MIN_READABLE_SIZE", f"Unreadable micro-font size ({sz}pt < 9.5pt).")
        else:
            for tm in TAILWIND_MICRO_RE.finditer(code):
                sz = float(tm.group(1))
                if sz < 9.0:
                    emit(line_1, "TYPOGRAPHY_MIN_READABLE_SIZE", f"Unreadable micro-font size ({sz}px < 9px).")

        # 11 & 12. Performance in SwiftUI body / loops
        if is_swift:
            if FORMATTER_CALL_RE.search(code) and (scope["in_body"] or scope["in_loop"]):
                emit(
                    line_1,
                    "PERF_NO_FORMATTER_IN_BODY",
                    "Formatter / NSRegularExpression instantiated inside SwiftUI body or loop; hoist to static let.",
                )
            if SYNC_IO_RE.search(code) and scope["in_body"]:
                emit(
                    line_1,
                    "PERF_NO_SYNC_IO_IN_BODY",
                    "Synchronous disk I/O inside SwiftUI body blocks main-thread rendering.",
                )
            if "AnyView(" in code:
                emit(
                    line_1,
                    "PERF_NO_ANYVIEW_ERASE",
                    "AnyView type erasure hurts SwiftUI structural diffing; prefer @ViewBuilder.",
                )

    # 14. ARCH_FUNCTION_LENGTH
    for fname, start_l, end_l in func_spans:
        span_len = end_l - start_l + 1
        if span_len <= 140:
            continue
        if allowed_lines is not None and not any(start_l <= ln <= end_l for ln in allowed_lines):
            continue
        sev = "error" if span_len > 260 else "warning"
        emit(
            start_l,
            "ARCH_FUNCTION_LENGTH",
            f"`{fname}` spans {span_len} lines ({'exceeds 260-line max' if sev == 'error' else 'exceeds 140-line guideline'}); extract crisp focused helpers.",
            severity_override=sev,
        )

    return findings


def git_changed_files_and_lines(staged: bool) -> dict[str, set[int] | None]:
    """Returns map of repo-relative path -> set of 1-based changed line numbers (None = whole untracked file)."""
    diff_cmd = ["git", "diff", "--unified=0", "--no-color"]
    if staged:
        diff_cmd.append("--cached")
    else:
        diff_cmd.append("HEAD")

    res = subprocess.run(diff_cmd, cwd=REPO_ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        res = subprocess.run(["git", "diff", "--unified=0", "--no-color"], cwd=REPO_ROOT, capture_output=True, text=True)

    changed: dict[str, set[int] | None] = {}
    current_file: str | None = None
    hunk_re = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")

    for line in res.stdout.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:].strip()
            changed.setdefault(current_file, set())
        elif line.startswith("+++ /dev/null"):
            current_file = None
        elif current_file and line.startswith("@@"):
            m = hunk_re.match(line)
            if m:
                start = int(m.group(1))
                count = int(m.group(2)) if m.group(2) else 1
                line_set = changed[current_file]
                if line_set is not None:
                    for ln in range(start, start + max(1, count)):
                        line_set.add(ln)

    if not staged:
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
        for rel in untracked.stdout.splitlines():
            rel = rel.strip()
            if rel and (rel.endswith(".swift") or rel.endswith(".ts") or rel.endswith(".tsx")):
                changed[rel] = None

    return changed


def collect_all_repo_files() -> list[str]:
    targets: list[str] = []
    for root_dir in (REPO_ROOT / "CotEditor" / "Sources", REPO_ROOT / "WebUI", REPO_ROOT / "Tests" / "Sources"):
        if not root_dir.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root_dir):
            dirnames[:] = [d for d in dirnames if d not in ("node_modules", "dist", ".build")]
            for fn in filenames:
                if fn.endswith((".swift", ".ts", ".tsx")):
                    full = Path(dirpath) / fn
                    targets.append(str(full.relative_to(REPO_ROOT)))
    targets.sort()
    return targets


def run_self_test() -> int:
    """Runs positive & negative fixtures for every rule to validate precision and zero regressions."""
    fixtures: list[tuple[str, str, str, bool]] = [
        # (filename, code, expected_rule, should_trigger)
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("点击即可开始使用这项非常棒的功能").font(.system(size: 11))', "NO_TINY_EXPLAINER", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("2026年11月").font(.system(size: 11.5))', "NO_TINY_EXPLAINER", False),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'TextField("搜索全文关键词（支持空格多词 · ⌘F）", text: $q)', "NO_VERBOSE_PLACEHOLDER", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'TextField("搜索", text: $q)', "NO_VERBOSE_PLACEHOLDER", False),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("✨ AI 生成")', "NO_EMOJI_IN_UI_CHROME", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("生成周报")', "NO_EMOJI_IN_UI_CHROME", False),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Image(systemName: "sparkles")', "NO_CHEAP_SF_SYMBOL", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Image(systemName: "magnifyingglass")', "NO_CHEAP_SF_SYMBOL", False),
        ("WebUI/beautiful-agent/src/Sample.tsx", 'export function Foo() { return <svg width="36" height="36"><path d="M0 0"/><circle r="1"/></svg>; }', "NO_CHEAP_INLINE_SVG", True),
        ("WebUI/beautiful-agent/src/Sample.tsx", 'export function Foo() { return <svg width="14" height="14"><rect x="3"/><rect x="14"/><rect y="14"/><rect x="14"/></svg>; }', "NO_CHEAP_INLINE_SVG", False),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Image(systemName: "doc").font(.system(size: 26))', "NO_DECORATIVE_EMPTY_ICON", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Image(systemName: "chevron.left").font(.system(size: 11))', "NO_DECORATIVE_EMPTY_ICON", False),
        ("CotEditor/Sources/Analytics/Sample.swift", '.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHovered ? palette.accentFill : palette.hairline))', "NO_BLUE_HOVER_RING", True),
        ("CotEditor/Sources/Analytics/Sample.swift", '.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isHighlighted ? hairlineStrong : hairline))', "NO_BLUE_HOVER_RING", False),
        ("CotEditor/Sources/Analytics/Sample.swift", '.offset(y: self.isHovered ? -1.5 : 0)', "NO_TWITCHY_HOVER_MOTION", True),
        ("CotEditor/Sources/Analytics/Sample.swift", '.scaleEffect(self.isHovered ? 1.04 : 1.0)', "NO_TWITCHY_HOVER_MOTION", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("共 \\(items.count) 篇").font(.system(size: 12))', "TYPOGRAPHY_TABULAR_DIGITS", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("共 \\(items.count) 篇").font(.system(size: 12).monospacedDigit())', "TYPOGRAPHY_TABULAR_DIGITS", False),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("x").font(.system(size: 8.5))', "TYPOGRAPHY_MIN_READABLE_SIZE", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'Text("x").font(.system(size: 11))', "TYPOGRAPHY_MIN_READABLE_SIZE", False),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'struct V: View { var body: some View { let fmt = DateFormatter(); return Text("a") } }', "PERF_NO_FORMATTER_IN_BODY", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'struct V: View { var body: some View { let _ = try? Data(contentsOf: url); return Text("a") } }', "PERF_NO_SYNC_IO_IN_BODY", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", 'func make() -> some View { AnyView(Text("a")) }', "PERF_NO_ANYVIEW_ERASE", True),
        ("Tests/Sources/Models/SampleTests.swift", 'let url = URL(filePath: "/Users/cmy/Desktop/test.txt")', "SAFETY_NO_BROKEN_ENDPOINTS_OR_SANDBOX_READ", True),
        ("CotEditor/Sources/Boards/Market/Client.swift", 'let s = "https://push2delay.eastmoney.com/api"', "SAFETY_NO_BROKEN_ENDPOINTS_OR_SANDBOX_READ", True),
        ("CotEditor/Sources/AI/UI/Sample.swift", '// formal-verify: allow(NO_CHEAP_SF_SYMBOL): intentional test fixture\nImage(systemName: "sparkles")', "NO_CHEAP_SF_SYMBOL", False),
    ]

    # Add ARCH_FUNCTION_LENGTH test (> 260 lines triggers error, > 140 lines triggers warning)
    long_body = "\n".join(["    let v = 1"] * 265)
    long_fn_code = f"func tooLongFunction() {{\n{long_body}\n}}\n"
    fixtures.append(("CotEditor/Sources/AI/UI/Sample.swift", long_fn_code, "ARCH_FUNCTION_LENGTH", True))

    failures: list[str] = []
    for idx, (rel_path, code, target_rule, should_trigger) in enumerate(fixtures):
        findings = audit_file(rel_path, code, None, mode="files")
        matched = [f for f in findings if f.rule_id == target_rule]
        if should_trigger and not matched:
            failures.append(f"Fixture #{idx} FAILED to trigger {target_rule}: {code[:60]}")
        elif not should_trigger and matched:
            failures.append(f"Fixture #{idx} FALSE POSITIVE for {target_rule}: {matched[0].message}")

    if failures:
        for fail in failures:
            print(f"[SELF-TEST FAIL] {fail}", file=sys.stderr)
        return 1

    print(f"[formal-verify] Self-test passed: {len(fixtures)}/{len(fixtures)} fixtures verified across {len(RULES)} rules.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="CotEditor Formal Verification CLI")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--diff", action="store_true", help="Verify modified/added lines in working tree vs HEAD (default)")
    group.add_argument("--staged", action="store_true", help="Verify staged lines in git index")
    group.add_argument("--files", nargs="+", help="Verify specific repo files in full")
    group.add_argument("--all", action="store_true", help="Audit all production and test files across repo")
    group.add_argument("--self-test", action="store_true", help="Run built-in rule test suite")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as errors")
    parser.add_argument("--json", action="store_true", help="Output findings as JSON")

    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    mode = "diff"
    file_line_map: dict[str, set[int] | None] = {}

    if args.files:
        mode = "files"
        for raw in args.files:
            p = Path(raw)
            rel = str(p.resolve().relative_to(REPO_ROOT)) if p.is_absolute() else raw.lstrip("./")
            file_line_map[rel] = None
    elif args.all:
        mode = "all"
        for rel in collect_all_repo_files():
            file_line_map[rel] = None
    elif args.staged:
        mode = "staged"
        file_line_map = git_changed_files_and_lines(staged=True)
    else:
        mode = "diff"
        file_line_map = git_changed_files_and_lines(staged=False)

    all_findings: list[Finding] = []
    checked_files = 0
    for rel, allowed_lines in sorted(file_line_map.items()):
        full = REPO_ROOT / rel
        if not full.is_file():
            continue
        checked_files += 1
        try:
            text = full.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        all_findings.extend(audit_file(rel, text, allowed_lines, mode=mode))

    if args.strict:
        for f in all_findings:
            if f.severity == "warning":
                f.severity = "error"

    errors = [f for f in all_findings if f.severity == "error"]
    warnings = [f for f in all_findings if f.severity == "warning"]

    if args.json:
        payload = {
            "mode": mode,
            "checkedFiles": checked_files,
            "errorCount": len(errors),
            "warningCount": len(warnings),
            "findings": [asdict(f) for f in all_findings],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        if all_findings:
            for f in all_findings:
                tag = "ERROR" if f.severity == "error" else "WARN "
                print(f"[{tag}] {f.file}:{f.line} [{f.rule_id}] {f.message}")
            print()

        by_rule: dict[str, int] = {}
        for f in all_findings:
            by_rule[f.rule_id] = by_rule.get(f.rule_id, 0) + 1
        summary = ", ".join(f"{k}={v}" for k, v in sorted(by_rule.items())) or "clean"
        print(
            f"[formal-verify] mode={mode} files={checked_files} errors={len(errors)} warnings={len(warnings)} ({summary})"
        )

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
