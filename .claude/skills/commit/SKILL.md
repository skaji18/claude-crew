---
name: commit
description: "Analyze staged changes, generate Conventional Commits message and CHANGELOG entry, then commit."
user-invocable: true
---

# Claude Skill: commit

## Overview

Analyze git diff, generate a Conventional Commits message and Keep a Changelog entry, then commit — all in one step.

## Invocation

```bash
/commit [options]
```

Options:
- `--dry-run` — Preview generated message and CHANGELOG entry without committing
- `--no-changelog` — Skip CHANGELOG.md update

## Workflow

When user invokes `/commit [options]`:

### 1. Parse Options

- Check for `--dry-run` and `--no-changelog` flags in arguments.

### 2. Check State

- Run `git status` to check for changes.
- If no changes at all (staged or unstaged): report "Nothing to commit" and stop.
- If there are unstaged changes but nothing staged: stage all changes with `git add`, but **exclude** sensitive files (`.env`, `*.key`, `*.pem`, `credentials*`, `*secret*`). Report what was staged.
- If there are already staged changes: use them as-is. If there are also unstaged changes, mention them but do not stage them.

### 3. Analyze Diff

- Run `git diff --cached` to get the full staged diff.
- Run `git log --oneline -5` to see recent commit style for reference.
- Read the diff content carefully to understand what changed.

### 4. Generate Commit Message

Format: [Conventional Commits](https://www.conventionalcommits.org/)

```
type(scope): description

body (optional, only if changes need explanation)

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Type selection rules:**

| Change | type |
|--------|------|
| New file, new feature | `feat` |
| Enhancement to existing feature | `feat` |
| Bug fix | `fix` |
| Code restructure, no behavior change | `refactor` |
| Documentation only | `docs` |
| Version bump, config, CI, deps | `chore` |

**Scope:** Target directory or module (e.g., `templates`, `scripts`, `docs`). Omit if changes span multiple unrelated areas.

**Description:** English, lowercase, imperative mood, max 50 characters.

**Body:** Only when the "why" isn't obvious from the description. Wrap at 72 characters.

### 5. Generate CHANGELOG Entry (skip if `--no-changelog`)

- Read `CHANGELOG.md`.
- Add entry under `## [Unreleased]` section.
- If `## [Unreleased]` has no content yet, add the appropriate category subheader.
- If the needed category subheader (`### Added`, `### Changed`, `### Fixed`, etc.) doesn't exist under Unreleased, create it.

**Category mapping:**

| type | Category |
|------|----------|
| feat (new) | Added |
| feat (change) | Changed |
| fix | Fixed |
| refactor | Changed |
| docs | Changed |
| chore | Changed |

**Entry format:** `- **{target}** — {description}`

### 6. Execute (skip if `--dry-run`)

- Edit `CHANGELOG.md` with the new entry using the Edit tool.
- Run `git add CHANGELOG.md` to include it in the commit.
- Run `git commit` with the message passed via HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
type(scope): description

body

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 7. Report Result

- If `--dry-run`: show the generated commit message and CHANGELOG entry, then stop.
- Otherwise: show the commit hash and message summary.

## Dry Run Output Format

```
## Commit Message (preview)

type(scope): description

body

Co-Authored-By: Claude <noreply@anthropic.com>

## CHANGELOG Entry (preview)

### Category
- **target** — description

---
Dry run complete. No changes were made.
```

## Error Handling

- **No changes**: Report and stop. Do not create an empty commit.
- **CHANGELOG.md not found**: Skip CHANGELOG update (same as `--no-changelog`) and warn.
- **Commit hook failure**: Report the hook output. Do NOT retry with `--no-verify`. Let the user decide.
