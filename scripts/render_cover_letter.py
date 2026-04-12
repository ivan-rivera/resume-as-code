#!/usr/bin/env python3
"""Render cover_letter_data.yaml to Markdown."""

import sys
from pathlib import Path

import yaml


def render_markdown(data: dict) -> str:
    """Render cover letter data dict to a Markdown string."""
    recipient = data['recipient']
    sender = data['sender']
    date = data['date']
    p = data['paragraphs']

    return (
        f"# Cover Letter — {recipient['role']} at {recipient['company']}\n"
        f"{date}\n\n"
        f"Dear Hiring Team,\n\n"
        f"{p['opening']}\n\n"
        f"{p['technical_fit']}\n\n"
        f"{p['company_specific']}\n\n"
        f"{p['closing']}\n\n"
        f"Warm regards,\n"
        f"{sender['name']}\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        print(
            f"Usage: {sys.argv[0]} <cover_letter_data.yaml> <output.md>",
            file=sys.stderr,
        )
        sys.exit(1)

    input_path, output_path = sys.argv[1], sys.argv[2]

    with open(input_path) as f:
        data = yaml.safe_load(f)

    md = render_markdown(data)

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, 'w') as f:
        f.write(md)

    print(f"Cover letter written to {output_path}")


if __name__ == '__main__':
    main()
