# Token Meter

一个原生 macOS 状态栏小组件，用来查看 Codex 额度和 Token 消耗。界面和产品形态参考 [codex-led-widget](https://github.com/xicunwus2025-sys/codex-led-widget)：启动后只在顶部状态栏显示 5 小时余额百分比，点击后弹出额度面板。

应用会读取三类本地数据：

- `codex app-server --listen stdio://` 的 `account/rateLimits/read`，用于实时显示 5 小时 / 7 天额度余量。
- `codex app-server --listen stdio://` 的 `account/usage/read`，用于读取 Codex 个人资料页同口径的累计 Token、峰值 Token、连续天数和每日 Token 活动。
- `~/.codex/sessions/**/*.jsonl` 和 `~/.codex/archived_sessions/*.jsonl` 里的 `token_count` 事件，作为本地兜底数据源。若官方每日统计暂时没有返回今天的日期桶，今日 Token 会自动回退到本地会话统计。

## 功能

- 状态栏常驻显示 5 小时余额百分比，并按余额改变颜色。
- 点击状态栏百分比打开简介面板，点击面板外部自动隐藏。
- 面板显示套餐类型、5 小时窗口、7 天窗口、剩余时间、今日 Token 和本月 Token。套餐类型来自 Codex app-server，读取不到时兜底显示 `FREE`。
- 详情页显示 Token 消耗看板和近 7 天折线趋势。
- 鼠标悬停到详情页折线图的对应日期时，会显示该日期的 Token 数。
- 每 60 秒自动刷新一次，也可以手动点击刷新按钮。

## 运行

```bash
swift run
```

## 打包成 macOS App

```bash
chmod +x scripts/build_app.sh
scripts/build_app.sh
open "dist/Token Meter.app"
```

脚本会做 ad-hoc 本地签名，适合自己机器运行；如果要发给其他人，需要再用 Developer ID 签名并 notarize。

## 统计说明

- 额度数据来自 `account/rateLimits/read`。
- Token 汇总优先来自 `account/usage/read`，这是 Codex Desktop 个人资料页使用的统计口径。
- 如果官方统计源没有返回今天的数据，今日 Token 使用本地 JSONL 会话文件补齐；近 7 天趋势和本月合计也会包含这个本地今日补值。
- 每日趋势按本机当前时区展示最近 7 天。
- 状态不再显示“绿灯/黄灯/红灯”文字，只通过左侧状态灯、状态栏百分比和额度窗口背景颜色表达。
- 颜色规则：0-10% 红色，10-20% 黄色，20-100% 绿色。5 小时余额和 7 天余额都使用同一套规则。
- 应用只调用本机 Codex app-server，并读取本机 `.codex` 会话文件；不会额外上传统计数据。
