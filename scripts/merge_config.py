#!/usr/bin/env python3
"""
scripts/merge_config.py
Merge config.yaml with local/config.yaml overrides.
Output merged result to work/cmd_NNN/ directory.

Usage: python3 scripts/merge_config.py <work_dir>
Example: python3 scripts/merge_config.py work/cmd_042

Exit codes:
  0 = success
  1 = fatal error (base config missing, parse error)
  2 = success with validation warnings (warnings printed to stderr)
"""

import sys
import os
import copy
import stat

# --- YAML handling (conditional import) ---
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False


# ---------------------------------------------------------------------------
# Deep merge
# ---------------------------------------------------------------------------

def deep_merge(base, overlay):
    """
    Recursively merge overlay into base (overlay wins on conflict).
    - Dicts: deep-merged
    - Lists: overlay replaces base entirely
    - Scalars: overlay wins
    - None value in overlay: clears the key (sets to None)
    Returns new dict (does not mutate base).
    """
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


# ---------------------------------------------------------------------------
# Dot-notation expansion
# ---------------------------------------------------------------------------

def expand_dot_notation(data):
    """
    Expand dot-notation keys into nested dicts.
    'retrospect.memory.max_candidates_per_cmd: 10'
    becomes {'retrospect': {'memory': {'max_candidates_per_cmd': 10}}}

    Non-dot keys are passed through unchanged. Mixed usage is supported.
    Only operates on top-level keys.
    """
    expanded = {}
    for key, value in data.items():
        if '.' in str(key):
            parts = str(key).split('.')
            current = expanded
            for part in parts[:-1]:
                if part not in current or not isinstance(current[part], dict):
                    if part in current and not isinstance(current[part], dict):
                        print(
                            f"WARNING: dot-notation '{key}' overwrites non-dict "
                            f"value at '{part}' (was: {current[part]})",
                            file=sys.stderr,
                        )
                    current[part] = {}
                current = current[part]
            current[parts[-1]] = value
        else:
            expanded[key] = value
    return expanded


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

def levenshtein(s1, s2):
    """Compute Levenshtein distance between two strings."""
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    prev_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        curr_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = prev_row[j + 1] + 1
            deletions = curr_row[j] + 1
            substitutions = prev_row[j] + (c1 != c2)
            curr_row.append(min(insertions, deletions, substitutions))
        prev_row = curr_row
    return prev_row[-1]


def validate_keys_recursive(base, overlay, path=''):
    """
    Recursively check that all keys in overlay exist in base.
    Returns list of warning strings.
    """
    warnings = []
    base_keys = set(base.keys()) if isinstance(base, dict) else set()

    if not isinstance(overlay, dict):
        return warnings

    for key in overlay:
        full_path = f'{path}.{key}' if path else key
        if key not in base_keys:
            candidates = []
            for known in base_keys:
                dist = levenshtein(str(key), str(known))
                if dist <= 2:
                    candidates.append(known)
            if candidates:
                suggestions = ', '.join(candidates)
                warnings.append(
                    f"Unknown key '{full_path}'. Did you mean: {suggestions}?"
                )
            else:
                warnings.append(f"Unknown key '{full_path}' (not in base config)")
        elif isinstance(base.get(key), dict) and isinstance(overlay[key], dict):
            warnings.extend(
                validate_keys_recursive(base[key], overlay[key], full_path)
            )

    return warnings


def validate_bounds(merged):
    """
    Check value bounds for known numeric/enum fields.
    Returns list of warning strings.
    """
    warnings = []

    model = merged.get('default_model')
    if model and model not in ('haiku', 'sonnet', 'opus'):
        warnings.append(
            f"default_model '{model}' not in (haiku, sonnet, opus)"
        )

    mp = merged.get('max_parallel')
    if mp is not None and (not isinstance(mp, int) or mp < 1 or mp > 20):
        warnings.append(f"max_parallel {mp} out of range (1-20)")

    wmt = merged.get('worker_max_turns')
    if wmt is not None and (not isinstance(wmt, int) or wmt < 5 or wmt > 100):
        warnings.append(f"worker_max_turns {wmt} out of range (5-100)")

    mr = merged.get('max_retries')
    if mr is not None and (not isinstance(mr, int) or mr < 0 or mr > 10):
        warnings.append(f"max_retries {mr} out of range (0-10)")

    retro = merged.get('retrospect', {})
    if isinstance(retro, dict):
        rm = retro.get('model')
        if rm and rm not in ('haiku', 'sonnet', 'opus'):
            warnings.append(
                f"retrospect.model '{rm}' not in (haiku, sonnet, opus)"
            )

    return warnings


# ---------------------------------------------------------------------------
# YAML config merge
# ---------------------------------------------------------------------------

