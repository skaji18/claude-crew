#!/bin/bash
# scripts/analyze_patterns.sh
# Analyzes execution logs to identify workflow patterns and success metrics.
# Usage: bash scripts/analyze_patterns.sh [output_path]
# Default output_path: $PROJECT_ROOT/patterns.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_PATH="${1:-$PROJECT_ROOT/patterns.md}"

# Find all execution logs
EXEC_LOGS=$(find "$PROJECT_ROOT/work" -type f -name "execution_log.yaml" 2>/dev/null | sort)

if [[ -z "$EXEC_LOGS" ]]; then
  echo "Error: No execution_log.yaml files found in $PROJECT_ROOT/work" >&2
  exit 1
fi

# Count logs
LOG_COUNT=$(echo "$EXEC_LOGS" | wc -l)

# Create temp files for data aggregation
TEMP_TASKS=$(mktemp)
TEMP_SEQUENCES=$(mktemp)
trap 'rm -f "$TEMP_TASKS" "$TEMP_SEQUENCES"' EXIT

# Extract task data from all logs
for log_file in $EXEC_LOGS; do
  # Parse tasks and save role:model:status:duration to temp file
  awk '
    /^tasks:/ { in_tasks=1; next }
    in_tasks && /^  - id:/ {
      # Print previous task if it exists and is a worker role
      if (task_id != "" && role != "" && role != "decomposer" && role != "aggregator" && role != "retrospector") {
        if (status == "") status = "unknown"
        if (duration == "" || duration == "null") duration = "0"
        print role ":" model ":" status ":" duration
      }
      # Reset for new task
      task_id=$3; role=""; model=""; status=""; duration=""
    }
    in_tasks && /^    role:/ { role=$2 }
    in_tasks && /^    model:/ { model=$2 }
    in_tasks && /^    status:/ { status=$2 }
    in_tasks && /^    duration_sec:/ { duration=$2 }
    in_tasks && /^[^ ]/ && !/^  - id:/ {
      # End of tasks section
      if (task_id != "" && role != "" && role != "decomposer" && role != "aggregator" && role != "retrospector") {
        if (status == "") status = "unknown"
        if (duration == "" || duration == "null") duration = "0"
        print role ":" model ":" status ":" duration
      }
      exit
    }
    END {
      # Handle last task
      if (in_tasks && task_id != "" && role != "" && role != "decomposer" && role != "aggregator" && role != "retrospector") {
        if (status == "") status = "unknown"
        if (duration == "" || duration == "null") duration = "0"
        print role ":" model ":" status ":" duration
      }
    }
  ' "$log_file" >> "$TEMP_TASKS"

  # Extract task sequences for pattern detection
  awk '
    /^tasks:/ { in_tasks=1; seq=""; prev=""; next }
    in_tasks && /^    role:/ {
      role=$2
      if (role != "decomposer" && role != "aggregator" && role != "retrospector") {
        if (prev != "" && prev != role) {
          if (seq == "") {
            seq = prev " → " role
          } else {
            seq = seq " → " role
          }
        }
        prev = role
      }
    }
    in_tasks && /^[^ ]/ && !/^  - id:/ {
      if (seq != "") print seq
      exit
    }
    END {
      if (in_tasks && seq != "") print seq
    }
  ' "$log_file" >> "$TEMP_SEQUENCES"
done

# Helper function: calculate percentage
calc_percent() {
  local num=$1
  local total=$2
  if [[ $total -eq 0 ]]; then
    echo "0"
  else
    echo $(( (num * 100) / total ))
  fi
}

