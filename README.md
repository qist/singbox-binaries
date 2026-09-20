# sing-box Binaries (with_v2ray_api)

[![Build Status](https://github.com/qist/singbox-binaries/actions/workflows/build.yml/badge.svg)](https://github.com/qist/singbox-binaries/actions/workflows/build.yml)

预编译的 sing-box 二进制，**在官方 build tags 基础上追加 `with_v2ray_api`**，用于 CoreFusion 面板按订阅用户统计流量。

打包与发布流程参照本组织既有仓库：[qist/caddy-binaries](https://github.com/qist/caddy-binaries)、[qist/nginx-binaries](https://github.com/qist/nginx-binaries)。

---

## 为什么需要这个仓库

上游官方 release **一律不包含 `with_v2ray_api`**：其 CI（`.github/workflows/build.yml`、`linux.yml`、`docker.yml`）统一使用 `release/DEFAULT_BUILD_TAGS` / `DEFAULT_BUILD_TAGS_OTHERS`，这两个文件里没有该 tag。缺少它时，只要配置里出现 `experimental.v2ray_api`，sing-box 就会直接启动失败：

```
FATAL[0000] create v2ray-server: v2ray api is not included in this build, rebuild with -tags with_v2ray_api
```

而面板的计费链路只能用这条通道：

| 统计通道 | 能否按订阅用户出账 | 说明 |
|---|---|---|
| `experimental.v2ray_api` | ✅ | `StatsService` 提供 `user>>>name>>>traffic>>>uplink/downlink`，与 xray stats 协议同名，面板可直接复用现有 gRPC 客户端，且支持 `reset_` 取增量 |
| `experimental.clash_api` | ❌ | `/connections` 的 JSON 里**不暴露 user 字段**，无法按用户聚合 |
| nftables 兜底 | ⚠️ | 面板侧 `SubscriptionIPTracker` 目前未建表/base chain，计数器不生效；且只能按源 IP 近似 |

> 实测对照（同源码、同 tag 组合，仅差 `with_v2ray_api`）：
> - 不带该 tag：`sing-box check -c 带v2ray_api的配置` → `FATAL ... v2ray api is not included in this build`（exit 1）
> - 带该 tag：同一配置 → check 通过（exit 0）

因此本仓库的产物**不是"更好的 sing-box"**，而是"能跑面板计费的 sing-box"。

## 与官方 release 的差异

| 项 | 官方 release | 本仓库产物 |
|---|---|---|
| build tags | `release/DEFAULT_BUILD_TAGS_OTHERS` | 同上，**追加 `with_v2ray_api`** |
| 源码 | 上游 tag | **完全相同的上游源码，未做任何修改** |
| 版本字符串 | `1.15.0` | `1.15.0-cf.1`（可配置，见下） |
| 产物命名 | `sing-box-<ver>-<os>-<arch>.tar.gz` | **保持一致**（面板无需改动即可使用） |

## 支持平台

| 操作系统 | 架构 | 文件格式 |
|----------|------|----------|
| Linux | amd64 | `.tar.gz` |
| Linux | arm64 | `.tar.gz` |
| Linux | armv7 | `.tar.gz` |
| Linux | 386 | `.tar.gz` |
| macOS | amd64 / arm64 | `.tar.gz` |
| FreeBSD | amd64 | `.tar.gz` |
| Windows | amd64 / arm64 | `.zip` |

> 服务端场景只需 Linux amd64 / arm64（含 armv7 低配 VPS）；其余平台为兼容保留，可在 `.github/workflows/build.yml` 的 matrix 里裁剪。

## 压缩包内容

```
sing-box-1.15.0-cf.1-linux-amd64.tar.gz
└── sing-box/
    ├── sing-box          # 二进制（Windows 为 sing-box.exe）
    ├── LICENSE           # 上游 GPLv3 许可证原文
    └── BUILD-INFO.txt    # 上游 tag/commit、build tags、完整编译命令、合规说明
```

> 归档内二进制名必须保持 `sing-box`：面板安装器的 `matchCoreBinary()` 按该名字匹配归档条目，改名会导致解压后找不到二进制。

## 使用方式

### 1. 面板直接安装（推荐，零后端改动）

面板的二进制安装接口本就支持直传下载地址：

```bash
curl -X POST "$PANEL/api/v1/node-servers/<id>/binaries/install" \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
        "core_type": "singbox",
        "version": "1.15.0-cf.1",
        "download_url": "https://github.com/qist/singbox-binaries/releases/download/v1.15.0-cf.1/sing-box-1.15.0-cf.1-linux-amd64.tar.gz",
        "asset_name": "sing-box-1.15.0-cf.1-linux-amd64.tar.gz"
      }'
```

> `download_url` 必须是**绝对 URL**（该接口没有像 Agent 自更新那样的相对路径解析）。

### 2. 让面板版本列表指向本仓库

`internal/service/binaries/installer.go` 的 `githubRepo()` 目前把 `singbox` 硬编码为上游 `SagerNet/sing-box`。把它改成 `qist/singbox-binaries` 后，前端"版本列表 / 切换版本"即可列出自建版本，且因为**产物命名与官方一致**，`buildDownloadURL()` 无需其他改动。

### 3. 手工安装

```bash
curl -L -o sb.tar.gz https://github.com/qist/singbox-binaries/releases/download/v1.15.0-cf.1/sing-box-1.15.0-cf.1-linux-amd64.tar.gz
tar -xzf sb.tar.gz
install -m 0755 sing-box/sing-box /usr/local/bin/sing-box
sing-box version          # => sing-box version 1.15.0-cf.1
```

## 校验产物（重要）

```bash
# 反向校验：未包含 with_v2ray_api 的产物会带这条 stub 字符串（期望 0）
strings -a sing-box | grep -c "v2ray api is not included in this build"

# 正向校验：V2Ray StatsService 的 gRPC 服务名（期望 >= 1）
strings -a sing-box | grep -c "v2ray.core.app.stats.command.StatsService"

# 端到端：带 experimental.v2ray_api 的配置必须能通过 check
./sing-box check -c config-with-v2ray-api.json
```

CI 的 `scripts/verify.sh` 会执行上述全部校验（含运行时 `check`），任一失败即终止发布，避免把"没有效果"的产物发出去。

## 自动构建说明（支持多版本）

**一次构建多个版本**：面板的版本列表需要可切换的历史版本，因此 CI 默认就构建上游最近 3 个 release（已发布过的自动跳过），而不是只打最新一个。

```
resolve（定版本列表 + 生成 matrix）
      │  versions × platforms 笛卡尔积
      ▼
build（matrix：每个"版本+平台"一个 job，各自编译 + verify + 打包）
      ▼
release（matrix：每个版本独立创建一个 Release + checksums）
```

| 触发方式 | 行为 |
|---|---|
| 每日 01:00 UTC 定时 | 自动取上游最近 `version_count`（默认 3）个 release，**只构建尚未发布过的**，逐个补齐 |
| 手动 `workflow_dispatch` | 可显式指定版本列表、数量、是否含预发布、后缀、额外 tags、强制重建 |

### workflow_dispatch 参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `versions` | *(空)* | 显式版本列表，逗号分隔，如 `v1.14.2,v1.14.1`；留空=自动按 `version_count` 取 |
| `version_count` | `3` | 自动模式取上游最近 N 个 release |
| `include_prerelease` | `true` | 自动模式是否包含 alpha/beta/rc |
| `tag_suffix` | `-cf.1` | 发布 tag 后缀；填 `__none__` 则与上游 tag 完全一致 |
| `extra_tags` | `with_v2ray_api` | 追加的 build tags；填 `__none__` 则只用官方 tag 集 |
| `force_build` | `false` | 已发布的版本也强制重建 |

### 示例

```bash
# 默认：构建最近 3 个版本（含预发布），跳过已发布
gh workflow run build.yml

# 构建指定的历史版本
gh workflow run build.yml -f versions="v1.15.0-alpha.4,v1.14.2,v1.14.1"

# 只构建最近 2 个正式版
gh workflow run build.yml -f version_count=2 -f include_prerelease=false

# 强制重建某个版本
gh workflow run build.yml -f versions="v1.14.2" -f force_build=true
```

> 任务数 = 版本数 × 平台数（默认 9）；脚本内置上限（`MAX_VERSIONS`，默认 10）防止 matrix 爆炸。
> 平台清单集中在 [`config/platforms.json`](config/platforms.json)，增删平台只改这一个文件。

发布 tag 默认带 `-cf.1` 后缀，用于与官方 tag 区分；`tag_suffix=__none__` 可生成与上游完全一致的 tag 与产物名（drop-in 替换场景）。

## 本地构建

```bash
git clone --depth 1 --branch v1.15.0-alpha.4 https://github.com/SagerNet/sing-box.git src

# 用法: build.sh <src_dir> <goos> <goarch> <goarm> <out_bin> <version> [extra_tags]
UPSTREAM_TAG=v1.15.0-alpha.4 \
  bash scripts/build.sh src linux amd64 "" dist/sing-box 1.15.0-alpha.4-cf.1 with_v2ray_api

bash scripts/verify.sh dist/sing-box 1.15.0-alpha.4-cf.1
bash scripts/package.sh dist dist/sing-box 1.15.0-alpha.4-cf.1 linux-amd64 tar.gz src
```

需要本机 Go 版本 ≥ 上游 `go.mod` 要求（当前为 1.25.5），脚本默认 `GOTOOLCHAIN=local`，不会隐式下载工具链。

## 许可与合规

上游 [SagerNet/sing-box](https://github.com/SagerNet/sing-box) 采用 **GPL-3.0-or-later**，且附带条款：

> In addition, no derivative work may use the name or imply association with this application without prior consent.

本仓库据此的合规做法：

1. **不修改上游源码**，只替换编译参数（build tags / ldflags）。因此 GPLv3 要求提供的"对应源码"就是上游对应 tag 的源码；`BUILD-INFO.txt` 中记录了上游 tag、commit 与**逐字可复现的编译命令**。
2. **随产物分发 `LICENSE`**（上游 release 也是把 LICENSE 与二进制一起打包）。
3. **明确标注为第三方非官方构建**，不以 `sing-box` 名义暗示官方关联或用于产品命名（可执行文件保留 `sing-box` 名称属于技术必需——面板安装器依赖该文件名匹配）。
4. 二进制为 Go 静态链接，内含第三方库（gvisor/quic-go/tailscale 等，多为 Apache-2.0/MIT/BSD）；正式对外分发建议另附 `THIRD_PARTY_NOTICES`。
5. 如需正式取得名称使用许可，可联系上游作者：`contact-sagernet@sekai.icu`。

> 以上为工程侧合规说明，不构成法律意见；正式商用前建议由法务确认。

## 维护

- 上游发布新版后，定时任务会自动跟进；如需立刻构建，手动触发 workflow 并填写 `upstream_tag`。
- 上游新增/调整 build tags 时，本仓库**自动继承**（tags 从源码目录的 `release/DEFAULT_BUILD_TAGS_OTHERS` 读取），无需改本仓库。
- 若要新增平台，只需在 `.github/workflows/build.yml` 的 matrix 中加一项。
