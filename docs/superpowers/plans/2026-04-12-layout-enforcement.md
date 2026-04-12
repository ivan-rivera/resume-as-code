# Layout Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent experience entries from splitting across pages and fill back trimmed content when page 1 has > 20mm of white space.

**Architecture:** Three additions to the existing pipeline — (1) a Typst `breakable: false` flag plus position labels guarantee no section splits at compile time, (2) a Python script uses `typst query` to measure the gap at the bottom of page 1, (3) a new Makefile fill loop calls Claude to restore trimmed content when the gap exceeds 20mm.

**Tech Stack:** Typst 0.14, Python 3, GNU Make, Claude CLI (`claude -p`), pyyaml, pytest

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `resume.typ` | Modify | Add `breakable: false`, `<exp-entry-end>` labels, `<page-height-pt>` marker |
| `scripts/measure_gap.py` | Create | Query `typst query` output and compute page 1 gap in mm |
| `tests/test_measure_gap.py` | Create | Unit tests for gap computation logic |
| `prompts/fill_system.txt` | Create | Fill-back system prompt for Claude |
| `Makefile` | Modify | New variables, pre-trim snapshot, gap check loop, fill loop |

---

## Task 1: Typst — prevent section splits

**Files:**
- Modify: `resume.typ:31-55` (`logo-section-element` function)

- [ ] **Step 1: Add `breakable: false` to the outer block**

Open `resume.typ`. The `logo-section-element` function has a `block(...)` call starting at line 39. Add `breakable: false` as the first argument:

```typst
#let logo-section-element(title: "", info: "", logo: none, body) = {
  let logo-h = 2.1em   // scales with font size; tweak if needed
  let title-content = {
    if logo != none {
      box(height: logo-h, baseline: 25%, image(logo, height: 100%))
      h(5pt)
    }
    text(weight: "semibold", title)
  }
  block(
    breakable: false,
    inset: (top: 3pt),
    width: 100%,
    below: 1.7em,
    {
      grid(
        columns: (1fr, auto),
        align: (left + horizon, right + horizon),
        title-content,
        text(size: 7pt, info),
      )
      v(4pt)
      set par(justify: true, spacing: 1em)
      body
    },
  )
}
```

- [ ] **Step 2: Verify the template still compiles**

```bash
make compile-test
```

Expected: `compile-test passed: build/resume.pdf` with no errors.

- [ ] **Step 3: Add `<exp-entry-end>` label inside the experience loop**

In `resume.typ`, find the `for job in d.experience` loop (starts around line 108). Add a metadata label as the very last item inside the body closure passed to `logo-section-element`. The label must be AFTER `bullet-list(job.bullets)`:

```typst
logo-section-element(
  title: title-text,
  info:  [_#info-text _],
  logo:  logo-path,
  {
    if multi {
      for r in job.roles {
        text(weight: "semibold")[#r.title]
        text(style: "italic")[ · #r.start – #r.end]
        linebreak()
      }
      v(0.25em)
    }
    if job.company_description != "" {
      text(style: "italic", size: 8pt)[#job.company_description]
      v(0.2em)
    }
    bullet-list(job.bullets)
    [#metadata(job.company) <exp-entry-end>]
  },
)
```

- [ ] **Step 4: Add `<page-height-pt>` marker before the assert block**

At the bottom of `resume.typ`, before the existing `#context { ... assert ... }` block, insert:

```typst
// ── Page height capture for gap measurement ───────────────────────────────
#context {
  [#metadata(page.height.pt()) <page-height-pt>]
}

// ── Hard 2-page guard ─────────────────────────────────────────────────────
#context {
  let total = counter(page).final().at(0)
  assert(
    total <= 2,
    message: "Resume is " + str(total) + " pages — must be ≤ 2. Run `make resume` to auto-trim.",
  )
}
```

- [ ] **Step 5: Verify labels compile and are queryable**

```bash
make compile-test
typst query resume.typ "<exp-entry-end>"
typst query resume.typ "<page-height-pt>"
```

Expected from first query: a JSON array with one object per company entry, each with a `"location"` field containing `"page"` and `"y"` keys.
Expected from second query: a JSON array with one object whose `"value"` is a float (e.g. `841.89` for A4).

If `typst query` returns an error or empty array, check Typst version (`typst --version` must be ≥ 0.14.0) and verify the label syntax matches exactly (`<exp-entry-end>` with angle brackets).

- [ ] **Step 6: Commit**

```bash
git add resume.typ
git commit -m "feat(layout): add breakable:false and position labels to experience blocks"
```

---

## Task 2: Gap measurement script (TDD)

