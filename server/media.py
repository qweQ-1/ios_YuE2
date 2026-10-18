"""ffmpeg 转码：FLAC → M4A(AAC)，供 iOS AVPlayer 播放。"""
from __future__ import annotations

import logging
import shutil
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


class MediaError(RuntimeError):
    """转码失败（含 ffmpeg 缺失）。"""


def ffmpeg_available() -> bool:
    return shutil.which("ffmpeg") is not None


def transcode_flac_to_m4a(flac_path: Path, m4a_path: Path, bitrate: str = "256k") -> Path:
    """转码为 M4A；已存在则直接返回。无 ffmpeg 抛 MediaError。"""
    if m4a_path.exists():
        return m4a_path
    if not ffmpeg_available():
        raise MediaError("服务器未安装 ffmpeg，无法提供流式音频；请下载 FLAC 原文件或安装 ffmpeg")
    cmd = [
        "ffmpeg", "-nostdin", "-y",
        "-i", str(flac_path),
        "-vn", "-c:a", "aac", "-b:a", bitrate,
        str(m4a_path),
    ]
    logger.info("transcode: %s", " ".join(cmd))
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0 or not m4a_path.exists():
        tail = (proc.stderr or "")[-500:]
        raise MediaError(f"音频转码失败：{tail}")
    return m4a_path
