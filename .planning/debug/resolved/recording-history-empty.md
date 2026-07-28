---
status: resolved
trigger: "今、インストールして試してみて、無事終わったけど、録画履歴に何も表示されてない"
created: 2026-07-28
updated: 2026-07-28
---

## Symptoms

- expected: 録画後処理が完了すると、録画履歴に完成した録画が1件表示される
- actual: 録画後処理は正常完了したが、録画履歴が空のまま
- errors: 画面上のエラー報告なし
- timeline: Homebrewでインストールした現行リリースを初めて試した録画で発生
- reproduction: 録画を開始・終了し、文字起こし・要約・保存の完了後に録画履歴を確認する

## Current Focus

- hypothesis: 履歴ScrollViewが最大高さだけを持ち、メニューパネル内のレイアウト圧縮で高さ0になっている
- test: 履歴リストに件数連動の最小高とレイアウト優先度を与え、ビルドと実データ読込を検証する
- expecting: 履歴が1件以上あれば最低1〜2行分の高さが常に確保される
- next_action: release the verified fix in the next app version
- reasoning_checkpoint:
- tdd_checkpoint:

## Evidence

- timestamp: 2026-07-28T17:03:02+09:00
  finding: 製品版ログに「録画履歴を保存 id=74B45BD2-C6A7-4F0A-99FB-53A6149060BB」と記録
- timestamp: 2026-07-28T17:03:03+09:00
  finding: 保存直後の製品版ログに「録画履歴を読込 count=52」と記録
- timestamp: 2026-07-28T17:03:02+09:00
  finding: 今回のジョブIDと一致する履歴JSONが存在し、録画・文字起こし・要約の完成パスを保持
- timestamp: 2026-07-28
  finding: RecordingHistoryViewのScrollViewはmaxHeightのみでminHeightがなく、高さ0まで圧縮可能

## Eliminated

- hypothesis: 履歴JSONの保存失敗
  reason: 今回のジョブIDのJSONと保存成功ログを確認
- hypothesis: 履歴JSONのデコードまたは再読込失敗
  reason: 保存直後およびその後のログで52件の読込を確認

## Resolution

- root_cause: 履歴ScrollViewに最大高さしかなく、MenuBarExtra内で他セクションと競合すると表示高が0まで圧縮される
- fix: 件数に応じた最小高（最大80pt）、理想高・最大高180pt、layoutPriorityを設定
- verification: Debug/Releaseビルド成功。録画履歴ストア回帰テスト、旧パイプラインジョブ互換性テスト成功。製品版実データは52件読込済み。
- files_changed: MeetingScribe/Features/MenuBar/MenuBarView.swift
