"""JobManager 测试：stub 引擎 + SQLite 真跑（不依赖 fastapi）。"""
from __future__ import annotations

import json
import sys
import time
import types
from pathlib import Path

import pytest

from server.config import Config
from server.engine import YuE2Engine
from server.jobs import (CANCELLED, FAILED, QUEUED, RUNNING, SUCCEEDED,
                         ConflictError, JobManager, NotFoundError)


@pytest.fixture()
def fake_soundfile(monkeypatch):
    fake = types.ModuleType("soundfile")
    fake.write = lambda path, data, sr, subtype=None: Path(path).write_bytes(b"FLAC")  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "soundfile", fake)


def make_manager(tmp_path: Path, keep_jobs: int = 3) -> JobManager:
    cfg = Config(host="127.0.0.1", port=1, model="m", vae="v", api_key="",
                 data_dir=tmp_path / "data", device="cpu", memory_budget_gib=24,
                 keep_jobs=keep_jobs, stub=True, max_lyrics=20000, hf_token=None,
                 stub_fast=True, jobs_limit_cap=50)
    engine = YuE2Engine(cfg)
    return JobManager(engine, cfg.data_dir, cfg.keep_jobs)


def wait_for(predicate, timeout: float = 5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return False


def test_submit_runs_to_success(tmp_path, fake_soundfile):
    m = make_manager(tmp_path)
    m.start()
    try:
        job_id = m.submit({"style": "city pop", "lyrics": "[Verse]", "cot": "full"})
        assert wait_for(lambda: (m.get(job_id) or {}).get("status") == SUCCEEDED), "任务未在时限内完成"
        job = m.get(job_id)
        assert job["status"] == SUCCEEDED
        assert job["progress"]["phase"] == "done"
        assert job["result"]["stub"] is True
        artifacts = m.job_dir(job_id)
        assert (artifacts / "audio.flac").exists()
        assert (artifacts / "score.abc").exists()
        # result.json 落盘
        assert json.loads((artifacts / "result.json").read_text(encoding="utf-8"))["stub"] is True
    finally:
        m.stop()


def test_queued_task_is_removed_by_cancel(tmp_path, fake_soundfile):
    # 未 start() 的 manager：任务入队但不执行，直接取消排队项
    m = make_manager(tmp_path)
    job_id = m.submit({"style": "s", "lyrics": "l", "cot": "off"})
    assert m.get(job_id)["status"] == QUEUED
    assert m.cancel(job_id) == CANCELLED
    assert m.get(job_id)["status"] == CANCELLED


def test_cancel_after_finish_conflicts(tmp_path, fake_soundfile):
    m = make_manager(tmp_path)
    job_id = m.submit({"style": "s", "lyrics": "l"})
    m.start()
    try:
        assert wait_for(lambda: m.get(job_id)["status"] == SUCCEEDED)
        with pytest.raises(ConflictError):
            m.cancel(job_id)
    finally:
        m.stop()


def test_unknown_job_raises_not_found(tmp_path):
    m = make_manager(tmp_path)
    with pytest.raises(NotFoundError):
        m.cancel("nope")
    assert m.get("nope") is None


def test_restart_marks_running_as_failed(tmp_path, fake_soundfile):
    m = make_manager(tmp_path)
    m.start()
    job_id = m.submit({"style": "s", "lyrics": "l"})
    # 等它进入 running（stub_fast 下很快，用轮询抢窗口；抢不到就跳过本断言的强校验）
    saw_running = wait_for(lambda: m.get(job_id)["status"] in (RUNNING, SUCCEEDED), timeout=1.0)
    m.stop()
    # 等旧 worker 完全退出后再造数据，避免与恢复逻辑竞争
    assert wait_for(lambda: m.get(job_id)["status"] in (SUCCEEDED, FAILED, CANCELLED), timeout=2.0)
    # 重建（模拟重启）：直接操作 db 造一个 running
    import sqlite3
    db = sqlite3.connect(str(m.db_path))
    db.execute("INSERT INTO jobs (id, status, created_at, updated_at, params, progress, error, result)"
               " VALUES ('fake-running', 'running', '2026-10-18T00:00:00Z', '2026-10-18T00:00:00Z', '{}', NULL, NULL, NULL)")
    db.commit()
    db.close()
    m2 = make_manager(tmp_path)
    recovered = m2.get("fake-running")
    assert recovered["status"] == FAILED
    assert "重启" in recovered["error"]
    if saw_running:
        # stop() 会把在飞任务置为取消；succeeded / cancelled 都是合理终态
        assert m.get(job_id)["status"] in (SUCCEEDED, CANCELLED)


def test_prune_keeps_recent_jobs(tmp_path, fake_soundfile):
    keep = 3
    m = make_manager(tmp_path, keep_jobs=keep)
    m.start()
    try:
        ids = [m.submit({"style": f"s{i}", "lyrics": "l"}) for i in range(keep + 2)]

        def all_settled_and_pruned() -> bool:
            rows, _ = m.list(limit=50)
            return (bool(rows) and len(rows) <= keep
                    and all(r["status"] in (SUCCEEDED, FAILED, CANCELLED) for r in rows))

        assert wait_for(all_settled_and_pruned, timeout=20), "任务未全部结束/未触发清理"
        items, total = m.list(limit=50)
        assert total == keep
        # 恰好保留 keep 份产物；同秒提交时保留集合由 id 排序决定，不假设是哪几个
        existing = [jid for jid in ids if m.job_dir(jid).exists()]
        assert len(existing) == keep
        pruned = [jid for jid in ids if jid not in existing]
        assert len(pruned) == len(ids) - keep
    finally:
        m.stop()


def test_list_orders_newest_first(tmp_path, fake_soundfile):
    m = make_manager(tmp_path, keep_jobs=50)
    m.start()
    try:
        ids = [m.submit({"style": f"s{i}", "lyrics": "l"}) for i in range(3)]
        for jid in ids:
            assert wait_for(lambda j=jid: (m.get(j) or {}).get("status") == SUCCEEDED)
        items, total = m.list()
        assert total == 3
        # newest-first：按 (created_at, id) 降序稳定返回
        keys = [(i["created_at"], i["id"]) for i in items]
        assert keys == sorted(keys, reverse=True)
        assert set(i["id"] for i in items) == set(ids)
    finally:
        m.stop()
