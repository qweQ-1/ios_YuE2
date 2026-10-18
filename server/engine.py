"""YuE2 推理引擎封装：真模型路径 + Stub 演示路径。

真模型路径通过 YuE2Pipeline 的分阶段 API 驱动：
plan → generate_semantic → synthesize → decode，全程回报阶段与 token 数，
并在阶段边界检查取消标志。
"""
from __future__ import annotations

import json
import logging
import math
import threading
import time
from pathlib import Path
from typing import Callable

from .config import Config

logger = logging.getLogger(__name__)

PhaseCallback = Callable[[str, str], None]     # (phase, message)
TokenCallback = Callable[[str], None]           # ("abc" | "semantic")
CancelCheck = Callable[[], bool]


class EngineError(RuntimeError):
    """模型加载或生成过程失败（中文信息）。"""


class JobCancelled(Exception):
    """任务在阶段边界被取消。"""


class YuE2Engine:
    """推理引擎。构造时不加载模型；warmup() 在后台线程预热。"""

    def __init__(self, config: Config) -> None:
        self.config = config
        self.stub = config.stub
        self._pipeline = None            # 真模型模式下的 YuE2Pipeline
        self._lock = threading.Lock()
        self._state = "cold"             # cold | loading | ready | error
        self._message = ""
        self._stub_engine = StubEngine(config) if config.stub else None

    # ---------- 状态 ----------

    @property
    def state(self) -> str:
        with self._lock:
            return self._state

    def info(self) -> dict:
        with self._lock:
            state, message = self._state, self._message
        if self.stub:
            return {"model": self.config.model, "device": "stub", "stub": True,
                    "engine": "ready", "engine_message": "Stub 演示引擎（未加载真模型）"}
        return {"model": self.config.model, "device": self.config.device,
                "stub": False, "engine": state, "engine_message": message}

    # ---------- 加载 ----------

    def warmup(self) -> None:
        """后台预热。幂等；失败进入 error 状态并记录原因。Stub 模式直接就绪。"""
        if self.stub:
            with self._lock:
                self._state, self._message = "ready", "Stub 演示引擎（未加载真模型）"
            return
        with self._lock:
            if self._state in ("loading", "ready"):
                return
            self._state, self._message = "loading", "加载模型…"
        try:
            self._load_pipeline()
        except Exception as e:  # noqa: BLE001 — 状态可见性优先
            logger.exception("engine warmup failed")
            with self._lock:
                self._state, self._message = "error", f"模型加载失败：{e}"
        else:
            with self._lock:
                self._state, self._message = "ready", ""

    def _load_pipeline(self):
        if self._pipeline is not None:
            return self._pipeline
        try:
            from yue2 import YuE2Pipeline
        except Exception as e:  # noqa: BLE001
            raise EngineError(
                "未安装 yue2-infer：请按 README 安装（pip install yue2-infer）") from e
        logger.info("loading YuE2Pipeline model=%s vae=%s device=%s",
                    self.config.model, self.config.vae, self.config.device)
        self._pipeline = YuE2Pipeline.from_pretrained(
            self.config.model, vae=self.config.vae,
            device=self.config.device,
            memory_budget_gib=self.config.memory_budget_gib,
            token=self.config.hf_token,
            progress=False,
        )
        return self._pipeline

    # ---------- 生成 ----------

    def run(self, request: dict, on_phase: PhaseCallback, on_token: TokenCallback,
            cancelled: CancelCheck, output_dir: Path) -> dict:
        """执行一整首歌曲生成，落盘 artifacts，返回 result 摘要。"""
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)

        style = request["style"]
        lyrics = request["lyrics"]
        cot = request.get("cot", "full")
        abc = request.get("abc") or None
        seed = int(request.get("seed") or 831001)
        guidance = request.get("guidance")

        if self.stub:
            return self._run_stub(request, on_phase, on_token, cancelled, output_dir)

        return self._run_real(style=style, lyrics=lyrics, cot=cot, abc=abc, seed=seed,
                              guidance=guidance, request=request,
                              on_phase=on_phase, on_token=on_token,
                              cancelled=cancelled, output_dir=output_dir)

    def _check(self, cancelled: CancelCheck) -> None:
        if cancelled and cancelled():
            raise JobCancelled()

    def _run_real(self, *, style, lyrics, cot, abc, seed, guidance, request,
                  on_phase, on_token, cancelled, output_dir) -> dict:
        try:
            from yue2.protocol import SongRequest
        except Exception as e:  # noqa: BLE001
            raise EngineError("未安装 yue2-infer：请按 README 安装（pip install yue2-infer）") from e

        try:
            req = SongRequest(style=style, lyrics=lyrics, cot=cot, abc=abc, seed=seed,
                              cfg_scale=guidance, id="song")
        except Exception as e:  # noqa: BLE001
            raise EngineError(f"请求参数不合法：{e}") from e

        pipe = self._load_pipeline()
        token_counts = {"abc": 0, "semantic": 0}

        def _counting_token(token_phase: str, _token: int) -> None:
            if token_phase in token_counts:
                token_counts[token_phase] += 1
            on_token(token_phase)

        started = time.perf_counter()

        # 1) 规划乐谱
        self._check(cancelled)
        on_phase("planning", "规划乐谱" if cot != "off" else "准备指令")
        plan_started = time.perf_counter()
        plan = pipe.plan(request=req, cancelled=cancelled, on_token=_counting_token)
        abc_timing = dict(plan.timing or {})
        self._check(cancelled)

        # 2) 语义 token
        on_phase("semantic", "谱写旋律")
        semantic_started = time.perf_counter()
        semantic = pipe.generate_semantic(plan, cancelled=cancelled, on_token=_counting_token)
        semantic_timing = dict(semantic.timing or {})
        self._check(cancelled)

        # 3) NAR 流匹配合成 latent
        on_phase("synthesizing", "合成音色")
        nar_started = time.perf_counter()
        latents = pipe.synthesize(semantic, cancelled=cancelled)
        nar_seconds = time.perf_counter() - nar_started
        self._check(cancelled)

        # 4) VAE 解码
        on_phase("decoding", "渲染音频")
        vae_started = time.perf_counter()
        audio = pipe.decode(latents)
        vae_seconds = time.perf_counter() - vae_started

        result = self._write_artifacts(output_dir=output_dir, request=request,
                                       plan_abc=plan.abc, audio=audio,
                                       plan_truncated=plan.truncated,
                                       semantic_truncated=semantic.truncated,
                                       timing={
                                           "abc": abc_timing,
                                           "semantic": semantic_timing,
                                           "nar_seconds": round(nar_seconds, 3),
                                           "vae_seconds": round(vae_seconds, 3),
                                           "e2e_seconds": round(time.perf_counter() - started, 3),
                                       },
                                       tokens=token_counts)
        on_phase("decoding", "渲染音频")
        return result

    def _write_artifacts(self, *, output_dir, request, plan_abc, audio,
                         plan_truncated, semantic_truncated, timing, tokens) -> dict:
        import soundfile as sf
        import numpy as np

        audio_path = output_dir / "audio.flac"
        sf.write(str(audio_path), audio, 48000, subtype="PCM_24")

        if plan_abc:
            (output_dir / "score.abc").write_text(plan_abc, encoding="utf-8")

        result = {
            "audio_seconds": round(float(len(audio)) / 48000, 2),
            "sample_rate": 48000,
            "truncated": {"abc": bool(plan_truncated), "semantic": bool(semantic_truncated)},
            "timing": timing,
            "tokens": tokens,
            "stub": False,
        }
        (output_dir / "request.json").write_text(
            json.dumps(request, ensure_ascii=False, indent=2), encoding="utf-8")
        (output_dir / "result.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        return result

    # ---------- Stub ----------

    def _run_stub(self, request, on_phase, on_token, cancelled, output_dir) -> dict:
        return self._stub_engine.run(request, on_phase=on_phase, on_token=on_token,
                                     cancelled=cancelled, output_dir=output_dir)

    def close(self) -> None:
        pipe, self._pipeline = self._pipeline, None
        if pipe is not None:
            try:
                pipe.close()
            except Exception:  # noqa: BLE001
                logger.exception("pipeline close failed")


class StubEngine:
    """无 GPU 演示引擎：生成正弦音频与示意 ABC，不 import torch/yue2。"""

    def __init__(self, config: Config) -> None:
        self.config = config
        self._step = 0.05 if config.stub_fast else 1.5

    def run(self, request: dict, *, on_phase, on_token, cancelled, output_dir) -> dict:
        import soundfile as sf
        import numpy as np

        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        step = self._step

        phases = [
            ("planning", "规划乐谱（Stub）"),
            ("semantic", "谱写旋律（Stub）"),
            ("synthesizing", "合成音色（Stub）"),
            ("decoding", "渲染音频（Stub）"),
        ]
        for phase, label in phases:
            if cancelled and cancelled():
                raise JobCancelled()
            on_phase(phase, label)
            on_token("abc" if phase == "planning" else "semantic")
            if step > 0:
                time.sleep(step)

        if cancelled and cancelled():
            raise JobCancelled()

        # 30 秒正弦「歌曲」
        sr = 48000
        seconds = 30
        t = np.linspace(0, seconds, sr * seconds, endpoint=False)
        freqs = [220.0, 277.2, 329.6]
        wave = sum(np.sin(2 * math.pi * f * t) / len(freqs) for f in freqs)
        wave = (wave * 0.6).astype("float32")
        sf.write(str(output_dir / "audio.flac"), wave, sr, subtype="PCM_24")

        abc = (
            "X:1\n"
            "T:YuE2 Stub Song\n"
            "C:YuE2-Studio (stub)\n"
            "M:4/4\n"
            "L:1/8\n"
            "Q:1/4=100\n"
            "K:C\n"
            "|: CDEF GABc | cBAG FEDC |\n"
            "w: Stub verse line\n"
            "| CDEF GABc | cBAG FEDC :|\n"
            "w: Stub chorus line\n"
        )
        (output_dir / "score.abc").write_text(abc, encoding="utf-8")

        result = {
            "audio_seconds": round(float(len(wave)) / sr, 2),
            "sample_rate": sr,
            "truncated": {"abc": False, "semantic": False},
            "timing": {"nar_seconds": 0, "vae_seconds": 0, "e2e_seconds": round(step * len(phases), 3)},
            "tokens": {"abc": 32, "semantic": 128},
            "stub": True,
        }
        (output_dir / "request.json").write_text(
            json.dumps(request, ensure_ascii=False, indent=2), encoding="utf-8")
        (output_dir / "result.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        return result
