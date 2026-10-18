# YuE2 Server ↔ YuE2Studio iOS 客户端 API 契约

iPhone 跑不动 YuE2-3B（需要 NVIDIA GPU + 24GB 显存），所以架构是：
**iOS 客户端（SwiftUI）↔ HTTP ↔ YuE2 服务器（Python，跑在带 GPU 的 Linux 机器上）**。

服务器包自尊敬合约实现（见 `server/README.md`）。本文档是双方唯一的事实来源。

## 通用约定

- Base URL 由客户端设置页保存，例如 `https://yue2.example.com` 或局域网 `http://192.168.1.10:8420`。
  - 所有路径以 `/api` 开头。
  - 客户端负责去掉末尾 `/`，服务器端也要容忍。
- 认证：服务器若设置了 API Key（环境变量 `YUE2_API_KEY`），客户端对所有请求带 Header `X-API-Key: <key>`。
  - 未设置则不校验。错误的 Key 返回 401 `{"error": "..."}`。
- 时间均为 ISO 8601 UTC 字符串（如 `2026-10-18T07:30:00Z`）。
- 错误统一返回 `{"error": "中文可读信息"}`，HTTP 状态码语义化。

## 1. GET /api/health

服务器与引擎健康检查。**不要求 API Key。**

200 OK:

```json
{
  "status": "ok",
  "engine": "ready",            // ready | loading | error（引擎是否已加载模型）
  "engine_message": "",         // loading 时的阶段描述；error 时的原因
  "model": "m-a-p/YuE2-3B",     // 当前模型标识
  "device": "cuda",             // cuda | cpu | stub
  "stub": false,                // 是否 Stub 模式（无 GPU 演示/测试）
  "version": "1.0.0",           // 服务器版本
  "queue_depth": 0,             // 排队中的任务数
  "active_job": null            // 正在运行的任务 id 或 null
}
```

## 2. POST /api/generate

提交一首歌的生成任务。引擎忙时入队。

请求体：

```json
{
  "style": "English, warm piano pop, expressive female voice, 88 BPM",
  "lyrics": "[Verse]\nNeon fades along the lane\n\n[Chorus]\nLet the day come into view",
  "cot": "full",                // full | melody | off，默认 full
  "abc": null,                  // 可选：自带 ABC 乐谱（cot=full 或 melody 时生效）
  "seed": 831001,               // 可选：随机种子，便于复现
  "guidance": null              // 可选：CFG scale（>0 的小数）
}
```

校验规则：
- `style`、`lyrics` 必填且去空白后非空 → 否则 400。
- `cot` ∈ {full, melody, off} → 否则 400。
- 提供 `abc` 时长度 ≤ 64KB、必须是合法 ABC 文本（含 `X:` 开头）→ 否则 400。
- `seed`（提供时）为整数 → 否则 400。

成功：202 Accepted

```json
{ "job_id": "20261018-a1b2c3d4", "status": "queued" }
```

失败：400 `{"error": "..."}`。

## 3. GET /api/jobs?limit=50

任务列表（新的在前，分页用 `limit`，先不做游标）。

200 OK:

```json
{
  "items": [
    {
      "id": "20261018-a1b2c3d4",
      "status": "succeeded",      // queued | running | succeeded | failed | cancelled
      "created_at": "2026-10-18T07:30:00Z",
      "style": "English, warm piano pop...",
      "lyrics_excerpt": "[Verse] Neon fades...",   // 前 ~200 字符
      "cot": "full",
      "audio_seconds": 182.4,     // 成功后有值，其余 null
      "seed": 831001
    }
  ],
  "total": 12                      // 服务器保留的任务总数（受 YUE2_KEEP_JOBS 限制）
}
```

## 4. GET /api/jobs/{id}

任务详情（客户端轮询这个接口刷新进度）。

200 OK:

```json
{
  "id": "20261018-a1b2c3d4",
  "status": "running",            // queued | running | succeeded | failed | cancelled
  "created_at": "2026-10-18T07:30:00Z",
  "updated_at": "2026-10-18T07:35:12Z",
  "params": { "style": "...", "lyrics": "...", "cot": "full", "abc": null, "seed": 831001, "guidance": null },
  "progress": {
    "phase": "semantic",          // queued | planning | semantic | synthesizing | decoding | done
    "message": "生成歌曲 token · 3,210",   // 人类可读的阶段描述（可为空字符串）
    "fraction": null              // 0~1；无法估计时为 null（客户端显示不确定进度）
  },
  "error": null,                  // failed 时的中文错误
  "result": null,                 // succeeded 时：
  // {
  //   "audio_seconds": 182.4,
  //   "sample_rate": 48000,
  //   "truncated": { "abc": false, "semantic": false },
  //   "timing": { "abc": {...}, "semantic": {...}, "nar_seconds": 120.5, "vae_seconds": 40.2, "e2e_seconds": 210.8 },
  //   "identity": "sha256:..."
  // },
  "urls": {
    "audio": "/api/jobs/20261018-a1b2c3d4/audio",        // FLAC 下载（附件）
    "stream": "/api/jobs/20261018-a1b2c3d4/stream",      // M4A(AAC) 流式播放，支持 Range
    "score": "/api/jobs/20261018-a1b2c3d4/score.abc"     // 生成的 ABC 乐谱
  }
}
```

- 任务不存在：404 `{"error": "任务不存在"}`。

## 5. POST /api/jobs/{id}/cancel

取消排队中或运行中的任务（协作式取消：引擎在阶段边界检查取消标志）。

- 200 `{"id": "...", "status": "cancelled"}`（queued 直接取消；running 置取消标志）
- 409 `{"error": "任务已结束，无法取消"}`
- 404 任务不存在。

## 6. GET /api/jobs/{id}/audio

下载 FLAC 原文件。`Content-Type: audio/flac`，`Content-Disposition: attachment; filename="YuE2-<短id>.flac"`。
任务未完成：409。

## 7. GET /api/jobs/{id}/stream

返回 M4A（AAC 256kbps）供播放器用。首次请求时按需转码（依赖 `ffmpeg`），转码结果缓存。
**必须支持 HTTP Range 请求**（AVPlayer 流式播放需要）。任务未完成：409；转码失败：500。

## 8. GET /api/jobs/{id}/score.abc

返回 YuE2 生成的 ABC 乐谱文本（text/plain; charset=utf-8）。任务未完成：409。

## 阶段说明（progress.phase）

| phase | 含义 |
| --- | --- |
| queued | 排队中（引擎忙） |
| planning | 生成/解析 ABC 乐谱 |
| semantic | 生成语义 token |
| synthesizing | 流匹配合成声学 latent（时间最长） |
| decoding | VAE 解码为音频 |
| done | 完成（与 status=succeeded 同步切换） |

## 客户端落库约定（本地）

- 设置页保存：server base URL、API Key（可选）、默认 cot 模式。
- 本地历史：记录每次提交（job_id、标题=style 前 40 字、cot、提交时间、最近一次 status），
  打开历史记录时调 `GET /api/jobs/{id}` 拉最新状态；服务器已淘汰（404）则标记为「已失效」。
