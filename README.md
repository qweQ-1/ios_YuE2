# YuE2 Studio（ios_YuE2）

YuE2 开源音乐生成模型的 **iOS 客户端**：输入歌词 + 风格提示，提交到你自建的 YuE2 服务器，生成完整歌曲（人声 + 伴奏）并查看/播放、保存 FLAC、查看乐谱。

- 上游模型：<https://github.com/multimodal-art-projection/YuE>（Apache-2.0，模型 YuE2-3B）
- 官方在线演示：<https://yue.noizai.net/>

## 为什么是「客户端 + 服务器」

YuE2-3B 推理需要 **NVIDIA GPU（BF16、≥24GB 显存）**，iPhone 本地跑不动。所以本仓库分两部分：

| 目录 | 内容 |
| --- | --- |
| `YuE2Studio/` | iOS App（SwiftUI，XcodeGen 工程，无第三方依赖） |
| `YuE2StudioTests/` | 逻辑测试 |
| `server/` | Python 服务端（FastAPI + `yue2-infer`，跑在你的 GPU 机器上） |
| `docs/API.md` | 客户端 ↔ 服务端 API 契约 |

没有 GPU 也可以先体验：服务器支持 `YUE2_STUB=1` 演示模式，或直接用 `server/mock_server.py`（零依赖）。

## 功能

- 三种创作模式：完整规划（默认）/ 仅旋律 / 直接生成；支持自带 ABC 乐谱、随机种子、Guidance
- 任务队列：排队 → 规划乐谱 → 谱写旋律 → 合成音色 → 渲染音频，实时进度与取消
- 播放：M4A 流式播放（后台播放已开）；保存 FLAC 原文件到"文件" App / 分享
- 乐谱：内置 abcjs 渲染 YuE2 生成的 ABC 乐谱（离线可用）
- 本地历史、服务器健康检查、参数一键复用重新创作

## 构建 IPA（GitHub Actions）

本仓库不依赖本地 Mac：所有编译在 CI 完成。

1. 推送代码到 GitHub；
2. Actions → **Build & Test** 自动跑测试（推送/PR 触发）；
3. Actions → **Unsigned IPA** → Run workflow，几分钟后下载 `yue2studio-unsigned-ipa` 产物；
4. 用 AltStore / Sideloadly / 轻松签 等工具以免费 Apple ID 自签安装；
5. （可选）打 `v*` 标签走 TestFlight 工作流（需配置 Apple 4 项 Secrets）。

工程由 `project.yml` 经 XcodeGen 生成；`.ios-ci.yml` 是 CI 配置。入口工作流锁定 `wenjinliuu/ios-ci-workflows @ df71d6096d6d39ea799179cb2635703548b07ae0 # v1.1.0`。

## 连接服务器

App 首次启动要求填写服务器地址（支持 http/https，局域网 http 已放行 ATS）与可选的 API Key。部署方法见 [`server/README.md`](server/README.md)。

## 目录

```
YuE2Studio/          SwiftUI 源码（Models/Networking/Persistence/Services/ViewModels/Views/Logic/Resources）
YuE2StudioTests/     逻辑测试（解码、URL、ABCParser、ViewModel、存储）
server/              Python 服务端（见 server/README.md）
docs/API.md          API 契约
.github/workflows/   Build & Test / Unsigned IPA / TestFlight / Server Tests
```

## 许可

本客户端代码用于调用 YuE2；YuE2 项目采用 Apache-2.0（见上游仓库 LICENSE 与 MODEL_LICENSE）。abcjs 按其许可随 App 内置分发。
