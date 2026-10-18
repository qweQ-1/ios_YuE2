"""FastAPI 应用工厂：YuE2 HTTP API（见 docs/API.md）。"""
from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse, Response

from .config import get_config
from .engine import YuE2Engine
from .jobs import QUEUED, SUCCEEDED, ConflictError, JobManager, NotFoundError
from .media import MediaError, ffmpeg_available, transcode_flac_to_m4a
from .ranges import parse_range

logger = logging.getLogger("yue2.server")

SERVER_VERSION = "1.0.0"


@asynccontextmanager
async def lifespan(app: FastAPI):
    config = get_config()
    logger.info("YuE2 server starting: %s", config.safe_summary())
    manager.start()
    logger.info("YuE2 server ready on %s:%s (stub=%s)", config.host, config.port, config.stub)
    try:
        yield
    finally:
        manager.stop()
        logger.info("YuE2 server stopped")


engine = YuE2Engine(get_config())
manager = JobManager(engine, get_config().data_dir, get_config().keep_jobs)


def create_app() -> FastAPI:
    app = FastAPI(title="YuE2 Studio Server", version=SERVER_VERSION, lifespan=lifespan)

    # ---------- 领域异常 → HTTP ----------

    @app.exception_handler(NotFoundError)
    async def _not_found(_: Request, exc: NotFoundError):
        return JSONResponse(status_code=404, content={"error": str(exc)})

    @app.exception_handler(ConflictError)
    async def _conflict(_: Request, exc: ConflictError):
        return JSONResponse(status_code=409, content={"error": str(exc)})

    @app.exception_handler(HTTPException)
    async def _http_exc(_: Request, exc: HTTPException):
        # 统一 {"error": ...} 形状（与 docs/API.md 契约一致）
        return JSONResponse(status_code=exc.status_code,
                            content={"error": str(exc.detail)})

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        return JSONResponse(status_code=400, content={"error": "请求参数格式不正确"})

    @app.exception_handler(MediaError)
    async def _media(_: Request, exc: MediaError):
        return JSONResponse(status_code=500, content={"error": str(exc)})

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, exc: Exception):
        logger.exception("unhandled error")
        return JSONResponse(status_code=500, content={"error": "服务器内部错误"})

    # ---------- API Key ----------

    async def require_key(request: Request) -> None:
        key = get_config().api_key
        if not key:
            return
        if request.headers.get("X-API-Key") != key:
            raise HTTPException(status_code=401, detail="API Key 无效")

    # ---------- 路由 ----------

    @app.get("/api/health")
    async def health() -> dict[str, Any]:
        info = engine.info()
        return {
            "status": "ok",
            "engine": info["engine"],
            "engine_message": info["engine_message"],
            "model": info["model"],
            "device": info["device"],
            "stub": info["stub"],
            "version": SERVER_VERSION,
            "queue_depth": manager.queue_depth(),
            "active_job": manager.active_id(),
        }

    @app.post("/api/generate", dependencies=[Depends(require_key)])
    async def generate(body: dict[str, Any]) -> Response:
        style = (body.get("style") or "").strip()
        lyrics = body.get("lyrics") or ""
        cot = body.get("cot", "full")
        abc = body.get("abc")
        seed = body.get("seed")
        guidance = body.get("guidance")

        if not isinstance(style, str) or not style:
            raise HTTPException(status_code=400, detail="style 不能为空")
        if not isinstance(lyrics, str) or not lyrics.strip():
            raise HTTPException(status_code=400, detail="lyrics 不能为空")
        if len(lyrics) > get_config().max_lyrics:
            raise HTTPException(status_code=400,
                                detail=f"歌词过长（上限 {get_config().max_lyrics} 字符）")
        if cot not in ("full", "melody", "off"):
            raise HTTPException(status_code=400, detail="cot 必须是 full / melody / off")
        if abc is not None:
            if not isinstance(abc, str) or len(abc) > 65536:
                raise HTTPException(status_code=400, detail="abc 是不超过 64KB 的字符串")
            if cot == "off":
                raise HTTPException(status_code=400, detail="cot=off 不支持自带乐谱")
            if not abc.lstrip().startswith("X:"):
                raise HTTPException(status_code=400, detail="abc 需要以 X: 开头")
        if seed is not None and (not isinstance(seed, int) or isinstance(seed, bool)):
            raise HTTPException(status_code=400, detail="seed 只能是整数")
        if guidance is not None:
            if not isinstance(guidance, (int, float)) or isinstance(guidance, bool):
                raise HTTPException(status_code=400, detail="guidance 只能是数字")
            if not 0 < float(guidance) <= 20:
                raise HTTPException(status_code=400, detail="guidance 需要在 (0, 20] 区间")

        params = {"style": style, "lyrics": lyrics, "cot": cot,
                  "abc": abc, "seed": seed, "guidance": guidance}
        job_id = manager.submit(params)
        return JSONResponse(status_code=202, content={"job_id": job_id, "status": "queued"})

    @app.get("/api/jobs", dependencies=[Depends(require_key)])
    async def jobs(limit: int = 50) -> dict[str, Any]:
        if limit < 1:
            limit = 1
        if limit > get_config().jobs_limit_cap:
            limit = get_config().jobs_limit_cap
        items, total = manager.list(limit)
        return {"items": [_summary(j) for j in items], "total": total}

    @app.get("/api/jobs/{job_id}", dependencies=[Depends(require_key)])
    async def job_detail(job_id: str) -> dict[str, Any]:
        job = _require_job(job_id)
        return _detail(job)

    @app.post("/api/jobs/{job_id}/cancel", dependencies=[Depends(require_key)])
    async def cancel_job(job_id: str) -> dict[str, Any]:
        status = manager.cancel(job_id)
        return {"id": job_id, "status": status}

    @app.get("/api/jobs/{job_id}/audio", dependencies=[Depends(require_key)])
    async def audio(job_id: str) -> Response:
        job = _require_job(job_id)
        if job["status"] != SUCCEEDED:
            raise HTTPException(status_code=409, detail="任务尚未完成，音频不可用")
        path = manager.job_dir(job_id) / "audio.flac"
        if not path.exists():
            raise HTTPException(status_code=410, detail="音频文件已被清理")
        return FileResponse(path, media_type="audio/flac",
                            filename=f"YuE2-{job_id[:8]}.flac")

    @app.get("/api/jobs/{job_id}/stream", dependencies=[Depends(require_key)])
    async def stream(job_id: str, request: Request) -> Response:
        job = _require_job(job_id)
        if job["status"] != SUCCEEDED:
            raise HTTPException(status_code=409, detail="任务尚未完成，无法播放")
        flac = manager.job_dir(job_id) / "audio.flac"
        if not flac.exists():
            raise HTTPException(status_code=410, detail="音频文件已被清理")
        m4a = flac.with_suffix(".m4a")
        if not m4a.exists():
            transcode_flac_to_m4a(flac, m4a)  # 失败抛 MediaError → 500
        return _range_response(m4a, "audio/mp4", request.headers.get("Range"))

    @app.get("/api/jobs/{job_id}/score.abc", dependencies=[Depends(require_key)])
    async def score(job_id: str) -> Response:
        job = _require_job(job_id)
        if job["status"] != SUCCEEDED:
            raise HTTPException(status_code=409, detail="任务尚未完成，乐谱不可用")
        path = manager.job_dir(job_id) / "score.abc"
        if not path.exists():
            raise HTTPException(status_code=409, detail="本次生成没有乐谱")
        text = path.read_text(encoding="utf-8")
        return PlainTextResponse(text, media_type="text/plain; charset=utf-8")

    return app