def merge_yaml_configs(project_root, work_dir):
    """
    Merge config.yaml + local/config.yaml -> work_dir/config.yaml.
    Injects _merged_from canary field into output.
    Returns (success: bool, exit_code: int).
    """
    base_path = os.path.join(project_root, 'config.yaml')
    local_path = os.path.join(project_root, 'local', 'config.yaml')
    out_path = os.path.join(work_dir, 'config.yaml')

    # Base config must exist
    if not os.path.exists(base_path):
        print('[E001] config.yaml not found → Run: bash scripts/setup.sh', file=sys.stderr)
        return False, 1

    # No local override: copy base verbatim with canary
    if not os.path.exists(local_path):
        with open(base_path, 'r') as f:
            content = f.read()
        with open(out_path, 'w') as f:
            f.write('# Config for this cmd session. Do not edit.\n')
            f.write('# _merged_from: base\n')
            f.write(content)
        _make_readonly(out_path)
        return True, 0

    # PyYAML not available but local exists: copy base with warning
    if not HAS_YAML:
        print(
            '[E023] PyYAML not installed, local config ignored → Install with: pip3 install pyyaml',
            file=sys.stderr,
        )
        with open(base_path, 'r') as f:
            content = f.read()
        with open(out_path, 'w') as f:
            f.write('# Config for this cmd session. Do not edit.\n')
            f.write('# _merged_from: base (local ignored, PyYAML missing)\n')
            f.write(content)
        _make_readonly(out_path)
        return True, 0

    # Load both files
    try:
        with open(base_path, 'r') as f:
            base = yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        print(f'[E002] config.yaml parse error - invalid YAML → Check YAML syntax with a YAML validator or PyYAML (Details: {e})', file=sys.stderr)
        return False, 1

    try:
        with open(local_path, 'r') as f:
            local = yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        print(f'[E020] local/config.yaml parse error - invalid YAML → Check YAML syntax in local/config.yaml (Details: {e})', file=sys.stderr)
        return False, 1

    if not isinstance(local, dict):
        print(
            f'[E022] local/config.yaml must be YAML mapping - not list or scalar → Edit local/config.yaml to use key-value format',
            file=sys.stderr,
        )
        return False, 1

    # Expand dot-notation in overlay
    local = expand_dot_notation(local)

    # Validate: unknown keys (typo detection)
    has_warnings = False
    key_warnings = validate_keys_recursive(base, local)
    for w in key_warnings:
        print(f'[E021] local/config.yaml has unknown keys → Review warnings from merge_config.py for typos or invalid keys ({w})', file=sys.stderr)
        has_warnings = True

    # Deep merge
    merged = deep_merge(base, local)

    # Inject canary (Fix 2)
    merged['_merged_from'] = 'local'

    # Validate: bounds checking
    bounds_warnings = validate_bounds(merged)
    for w in bounds_warnings:
        print(f'WARNING: {w}', file=sys.stderr)
        has_warnings = True

    # Write merged config
    with open(out_path, 'w') as f:
        f.write('# Merged config: config.yaml + local/config.yaml\n')
        f.write('# Generated at cmd start. Do not edit.\n')
        yaml.dump(
            merged, f,
            default_flow_style=False,
            allow_unicode=True,
            sort_keys=False,
        )

    _make_readonly(out_path)

    exit_code = 2 if has_warnings else 0
    return True, exit_code


# ---------------------------------------------------------------------------
# Permission-config.yaml merge (reference copy to work dir)
# ---------------------------------------------------------------------------

# Security floor: these commands MUST remain in always_ask/subcommand_ask.
SECURITY_FLOOR_ALWAYS_ASK = {
    'sudo', 'su', 'rm', 'rmdir',
}
SECURITY_FLOOR_SUBCOMMAND_ASK = {
    'git:push', 'git:reset:--hard', 'gh:pr:merge',
}

# FROZEN KEYS: cannot be overridden by local config at all (Fix 1).
# The interpreters key defines which commands get script-containment
# treatment. Allowing local override enables dangerous_flags clearing
# (bypasses -c rejection) and new-interpreter injection (bypasses
# always_ask entirely).
FROZEN_KEYS = {'interpreters'}


def _safe_set_from(value):
    """
    Convert a value to a set safely (Fix 3: null safety).
    Returns empty set for None or non-iterable types.
    """
    if value is None:
        return set()
    if isinstance(value, list):
        return set(value)
    if isinstance(value, set):
        return value
    print(
        f"WARNING: expected array, got {type(value).__name__}. Treating as empty.",
        file=sys.stderr,
    )
    return set()


