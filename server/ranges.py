"""HTTP Range 解析（单段）。"""
from __future__ import annotations

import re

_RANGE_RE = re.compile(r"^bytes=(\d*)-(\d*)$")


def parse_range(header: str | None, total: int) -> tuple[int, int] | None:
    """解析单段 Range。

    - "bytes=0-"      → (0, total-1)
    - "bytes=-500"    → (total-500, total-1)（不足 500 则从 0 开始）
    - "bytes=100-200" → (100, 200)（超出 total 则截断）
    - 多段/非法/空    → None
    """
    if not header:
        return None
    m = _RANGE_RE.match(header.strip())
    if not m:
        return None
    start_s, end_s = m.group(1), m.group(2)
    if not start_s and not end_s:
        return None
    if not start_s:  # 后缀形式 bytes=-N
        n = int(end_s)
        if n <= 0:
            return None
        return (max(total - n, 0), total - 1)
    start = int(start_s)
    if start >= total:
        return None
    if not end_s:
        return (start, total - 1)
    end = int(end_s)
    if end >= total:
        end = total - 1
    if end < start:
        return None
    return (start, end)
