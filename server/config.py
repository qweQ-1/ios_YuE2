"""环境变量配置。所有密钥只从环境读取，绝不写默认值。"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

_TRUE = {"1", "true", "yes", "on"}


def _flag(name: str, default: bool = False) -> bool:
    return os.environ.get(name, str(default)).strip().lower() in _TRUE


def _int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


def _float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


@dataclass(frozen=True)
class Config:
    host: str
    port: int
    model: str
    vae: str
    api_key: str                # 空 = 不校验
    data_dir: Path
    device: str
    memory_budget_gib: float
    keep_jobs: int
    stub: bool
    max_lyrics: int
    hf_token: str | None
    stub_fast: bool
    jobs_limit_cap: int

    @classmethod
    def from_env(cls) -> "Config":
        return cls(
            host=os.environ.get("YUE2_HOST", "0.0.0.0"),
            port=_int("YUE2_PORT", 8420),
            model=os.environ.get("YUE2_MODEL", "m-a-p/YuE2-3B"),
            vae=os.environ.get("YUE2_VAE", "m-a-p/YuE2-Vae"),
            api_key=os.environ.get("YUE2_API_KEY", "").strip(),
            data_dir=Path(os.environ.get("YUE2_DATA_DIR", "./data")),
            device=os.environ.get("YUE2_DEVICE", "auto"),
            memory_budget_gib=_float("YUE2_MEMORY_BUDGET_GIB", 24),
            keep_jobs=_int("YUE2_KEEP_JOBS", 100),
            stub=_flag("YUE2_STUB", False),
            max_lyrics=_int("YUE2_MAX_LYRICS", 20000),
            hf_token=os.environ.get("YUE2_HF_TOKEN") or os.environ.get("HF_TOKEN") or None,
            stub_fast=_flag("YUE2_STUB_FAST", False),
            jobs_limit_cap=_int("YUE2_JOBS_LIMIT_CAP", 200),
        )

    def safe_summary(self) -> dict:
        """可安全打印/打日志的摘要（密钥只显示是否设置）。"""
        return {
            "host": self.host,
            "port": self.port,
            "model": self.model,
            "vae": self.vae,
            "api_key_set": bool(self.api_key),
            "data_dir": str(self.data_dir),
            "device": self.device,
            "memory_budget_gib": self.memory_budget_gib,
            "keep_jobs": self.keep_jobs,
            "stub": self.stub,
            "max_lyrics": self.max_lyrics,
            "hf_token_set": bool(self.hf_token),
            "stub_fast": self.stub_fast,
        }


_CONFIG: Config | None = None


def get_config() -> Config:
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = Config.from_env()
    return _CONFIG


def reset_config() -> None:
    """测试用：清除缓存。"""
    global _CONFIG
    _CONFIG = None
