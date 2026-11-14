#!/usr/bin/env bash
# 実コードをランダムに動かした軌跡を、fslc replay で仕様に照らす。fslc 5.x が要る。
# Run from the repository root: ./specs/conformance/replay_random_walks.sh [walks]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
WALKS="${1:-3000}"

# 仕様、テストのターゲット
replay() {
  local spec="$1" target="$2"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/spec-walks.XXXXXX")"
  FSL_TRACE_DIR="$dir" FSL_WALKS="$WALKS" \
    swift test --package-path specs/conformance \
      --filter "$target.randomWalkTracesForReplay" >/dev/null
  local total=0 trace result
  for trace in "$dir"/walk-*.json; do
    total=$((total + 1))
    if ! result="$(fslc replay "specs/$spec" --trace "$trace")"; then
      echo "$spec nonconformant: $(basename "$trace") (kept in $dir)" >&2
      echo "$result" >&2
      exit 1
    fi
  done
  rm -rf "$dir"
  [[ $total -gt 0 ]] || { echo "$spec: 軌跡が 1 本も書き出されていない" >&2; exit 1; }
  echo "$spec conformant: $total walks"
}

replay pipeline_jobs.fsl PipelineJobsConformanceTests
replay initial_setup.fsl InitialSetupConformanceTests
