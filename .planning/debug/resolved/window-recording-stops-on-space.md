---
status: resolved
trigger: "特定のウィンドウを録画中にデスクトップを切り替えると、約2秒以内に録画が勝手に終了する。以前から発生している。"
created: 2026-07-24
updated: 2026-07-24
---

# Symptoms

- expected: 録画対象ウィンドウとは別のデスクトップ（Space）へ切り替えても録画が継続する
- actual: デスクトップ切り替え直後、約2秒以内に録画が終了する
- errors: エラー報告なし
- timeline: 以前から発生
- reproduction: 特定ウィンドウを選択して録画開始後、別のデスクトップへ切り替える

# Current Focus

- hypothesis: `pollWindowExistence` が現在のSpaceに表示中のウィンドウだけを取得し、別Spaceの録画対象を閉鎖済みと誤判定している
- test: 存在確認時にオフスクリーンのウィンドウも取得するよう変更し、Debugスキームをビルドする
- expecting: 別Spaceにある対象ウィンドウが存在確認結果に残り、録画が終了しない
- next_action: 完了
- reasoning_checkpoint: 症状の約2秒が `windowCheckInterval` と一致し、欠落時に `handleStreamStoppedUnexpectedly()` を直接呼んでいる

# Evidence

- timestamp: 2026-07-24
  observation: `windowCheckInterval` は2秒
  implication: 報告された終了タイミングと一致する
- timestamp: 2026-07-24
  observation: `pollWindowExistence` は `onScreenWindowsOnly: true` で取得した一覧に対象IDがなければ録画を終了する
  implication: Space切り替えで非表示になっただけのウィンドウを閉鎖済みと誤判定する

# Eliminated

- hypothesis: SCStream自体がSpace切り替えで停止している
  reason: アプリ独自の2秒間隔ポーリングと終了タイミングが一致し、明示的に予期しない停止処理を呼ぶ経路が存在する

# Resolution

- root_cause: 2秒間隔のウィンドウ存在確認が `onScreenWindowsOnly: true` を指定していたため、別Spaceへ切り替えた対象ウィンドウを閉鎖済みと誤判定していた
- fix: 存在確認に限り `onScreenWindowsOnly: false` とし、現在のSpaceに表示されていないウィンドウも存在判定に含めた
- verification: "TextEditの特定ウィンドウを録画し、別のTextEditウィンドウをフルスクリーン化して別Spaceへ移動。誤終了周期の2秒を超えて6秒待機後も録画中であることをUIで確認し、手動停止に成功。生成されたMP4はH.264映像（586x488）＋AAC音声、72.18秒、1,852,722 bytesとしてffprobe検証済み。テスト入口削除後の`MeetingScribe - Debug`ビルドも成功し、警告・エラー0件"
- files_changed: MeetingScribe/Services/RecordingService.swift
