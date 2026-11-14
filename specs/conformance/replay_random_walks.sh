#!/usr/bin/env bash
# 実コード (PipelineJobCoordinator) をランダムに動かした軌跡を、fslc replay で仕様に照らす。fslc 5.x が要る。
# Run from the repository root: ./specs/conformance/replay_random_walks.sh [walks]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
TRACE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pipeline-jobs-walks.XXXXXX")"
trap 'rm -rf "$TRACE_DIR"' EXIT
FSL_TRACE_DIR="$TRACE_DIR" FSL_WALKS="${1:-3000}" \
  swift test --package-path specs/conformance --filter randomWalkTracesForReplay >/dev/null
total=0
for trace in "$TRACE_DIR"/walk-*.json; do
  total=$((total + 1))
  if ! result="$(fslc replay specs/pipeline_jobs.fsl --trace "$trace")"; then
    echo "nonconformant: $(basename "$trace")" >&2
    echo "$result" >&2
    exit 1
  fi
done
[[ $total -gt 0 ]] || { echo "軌跡が 1 本も書き出されていない" >&2; exit 1; }
echo "conformant: $total walks"
