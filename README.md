# Listen1 Xuan

跨平台的音乐聚合播放器：在一个简洁的界面中搜索、收藏、播放和管理多个音乐平台的内容。

![Listen1 Xuan 概念图：桌面与移动端音乐库](readme/assets/hero-gpt-image-2.5.webp)

<p align="center">
  <strong>一个界面，管理你的多平台音乐库</strong><br>
  Windows · macOS · Android · iOS
</p>

<p align="center">
  <a href="https://github.com/preauthn1/listen1_xuan/actions/workflows/build.yml"><img src="https://github.com/preauthn1/listen1_xuan/actions/workflows/build.yml/badge.svg?branch=main" alt="Build status"></a>
  <a href="https://github.com/preauthn1/listen1_xuan/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-blue.svg" alt="MPL-2.0 license"></a>
  <a href="https://github.com/preauthn1/listen1_xuan/releases"><img src="https://img.shields.io/github/v/release/preauthn1/listen1_xuan?display_name=tag" alt="Latest release"></a>
</p>

> 这是一个 Flutter 重写的 Listen1 客户端。项目仍在持续开发中，平台接口和登录流程可能随上游服务变化而调整。

## 适合谁

- 希望用一个客户端浏览多个音乐平台内容的桌面用户；
- 需要在 Windows、macOS、Android 或 iOS 之间保持相近使用体验的用户；
- 喜欢自己构建 Flutter 应用、调试平台适配或参与开源改进的开发者。

## 主要功能

- **多平台搜索与播放**：统一搜索歌曲、歌单、专辑和歌手内容；
- **歌单管理**：浏览推荐歌单、创建的歌单和收藏的歌单；
- **歌词与播放控制**：支持歌词页面、队列管理、播放模式、音量和快捷键；
- **跨平台桌面体验**：Windows 和 macOS 提供窗口控制、托盘与桌面快捷操作；
- **移动端适配**：Android 与 iOS 提供竖屏播放控制、歌词和系统媒体控制；
- **可选音频增强**：带 FFmpeg 的构建变体提供额外的音频处理与缓存能力；
- **主题与外观**：支持浅色、深色及跟随系统的主题体验；
- **持续集成**：GitHub Actions 负责 Windows、macOS、iOS 和 Android 构建检查。

## 快速开始

### 使用预构建版本

