#!/usr/bin/env bash
# gate.sh — Opus→DeepSeek 接力协议的验收门（双轨道）
#
# 用法:
#   TRACK=ui   TASK_DIR=docs/handoff/hero-motion bash gate.sh G1
#   TRACK=arch TASK_DIR=docs/handoff/order-refactor BASE_TAG=baseline/order-refactor bash gate.sh G2
#
# 可选环境变量:
#   TRACK           ui（默认）/ arch
#   BASE_TAG        基线 tag（G2/G3 必填，G1 可留空）
#   TYPECHECK_CMD   如 "pnpm -s typecheck"
#   BUILD_CMD       如 "pnpm -s build"
#   TEST_CMD        如 "pnpm -s test --run"（ARCH 轨道必填）
#   ARCH_CHECK_CMD  如 "pnpm -s arch:check"（ARCH 轨道：依赖方向/无环/边界）
#   API_CHECK_CMD   如 "pnpm -s api:check"（ARCH 轨道：公共 API 兼容性，可选）
#   STILLS_URL      如 "http://localhost:5173"（仅 UI 轨道；需要 playwright）
#   TOKEN_HINTS     令牌文件/目录的正则，默认 "tokens|theme|tailwind"（仅 UI 轨道）
#
# 退出码: 0 全绿 / 1 有失败项
set -uo pipefail

LEVEL="${1:-G2}"
TRACK="${TRACK:-ui}"
TASK_DIR="${TASK_DIR:-}"
BASE_TAG="${BASE_TAG:-}"
TOKEN_HINTS="${TOKEN_HINTS:-tokens|theme|tailwind}"
fail=0

GATE_DIR=$(cd "$(dirname "$0")" && pwd)

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail+1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

# 自动加载本仓库的门命令，避免忘了 source 导致「静默全绿」
if [ -f "$GATE_DIR/../handoff.env" ]; then
  # shellcheck disable=SC1091
  . "$GATE_DIR/../handoff.env"
  ok "已加载 handoff.env"
fi

case "$TRACK" in
  ui)   H="$TASK_DIR/HANDOFF.md";  D="$TASK_DIR/DESIGN.md" ;;
  arch) H="$TASK_DIR/REFACTOR.md"; D="$TASK_DIR/ARCH.md" ;;
  *) echo "✗ TRACK 只能是 ui 或 arch（当前: $TRACK）"; exit 1 ;;
esac

echo "== 门 $LEVEL · 方向 $TRACK · ${TASK_DIR:-<TASK_DIR 未设置>} =="

# ---------- 0. 基本文件 ----------
if [ -z "$TASK_DIR" ]; then
  bad "需要设置 TASK_DIR（如 docs/handoff/hero-motion）"
  echo "结果: ✗ 无法继续"; exit 1
fi
[ -f "$H" ] && ok "$(basename "$H")" || bad "缺 $H"
[ -f "$D" ] && ok "$(basename "$D")" || bad "缺 $D"
if [ "$TRACK" = "arch" ] && [ ! -f "$TASK_DIR/CODEBASE.md" ]; then
  warn "缺 $TASK_DIR/CODEBASE.md（P0 测绘产物；体检模式必须有）"
fi

# ---------- 1. 基线 tag ----------
if [ -n "$BASE_TAG" ] && git rev-parse -q --verify "refs/tags/$BASE_TAG" >/dev/null 2>&1; then
  ok "基线 tag $BASE_TAG 存在"
  CHANGED=$( { git diff --name-only "$BASE_TAG" 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } | sort -u )
  n=$(printf '%s\n' "$CHANGED" | grep -c . || true)
  ok "自基线以来改了 $n 个文件"
  [ "$n" -eq 0 ] && warn "自基线以来没有文件变动（是不是还没开始改，或忘了 git add？）"
else
  if [ "$LEVEL" = "G1" ]; then
    warn "未设置 BASE_TAG（G1 允许；交接前记得 git tag baseline/<slug>）"
  else
    bad "需要 BASE_TAG 且该 tag 存在（$LEVEL 要用它查 FROZEN / 新依赖）"
  fi
  CHANGED=""
fi

