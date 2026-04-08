# CLAUDE.md — Resume as Code

## Project Overview

RAC is a resume tailoring pipeline. `data/resume.yaml` is the single source of truth. The pipeline fetches a job posting, tailors the YAML via Claude CLI, audits for hallucinations, and renders a 2-page PDF with Typst + lavandula.

Entry point: `make resume URL=<url>`

## Critical Rules

1. **Never edit build/ files directly** — they are generated. Edit `data/resume.yaml` instead.
2. **Never fabricate** — do not add skills, tools, companies, or metrics to `data/resume.yaml` that are not true.
3. **YAML is ground truth** — `resume.md` is retained for reference but is not used in the pipeline.
4. **2-page limit is hard** — the Typst template asserts ≤ 2 pages at compile time.

## Key Design Decisions

- **YAML over Markdown**: Markdown is prose, not structured data. YAML is diffable and Typst-native.
- **YAML patch over full rewrite**: The LLM produces a minimal patch, not a full document. Fabrication is visible by construction.
- **Claude CLI over Python + API**: Zero extra dependencies, uses existing Claude Code auth.
- **No `--bare` flag**: `--bare` disables OAuth authentication. Omit it when using Claude Code's standard login.
- **Jina Reader**: Free, no API key, handles JS-rendered pages via `curl https://r.jina.ai/<url>`.
- **awk extraction**: LLM output is extracted with `awk '/^patches:/{p=1} p'` rather than sed — handles preamble text and closing fences reliably.
- **Binary fraud auditor**: A second Claude call returns PASS/FAIL with specific violations. Simpler than similarity scoring.

## Lavandula Template Notes

- Requires Typst ≥ 0.14.0 (skill-levels progress bars broken in 0.13.x).
- Font Awesome 7 Free Desktop fonts must be installed locally (download `.otf` files from fontawesome.com/download — install `Free-Regular`, `Free-Solid`, `Brands`). The `@preview/fontawesome:0.6.0` package requires FA7; FA6 will not work. Missing fonts render as `?` characters.
- Fira Sans font should be installed — compilation succeeds without it but text falls back to system fonts.
- Language fluency flags are local PNGs in `assets/flags/` (MIT-licensed, from gosquared/flags).
- Multi-role entries (Spotify two tenures, BNZ three roles) use a single `company` entry with multiple `roles` objects — saves ~2cm vertical space.
- The page count assert at the end of `resume.typ` causes `typst compile` to exit non-zero on overflow.

## Cache Behaviour

- Cache key: `sha256(URL + sha256(resume.yaml))` → stored in `build/.input_hash`.
- Cache is **content-addressed**, not timestamp-based. `touch resume.yaml` without changing content does NOT invalidate the cache.
- Any actual content change to either input triggers a full pipeline re-run.
- `make clean` wipes `build/` entirely.
- Individual steps can be re-run with `make fetch`, `make tailor`, `make audit`, `make render`.

## Prompt Files

- `prompts/tailor_system.txt` — constrains LLM to reorder/rephrase only; prohibits modifying summary, personal, education, awards sections; outputs YAML patches only.
- `prompts/audit_system.txt` — fraud auditor, returns PASS or FAIL + violations list.
- `prompts/trim_system.txt` — tells LLM which sections to cut first when over 2 pages.

## LLM Output Extraction

The LLM often adds preamble text and/or closing code fences despite instructions. The Makefile handles this:
- **Tailor**: `awk '/^patches:/{p=1} p'` — extracts from `patches:` onwards, stops at closing fence
- **Audit**: `awk '/^(PASS|FAIL)/{p=1} p'` — extracts verdict and violations only
- **Trim**: `awk` pattern matching on top-level YAML keys

## Trim Priority (when PDF > 2 pages)

1. `extra_qualifications` section — remove entirely
2. `interests` section — remove entirely
3. GetYourGuide bullets → title/company/dates only
4. Bank of New Zealand bullets → max 2
5. Zalando bullets → max 1
6. Older Qrious bullets → keep 2 strongest

## Known Issues / Gotchas

- Some job boards block Jina Reader (auth-gated). Fallback: save job text locally and use `URL=/path/to/file.txt`.
- The LLM occasionally modifies the `summary` field despite instructions; the fraud auditor catches this.
- `pdfinfo` requires poppler (`brew install poppler`). On Linux: `apt install poppler-utils`.
- YAML strings with colons or special characters must be quoted.
- The tailor prompt explicitly forbids modifying `summary`, `personal`, `education`, and `awards_and_publications` — these fields are off-limits.

## Self-Learning Loop

After each session where resume tailoring was run or the pipeline was changed, update this file:

1. **What worked?** — note any prompt tweaks that improved tailoring quality.
2. **What failed?** — note any audit failures, their root cause, and the fix.
3. **What was trimmed?** — note which sections were cut for which job types (IC vs leadership).
4. **Prompt improvements** — if you improved a system prompt, note what changed and why.
5. **Template changes** — if you adjusted Typst layout knobs (font size, margins), note the values and why.

Format: append a dated entry to the `## Session Log` section below.

## Session Log

### 2026-04-05 — Initial build
- Established YAML as ground truth, replacing resume.md.
- Chose YAML patch format over full rewrite for anti-hallucination.
- Chose binary fraud auditor over SequenceMatcher — simpler and more actionable.
- Consolidated Spotify's two tenures into one entry (saves ~2cm vertical space).
- BNZ and Qrious also consolidated (multiple roles, one entry each).
- lavandula v0.1.1 requires Typst ≥ 0.14.0 — pinned in CLAUDE.md.
- Flag PNGs sourced from gosquared/flags (MIT licensed).
- `--bare` flag removed: incompatible with OAuth authentication used by Claude Code.
- LLM output extraction hardened: `awk` instead of `sed` — handles both preamble text and closing fences.
- Tailor prompt tightened: added explicit prohibition on modifying `summary`, `personal`, `education`, `awards_and_publications` fields. Only `experience` bullets and `skills` ordering may be changed.
- Fraud auditor confirmed working: caught LLM attempt to change "ML specialist" to "Senior ML engineer" and fabricate MLOps achievement.
- Full pipeline verified: 10 patches applied, audit PASS, 2-page PDF produced.
