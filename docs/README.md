# Meeting Scribe LP

会議議事録アプリ「Meeting Scribe」のダウンロード用ランディングページ。

`index.html` をブラウザで開くか、静的サーバーで配信して表示できます。

## GitHub Pages と appcast

リポジトリの **Settings → Pages** で **Build and deployment** の Source を **GitHub Actions** にすると、`main` へのプッシュで `.github/workflows/deploy-pages.yml` が走り、`docs/` 以下がサイトのルートとして公開されます。

Sparkle 用の appcast URL: `https://shu-pf.github.io/meeting-scribe/appcast.xml`（このディレクトリの `appcast.xml`）

`./scripts/notarize_and_dmg.sh` が `docs/appcast.xml` を直接更新するので、リリース後はこのファイルをコミットしてください。
