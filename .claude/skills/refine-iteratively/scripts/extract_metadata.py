#!/usr/bin/env python3
"""
Extract YAML frontmatter metadata from result files.

This script reads a result file with YAML frontmatter (delimited by --- markers)
and outputs the extracted metadata as JSON.

Usage:
    ./extract_metadata.py --file path/to/result_file.md
"""

import sys
import json
import argparse
from pathlib import Path


def extract_frontmatter(file_content: str) -> dict:
    """
    Extract YAML frontmatter from file content.

    Expected format:
    ---
    key1: value1
    key2: value2
    ---
    Rest of content...

    Args:
        file_content: The full file content as a string

    Returns:
        Dictionary with parsed YAML frontmatter

    Raises:
        ValueError: If frontmatter is malformed or invalid YAML
    """
    lines = file_content.split('\n')

    # Check for opening --- delimiter
    if not lines or lines[0].strip() != '---':
        raise ValueError("File does not start with '---' delimiter")

    # Find closing --- delimiter
    closing_index = None
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            closing_index = i
            break

    if closing_index is None:
        raise ValueError("No closing '---' delimiter found for frontmatter")

    # Extract frontmatter content (preserve structure for list parsing)
    frontmatter_lines = lines[1:closing_index]

    # Parse YAML manually (without external dependencies)
    metadata = {}
    current_key = None
    current_list = None

    for line in frontmatter_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue

        # Check if this is a list item (starts with -)
        if stripped.startswith('- '):
            if current_key is not None:
                if current_list is None:
                    current_list = []
                item_value = stripped[2:].strip()
                current_list.append(item_value)
            continue

        # Standard key: value parsing
        if ':' not in stripped:
            raise ValueError(f"Invalid YAML line: {stripped}")

        # If we were accumulating a list, save it first
        if current_key is not None and current_list is not None:
            metadata[current_key] = current_list
            current_list = None

        key, value = stripped.split(':', 1)
        key = key.strip()
        value = value.strip()
        current_key = key

        # Parse value based on type indicators
        if not value:
            # Empty value, might be a list or null
            metadata[key] = None
        elif value.lower() in ('true', 'false'):
            metadata[key] = value.lower() == 'true'
        elif value.lower() in ('null', 'none', '~'):
            metadata[key] = None
        elif value.startswith('[') and value.endswith(']'):
            # Simple list parsing for empty [] or simple values
            inner = value[1:-1].strip()
            if not inner:
                metadata[key] = []
            else:
                # Parse comma-separated items (basic approach)
                items = [item.strip().strip('"\'') for item in inner.split(',')]
                metadata[key] = items
            current_list = None
        elif value.isdigit():
            metadata[key] = int(value)
        elif value.startswith('"') and value.endswith('"'):
            metadata[key] = value[1:-1]
            current_list = None
        elif value.startswith("'") and value.endswith("'"):
            metadata[key] = value[1:-1]
            current_list = None
        else:
            # Keep as string
            metadata[key] = value
            current_list = None

    # Save any remaining list
    if current_key is not None and current_list is not None:
        metadata[current_key] = current_list

    return metadata


def extract_metadata(filepath: str) -> dict:
    """
    Read a result file and extract metadata with defaults.

    Args:
        filepath: Path to the result file

    Returns:
        Dictionary with extracted metadata and applied defaults

    Raises:
        FileNotFoundError: If file does not exist
        ValueError: If file is empty or frontmatter is invalid
    """
    path = Path(filepath)

    if not path.exists():
        raise FileNotFoundError(f"File not found: {filepath}")

    if not path.is_file():
        raise ValueError(f"Path is not a file: {filepath}")

    # Read file content
    try:
        content = path.read_text(encoding='utf-8')
    except Exception as e:
        raise ValueError(f"Failed to read file: {e}")

    if not content.strip():
        raise ValueError("File is empty")

    # Extract frontmatter
    try:
        metadata = extract_frontmatter(content)
    except ValueError as e:
        raise ValueError(f"Failed to parse frontmatter: {e}")

    # Apply defaults for required fields
    defaults = {
        'status': 'unknown',
        'quality': 'YELLOW',
        'completeness': 0,
        'errors': [],
        'warnings': []
    }

    # Build result with defaults
    result = {}
    for key, default_value in defaults.items():
        result[key] = metadata.get(key, default_value)

    return result


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Extract YAML frontmatter metadata from result files'
    )
    parser.add_argument(
        '--file',
        required=True,
        help='Path to the result file with YAML frontmatter'
    )

    args = parser.parse_args()

    try:
        metadata = extract_metadata(args.file)
        # Output as JSON to stdout
        json.dump(metadata, sys.stdout, indent=2)
        sys.stdout.write('\n')
        return 0
    except FileNotFoundError as e:
        error_output = {
            'status': 'unknown',
            'quality': 'YELLOW',
            'completeness': 0,
            'errors': [str(e)],
            'warnings': []
        }
        json.dump(error_output, sys.stderr, indent=2)
        sys.stderr.write('\n')
        return 1
    except ValueError as e:
        error_output = {
            'status': 'unknown',
            'quality': 'YELLOW',
            'completeness': 0,
            'errors': [str(e)],
            'warnings': []
        }
        json.dump(error_output, sys.stderr, indent=2)
        sys.stderr.write('\n')
        return 1
    except Exception as e:
        error_output = {
            'status': 'unknown',
            'quality': 'YELLOW',
            'completeness': 0,
            'errors': [f'Unexpected error: {e}'],
            'warnings': []
        }
        json.dump(error_output, sys.stderr, indent=2)
        sys.stderr.write('\n')
        return 1


if __name__ == '__main__':
    sys.exit(main())
