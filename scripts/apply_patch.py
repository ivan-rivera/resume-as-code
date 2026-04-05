#!/usr/bin/env python3
"""Apply an LLM-generated YAML patch to resume.yaml, producing tailored.yaml."""

import re
import sys
from copy import deepcopy
from pathlib import Path

import yaml


def _parse_path(path: str) -> list:
    """Tokenize a dotted/indexed path into a list of keys (str) and indices (int).

    'experience[0].bullets[1]' → ['experience', 0, 'bullets', 1]
    """
    tokens = []
    for key, idx in re.findall(r'(\w+)|\[(\d+)\]', path):
        if key:
            tokens.append(key)
        else:
            tokens.append(int(idx))
    return tokens


def get_nested(data, path: str):
    """Navigate a dotted/indexed path like 'experience[1].bullets[0]'."""
    node = data
    for token in _parse_path(path):
        node = node[token]
    return node


def set_nested(data, path: str, value):
    """Set a value at a dotted/indexed path."""
    tokens = _parse_path(path)
    node = data
    for token in tokens[:-1]:
        node = node[token]
    node[tokens[-1]] = value


def apply_patch(original: dict, patches: list) -> dict:
    """Apply a list of {path, original, replacement} patches. Returns a deep copy."""
    result = deepcopy(original)
    for patch in patches:
        path = patch['path']
        expected = patch['original']
        replacement = patch['replacement']
        try:
            current = get_nested(result, path)
            if current != expected:
                print(
                    f"WARNING: path '{path}' value mismatch — skipping patch",
                    file=sys.stderr,
                )
                continue
            set_nested(result, path, replacement)
        except (KeyError, IndexError, TypeError) as exc:
            print(
                f"WARNING: could not apply patch at '{path}': {exc} — skipping",
                file=sys.stderr,
            )
    return result


def main() -> None:
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <original.yaml> <patch.yaml> <output.yaml>", file=sys.stderr)
        sys.exit(1)

    original_path, patch_path, output_path = sys.argv[1:]

    with open(original_path) as f:
        original = yaml.safe_load(f)

    with open(patch_path) as f:
        patch_data = yaml.safe_load(f)

    patches = patch_data.get('patches', []) if patch_data else []
    if not patches:
        print("WARNING: No patches found — writing original as-is", file=sys.stderr)

    patched = apply_patch(original, patches)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w') as f:
        yaml.dump(patched, f, allow_unicode=True, default_flow_style=False, sort_keys=False)

    print(f"Applied {len(patches)} patch(es) → {output_path}")


if __name__ == '__main__':
    main()
