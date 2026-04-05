"""Tests for YAML patch application logic."""
import sys
import pytest
from copy import deepcopy

sys.path.insert(0, '.')
from scripts.apply_patch import apply_patch, get_nested, set_nested

SAMPLE = {
    'experience': [
        {
            'company': 'Spotify',
            'bullets': ['Improved ranking algorithm', 'Built RAG LLM'],
        },
        {
            'company': 'BidOne',
            'bullets': ['Built AI team'],
        },
    ],
    'skills': [{'group': 'ML & AI', 'items': ['LLM', 'RAG']}],
    'personal': {'name': 'Ivan Rivera'},
}


def test_get_nested_dict_key():
    assert get_nested(SAMPLE, 'personal.name') == 'Ivan Rivera'


def test_get_nested_list_index():
    assert get_nested(SAMPLE, 'experience[0].company') == 'Spotify'


def test_get_nested_deep():
    assert get_nested(SAMPLE, 'experience[0].bullets[1]') == 'Built RAG LLM'


def test_set_nested_list():
    data = deepcopy(SAMPLE)
    set_nested(data, 'experience[0].bullets[0]', 'Shipped new ranking algorithm')
    assert data['experience'][0]['bullets'][0] == 'Shipped new ranking algorithm'


def test_set_nested_dict():
    data = deepcopy(SAMPLE)
    set_nested(data, 'personal.name', 'I. Rivera')
    assert data['personal']['name'] == 'I. Rivera'


def test_apply_patch_replaces_matching_value():
    patches = [{
        'path': 'experience[0].bullets[0]',
        'original': 'Improved ranking algorithm',
        'replacement': 'Shipped ML ranking algorithm driving subscriber growth',
    }]
    result = apply_patch(SAMPLE, patches)
    assert result['experience'][0]['bullets'][0] == 'Shipped ML ranking algorithm driving subscriber growth'


def test_apply_patch_does_not_mutate_original():
    patches = [{
        'path': 'experience[0].bullets[0]',
        'original': 'Improved ranking algorithm',
        'replacement': 'New text',
    }]
    apply_patch(SAMPLE, patches)
    assert SAMPLE['experience'][0]['bullets'][0] == 'Improved ranking algorithm'


def test_apply_patch_skips_wrong_original():
    patches = [{
        'path': 'experience[0].bullets[0]',
        'original': 'THIS DOES NOT MATCH',
        'replacement': 'Should not appear',
    }]
    result = apply_patch(SAMPLE, patches)
    assert result['experience'][0]['bullets'][0] == 'Improved ranking algorithm'


def test_apply_patch_skips_invalid_path():
    patches = [{'path': 'experience[99].bullets[0]', 'original': 'x', 'replacement': 'y'}]
    result = apply_patch(SAMPLE, patches)  # must not raise
    assert result == SAMPLE


def test_apply_patch_empty_list():
    result = apply_patch(SAMPLE, [])
    assert result == SAMPLE


def test_apply_patch_multiple_patches():
    patches = [
        {'path': 'experience[0].bullets[0]', 'original': 'Improved ranking algorithm', 'replacement': 'Shipped ML ranking algorithm'},
        {'path': 'experience[0].bullets[1]', 'original': 'Built RAG LLM', 'replacement': 'Built production RAG system'},
    ]
    result = apply_patch(SAMPLE, patches)
    assert result['experience'][0]['bullets'][0] == 'Shipped ML ranking algorithm'
    assert result['experience'][0]['bullets'][1] == 'Built production RAG system'
