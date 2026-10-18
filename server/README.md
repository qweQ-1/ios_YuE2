# YuE2 Server

YuE2 音乐生成服务器：把开源模型 YuE2（[multimodal-art-projection/YuEE](https://github.com/multimodal-art-projection/YuE)，包名 `yue2-infer`）包装成任务式 HTTP API，供 **YuE2Studio iOS 客户端**调用。契约见仓库根目录 [`docs/API.md`](../docs/API.md)。

## 硬件要求（真模型）

- Linux（x86_64）+ NVIDIA GPU：**BF16 支持、≥24GB 显存**
- Python 3.12；`ffmpeg`（FLAC→M4A 转码）
- 磁盘：模型约 6~10GB + 每首歌曲产物几 MB~几十 MB（FLAC PCM_24）

> iPhone 无法本地推理 YuE2-3B，所以 App 只做客户端；推理都在这台服务器上。
> 没有 GPU 时可用 **Stub 模式**（`YUE2_STUB=1`）先联调界面与流程。

## 快速开始

```bash
cd server
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # torch 建议另按 YuE 官方 README 装 CUDA 版
cp .env.example .env                     # 按需修改
python -m uvicorn server.app:create_app --factory --host 0.0.0.0 --port 8420
# 或：python -m server.main
```

YuE2-3B 若为 gated 模型，先 `export YUE2_HF_TOKEN=hf_xxx` 再启动。

### Stub 演示模式（无 GPU）

```bash
YUE2_STUB=1 python -m uvicorn server.app:create_app --factory --port 8420
```

### Docker

```bash
docker build -t yue2-server .
docker run --gpus all -p 8420:8420 -v yue2-data:/data \
  -e YUE2_API_KEY=你的密钥 -e YUE2_HF_TOKEN=hf_xxx yue2-server
```

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `YUE2_HOST` / `YUE2_PORT` | `0.0.0.0` / `8420` | 监听地址 |
| `YUE2_MODEL` / `YUE2_VAE` | `m-a-p/YuE2-3B` / `m-a-p/YuE2-Vae` | 模型仓库或本地目录 |
| `YUE2_DEVICE` | `auto` | auto / cuda / cpu |
| `YUE2_MEMORY_BUDGET_GIB` | `24` | 显存预算 |
| `YUE2_HF_TOKEN`（或 `HF_TOKEN`） | 空 | Hugging Face 令牌 |
| `YUE2_API_KEY` | 空 | 设置后校验 `X-API-Key` 头 |
| `YUE2_DATA_DIR` | `./data` | 任务库与产物目录 |
| `YUE2_KEEP_JOBS` | `100` | 保留任务数（超出清理产物） |
| `YUE2_STUB` | `0` | `1` = 演示模式（不加载模型） |
| `YUE2_MAX_LYRICS` | `20000` | 歌词长度上限 |

## 反代与 HTTPS（给 iPhone 用）

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:8420;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    # Range 必须透传，否则 stream 播放会失败
    proxy_set_header Range $http_range;
    proxy_buffering off;
}
```

## API 摘要

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 健康检查（不校验 Key） |
| POST | `/api/generate` | 提交创作（style/lyrics/cot/abc/seed/guidance） |
| GET | `/api/jobs?limit=N` | 任务列表 |
| GET | `/api/jobs/{id}` | 任务详情（轮询进度） |
| POST | `/api/jobs/{id}/cancel` | 取消 |
| GET | `/api/jobs/{id}/audio` | FLAC 原文件下载 |
| GET | `/api/jobs/{id}/stream` | M4A 流式播放（支持 Range） |
| GET | `/api/jobs/{id}/score.abc` | 生成的 ABC 乐谱 |

字段与错误格式以 [`docs/API.md`](../docs/API.md) 为准。

## 结构

```
server/
├── app.py          FastAPI 路由与响应组装
├── engine.py       YuE2Pipeline 封装（分阶段 + 进度/取消回调）+ Stub 引擎
├── jobs.py         SQLite 任务库 + 单 worker 串行队列 + 清理
├── media.py        ffmpeg 转码 FLAC→M4A
├── ranges.py       HTTP Range 解析
├── config.py       环境变量配置（脱敏摘要）
├── mock_server.py  零依赖 mock（无 GPU 联调 iOS 客户端）
└── tests/          pytest（stub 模式，无 GPU 可跑）
```

## 测试

```bash
cd server
python -m pytest tests -q          # 无 fastapi 时 HTTP 测试自动跳过
```

GitHub Actions 的 *Server Tests* 工作流会在推送时跑同一套测试（含 fastapi 的 HTTP 用例）。