**Files:**
- Create: `scripts/measure_gap.py`
- Create: `tests/test_measure_gap.py`

- [ ] **Step 1: Write the failing tests**

Create `tests/test_measure_gap.py`:

```python
"""Tests for gap measurement logic in measure_gap.py."""
import sys
import pytest

sys.path.insert(0, ".")
from scripts.measure_gap import measure_gap


PT_TO_MM = 0.352778
A4_H_PT = 841.89
# usable_bottom_mm = (841.89 * 0.352778) - 20 ≈ 276.9mm


def _entry(page: int, y_pt: float) -> dict:
    return {"location": {"page": page, "x": "10pt", "y": f"{y_pt}pt"}}


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
    # Entry y beyond usable bottom — shouldn't happen in practice, but guard it
    entries = [_entry(1, 900.0)]
    assert measure_gap(entries, [_page_height(A4_H_PT)]) == 0.0
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
python3 -m pytest tests/test_measure_gap.py -v
```

Expected: `ModuleNotFoundError: No module named 'scripts.measure_gap'` or similar — confirms tests are wired up and the module doesn't exist yet.

- [ ] **Step 3: Implement `scripts/measure_gap.py`**

Create `scripts/measure_gap.py`:

```python
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


def _parse_y_pt(location: dict) -> float:
    return float(location["y"].replace("pt", "").strip())


def measure_gap(entry_ends: list[dict], page_height_elements: list[dict]) -> float:
    """Compute gap in mm between the last page-1 entry and the usable page bottom.

    Args:
        entry_ends: JSON objects from `typst query resume.typ "<exp-entry-end>"`.
        page_height_elements: JSON objects from `typst query resume.typ "<page-height-pt>"`.

    Returns:
        Gap in mm, clamped to >= 0.
    """
    page1 = [e for e in entry_ends if e["location"]["page"] == 1]
    if not page1:
        return 0.0

    max_y_pt = max(_parse_y_pt(e["location"]) for e in page1)

    if page_height_elements:
        page_h_mm = float(page_height_elements[0]["value"]) * PT_TO_MM
    else:
        page_h_mm = PAGE_HEIGHT_MM

    usable_bottom_mm = page_h_mm - BOTTOM_MARGIN_MM
    gap_mm = usable_bottom_mm - (max_y_pt * PT_TO_MM)
    return max(0.0, gap_mm)


def _run_query(label: str) -> list[dict]:
    result = subprocess.run(
        ["typst", "query", "resume.typ", label],
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
    except subprocess.CalledProcessError as exc:
        print(f"WARN: typst query failed: {exc.stderr.strip()}", file=sys.stderr)
        print("0.0")
        sys.exit(0)
    except json.JSONDecodeError as exc:
        print(f"WARN: failed to parse typst query output: {exc}", file=sys.stderr)
        print("0.0")
        sys.exit(0)

    print(f"{measure_gap(entry_ends, page_height_els):.1f}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
python3 -m pytest tests/test_measure_gap.py -v
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Verify the script works against the compiled resume**

```bash
make compile-test
python3 scripts/measure_gap.py
```

Expected: a float printed to stdout (e.g. `23.4`). Any value is acceptable here — we're just confirming the query runs and produces a number. If `typst query` returns an unexpected format (e.g. `"y"` is `"12.3mm"` instead of `"12.3pt"`), update `_parse_y_pt` to strip `"mm"` and skip the `PT_TO_MM` conversion.

- [ ] **Step 6: Verify `--check` flag**

```bash
python3 scripts/measure_gap.py --check
echo "exit code: $?"
```

Expected: prints `ok` and exits 0.

- [ ] **Step 7: Commit**

```bash
git add scripts/measure_gap.py tests/test_measure_gap.py
git commit -m "feat(layout): add gap measurement script with tests"
```

---

## Task 3: Fill system prompt

**Files:**
- Create: `prompts/fill_system.txt`

- [ ] **Step 1: Create the fill prompt**

Create `prompts/fill_system.txt`:

```
You are a resume editor. The resume has been trimmed to fit 2 pages but now has
too much white space at the bottom of page 1. Your task: restore removed content
to reduce that gap.

INPUTS you will receive:
  <ORIGINAL>  — the post-tailor, pre-trim YAML (the ceiling of what may be restored)
  <TRIMMED>   — the current trimmed YAML
  <GAP_MM>    — white space gap in millimetres (1 typical bullet ≈ 4mm)

