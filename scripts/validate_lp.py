#!/usr/bin/env python3
# scripts/validate_lp.py
# Validates LP (Learned Preference) entities for format correctness.
# Usage:
#   echo '{"name": "lp:vocabulary:simplicity", ...}' | scripts/validate_lp.py
#   scripts/validate_lp.py --file lp_export.json
#   scripts/validate_lp.py --candidate "lp:defaults:typescript" "[what] ... [evidence] ... [scope] ... [action] ..."
# Exit code: 0 = valid, 1 = validation errors found

import sys
import json
import re
import argparse
from typing import Dict, List, Tuple, Optional

# Allowed cluster names (from result_8.md Section 1, with Mutation 2 rename)
ALLOWED_CLUSTERS = {
    "vocabulary",   # How user defines ambiguous terms
    "defaults",     # Values user repeatedly specifies
    "avoid",        # Things user consistently rejects
    "judgment",     # Tradeoff decision patterns
    "communication",  # Interaction style preferences
    "task_scope"    # Renamed from "implicit" per Mutation 2
}

# Privacy forbidden keywords (from LP design Forbidden Categories - 8 items)
PRIVACY_FORBIDDEN_KEYWORDS = [
    # Personality/emotional/cognitive profiling
    "personality", "emotional", "cognitive", "psychological",
    "iq", "eq", "temperament", "stress response",
    # Big Five
    "extraversion", "neuroticism", "conscientiousness", "agreeableness", "openness",
    # Mood/emotional states
    "mood", "anxiety", "frustration", "anger", "excitement",
    # Work patterns (time-based, productivity)
    "productivity metric", "output rate", "work speed",
    "work schedule", "working hours", "time management",
    # Health
    "health indicator", "sleep", "fatigue", "wellness",
    # Political/social
    "political", "social views", "political views", "ideology",
    # Relationship
    "relationship", "team dynamics", "interpersonal",
    # Financial/compensation
    "financial", "compensation", "salary", "income", "payment",
]

# Quality guardrail forbidden action patterns (from result_8.md Section 5)
QUALITY_FORBIDDEN_ACTIONS = [
    "skip tests", "skip test", "ignore errors", "ignore error",
    "reduce security", "omit validation", "incomplete implementation",
    "accept data loss", "no error handling", "skip edge case",
    "never confirm destructive", "always use", "ignore performance"
]

# Observation length constraints
MIN_OBSERVATION_LENGTH = 100
MAX_OBSERVATION_LENGTH = 500


def validate_naming_convention(name: str) -> Tuple[bool, str]:
    """
    Validate LP entity naming convention: lp:{cluster}:{topic}
    Internal entities (lp:_internal:*) are allowed.
    Topic must be snake_case.

    Returns: (is_valid, error_message)
    """
    # Check basic format
    if not name.startswith("lp:"):
        return False, f"Entity name must start with 'lp:' (got: {name})"

    parts = name.split(":")
    if len(parts) != 3:
        return False, f"Entity name must follow 'lp:{{cluster}}:{{topic}}' format (got: {name})"

    _, cluster, topic = parts

    # Allow internal entities
    if cluster == "_internal":
        return True, ""

    # Check cluster is allowed
    if cluster not in ALLOWED_CLUSTERS:
        return False, f"Cluster '{cluster}' is not allowed. Must be one of: {', '.join(sorted(ALLOWED_CLUSTERS))}"

    # Check topic is snake_case (lowercase, underscores, alphanumeric)
    if not re.match(r'^[a-z0-9_]+$', topic):
        return False, f"Topic '{topic}' must be snake_case (lowercase, underscores, alphanumeric only)"

    # Check topic doesn't start or end with underscore
    if topic.startswith("_") or topic.endswith("_"):
        return False, f"Topic '{topic}' should not start or end with underscore"

    # Check topic is not empty
    if not topic:
        return False, "Topic cannot be empty"

    return True, ""


