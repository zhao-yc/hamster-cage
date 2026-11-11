#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 ]]; then
  printf '用法：bash ios/build-plugin.sh <已生成头文件的 Godot 4.5.1 源码目录>\n' >&2
  exit 2
fi

project="$(cd "$(dirname "$0")/.." && pwd)"
godot="$(cd "$1" && pwd)"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
work="$(mktemp -d)"
trap 'rm -f "$work/HamsterAR.o" "$work/bridge.o"; rmdir "$work"' EXIT
mkdir -p "$project/ios/plugins"

xcrun --sdk iphoneos swiftc -swift-version 5 -parse-as-library -whole-module-optimization -O \
  -sdk "$sdk" -target arm64-apple-ios16.0 -module-name HamsterARUI \
  -emit-object "$project/ios/native/HamsterAR.swift" -o "$work/HamsterAR.o"

for variant in debug release; do
  flags=()
  if [[ "$variant" == debug ]]; then
    flags=(-DDEBUG_ENABLED)
  fi
  # 原生桥的对象布局必须与对应的 Godot 导出模板一致。
  xcrun --sdk iphoneos clang++ -std=c++17 -fno-exceptions -fno-rtti -fobjc-arc \
    -isysroot "$sdk" -target arm64-apple-ios16.0 -I "$godot" -I "$godot/platform/ios" \
    -DAPPLE_EMBEDDED_ENABLED -DIOS_ENABLED -DUNIX_ENABLED -DPTRCALL_ENABLED \
    ${flags[@]+"${flags[@]}"} -c "$project/ios/native/hamster_bridge.mm" -o "$work/bridge.o"
  xcrun --sdk iphoneos libtool -static -o "$project/ios/plugins/HamsterAR.$variant.a" \
    "$work/bridge.o" "$work/HamsterAR.o"
done
cp "$project/ios/native/HamsterAR.gdip" "$project/ios/plugins/HamsterAR.gdip"
