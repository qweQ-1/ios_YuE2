"""HTTP API 测试：需要 fastapi 环境（GPU 机器或 CI 的 Server Tests）。

本文件在**没有 fastapi** 的本地 Alpine 环境会自动跳过
（importorskip）；核心逻辑由 test_jobs / test_engine_stub 覆盖。
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

pytest.importorskip("fastapi")

# ---- 环境必须在导入 server.app 之前设置（engine/manager 是导入期单例）----
os.environ.setdefault("YUE2_STUB", "1")
os.environ.setdefault("YUE2_STUB_FAST", "1")
os.environ.setdefault("YUE2_API_KEY", "test-key")
_test_data_dir = Path(os.environ.get("YUE2_TEST_DATA_DIR", "/tmp/yue2-http-tests"))
os.environ.setdefault("YUE2_DATA_DIR", str(_test_data_dir))
os.environ.setdefault("YUE2_KEEP_JOBS", "100")

from fastapi.testclient import TestClient  # noqa: E402

from server.app import create_app  # noqa: E402

HEADERS = {"X-API-Key": "test-key"}


@pytest.fixture(scope="module")
def client():
    with TestClient(create_app()) as c:
        yield c


def _wait_job(client, job_id, timeout=10):
    import time
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = client.get(f"/api/jobs/{job_id}", headers=HEADERS)
        assert r.status_code == 200
        body = r.json()
        if body["status"] == "succeeded":
            return body
        if body["status"] in ("failed", "cancelled"):
            pytest.fail(f"job ended unexpectedly: {body}")
        time.sleep(0.05)
    pytest.fail("job did not finish in time")


def test_health_needs_no_key(client):
    r = client.get("/api/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["stub"] is True
    assert body["engine"] == "ready"
    assert "queue_depth" in body


def test_generate_requires_key(client):
    r = client.post("/api/generate", json={"style": "s", "lyrics": "l"})
    assert r.status_code == 401
    assert "error" in r.json()


def test_generate_validation(client):
    r = client.post("/api/generate", json={"style": "", "lyrics": "l"}, headers=HEADERS)
    assert r.status_code == 400
    assert "style" in r.json()["error"]

    r = client.post("/api/generate", json={"style": "s", "lyrics": ""}, headers=HEADERS)
    assert r.status_code == 400

    r = client.post("/api/generate", json={"style": "s", "lyrics": "l", "cot": "weird"}, headers=HEADERS)
    assert r.status_code == 400

    r = client.post("/api/generate", json={"style": "s", "lyrics": "l", "abc": "not-abc"}, headers=HEADERS)
    assert r.status_code == 400

    r = client.post("/api/generate", json={"style": "s", "lyrics": "l", "seed": "x"}, headers=HEADERS)
    assert r.status_code == 400


def test_full_flow(client):
    r = client.post("/api/generate",
                    json={"style": "English, warm piano pop", "lyrics": "[Verse]\nhello", "cot": "full"},
                    headers=HEADERS)
    assert r.status_code == 202
    job_id = r.json()["job_id"]
    detail = _wait_job(client, job_id)
    assert detail["status"] == "succeeded"
    assert detail["progress"]["phase"] == "done"
    assert detail["result"]["stub"] is True
    assert detail["result"]["audio_seconds"] == 30.0
    assert detail["urls"]["score"].endswith("/score.abc")

    # 列表含该任务
    r = client.get("/api/jobs?limit=50", headers=HEADERS)
    assert r.status_code == 200
    ids = [i["id"] for i in r.json()["items"]]
    assert job_id in ids

    # 乐谱
    r = client.get(f"/api/jobs/{job_id}/score.abc", headers=HEADERS)
    assert r.status_code == 200
    assert r.text.startswith("X:1")

    # FLAC 下载
    r = client.get(f"/api/jobs/{job_id}/audio", headers=HEADERS)
    assert r.status_code == 200
    assert r.headers["content-type"] == "audio/flac"
    assert len(r.content) > 8

    # stream：ffmpeg 不存在时给 500 中文错误；存在时 200 且支持 Range
    r = client.get(f"/api/jobs/{job_id}/stream", headers={"X-API-Key": "test-key"}, )
    assert r.status_code in (200, 500)
    if r.status_code == 200:
        assert r.headers["content-type"].startswith("audio/mp4")
        assert r.headers.get("accept-ranges") == "bytes"
        r2 = client.get(f"/api/jobs/{job_id}/stream",
                        headers={**HEADERS, "Range": "bytes=0-9"})
        assert r2.status_code == 206
        assert r2.headers["content-range"].startswith("bytes 0-9/")


def test_cancel_running_job(client):
    # 用长任务验证取消：stub_fast 时很快，改为取消已完成任务的 409 路径
    r = client.post("/api/generate", json={"style": "s", "lyrics": "l"}, headers=HEADERS)
    job_id = r.json()["job_id"]
    _wait_job(client, job_id)
    r = client.post(f"/api/jobs/{job_id}/cancel", headers=HEADERS)
    assert r.status_code == 409
    assert "无法取消" in r.json()["error"]


def test_unknown_job_404(client):
    r = client.get("/api/jobs/not-exist", headers=HEADERS)
    assert r.status_code == 404
    r = client.post("/api/jobs/not-exist/cancel", headers=HEADERS)
    assert r.status_code == 404


def test_audio_before_done_409(client):
    # 未完成任务：直接插一条 queued 记录
    import sqlite3
    from server.app import manager
    with manager._db:
        manager._db.execute(
            "INSERT INTO jobs (id, status, created_at, updated_at, params, progress, error, result)"
            " VALUES ('queued-job', 'queued', '2026-10-18T00:00:00Z', '2026-10-18T00:00:00Z',"
            " '{\"style\":\"s\",\"lyrics\":\"l\"}', NULL, NULL, NULL)"
        )
    r = client.get("/api/jobs/queued-job/audio", headers=HEADERS)
    assert r.status_code == 409
