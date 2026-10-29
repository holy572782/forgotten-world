# Effekseer for Godot4 — 導入元

- 導入日: 2026-10-29
- 公式安定版: **1.80.5.1**（Godot 4.7向けスクリプト修正を含む）
- リリース: https://github.com/effekseer/EffekseerForGodot4/releases/tag/1.80.5.1
- 配布物: https://github.com/effekseer/EffekseerForGodot4/releases/download/1.80.5.1/EffekseerForGodot4-180_5_1.zip
- ZIP SHA256: `1a4987f748156b4707659e9b96b9e28dad42614e2862dc63ec0da8408e089cb6`
- 対応ソース: `29361d13afe24eb8acacf44695e8b8ac3f1aa33e`
- 許諾: 同梱 [LICENSE](LICENSE)（MIT、Copyright (c) 2020 Effekseer）を保持。

配布物の `addons/effekseer/` を全プラットフォーム分そのまま配置し、ルートのLICENSEを本フォルダーへ複製。コードとネイティブバイナリは未改変。Godotによる `.import` メタデータ更新と `.gd.uid` 生成、本書の追加は導入先の管理差分。全体は約153MiB、最大ファイルはiOS用 `libgodot-cpp.a`（80,487,688 bytes）。`.godot/` 内の取得ZIP・展開元はキャッシュであり実行時に不要。

検証対象はWindows x86_64 / Godot 4.7.2 / Compatibility。他OS用ライブラリの同梱は、それらの動作確認や最終対象OSの決定を意味しない。更新時は互換性・ライセンスを確認し、本書と [導入記録](../../docs/effekseer_integration_audit.md) を更新する。
