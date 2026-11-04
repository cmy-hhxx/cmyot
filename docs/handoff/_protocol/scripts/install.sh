#!/usr/bin/env bash
# install.sh — 把接力协议装进一个 git 仓库
# 用法: bash install.sh /path/to/repo
set -euo pipefail

src=$(cd "$(dirname "$0")/.." && pwd)
dst=${1:-}

if [ -z "$dst" ]; then
  echo "用法: bash install.sh /path/to/repo"; exit 2
fi
if [ ! -d "$dst" ]; then
  echo "✗ 目录不存在: $dst"; exit 2
fi
if [ ! -d "$dst/.git" ]; then
  echo "! 警告: $dst 看起来不是 git 仓库根目录（没有 .git/），继续安装..."
fi

target="$dst/docs/handoff/_protocol"
mkdir -p "$target/prompts" "$target/templates" "$target/scripts"

cp "$src/README.md" "$src/PROTOCOL.md" "$src/QUICKSTART.md" "$src/TRACK-UI.md" "$src/TRACK-ARCH.md" "$src/THINKING.md" "$target/"
cp "$src"/prompts/*.md "$target/prompts/"
cp "$src"/templates/*.md "$target/templates/"
cp "$src"/scripts/* "$target/scripts/"
mkdir -p "$target/examples" && cp -R "$src/examples/." "$target/examples/"
chmod +x "$target/scripts/gate.sh" "$target/scripts/install.sh" 2>/dev/null || true

cat <<EOF

✓ 已安装到 $target/
  README.md       选方向 + 选模式 + 分工 + 安装
  QUICKSTART.md   共享准备 + 两条轨道入口 + 门速查 + 故障排查
  TRACK-UI.md     UI 轨道 runbook（动效 / UI / 展示）
  TRACK-ARCH.md   ARCH 轨道 runbook（架构 / bug / 性能）
  PROTOCOL.md     协议正文（规则与门）
  THINKING.md     为什么这样设计
  prompts/        P0~P3 四份可直接粘贴的 prompt
  templates/      BRIEF / DESIGN / HANDOFF 模板
  scripts/        gate.sh · handoff.env.example · stills.mjs · still-pause.js
  examples/       填好的 DESIGN / HANDOFF 示例

下一步（按顺序做）:
  cd $dst

  1) 填门命令（每个仓库一次）
     cp docs/handoff/_protocol/scripts/handoff.env.example docs/handoff/_protocol/handoff.env
     \$EDITOR docs/handoff/_protocol/handoff.env
     source docs/handoff/_protocol/handoff.env
     eval "\$TYPECHECK_CMD" && eval "\$BUILD_CMD"     # 这一步就是 G0

  2) 提交
     git add docs/handoff && git commit -m "chore: 安装 Opus→DeepSeek 接力协议"

  3) 读 docs/handoff/_protocol/QUICKSTART.md（共享准备），再按方向读：
     UI   → docs/handoff/_protocol/TRACK-UI.md
     ARCH → docs/handoff/_protocol/TRACK-ARCH.md

  4) 开第一个任务（按方向拷模板）：
     git switch -c feat/<slug>
     mkdir -p docs/handoff/<slug>
     # UI:
     cp docs/handoff/_protocol/templates/{BRIEF,DESIGN,HANDOFF}.md docs/handoff/<slug>/
     # ARCH:
     cp docs/handoff/_protocol/templates/{CODEBASE,AUDIT,ARCH,REFACTOR}.md docs/handoff/<slug>/
EOF