# Helper function: calculate average
calc_average() {
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

# Aggregate statistics by persona
declare -A persona_total
declare -A persona_success
declare -A persona_durations

for persona in worker_researcher worker_writer worker_coder worker_reviewer; do
  total=$(grep "^$persona:" "$TEMP_TASKS" 2>/dev/null | wc -l)
  success=$(grep "^$persona:.*:success:" "$TEMP_TASKS" 2>/dev/null | wc -l)
  durations=$(grep "^$persona:.*:success:" "$TEMP_TASKS" 2>/dev/null | awk -F: '{if ($4 != "" && $4 != "null") print $4}')

  persona_total["$persona"]=$total
  persona_success["$persona"]=$success

  if [[ -n "$durations" ]]; then
    persona_durations["$persona"]=$(calc_average "$durations")
  else
    persona_durations["$persona"]="N/A"
  fi
done

# Aggregate statistics by persona+model
declare -A combo_total
declare -A combo_success
declare -A combo_durations

for persona in worker_researcher worker_writer worker_coder worker_reviewer; do
  for model in haiku sonnet opus; do
    combo="${persona}:${model}"
    total=$(grep "^$persona:$model:" "$TEMP_TASKS" 2>/dev/null | wc -l)
    success=$(grep "^$persona:$model:success:" "$TEMP_TASKS" 2>/dev/null | wc -l)
    durations=$(grep "^$persona:$model:success:" "$TEMP_TASKS" 2>/dev/null | awk -F: '{if ($4 != "" && $4 != "null") print $4}')

    if [[ $total -gt 0 ]]; then
      combo_total["$combo"]=$total
      combo_success["$combo"]=$success

      if [[ -n "$durations" ]]; then
        combo_durations["$combo"]=$(calc_average "$durations")
      else
        combo_durations["$combo"]="N/A"
      fi
    fi
  done
done

# Find common task sequences
declare -A sequence_counts
while IFS= read -r seq; do
  ((sequence_counts["$seq"]++)) || true
done < "$TEMP_SEQUENCES"

# Calculate wave size distribution
total_tasks=$(wc -l < "$TEMP_TASKS" 2>/dev/null || echo "0")
total_logs=$LOG_COUNT

# Generate patterns.md
cat > "$OUTPUT_PATH" <<EOF
# Workflow Patterns (Auto-Generated)

Last updated: $(date '+%Y-%m-%d %H:%M:%S')
Data source: $LOG_COUNT execution logs

## Success Rates by Persona

| Persona | Tasks | Success Rate | Avg Duration |
|---------|-------|--------------|--------------|
EOF

for persona in worker_researcher worker_writer worker_coder worker_reviewer; do
  total=${persona_total["$persona"]:-0}
  success=${persona_success["$persona"]:-0}
  avg_dur=${persona_durations["$persona"]:-N/A}

  if [[ $total -gt 0 ]]; then
    rate=$(calc_percent $success $total)
    echo "| $persona | $total | $success/$total ($rate%) | ${avg_dur}s |" >> "$OUTPUT_PATH"
  fi
done

cat >> "$OUTPUT_PATH" <<EOF

## Model Performance by Persona

| Persona | Model | Success Rate | Avg Duration |
|---------|-------|--------------|--------------|
EOF

for persona in worker_researcher worker_writer worker_coder worker_reviewer; do
  for model in haiku sonnet opus; do
    combo="${persona}:${model}"
    total=${combo_total["$combo"]:-0}
    success=${combo_success["$combo"]:-0}
    avg_dur=${combo_durations["$combo"]:-N/A}

    if [[ $total -gt 0 ]]; then
      rate=$(calc_percent $success $total)
      echo "| $persona | $model | $success/$total ($rate%) | ${avg_dur}s |" >> "$OUTPUT_PATH"
    fi
  done
done

cat >> "$OUTPUT_PATH" <<EOF

## Common Task Sequences

EOF

# Sort sequences by count (descending) and output top 10
if [[ ${#sequence_counts[@]} -gt 0 ]]; then
  seq_num=1
  for seq in "${!sequence_counts[@]}"; do
    count=${sequence_counts["$seq"]}
    echo "$count|$seq"
  done | sort -t'|' -k1 -nr | head -10 | while IFS='|' read -r count seq; do
    # Calculate success rate for this sequence by checking individual occurrences
    # For simplicity, we report occurrence count only
    echo "$seq_num. $seq ($count occurrences)" >> "$OUTPUT_PATH"
    ((seq_num++)) || true
  done
else
  echo "(No task sequences detected)" >> "$OUTPUT_PATH"
fi

# Add recommendations section if we have enough data
if [[ $LOG_COUNT -ge 10 ]]; then
  cat >> "$OUTPUT_PATH" <<EOF

## Recommendations (N >= 10 logs)

EOF

  # Analyze wave sizes (approximate by tasks per cmd)
  avg_tasks_per_cmd=$((total_tasks / total_logs))

  # Find best-performing persona by success rate
  best_persona=""
  best_rate=0
  for persona in worker_researcher worker_writer worker_coder worker_reviewer; do
    total=${persona_total["$persona"]:-0}
    success=${persona_success["$persona"]:-0}
    if [[ $total -ge 3 ]]; then  # Only consider personas with at least 3 tasks
      rate=$(calc_percent $success $total)
      if [[ $rate -gt $best_rate ]]; then
        best_rate=$rate
        best_persona=$persona
      fi
    fi
  done

  # Find most efficient model (best success rate with reasonable sample size)
  best_model_combo=""
  best_model_rate=0
  for persona in worker_researcher worker_writer worker_coder worker_reviewer; do
    for model in haiku sonnet opus; do
      combo="${persona}:${model}"
      total=${combo_total["$combo"]:-0}
      success=${combo_success["$combo"]:-0}
      if [[ $total -ge 2 ]]; then
        rate=$(calc_percent $success $total)
        if [[ $rate -gt $best_model_rate ]]; then
          best_model_rate=$rate
          best_model_combo="$combo"
        fi
      fi
    done
  done

  cat >> "$OUTPUT_PATH" <<EOF
- **Wave sizing**: Average tasks per cmd is $avg_tasks_per_cmd. Consider keeping waves at or below this size for consistency.
EOF

  if [[ -n "$best_persona" ]]; then
    cat >> "$OUTPUT_PATH" <<EOF
- **Persona selection**: $best_persona has the highest success rate ($best_rate%) among personas with 3+ tasks.
EOF
  fi

  if [[ -n "$best_model_combo" ]]; then
    persona_part=$(echo "$best_model_combo" | cut -d: -f1)
    model_part=$(echo "$best_model_combo" | cut -d: -f2)
    cat >> "$OUTPUT_PATH" <<EOF
- **Model selection**: $persona_part with $model_part has a $best_model_rate% success rate.
EOF
  fi

  # Find well-tested sequences
  most_common_seq=""
  most_common_count=0
  for seq in "${!sequence_counts[@]}"; do
    count=${sequence_counts["$seq"]}
    if [[ $count -gt $most_common_count ]]; then
      most_common_count=$count
      most_common_seq="$seq"
    fi
  done

  if [[ $most_common_count -ge 3 ]]; then
    cat >> "$OUTPUT_PATH" <<EOF
- **Persona transitions**: "$most_common_seq" sequence appears $most_common_count times and is well-tested.
EOF
  fi
fi

echo "Workflow patterns written to: $OUTPUT_PATH"