打开 [Releases](https://github.com/preauthn1/listen1_xuan/releases) 下载适合平台的构建包。

- **Windows**：下载压缩包，解压后运行 `listen1_xuan.exe`；也可以使用 Inno Setup 安装包。
- **macOS**：选择 Apple Silicon 或 Intel 架构对应的应用包。
- **iOS**：下载对应的 `.app.zip`，适用于开发测试或自行签名安装。
- **Android**：按设备架构选择 APK。正式签名构建是否可用取决于发布者的 CI 配置。

每个平台通常有两个变体：

- **Lite**：体积更小，不包含 FFmpeg；
- **FFmpeg**：包含额外音频处理能力，体积更大。

#### Release 资产命名

| 平台 | 文件名 | 说明 |
|---|---|---|
| Android | `app-<架构>-release[-without.embedded.Cronet][-ffmpeg]-<hash>.apk`，另有同名 `.zip` | 一般选 `arm64-v8a`；`.zip` 内是同一个已签名 APK |
| Windows | `windows-build-artifact[-ffmpeg]-<hash>.zip`，Inno Setup 安装包为 `.exe` | 压缩包解压即用 |
| macOS | `listen1_xuan-<版本>-macos-<apple-silicon\|intel>[-ffmpeg]-<hash>.zip` | 按芯片选择 |
| iOS | `listen1_xuan-ios[-ffmpeg]-<hash>.app.zip` | 未签名，需自行签名 |

Android 关于 Cronet：

- **带 `without.embedded.Cronet`** 的包体积更小，网络库依赖设备上的 Google Play 服务，适合有 Google Play 服务的手机；
- **没有 Google Play 服务**的设备（多数国行手机、部分模拟器）请选**不带** `without.embedded.Cronet` 的包，它内置了 Cronet。

每个 Release 正文顶部的安装说明会按实际上传的文件列出推荐包和下载大小，见 `docs/release_installation_guide.md`。

### 首次使用

1. 启动应用并进入 **设置 → 第三方平台登录**；
2. 只为需要使用的音乐平台完成登录；
3. 返回首页搜索歌曲或歌单，点击播放；
4. 在设置中按需调整下载、缓存、主题、快捷键和桌面窗口选项。

登录信息由应用运行时管理。请勿把账号、Cookie、访问令牌或任何个人配置提交到仓库、日志、截图或 Issue 中。

## 从源码构建

### 环境要求

- Flutter `3.41.9`；
- Dart SDK `3.10.0` 或兼容版本；
- 对应平台的原生构建工具链：Android Studio、Xcode、Visual Studio 或 macOS 开发工具；
- Git，以及 Flutter 可以访问依赖仓库的网络环境。

### 获取依赖

```bash
git clone https://github.com/preauthn1/listen1_xuan.git
cd listen1_xuan
flutter pub get
flutter analyze
```

### 本地运行

```bash
flutter run
```

指定桌面平台时可以使用：

```bash
flutter run -d windows
flutter run -d macos
```

### 构建

```bash
flutter build windows --release
flutter build macos --release
flutter build ios --release --no-codesign
flutter build apk --release
```

不同平台的签名、商店发布和系统权限由平台工具链管理。不要在源码、构建脚本或公开 Issue 中写入签名材料、服务令牌或账号信息。

## 架构概览

项目是 Flutter 应用，主要由以下部分组成：

```text
lib/
├── pages/        页面与桌面/移动端界面
├── provider/     音乐平台适配与搜索、歌单、歌词、播放接口
├── controllers/  设置、播放、下载、主题和网络状态
├── models/       歌曲、歌单、用户和搜索结果模型
├── services/     日志、更新、提示和平台服务
└── widgets/      可复用控件与播放组件
```

平台适配通过统一的 Provider 抽象接入。各平台的登录、搜索、歌单、歌词和音频地址能力可能不同，README 不把某个平台的行为描述为所有平台都具备。

## 快捷键

在 Windows、Android 和 macOS 中，文本框未获得焦点时可以使用：

| 按键 | 操作 |
| --- | --- |
| `E` / `.` | 下一首 |
| `Q` / `,` | 上一首 |
| `Space` | 播放 / 暂停 |
| `W` / `↑` | 音量增加 2% |
| `S` / `↓` | 音量减少 2% |
| `D` / `←` | 快进 3 秒 |
| `A` / `→` | 后退 3 秒 |

快捷键可以在设置中关闭或重新配置。

## 隐私与安全

- 仓库不包含平台账号、Cookie、访问令牌、签名密钥或其他凭据；
- GitHub Actions 只通过 GitHub Secrets 引用构建所需的敏感配置；
- 不要提交本地 `.env`、签名文件、Firebase 配置、导出的登录数据或带有个人信息的截图；
- 使用第三方平台时，请遵守对应平台的服务条款、版权规则和适用法律；
- 遇到安全问题，请不要在公开 Issue 中粘贴令牌、Cookie 或完整请求头，先通过私下渠道联系维护者。

### 与上游原版的互通

本 fork 的 WebSocket 服务器（远程控制、缓存拉取、剪贴板传输）要求配对令牌，这是相对上游的**不兼容协议变更**：

- 本 fork 客户端 → 上游原版服务器：可用（多出的令牌头会被忽略）；
- 上游原版客户端 → 本 fork 服务器：不可用。服务器返回 401，并说明需要配对令牌；服务器卡片会显示被拒绝的次数。两端都更新到本 fork 后扫码配对即可；
- 服务器默认只监听本机。开启「允许局域网设备连接」后，只监听所选的一个局域网地址，并拒绝公网来源；局域网内为明文传输，仅凭配对令牌鉴权，请只在可信网络中开启。

## 参与贡献

欢迎提交修复、平台适配、文档改进和 UI 改进。建议按以下方式开始：

1. Fork 仓库并创建独立分支；
2. 保持改动范围清晰，避免提交本地配置和构建产物；
3. 在提交前运行 `flutter analyze` 和必要的轻量静态检查；
4. 提交 Pull Request，说明改动范围、验证方式和已知限制。

## 项目状态

项目处于持续迭代状态。Windows、macOS、iOS 的 GitHub Actions 构建已配置；Android 正式发布构建需要仓库维护者配置签名材料，未配置时 CI 会安全跳过签名发布，而不会使用临时调试签名替代。

版本变更见 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

本项目使用 [Mozilla Public License 2.0](LICENSE)。第三方依赖和资源可能使用各自的许可证，请以其上游项目声明为准。

## 致谢

本项目基于 Flutter 生态和多个开源依赖构建。感谢所有提交代码、报告问题、维护平台适配和改进文档的贡献者。