# ---------- 2. FROZEN 未被修改 ----------
if [ -n "$CHANGED" ] && [ -f "$H" ]; then
  FROZEN=$(awk '/^## /{ if ($0 ~ /FROZEN/) {f=1; next} else if (f) exit } f' "$H" \
           | grep -o '`[^`]*`' | tr -d '`' | sort -u)
  if [ -z "$FROZEN" ]; then
    warn "$(basename "$H") 没有 FROZEN 清单（强烈建议补）"
  else
    hit=0
    for f in $FROZEN; do
      if printf '%s\n' "$CHANGED" | grep -qF -- "$f"; then
        bad "FROZEN 被修改: $f"
        hit=1
      fi
    done
    [ "$hit" -eq 0 ] && ok "FROZEN 清单未被触碰（$(printf '%s\n' "$FROZEN" | grep -c .) 项）"
  fi
fi

# ---------- 3. 没有偷偷加依赖 ----------
if [ -n "$CHANGED" ]; then
  for mf in package.json; do
    if printf '%s\n' "$CHANGED" | grep -qx "$mf"; then
      if command -v node >/dev/null 2>&1; then
        NEW=$(node -e '
          const {execSync} = require("child_process");
          const fs = require("fs");
          const [base, file] = process.argv.slice(1);
          const read = (o) => { try { return typeof o === "string" ? JSON.parse(o) : o; } catch { return {}; } };
          let oldPkg = {}, newPkg = {};
          try { oldPkg = read(execSync(`git show ${base}:${file}`, {encoding:"utf8"})); } catch {}
          try { newPkg = read(fs.readFileSync(file, "utf8")); } catch {}
          const secs = ["dependencies","devDependencies","peerDependencies","optionalDependencies"];
          const out = [];
          for (const s of secs) {
            const o = oldPkg[s] || {}, n = newPkg[s] || {};
            for (const k of Object.keys(n)) if (o[k] !== n[k]) out.push(`${s}: ${k}@${n[k]}`);
            for (const k of Object.keys(o)) if (!(k in n)) out.push(`${s}: -${k}`);
          }
          if (out.length) console.log(out.join("\n"));
        ' "$BASE_TAG" "$mf" 2>/dev/null)
      else
        NEW=$(git diff "$BASE_TAG" -- "$mf" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+')
      fi
      if [ -n "$NEW" ]; then
        bad "$mf 有依赖变动（需要显式授权）:"
        printf '%s\n' "$NEW" | head -10 | sed 's/^/      /'
      else
        ok "$mf 无新增依赖"
      fi
    fi
  done
fi

# ---------- 3.5 / 4. UI 轨道专属：Never 规则 + 裸值 ----------
if [ "$TRACK" = "ui" ] && [ -n "$CHANGED" ]; then
  never=""
  for f in $CHANGED; do
    case "$f" in *.css|*.scss|*.less|*.ts|*.tsx|*.js|*.jsx|*.vue|*.svelte) ;; *) continue ;; esac
    [ -f "$f" ] || continue
    h=$(grep -nE 'transition:[^;]*\ball\b|!important' "$f" 2>/dev/null | head -2)
    [ -n "$h" ] && never="$never
    $f: $h"
  done
  [ -n "$never" ] && warn "命中 DESIGN 的 Never 规则（transition:all / !important），确认不是本次引入:$never"

  raw=""
  for f in $CHANGED; do
    case "$f" in
      *.css|*.scss|*.less|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.vue|*.svelte|*.html) ;;
      *) continue ;;
    esac
    [ -f "$f" ] || continue
    printf '%s' "$f" | grep -qE "$TOKEN_HINTS" && continue
    hits=$(grep -nE '#[0-9a-fA-F]{3,8}\b' "$f" 2>/dev/null | grep -vE "$TOKEN_HINTS" | head -3)
    [ -n "$hits" ] && raw="$raw
    $f:
$hits"
  done
  if [ -n "$raw" ]; then
    warn "发现 tokens 之外的裸颜色值（确认是否违规）:$raw"
  else
    ok "改动文件内无裸颜色值"
  fi
fi

