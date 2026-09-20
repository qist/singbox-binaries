#!/usr/bin/env bash
#
# verify.sh - 校验 sing-box 产物：静态校验（必做）+ 运行时校验（本机能跑才做）
#
# 用法: verify.sh <binary> [expected_version]
#
# 校验项:
#   1) 反向：stub 字符串 "v2ray api is not included in this build" 必须不存在
#      —— 该字符串只在 !with_v2ray_api 时编译进产物，出现即说明 tag 没生效
#   2) 正向：V2Ray StatsService 的 gRPC 服务名必须存在
#   3) 文件类型：ELF / Mach-O / PE 魔数
#   4) 运行时（本机可执行时）：`sing-box version` 输出 + 带 experimental.v2ray_api
#      的配置能通过 `sing-box check`（这是面板生成配置的前提）
#
set -euo pipefail

BIN="${1:?用法: verify.sh <binary> [expected_version]}"
EXPECT="${2:-}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ -f "$BIN" ] || fail "找不到产物: $BIN"

echo "==> [verify] 目标: $BIN ($(du -h "$BIN" | cut -f1))"

# ---------- 1) 反向校验 ----------
if grep -qa -- "v2ray api is not included in this build" "$BIN"; then
  fail "产物未包含 with_v2ray_api（命中 stub 字符串），构建参数有误"
fi
echo "    [OK] 未命中 v2ray_api stub 字符串 → tag 已生效"

# ---------- 2) 正向校验 ----------
grep -qa -- "v2ray.core.app.stats.command.StatsService" "$BIN" \
  || fail "未找到 V2Ray StatsService 符号，产物可疑"
echo "    [OK] 找到 v2ray.core.app.stats.command.StatsService"

# ---------- 3) 文件类型 ----------
MAGIC="$(head -c 4 "$BIN" | od -An -tx1 | tr -d ' \n')"
case "$MAGIC" in
  7f454c46)      echo "    [OK] ELF (Linux)" ;;
  feedface|feedfacf|cefaedfe|cffaedfe|cafebabe|cafebabf) echo "    [OK] Mach-O (macOS)" ;;
  4d5a*)         echo "    [OK] PE (Windows)" ;;
  *)             fail "未知可执行文件魔数: $MAGIC" ;;
esac

# ---------- 4) 运行时校验（跨平台/跨架构自动跳过）----------
if "$BIN" version >/tmp/sb-verify-version.txt 2>/dev/null; then
  echo "    [OK] version 输出: $(head -1 /tmp/sb-verify-version.txt)"
  if [ -n "$EXPECT" ]; then
    grep -q -- "$EXPECT" /tmp/sb-verify-version.txt \
      || fail "version 输出中未找到期望版本字符串: $EXPECT"
    echo "    [OK] 版本字符串匹配: $EXPECT"
  fi

  cat > /tmp/sb-verify-config.json <<'EOF'
{
  "log": {"level": "info", "timestamp": true},
  "experimental": {
    "v2ray_api": {
      "listen": "127.0.0.1:10086",
      "stats": {"enabled": true, "inbounds": ["in-1"], "users": ["verify@test"]}
    }
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-1",
      "listen": "0.0.0.0",
      "listen_port": 10443,
      "users": [{"name": "verify@test", "uuid": "bf000d23-0752-40b4-affe-68f7707a9661"}]
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}],
  "route": {"rules": [{"action": "sniff"}, {"inbound": ["in-1"], "outbound": "direct"}]}
}
EOF
  if "$BIN" check -c /tmp/sb-verify-config.json >/dev/null 2>&1; then
    echo "    [OK] 含 experimental.v2ray_api 的配置通过 sing-box check"
  else
    "$BIN" check -c /tmp/sb-verify-config.json || true
    fail "含 experimental.v2ray_api 的配置未能通过 check"
  fi
else
  echo "    [SKIP] 本机无法执行该产物（跨平台/跨架构），跳过运行时校验"
fi

echo "==> [verify] 通过"
