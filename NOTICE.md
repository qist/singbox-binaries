# NOTICE

本仓库**不是** sing-box 官方项目，仅是第三方重新编译的二进制分发仓库。

- 上游项目：https://github.com/SagerNet/sing-box
- 上游许可证：GNU General Public License v3.0 or later（见 https://github.com/SagerNet/sing-box/blob/dev/LICENSE）
- 上游附加条款：`In addition, no derivative work may use the name or imply association with this application without prior consent.`

## 本仓库做了什么

仅调整编译参数，**未修改上游任何源码**：

1. 在 `release/DEFAULT_BUILD_TAGS_OTHERS` 的基础上**追加 `with_v2ray_api`**，使 `experimental.v2ray_api` 可用（面板按用户统计流量所需）；
2. 通过 `-ldflags "-X github.com/sagernet/sing-box/constant.Version=<ver>"` 注入自定义版本串（如 `1.15.0-cf.1`），以便与官方产物区分。

## 分发要求

再分发本仓库产出的二进制时，请同时满足：

1. 随附 `LICENSE`（归档内已包含）；
2. 提供对应源码的获取方式 —— 即上游仓库对应 tag（归档内 `BUILD-INFO.txt` 记录了 tag、commit 与完整编译命令，可直接复现）；
3. 不得声称该产物为官方发布，或以 `sing-box` 名义暗示与上游项目存在隶属/背书关系。

## 商标与名称

归档内可执行文件保留 `sing-box` / `sing-box.exe` 名称，仅为兼容下游安装器的文件匹配逻辑（CoreFusion 的 `matchCoreBinary()` 按该名字识别归档条目），不代表任何官方关联。若需在产品/发布物中使用 `sing-box` 名称进行宣传，建议先向作者取得书面同意：`contact-sagernet@sekai.icu`。

*本文件为工程侧合规说明，不构成法律意见。*
