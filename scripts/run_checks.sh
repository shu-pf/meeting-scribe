#!/usr/bin/env bash
# TCC 権限と Ollama が要らない確認スクリプトをビルドして実行する（CI 用）。
# Run from the repository root: ./scripts/run_checks.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/MeetingScribe-checks.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Xcode プロジェクトと同じ並行性の設定で型チェックする
SWIFT_FLAGS=(
  -parse-as-library
  -default-isolation MainActor
  -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferIsolatedConformances
  -enable-upcoming-feature MemberImportVisibility
)
PIPELINE_SOURCES=(
  MeetingScribe/Domain/Pipeline/RecordingPipeline.swift
  MeetingScribe/Domain/Pipeline/PipelineJobStore.swift
  MeetingScribe/Services/SummaryService.swift
  MeetingScribe/Services/TranscriptionService.swift
  MeetingScribe/Services/ElevenLabsScribeService.swift
  MeetingScribe/Services/WhisperModelStore.swift
  MeetingScribe/Services/AudioExtractor.swift
  MeetingScribe/Services/DiagnosticLogger.swift
)

run_check() {
  local name="$1"; shift
  local -a sources=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do sources+=("$1"); shift; done
  [[ $# -gt 0 ]] && shift
  echo "== check_$name"
  xcrun swiftc "${SWIFT_FLAGS[@]}" "scripts/check_$name.swift" "${sources[@]}" -o "$BUILD_DIR/check_$name"
  "$BUILD_DIR/check_$name" "$@"
}

run_check pipeline_job_store MeetingScribe/Domain/Pipeline/PipelineJobStore.swift
run_check recording_history_store MeetingScribe/Domain/History/RecordingHistoryStore.swift
run_check skip_summary "${PIPELINE_SOURCES[@]}" -- --no-ollama