RULES:
1. Output the complete restored YAML — same schema as the input, all keys preserved.
2. Do NOT add any content not present in <ORIGINAL>.
3. Do NOT change any numbers, metrics, dates, or proper nouns.
4. Restore in reverse trim priority (most impactful content first):
   a. Qrious bullets — restore up to 2 bullets not in TRIMMED
   b. Zalando bullets — restore up to 2 total
   c. Bank of New Zealand bullets — restore up to 4 total
   d. GetYourGuide bullets — restore up to 2 total
   e. interests section — restore only if GAP_MM > 35
   f. extra_qualifications section — restore only if GAP_MM > 35
5. Estimate ~4mm per bullet line. Restore just enough bullets to close GAP_MM.
   Do not overfill — stop restoring once the estimated addition equals GAP_MM.
6. Do NOT restore or modify the summary, personal, education, or
   awards_and_publications fields.

Output only valid YAML — no commentary, no markdown fences.
```

- [ ] **Step 2: Verify the prompt file is plain text with no trailing whitespace issues**

```bash
cat prompts/fill_system.txt | wc -l
```

Expected: 28 (approximately). If the file is empty or shows 0, re-check the write.

- [ ] **Step 3: Commit**

```bash
git add prompts/fill_system.txt
git commit -m "feat(layout): add fill-back system prompt"
```

---

## Task 4: Makefile — variables and pre-trim snapshot

**Files:**
- Modify: `Makefile`

This task adds the new variable declarations and modifies the trim loop to save a pre-trim snapshot. The gap loop (Task 5) builds on top of this.

- [ ] **Step 1: Add new variables after the existing variable block**

In `Makefile`, after the `TAILOR_SYS / AUDIT_SYS / CORRECT_SYS / TRIM_SYS` lines (around line 33), add:

```makefile
FILL_SYS      := prompts/fill_system.txt
PRE_TRIM_YAML := $(BUILD_DIR)/pre_trim.yaml
GAP_THRESHOLD_MM := 20
MAX_FILL_RETRIES := 2
```

- [ ] **Step 2: Update `check-deps` to verify `measure_gap.py --check`**

In the `check-deps` target, add after the `python3 -c "import yaml"` check:

```makefile
	@python3 scripts/measure_gap.py --check 2>/dev/null || \
		echo "WARN: typst query unavailable — gap check will be skipped"
```

Note: this is a warning, not a hard error — the pipeline still works if `typst query` fails (it returns 0.0 gap).

- [ ] **Step 3: Add pre-trim snapshot to the trim loop in `$(OUTPUT_PDF)`**

Locate the trim loop inside `$(OUTPUT_PDF)`. It currently starts with:

```bash
retries=0; \
current_yaml=$(TAILORED_YAML); \
```

Change to:

```bash
retries=0; \
fill_retries=0; \
pre_trim_saved=0; \
just_filled=0; \
current_yaml=$(TAILORED_YAML); \
```

Then find the line inside the trim block that currently reads:
```bash
echo "      Over limit ($$pages pages) -- trimming (attempt $$retries/$(MAX_RETRIES))..."; \
```

Add the snapshot save BEFORE that echo, so it looks like:

```bash
if [ $$pre_trim_saved -eq 0 ]; then \
    cp $$current_yaml $(PRE_TRIM_YAML); \
    pre_trim_saved=1; \
fi; \
echo "      Over limit ($$pages pages) -- trimming (attempt $$retries/$(MAX_RETRIES))..."; \
```

- [ ] **Step 4: Verify the Makefile is syntactically valid**

```bash
make --dry-run compile-test 2>&1 | head -5
```

Expected: no `Makefile:N: *** missing separator` errors.

- [ ] **Step 5: Run a compile-test to confirm pre_trim.yaml is NOT created when no trimming occurs**

```bash
make compile-test
ls build/pre_trim.yaml 2>/dev/null && echo "EXISTS" || echo "NOT PRESENT"
```

Expected: `NOT PRESENT` — `pre_trim.yaml` must only be created when trimming is actually triggered.

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit -m "feat(layout): add gap loop variables and pre-trim snapshot to Makefile"
```

---

## Task 5: Makefile — gap check and fill loop

**Files:**
- Modify: `Makefile`

This task adds the gap loop that runs after the trim loop achieves ≤ 2 pages. The complete `$(OUTPUT_PDF)` target after this task is shown in full below — replace the target entirely rather than patching it line-by-line.

- [ ] **Step 1: Replace the `$(OUTPUT_PDF)` target with the full updated version**

Replace everything from `$(OUTPUT_PDF): $(AUDIT_REPORT) | $(BUILD_DIR)` through the closing `done` line with:

