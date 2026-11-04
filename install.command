#!/bin/bash
#
# 双击这个文件（或在终端里 ./install.command）即可：构建 → 安装 → 清理旧副本 → 校验 → 重启。
# 加 --check 只体检、不改动。
#
exec "$(cd "$(dirname "$0")" && pwd)/Scripts/install-personal.sh" "$@"
