#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  printf '用法：GODOT_BIN=godot bash ios/build-plugin.sh <已生成头文件的 Godot 4.5.1 源码目录>\n' >&2
  exit 2
fi

project="$(cd "$(dirname "$0")/.." && pwd)"
godot="$(cd "$1" && pwd)"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$project/ios/plugins"

# 每次从笼子导出模型，使两个场景的外形和配色随同一份代码更新。
"${GODOT_BIN:-godot}" --headless --log-file "$work/export.log" --path "$project" \
  --script res://ios/export-hamsters.gd -- "$work"
(
  cd "$work"
  for model in HamsterGray HamsterWhite; do
    usdcat "$model.usda" -o "$model.usdc"
    usdzip -a "$model.usdc" "$model.usdz"
    usdchecker --arkit "$model.usdz"
  done
)

xcrun --sdk iphoneos swiftc -module-cache-path "$work/module-cache" -swift-version 5 -parse-as-library -whole-module-optimization -O \
  -sdk "$sdk" -target arm64-apple-ios16.0 -module-name HamsterARUI \
  -emit-object "$project/ios/native/HamsterAR.swift" -o "$work/HamsterAR.o"

for variant in debug release; do
  flags=()
  if [[ "$variant" == debug ]]; then
    flags=(-DDEBUG_ENABLED)
  fi
  # 保持与 Godot 导出模板一致。4.5.1 的调试头文件用 typeid 检查分配器，需要保留 RTTI。
  xcrun --sdk iphoneos clang++ -fmodules-cache-path="$work/module-cache" -std=c++17 -fno-exceptions -fobjc-arc \
    -isysroot "$sdk" -target arm64-apple-ios16.0 -I "$godot" -I "$godot/platform/ios" \
    -DAPPLE_EMBEDDED_ENABLED -DIOS_ENABLED -DUNIX_ENABLED -DPTRCALL_ENABLED \
    ${flags[@]+"${flags[@]}"} -c "$project/ios/native/hamster_bridge.mm" -o "$work/bridge.o"
  xcrun --sdk iphoneos clang++ -fmodules-cache-path="$work/module-cache" -std=c++17 -fobjc-arc \
    -isysroot "$sdk" -target arm64-apple-ios16.0 -I "$godot" -I "$godot/platform/ios" \
    -DAPPLE_EMBEDDED_ENABLED -DIOS_ENABLED -DUNIX_ENABLED -DPTRCALL_ENABLED \
    -c "$project/ios/native/scene_delegate.mm" -o "$work/scene_delegate.o"
  xcrun --sdk iphoneos libtool -static -o "$project/ios/plugins/HamsterAR.$variant.a" \
    "$work/bridge.o" "$work/scene_delegate.o" "$work/HamsterAR.o"
done
cp "$project/ios/native/HamsterAR.gdip" "$project/ios/plugins/HamsterAR.gdip"
install -m 644 "$work/HamsterGray.usdz" "$work/HamsterWhite.usdz" "$project/ios/plugins"