```makefile
$(OUTPUT_PDF): $(AUDIT_REPORT) | $(BUILD_DIR)
	@echo "[4/4] Compiling PDF..."
	@retries=0; \
	fill_retries=0; \
	pre_trim_saved=0; \
	just_filled=0; \
	current_yaml=$(TAILORED_YAML); \
	while true; do \
		if typst compile $(TYPST_TPL) $@ 2>/dev/null; then \
			pages=$$(pdfinfo $@ 2>/dev/null | awk '/^Pages:/{print $$2}' || echo "0"); \
			if [ "$$pages" -gt 2 ]; then \
				if [ "$$just_filled" -eq 1 ]; then \
					echo "      WARN: fill caused overflow — reverting to pre-fill YAML"; \
					cp $(BUILD_DIR)/pre_fill.yaml $$current_yaml; \
					just_filled=0; \
					cat $(BUILD_DIR)/.current_hash > $(HASH_FILE); \
					break; \
				fi; \
				retries=$$((retries + 1)); \
				if [ $$retries -gt $(MAX_RETRIES) ]; then \
					echo ""; \
					echo "ERROR: Resume is $$pages pages after $(MAX_RETRIES) trim attempts."; \
					echo "Suggested manual cuts (in order):"; \
					echo "  1. extra_qualifications section"; \
					echo "  2. interests section"; \
					echo "  3. GetYourGuide bullets -> title only"; \
					echo "  4. Bank of New Zealand bullets -> 2 max"; \
					echo "  5. Zalando bullets -> 1 max"; \
					exit 1; \
				fi; \
				if [ $$pre_trim_saved -eq 0 ]; then \
					cp $$current_yaml $(PRE_TRIM_YAML); \
					pre_trim_saved=1; \
				fi; \
				echo "      Over limit ($$pages pages) -- trimming (attempt $$retries/$(MAX_RETRIES))..."; \
				{ \
					echo '<TAILORED_YAML>'; \
					cat $$current_yaml; \
					echo '</TAILORED_YAML>'; \
					echo ''; \
					echo "The resume compiles to $$pages pages. Trim to fit 2 pages."; \
				} > $(BUILD_DIR)/trim_prompt.txt; \
				claude -p "$$(cat $(BUILD_DIR)/trim_prompt.txt)" \
					--system-prompt-file $(TRIM_SYS) \
					--max-turns 1 \
					--no-session-persistence \
					--output-format text \
					--model $(MODEL) \
					| awk '/^(personal:|summary:|languages:|skills:|experience:|education:|awards_and_publications:|extra_qualifications:|interests:)/{p=1} p' \
					> $${current_yaml}.tmp \
				&& mv $${current_yaml}.tmp $$current_yaml; \
				continue; \
			fi; \
			just_filled=0; \
			echo "      Compiled: $$pages page(s)"; \
			gap=$$(python3 scripts/measure_gap.py 2>/dev/null || echo "0.0"); \
			gap_ok=$$(echo "$$gap $(GAP_THRESHOLD_MM)" | awk '{print ($$1 <= $$2) ? "1" : "0"}'); \
			if [ "$$gap_ok" = "1" ]; then \
				echo "      Gap: $${gap}mm (OK)"; \
				cat $(BUILD_DIR)/.current_hash > $(HASH_FILE); \
				break; \
			fi; \
			if [ ! -f "$(PRE_TRIM_YAML)" ]; then \
				echo "      WARN: gap $${gap}mm but nothing was trimmed (structural spacing — accepted)"; \
				cat $(BUILD_DIR)/.current_hash > $(HASH_FILE); \
				break; \
			fi; \
			fill_retries=$$((fill_retries + 1)); \
			if [ "$$fill_retries" -gt "$(MAX_FILL_RETRIES)" ]; then \
				echo "      WARN: gap $${gap}mm after $(MAX_FILL_RETRIES) fill attempts (accepted)"; \
				cat $(BUILD_DIR)/.current_hash > $(HASH_FILE); \
				break; \
			fi; \
			echo "      Gap $${gap}mm > $(GAP_THRESHOLD_MM)mm -- filling (attempt $$fill_retries/$(MAX_FILL_RETRIES))..."; \
			cp $$current_yaml $(BUILD_DIR)/pre_fill.yaml; \
			{ \
				echo '<ORIGINAL>'; \
				cat $(PRE_TRIM_YAML); \
				echo '</ORIGINAL>'; \
				echo ''; \
				echo '<TRIMMED>'; \
				cat $$current_yaml; \
				echo '</TRIMMED>'; \
				echo ''; \
				echo "<GAP_MM>$$gap</GAP_MM>"; \
			} > $(BUILD_DIR)/fill_prompt.txt; \
			claude -p "$$(cat $(BUILD_DIR)/fill_prompt.txt)" \
				--system-prompt-file $(FILL_SYS) \
				--max-turns 1 \
				--no-session-persistence \
				--output-format text \
				--model $(MODEL) \
				| awk '/^(personal:|summary:|languages:|skills:|experience:|education:|awards_and_publications:|extra_qualifications:|interests:)/{p=1} p' \
				> $${current_yaml}.tmp \
			&& mv $${current_yaml}.tmp $$current_yaml || { \
				echo "      WARN: fill LLM call failed — accepted"; \
				cat $(BUILD_DIR)/.current_hash > $(HASH_FILE); \
				break; \
			}; \
			just_filled=1; \
		else \
			echo "ERROR: typst compile failed. Check $(TYPST_TPL) syntax."; \
			exit 1; \
		fi; \
	done
```

