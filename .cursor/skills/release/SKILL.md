---
name: release
description: MeetingScribeのリリースを作成する。バージョン決定、project.pbxproj更新、Xcodeビルド誘導、公証・DMG作成、コミット、タグ付きGitHubリリース作成までの一連のワークフローを実行する。Use when the user mentions release, deploy, version bump, or shipping a new version.
---

# MeetingScribe リリースワークフロー

## 概要

macOSアプリ MeetingScribe の新バージョンをリリースするための手順。
リポジトリ: `shu-pf/meeting-scribe`

## ワークフロー

チェックリストをコピーして進捗を追跡する:

```
リリース進捗:
- [ ] Step 1: バージョン決定
- [ ] Step 2: project.pbxproj 更新
- [ ] Step 3: Xcode Release ビルド（ユーザー操作）
- [ ] Step 4: 公証 & DMG 作成
- [ ] Step 5: 変更をコミット
- [ ] Step 6: git push
- [ ] Step 7: GitHub リリース作成
```

### Step 1: バージョン決定

1. 最新タグを取得: `git tag --sort=-v:refname | head -1`
2. 前回リリース以降の変更を確認: `git log --oneline <最新タグ>..HEAD`
3. 変更内容をもとにバージョンアップの種類をユーザーに提案する:
   - **メジャー** (X.0.0): 破壊的変更、大幅な機能刷新
   - **マイナー** (x.Y.0): 新機能追加、大きな改善
   - **パッチ** (x.y.Z): バグ修正、小さな改善
4. ユーザーに確認し、新バージョン番号を確定する

### Step 2: project.pbxproj 更新

`MeetingScribe.xcodeproj/project.pbxproj` 内の `MARKETING_VERSION` を新バージョンに更新する。
Debug と Release の両方のビルド設定に存在するため、両方を更新すること。

```
MARKETING_VERSION = X.Y.Z;
```

### Step 3: Xcode Release ビルド

ユーザーに以下を依頼し、完了を待つ:

> Xcode で MeetingScribe を **Release** スキームでビルドしてください。
> Product → Build (⌘B) で、スキームが Release になっていることを確認してください。
> ビルドが完了したら教えてください。

**ユーザーがビルド完了を報告するまで次のステップに進まないこと。**

### Step 4: 公証 & DMG 作成

`APP_VERSION` 環境変数に新バージョンを設定してスクリプトを実行する:

```bash
APP_VERSION=X.Y.Z ./scripts/notarize_and_dmg.sh
```

このスクリプトは以下を自動で行う:
- Release ビルドを dist/ にコピー
- コード署名（hardened runtime）
- Apple 公証の提出・待機
- DMG 作成 (`dist/MeetingScribe.dmg`)
- DMG の公証
- `docs/appcast.xml` の生成（Sparkle 自動更新用）

### Step 5: 変更をコミット

生成・更新されたファイルをすべてコミットする。主な対象:
- `MeetingScribe.xcodeproj/project.pbxproj`
- `docs/appcast.xml`
- `dist/` 配下の成果物（.gitignore の設定に注意）

コミットメッセージ例:
```
Release vX.Y.Z
```

### Step 6: git push

```bash
git push origin main
```

### Step 7: GitHub リリース作成

タグ付きリリースを作成し、DMG を添付する:

```bash
gh release create vX.Y.Z dist/MeetingScribe.dmg --title "vX.Y.Z" --generate-notes
```

`--generate-notes` で前回リリースからの変更履歴が自動生成される。

## 重要な注意事項

- `.env` に公証用の環境変数（`NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD`, `NOTARY_IDENTITY`）が設定されている必要がある
- `create-dmg` が Homebrew でインストール済みであること
- Sparkle の `generate_appcast` が利用可能であること（Xcode の SPM で Sparkle を解決済み）