# ---------- 5. TODO 状态（两轨道通用，文件不同） ----------
if [ -f "$H" ]; then
  todo=$(grep -cE '\|[[:space:]]*todo[[:space:]]*\|' "$H" || true)
  doing=$(grep -cE '\|[[:space:]]*doing[[:space:]]*\|' "$H" || true)
  done_n=$(grep -cE '\|[[:space:]]*done[[:space:]]*\|' "$H" || true)
  blocked=$(grep -cE '\|[[:space:]]*blocked[[:space:]]*\|' "$H" || true)
  needs=$(grep -cE '\|[[:space:]]*NEEDS-OPUS[[:space:]]*\|' "$H" || true)
  echo "  i TODO: done=$done_n doing=$doing todo=$todo blocked=$blocked NEEDS-OPUS=$needs"
  [ "$blocked" -gt 0 ] && warn "有 $blocked 条 blocked，交付前必须逐条裁决"
  if [ "$LEVEL" = "G3" ]; then
    [ "$todo" -gt 0 ]    && bad "G3 要求 TODO 清零，还剩 $todo 条 todo"
    [ "$doing" -gt 0 ]   && bad "G3 要求没有 doing 状态的条目，还剩 $doing 条"
    [ "$blocked" -gt 0 ] && bad "G3 要求 blocked 清零，还剩 $blocked 条（裁决后改 done 或 dropped）"
    [ "$needs" -gt 0 ]   && bad "G3 要求 NEEDS-OPUS 清零，还剩 $needs 条（裁决后改 done 或 dropped）"
  fi
  if [ "$needs" -gt 8 ]; then
    warn "NEEDS-OPUS 有 $needs 条（>8）→ 规范和参照实现不够，下轮把 Opus 切点上移"
  fi
fi

# ---------- 6. 仓库状态 ----------
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$dirty" -eq 0 ]; then ok "工作区干净"; else warn "工作区有 $dirty 处未提交改动（打 tag 前应干净）"; fi

# ---------- 7. 自定义命令 ----------
run_cmd() {
  local label="$1" cmd="$2"
  [ -z "$cmd" ] && return 0
  echo "  ▸ $label: $cmd"
  if eval "$cmd" >"/tmp/gate-$label.log" 2>&1; then
    ok "$label 通过"
  else
    bad "$label 失败（日志 /tmp/gate-$label.log，尾部 5 行）:"
    tail -5 "/tmp/gate-$label.log" | sed 's/^/      /'
  fi
}

if [ "$TRACK" = "arch" ]; then
  if [ -z "${TEST_CMD:-}" ]; then
    bad "ARCH 轨道必须设置 TEST_CMD（没有测试就没有重构的安全网）"
  else
    run_cmd test "${TEST_CMD}"
  fi
  [ -z "${ARCH_CHECK_CMD:-}" ] && warn "未设置 ARCH_CHECK_CMD：依赖方向 / 无环 / 边界规则没有机器检查"
  [ -n "${ARCH_CHECK_CMD:-}" ] && run_cmd arch-check "${ARCH_CHECK_CMD}"
  [ -z "${API_CHECK_CMD:-}" ] && warn "未设置 API_CHECK_CMD：公共 API 兼容性靠人工看"
  [ -n "${API_CHECK_CMD:-}" ] && run_cmd api-check "${API_CHECK_CMD}"
  run_cmd typecheck "${TYPECHECK_CMD:-}"
  run_cmd build "${BUILD_CMD:-}"
else
  if [ -z "${TYPECHECK_CMD:-}${BUILD_CMD:-}${TEST_CMD:-}" ]; then
    warn "没有设置 TYPECHECK_CMD / BUILD_CMD / TEST_CMD（是不是忘了 source handoff.env？）"
  fi
  run_cmd typecheck "${TYPECHECK_CMD:-}"
  run_cmd build "${BUILD_CMD:-}"
fi

# ---------- 8. UI 轨道专属：截图 / console error ----------
if [ "$TRACK" = "ui" ]; then
  if [ -n "${STILLS_URL:-}" ]; then
    if [ -f "$GATE_DIR/stills.mjs" ] && node -e "require.resolve('playwright')" >/dev/null 2>&1; then
      echo "  ▸ stills: $STILLS_URL"
      if node "$GATE_DIR/stills.mjs" "$STILLS_URL" "$TASK_DIR/stills" >/tmp/gate-stills.log 2>&1; then
        ok "截图门通过（3 视口 · 两帧有差 · 无 console error）"
      else
        bad "截图门失败（日志 /tmp/gate-stills.log，尾部 15 行）:"
        tail -15 /tmp/gate-stills.log | sed 's/^/      /'
      fi
    else
      warn "跳过截图门：未安装 playwright（pnpm add -D playwright && npx playwright install chromium）"
    fi
  else
    warn "未设置 STILLS_URL：截图 / console error / 「主视效在动」检查全部被跳过"
  fi
fi

echo "== 结果: $([ "$fail" -eq 0 ] && echo '✓ 全绿' || echo "✗ $fail 项失败") =="
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
