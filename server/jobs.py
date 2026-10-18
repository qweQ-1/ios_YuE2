"""任务管理：SQLite 持久化 + 单 worker 串行队列。"""
from __future__ import annotations

import json
import logging
import sqlite3
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .engine import JobCancelled, YuE2Engine

logger = logging.getLogger(__name__)

QUEUED, RUNNING, SUCCEEDED, FAILED, CANCELLED = "queued", "running", "succeeded", "failed", "cancelled"


class NotFoundError(Exception):
    def __init__(self, message: str = "任务不存在") -> None:
        super().__init__(message)


class ConflictError(Exception):
    def __init__(self, message: str) -> None:
        super().__init__(message)


def _utcnow() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _short_job_id() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    return f"{stamp}-{uuid.uuid4().hex[:8]}"


class JobManager:
    """单 GPU 串行执行；进程重启时把 running 标为 failed（queued 保留待重入队需要人工提交，统一标 failed 并在原因里说明，避免旧任务永久悬挂在队列里）。"""

    def __init__(self, engine: YuE2Engine, data_dir: Path, keep_jobs: int = 100) -> None:
        self.engine = engine
        self.data_dir = Path(data_dir)
        self.keep_jobs = keep_jobs
        self.db_path = self.data_dir / "jobs.db"
        self.jobs_root = self.data_dir / "jobs"
        self._pool: ThreadPoolExecutor | None = None
        self._pending: list[str] = []          # FIFO 队列（内存）
        self._pending_lock = threading.Lock()
        self._cancel_flags: dict[str, threading.Event] = {}
        self._cancelled_lock = threading.Lock()
        self._worker_busy = False
        self._db = self._connect()
        self._recover()

    # ---------- 存储 ----------

    def _connect(self) -> sqlite3.Connection:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.jobs_root.mkdir(parents=True, exist_ok=True)
        db = sqlite3.connect(str(self.db_path), check_same_thread=False, timeout=30,
                            isolation_level=None)  # autocommit：避免 with 块在无事务时报错
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA synchronous=NORMAL")
        db.execute(
            """
            CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,
                status TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                params TEXT NOT NULL,
                progress TEXT,
                error TEXT,
                result TEXT
            )
            """
        )
        db.execute("CREATE INDEX IF NOT EXISTS idx_jobs_created ON jobs(created_at DESC)")
        db.commit()
        return db

    def _recover(self) -> None:
        """重启恢复：未结束的任务标 failed，APP 侧可据此提示重新创作。"""
        with self._db:
            self._db.execute(
                "UPDATE jobs SET status=?, error=?, updated_at=? WHERE status IN (?, ?)",
                (FAILED, "服务器重启，任务中断；请重新提交", _utcnow(), RUNNING, QUEUED),
            )

    # ---------- 查询 ----------

    def get(self, job_id: str) -> dict | None:
        row = self._db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
        return self._row_to_dict(row) if row else None

    def list(self, limit: int = 50) -> tuple[list[dict], int]:
        total = self._db.execute("SELECT COUNT(*) AS c FROM jobs").fetchone()["c"]
        rows = self._db.execute(
            "SELECT * FROM jobs ORDER BY created_at DESC, id DESC LIMIT ?", (limit,)
        ).fetchall()
        return [self._row_to_dict(r) for r in rows], total

    @staticmethod
    def _row_to_dict(row: sqlite3.Row) -> dict:
        return {
            "id": row["id"],
            "status": row["status"],
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
            "params": json.loads(row["params"]),
            "progress": json.loads(row["progress"]) if row["progress"] else None,
            "error": row["error"],
            "result": json.loads(row["result"]) if row["result"] else None,
        }

    def active_id(self) -> str | None:
        row = self._db.execute(
            "SELECT id FROM jobs WHERE status=? ORDER BY created_at DESC LIMIT 1", (RUNNING,)
        ).fetchone()
        return row["id"] if row else None

    def queue_depth(self) -> int:
        with self._pending_lock:
            return len(self._pending) + (1 if self._worker_busy and self._pending else 0)

    # ---------- 变更 ----------

    def _update(self, job_id: str, **fields: Any) -> None:
        if not fields:
            return
        fields["updated_at"] = _utcnow()
        cols = ", ".join(f"{k}=?" for k in fields)
        values: list[Any] = []
        for k, v in fields.items():
            if k in ("params", "progress", "result") and v is not None:
                values.append(json.dumps(v, ensure_ascii=False))
            else:
                values.append(v)
        with self._db:
            self._db.execute(f"UPDATE jobs SET {cols} WHERE id=?", (*values, job_id))

    def submit(self, params: dict) -> str:
        job_id = _short_job_id()
        now = _utcnow()
        progress = {"phase": "queued", "message": "排队中", "fraction": None, "tokens": 0}
        with self._db:
            self._db.execute(
                "INSERT INTO jobs (id, status, created_at, updated_at, params, progress, error, result)"
                " VALUES (?, ?, ?, ?, ?, ?, NULL, NULL)",
                (job_id, QUEUED, now, now, json.dumps(params, ensure_ascii=False),
                 json.dumps(progress, ensure_ascii=False)),
            )
        with self._pending_lock:
            self._pending.append(job_id)
        self._dispatch()
        return job_id

    def cancel(self, job_id: str) -> str:
        job = self.get(job_id)
        if job is None:
            raise NotFoundError()
        with self._pending_lock:
            in_pending = job_id in self._pending
        if in_pending:
            self._pending = [j for j in self._pending if j != job_id]
            with self._cancelled_lock:
                self._cancel_flags.pop(job_id, None)
            self._update(job_id, status=CANCELLED, progress={"phase": "queued", "message": "已取消", "fraction": None, "tokens": 0})
            return CANCELLED
        if job["status"] == RUNNING:
            with self._cancelled_lock:
                self._cancel_flags.setdefault(job_id, threading.Event()).set()
            # 标志已置，worker 在阶段边界把任务落为 cancelled
            return CANCELLED
        raise ConflictError("任务已结束，无法取消")

    # ---------- Worker ----------

    def start(self) -> None:
        if self._pool is None:
            self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="yue2-job")
            # 预热模型（后台）
            self._pool.submit(self.engine.warmup)
            self._dispatch()

    def stop(self) -> None:
        with self._cancelled_lock:
            for ev in self._cancel_flags.values():
                ev.set()
        if self._pool is not None:
            self._pool.shutdown(wait=False, cancel_futures=True)
            self._pool = None

    def _dispatch(self) -> None:
        if self._pool is None:
            return
        with self._pending_lock:
            if self._worker_busy or not self._pending:
                return
            job_id = self._pending.pop(0)
            self._worker_busy = True
        self._pool.submit(self._run, job_id)

    def _run(self, job_id: str) -> None:
        try:
            job = self.get(job_id)
            if job is None or job["status"] != QUEUED:
                return
            cancel_event = threading.Event()
            with self._cancelled_lock:
                self._cancel_flags[job_id] = cancel_event

            self._update(job_id, status=RUNNING)
            state = {"phase": "planning", "tokens": 0}

            def on_phase(phase: str, message: str) -> None:
                state["phase"] = phase
                self._update(job_id, progress={"phase": phase, "message": message,
                                               "fraction": None, "tokens": state["tokens"]})

            def on_token(token_phase: str) -> None:
                if token_phase in ("abc", "semantic"):
                    state["tokens"] += 1
                self._update(job_id, progress={"phase": state["phase"],
                                               "message": f"{'规划乐谱' if token_phase == 'abc' else '谱写旋律'} · {state['tokens']} tokens",
                                               "fraction": None, "tokens": state["tokens"]})

            try:
                result = self.engine.run(
                    request=job["params"],
                    on_phase=on_phase,
                    on_token=on_token,
                    cancelled=cancel_event.is_set,
                    output_dir=self.jobs_root / job_id,
                )
            except JobCancelled:
                self._update(job_id, status=CANCELLED,
                             progress={"phase": "queued", "message": "已取消", "fraction": None,
                                       "tokens": state["tokens"]})
            except Exception as e:  # noqa: BLE001
                logger.exception("job %s failed", job_id)
                self._update(job_id, status=FAILED,
                             error=str(e) or e.__class__.__name__,
                             progress={"phase": "decoding", "message": "失败", "fraction": None,
                                       "tokens": state["tokens"]})
            else:
                self._update(job_id, status=SUCCEEDED, result=result,
                             progress={"phase": "done", "message": "完成", "fraction": 1.0,
                                       "tokens": state["tokens"]})
            self._prune()
        finally:
            with self._cancelled_lock:
                self._cancel_flags.pop(job_id, None)
            with self._pending_lock:
                self._worker_busy = False
            self._dispatch()

    def _prune(self) -> None:
        """只保留最近 keep_jobs 个任务的产物。"""
        try:
            rows = self._db.execute(
                "SELECT id FROM jobs ORDER BY created_at DESC, id DESC LIMIT -1 OFFSET ?",
                (self.keep_jobs,),
            ).fetchall()
            stale = [r["id"] for r in rows]
            if not stale:
                return
            with self._db:
                self._db.executemany("DELETE FROM jobs WHERE id=?", [(j,) for j in stale])
            for j in stale:
                _rmtree(self.jobs_root / j)
        except Exception:  # noqa: BLE001
            logger.exception("prune failed")

    def job_dir(self, job_id: str) -> Path:
        return self.jobs_root / job_id


def _rmtree(path: Path) -> None:
    import shutil
    shutil.rmtree(path, ignore_errors=True)
