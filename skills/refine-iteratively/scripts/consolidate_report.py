#!/usr/bin/env python3
"""
Consolidate all round results into a final summary report.

This script aggregates metadata from all result_N.md files and generates a
consolidated report with quality history and final summary. Executed at the
end of the iterative refinement process.

Usage:
    ./consolidate_report.py \
        --results-dir path/to/results/ \
        --output path/to/final_report.md
"""

import sys
import json
import argparse
import subprocess
from pathlib import Path
from datetime import datetime


def extract_metadata_via_script(filepath: str, extract_script_path: str) -> dict:
    """
    Call extract_metadata.py to extract metadata from a result file.

    Args:
        filepath: Path to the result file
        extract_script_path: Path to extract_metadata.py script

    Returns:
        Dictionary with extracted metadata

    Raises:
        RuntimeError: If extraction fails
    """
    try:
        result = subprocess.run(
            [extract_script_path, '--file', filepath],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode != 0:
            # Return defaults on error
            return {
                'status': 'unknown',
                'quality': 'YELLOW',
                'completeness': 0,
                'errors': ['Failed to extract metadata'],
                'warnings': []
            }

        # Parse JSON output
        try:
            metadata = json.loads(result.stdout)
            return metadata
        except json.JSONDecodeError:
            return {
                'status': 'unknown',
                'quality': 'YELLOW',
                'completeness': 0,
                'errors': ['Invalid JSON from extract_metadata.py'],
                'warnings': []
            }

    except subprocess.TimeoutExpired:
        return {
            'status': 'unknown',
            'quality': 'YELLOW',
            'completeness': 0,
            'errors': ['Metadata extraction timed out'],
            'warnings': []
        }
    except Exception as e:
        return {
            'status': 'unknown',
            'quality': 'YELLOW',
            'completeness': 0,
            'errors': [f'Error extracting metadata: {str(e)}'],
            'warnings': []
        }


def find_result_files(results_dir: str) -> list:
    """
    Find all result_*.md files in the results directory.

    Args:
        results_dir: Path to directory containing result files

    Returns:
        List of (round_number, filepath) tuples sorted by round number

    Raises:
        FileNotFoundError: If results_dir does not exist
    """
    path = Path(results_dir)

    if not path.exists():
        raise FileNotFoundError(f"Results directory not found: {results_dir}")

    if not path.is_dir():
        raise ValueError(f"Path is not a directory: {results_dir}")

    # Find result_N.md files
    result_files = []
    for file_path in path.glob('result_*.md'):
        # Extract round number from filename
        try:
            round_num = int(file_path.stem.split('_')[1])
            result_files.append((round_num, file_path))
        except (ValueError, IndexError):
            # Skip files that don't match result_N.md pattern
            continue

    # Sort by round number
    result_files.sort(key=lambda x: x[0])

    return result_files


def extract_output_files(result_filepath: str) -> list:
    """
    Extract output files from a result file's "## Output Files" section.

    Args:
        result_filepath: Path to the result file

    Returns:
        List of (filename, line_count) tuples

    Raises:
        FileNotFoundError: If file does not exist
    """
    path = Path(result_filepath)

    if not path.exists():
        return []

    try:
        content = path.read_text(encoding='utf-8')
    except Exception:
        return []

    output_files = []
    in_output_section = False

    lines = content.split('\n')
    for line in lines:
        if line.startswith('## Output Files'):
            in_output_section = True
            continue

        if in_output_section:
            # Stop at next section or end of file
            if line.startswith('##'):
                break

            # Parse list items: "- `filename` (N lines)"
            line = line.strip()
            if line.startswith('- '):
                # Remove list marker
                line = line[2:]

                # Extract filename (between backticks)
                if '`' in line:
                    parts = line.split('`')
                    if len(parts) >= 2:
                        filename = parts[1]

                        # Extract line count (in parentheses)
                        line_count = 0
                        if '(' in line and 'lines' in line:
                            try:
                                count_str = line.split('(')[1].split()[0]
                                line_count = int(count_str)
                            except (ValueError, IndexError):
                                pass

                        output_files.append((filename, line_count))

    return output_files


def quality_to_score(quality: str) -> int:
    """
    Convert quality level to numeric score for comparison.

    Args:
        quality: Quality level (RED, YELLOW, GREEN)

    Returns:
        Numeric score (0=RED, 1=YELLOW, 2=GREEN)
    """
    quality_map = {
        'RED': 0,
        'YELLOW': 1,
        'GREEN': 2
    }
    return quality_map.get(quality, 0)


def consolidate_report(
    results_dir: str,
    output_file: str,
    extract_script_path: str = None
) -> dict:
    """
    Consolidate all round results into a final report.

    Args:
        results_dir: Path to directory with result_N.md files
        output_file: Where to write the consolidated report
        extract_script_path: Path to extract_metadata.py (optional, use default if None)

    Returns:
        Dictionary with consolidation metadata:
        - rounds_completed: Number of rounds processed
        - final_status: Overall status (success/partial/failure)
        - final_quality: Final quality level
        - final_completeness: Final completeness percentage
        - output_file_count: Number of deliverables identified

    Raises:
        FileNotFoundError: If results directory doesn't exist
        IOError: If unable to write output file
    """
    # Default extract_script location
    if extract_script_path is None:
        script_dir = Path(__file__).parent
        extract_script_path = str(script_dir / 'extract_metadata.py')

    # Find all result files
    result_files = find_result_files(results_dir)

    if not result_files:
        raise FileNotFoundError(f"No result_*.md files found in {results_dir}")

    # Extract metadata from each round
    rounds_data = []
    for round_num, filepath in result_files:
        metadata = extract_metadata_via_script(str(filepath), extract_script_path)

        # Extract output files from last round
        output_files = []
        if round_num == result_files[-1][0]:  # Last round
            output_files = extract_output_files(str(filepath))

        rounds_data.append({
            'round': round_num,
            'filepath': str(filepath),
            'status': metadata.get('status', 'unknown'),
            'quality': metadata.get('quality', 'YELLOW'),
            'completeness': metadata.get('completeness', 0),
            'errors': metadata.get('errors', []),
            'warnings': metadata.get('warnings', []),
            'output_files': output_files
        })

    # Determine final values
    final_round = rounds_data[-1]
    final_status = final_round['status']
    final_quality = final_round['quality']
    final_completeness = final_round['completeness']
    output_files_list = final_round['output_files']

    # Generate consolidated report
    report_lines = []

    # YAML frontmatter
    report_lines.append('---')
    report_lines.append('generated_by: "refine-iteratively v1.0.0"')
    report_lines.append(f'rounds_completed: {len(rounds_data)}')
    report_lines.append(f'final_status: "{final_status}"')
    report_lines.append(f'final_quality: "{final_quality}"')
    report_lines.append(f'final_completeness: {final_completeness}')
    report_lines.append('---')
    report_lines.append('')

    # Title
    report_lines.append('# Iterative Refinement Report')
    report_lines.append('')

    # Quality History table
    report_lines.append('## Quality History')
    report_lines.append('| Round | Status | Quality | Completeness |')
    report_lines.append('|-------|--------|---------|--------------|')

    for round_data in rounds_data:
        round_num = round_data['round']
        status = round_data['status']
        quality = round_data['quality']
        completeness = round_data['completeness']
        report_lines.append(
            f'| {round_num} | {status} | {quality} | {completeness}% |'
        )

    report_lines.append('')

    # Final Summary
    report_lines.append('## Final Summary')
    report_lines.append(f'**Final Status**: {final_status}')
    report_lines.append(f'**Final Quality**: {final_quality}')
    report_lines.append(f'**Final Completeness**: {final_completeness}%')
    report_lines.append('')

    # Quality progression
    if len(rounds_data) > 1:
        first_quality_score = quality_to_score(rounds_data[0]['quality'])
        final_quality_score = quality_to_score(final_quality)
        quality_change = final_quality_score - first_quality_score

        first_completeness = rounds_data[0]['completeness']
        completeness_change = final_completeness - first_completeness

        report_lines.append('**Quality Progression**:')
        quality_symbols = ['RED', 'YELLOW', 'GREEN']
        if quality_change > 0:
            report_lines.append(
                f'- Quality improved: {quality_symbols[first_quality_score]} → '
                f'{quality_symbols[final_quality_score]} (+{quality_change} level)'
            )
        elif quality_change < 0:
            report_lines.append(
                f'- Quality declined: {quality_symbols[first_quality_score]} → '
                f'{quality_symbols[final_quality_score]} ({quality_change} level)'
            )
        else:
            report_lines.append(f'- Quality stable: {final_quality}')

        report_lines.append(f'- Completeness change: {completeness_change:+d}% '
                          f'({first_completeness}% → {final_completeness}%)')
        report_lines.append('')

    # Deliverables section
    if output_files_list:
        report_lines.append('## Deliverables')
        for filename, line_count in output_files_list:
            line_info = f'({line_count} lines)' if line_count > 0 else ''
            report_lines.append(f'- `{filename}` {line_info}'.strip())
        report_lines.append('')

    # Completion marker
    report_lines.append('<!-- COMPLETE -->')

    # Write output file
    report_content = '\n'.join(report_lines)

    try:
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(report_content, encoding='utf-8')
    except Exception as e:
        raise IOError(f"Failed to write output file: {e}")

    # Return consolidation metadata
    return {
        'rounds_completed': len(rounds_data),
        'final_status': final_status,
        'final_quality': final_quality,
        'final_completeness': final_completeness,
        'output_file_count': len(output_files_list)
    }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Consolidate all round results into a final summary report'
    )
    parser.add_argument(
        '--results-dir',
        required=True,
        help='Directory containing result_N.md files'
    )
    parser.add_argument(
        '--output',
        required=True,
        help='Where to write the final consolidated report'
    )
    parser.add_argument(
        '--extract-script',
        help='Path to extract_metadata.py (optional, uses default if not provided)'
    )

    args = parser.parse_args()

    try:
        metadata = consolidate_report(
            args.results_dir,
            args.output,
            args.extract_script
        )

        # Output metadata as JSON to stdout
        json.dump(metadata, sys.stdout, indent=2)
        sys.stdout.write('\n')

        print(f"✓ Report written to: {args.output}", file=sys.stderr)
        return 0

    except FileNotFoundError as e:
        error_msg = f"Error: {str(e)}"
        print(error_msg, file=sys.stderr)
        return 1

    except ValueError as e:
        error_msg = f"Invalid input: {str(e)}"
        print(error_msg, file=sys.stderr)
        return 1

    except IOError as e:
        error_msg = f"I/O error: {str(e)}"
        print(error_msg, file=sys.stderr)
        return 1

    except Exception as e:
        error_msg = f"Unexpected error: {str(e)}"
        print(error_msg, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
