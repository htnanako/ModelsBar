# ModelsBar

[English](README.md) | 简体中文

`ModelsBar` 是一款原生 macOS 菜单栏应用，用于查看 NewAPI、Sub2API 与 OpenAI-compatible 服务的模型列表、Key 健康状态、额度使用和连通性。

## 目录

- [功能](#功能)
- [安装](#安装)
- [开始使用](#开始使用)
- [推荐使用流程](#推荐使用流程)
- [使用说明](#使用说明)
- [关于](#关于)

## 功能

- 常驻 macOS 状态栏，随时快速查看状态。
- 支持多个 NewAPI、Sub2API 和 OpenAI-compatible 站点。
- 支持同一站点下配置多个 API Key。
- 支持同步模型列表、额度和当日使用数据。
- 支持模型连通性测试，帮助定位失效 Key 或不可用模型。

## 安装

1. 前往 GitHub Releases 页面，下载对应 CPU 架构的 `.dmg` 安装包。
2. Apple Silicon 机型下载 `arm64` 版本。
3. Intel 机型下载 `x86_64` 版本。
4. 打开下载好的 `.dmg`。
5. 将 `ModelsBar.app` 拖入 `Applications` 文件夹。
6. 从 `Applications` 中启动应用。

如果 macOS 弹出安全提示，按系统标准流程确认打开即可。

## 开始使用

首次启动 ModelsBar 后，建议按下面步骤完成配置：

1. 点击状态栏图标打开主面板。
2. 打开 `Settings`。
3. 添加你的服务地址和访问凭据。
4. 为该站点添加一个或多个 API Key。
5. 同步数据并查看模型、额度和当前状态。

## 推荐使用流程

1. 准备好你的 NewAPI、Sub2API 或 OpenAI-compatible 服务。
2. 安装 ModelsBar。
3. 在 `Settings` 中添加站点。
4. 添加或同步 API Key。
5. 刷新模型和额度信息。
6. 需要时执行连通性测试。

## 使用说明

- ModelsBar 适合在菜单栏中快速查看服务和 Key 的整体状态。
- 如果发现某个站点或 Key 不可用，建议先刷新数据，再进行模型连通性测试。
- 你可以通过 `Settings` 统一管理多个站点和多个 Key。

## 关于

- 作者：`htnanako`
- 开源协议：`MIT`
