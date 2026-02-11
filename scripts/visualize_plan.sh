#!/bin/bash
# scripts/visualize_plan.sh
# Parses plan.md and generates a Mermaid diagram showing task dependencies and execution waves.
# Usage: bash scripts/visualize_plan.sh [plan.md path]
# Default: Latest cmd's plan.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse plan.md path (default to latest cmd)
PLAN_PATH="${1:-$(ls -t "$PROJECT_ROOT"/work/cmd_*/plan.md 2>/dev/null | head -n1)}"

# Validate plan exists
if [[ ! -f "$PLAN_PATH" ]]; then
  echo "Error: Plan file not found: $PLAN_PATH" >&2
  exit 1
fi

# Extract task information from Tasks table
declare -A task_names
declare -A task_deps
declare -a task_order

# Parse the Tasks table (between "## Tasks" and "## Execution Order")
in_table=0
while IFS= read -r line; do
  # Start parsing when we hit "## Tasks"
  if [[ "$line" == "## Tasks" ]]; then
    in_table=1
    continue
  fi

  # Stop parsing when we hit "## Execution Order"
  if [[ "$line" == "## Execution Order" ]]; then
    in_table=0
    break
  fi

  # Skip non-table lines and header separator
  if [[ ! "$line" =~ ^\| ]] || [[ "$line" =~ ^\|\s*-+ ]]; then
    continue
  fi

  # Parse table row: | # | Task | ... | Depends On | ...
  task_num=$(echo "$line" | cut -d'|' -f2 | xargs)

  # Skip if not a number (header row)
  if ! [[ "$task_num" =~ ^[0-9]+$ ]]; then
    continue
  fi

  task_name=$(echo "$line" | cut -d'|' -f3 | xargs)
  depends_on=$(echo "$line" | cut -d'|' -f6 | xargs)

  # Store task info
  task_order+=("$task_num")
  task_names["$task_num"]="$task_name"
  task_deps["$task_num"]="$depends_on"
done < "$PLAN_PATH"

# Parse Execution Order section to build Wave groupings
declare -A wave_tasks

while IFS= read -r line; do
  # Look for lines starting with "- Wave"
  if [[ "$line" =~ ^-\ Wave\ ([0-9]+) ]]; then
    wave_num="${BASH_REMATCH[1]}"

    # Extract task list from the rest of the line
    # Remove the leading "- Wave N (...): " part
    tasks_part="${line#*: }"

    # Clean up "Tasks" or "Task" prefix and get just the numbers
    tasks_part="${tasks_part#Task[s] }"

    # Store the task list for this wave
    wave_tasks["$wave_num"]="$tasks_part"
  fi
done < "$PLAN_PATH"

# Start generating Mermaid output
echo "graph TD"
echo ""

# Generate subgraphs by Wave if we found any
if [[ ${#wave_tasks[@]} -gt 0 ]]; then
  for wave in $(printf '%s\n' "${!wave_tasks[@]}" | sort -n); do
    task_list="${wave_tasks[$wave]}"

    echo "  subgraph \"Wave $wave\""

    # Parse task numbers (handle comma-separated with optional spaces)
    # Convert "1, 2, 3, 4" to "1 2 3 4"
    task_list="${task_list//,/ }"

    for task_num in $task_list; do
      task_num=$(echo "$task_num" | xargs)  # trim whitespace
      if [[ -v "task_names[$task_num]" ]]; then
        task_label="${task_names[$task_num]}"
        # Truncate long task names for readability
        if [[ ${#task_label} -gt 50 ]]; then
          task_label="${task_label:0:47}..."
        fi
        echo "    T$task_num[\"Task $task_num: $task_label\"]"
      fi
    done

    echo "  end"
    echo ""
  done
else
  # Fallback: create nodes without subgraphs
  for task_num in "${task_order[@]}"; do
    task_label="${task_names[$task_num]}"
    # Truncate long task names
    if [[ ${#task_label} -gt 50 ]]; then
      task_label="${task_label:0:47}..."
    fi
    echo "  T$task_num[\"Task $task_num: $task_label\"]"
  done
  echo ""
fi

# Generate dependency arrows
for task_num in "${task_order[@]}"; do
  depends="${task_deps[$task_num]}"

  # Skip if no dependencies (represented as "-" or empty)
  if [[ "$depends" == "-" ]] || [[ -z "$depends" ]]; then
    continue
  fi

  # Parse dependencies: could be single number or comma-separated list
  # Convert "1, 2" to "1 2"
  depends="${depends//,/ }"

  for dep in $depends; do
    dep=$(echo "$dep" | xargs)  # trim whitespace
    # Only add arrow if dep is a number
    if [[ "$dep" =~ ^[0-9]+$ ]]; then
      echo "  T$dep --> T$task_num"
    fi
  done
done
