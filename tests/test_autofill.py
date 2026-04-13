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
