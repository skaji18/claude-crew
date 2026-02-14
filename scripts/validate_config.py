#!/usr/bin/env python3
"""
validate_config.py - Configuration validation for claude-crew

Validates config.yaml structure and field values using the error code system.
Usage: python3 scripts/validate_config.py [config_path]
Exit code: 0 = valid, non-zero = invalid
"""

import sys
import os
import re
from typing import Dict, Any, List, Tuple, Optional

# ============================================================================
# Error Code System (from scripts/error_codes.sh)
# ============================================================================

ERROR_CODES = {
    "E001": "config.yaml not found → Run: bash scripts/setup.sh",
    "E002": "config.yaml parse error - invalid YAML → Check YAML syntax with a YAML validator or PyYAML",
    "E003": "config.yaml missing required field → Run: bash scripts/validate_config.sh to identify missing fields",
    "E004": "default_model invalid - expected haiku, sonnet, or opus → Edit config.yaml and set default_model appropriately",
    "E005": "max_parallel out of range - expected 1-20 → Edit config.yaml and set max_parallel to a value between 1 and 20",
    "E006": "max_retries out of range - expected 0-10 → Edit config.yaml and set max_retries to a value between 0 and 10",
    "E007": "worker_max_turns out of range - expected 5-100 → Edit config.yaml and set worker_max_turns to a value between 5 and 100",
    "E008": "background_threshold out of range - expected 1-20 → Edit config.yaml and set background_threshold to a value between 1 and 20",
    "E009": "retrospect.enabled invalid - expected true or false → Edit config.yaml and set retrospect.enabled to true or false",
    "E010": "retrospect.model invalid - expected haiku, sonnet, or opus → Edit config.yaml and set retrospect.model appropriately",
    "E011": "version field missing or invalid - expected semver → Edit config.yaml and set version to format like \"1.0.0\" or \"1.0-rc\"",
    "E012": "retrospect.filter_threshold invalid - expected number → Edit config.yaml and set retrospect.filter_threshold to a numeric value",
    "E013": "max_cmd_duration_sec invalid - expected positive integer → Edit config.yaml and set max_cmd_duration_sec to a positive integer or remove it",
}

# ============================================================================
# YAML Parsing (using only standard library)
# ============================================================================

class SimpleYAMLParser:
    """Minimal YAML parser for config.yaml validation."""

    @staticmethod
    def parse_value(value_str: str) -> Any:
        """Parse YAML value string."""
        value_str = value_str.strip()

        # Boolean
        if value_str.lower() in ('true', 'yes'):
            return True
        if value_str.lower() in ('false', 'no'):
            return False

        # Null
        if value_str.lower() in ('null', '~', ''):
            return None

        # Integer
        try:
            return int(value_str)
        except ValueError:
            pass

        # Float
        try:
            return float(value_str)
        except ValueError:
            pass

        # String (remove quotes if present)
        if value_str.startswith('"') and value_str.endswith('"'):
            return value_str[1:-1]
        if value_str.startswith("'") and value_str.endswith("'"):
            return value_str[1:-1]

        return value_str

    @staticmethod
    def parse(yaml_content: str) -> Dict[str, Any]:
        """
        Parse simplified YAML config file.
        Handles flat keys and nested keys (with indentation).
        """
        result = {}
        current_section = None

        for line in yaml_content.split('\n'):
            # Strip comments
            if '#' in line:
                line = line.split('#')[0]

            line = line.rstrip()

            # Skip empty lines
            if not line.strip():
                continue

            # Detect indentation level
            indent = len(line) - len(line.lstrip())
            content = line.lstrip()

            # Skip if no colon
            if ':' not in content:
                continue

            key, value_str = content.split(':', 1)
            key = key.strip()

            if indent == 0:
                # Top-level key
                current_section = None
                result[key] = SimpleYAMLParser.parse_value(value_str)
            else:
                # Nested key
                if current_section is None:
                    # Find parent from previous keys
                    current_section = {}
                    for prev_key in reversed(result.keys()):
                        if isinstance(result[prev_key], dict):
                            current_section = result[prev_key]
                            break

                if not isinstance(current_section, dict):
                    current_section = {}
                    # Store with parent
                    result[key] = current_section

                current_section[key] = SimpleYAMLParser.parse_value(value_str)

        # Post-process to handle nested structures
        final_result = {}
        for key, value in result.items():
            if '.' in key:
                # Handle dotted keys (not applicable here, but for future)
                final_result[key] = value
            else:
                final_result[key] = value

        return final_result


