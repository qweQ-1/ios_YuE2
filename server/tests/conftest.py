"""让 `cd server && pytest tests` 也能找到 server 包（仓库根 = 上两级）。"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
