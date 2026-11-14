#!/usr/bin/env bash
# specs/*.fsl から照合テストを生成し直し、Adapter につなぐ。fslc 5.x が要る。
# Run from the repository root: ./specs/conformance/regenerate.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# 仕様、テストのターゲット、Adapter の型、探索の深さ
generate() {
  local spec="$1" target="$2" adapter="$3" depth="$4"
  local out="specs/conformance/Tests/$target/$target.swift"
  fslc testgen "specs/$spec" --target swift --depth "$depth" -o "$out" >/dev/null
  # 生成物は Adapter 未接続だと全テストが失敗する。Adapter.swift の実装につなぐ。
  perl -0pi -e "s/(func makeAdapter\\(\\) throws -> any Adapter \\{\\n)    throw FSLNotWired\\.notWired\\n/\$1    $adapter()\\n/" "$out"
  grep -q "$adapter()" "$out" || { echo "$out: makeAdapter の差し替えに失敗" >&2; exit 1; }
}

generate pipeline_jobs.fsl PipelineJobsConformanceTests PipelineJobsAdapter 10
generate initial_setup.fsl InitialSetupConformanceTests InitialSetupAdapter 16
