"""uvicorn 入口：
    python -m uvicorn server.app:create_app --factory --host 0.0.0.0 --port 8420
或直接：
    python -m server.main
"""
from __future__ import annotations

import logging

import uvicorn

from .config import get_config


def main() -> None:
    config = get_config()
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    uvicorn.run("server.app:create_app", factory=True,
                host=config.host, port=config.port, log_level="info")


if __name__ == "__main__":
    main()
