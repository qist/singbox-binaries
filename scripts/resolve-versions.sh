#!/usr/bin/env bash
#
# resolve-versions.sh - 解析"要构建哪些版本"，并生成 build / release 的 matrix
#
# 设计目标：一次可以构建多个版本（面板的版本列表需要可切换的历史版本），
#          已发布过的版本自动跳过，避免重复消耗 CI。
#
# 输入（环境变量）:
#   VERSIONS           显式版本列表（逗号/空格/换行分隔，如 "v1.14.0,v1.13.0"）；留空=按 VERSION_COUNT 自动取
#   VERSION_COUNT      自动取上游最近 N 个 release，默认 3
#   INCLUDE_PRERELEASE 自动模式下是否含预发布（alpha/beta/rc），默认 true
#   TAG_SUFFIX         发布 tag 后缀，默认 -cf.1（__none__ 或空 = 与上游一致）
#   FORCE_BUILD        true = 已发布也重建
#   UPSTREAM_REPO      上游仓库，默认 SagerNet/sing-box
#   SELF_REPO          本仓库（用于查已发布），默认 $GITHUB_REPOSITORY
#   PLATFORMS_FILE     平台定义，默认 <repo>/config/platforms.json
#   RELEASES_JSON      本地测试用：直接提供上游 release 列表 JSON，跳过 gh 调用
#   SKIP_EXISTS_CHECK  本地测试用：=1 时跳过"是否已发布"检查
#
# 输出（stdout，GITHUB_OUTPUT 格式，单行值）:
#   should_build / versions / extra_tags / build_matrix / release_matrix
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSIONS="${VERSIONS:-}"
VERSION_COUNT="${VERSION_COUNT:-3}"
# 数值兜底（输入可能是空串或非数字）
case "$VERSION_COUNT" in
  ''|*[!0-9]*) VERSION_COUNT=3 ;;
esac
if [ "$VERSION_COUNT" -lt 1 ]; then VERSION_COUNT=1; fi
INCLUDE_PRERELEASE="${INCLUDE_PRERELEASE:-true}"
TAG_SUFFIX="${TAG_SUFFIX:--cf.1}"
FORCE_BUILD="${FORCE_BUILD:-false}"
UPSTREAM_REPO="${UPSTREAM_REPO:-SagerNet/sing-box}"
SELF_REPO="${SELF_REPO:-${GITHUB_REPOSITORY:-}}"
PLATFORMS_FILE="${PLATFORMS_FILE:-$REPO_ROOT/config/platforms.json}"
EXTRA_TAGS="${EXTRA_TAGS:-with_v2ray_api}"
MAX_VERSIONS="${MAX_VERSIONS:-10}"

if [ "$TAG_SUFFIX" = "__none__" ]; then TAG_SUFFIX=""; fi
# 允许"只用官方 tag 集"（不追加任何额外 tag）
if [ "$EXTRA_TAGS" = "__none__" ]; then EXTRA_TAGS=""; fi

[ -f "$PLATFORMS_FILE" ] || { echo "ERROR: 找不到平台定义 $PLATFORMS_FILE" >&2; exit 1; }

log() { echo "[resolve] $*" >&2; }

# 兜底输出（保证各 key 始终存在，避免下游 fromJSON 报错）
emit_empty() {
  echo "should_build=false"
  echo "versions="
  echo "extra_tags=${EXTRA_TAGS}"
  echo "build_matrix=[]"
  echo "release_matrix=[]"
}

# ---------------------------------------------------------------------------
# 1. 确定候选版本列表
# ---------------------------------------------------------------------------
CANDIDATES=""
if [ -n "${VERSIONS// /}" ]; then
  CANDIDATES="$(printf '%s' "$VERSIONS" | tr ',;' '  ' | tr -s ' \t\n' ' ')"
  log "使用显式版本列表: $CANDIDATES"
