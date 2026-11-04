#!/bin/bash
#
# Rebuild, install and — crucially — leave exactly ONE copy of the editor on the system.
#
# Double-click this file in Finder, or run either of:
#
#   ./install.command            # build + install + clean + relaunch
#   ./install.command --check    # report only, change nothing
#
# Build products go to Xcode's default DerivedData (~/Library/Developer/Xcode/DerivedData),
# which Spotlight does not index. Never build into the repository: a .app inside the
# desktop folder shows up in Spotlight/Launchpad as a second, stale copy of the editor.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Cot"
TARGET="/Applications/${APP_NAME}.app"
BUNDLE_IDS=("local.cmy.Cot" "com.coteditor.CotEditor")
MODE="${1:-install}"

find_installs() {
    mdfind "kMDItemKind == 'Application'" 2>/dev/null \
        | grep -Ei "/(cot|coteditor)[^/]*\.app$" \
        | sort -u
}

echo "== 当前系统中的编辑器副本 =="
CURRENT="$(find_installs || true)"
echo "${CURRENT:-(无)}"

if [[ "$MODE" == "--check" ]]; then
    COUNT=$(printf "%s\n" "$CURRENT" | grep -c "\.app$" || true)
    if [[ "$COUNT" == "1" && -d "$TARGET" ]]; then
        echo "✅ 只有一个副本：$TARGET"
    else
        echo "⚠️  副本数量：$COUNT（应为 1，且位于 $TARGET）"
    fi
    exit 0
fi

echo
echo "== 1/4 构建 =="
cd "$REPO"
xcodebuild -project CotEditor.xcodeproj -scheme CotEditor -configuration Release \
    -destination 'platform=macOS' -skipPackagePluginValidation build \
    | tail -3

PRODUCT="$(ls -dt ~/Library/Developer/Xcode/DerivedData/CotEditor-*/Build/Products/Release/CotEditor.app 2>/dev/null | head -1)"
[[ -d "$PRODUCT" ]] || { echo "找不到构建产物"; exit 1; }

echo
echo "== 2/4 安装到 $TARGET =="
pkill -f "${TARGET}/Contents/MacOS/CotEditor" 2>/dev/null || true
rm -rf "$TARGET"
ditto "$PRODUCT" "$TARGET"
codesign --verify --deep --strict "$TARGET"
echo "签名 OK"

# Delete the build product: a .app left in DerivedData is indexed by Spotlight and
# shows up in Spotlight/Launchpad as a second, stale copy of the editor.
rm -rf "$PRODUCT"
echo "已删除构建产物副本"

echo
echo "== 3/4 清理其它副本（移到废纸篓，可恢复） =="
mkdir -p "$HOME/.Trash"
while IFS= read -r app; do
    [[ -z "$app" ]] && continue
    [[ "$app" == "$TARGET" ]] && continue
    [[ -d "$app" ]] || continue
    # skip anything that is not our editor
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null || echo "")
    if [[ " ${BUNDLE_IDS[*]} " == *" $id "* ]]; then
        dest="$HOME/.Trash/$(basename "$app" .app)-$(date +%Y%m%d-%H%M%S).app"
        mv "$app" "$dest"
        echo "已移动：$app -> $dest"
    fi
done <<< "$CURRENT"

echo
echo "== 4/4 验证 =="
FINAL=""
for _ in $(seq 1 20); do
    FINAL="$(find_installs || true)"
    [[ "$FINAL" == "$TARGET" ]] && break
    sleep 1
done

COUNT=$(printf "%s\n" "$FINAL" | grep -c "\.app$" || true)
echo "${FINAL:-(无)}"

if [[ "$COUNT" == "1" && "$FINAL" == "$TARGET" ]]; then
    echo "✅ 现在系统里只有一个编辑器：$TARGET"
elif [[ "$COUNT" == "1" && -d "$TARGET" ]]; then
    echo "⚠️  磁盘上只有 $TARGET，但 Spotlight 仍报另一个路径（索引尚未刷新，稍等即可）"
else
    echo "⚠️  仍有 $COUNT 个副本，请检查上面的列表"
    exit 1
fi

open "$TARGET"
echo "已启动。"