def merge_permission_configs(base, local):
    """
    Merge permission-config.yaml with security-aware semantics:
    - interpreters: FROZEN (local override skipped entirely) (Fix 1)
    - always_ask: UNION (additive only) + security floor + null safety (Fix 3)
    - subcommand_ask: UNION (additive only) + security floor + null safety (Fix 3)
    - allowed_dirs_extra: UNION (additive only) + null safety (Fix 3)
    """
    result = copy.deepcopy(base)

    # Check for frozen keys (Fix 1)
    for key in FROZEN_KEYS:
        if key in local:
            print(
                f"[E028] frozen key override blocked - interpreters cannot be overridden → Remove 'interpreters' key from local/hooks/permission-config.yaml",
                file=sys.stderr,
            )

    # Security arrays: UNION only (additive) with null safety (Fix 3)
    for array_key in ['always_ask', 'subcommand_ask', 'allowed_dirs_extra']:
        if array_key in local:
            existing = _safe_set_from(result.get(array_key, []))
            override = _safe_set_from(local[array_key])
            existing |= override
            result[array_key] = sorted(existing)

    # Enforce security floor
    always_set = _safe_set_from(result.get('always_ask', []))
    always_set |= SECURITY_FLOOR_ALWAYS_ASK
    result['always_ask'] = sorted(always_set)

    sub_set = _safe_set_from(result.get('subcommand_ask', []))
    sub_set |= SECURITY_FLOOR_SUBCOMMAND_ASK
    result['subcommand_ask'] = sorted(sub_set)

    # Inject canary (Fix 2)
    if local:
        result['_merged_from'] = 'local'
    else:
        result['_merged_from'] = 'base'

    return result


def merge_permission_configs_yaml(project_root, work_dir):
    """
    Merge permission-config.yaml + local/hooks/permission-config.yaml
    -> work_dir/permission-config.yaml (reference snapshot).

    Note: The hook reads from local/hooks/ directly at runtime.
    This snapshot is for reproducibility/debugging only.
    """
    base_path = os.path.join(
        project_root, '.claude', 'hooks', 'permission-config.yaml'
    )
    local_path = os.path.join(
        project_root, 'local', 'hooks', 'permission-config.yaml'
    )
    out_path = os.path.join(work_dir, 'permission-config.yaml')

    # Base not found: not fatal (hook has hardcoded defaults)
    if not os.path.exists(base_path):
        print(
            f'WARNING: {base_path} not found, skipping permission merge',
            file=sys.stderr,
        )
        return True, 0

    # PyYAML not available: skip permission merge with warning
    if not HAS_YAML:
        print(
            'WARNING: PyYAML not installed. Permission config merge skipped.',
            file=sys.stderr,
        )
        return True, 0

    # No local override: copy base with canary
    if not os.path.exists(local_path):
        with open(base_path, 'r') as f:
            base = yaml.safe_load(f) or {}
        base['_merged_from'] = 'base'
        with open(out_path, 'w') as f:
            yaml.dump(base, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        _make_readonly(out_path)
        return True, 0

    # Load and merge
    try:
        with open(base_path, 'r') as f:
            base = yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        print(f'[E025] permission-config.yaml parse error → Check YAML syntax in .claude/hooks/permission-config.yaml (Details: {e})', file=sys.stderr)
        return False, 1

    try:
        with open(local_path, 'r') as f:
            local = yaml.safe_load(f) or {}
    except yaml.YAMLError as e:
        print(f'[E026] local permission-config.yaml parse error → Check YAML syntax in local/hooks/permission-config.yaml (Details: {e})', file=sys.stderr)
        return False, 1

    if not isinstance(local, dict):
        print(
            f'[E027] permission-config.yaml must be YAML mapping → Edit permission-config.yaml to use key-value format',
            file=sys.stderr,
        )
        base['_merged_from'] = 'base'
        with open(out_path, 'w') as f:
            yaml.dump(base, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        _make_readonly(out_path)
        return True, 0

    merged = merge_permission_configs(base, local)

    with open(out_path, 'w') as f:
        yaml.dump(merged, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

    _make_readonly(out_path)
    return True, 0


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_readonly(path):
    """Set file to read-only (chmod 444). Immutable for the cmd session."""
    try:
        os.chmod(path, stat.S_IRUSR | stat.S_IRGRP | stat.S_IROTH)
    except OSError:
        pass  # Best-effort: some filesystems don't support chmod


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print(
            'Usage: python3 scripts/merge_config.py <work_dir>',
            file=sys.stderr,
        )
        sys.exit(1)

    work_dir = sys.argv[1]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    # Ensure work_dir exists
    if not os.path.isdir(work_dir):
        work_dir = os.path.join(project_root, work_dir)
        if not os.path.isdir(work_dir):
            print(f'[E060] work directory not found → Work directory should be created automatically, check file system permissions (Path: {work_dir})', file=sys.stderr)
            sys.exit(1)

    max_exit = 0

    # Merge config.yaml
    ok, code = merge_yaml_configs(project_root, work_dir)
    if not ok:
        sys.exit(1)
    max_exit = max(max_exit, code)

    # Merge permission-config.yaml (reference snapshot)
    ok, code = merge_permission_configs_yaml(project_root, work_dir)
    if not ok:
        sys.exit(1)
    max_exit = max(max_exit, code)

    # Print merged config path to stdout (for callers to capture)
    print(os.path.join(work_dir, 'config.yaml'))

    sys.exit(max_exit)


if __name__ == '__main__':
    main()