else
  if [ -n "${RELEASES_JSON:-}" ]; then
    JSON="$RELEASES_JSON"
  else
    JSON="$(gh release list --repo "$UPSTREAM_REPO" --limit 50 --json tagName,isPrerelease)"
  fi
  if [ "$INCLUDE_PRERELEASE" = "true" ]; then
    # 默认策略：最近 (N-1) 个（不限预发布）+ 最新 1 个正式版。
    # 原因：上游连续发 alpha 时，若纯按时间取 N 个会永远取不到正式版，
    #       而面板需要"最新尝鲜 + 稳定可用"两类版本。
    HEAD_N="$VERSION_COUNT"
    if [ "$VERSION_COUNT" -ge 2 ]; then HEAD_N=$((VERSION_COUNT - 1)); fi
    PART1="$(echo "$JSON" | jq -r '.[].tagName' | head -n "$HEAD_N")"
    PART2="$(echo "$JSON" | jq -r '.[] | select(.isPrerelease == false) | .tagName' | head -n 1)"
    CANDIDATES="$(printf '%s\n%s\n' "$PART1" "$PART2" | awk 'NF && !seen[$0]++' | head -n "$VERSION_COUNT" | tr '\n' ' ' | tr -s ' ')"
    log "自动选择（最近 $HEAD_N 个 + 最新正式版）: $CANDIDATES"
  else
    CANDIDATES="$(echo "$JSON" | jq -r '.[] | select(.isPrerelease == false) | .tagName' | head -n "$VERSION_COUNT" | tr '\n' ' ' | tr -s ' ')"
    log "自动选择最近 $VERSION_COUNT 个正式版: $CANDIDATES"
  fi
fi

CANDIDATES="$(printf '%s' "$CANDIDATES" | xargs || true)"
[ -n "$CANDIDATES" ] || { log "未解析到任何上游版本"; emit_empty; exit 0; }

# 上限保护：避免 matrix 爆炸（版本数 × 平台数）
COUNT_NOW="$(printf '%s\n' "$CANDIDATES" | wc -w | tr -d ' ')"
if [ "$COUNT_NOW" -gt "$MAX_VERSIONS" ]; then
  log "WARN: 版本数 $COUNT_NOW 超过上限 $MAX_VERSIONS，仅取前 $MAX_VERSIONS 个"
  CANDIDATES="$(printf '%s\n' "$CANDIDATES" | tr ' ' '\n' | head -n "$MAX_VERSIONS" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# 2. 过滤掉已发布过的版本（force=true 时不过滤）
# ---------------------------------------------------------------------------
PENDING=""
for v in $CANDIDATES; do
  tag="${v}${TAG_SUFFIX}"
  if [ "$FORCE_BUILD" != "true" ] && [ "${SKIP_EXISTS_CHECK:-}" != "1" ] && [ -n "$SELF_REPO" ]; then
    if gh release view "$tag" --repo "$SELF_REPO" >/dev/null 2>&1; then
      log "跳过（已发布）: $tag"
      continue
    fi
  fi
  PENDING="$PENDING $v"
done
PENDING="$(printf '%s' "$PENDING" | xargs || true)"

if [ -z "$PENDING" ]; then
  log "所有候选版本均已发布，无需构建"
  emit_empty
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. 生成 matrix（版本 × 平台 的笛卡尔积）
# ---------------------------------------------------------------------------
VS_JSON="$(printf '%s\n' $PENDING | jq -R . | jq -sc .)"

BUILD_MATRIX="$(jq -cn --argjson p "$(cat "$PLATFORMS_FILE")" --argjson vs "$VS_JSON" --arg suffix "$TAG_SUFFIX" '
  [ $p[] as $pl | $vs[] as $v
    | ($v + $suffix) as $t
    | $pl + {
        version: $v,
        release_tag: $t,
        asset_version: ($t | ltrimstr("v"))
      } ]')"

RELEASE_MATRIX="$(jq -cn --argjson vs "$VS_JSON" --arg suffix "$TAG_SUFFIX" '
  [ $vs[] as $v
    | ($v + $suffix) as $t
    | { version: $v,
        release_tag: $t,
        asset_version: ($t | ltrimstr("v")),
        is_prerelease: (if ($t | test("-alpha|-beta|-rc|-dev")) then "true" else "false" end) } ]')"

PLATFORM_COUNT="$(jq 'length' "$PLATFORMS_FILE")"
VERSION_COUNT_FINAL="$(printf '%s\n' $PENDING | wc -w | tr -d ' ')"
log "待构建版本: $PENDING"
log "任务数: ${VERSION_COUNT_FINAL} 版本 × ${PLATFORM_COUNT} 平台 = $((VERSION_COUNT_FINAL * PLATFORM_COUNT)) 个 job"

echo "should_build=true"
echo "versions=${PENDING}"
echo "extra_tags=${EXTRA_TAGS}"
echo "build_matrix=${BUILD_MATRIX}"
echo "release_matrix=${RELEASE_MATRIX}"
