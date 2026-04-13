# Form Autofill Design Spec
**Date:** 2026-04-13  
**Status:** Approved

## Problem

Structured job application forms (Greenhouse, Lever, Workday, Ashby, etc.) require manual re-entry of information already present in `resume.yaml`. This is repetitive and error-prone. The goal is a `make apply URL=<form-url>` target that navigates to the form, fills all fields from `resume.yaml`, and hands control back to the user for review and submission.

## Constraints

- Uses `data/resume.yaml` as the sole data source (no tailored variant)
- Never submits or advances the form — user retains full control
- Consistent with existing pipeline style: bash orchestration, `claude -p` for intelligence
- No new authentication mechanism — uses existing Claude Code OAuth
- Browser must remain open after filling for manual review

---

## Architecture

### Make target

```makefile
apply: guard-URL check-deps
    @bash scripts/autofill.sh "$(URL)" $(RESUME_YAML)
```

Added to `.PHONY`. `check-deps` gains a check for `node`/`npx` (needed only if Playwright plugin fallback is required — see below).

### Invocation

```
make apply URL=https://jobs.lever.co/acme/abc123
```

---

## Components

### `scripts/autofill.sh`

Bash script, consistent with existing pipeline style. Responsibilities:

1. Construct a user prompt embedding the target URL and full `resume.yaml` content
2. Invoke `claude -p` with:
   - `--system-prompt-file prompts/autofill_system.txt`
   - `--max-turns 30` (headroom for multi-page or JS-heavy forms)
   - `--no-session-persistence`
   - `--output-format text`
   - `--model $MODEL` (respects existing `MODEL` variable)
3. Exit when the agent loop completes — browser stays open

```bash
#!/usr/bin/env bash
set -euo pipefail

URL="$1"
RESUME_YAML="$2"
MODEL="${MODEL:-claude-sonnet-4-6}"
MCP_CONFIG="config/playwright-mcp.json"

PROMPT=$(cat <<EOF
Navigate to ${URL} and fill out the job application form using the candidate profile below.

Rules:
- Do NOT click Submit, Apply, Next, Continue, Save, or any button that advances or submits the form
- Fill all visible text inputs, textareas, dropdowns, checkboxes, and radio buttons
- Skip file upload fields — list each one by its label so the user knows what to attach manually
- If a required field has no matching data in the candidate profile, leave it empty
- When done, print a summary: fields filled, fields skipped (with reason)

<CANDIDATE_PROFILE>
$(cat "${RESUME_YAML}")
</CANDIDATE_PROFILE>
EOF
)

# Use --mcp-config only if the playwright plugin is not available via global config
if [ -f "${MCP_CONFIG}" ]; then
  MCP_ARGS="--mcp-config ${MCP_CONFIG}"
else
  MCP_ARGS=""
fi

claude -p "${PROMPT}" \
  --system-prompt-file prompts/autofill_system.txt \
  ${MCP_ARGS} \
  --max-turns 30 \
  --no-session-persistence \
  --output-format text \
  --model "${MODEL}"
```

### `prompts/autofill_system.txt`

System prompt constraining Claude's behaviour:

- You are a browser automation agent filling a job application form on behalf of a candidate
- Use Playwright tools to navigate, inspect, and fill fields
- Infer field intent from label text (e.g. "First Name", "Current Company", "LinkedIn URL")
- Map candidate profile fields to form fields semantically — do not require exact label matches
- For dropdowns, select the closest matching option (e.g. "Australia" for location, "Full-time" for work type)
- For work history fields, use the most recent role unless the form requests a specific entry
- **Never interact with Submit, Apply, Next, Continue, Save, or any button that would advance or submit the form**
- File inputs: identify by label and skip — do not attempt to upload
- When complete, output a plain-text summary listing filled fields and skipped fields with reasons

### `config/playwright-mcp.json` *(conditional)*

Only created if the `playwright@claude-plugins-official` plugin does not propagate to `claude -p` headless invocations. Determined during implementation step 1 (see below).

