#!/usr/bin/env python3
"""
validate_round.py - Round validation script for iterative refinement

Validates a round's output against quality thresholds by checking:
- Status (must be success or partial, not failure)
- Quality level (must meet or exceed threshold: RED < YELLOW < GREEN)
- Completeness percentage (must meet or exceed threshold)

Usage:
    ./validate_round.py --metadata-json PATH [--quality-threshold LEVEL] [--completeness-threshold N]

Arguments:
    --metadata-json PATH          Path to metadata JSON file (required)
    --quality-threshold LEVEL     Minimum quality level (RED/YELLOW/GREEN, default: GREEN)
    --completeness-threshold N    Minimum completeness percentage (0-100, default: 90)

Output:
    JSON object with validation result:
    {
      "valid": true/false,
      "reason": "Passed all thresholds" or failure reason,
      "checks": {
        "status": "pass/fail",
        "quality": "pass/fail",
        "completeness": "pass/fail"
      }
    }

Exit codes:
    0 - Validation passed
    1 - Validation failed
    2 - Error (invalid input, missing file, etc.)
"""

import argparse
import json
import sys
from pathlib import Path


# Quality level ordering (lower index = lower quality)
QUALITY_LEVELS = ["RED", "YELLOW", "GREEN"]


def load_metadata(filepath):
    """Load and parse metadata JSON file.

    Args:
        filepath: Path to metadata JSON file

    Returns:
        dict: Parsed metadata

    Raises:
        FileNotFoundError: If file does not exist
        json.JSONDecodeError: If file contains invalid JSON
        ValueError: If required fields are missing
    """
    path = Path(filepath)
    if not path.exists():
        raise FileNotFoundError(f"Metadata file not found: {filepath}")

    with open(path, 'r') as f:
        try:
            metadata = json.load(f)
        except json.JSONDecodeError as e:
            raise json.JSONDecodeError(
                f"Invalid JSON in metadata file: {e.msg}",
                e.doc,
                e.pos
            )

    # Validate required fields exist
    # Note: We apply defaults for missing fields per CLAUDE.md Phase 2 step 4c
    if 'status' not in metadata:
        metadata['status'] = 'failure'  # Safe default per spec

    if 'quality' not in metadata:
        metadata['quality'] = 'YELLOW'  # Unknown quality default

    if 'completeness' not in metadata:
        metadata['completeness'] = 0  # Incomplete by default

    return metadata


def validate_status(status):
    """Check if status is acceptable (success or partial).

    Args:
        status: Status string from metadata

    Returns:
        tuple: (passed: bool, reason: str or None)
    """
    acceptable_statuses = ["success", "partial"]

    if status in acceptable_statuses:
        return (True, None)
    else:
        return (False, f"Status '{status}' not in acceptable values {acceptable_statuses}")


def validate_quality(quality, threshold):
    """Check if quality meets or exceeds threshold.

    Quality ordering: RED < YELLOW < GREEN

    Args:
        quality: Quality level from metadata
        threshold: Minimum acceptable quality level

    Returns:
        tuple: (passed: bool, reason: str or None)
    """
    if quality not in QUALITY_LEVELS:
        return (False, f"Invalid quality level '{quality}' (must be RED/YELLOW/GREEN)")

    if threshold not in QUALITY_LEVELS:
        return (False, f"Invalid quality threshold '{threshold}' (must be RED/YELLOW/GREEN)")

    quality_index = QUALITY_LEVELS.index(quality)
    threshold_index = QUALITY_LEVELS.index(threshold)

    if quality_index >= threshold_index:
        return (True, None)
    else:
        return (False, f"Quality {quality} below threshold {threshold}")


def validate_completeness(completeness, threshold):
    """Check if completeness meets or exceeds threshold.

    Args:
        completeness: Completeness percentage (0-100)
        threshold: Minimum acceptable completeness

    Returns:
        tuple: (passed: bool, reason: str or None)
    """
    try:
        completeness_val = float(completeness)
        threshold_val = float(threshold)
    except (ValueError, TypeError):
        return (False, f"Invalid completeness values: {completeness} / {threshold}")

    if not (0 <= completeness_val <= 100):
        return (False, f"Completeness {completeness_val} out of valid range [0-100]")

    if not (0 <= threshold_val <= 100):
        return (False, f"Completeness threshold {threshold_val} out of valid range [0-100]")

    if completeness_val >= threshold_val:
        return (True, None)
    else:
        return (False, f"Completeness {completeness_val}% below threshold {threshold_val}%")


def validate_round(metadata, quality_threshold, completeness_threshold):
    """Validate round output against thresholds.

    Args:
        metadata: Metadata dictionary
        quality_threshold: Minimum quality level
        completeness_threshold: Minimum completeness percentage

    Returns:
        dict: Validation result with structure:
            {
              "valid": bool,
              "reason": str,
              "checks": {
                "status": "pass" | "fail",
                "quality": "pass" | "fail",
                "completeness": "pass" | "fail"
              }
            }
    """
    checks = {}
    reasons = []

    # Check status
    status_pass, status_reason = validate_status(metadata['status'])
    checks['status'] = 'pass' if status_pass else 'fail'
    if not status_pass:
        reasons.append(status_reason)

    # Check quality
    quality_pass, quality_reason = validate_quality(
        metadata['quality'],
        quality_threshold
    )
    checks['quality'] = 'pass' if quality_pass else 'fail'
    if not quality_pass:
        reasons.append(quality_reason)

    # Check completeness
    completeness_pass, completeness_reason = validate_completeness(
        metadata['completeness'],
        completeness_threshold
    )
    checks['completeness'] = 'pass' if completeness_pass else 'fail'
    if not completeness_pass:
        reasons.append(completeness_reason)

    # Overall validation
    all_passed = status_pass and quality_pass and completeness_pass

    return {
        'valid': all_passed,
        'reason': 'Passed all thresholds' if all_passed else '; '.join(reasons),
        'checks': checks
    }


def main():
    parser = argparse.ArgumentParser(
        description='Validate round output against quality thresholds',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument(
        '--metadata-json',
        required=True,
        help='Path to metadata JSON file'
    )

    parser.add_argument(
        '--quality-threshold',
        default='GREEN',
        choices=QUALITY_LEVELS,
        help='Minimum quality level (default: GREEN)'
    )

    parser.add_argument(
        '--completeness-threshold',
        type=int,
        default=90,
        help='Minimum completeness percentage (default: 90)'
    )

    args = parser.parse_args()

    try:
        # Load metadata
        metadata = load_metadata(args.metadata_json)

        # Validate
        result = validate_round(
            metadata,
            args.quality_threshold,
            args.completeness_threshold
        )

        # Output result as JSON
        print(json.dumps(result, indent=2))

        # Exit code based on validation result
        sys.exit(0 if result['valid'] else 1)

    except FileNotFoundError as e:
        error_result = {
            'valid': False,
            'reason': str(e),
            'checks': {}
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(2)

    except json.JSONDecodeError as e:
        error_result = {
            'valid': False,
            'reason': f"Invalid JSON: {e.msg}",
            'checks': {}
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(2)

    except Exception as e:
        error_result = {
            'valid': False,
            'reason': f"Unexpected error: {str(e)}",
            'checks': {}
        }
        print(json.dumps(error_result, indent=2), file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
