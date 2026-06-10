# Token Meter

Token Meter 是一个 macOS 状态栏小工具，用来快速查看 Codex 额度和 Token 消耗情况。

启动后，应用只会常驻在顶部状态栏。点击状态栏百分比，可以展开小巧的额度面板；点击面板外部会自动隐藏。

## 功能

- 状态栏显示 5 小时额度剩余百分比
- 支持 5 小时和 7 天额度窗口查看
- 显示今日、本月和近 7 天 Token 消耗
- 详情页提供近 7 天趋势图
- 根据额度余量显示轻量颜色提示
- 支持手动刷新和自动刷新

## 安装

从 Releases 下载最新的 macOS 版本，解压后打开 `Token Meter.app`。

如果 macOS 提示无法打开，可以在系统设置的“隐私与安全性”里允许打开。

## 从源码运行

```bash
swift run
```

## 打包

```bash
chmod +x scripts/build_app.sh
scripts/build_app.sh
open "dist/Token Meter.app"
```

## 隐私

Token Meter 只在本机读取必要的 Codex 使用信息，不会上传或收集个人数据。

## 要求

- macOS 14 或更高版本
- 已安装并登录 Codex Desktop
