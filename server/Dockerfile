FROM python:3.12-slim

# ffmpeg：FLAC → M4A 转码（iOS 播放用）
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV YUE2_HOST=0.0.0.0 \
    YUE2_PORT=8420 \
    YUE2_DATA_DIR=/data

EXPOSE 8420
VOLUME ["/data"]

# GPU 运行需要 nvidia-container-toolkit，例如：
#   docker run --gpus all -p 8420:8420 -v yue2-data:/data \
#     -e YUE2_API_KEY=你的密钥 -e YUE2_HF_TOKEN=hf_xxx yue2-server
# （不传 HF_TOKEN 时模型下载走匿名额度；gated 模型需要令牌）
CMD ["python", "-m", "uvicorn", "server.app:create_app", "--factory", "--host", "0.0.0.0", "--port", "8420"]
