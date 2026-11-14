#!/usr/bin/env bash
# 確認スクリプト scripts/check_<名前>.swift を、必要なアプリのソースとともにビルドして実行する。
# Run from the repository root:
#   ./scripts/run_checks.sh                 TCC 権限と Ollama が要らない確認をまとめて実行する（CI 用）
#   ./scripts/run_checks.sh <名前> [引数...]  1 つの確認を引数付きで実行する（例: resummarize gemma4:12b）
#   ./scripts/run_checks.sh --list          名前の一覧を表示する
# 次の 2 つは対象外。手順は各スクリプトの冒頭と AGENTS.md にある。
#   check_screen_capture_permission.swift: Debug アプリと同じ bundle ID・開発証明書での署名が要る
#   check_update_settings_sync.swift: Debug ビルドの Sparkle.framework とアプリが要る
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
SUMMARY_SOURCES=(
  MeetingScribe/Services/SummaryService.swift
  MeetingScribe/Services/DiagnosticLogger.swift
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

CHECK_NAMES=(
  pipeline_job_store recording_history_store skip_summary privacy_scrubber
  resummarize long_summary_input summary_input ollama_reconnect
  video_summary long_audio_extraction window_close_signal
)

# 確認ごとに、一緒にコンパイルするアプリのソースを SOURCES に入れる。
# ソースのファイルを増やしたり名前を変えたりしたら、ここだけ直す。
sources_for() {
  case "$1" in
    pipeline_job_store) SOURCES=(MeetingScribe/Domain/Pipeline/PipelineJobStore.swift) ;;
    recording_history_store) SOURCES=(MeetingScribe/Domain/History/RecordingHistoryStore.swift) ;;
    privacy_scrubber) SOURCES=(MeetingScribe/Services/PrivacyScrubber.swift) ;;
    skip_summary | resummarize | video_summary) SOURCES=("${PIPELINE_SOURCES[@]}") ;;
    long_summary_input | summary_input | ollama_reconnect) SOURCES=("${SUMMARY_SOURCES[@]}") ;;
    long_audio_extraction) SOURCES=(MeetingScribe/Services/AudioExtractor.swift MeetingScribe/Services/DiagnosticLogger.swift) ;;
    window_close_signal) SOURCES=() ;;
    *)
      echo "unknown check: $1 (./scripts/run_checks.sh --list で一覧を表示)" >&2
      exit 2
      ;;
  esac
}

run_check() {
  local name="$1"; shift
  sources_for "$name"
  echo "== check_$name"
  xcrun swiftc "${SWIFT_FLAGS[@]}" "scripts/check_$name.swift" ${SOURCES[@]+"${SOURCES[@]}"} -o "$BUILD_DIR/check_$name"
  "$BUILD_DIR/check_$name" "$@"
}

if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--list" ]]; then
    printf '%s\n' "${CHECK_NAMES[@]}"
  else
    run_check "$@"
  fi
  exit 0
fi

run_check pipeline_job_store
run_check recording_history_store
run_check skip_summary --no-ollama
run_check privacy_scrubber

# specs/*.fsl から生成した照合テストを、録画後ジョブの PipelineJobCoordinator と初回セットアップの InitialSetupFlow に対して実行する
echo "== spec_conformance"
swift test --package-path specs/conformance
