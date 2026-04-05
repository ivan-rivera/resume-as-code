# Resume as Code (RAC)

A pipeline that takes a job posting URL and produces a tailored, 2-page PDF resume — without fabricating anything.

## How it works

```
data/resume.yaml  +  job posting URL
        │
        ▼
Claude CLI: tailor (YAML patch)
        │
        ▼
Claude CLI: fraud audit (PASS/FAIL)
        │
        ▼
Typst + lavandula: render PDF (≤ 2 pages)
```

The LLM reorders and rephrases — it never adds experience or skills that aren't already there. A second LLM call acts as a fraud auditor and blocks the PDF if it finds fabricated content.

## Prerequisites

| Tool | Install |
|---|---|
| Typst ≥ 0.14.0 | `brew install typst` |
| Claude Code CLI | [code.claude.ai](https://code.claude.ai) |
| poppler (pdfinfo) | `brew install poppler` |
| Python 3 + pyyaml | `pip install pyyaml` |
| curl | pre-installed on macOS |

## Usage

```bash
# Tailor resume for a job posting URL
make resume URL=https://company.com/jobs/123

# Use a local job description file (useful when the page is auth-gated)
make resume URL=/path/to/job.txt

# Individual steps
make fetch  URL=<url>   # extract job posting → build/job_posting.md
make tailor URL=<url>   # fetch + LLM tailor  → build/tailored.yaml
make audit              # fraud check          → build/audit_report.txt
make render             # compile PDF          → build/resume.pdf

# Cache management
make clean              # wipe build/ entirely

# Tests
make test
```

## Updating your resume

Edit `data/resume.yaml` — it is the single source of truth. The pipeline auto-detects changes and invalidates the cache. `resume.md` is retained for reference only.

## File structure

```
rac/
├── data/resume.yaml        # Your resume (edit this)
├── resume.typ              # Typst template (lavandula v0.1.1)
├── prompts/                # LLM system prompts
├── assets/flags/           # Language fluency icons
├── Makefile                # Pipeline
├── scripts/apply_patch.py  # YAML patch applicator
├── tests/                  # Unit tests
└── build/                  # Generated files (gitignored)
    ├── job_posting.md      # Extracted job text
    ├── llm_patch.yaml      # Raw LLM output
    ├── tailored.yaml       # Patched resume
    ├── audit_report.txt    # Fraud audit result
    └── resume.pdf          # Final output
```

## Caching

Intermediate results are cached in `build/`. The cache key is a SHA-256 hash of the URL + `data/resume.yaml` content. If either changes, the full pipeline re-runs. Run `make clean` to force a fresh start.

## Anti-hallucination

Two layers:
1. **Structural** — the LLM outputs a YAML patch, not a full rewrite. Every change is explicit and traceable.
2. **Fraud auditor** — a second LLM call compares the tailored YAML against the original and returns PASS or FAIL with specific violations. The pipeline halts on FAIL.

## Troubleshooting

**Empty job posting:** Some pages require login. Save the job text to a `.txt` file and use `URL=/path/to/file.txt`.

**Audit FAIL:** Check `build/audit_report.txt` for the specific violation. Run `make clean` then `make resume` to retry — the LLM output varies between runs.

**PDF > 2 pages:** The pipeline auto-trims up to 2 times. If it still fails, follow the suggested manual cuts printed in the error message, edit `data/resume.yaml`, and re-run.

**Font Awesome icons missing (blank boxes):** Install Font Awesome 6 Desktop OTF fonts from [fontawesome.com/download](https://fontawesome.com/download). Compilation still succeeds without them — icons just appear blank.

**Fira Sans font warning:** Install Fira Sans from [Google Fonts](https://fonts.google.com/specimen/Fira+Sans) for proper rendering. Also compiles without it.
