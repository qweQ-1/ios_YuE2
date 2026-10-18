#!/usr/bin/env bash
# YuE2 服务器一键部署（Stub 演示模式，无需 GPU）。
# 适用：Ubuntu 22.04 / 24.04（含 Lightsail 通用型实例）。
# 用法：bash deploy-stub.sh [端口，默认 8420]
set -euo pipefail

PORT="${1:-8420}"
APP_DIR="$HOME/yue2-server"
REPO_URL="${YUE2_REPO_URL:-https://github.com/qweQ-1/ios_YuE2.git}"

echo "==> 安装系统依赖（python3.12 / venv / ffmpeg）"
sudo apt-get update -qq
sudo apt-get install -y -qq python3 python3-venv python3-pip ffmpeg git >/dev/null
PY=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "    Python: $PY（需要 ≥3.10）"

echo "==> 拉取代码到 $APP_DIR"
if [ -d "$APP_DIR/.git" ]; then
    git -C "$APP_DIR" pull --ff-only -q
else
    git clone -q "$REPO_URL" "$APP_DIR"
fi

echo "==> 创建虚拟环境并安装依赖（stub 精简集）"
cd "$APP_DIR/server"
python3 -m venv .venv
./.venv/bin/pip install -q --upgrade pip
./.venv/bin/pip install -q -r requirements-stub.txt

echo "==> 写入 systemd 服务（开机自启）"
sudo tee /etc/systemd/system/yue2-server.service > /dev/null <<EOF
[Unit]
Description=YuE2 Studio Server (stub)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$APP_DIR
Environment=PYTHONPATH=$APP_DIR
Environment=YUE2_STUB=1
Environment=YUE2_DATA_DIR=$APP_DIR/server/data
Environment=YUE2_PORT=$PORT
ExecStart=$APP_DIR/server/.venv/bin/python -m uvicorn server.app:create_app --factory --host 0.0.0.0 --port $PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now yue2-server
sleep 2

echo "==> 冒烟测试：GET /api/health"
curl -sf "http://127.0.0.1:$PORT/api/health" && echo

echo
echo "✅ 部署完成。下一步："
echo "   1. Lightsail 控制台 → 实例 → 联网 → 防火墙 → 添加 TCP $PORT 入站"
echo "   2. iPhone App 里填：http://<实例公网IP>:$PORT"
echo "   3. 查看日志：sudo journalctl -u yue2-server -f"
