#!/usr/bin/env python3
"""
Generate structured feedback for iterative refinement rounds.

This script synthesizes review findings and metadata from a previous round's result
into actionable improvement suggestions for the next refinement round.

Typical usage:
    ./generate_feedback.py \\
      --result-file work/cmd_036/results/result_7.md \\
      --metadata-json /tmp/metadata.json \\
      --output /tmp/feedback_round2.md
"""

import argparse
import json
import sys
from pathlib import Path


def extract_section(content: str, section_name: str) -> list[str]:
    """
    Extract a section from markdown content.

    Args:
        content: Full markdown content
        section_name: Section header to find (e.g., "## Issues", "## Warnings")

    Returns:
        List of items in the section, or empty list if not found
    """
    lines = content.split('\n')
    items = []
    in_section = False

    for i, line in enumerate(lines):
        # Check for section header
        if line.strip().startswith(section_name):
            in_section = True
            continue

        # If we were in the section and hit another header, we're done
        if in_section and line.strip().startswith('##'):
            break

        # If we're in the section, capture bullet points
        if in_section:
            stripped = line.strip()
            if stripped.startswith('- '):
                # Extract text after "- "
                item = stripped[2:].strip()
                if item:
                    items.append(item)
            elif stripped.startswith('* '):
                # Also support asterisk bullets
                item = stripped[2:].strip()
                if item:
                    items.append(item)

    return items


def load_metadata(metadata_json_path: str) -> dict:
    """
    Load metadata from JSON file.

    Args:
        metadata_json_path: Path to JSON metadata file

    Returns:
        Dictionary with metadata (may be empty if file doesn't exist)
    """
    try:
        with open(metadata_json_path, 'r') as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def read_result_file(result_path: str) -> str:
    """
    Read the entire result file.

    Args:
        result_path: Path to result_N.md file

    Returns:
        Full file content
    """
    with open(result_path, 'r') as f:
        return f.read()


def categorize_issues(issues: list[str], warnings: list[str]) -> tuple[list[str], list[str]]:
    """
    Categorize issues and warnings into critical and improvement categories.

    Args:
        issues: List of issues from ## Issues section
        warnings: List of warnings from ## Warnings section

    Returns:
        Tuple of (critical_issues, improvements)
    """
    # Issues map to critical (must-fix)
    critical = list(issues)

    # Warnings map to improvements (nice-to-have)
    improvements = list(warnings)

    return critical, improvements


def generate_strengths(content: str) -> list[str]:
    """
    Extract strengths from result content.

    Looks for common positive indicators in the content:
    - Test passing statements
    - Verification/validation success
    - Implementation completeness

    Args:
        content: Full markdown content

    Returns:
        List of identified strengths
    """
    strengths = []
    lines = content.split('\n')

    # Skip the metadata header (first ~10 lines)
    start_idx = 0
    for i, line in enumerate(lines):
        if line.strip() == '---' and i > 0:
            start_idx = i + 1
            break

    for line in lines[start_idx:]:
        stripped = line.strip()

        # Skip section headers, empty lines, and bullet items from Issues/Warnings
        if not stripped or stripped.startswith('#') or stripped.startswith('- '):
            continue

        # Look for positive indicators only in non-bullet content
        lower = stripped.lower()
        if ('test' in lower and ('pass' in lower or 'success' in lower)):
            strengths.append(stripped)
        elif ('verif' in lower and 'pass' in lower):
            strengths.append(stripped)
        elif 'all' in lower and 'pass' in lower:
            strengths.append(stripped)

    # Limit to unique items, max 3
    return list(dict.fromkeys(strengths))[:3]


def format_feedback_markdown(
    critical_issues: list[str],
    improvements: list[str],
    strengths: list[str],
    round_number: int = 2
) -> str:
    """
    Format feedback into structured markdown.

    Args:
        critical_issues: List of critical issues to fix
        improvements: List of suggested improvements
        strengths: List of strengths to preserve
        round_number: Next round number (default: 2)

    Returns:
        Formatted markdown string
    """
    lines = []
    lines.append(f"# Feedback for Round {round_number}\n")

    # Critical Issues section
    lines.append("## Critical Issues (Must Fix)")
    if critical_issues:
        for issue in critical_issues:
            lines.append(f"- {issue}")
    else:
        lines.append("- No critical issues identified")
    lines.append("")

    # Suggested Improvements section
    lines.append("## Suggested Improvements")
    if improvements:
        for improvement in improvements:
            lines.append(f"- {improvement}")
    else:
        lines.append("- No suggested improvements")
    lines.append("")

    # Strengths to Preserve section
    lines.append("## Strengths to Preserve")
    if strengths:
        for strength in strengths:
            lines.append(f"- {strength}")
    else:
        lines.append("- Continue current approach; iterate on issues identified")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Generate structured feedback for iterative refinement rounds"
    )
    parser.add_argument(
        "--result-file",
        required=True,
        help="Path to previous round's result_N.md file"
    )
    parser.add_argument(
        "--metadata-json",
        required=True,
        help="Path to extracted metadata JSON file"
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path where feedback markdown will be written"
    )
    parser.add_argument(
        "--round-number",
        type=int,
        default=2,
        help="Next round number for feedback header (default: 2)"
    )

    args = parser.parse_args()

    # Validate input files exist
    if not Path(args.result_file).exists():
        print(f"ERROR: Result file not found: {args.result_file}", file=sys.stderr)
        sys.exit(1)

    # Read result file
    try:
        result_content = read_result_file(args.result_file)
    except IOError as e:
        print(f"ERROR: Failed to read result file: {e}", file=sys.stderr)
        sys.exit(1)

    # Load metadata (non-fatal if missing)
    metadata = load_metadata(args.metadata_json)

    # Extract sections from result file
    issues = extract_section(result_content, "## Issues")
    warnings = extract_section(result_content, "## Warnings")

    # Categorize findings
    critical_issues, improvements = categorize_issues(issues, warnings)

    # Extract strengths
    strengths = generate_strengths(result_content)

    # Generate feedback markdown
    feedback = format_feedback_markdown(
        critical_issues,
        improvements,
        strengths,
        args.round_number
    )

    # Write output
    try:
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w') as f:
            f.write(feedback)
        print(f"Feedback generated: {args.output}")
    except IOError as e:
        print(f"ERROR: Failed to write output file: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
