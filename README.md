# Codex Pulse

Codex Pulse 是一款原生 macOS 菜单栏与仪表盘应用，用来实时查看 Codex 的 token、项目、时段、会话、额度窗口和模型基准表现。

## 功能

- **总览**：今天、7 天、30 天的 token 曲线、会话数、活跃时长与项目占比。
- **项目**：按工作区聚合 token、会话、时长与模型使用情况。
- **时间**：按天与小时查看使用分布、峰值时段和最长活跃项目。
- **额度**：通过本机 `codex app-server` 读取账户公开给客户端的限额窗口与重置时间。
- **模型智商**：读取 [CodexRadar 公共榜单 API](https://api.codexradar.com/api/v1/table)，展示各模型与推理强度的实时 IQ 信号、覆盖率、成本和耗时。
- **菜单栏**：快速查看剩余额度、当日 token、活跃任务，并可一键刷新或打开主窗口。
- **容错**：CodexRadar 暂时不可用时保留最后一次成功快照；本地增量缓存避免每次重扫全部会话。

## 隐私

Codex Pulse 默认只在本机分析 `~/.codex/state_*.sqlite` 与会话 JSONL 的统计事件。它不会读取或展示提示词、回复正文、`auth.json` 或账户身份字段。

只有两类网络/进程访问：

1. 启动本机已安装的 `codex app-server --stdio`，读取 Codex 客户端协议暴露的额度与账户用量统计。
2. 通过 HTTPS GET 请求 CodexRadar 的公共榜单；贡献者身份字段不会写入应用快照。

## 运行

要求：macOS 14 或更高版本，且本机已安装并登录 Codex CLI。

解压 `CodexPulse-macOS.zip`，把 `CodexPulse.app` 拖到“应用程序”后打开即可。应用采用本机临时签名，适合本地使用；没有做 Apple 公证或 App Store 分发。

## 从源码构建

```bash
swift test
./script/build_and_run.sh --verify
```

只构建但不启动时使用 `./script/build_and_run.sh --build`。构建产物位于 `dist/CodexPulse.app`。项目使用 SwiftPM、SwiftUI、Swift Charts、SQLite C API 和 OSLog，不依赖第三方包。

## 指标口径

- Token 数据以 Codex 会话事件中的累计计数为准，并处理重复记录和计数器重置。
- “活跃”要求任务尚未结束，且最近事件在 10 分钟内，避免把陈旧会话误判为运行中。
- 当日预测需要至少 3 小时观测数据，避免凌晨小样本外推造成误导。
- CodexRadar IQ 是公共 benchmark 的通过率信号，不等同于模型的绝对智力或适配所有任务的结论。

## 参考产品

产品取舍参考了 [CodexBar](https://github.com/steipete/codexbar)、[Code Meter](https://codemeter.dev/) 与 [ReserveGauge](https://reservegauge.com/) 的菜单栏速览、历史趋势、额度重置和预测思路；实现坚持真实数据、明确新鲜度和本地优先。
