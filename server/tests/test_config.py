"""配置解析测试（不依赖 fastapi）。"""
from __future__ import annotations

import os
from pathlib import Path

from server.config import Config, get_config, reset_config


def test_defaults():
    env = {k: v for k, v in os.environ.items() if not k.startswith("YUE2_") and k != "HF_TOKEN"}
    old = dict(os.environ)
    os.environ.clear()
    os.environ.update(env)
    try:
        c = Config.from_env()
    finally:
        os.environ.clear()
        os.environ.update(old)
    assert c.host == "0.0.0.0"
    assert c.port == 8420
    assert c.model == "m-a-p/YuE2-3B"
    assert c.vae == "m-a-p/YuE2-Vae"
    assert c.api_key == ""
    assert c.device == "auto"
    assert c.keep_jobs == 100
    assert c.stub is False
    assert c.max_lyrics == 20000
    assert c.hf_token is None
    assert c.jobs_limit_cap == 200


def test_env_overrides():
    old = dict(os.environ)
    os.environ["YUE2_PORT"] = "9001"
    os.environ["YUE2_STUB"] = "1"
    os.environ["YUE2_API_KEY"] = "k"
    os.environ["YUE2_KEEP_JOBS"] = "7"
    os.environ["YUE2_STUB_FAST"] = "yes"
    os.environ["YUE2_DEVICE"] = "cpu"
    os.environ["YUE2_DATA_DIR"] = "/tmp/yue2-cfg-test"
    os.environ["YUE2_MEMORY_BUDGET_GIB"] = "12"
    os.environ["YUE2_MAX_LYRICS"] = "1000"
    try:
        c = Config.from_env()
    finally:
        os.environ.clear()
        os.environ.update(old)
    assert c.port == 9001
    assert c.stub is True
    assert c.api_key == "k"
    assert c.keep_jobs == 7
    assert c.stub_fast is True
    assert c.device == "cpu"
    assert c.memory_budget_gib == 12.0
    assert c.max_lyrics == 1000
    assert c.data_dir == Path("/tmp/yue2-cfg-test")


def test_safe_summary_hides_secrets():
    c = Config(host="h", port=1, model="m", vae="v", api_key="secret", data_dir=Path("."),
               device="cuda", memory_budget_gib=24, keep_jobs=1, stub=True,
               max_lyrics=10, hf_token="hf-secret", stub_fast=True, jobs_limit_cap=10)
    s = c.safe_summary()
    assert s["api_key_set"] is True
    assert s["hf_token_set"] is True
    dumped = repr(s)
    assert "secret" not in dumped.replace("_set", "")  # 只出现布尔键名
    assert "hf-secret" not in dumped


def test_get_config_caches_and_resets(tmp_path, monkeypatch):
    monkeypatch.setenv("YUE2_DATA_DIR", str(tmp_path))
    reset_config()
    c1 = get_config()
    c2 = get_config()
    assert c1 is c2
    reset_config()
    c3 = get_config()
    assert c3 is not c1
