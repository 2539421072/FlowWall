#!/bin/bash
set -euo pipefail

# 流光壁纸 FlowWall 构建脚本（Objective-C / AppKit）
# 用法: ./build.sh [debug|release]

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

MODE="${1:-release}"
APP_NAME="流光壁纸"
EXEC_NAME="FlowWall"
BUNDLE="$ROOT/build/$APP_NAME.app"
ICON_SRC="$ROOT/Resources/AppIcon.png"
SDK="$(xcrun --show-sdk-path)"

if [ "$MODE" = "debug" ]; then
  OPT=(-O0 -g)
else
  OPT=(-O2)
fi

echo "==> 清理"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> 编译 ($MODE, SDK: $SDK)"
clang \
  -fobjc-arc -fblocks \
  "${OPT[@]}" \
  -mmacosx-version-min=13.0 \
  -isysroot "$SDK" \
  -Wall -Wno-deprecated-declarations \
  -framework Cocoa \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework QuartzCore \
  -framework ServiceManagement \
  -framework UniformTypeIdentifiers \
  -framework ImageIO \
  -o "$BUNDLE/Contents/MacOS/$EXEC_NAME" \
  Sources/*.m

echo "==> 组装 App 包"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

if [ -f "$ICON_SRC" ]; then
  echo "==> 生成 icns"
  ICONSET="$ROOT/build/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
    d=$((s * 2))
    sips -z $d $d "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns" || true
  rm -rf "$ICONSET"
fi

echo "==> 签名（ad-hoc）"
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || echo "   签名跳过"

echo "==> 完成: $BUNDLE"
/usr/bin/du -sh "$BUNDLE"