# ---------- 组装响应 ----------

def _require_job(job_id: str) -> dict[str, Any]:
    job = manager.get(job_id)
    if job is None:
        raise NotFoundError()
    return job


def _summary(job: dict[str, Any]) -> dict[str, Any]:
    params = job["params"]
    return {
        "id": job["id"],
        "status": job["status"],
        "created_at": job["created_at"],
        "style": params.get("style", ""),
        "lyrics_excerpt": (params.get("lyrics") or "")[:200],
        "cot": params.get("cot", "full"),
        "audio_seconds": (job["result"] or {}).get("audio_seconds") if job["result"] else None,
        "seed": params.get("seed"),
    }


def _detail(job: dict[str, Any]) -> dict[str, Any]:
    params = job["params"]
    progress = job["progress"] or {"phase": _phase_for(job), "message": "", "fraction": None, "tokens": 0}
    return {
        "id": job["id"],
        "status": job["status"],
        "created_at": job["created_at"],
        "updated_at": job["updated_at"],
        "params": params,
        "progress": progress,
        "error": job["error"],
        "result": job["result"],
        "urls": {
            "audio": f"/api/jobs/{job['id']}/audio",
            "stream": f"/api/jobs/{job['id']}/stream",
            "score": f"/api/jobs/{job['id']}/score.abc",
        },
    }


def _phase_for(job: dict[str, Any]) -> str:
    if job["status"] == SUCCEEDED:
        return "done"
    if job["status"] == QUEUED:
        return "queued"
    return "planning"


def _range_response(path: Path, content_type: str, range_header: str | None) -> Response:
    size = path.stat().st_size
    rng = parse_range(range_header, size)
    if rng is None:
        data = path.read_bytes()
        return Response(content=data, media_type=content_type,
                        headers={"Accept-Ranges": "bytes", "Content-Length": str(size)})
    start, end = rng
    with path.open("rb") as f:
        f.seek(start)
        data = f.read(end - start + 1)
    return Response(
        content=data,
        status_code=206,
        media_type=content_type,
        headers={
            "Content-Range": f"bytes {start}-{end}/{size}",
            "Accept-Ranges": "bytes",
            "Content-Length": str(len(data)),
        },
    )