- [ ] **Step 2: Verify Makefile syntax**

```bash
make --dry-run compile-test 2>&1 | head -5
```

Expected: no `missing separator` errors.

- [ ] **Step 3: Run `compile-test` and verify gap is reported**

```bash
make compile-test
```

Expected output includes a line like:
```
[4/4] Compiling PDF...
      Compiled: 2 page(s)
      Gap: XX.Xmm (OK)
```

(The gap value will vary. Any number ≤ 20 shows `OK`. A number > 20 with no `pre_trim.yaml` shows the structural spacing warning.)

- [ ] **Step 4: Verify no regression — full test suite passes**

```bash
python3 -m pytest tests/ -v
```

Expected: all tests PASS (existing `test_apply_patch.py` + new `test_measure_gap.py`).

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "feat(layout): add gap check and fill-back loop to compile step"
```

---

## Task 6: End-to-end verification

No new files. Validate the complete pipeline behaviour against the spec.

- [ ] **Step 1: Verify section breaks are gone**

```bash
make compile-test
python3 scripts/measure_gap.py
typst query resume.typ "<exp-entry-end>" | python3 -c "
import json, sys
entries = json.load(sys.stdin)
for e in entries:
    print(e['value'], '→ page', e['location']['page'])
"
```

Expected: all companies print with a page number. No company should have its header on page 1 and its last bullet on page 2 (since `breakable: false` prevents this — verifiable by comparing against the original PDF visual).

- [ ] **Step 2: Open the compiled PDF and confirm no broken sections**

```bash
open build/resume.pdf
```

Visually confirm: every company entry is fully contained on one page. The Qrious section (previously split) should now be entirely on one page.

- [ ] **Step 3: Verify gap reporting**

```bash
python3 scripts/measure_gap.py
```

Expected: prints a float. Note the value. If > 20mm and no trimming occurred during `compile-test`, the structural spacing warning was correctly emitted during the make step.

- [ ] **Step 4: Run unit tests one final time**

```bash
python3 -m pytest tests/ -v
```

Expected: all PASS.

- [ ] **Step 5: Final commit**

```bash
git add -A
git status  # confirm only expected files changed
git commit -m "feat(layout): complete layout enforcement — breakable blocks, gap check, fill loop"
```

---

## Self-Review Notes

**Spec coverage check:**
- ✅ Section 1 (Typst `breakable: false`) → Task 1
- ✅ Section 1 (`<exp-entry-end>` labels) → Task 1
- ✅ Section 1 (`<page-height-pt>` marker) → Task 1 (spec called this `<page-bottom>`; redesigned to capture actual page dimensions — more reliable)
- ✅ Section 2 (`measure_gap.py` logic) → Task 2
- ✅ Section 2 (`--check` flag) → Task 2
- ✅ Section 3 (fill prompt) → Task 3
- ✅ Section 4 (new Makefile variables) → Task 4
- ✅ Section 4 (`pre_trim_saved` snapshot) → Task 4
- ✅ Section 4 (gap loop) → Task 5
- ✅ Section 4 (fill loop) → Task 5
- ✅ Error table: fill causes overflow → `just_filled` flag + revert in Task 5
- ✅ Error table: gap > threshold, no pre_trim.yaml → structural warning in Task 5
- ✅ Error table: gap > threshold after MAX_FILL_RETRIES → warn + accept in Task 5
- ✅ Error table: `measure_gap.py` fails → falls back to 0.0, pipeline continues in Task 2

**Note on spec deviation:** The spec described a `<page-bottom>` content marker; the plan uses `<page-height-pt>` metadata from `context page.height.pt()` instead. This is more reliable because it captures the true page height regardless of content length, and avoids the "floating marker" problem where content-based markers move with the content.
