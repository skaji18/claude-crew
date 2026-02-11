#!/bin/bash
# scripts/stats.sh
# Parses execution_log.yaml files and outputs statistics about task execution.
# Usage: bash scripts/stats.sh [work_dir]
# Default work_dir: work/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="${1:-$PROJECT_ROOT/work}"

# Validate work directory exists
if [[ ! -d "$WORK_DIR" ]]; then
  echo "Error: work directory not found: $WORK_DIR" >&2
  exit 1
fi

# Find all execution logs
EXEC_LOGS=$(find "$WORK_DIR" -type f -name "execution_log.yaml" 2>/dev/null | sort)

if [[ -z "$EXEC_LOGS" ]]; then
  echo "No execution_log.yaml files found in $WORK_DIR" >&2
  exit 1
fi

# Create temp file for aggregated task data
TEMP_TASKS=$(mktemp)
TEMP_CMD_INFO=$(mktemp)
trap 'rm -f "$TEMP_TASKS" "$TEMP_CMD_INFO"' EXIT

total_cmds=0

# Process each execution log
for log_file in $EXEC_LOGS; do
  ((total_cmds++)) || true

  # Extract cmd_id
  cmd_id=$(grep "^cmd_id:" "$log_file" | head -1 | sed 's/cmd_id: *//' || echo "unknown")

  # Extract cmd-level timestamps for cmd duration
  cmd_started=$(grep "^started:" "$log_file" | head -1 | sed 's/started: *"\(.*\)"/\1/' || echo "")
  cmd_finished=$(grep "^finished:" "$log_file" | head -1 | sed 's/finished: *"\(.*\)"/\1/' || echo "")

  # Calculate cmd duration if both timestamps present
  cmd_dur=""
  if [[ -n "$cmd_started" && -n "$cmd_finished" ]]; then
    cmd_start_sec=$(date -d "$cmd_started" +%s 2>/dev/null || echo "")
    cmd_finish_sec=$(date -d "$cmd_finished" +%s 2>/dev/null || echo "")
    if [[ -n "$cmd_start_sec" && -n "$cmd_finish_sec" ]]; then
      cmd_dur=$((cmd_finish_sec - cmd_start_sec))
    fi
  fi

  # Parse tasks and save to temp file
  awk '
    /^tasks:/ { in_tasks=1; next }
    in_tasks && /^  - id:/ {
      if (task_id != "") {
        print role ":" model ":" status ":" duration
      }
      task_id=$3
      role=""; model=""; status=""; duration=""
    }
    in_tasks && /^    role:/ { role=$2 }
    in_tasks && /^    model:/ { model=$2 }
    in_tasks && /^    status:/ { status=$2 }
    in_tasks && /^    duration_sec:/ { duration=$2 }
    in_tasks && /^[^ ]/ && !/^  - id:/ {
      if (task_id != "") {
        print role ":" model ":" status ":" duration
      }
      exit
    }
    END {
      if (in_tasks && task_id != "") {
        print role ":" model ":" status ":" duration
      }
    }
  ' "$log_file" >> "$TEMP_TASKS"

  # Save cmd info for time trend
  cmd_date=$(echo "$cmd_started" | cut -d' ' -f1)
  cmd_task_count=$(grep -c "^  - id:" "$log_file" 2>/dev/null || echo "0")
  cmd_success_count=$(awk '
    /^tasks:/ { in_tasks=1; next }
    in_tasks && /^  - id:/ { task_id=$3 }
    in_tasks && /^    status: success/ { success++ }
    in_tasks && /^[^ ]/ && !/^  - id:/ { exit }
    END { print success+0 }
  ' "$log_file")

  echo "$cmd_id:$cmd_date:$cmd_task_count:$cmd_success_count:$cmd_dur" >> "$TEMP_CMD_INFO"
done

# Count statistics from temp file
total_tasks=$(wc -l < "$TEMP_TASKS" 2>/dev/null || echo "0")
total_success=$(grep -c ":success:" "$TEMP_TASKS" 2>/dev/null || echo "0")

# Per-persona stats (worker roles only)
declare -A persona_stats
for persona in worker_coder worker_researcher worker_writer worker_reviewer; do
  total=$(grep "^$persona:" "$TEMP_TASKS" 2>/dev/null | wc -l)
  success=$(grep "^$persona:.*:success:" "$TEMP_TASKS" 2>/dev/null | wc -l)
  persona_stats["$persona"]="$success/$total"
done

# Per-model stats (all tasks)
declare -A model_stats
for model in haiku sonnet opus; do
  total=$(grep ":$model:" "$TEMP_TASKS" 2>/dev/null | wc -l)
  success=$(grep ":$model:success:" "$TEMP_TASKS" 2>/dev/null | wc -l)
  model_stats["$model"]="$success/$total"
done

# Duration stats - extract all durations
all_durations=$(awk -F: '{if ($4 != "" && $4 != "null") print $4}' "$TEMP_TASKS" | sort -n)
cmd_durations=$(awk -F: '{if ($5 != "") print $5}' "$TEMP_CMD_INFO" | sort -n)

# Calculate statistics from newline-separated data
calculate_average() {
  local data="$1"
  if [[ -z "$data" ]]; then
    echo "N/A"
    return
  fi
  local count=$(echo "$data" | wc -l)
  local sum=$(echo "$data" | awk '{sum+=$1} END {print sum+0}')
  if [[ $count -eq 0 ]]; then
    echo "N/A"
  else
    echo $((sum / count))
  fi
}

calculate_median() {
  local data="$1"
  if [[ -z "$data" ]]; then
    echo "N/A"
    return
  fi
  local count=$(echo "$data" | wc -l)
  if [[ $count -eq 0 ]]; then
    echo "N/A"
    return
  fi

  if (( count % 2 == 1 )); then
    # Odd: middle element
    echo "$data" | sed -n "$((count / 2 + 1))p"
  else
    # Even: average of two middle elements
    local mid1=$(echo "$data" | sed -n "$((count / 2))p")
    local mid2=$(echo "$data" | sed -n "$((count / 2 + 1))p")
    echo $(( (mid1 + mid2) / 2 ))
  fi
}

calc_percent() {
  local num=$1
  local total=$2
  if [[ $total -eq 0 ]]; then
    echo "0"
  else
    echo $(( (num * 100) / total ))
  fi
}

# Calculate duration statistics
avg_task_dur=$(calculate_average "$all_durations")
median_task_dur=$(calculate_median "$all_durations")
avg_cmd_dur=$(calculate_average "$cmd_durations")

# Display results
echo "=== claude-crew Execution Statistics ==="
echo ""
echo "Overview:"
echo "  Total cmds processed: $total_cmds"
echo "  Total tasks executed: $total_tasks"
overall_rate=$(calc_percent $total_success $total_tasks)
echo "  Overall success rate: $total_success/$total_tasks ($overall_rate%)"
echo ""

echo "Per-persona success rates (worker roles only):"
for persona in worker_coder worker_researcher worker_writer worker_reviewer; do
  stats="${persona_stats[$persona]:-0/0}"
  IFS='/' read -r success total <<< "$stats"
  if [[ ${total:-0} -gt 0 ]]; then
    rate=$(calc_percent ${success:-0} ${total:-0})
    printf "  %-20s %3d/%-3d tasks succeeded (%3d%%)\n" "$persona:" "${success:-0}" "${total:-0}" "$rate"
  fi
done
echo ""

echo "Per-model success rates (all tasks):"
for model in haiku sonnet opus; do
  stats="${model_stats[$model]:-0/0}"
  IFS='/' read -r success total <<< "$stats"
  if [[ ${total:-0} -gt 0 ]]; then
    rate=$(calc_percent ${success:-0} ${total:-0})
    printf "  %-20s %3d/%-3d tasks succeeded (%3d%%)\n" "$model:" "${success:-0}" "${total:-0}" "$rate"
  fi
done
echo ""

echo "Duration stats:"
echo "  Average task duration: $avg_task_dur seconds"
echo "  Median task duration:  $median_task_dur seconds"
echo "  Average cmd duration:  $avg_cmd_dur seconds"
echo ""

echo "Time trend (by cmd):"
printf "  %-12s %-20s %6s %8s %8s\n" "cmd_id" "date" "tasks" "success" "rate"
printf "  %s\n" "------------------------------------------------------------"

while IFS=: read -r cmd_id cmd_date cmd_task_count cmd_success_count cmd_dur; do
  if [[ $cmd_task_count -gt 0 ]]; then
    cmd_rate=$(calc_percent $cmd_success_count $cmd_task_count)
    printf "  %-12s %-20s %6d %8d %7d%%\n" "$cmd_id" "$cmd_date" "$cmd_task_count" "$cmd_success_count" "$cmd_rate"
  fi
done < "$TEMP_CMD_INFO"

echo ""
echo "=== END ==="
