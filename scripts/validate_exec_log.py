#!/usr/bin/env python3
"""
Validation script for execution_log.yaml files.

Detects anomalies including:
- Invalid status values
- Orphaned tasks (finished=null while status suggests completion)
- Excessive durations
- Retry limit violations
- Duplicate task IDs

Uses error codes E200-E299 (Validation errors).

Usage:
    python3 scripts/validate_exec_log.py <path/to/execution_log.yaml>

Exit codes:
    0: No anomalies found
    1: Anomalies detected
"""

import sys
import os
import yaml
from pathlib import Path
from typing import Dict, Any, List, Tuple


# Error code definitions for validation errors (E200-E299)
ERROR_CODES = {
    'E200': 'YAML frontmatter missing',
    'E201': 'YAML frontmatter parse error',
    'E220': 'status field invalid - expected success, partial, failure, running, or pending',
    'E281': 'YAML parse error',
    'E283': 'data type mismatch',
    'E284': 'value out of bounds',
    'E285': 'enum value invalid',
    'E286': 'required field null',
}


class ExecutionLogValidator:
    """Validates execution_log.yaml files for anomalies."""

    # Valid status values for both cmd and tasks
    VALID_CMD_STATUSES = {'success', 'failed', 'running', 'pending'}
    VALID_TASK_STATUSES = {'success', 'failed', 'running', 'pending', 'partial'}

    def __init__(self, exec_log_path: str, config_path: str = 'config.yaml'):
        """Initialize validator with paths."""
        self.exec_log_path = Path(exec_log_path)
        self.config_path = Path(config_path)
        self.exec_log = None
        self.config = None
        self.anomalies = []

    def load_files(self) -> bool:
        """Load execution_log.yaml and config.yaml."""
        try:
            if not self.exec_log_path.exists():
                self.anomalies.append({
                    'type': 'E300',
                    'message': f'file not found: {self.exec_log_path}',
                    'severity': 'critical'
                })
                return False

            with open(self.exec_log_path, 'r') as f:
                self.exec_log = yaml.safe_load(f)
                if not isinstance(self.exec_log, dict):
                    self.anomalies.append({
                        'type': 'E281',
                        'message': 'execution_log.yaml is not a valid YAML mapping',
                        'severity': 'critical'
                    })
                    return False

        except yaml.YAMLError as e:
            self.anomalies.append({
                'type': 'E201',
                'message': f'YAML parse error: {str(e)}',
                'severity': 'critical'
            })
            return False
        except Exception as e:
            self.anomalies.append({
                'type': 'E303',
                'message': f'file read failed: {str(e)}',
                'severity': 'critical'
            })
            return False

        # Load config for threshold values
        try:
            if self.config_path.exists():
                with open(self.config_path, 'r') as f:
                    self.config = yaml.safe_load(f)
            else:
                # Use defaults if config not found
                self.config = {}
        except Exception:
            # If config fails to load, use defaults
            self.config = {}

        return True

    def validate(self) -> bool:
        """Run all validation checks."""
        if not self.load_files():
            return False

        if not self.exec_log:
            return False

        # Get threshold values from config
        max_cmd_duration_sec = self.config.get('max_cmd_duration_sec', 1800)
        max_retries = self.config.get('max_retries', 2)

        # Validate cmd-level fields
        self._validate_cmd_status()
        self._validate_cmd_finished()

        # Validate tasks
        if 'tasks' in self.exec_log:
            tasks = self.exec_log['tasks']
            if not isinstance(tasks, list):
                self.anomalies.append({
                    'type': 'E283',
                    'message': 'tasks field must be a list',
                    'task': None,
                    'severity': 'critical'
                })
                return len(self.anomalies) == 0

            # Check for duplicate task IDs
            self._check_duplicate_ids(tasks)

            # Validate each task
            for task in tasks:
                if not isinstance(task, dict):
                    self.anomalies.append({
                        'type': 'E283',
                        'message': 'task entry is not a dict',
                        'task': None,
                        'severity': 'error'
                    })
                    continue

                task_id = task.get('id')
                self._validate_task_status(task, task_id)
                self._validate_task_finished(task, task_id)
                self._validate_task_duration(task, max_cmd_duration_sec, task_id)
                self._validate_task_retries(task, max_retries, task_id)

        return len(self.anomalies) == 0

    def _validate_cmd_status(self) -> None:
        """Check if cmd status is valid."""
        status = self.exec_log.get('status')
        if status is None:
            self.anomalies.append({
                'type': 'E286',
                'message': 'cmd status field is null',
                'task': None,
                'severity': 'critical'
            })
        elif status not in self.VALID_CMD_STATUSES:
            self.anomalies.append({
                'type': 'E220',
                'message': f'cmd status "{status}" is invalid (expected: {", ".join(sorted(self.VALID_CMD_STATUSES))})',
                'task': None,
                'severity': 'error'
            })

    def _validate_cmd_finished(self) -> None:
        """Check if cmd finished timestamp is appropriate."""
        status = self.exec_log.get('status')
        finished = self.exec_log.get('finished')

        # If status is success/failed, finished should not be null
        if status in ('success', 'failed') and finished is None:
            self.anomalies.append({
                'type': 'E286',
                'message': f'cmd status is {status} but finished timestamp is null',
                'task': None,
                'severity': 'error'
            })

    def _validate_task_status(self, task: Dict, task_id: Any) -> None:
        """Check if task status is valid."""
        status = task.get('status')
        if status is None:
            self.anomalies.append({
                'type': 'E286',
                'message': f'task {task_id} status field is null',
                'task': task_id,
                'severity': 'critical'
            })
        elif status not in self.VALID_TASK_STATUSES:
            self.anomalies.append({
                'type': 'E220',
                'message': f'task {task_id} status "{status}" is invalid (expected: {", ".join(sorted(self.VALID_TASK_STATUSES))})',
                'task': task_id,
                'severity': 'error'
            })

    def _validate_task_finished(self, task: Dict, task_id: Any) -> None:
        """Check if task finished timestamp is appropriate (orphaned task detection)."""
        status = task.get('status')
        finished = task.get('finished')

        # If status is success/failed/partial, finished should not be null
        if status in ('success', 'failed', 'partial') and finished is None:
            self.anomalies.append({
                'type': 'E286',
                'message': f'task {task_id} status is {status} but finished timestamp is null (orphaned task)',
                'task': task_id,
                'severity': 'error'
            })

    def _validate_task_duration(self, task: Dict, max_duration: int, task_id: Any) -> None:
        """Check if task duration exceeds threshold."""
        duration = task.get('duration_sec')
        status = task.get('status')

        # Skip validation for running tasks (duration_sec may be null)
        if status == 'running':
            return

        if duration is not None and isinstance(duration, (int, float)):
            if duration > max_duration:
                self.anomalies.append({
                    'type': 'E284',
                    'message': f'task {task_id} duration {duration}s exceeds max_cmd_duration_sec {max_duration}s',
                    'task': task_id,
                    'severity': 'warning'
                })

    def _validate_task_retries(self, task: Dict, max_retries: int, task_id: Any) -> None:
        """Check if task retries exceed configured maximum."""
        retries = task.get('retries')

        if retries is not None and isinstance(retries, int):
            if retries > max_retries:
                self.anomalies.append({
                    'type': 'E284',
                    'message': f'task {task_id} retries {retries} exceeds max_retries {max_retries}',
                    'task': task_id,
                    'severity': 'warning'
                })

    def _check_duplicate_ids(self, tasks: List[Dict]) -> None:
        """Check for duplicate task IDs."""
        ids = [task.get('id') for task in tasks if isinstance(task, dict)]
        seen = set()
        duplicates = set()

        for task_id in ids:
            if task_id in seen:
                duplicates.add(task_id)
            seen.add(task_id)

        for dup_id in duplicates:
            self.anomalies.append({
                'type': 'E285',
                'message': f'duplicate task ID: {dup_id}',
                'task': dup_id,
                'severity': 'critical'
            })

    def report(self) -> None:
        """Print validation report."""
        if not self.anomalies:
            print(f'✓ {self.exec_log_path}: No anomalies detected')
            return

        print(f'✗ {self.exec_log_path}: {len(self.anomalies)} anomaly/anomalies detected\n')

        # Group by severity
        critical = [a for a in self.anomalies if a.get('severity') == 'critical']
        errors = [a for a in self.anomalies if a.get('severity') == 'error']
        warnings = [a for a in self.anomalies if a.get('severity') == 'warning']

        if critical:
            print(f'CRITICAL ({len(critical)}):')
            for anomaly in critical:
                self._print_anomaly(anomaly)
            print()

        if errors:
            print(f'ERROR ({len(errors)}):')
            for anomaly in errors:
                self._print_anomaly(anomaly)
            print()

        if warnings:
            print(f'WARNING ({len(warnings)}):')
            for anomaly in warnings:
                self._print_anomaly(anomaly)
            print()

    def _print_anomaly(self, anomaly: Dict) -> None:
        """Print a single anomaly."""
        code = anomaly['type']
        message = anomaly['message']
        task = anomaly.get('task')

        if task is not None:
            print(f'  [{code}] Task {task}: {message}')
        else:
            print(f'  [{code}] {message}')


def main():
    """Main entry point."""
    if len(sys.argv) < 2:
        print('Usage: python3 scripts/validate_exec_log.py <path/to/execution_log.yaml>')
        sys.exit(1)

    exec_log_path = sys.argv[1]

    # Determine config.yaml path (look in same directory or parent)
    config_path = 'config.yaml'
    if not Path(config_path).exists():
        # Try to find it relative to the script
        script_dir = Path(__file__).parent.parent
        potential_config = script_dir / 'config.yaml'
        if potential_config.exists():
            config_path = str(potential_config)

    validator = ExecutionLogValidator(exec_log_path, config_path)
    has_anomalies = not validator.validate()
    validator.report()

    sys.exit(1 if has_anomalies else 0)


if __name__ == '__main__':
    main()
