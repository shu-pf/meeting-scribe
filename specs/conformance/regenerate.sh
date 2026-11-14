#!/usr/bin/env bash
# specs/pipeline_jobs.fsl から照合テストを生成し直し、Adapter につなぐ。fslc 5.x が要る。
# Run from the repository root: ./specs/conformance/regenerate.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
OUT=specs/conformance/Tests/PipelineJobsConformanceTests/PipelineJobsConformanceTests.swift
fslc testgen specs/pipeline_jobs.fsl --target swift --depth 10 -o "$OUT" >/dev/null
# 生成物は Adapter 未接続だと全テストが失敗する。Adapter.swift の実装につなぐ。
perl -0pi -e 's/(func makeAdapter\(\) throws -> any Adapter \{\n)    throw FSLNotWired\.notWired\n/$1    PipelineJobsAdapter()\n/' "$OUT"
grep -q 'PipelineJobsAdapter()' "$OUT" || { echo "makeAdapter の差し替えに失敗" >&2; exit 1; }
