#!/usr/bin/env bash
#
# build.sh - 编译 sing-box（官方 tag + 追加 with_v2ray_api），产出单平台二进制
#
# 用法:
#   build.sh <src_dir> <goos> <goarch> <goarm> <out_bin> <version> [extra_tags]
#
# 示例:
#   build.sh src linux amd64 ""  dist/sing-box 1.15.0-cf.1
#   build.sh src linux arm   "7" dist/sing-box 1.15.0-cf.1
#   build.sh src linux arm64 ""  dist/sing-box 1.15.0-cf.1 "with_v2ray_api,with_musl"
#
# 说明:
#   - 基础 tags 取自 <src_dir>/release/DEFAULT_BUILD_TAGS_OTHERS（与官方非 naive 构建一致）
#   - 默认额外追加 with_v2ray_api：面板按用户统计流量必需；官方 release 未包含该 tag，
#     缺少它时配置里只要出现 experimental.v2ray_api 就会 FATAL 起不来
#   - ldflags 取自 <src_dir>/release/LDFLAGS，并注入 constant.Version（不带 v 前缀，与官方输出一致）
#   - 同时生成 BUILD-INFO.txt（上游 tag/commit + tags + 编译命令），供打包与 GPL 合规留存
#
set -euo pipefail

SRC="${1:?用法: build.sh <src_dir> <goos> <goarch> <goarm> <out_bin> <version> [extra_tags]}"
GOOS_="${2:?缺少 goos}"
GOARCH_="${3:?缺少 goarch}"
GOARM_="${4:-}"
OUT="${5:?缺少 out_bin}"
VERSION="${6:?缺少 version}"
EXTRA_TAGS="${7-with_v2ray_api}"

[ -d "$SRC" ] || { echo "ERROR: 源码目录不存在: $SRC" >&2; exit 1; }
[ -f "$SRC/release/DEFAULT_BUILD_TAGS_OTHERS" ] || {
  echo "ERROR: 找不到 $SRC/release/DEFAULT_BUILD_TAGS_OTHERS（源码目录不对？）" >&2
  exit 1
}

# ---------- tags ----------
BASE_TAGS="$(cat "$SRC/release/DEFAULT_BUILD_TAGS_OTHERS")"
TAGS="$BASE_TAGS"
if [ -n "$EXTRA_TAGS" ]; then
  TAGS="${TAGS},${EXTRA_TAGS}"
fi

# ---------- ldflags ----------
LDFLAGS_SHARED="$(cat "$SRC/release/LDFLAGS" 2>/dev/null || true)"
LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=${VERSION}"
if [ -n "$LDFLAGS_SHARED" ]; then
  LDFLAGS="${LDFLAGS} ${LDFLAGS_SHARED}"
fi
LDFLAGS="${LDFLAGS} -s -w -buildid="

# ---------- 输出路径（绝对化，便于 cd 后引用）----------
mkdir -p "$(dirname "$OUT")"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT_ABS="$OUT_DIR/$(basename "$OUT")"

echo "==> [build] GOOS=$GOOS_ GOARCH=$GOARCH_ GOARM=${GOARM_:-none} VERSION=$VERSION"
echo "==> [build] tags: $TAGS"

(
  cd "$SRC"
  # 与上游 Makefile 一致：禁止隐式下载 toolchain，保证可复现
  export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
  export CGO_ENABLED=0
  export GOOS="$GOOS_"
  export GOARCH="$GOARCH_"
  if [ -n "$GOARM_" ]; then export GOARM="$GOARM_"; fi
  go build -v -trimpath -o "$OUT_ABS" -tags "$TAGS" -ldflags "$LDFLAGS" ./cmd/sing-box
)

[ -f "$OUT_ABS" ] || { echo "ERROR: 编译未产生产物 $OUT_ABS" >&2; exit 1; }
chmod 0755 "$OUT_ABS"

# ---------- BUILD-INFO.txt（合规 + 可复现）----------
UPSTREAM_TAG="${UPSTREAM_TAG:-$(git -C "$SRC" describe --tags --abbrev=0 2>/dev/null || echo unknown)}"
UPSTREAM_COMMIT="${UPSTREAM_COMMIT:-$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)}"
GO_VER="$(go version 2>/dev/null || echo unknown)"

{
  echo "sing-box 第三方自定义构建（非官方）"
  echo "==============================================="
  echo "上游仓库     : https://github.com/SagerNet/sing-box"
  echo "上游 tag     : ${UPSTREAM_TAG}"
  echo "上游 commit  : ${UPSTREAM_COMMIT}"
  echo "目标平台     : ${GOOS_}/${GOARCH_}${GOARM_:+/armv${GOARM_}}"
  echo "版本字符串   : ${VERSION}"
  echo "build tags   : ${TAGS}"
  echo "编译工具链   : ${GO_VER}"
  echo "CGO_ENABLED  : 0"
  echo "编译命令     : cd <source> && CGO_ENABLED=0 GOOS=${GOOS_} GOARCH=${GOARCH_} \\"
  echo "                 go build -trimpath -tags \"${TAGS}\" \\"
  echo "                 -ldflags \"${LDFLAGS}\" ./cmd/sing-box"
  echo "构建时间     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "构建来源     : ${GITHUB_SERVER_URL:-local}/${GITHUB_REPOSITORY:-local} run=${GITHUB_RUN_ID:-local}"
  echo ""
  echo "许可与合规"
  echo "-----------------------------------------------"
  echo "本二进制由 GPL-3.0-or-later 许可的 sing-box 源码编译而来，未修改上游源码；"
  echo "对应源码即上述上游仓库的 ${UPSTREAM_TAG}（commit ${UPSTREAM_COMMIT}），"
  echo "可按上面的编译命令自行复现，以便满足 GPLv3 关于提供对应源码的要求。"
  echo "本产物为第三方非官方构建，与 SagerNet / sing-box 项目无隶属或背书关系；"
  echo "按上游 LICENSE 附加条款，不得以 sing-box 名义暗示官方关联或用于产品命名。"
  echo "再分发本产物须随附 LICENSE 与源码获取方式。"
} > "$OUT_DIR/BUILD-INFO.txt"

echo "==> [build] 产物: $OUT_ABS ($(du -h "$OUT_ABS" | cut -f1))"
echo "==> [build] 说明: $OUT_DIR/BUILD-INFO.txt"
