# Form Autofill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make apply URL=<form-url>` that opens Arc with remote debugging, then uses Claude via Playwright MCP over CDP to fill a job application form from `data/resume.yaml` without submitting.

**Architecture:** `autofill.sh` launches Arc independently with `--remote-debugging-port=9222`, then calls `claude -p` with `--mcp-config config/playwright-mcp.json`. The MCP config points Playwright at the live Arc window via CDP — Arc was launched independently so it survives after `claude -p` exits. Claude uses the autofill system prompt to inspect and fill fields semantically from `resume.yaml`.

**Tech Stack:** bash, Arc browser (Chromium CDP), `@playwright/mcp` npm package (via npx), `claude -p` CLI, pytest (existing)

---

### Task 1: Write failing tests

**Files:**
- Create: `tests/test_autofill.py`

- [ ] **Step 1: Write the test file**

```python
"""Tests for autofill.sh and supporting files."""
import json
import socket
import subprocess
import pytest
from pathlib import Path


def bind_port(port: int) -> socket.socket:
    """Bind a dummy TCP listener. Caller must call .close()."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(1)
    return s


def test_port_guard_exits_when_9222_in_use():
    """autofill.sh must exit 1 with a clear error if port 9222 is already bound."""
    sock = bind_port(9222)
    try:
        result = subprocess.run(
            ['bash', 'scripts/autofill.sh', 'https://example.com', 'data/resume.yaml'],
            capture_output=True, text=True, timeout=10
        )
    finally:
        sock.close()
    assert result.returncode == 1
    assert '9222' in (result.stdout + result.stderr)


def test_autofill_system_prompt_exists():
    assert Path('prompts/autofill_system.txt').exists()


def test_autofill_system_prompt_forbids_submission():
    """System prompt must explicitly forbid Submit/Apply/Next/Continue."""
    text = Path('prompts/autofill_system.txt').read_text()
    for keyword in ('Submit', 'Apply', 'Next', 'Continue'):
        assert keyword in text, f"System prompt must mention '{keyword}' as forbidden"


def test_autofill_system_prompt_requires_summary():
    text = Path('prompts/autofill_system.txt').read_text()
    assert 'summary' in text.lower(), "System prompt must require a fill summary"


def test_playwright_mcp_config_valid():
    config_path = Path('config/playwright-mcp.json')
    assert config_path.exists(), "config/playwright-mcp.json must exist"
    data = json.loads(config_path.read_text())
    assert 'mcpServers' in data
    assert 'playwright-arc' in data['mcpServers'], \
        "Key must be 'playwright-arc' to avoid collision with global playwright plugin"
    args = data['mcpServers']['playwright-arc'].get('args', [])
    assert '--cdp-endpoint' in args
    assert 'http://localhost:9222' in args
```

- [ ] **Step 2: Run tests to confirm they all fail**

```bash
python3 -m pytest tests/test_autofill.py -v
```

Expected: 5 FAILED — files don't exist yet.

- [ ] **Step 3: Commit**

Use `commit-commands:commit` skill with message:
```
test(autofill): add failing tests for port guard, system prompt, MCP config
```

---

### Task 2: Create `config/playwright-mcp.json`

**Files:**
- Create: `config/playwright-mcp.json`

- [ ] **Step 1: Create the directory and write the file**

```json
{
  "mcpServers": {
    "playwright-arc": {
      "command": "npx",
      "args": ["@playwright/mcp", "--cdp-endpoint", "http://localhost:9222"]
    }
  }
}
```

Key is `playwright-arc` (not `playwright`) to avoid conflicting with the globally installed `playwright@claude-plugins-official` plugin.

- [ ] **Step 2: Run the config test**

```bash
python3 -m pytest tests/test_autofill.py::test_playwright_mcp_config_valid -v
```

Expected: PASS

- [ ] **Step 3: Commit**

```
feat(autofill): add Playwright MCP config for Arc CDP bridge
```

---

### Task 3: Write `prompts/autofill_system.txt`

**Files:**
- Create: `prompts/autofill_system.txt`

- [ ] **Step 1: Write the system prompt**