def validate_observation_format(observation: str, is_internal: bool = False) -> Tuple[bool, str]:
    """
    Validate 4-element observation format:
    [what] ... [evidence] ... [scope] ... [action] ...

    For internal entities, the format is different (e.g., signal_log, metadata).
    Internal entities are exempt from strict format validation.

    Returns: (is_valid, error_message)
    """
    # Internal entities have different formats, skip strict validation
    if is_internal:
        return True, ""

    required_elements = ["[what]", "[evidence]", "[scope]", "[action]"]
    missing_elements = []

    for element in required_elements:
        if element not in observation:
            missing_elements.append(element)

    if missing_elements:
        return False, f"Observation missing required elements: {', '.join(missing_elements)}"

    # Check element order (what -> evidence -> scope -> action)
    what_pos = observation.find("[what]")
    evidence_pos = observation.find("[evidence]")
    scope_pos = observation.find("[scope]")
    action_pos = observation.find("[action]")

    if not (what_pos < evidence_pos < scope_pos < action_pos):
        return False, "Observation elements must appear in order: [what] [evidence] [scope] [action]"

    # Check each section has content (not just the tag)
    what_content = observation[what_pos + 6:evidence_pos].strip()
    evidence_content = observation[evidence_pos + 11:scope_pos].strip()
    scope_content = observation[scope_pos + 7:action_pos].strip()
    action_content = observation[action_pos + 8:].strip()

    if not what_content:
        return False, "[what] section is empty"
    if not evidence_content:
        return False, "[evidence] section is empty"
    if not scope_content:
        return False, "[scope] section is empty"
    if not action_content:
        return False, "[action] section is empty"

    return True, ""


def validate_entity_type(entity_type: str, name: str) -> Tuple[bool, str]:
    """
    Validate entity type is correct for LP entities.

    Returns: (is_valid, error_message)
    """
    if name.startswith("lp:_internal:"):
        if entity_type != "lp_internal":
            return False, f"Internal LP entities must have entityType 'lp_internal' (got: {entity_type})"
    else:
        if entity_type != "learned_preference":
            return False, f"LP entities must have entityType 'learned_preference' (got: {entity_type})"

    return True, ""


def validate_privacy_safeguards(observation: str) -> Tuple[bool, List[str]]:
    """
    Check observation does not violate privacy safeguards.
    From result_13.md: no personality traits, emotional patterns, cognitive abilities.

    Returns: (is_valid, list_of_violations)
    """
    violations = []
    observation_lower = observation.lower()

    # Check for forbidden keywords
    for keyword in PRIVACY_FORBIDDEN_KEYWORDS:
        if keyword.lower() in observation_lower:
            violations.append(f"Privacy violation: contains forbidden keyword '{keyword}'")

    # Check scope doesn't reference personal identity (heuristic check)
    scope_match = re.search(r'\[scope\]\s*([^\[]+)', observation)
    if scope_match:
        scope_content = scope_match.group(1).strip().lower()
        identity_keywords = ["user's", "user is", "my", "personal"]
        for keyword in identity_keywords:
            if keyword in scope_content:
                violations.append(f"Privacy violation: scope references personal identity ('{keyword}')")

    return len(violations) == 0, violations


def validate_quality_guardrails(observation: str) -> Tuple[bool, List[str]]:
    """
    Check observation does not violate quality guardrails.
    From result_8.md Section 5: action must not reference absolute quality aspects.

    Returns: (is_valid, list_of_violations)
    """
    violations = []

    # Extract action section
    action_match = re.search(r'\[action\]\s*(.+)', observation)
    if not action_match:
        # This should be caught by format validation, but be defensive
        return True, []

    action_content = action_match.group(1).strip().lower()

    # Check for forbidden action patterns
    for pattern in QUALITY_FORBIDDEN_ACTIONS:
        if pattern.lower() in action_content:
            violations.append(f"Quality violation: action contains forbidden pattern '{pattern}'")

    return len(violations) == 0, violations


def validate_observation_length(observation: str) -> Tuple[bool, str]:
    """
    Check observation length is within acceptable range (100-500 characters).

    Returns: (is_valid, error_message)
    """
    length = len(observation)

    if length < MIN_OBSERVATION_LENGTH:
        return False, f"Observation too short ({length} chars, minimum {MIN_OBSERVATION_LENGTH})"

    if length > MAX_OBSERVATION_LENGTH:
        return False, f"Observation too long ({length} chars, maximum {MAX_OBSERVATION_LENGTH})"

    return True, ""


