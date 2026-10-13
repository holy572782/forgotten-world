# Codex 実装計画 v0.2.0
2026-10-13 / 技術: Godot 4.x / GDScript（初期案）

## 0. 初回の指示
1. `AGENTS.md` と `docs/08_DECISIONS.md`, `docs/10_SYSTEM_SPEC_GODOT.md`, `docs/12_TEST_PLAN.md` を読む。
2. `project.godot`が存在するか確認。ない場合は最小プロジェクトを生成する。既存のゲーム資産や世界設定ファイルを勝手に削除しない。
3. Godot実行バイナリの有無とバージョンを報告し、利用版を`README.md`に記録（最新版と決めつけない）。
4. 変更前に担当チケット、実装範囲、手動確認方法を短く説明。コミット前に差分と新規ファイルを確認。

## 1. リポジトリ構造（推奨）
```text
project.godot
AGENTS.md
README.md
docs/
  10_SYSTEM_SPEC_GODOT.md
  11_CODEX_IMPLEMENTATION_PLAN.md
  12_TEST_PLAN.md
scenes/
  main.tscn
  test_arena.tscn
  player/player.tscn
  enemies/training_enemy.tscn
  ui/hud.tscn
scripts/
  player/player_controller.gd
  player/player_combat.gd
  camera/camera_rig.gd
  combat/health_component.gd
  combat/hitbox_component.gd
  enemies/enemy_ai.gd
  ui/hud.gd
resources/
  player_movement.tres
  combat_balance.tres
assets/
  sprites/
  environments/
  audio/
tests/
```
Godot固有のuid等の自動生成物は実際の動作確認後にGit管理方針を決める。

## 2. マイルストーン / 完了条件
| ID | 実装内容 | 依存 | 完了条件 |
|---|---|---|---|
| M00 | Godot空プロジェクト/入力/README | なし | 起動、ヘッドレス読み込みが成功 |
| M01 | 3Dテスト地形と当たり判定 | M00 | 平地・壁・坂・段差がある |
| M02 | 2Dスプライト+CharacterBody3D移動 | M01 | 8方向移動の速度一定、3D衝突 |
| M03 | ジャンプ/落下/着地 | M02 | 連続ジャンプせず段差越え可能 |
| M04 | 斜め見下ろし追従カメラ+水平回転 | M02 | 回転後も入力方向が画面基準 |
| M05 | HP/攻撃ゲージ/HUD | M02 | 時間ベースで0→100回復 |
| M06 | 1段攻撃+ヒット判定+ダメージ | M05 | 1振り1対象1ヒット、ゲージ反映 |
| M07 | 3段コンボ+バッファ | M06 | 指定時間内連続3段、タイムアウトリセット |
| M08 | 回避+無敵+クールダウン | M06 | 無敵内のみ被ダメージ無効 |
| M09 | 敵AI/予兆/攻撃/死亡 | M08 | シームレスで1対1の戦闘成立 |
| M10 | 小ボス+短い洞窟+達成画面 | M09 | 10〜15分プレイの導線 |
| M11 | 保存/ロードとエラー処理 | M10 | 再起動後必要状態復元 |
| M12 | 品質修正と性能確認 | M11 | 受入テスト・数値計測・既知課題記録 |
| M13 | 残響アクション技術試作（任意） | M12 | 一時復元橋が安全に機能 |

## 3. 実装上の責務分離
- `PlayerController`: 移動/ジャンプのみ。HP・攻撃判定を直書きしない。
- `CameraRig`: カメラ回転・追従・衝突補正。プレイヤーはカメラ水平方向だけ参照。
- `PlayerCombat`: 攻撃ゲージ/コンボ/回避要求。状態機械へのイベント。
- `HitboxComponent`: 有効時間と当たったインスタンスの重複排除。
- `HealthComponent`: HP・被ダメージ・死亡シグナル。
- `EnemyAI`: 状態遷移と攻撃予兆、対象選択。
- `HUD`: シグナルの表示のみ。戦闘の内部状態をUIから変更しない。
- 戦闘値/移動値はResourceまたは一元定義。グローバルSingleton乱用禁止。

## 4. PR / チケット運用
- 基本1マイルストーンを小さなIssueに分割し、1PRにつき1つの検証可能な変更。
- 推奨ブランチ例 `feature/m02-player-movement`、`fix/m08-invulnerability`。
- PR本文に: 目的、変更ファイル、操作確認手順、実行した検証、未実施、スクリーンショット(必要な時)、既知の問題。
- `main`へマージする前に `docs/12_TEST_PLAN.md` の対応受入項目を確認。
- CodexはGitHubへのpush/PR作成/既存ファイルの大規模削除を指示なく勝手に行わない。

## 5. Codexへ貼り付ける最初の依頼
```text
このリポジトリのAGENTS.md、docs/08_DECISIONS.md、docs/10_SYSTEM_SPEC_GODOT.md、docs/11_CODEX_IMPLEMENTATION_PLAN.md、docs/12_TEST_PLAN.mdを読んでください。
今回はM00のみ実装してください。Godotのインストール状況とバージョンを確認し、必要最小限のproject.godot、起動可能なmainシーン、InputMap、READMEの起動手順を整備してください。
物語・世界設定・ゲームバランスを決め直さないでください。作成・変更ファイル一覧、動作検証の結果、未実施事項を報告してください。Gitのcommit/pushはまだ行わないでください。
```

## 6. 完成の定義
「コードを作った」ではなく、Godotで起動でき、プレースホルダーの3D地形上で動作し、対応する手動受入項目を確認できた状態を完成とする。環境上Godotを実行できない場合は未検証と明記して次の手動確認手順を記載。