```
You are a browser automation agent. Your job is to fill a job application form on behalf of a candidate using their profile data.

## Behaviour

1. The candidate's Arc browser is already open at the form URL. Take a snapshot to inspect the current state.
2. Identify all visible form fields: text inputs, textareas, selects, checkboxes, radio buttons.
3. Map each field to the correct value from the candidate profile by reading label text semantically:
   - "First name" → personal.name (first word)
   - "Last name" → personal.name (last word)
   - "Email" → personal.email
   - "Phone" → personal.phone
   - "LinkedIn" → personal.linkedin_url
   - "GitHub" → personal.github_url
   - "Location" / "City" / "Country" → personal.location
   - "Current title" / "Job title" → most recent role title in experience
   - "Current company" / "Employer" → most recent company in experience
   - "Years of experience" → calculate from earliest to most recent experience date
4. Fill fields using Playwright tools (fill, select_option, check).
5. For dropdowns, pick the closest matching option by label or value text.
6. Leave fields empty if the candidate profile has no matching data — never invent values.

## Hard rules

- **NEVER** click Submit, Apply, Next, Continue, Save, or any button that advances or submits the form
- **NEVER** upload files — skip any file input field entirely
- Do NOT navigate away from the form page

## On completion

Print a plain-text summary:

Filled:
  - [Field label] → [Value used]

Skipped:
  - [Field label] → [Reason: file input / no matching data / field not found]
```

- [ ] **Step 2: Run the system prompt tests**

```bash
python3 -m pytest tests/test_autofill.py::test_autofill_system_prompt_exists \
  tests/test_autofill.py::test_autofill_system_prompt_forbids_submission \
  tests/test_autofill.py::test_autofill_system_prompt_requires_summary -v
```

Expected: all 3 PASS

- [ ] **Step 3: Commit**

```
feat(autofill): add autofill system prompt
```

---

### Task 4: Write `scripts/autofill.sh`

**Files:**
- Create: `scripts/autofill.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

URL="$1"
RESUME_YAML="$2"
MODEL="${MODEL:-claude-sonnet-4-6}"
DEBUG_PORT=9222
MCP_CONFIG="config/playwright-mcp.json"

# ── Guard: port 9222 must be free ────────────────────────────
if lsof -ti tcp:${DEBUG_PORT} >/dev/null 2>&1; then
  echo "ERROR: Port ${DEBUG_PORT} is already in use." >&2
  echo "  Stop the process holding it: kill \$(lsof -ti tcp:${DEBUG_PORT})" >&2
  exit 1
fi

# ── Launch Arc with remote debug port ────────────────────────
echo "[apply] Opening Arc at ${URL}..."
open -na "Arc" --args \
  "--remote-debugging-port=${DEBUG_PORT}" \
  "--new-window" \
  "${URL}"

# Wait for Arc to start and expose the debug port
sleep 3

# Verify Arc is now listening
if ! lsof -ti tcp:${DEBUG_PORT} >/dev/null 2>&1; then
  echo "ERROR: Arc did not open remote debugging on port ${DEBUG_PORT}." >&2
  echo "  Ensure Arc is installed at /Applications/Arc.app" >&2
  exit 1
fi

# ── Build prompt ──────────────────────────────────────────────
PROMPT=$(cat <<PROMPT_EOF
Fill the job application form at ${URL} using the candidate profile below.
The browser is already open — take a snapshot to inspect the form first.

Do NOT click Submit, Apply, Next, Continue, Save, or any button that advances or submits the form.
Fill text inputs, textareas, dropdowns, checkboxes, and radio buttons.
Skip file upload fields — list each by its label in your summary.
Leave fields empty if the candidate profile has no relevant data.

<CANDIDATE_PROFILE>
$(cat "${RESUME_YAML}")
</CANDIDATE_PROFILE>
PROMPT_EOF
)

# ── Invoke Claude with Playwright MCP over CDP ────────────────
echo "[apply] Filling form (this may take a minute)..."
claude -p "${PROMPT}" \
  --system-prompt-file "prompts/autofill_system.txt" \
  --mcp-config "${MCP_CONFIG}" \
  --max-turns 30 \
  --no-session-persistence \
  --output-format text \
  --model "${MODEL}"

echo ""
echo "[apply] Done. Review the form in Arc and submit manually."
```

- [ ] **Step 2: Run the port guard test**

```bash
python3 -m pytest tests/test_autofill.py::test_port_guard_exits_when_9222_in_use -v
```

Expected: PASS

- [ ] **Step 3: Run the full test suite**

```bash
python3 -m pytest tests/test_autofill.py -v
```

Expected: all 5 PASS

- [ ] **Step 4: Commit**

```
feat(autofill): add autofill.sh with Arc CDP launch and port guard
```

---

### Task 5: Add Makefile target

**Files:**
- Modify: `Makefile` (lines 73, 89-101, 286, 477-498)

- [ ] **Step 1: Add `apply` to `.PHONY` (line 73)**

Old:
```makefile
.PHONY: resume fetch tailor audit render clean test compile-test help report \
        check-deps _cache_check cover
```

New:
```makefile
.PHONY: resume fetch tailor audit render clean test compile-test help report \
        check-deps _cache_check cover apply
```

- [ ] **Step 2: Add `npx` to `check-deps` bin loop (line 90)**

Old:
```makefile
	@for bin in typst claude curl python3 pdfinfo; do \
```

