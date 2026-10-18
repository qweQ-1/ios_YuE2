#!/usr/bin/env python3
"""零依赖 Mock 服务器：契约与 docs/API.md 一致，Stub 行为，无 GPU/无 ffmpeg 联调用。

    python server/mock_server.py --port 8420

限制：音频是 3 秒 WAV（非 FLAC），stream 返回 audio/wav 且不支持 Range；
仅供无 GPU 环境验证界面与流程，真机联调请以 server/README.md 部署真服务端为准。
"""
from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

SERVER_VERSION = "1.0.0-mock"
STUB_SECONDS = float(1.0)

JOBS: dict[str, dict] = {}
LOCK = threading.Lock()


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _write_wav(path: Path) -> None:
    """写一段 3 秒静音 WAV（PCM16 单声道）。"""
    import math
    import struct
    import wave

    sr = 48000
    frames = bytearray()
    for i in range(sr * 3):
        v = int(8000 * math.sin(2 * math.pi * 220 * i / sr))
        frames += struct.pack("<h", v)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(frames))


class Handler(BaseHTTPRequestHandler):
    server_version = "YuE2Mock/1.0"

    def log_message(self, fmt, *args):  # 静音默认日志
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    # ---- 工具 ----
    def _json(self, obj, status: int = 200) -> None:
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status: int, message: str) -> None:
        self._json({"error": message}, status=status)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except Exception:
            return {}

    # ---- 路由 ----
    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        parts = [p for p in path.split("/") if p]

        if path == "/api/health":
            self._json({
                "status": "ok", "engine": "ready", "engine_message": "",
                "model": "mock", "device": "stub", "stub": True,
                "version": SERVER_VERSION, "queue_depth": 0, "active_job": None,
            })
            return

        if parts == ["api", "jobs"]:
            with LOCK:
                items = [_summary(j) for j in JOBS.values()]
            items.sort(key=lambda j: j["created_at"], reverse=True)
            query = parse_qs(urlparse(self.path).query)
            limit = int((query.get("limit") or ["50"])[0])
            self._json({"items": items[:limit], "total": len(items)})
            return

        if len(parts) == 3 and parts[0] == "api" and parts[1] == "jobs":
            job_id = parts[2]
            job = JOBS.get(job_id)
            if job is None:
                self._error(404, "任务不存在")
                return
            self._json({
                "id": job["id"],
                "status": job["status"],
                "created_at": job["created_at"],
                "updated_at": job.get("updated_at", job["created_at"]),
                "params": job["params"],
                "progress": {"phase": "done" if job["status"] == "succeeded" else "queued",
                             "message": "", "fraction": None, "tokens": 0},
                "error": None,
                "result": {"audio_seconds": 3.0, "sample_rate": 48000,
                           "truncated": {"abc": False, "semantic": False},
                           "timing": {"nar_seconds": 0, "vae_seconds": 0, "e2e_seconds": 1.0}}
                          if job["status"] == "succeeded" else None,
                "urls": {"audio": f"/api/jobs/{job_id}/audio",
                         "stream": f"/api/jobs/{job_id}/stream",
                         "score": f"/api/jobs/{job_id}/score.abc"},
            })
            return

        if len(parts) >= 4 and parts[0] == "api" and parts[1] == "jobs":
            job_id, action = parts[2], parts[3]
            job = JOBS.get(job_id)
            if job is None:
                self._error(404, "任务不存在")
                return
            if action == "score.abc":
                if job["status"] != "succeeded":
                    self._error(409, "任务尚未完成，乐谱不可用")
                    return
                data = job["score"].encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if action == "audio":
                if job["status"] != "succeeded":
                    self._error(409, "任务尚未完成，音频不可用")
                    return
                data = Path(job["audio"]).read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Disposition", f'attachment; filename="YuE2-{job_id[:8]}.wav"')
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            if action == "stream":
                if job["status"] != "succeeded":
                    self._error(409, "任务尚未完成，无法播放")
                    return
                data = Path(job["audio"]).read_bytes()
                # 简化：忽略 Range，整体返回（mock 限制，README 已注明）
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self._error(404, "接口不存在")
            return

        self._error(404, "接口不存在")

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        parts = [p for p in path.split("/") if p]

        if path == "/api/generate":
            body = self._body()
            style = (body.get("style") or "").strip()
            lyrics = (body.get("lyrics") or "").strip()
            cot = body.get("cot", "full")
            if not style or not lyrics:
                self._error(400, "style 和 lyrics 不能为空")
                return
            if cot not in ("full", "melody", "off"):
                self._error(400, "cot 必须是 full / melody / off")
                return
            job_id = time.strftime("%Y%m%d") + "-" + uuid.uuid4().hex[:8]
            job_dir = Path("/tmp") / "yue2-mock" / job_id
            job_dir.mkdir(parents=True, exist_ok=True)
            _write_wav(job_dir / "audio.wav")
            with LOCK:
                JOBS[job_id] = {
                    "id": job_id, "status": "running", "created_at": _now(),
                    "params": {"style": style, "lyrics": lyrics, "cot": cot},
                    "score": "X:1\nT:Mock Song\nM:4/4\nL:1/4\nK:C\nCDEF|",
                    "audio": str(job_dir / "audio.wav"),
                }

            def finish() -> None:
                time.sleep(STUB_SECONDS)
                with LOCK:
                    JOBS[job_id]["status"] = "succeeded"
                    JOBS[job_id]["updated_at"] = _now()

            threading.Thread(target=finish, daemon=True).start()
            self._json({"job_id": job_id, "status": "queued"}, status=202)
            return

        if len(parts) == 4 and parts[0] == "api" and parts[1] == "jobs" and parts[3] == "cancel":
            job_id = parts[2]
            with LOCK:
                job = JOBS.get(job_id)
                if job is None:
                    self._error(404, "任务不存在")
                    return
                if job["status"] == "succeeded":
                    self._error(409, "任务已结束，无法取消")
                    return
                job["status"] = "cancelled"
            self._json({"id": job_id, "status": "cancelled"})
            return

        self._error(404, "接口不存在")


def _summary(job: dict) -> dict:
    return {
        "id": job["id"], "status": job["status"], "created_at": job["created_at"],
        "style": job["params"]["style"], "lyrics_excerpt": job["params"]["lyrics"][:200],
        "cot": job["params"]["cot"],
        "audio_seconds": 3.0 if job["status"] == "succeeded" else None,
        "seed": None,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8420)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"mock server on http://{args.host}:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
