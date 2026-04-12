"""Tests for cover letter YAML → Markdown renderer."""
import sys
import pytest

sys.path.insert(0, '.')
from scripts.render_cover_letter import render_markdown

SAMPLE_DATA = {
    'recipient': {
        'company': 'Acme Corp',
        'role': 'Lead ML Engineer',
    },
    'sender': {
        'name': 'Ivan Rivera',
    },
    'date': '12 April 2026',
    'paragraphs': {
        'opening': 'Opening paragraph text.',
        'technical_fit': 'Technical fit paragraph text.',
        'company_specific': 'Company specific paragraph text.',
        'closing': 'Closing paragraph text.',
    },
}


def test_render_contains_role_and_company():
    md = render_markdown(SAMPLE_DATA)
    assert 'Lead ML Engineer' in md
    assert 'Acme Corp' in md


def test_render_contains_date():
    md = render_markdown(SAMPLE_DATA)
    assert '12 April 2026' in md


def test_render_contains_all_paragraphs():
    md = render_markdown(SAMPLE_DATA)
    assert 'Opening paragraph text.' in md
    assert 'Technical fit paragraph text.' in md
    assert 'Company specific paragraph text.' in md
    assert 'Closing paragraph text.' in md


def test_render_contains_sender_name():
    md = render_markdown(SAMPLE_DATA)
    assert 'Ivan Rivera' in md


def test_render_paragraphs_are_separated():
    md = render_markdown(SAMPLE_DATA)
    # Each paragraph must be separated by a blank line
    assert '\n\nOpening paragraph text.' in md
    lines = md.split('\n')
    non_empty = [l for l in lines if l.strip()]
    assert len(non_empty) >= 9  # heading, date, greeting, 4 paragraphs, sign-off, sender name
