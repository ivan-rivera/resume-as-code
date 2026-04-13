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
