"""Range 解析测试。"""
from server.ranges import parse_range


def test_bytes_from_start():
    assert parse_range("bytes=0-", 100) == (0, 99)


def test_bytes_range():
    assert parse_range("bytes=10-20", 100) == (10, 20)


def test_suffix_range():
    assert parse_range("bytes=-50", 100) == (50, 99)
    assert parse_range("bytes=-500", 100) == (0, 99)


def test_range_beyond_total_is_clamped():
    assert parse_range("bytes=50-999", 100) == (50, 99)


def test_start_beyond_total_rejected():
    assert parse_range("bytes=100-", 100) is None
    assert parse_range("bytes=101-200", 100) is None


def test_invalid_rejected():
    assert parse_range(None, 100) is None
    assert parse_range("", 100) is None
    assert parse_range("bytes=-", 100) is None
    assert parse_range("bytes=abc", 100) is None
    assert parse_range("bytes=20-10", 100) is None
    assert parse_range("items=0-1", 100) is None
    assert parse_range("bytes=0-1,5-6", 100) is None


def test_empty_file():
    assert parse_range("bytes=0-", 0) is None
