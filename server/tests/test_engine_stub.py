"""Stub 引擎测试：用 monkeypatch 绕过 soundfile（本地可能未装）。"""
from __future__ import annotations

import json
import sys
import types
from pathlib import Path

import pytest

from server.config import Config
from server.engine import EngineError, JobCancelled, YuE2Engine


@pytest.fixture()
def stub_config(tmp_path: Path) -> Config:
    return Config(host="127.0.0.1", port=1, model="m-a-p/YuE2-3B", vae="m-a-p/YuE2-Vae",
                  api_key="", data_dir=tmp_path / "data", device="cpu",
                  memory_budget_gib=24, keep_jobs=10, stub=True, max_lyrics=20000,
                  hf_token=None, stub_fast=True, jobs_limit_cap=50)


@pytest.fixture()
def fake_soundfile(monkeypatch):
    """即使没有真 soundfile 也提供写文件的假实现。"""
    written: dict[str, int] = {}

    fake = types.ModuleType("soundfile")

    def write(path, data, samplerate, subtype=None):
        Path(path).write_bytes(b"FAKEFLAC" + str(getattr(data, "shape", len(data))).encode())
        written[path] = 1

    fake.write = write  # type: ignore[attr-defined]
    monkeypatch.setitem(sys.modules, "soundfile", fake)
    return written


def test_stub_info(stub_config):
    e = YuE2Engine(stub_config)
    info = e.info()
    assert info["stub"] is True
    assert info["engine"] == "ready"
    assert info["device"] == "stub"


def test_stub_generates_artifacts(stub_config, fake_soundfile, tmp_path):
    e = YuE2Engine(stub_config)
    phases: list[str] = []
    tokens: list[str] = []
    out = tmp_path / "job"
    result = e.run(
        request={"style": "s", "lyrics": "l", "cot": "full"},
        on_phase=lambda p, m: phases.append(p),
        on_token=lambda t: tokens.append(t),
        cancelled=lambda: False,
        output_dir=out,
    )
    assert phases == ["planning", "semantic", "synthesizing", "decoding"]
    assert set(tokens) == {"abc", "semantic"}
    assert result["stub"] is True
    assert result["audio_seconds"] == 30.0
    assert result["truncated"] == {"abc": False, "semantic": False}
    assert (out / "audio.flac").exists()
    score = (out / "score.abc").read_text(encoding="utf-8")
    assert score.startswith("X:1")
    saved = json.loads((out / "result.json").read_text(encoding="utf-8"))
    assert saved["stub"] is True


def test_stub_cancel_raises(stub_config, fake_soundfile, tmp_path):
    e = YuE2Engine(stub_config)
    with pytest.raises(JobCancelled):
        e.run(request={"style": "s", "lyrics": "l"},
              on_phase=lambda p, m: None,
              on_token=lambda t: None,
              cancelled=lambda: True,
              output_dir=tmp_path / "job")


def test_real_engine_without_yue2_gives_chinese_error(tmp_path):
    """未安装 yue2-infer 时（本地就是），真路径必须给中文错误而不是裸 ImportError。"""
    c = Config(host="127.0.0.1", port=1, model="m", vae="v", api_key="",
               data_dir=tmp_path / "data", device="cpu", memory_budget_gib=24,
               keep_jobs=10, stub=False, max_lyrics=100, hf_token=None,
               stub_fast=True, jobs_limit_cap=50)
    e = YuE2Engine(c)
    e.warmup()
    info = e.info()
    if info["engine"] == "error":
        assert "yue2-infer" in info["engine_message"]
    else:  # 机器上碰巧装了 yue2-infer：至少确认 ready
        assert info["engine"] == "ready"