New:
```makefile
	@for bin in typst claude curl python3 pdfinfo npx; do \
```

Also add the install hint inside the error block (after the `pdfinfo` line):

Old:
```makefile
			echo "  pdfinfo -> brew install poppler"; \
```

New:
```makefile
			echo "  pdfinfo -> brew install poppler"; \
			echo "  npx     -> brew install node"; \
```

- [ ] **Step 3: Add `apply` target after the `cover` target (after line 286)**

```makefile
# ── Apply: fill job application form in Arc ───────────────────
apply: guard-URL check-deps
	@bash scripts/autofill.sh "$(URL)" $(RESUME_YAML)
```

- [ ] **Step 4: Add `apply` to `make help` output**

In the help target, after the `make report` line, add:

```makefile
	@echo "  make apply URL=<url>               Fill job application form in Arc (no submit)"
```

- [ ] **Step 5: Verify guard fires correctly**

```bash
make apply 2>&1 | head -3
```

Expected: `ERROR: URL is required. Example: make resume URL=https://...`

- [ ] **Step 6: Verify help shows the new target**

```bash
make help | grep apply
```

Expected: `  make apply URL=<url>               Fill job application form in Arc (no submit)`

- [ ] **Step 7: Commit**

```
feat(autofill): add make apply target with check-deps and help entry
```

---

### Task 6: Verify MCP connectivity (manual diagnostic)

No files changed. Confirm the MCP server loads before smoke testing.

- [ ] **Step 1: Confirm `@playwright/mcp` is available via npx**

```bash
npx --yes @playwright/mcp --version 2>&1 | head -3
```

Expected: version string (e.g. `1.x.x`). First run may take ~30s to download.

- [ ] **Step 2: Test that `claude -p` loads Playwright MCP tools**

Open any URL in Arc first so port 9222 is bound (or run `open -na "Arc" --args --remote-debugging-port=9222`), then:

```bash
claude -p "List all Playwright MCP tools you have available. One tool name per line only." \
  --mcp-config config/playwright-mcp.json \
  --max-turns 1 \
  --no-session-persistence \
  --output-format text \
  --model claude-sonnet-4-6
```

Expected: a list of tool names including `browser_navigate`, `browser_snapshot`, `browser_fill_form` or similar.

If Claude responds with "I have no Playwright tools" or similar: verify `npx @playwright/mcp` resolves and that port 9222 is open. If the CDP connection is refused, that's acceptable — Claude should still list the available tools before attempting to use them.

---

### Task 7: Smoke test against a live form

No files changed. Manual end-to-end verification.

- [ ] **Step 1: Run against a real Lever or Greenhouse form**

```bash
make apply URL=https://jobs.lever.co/anthropic/<role-id>
```

Or substitute any live ATS form URL.

- [ ] **Step 2: Observe Arc and terminal**

Verify all of the following:
1. Arc opens a new window with the form URL loaded
2. Terminal shows `[apply] Filling form (this may take a minute)...`
3. Fields in Arc fill visibly
4. No Submit/Apply button is clicked at any point
5. Terminal shows `[apply] Done. Review the form in Arc and submit manually.`
6. Arc window remains open after terminal returns to prompt

- [ ] **Step 3: Check terminal summary**

Claude should print something like:

```
Filled:
  - First name → Ivan
  - Last name → Rivera
  - Email → ivan.s.rivera@gmail.com
  - Phone → +61449857572
  - LinkedIn → https://www.linkedin.com/in/isrivera/
  - Current title → ML Specialist

Skipped:
  - Resume upload → file input
  - Cover letter → file input
```

- [ ] **Step 4: Note any ATS-specific quirks**

Record: fields Claude missed, dropdowns that failed to match, JS-rendered fields that caused issues, turn count used.

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Append to `## Session Log`**

Add after the existing `### 2026-04-05` entry:

```markdown
### 2026-04-13 — Form autofill feature
- Added `make apply URL=<url>` target for automated browser form filling.
- Architecture: `autofill.sh` launches Arc with `--remote-debugging-port=9222`; Playwright MCP connects via `--cdp-endpoint http://localhost:9222`; Claude fills fields semantically from `data/resume.yaml`.
- CDP bridge is how the browser stays open after `claude -p` exits — Arc launched independently survives the MCP server shutdown.
- `config/playwright-mcp.json` uses key `playwright-arc` (not `playwright`) to avoid colliding with the global `playwright@claude-plugins-official` plugin.
- File upload fields always skipped — attach resume PDF and cover letter manually.
- Multi-page form navigation (Next/Continue) is out of scope for v1.
- [Append ATS-specific notes from smoke test here]
```

- [ ] **Step 2: Commit**

```
docs: update CLAUDE.md with form autofill session log
```
