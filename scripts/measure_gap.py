#!/usr/bin/env python3
"""Measure the white-space gap at the bottom of page 1 in the compiled resume.

Usage:
    python3 scripts/measure_gap.py          # prints gap in mm to stdout
    python3 scripts/measure_gap.py --check  # verify typst query is available; exits 0 or 1
"""

import json
import os
import subprocess
import sys

# A4 default; overridden by <page-height-pt> query when available
PAGE_HEIGHT_MM = 297.0
# Override with env var GAP_BOTTOM_MARGIN_MM if lavandula margins differ
BOTTOM_MARGIN_MM = float(os.environ.get("GAP_BOTTOM_MARGIN_MM", "20"))
PT_TO_MM = 0.352778


def measure_gap(entry_ends: list[dict], page_height_elements: list[dict]) -> float:
    """Compute gap in mm between the last page-1 entry and the usable page bottom.

    Args:
        entry_ends: JSON objects from `typst query resume.typ "<exp-entry-end>"`.
                    Each has value: {"page": int, "y": float_pt}
        page_height_elements: JSON objects from `typst query resume.typ "<page-height-pt>"`.
                    Each has value: float_pt

    Returns:
        Gap in mm, clamped to >= 0.
    """
    page1 = [e for e in entry_ends if e["value"]["page"] == 1]
    if not page1:
        return 0.0

    max_y_pt = max(e["value"]["y"] for e in page1)

    if page_height_elements:
        page_h_mm = float(page_height_elements[0]["value"]) * PT_TO_MM
    else:
        page_h_mm = PAGE_HEIGHT_MM

    usable_bottom_mm = page_h_mm - BOTTOM_MARGIN_MM
    gap_mm = usable_bottom_mm - (max_y_pt * PT_TO_MM)
    return max(0.0, gap_mm)


def _run_query(label: str) -> list[dict]:
    result = subprocess.run(
        ["typst", "query", "resume.typ", label, "--input", "skip-assert=true"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def main() -> None:
    if "--check" in sys.argv:
        try:
            subprocess.run(["typst", "query", "--help"], capture_output=True, check=True)
            print("ok")
            sys.exit(0)
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("ERROR: typst query not available", file=sys.stderr)
            sys.exit(1)

    try:
        entry_ends = _run_query("<exp-entry-end>")
        page_height_els = _run_query("<page-height-pt>")
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"WARN: typst query failed: {exc}", file=sys.stderr)
        print("0.0")
        sys.exit(0)
    except json.JSONDecodeError as exc:
        print(f"WARN: failed to parse typst query output: {exc}", file=sys.stderr)
        print("0.0")
        sys.exit(0)

    print(f"{measure_gap(entry_ends, page_height_els):.1f}")


if __name__ == "__main__":
    main()