When the Playwright plugin is unavailable, the MCP server is configured to connect to Arc via CDP rather than launching its own browser. This is what keeps the browser alive after `claude -p` exits (see Browser behaviour section).

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp", "--cdp-endpoint", "http://localhost:9222"]
    }
  }
}
```

---

## Browser behaviour

### Keeping the browser open — the CDP approach

A critical constraint: when `claude -p` exits it kills the Playwright MCP child process, which closes any browser the MCP server launched itself. To satisfy "browser must remain open after filling," the script launches Arc **independently** before invoking Claude, then connects Playwright to it via CDP:

1. `autofill.sh` opens a new Arc window with the remote debug port:
   ```bash
   open -na "Arc" --args --remote-debugging-port=9222 --new-window "$URL"
   sleep 3  # allow Arc to start and load the page
   ```
2. Playwright MCP connects to `http://localhost:9222` (the running Arc window) instead of launching its own browser
3. Claude fills the form via that CDP connection
4. `claude -p` exits → MCP server exits → CDP connection drops — but Arc continues running independently, form intact

The user then reviews and submits in the Arc window that's already open.

**Note:** Arc must not already be running with a different `--remote-debugging-port`. If port 9222 is in use, the script exits with a clear error.

### Fallback — if the Playwright plugin propagates to `claude -p`

If implementation step 1 confirms the plugin works in `claude -p` headless mode, the plugin may manage its own browser lifecycle differently. In that case, test whether the browser stays open after `claude -p` exits. If it does, the CDP approach is unnecessary. If it doesn't, fall back to the CDP approach above regardless of plugin availability.

- User reviews, corrects any missed fields, and submits manually
- Terminal prints the agent's final summary (filled / skipped counts)

---

## Error handling

| Scenario | Behaviour |
|---|---|
| Page load timeout | Playwright raises timeout error; `claude` reports it; script exits non-zero |
| Auth-gated form (login wall) | Claude reports it cannot access form fields; exits with message |
| Field selector not found | Claude logs the skip and continues — partial fill is better than abort |
| No matching profile data for a field | Left empty, listed in summary |
| File upload field | Skipped, listed in summary by label name |
| `claude -p` exits mid-form (turn limit) | Browser stays open at whatever state was reached |

---

## New files

| File | Purpose |
|---|---|
| `scripts/autofill.sh` | Main entry point — constructs prompt, calls `claude -p` |
| `prompts/autofill_system.txt` | System prompt constraining agent behaviour |
| `config/playwright-mcp.json` | MCP config fallback (only if plugin doesn't propagate) |

---

## Implementation sequence

**Step 1 — Playwright plugin verification**  
Run `claude -p "List your available MCP tools" --max-turns 1 --no-session-persistence --output-format text` and check whether Playwright tools appear. If yes: skip `config/playwright-mcp.json`. If no: create it and add `--mcp-config` to the script.

**Step 2 — `prompts/autofill_system.txt`**  
Write the system prompt.

**Step 3 — `scripts/autofill.sh`**  
Write the shell script. Include Arc launch via `open -na "Arc" --args --remote-debugging-port=9222 --new-window "$URL"` and the 9222 port-in-use guard before the `claude -p` invocation.

**Step 4 — Makefile target**  
Add `apply` target and update `check-deps` and `.PHONY`.

**Step 5 — Update `make help`**  
Add `make apply URL=<url>` to the help text.

**Step 6 — Smoke test**  
Run `make apply URL=https://jobs.lever.co/anthropic` (or any live Lever form) and verify fields fill without submission.

**Step 7 — CLAUDE.md update**  
Append session log entry documenting what worked and any ATS-specific quirks discovered.

---

## Out of scope

- Resume PDF or cover letter upload (file inputs — manual step)
- Multi-page form navigation (Next/Continue buttons) — single-page fill only in v1
- Form validation error recovery
- Saving partially filled forms