def parse_yaml_dict(yaml_content: str) -> Dict[str, Any]:
    """
    Parse YAML into nested dict structure.
    Handles both flat and nested keys.
    """
    result = {}
    stack = [result]

    for line in yaml_content.split('\n'):
        # Remove comments
        if '#' in line:
            line = line.split('#')[0]

        line_stripped = line.rstrip()

        # Skip empty lines
        if not line_stripped.strip():
            continue

        # Calculate indentation
        indent_level = (len(line_stripped) - len(line_stripped.lstrip())) // 2
        content = line_stripped.lstrip()

        # Skip lines without colon
        if ':' not in content:
            continue

        key, value_part = content.split(':', 1)
        key = key.strip()
        value_part = value_part.strip()

        # Adjust stack depth
        while len(stack) > indent_level + 1:
            stack.pop()

        # Ensure we have dict at current level
        while len(stack) < indent_level + 1:
            new_dict = {}
            if len(stack) > 0 and stack[-1]:
                # Find last dict in current level
                last_key = list(stack[-1].keys())[-1] if stack[-1] else None
                if last_key:
                    stack[-1][last_key] = new_dict
            stack.append(new_dict)

        # Parse value
        current_dict = stack[-1]
        current_dict[key] = SimpleYAMLParser.parse_value(value_part)

    return result


# ============================================================================
# Validation Schema
# ============================================================================

SCHEMA = {
    "version": {
        "required": True,
        "type": str,
        "validator": lambda v: bool(re.match(r'^\d+\.\d+(\.\d+)?(-[a-zA-Z0-9.]+)?$', str(v))),
        "error_code": "E011",
    },
    "default_model": {
        "required": True,
        "type": str,
        "validator": lambda v: v in ("haiku", "sonnet", "opus"),
        "error_code": "E004",
    },
    "max_parallel": {
        "required": True,
        "type": int,
        "validator": lambda v: isinstance(v, int) and 1 <= v <= 20,
        "error_code": "E005",
    },
    "max_retries": {
        "required": True,
        "type": int,
        "validator": lambda v: isinstance(v, int) and 0 <= v <= 10,
        "error_code": "E006",
    },
    "background_threshold": {
        "required": True,
        "type": int,
        "validator": lambda v: isinstance(v, int) and 1 <= v <= 20,
        "error_code": "E008",
    },
    "worker_max_turns": {
        "required": True,
        "type": int,
        "validator": lambda v: isinstance(v, int) and 5 <= v <= 100,
        "error_code": "E007",
    },
    "max_cmd_duration_sec": {
        "required": False,
        "type": int,
        "validator": lambda v: v is None or (isinstance(v, int) and v > 0),
        "error_code": "E013",
    },
}

NESTED_SCHEMA = {
    "retrospect.enabled": {
        "required": True,
        "type": bool,
        "validator": lambda v: isinstance(v, bool),
        "error_code": "E009",
    },
    "retrospect.filter_threshold": {
        "required": True,
        "type": (int, float),
        "validator": lambda v: isinstance(v, (int, float)),
        "error_code": "E012",
    },
    "retrospect.model": {
        "required": True,
        "type": str,
        "validator": lambda v: v in ("haiku", "sonnet", "opus"),
        "error_code": "E010",
    },
}


# ============================================================================
# Validation Functions
# ============================================================================

