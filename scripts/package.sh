#!/usr/bin/env bash
#
# package.sh - 打包 sing-box 产物（二进制 + LICENSE + BUILD-INFO.txt）
#
# 用法: package.sh <root> <binary> <version> <suffix> <fmt> <src_dir>
#   root    : 产物落地目录（CI 内一般为仓库根）
#   binary  : 已编译好的二进制路径（如 dist/sing-box）
#   version : 版本串（不含前导 v，如 1.15.0-cf.1）——直接用于文件名
#   suffix  : 平台后缀（如 linux-amd64 / linux-arm64 / linux-armv7 / darwin-arm64）
#   fmt     : tar.gz | zip
#   src_dir : sing-box 源码目录（用于取 LICENSE）
#
# 产物命名刻意与官方保持一致：
#   sing-box-<version>-<os>-<arch>.tar.gz  (Linux/macOS/FreeBSD)
#   sing-box-<version>-<os>-<arch>.zip     (Windows)
# 这样 CoreFusion 的 buildDownloadURL() 无需任何改动即可直接下载安装。
#
# 归档内二进制名必须保持 "sing-box"（Windows 为 sing-box.exe），
# 否则面板的 matchCoreBinary() 匹配不到（见 internal/service/binaries/installer.go）。
#
set -euo pipefail

ROOT="${1:?用法: package.sh <root> <binary> <version> <suffix> <fmt> <src_dir>}"
BIN="${2:?缺少 binary}"
VER="${3:?缺少 version}"
SUFFIX="${4:?缺少 suffix}"
FMT="${5:-tar.gz}"
SRC="${6:?缺少 src_dir}"

[ -f "$BIN" ] || { echo "ERROR: 找不到二进制 $BIN" >&2; exit 1; }

STAGE="$(mktemp -d)"
OUT_DIR="$STAGE/sing-box"
mkdir -p "$OUT_DIR"

# 二进制（保持官方命名 sing-box / sing-box.exe）
case "$SUFFIX" in
  windows-*) cp "$BIN" "$OUT_DIR/sing-box.exe" ;;
  *)         cp "$BIN" "$OUT_DIR/sing-box" ;;
esac

# LICENSE（GPLv3 要求随二进制分发；上游 release 也是这么做的）
if [ -f "$SRC/LICENSE" ]; then
  cp "$SRC/LICENSE" "$OUT_DIR/LICENSE"
else
  echo "WARN: 源码目录缺少 LICENSE，归档内不含许可证文件" >&2
fi

# BUILD-INFO.txt（由 build.sh 生成在二进制同目录）
if [ -f "$(dirname "$BIN")/BUILD-INFO.txt" ]; then
  cp "$(dirname "$BIN")/BUILD-INFO.txt" "$OUT_DIR/BUILD-INFO.txt"
fi

# 归档
ASSET="sing-box-${VER}-${SUFFIX}.${FMT}"
mkdir -p "$ROOT"
(
  cd "$STAGE"
  if [ "$FMT" = "zip" ]; then
    zip -r -q "$ROOT/$ASSET" sing-box
  else
    tar czf "$ROOT/$ASSET" sing-box
  fi
)
rm -rf "$STAGE"

echo "==> [package] 产物: $ROOT/$ASSET"
if command -v tar >/dev/null 2>&1 && [ "$FMT" = "tar.gz" ]; then
  echo "    内容:"; tar tzf "$ROOT/$ASSET" | sed 's/^/      /'
fi
