#!/usr/bin/env python3
"""
Convert resume.md to resume.yaml according to instructions.
"""
import re
import yaml
import sys
from datetime import datetime

def read_resume_md(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    return content

def parse_sections(content):
    """Parse markdown sections by heading level."""
    lines = content.split('\n')
    sections = {}
    current_heading = None
    current_lines = []

    for line in lines:
        if line.startswith('# '):
            if current_heading:
                sections[current_heading] = '\n'.join(current_lines).strip()
            current_heading = line[2:].strip()
            current_lines = []
        elif line.startswith('## '):
            # Subheadings are part of the parent section
            current_lines.append(line)
        else:
            current_lines.append(line)
    if current_heading:
        sections[current_heading] = '\n'.join(current_lines).strip()
    return sections

def extract_work_experience(content):
    """Extract work experience entries."""
    # Find the Work experience section
    work_start = content.find('# Work experience')
    if work_start == -1:
        return []
    # Find next top-level heading after work experience
    next_section = content.find('\n# ', work_start + 1)
    if next_section == -1:
        work_section = content[work_start:]
    else:
        work_section = content[work_start:next_section]

    # Split by ## headings (each role)
    entries = []
    pattern = r'## (.+?)\n(.*?)(?=\n## |\Z)'
    matches = re.findall(pattern, work_section, re.DOTALL)
    for title, body in matches:
        entries.append((title.strip(), body.strip()))
    return entries

def main():
    content = read_resume_md('resume.md')
    sections = parse_sections(content)
    print("Sections found:", list(sections.keys()))

    # Test work experience extraction
    work_entries = extract_work_experience(content)
    for title, body in work_entries:
        print(f"Title: {title}")
        print(f"Body length: {len(body)}")
        print()

if __name__ == '__main__':
    main()