# Release Notes

## v1.0.0（首个版本）

- YuE2 iOS 客户端上线：歌词 + 风格 → 服务器生成完整歌曲，可播放、保存、看乐谱
- 三种创作模式（full / melody / off）+ 自带 ABC 乐谱 + 种子/Guidance
- 任务队列与实时进度（规划乐谱 → 谱写旋律 → 合成音色 → 渲染音频），支持取消
- M4A 流式播放（Range、后台播放）；FLAC 原文件导出/分享
- abcjs 离线乐谱渲染（YuE2 生成的 ABC）
- 服务器健康检查、本地历史、参数复用
- 配套 Python 服务端（FastAPI + yue2-infer，GPU 机器部署，stub 演示模式）
- CI：Build & Test、Unsigned IPA、TestFlight、Server Tests