def validate_lp_entity(entity: Dict) -> Tuple[bool, List[str]]:
    """
    Validate a single LP entity for all format and quality constraints.

    Returns: (is_valid, list_of_errors)
    """
    errors = []

    # Required fields
    if "name" not in entity:
        errors.append("Missing required field: name")
        return False, errors

    if "entityType" not in entity:
        errors.append("Missing required field: entityType")

    if "observations" not in entity:
        errors.append("Missing required field: observations")
        return False, errors

    name = entity["name"]
    entity_type = entity.get("entityType", "")
    observations = entity["observations"]

    # Check if this is an internal entity
    is_internal = name.startswith("lp:_internal:")

    # Validate naming convention
    valid, error = validate_naming_convention(name)
    if not valid:
        errors.append(f"Naming: {error}")

    # Validate entity type
    valid, error = validate_entity_type(entity_type, name)
    if not valid:
        errors.append(f"Entity type: {error}")

    # Validate observations
    if not isinstance(observations, list):
        errors.append("Observations must be an array")
        return False, errors

    if len(observations) == 0:
        errors.append("Observations array is empty (must have at least 1)")

    for i, obs in enumerate(observations):
        if not isinstance(obs, str):
            errors.append(f"Observation {i+1}: must be a string")
            continue

        # Internal entities have different format, skip most validations
        if is_internal:
            continue

        # Validate format
        valid, error = validate_observation_format(obs, is_internal)
        if not valid:
            errors.append(f"Observation {i+1} format: {error}")

        # Validate length
        valid, error = validate_observation_length(obs)
        if not valid:
            errors.append(f"Observation {i+1} length: {error}")

        # Validate privacy
        valid, violations = validate_privacy_safeguards(obs)
        if not valid:
            for violation in violations:
                errors.append(f"Observation {i+1} privacy: {violation}")

        # Validate quality
        valid, violations = validate_quality_guardrails(obs)
        if not valid:
            for violation in violations:
                errors.append(f"Observation {i+1} quality: {violation}")

    return len(errors) == 0, errors


def validate_from_stdin() -> int:
    """
    Validate LP entity from stdin (JSON input).

    Returns: exit code (0 = valid, 1 = invalid)
    """
    try:
        data = json.loads(sys.stdin.read())
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON input: {e}", file=sys.stderr)
        return 1

    valid, errors = validate_lp_entity(data)

    if valid:
        print(f"✓ VALID: {data['name']}")
        return 0
    else:
        print(f"✗ INVALID: {data['name']}", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1


def validate_from_file(filepath: str) -> int:
    """
    Validate LP entities from a JSON file (array of entities or single entity).

    Returns: exit code (0 = all valid, 1 = some invalid)
    """
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: File not found: {filepath}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in file: {e}", file=sys.stderr)
        return 1

    # Handle both single entity and array of entities
    if isinstance(data, list):
        entities = data
    else:
        entities = [data]

    total_valid = 0
    total_invalid = 0

    for entity in entities:
        if not isinstance(entity, dict):
            print(f"✗ INVALID: Entity is not a JSON object", file=sys.stderr)
            total_invalid += 1
            continue

        name = entity.get("name", "<unnamed>")
        valid, errors = validate_lp_entity(entity)

        if valid:
            print(f"✓ VALID: {name}")
            total_valid += 1
        else:
            print(f"✗ INVALID: {name}", file=sys.stderr)
            for error in errors:
                print(f"  - {error}", file=sys.stderr)
            total_invalid += 1

    print(f"\n=== SUMMARY ===")
    print(f"Valid: {total_valid}, Invalid: {total_invalid}")

    return 0 if total_invalid == 0 else 1


def validate_candidate(name: str, observation: str) -> int:
    """
    Validate a single LP candidate (name + observation).

    Returns: exit code (0 = valid, 1 = invalid)
    """
    entity = {
        "name": name,
        "entityType": "lp_internal" if name.startswith("lp:_internal:") else "learned_preference",
        "observations": [observation]
    }

    valid, errors = validate_lp_entity(entity)

    if valid:
        print(f"✓ VALID: {name}")
        return 0
    else:
        print(f"✗ INVALID: {name}", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1


def main():
    parser = argparse.ArgumentParser(
        description="Validate LP (Learned Preference) entities for format correctness",
        epilog="""
Examples:
  # Validate from stdin
  echo '{"name": "lp:vocabulary:simplicity", ...}' | scripts/validate_lp.py

  # Validate from file
  scripts/validate_lp.py --file lp_export.json

  # Validate a candidate
  scripts/validate_lp.py --candidate "lp:defaults:typescript" "[what] ... [evidence] ... [scope] ... [action] ..."
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "--file",
        help="JSON file containing LP entities (array or single object)"
    )

    parser.add_argument(
        "--candidate",
        nargs=2,
        metavar=("NAME", "OBSERVATION"),
        help="Validate a single LP candidate (name and observation)"
    )

    args = parser.parse_args()

    # Determine input mode
    if args.file:
        return validate_from_file(args.file)
    elif args.candidate:
        name, observation = args.candidate
        return validate_candidate(name, observation)
    else:
        # Default: read from stdin
        return validate_from_stdin()


if __name__ == "__main__":
    sys.exit(main())
