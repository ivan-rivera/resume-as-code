# Layout Enforcement Design
**Date:** 2026-04-12
**Status:** Approved

## Problem

The resume pipeline produces a dynamically tailored PDF. After tailoring and trimming, experience entries can split across page boundaries (e.g. a company header on page 1, the last bullet on page 2). Additionally, when entries are bumped to the next page to avoid splits, the bottom of page 1 can accumulate significant white space.

**Constraints:**
- No experience entry may split across pages
- White space gap at the bottom of page 1 must be ≤ 20mm (tolerant threshold)
- Gaps > 20mm are filled by restoring previously trimmed content via an AI step
- Gaps that cannot be closed after 2 fill attempts are warned, not errored

## Approach

Approach B: `breakable: false` + gap measurement via `typst query` + AI fill-back loop.

## Components

### 1. Typst changes (`resume.typ`)

**1a. `breakable: false` on `logo-section-element`**

Add `breakable: false` to the outer `block(...)` call in `logo-section-element`. This is a Typst compile-time guarantee — no experience entry will ever be split across pages. When an entry does not fit in the remaining space on a page it shifts entirely to the next page.

**1b. End-of-entry position label**

At the end of each experience entry's body (inside the `for job in d.experience` loop), inject:

```typst
#metadata(job.company) <exp-entry-end>
```

This zero-size element sits at the baseline of the last bullet. `typst query resume.typ "<exp-entry-end>"` returns a JSON array of `{page, x, y}` positions used by the gap measurement script.

**1c. Page-bottom calibration marker**

Immediately before the hard 2-page assert at the bottom of `resume.typ`, inject:

```typst
#metadata("page-bottom") <page-bottom>
```

This marker's y-position on page 2 gives the actual usable bottom of the page. The gap script uses this instead of hardcoded A4/margin values, making it self-calibrating against lavandula margin changes.

No changes to the lavandula package. No changes to the YAML schema.

### 2. Gap measurement script (`scripts/measure_gap.py`)

Operates on the compiled `resume.typ` in the current directory. Outputs a single float (gap in mm) to stdout.

**Logic:**
1. Run `typst query resume.typ "<exp-entry-end>"` — returns JSON array of `{page, x, y}` positions. Typst positions are in points; convert to mm (1pt = 0.352778mm).
2. Run `typst query resume.typ "<page-bottom>"` — get the usable bottom y-position from page 2's calibration marker.
3. Filter `<exp-entry-end>` results to page 1 entries, find `max_y_mm`.
4. `gap_mm = page_usable_bottom_mm - max_y_mm`
5. If no page 1 entries exist, return 0 (nothing to measure).

**CLI:**
- Default: print gap in mm to stdout, exit 0
- `--check`: verify `typst query` is available, exit 0 or 1 (used by `check-deps`)

**No new dependencies** — `typst query` ships with Typst (already required).

### 3. Fill prompt (`prompts/fill_system.txt`)

Receives three inputs in the user message:
- `<ORIGINAL>` — `build/pre_trim.yaml`: the post-tailor, pre-trim YAML (the ceiling of what can be restored)
- `<TRIMMED>` — current `build/tailored.yaml`: what survived trimming
- `<GAP_MM>` — measured gap in millimetres

**Instructions to LLM:**
1. Diff ORIGINAL vs TRIMMED to identify removed content
2. Restore in reverse trim priority (strongest bullets first, whole sections last) until estimated restored content would close the gap (~4mm per bullet as line-height estimate)
3. Output complete YAML — same schema, all keys preserved

**Rules:**
- Do NOT add anything not present in ORIGINAL
- Do NOT change numbers, dates, metrics, or proper nouns
- Do NOT restore `extra_qualifications` or `interests` unless gap > 35mm
- Output only valid YAML, no commentary, no fences

**Extraction:** same `awk` pattern as trim — match on top-level YAML keys.

### 4. Makefile changes

**New variables:**
```makefile
GAP_THRESHOLD_MM := 20
MAX_FILL_RETRIES := 2
FILL_SYS         := prompts/fill_system.txt
PRE_TRIM_YAML    := $(BUILD_DIR)/pre_trim.yaml
```

**Updated `$(OUTPUT_PDF)` target flow:**
```
compile
├─ typst fails → error (unchanged)
├─ pages > 2 → trim loop (existing, max MAX_RETRIES=2)
│    └─ save pre_trim.yaml snapshot on FIRST trim entry only
│    └─ claude trim → extract YAML → recompile → recheck pages
│    └─ pages still > 2 after MAX_RETRIES → error (unchanged)
└─ pages ≤ 2 → gap loop (new)
     └─ python3 scripts/measure_gap.py → gap_mm
     └─ gap_mm ≤ GAP_THRESHOLD_MM → done ✓
     └─ gap_mm > GAP_THRESHOLD_MM AND pre_trim.yaml missing
          → WARN "gap Xmm but nothing was trimmed; structural spacing" → done ✓
     └─ gap_mm > GAP_THRESHOLD_MM AND pre_trim.yaml exists → fill loop
          └─ claude fill (pre_trim + trimmed + gap_mm) → extract YAML → recompile
          └─ remeasure gap
          └─ repeat up to MAX_FILL_RETRIES=2
          └─ gap still > threshold after retries → WARN + done ✓ (not an error)
```

**`check-deps` addition:**
```bash
python3 scripts/measure_gap.py --check
```

## Data Flow

```
data/resume.yaml ──► tailor ──► build/tailored.yaml
                                       │
                               (first trim entry)
                                       │
                               build/pre_trim.yaml (snapshot)
                                       │
                               trim loop (if pages > 2)
                                       │
                               typst compile
                                       │
                               measure_gap.py
                                       │
                         ┌─────────────┴─────────────┐
                    gap ≤ 20mm                   gap > 20mm
                         │                            │
                        done                    fill loop
                                                      │
                                             build/tailored.yaml (updated)
                                                      │
                                               recompile + remeasure
                                                      │
                                              done (or WARN after 2 retries)
```

## Error Handling

| Condition | Behaviour |
|---|---|
| `typst compile` fails | ERROR — exit 1 (unchanged) |
| Pages > 2 after MAX_RETRIES trims | ERROR — exit 1 (unchanged) |
| Gap > threshold, no pre_trim.yaml | WARN — structural gap, accepted |
| Gap > threshold after MAX_FILL_RETRIES | WARN — gap Xmm, accepted |
| `measure_gap.py` fails (query error) | WARN — skip gap check, proceed |
| Fill causes pages > 2 | WARN — revert to pre-fill YAML, accept gap |

Fill failures are non-fatal because the resume is already valid (≤ 2 pages, no broken sections). A gap warning tells the user they may want to manually review spacing.

## Files Changed

| File | Change |
|---|---|
| `resume.typ` | Add `breakable: false`, `<exp-entry-end>` labels, `<page-bottom>` marker |
| `scripts/measure_gap.py` | New file |
| `prompts/fill_system.txt` | New file |
| `Makefile` | New variables, pre_trim snapshot, gap loop in `$(OUTPUT_PDF)` |

## Out of Scope

- Sidebar gap management (skills section rarely trimmed; sidebar gap is a lavandula layout concern)
- Cover letter layout (separate pipeline)
- Non-experience sections breaking across pages (Education and Awards are short; not observed to break)