def get_nested_value(data: Dict, path: str) -> Tuple[bool, Any]:
    """Get nested value from dict using dot notation."""
    parts = path.split('.')
    current = data
    for part in parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            return False, None
    return True, current


def validate_config(config_path: str) -> Tuple[bool, List[str], List[str]]:
    """
    Validate config.yaml.
    Returns: (success, errors, warnings)
    """
    errors = []
    warnings = []

    # Check file exists
    if not os.path.isfile(config_path):
        errors.append(f"[E001] {ERROR_CODES['E001']}")
        return False, errors, warnings

    # Parse YAML
    try:
        with open(config_path, 'r') as f:
            yaml_content = f.read()
        config = parse_yaml_dict(yaml_content)
    except Exception as e:
        errors.append(f"[E002] {ERROR_CODES['E002']} (Details: {str(e)})")
        return False, errors, warnings

    # Validate top-level fields
    for field_name, field_spec in SCHEMA.items():
        if field_name not in config:
            if field_spec["required"]:
                errors.append(f"[E003] {ERROR_CODES['E003']} (Missing: {field_name})")
        else:
            value = config[field_name]

            # Type check (skip if value is None and optional)
            if value is not None and not field_spec.get("type") is None:
                expected_type = field_spec["type"]
                if not isinstance(value, expected_type):
                    error_code = field_spec["error_code"]
                    errors.append(f"[{error_code}] {ERROR_CODES[error_code]}")
                    continue

            # Value validation
            if not field_spec["validator"](value):
                error_code = field_spec["error_code"]
                errors.append(f"[{error_code}] {ERROR_CODES[error_code]}")

    # Validate nested fields (retrospect.*)
    if "retrospect" in config and isinstance(config["retrospect"], dict):
        retrospect = config["retrospect"]

        # Check enabled
        if "enabled" not in retrospect:
            errors.append(f"[E003] {ERROR_CODES['E003']} (Missing: retrospect.enabled)")
        else:
            if not isinstance(retrospect["enabled"], bool):
                errors.append(f"[E009] {ERROR_CODES['E009']}")

        # Check model
        if "model" not in retrospect:
            errors.append(f"[E003] {ERROR_CODES['E003']} (Missing: retrospect.model)")
        else:
            if retrospect["model"] not in ("haiku", "sonnet", "opus"):
                errors.append(f"[E010] {ERROR_CODES['E010']}")

        # Check filter_threshold
        if "filter_threshold" not in retrospect:
            errors.append(f"[E003] {ERROR_CODES['E003']} (Missing: retrospect.filter_threshold)")
        else:
            if not isinstance(retrospect["filter_threshold"], (int, float)):
                errors.append(f"[E012] {ERROR_CODES['E012']}")
    else:
        if "retrospect" not in config:
            errors.append(f"[E003] {ERROR_CODES['E003']} (Missing: retrospect section)")

    return len(errors) == 0, errors, warnings


def print_validation_results(success: bool, errors: List[str], warnings: List[str]):
    """Print validation results."""
    print("=" * 70)
    print("CONFIG.YAML VALIDATION RESULTS")
    print("=" * 70)
    print()

    if success:
        print("✓ Configuration is valid")
        print()
    else:
        print("✗ Configuration has errors:")
        print()
        for error in errors:
            print(f"  {error}")
        print()

    if warnings:
        print("Warnings:")
        for warning in warnings:
            print(f"  ⚠ {warning}")
        print()


# ============================================================================
# Main
# ============================================================================

def main():
    """Main entry point."""
    # Determine config path
    if len(sys.argv) > 1:
        config_path = sys.argv[1]
    else:
        # Default to project root config.yaml
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(script_dir)
        config_path = os.path.join(project_root, "config.yaml")

    # Validate
    success, errors, warnings = validate_config(config_path)

    # Print results
    print_validation_results(success, errors, warnings)

    # Exit code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
