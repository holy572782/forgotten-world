# 06 技術選定とGitHub運用

## 技術は未確定
候補：Godot 4系、Unity等。エンジン選定時は (1) 2Dスプライト＋3D地形 (2) 3D物理と入力 (3) マルチプラットフォーム展開 (4) ツール・アセット運用 (5) Codexでの自動テストと編集 (6) ライセンス を比較する。以前のRPGツクールMZプロジェクトとは**独立**。

## 推奨リポジトリ初期設定
- 初期段階はGitHubの**Private**リポジトリ。
- デフォルトブランチ `main`、機能追加用 `feature/<topic>`、修正用 `fix/<topic>`。
- 作業単位はIssue、変更単位はPull Request。`main`に直接大量変更を入れない。
- 大きなバイナリ（画像原本、音声、3D制作元）はGit LFS利用を検討。
- GitHub Actionsのビルド／テストは、エンジン決定後に追加する。架空のCIは置かない。

## 初期登録手順（既存フォルダで実行）
```bash
git init
git add .
git commit -m "docs: initialize world bible and production rules"
git branch -M main
git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPO.git
git push -u origin main
```
`YOUR_ACCOUNT/YOUR_REPO`は必ず自身の実際のリポジトリに置き換える。初回pushの前にGitHub上で空リポジトリを作る。`git`利用やGitHub認証は別途必要。

## セキュリティ
APIキー・パスワード・個人情報・素材購入履歴や未許諾の原本データはGit管理しない。`.env`を除外する。公開切り替え前に履歴を確認する。

## 設計変更フロー
1. Issueに背景、変更目的、受け入れ条件を書く。
2. 仕様の正本と矛盾しないかチェック。
3. 仕様変更なら `08_DECISIONS.md` に追記。
4. PRを作り差分・テスト結果を確認。
5. マージ後に必要なリリースノートを更新。

## バックアップ
GitHubは履歴管理であり唯一のバックアップにしない。原本アセットの別ストレージ保管と定期的な復元テストを推奨。OneDriveなど同期フォルダでのGit二重操作は競合しやすいので避ける。
