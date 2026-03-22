# 已阅 — 小说漫画阅读器

基于 iOS 16+ 的阅读器，支持用户自定义源，采用液态玻璃 UI 风格。

## 构建
本项目使用 XcodeGen 管理项目，GitHub Actions 自动构建 IPA。

## 安装
- 巨魔用户：下载 Releases 中的 `.ipa` 用 TrollStore 安装。
- 普通用户：需自签名。

## 使用
1. 添加源：点击右上角“+” → 填写源名称和 JSON 规则。
2. 添加书籍：通过源搜索（待完善）或手动添加。

## 开发
1. 安装 XcodeGen：`brew install xcodegen`
2. 生成项目：`xcodegen generate`
3. 打开 `YueYue.xcodeproj` 开发