"""Tests for gap measurement logic in measure_gap.py."""
import sys
import pytest

sys.path.insert(0, ".")
from scripts.measure_gap import measure_gap


PT_TO_MM = 0.352778
A4_H_PT = 841.89
# usable_bottom_mm = (841.89 * 0.352778) - 20 ≈ 276.9mm


def _entry(page: int, y_pt: float) -> dict:
    return {"value": {"page": page, "y": y_pt}}


def _page_height(pt: float) -> dict:
    return {"value": pt}


def test_gap_single_page1_entry():
    # 700pt * 0.352778 = 246.9mm; usable = 276.9mm; gap ≈ 30.0mm
    entries = [_entry(1, 700.0)]
    gap = measure_gap(entries, [_page_height(A4_H_PT)])
    assert gap == pytest.approx(30.0, abs=0.5)


def test_gap_uses_deepest_page1_entry():
    entries = [_entry(1, 500.0), _entry(1, 750.0)]
    gap = measure_gap(entries, [_page_height(A4_H_PT)])
    # 750pt * 0.352778 = 264.6mm; usable = 276.9mm; gap ≈ 12.3mm
    assert gap == pytest.approx(12.3, abs=0.5)


def test_page2_entries_ignored():
    entries = [_entry(1, 700.0), _entry(2, 200.0)]
    gap = measure_gap(entries, [_page_height(A4_H_PT)])
    assert gap == pytest.approx(30.0, abs=0.5)


def test_no_page1_entries_returns_zero():
    entries = [_entry(2, 300.0)]
    assert measure_gap(entries, [_page_height(A4_H_PT)]) == 0.0


def test_empty_entries_returns_zero():
    assert measure_gap([], []) == 0.0
    assert measure_gap([], [_page_height(A4_H_PT)]) == 0.0


def test_no_page_height_falls_back_to_297mm_default():
    # Without page-height elements, script uses PAGE_HEIGHT_MM = 297.0
    # usable = 297 - 20 = 277mm
    # 700pt * 0.352778 = 246.9mm; gap ≈ 30.1mm
    entries = [_entry(1, 700.0)]
    gap = measure_gap(entries, [])
    assert gap == pytest.approx(30.1, abs=0.5)


def test_gap_clamped_to_zero_when_content_overflows():
    entries = [_entry(1, 900.0)]
    assert measure_gap(entries, [_page_height(A4_H_PT)]) == 0.0
