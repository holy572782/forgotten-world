> **M07更新（2026-10-19、実装・自動検証済み／手動待ち）**: 今回承認されたM07指示・武器別コンボ方針は末尾のM07節とADR-009を優先。初期武器の3段とストック上限3は別設定。M06の2026-10-18試作完了記録は維持。過去の未着手・ゲージ維持の記述は当時の履歴。
> **M06実装依頼による更新（2026-10-18）**: 今回は対象選択・踏み込み・単発命中・攻撃終了直後の自動帰還を実装。本文の「M06でストックへ移行」は今回の明示指示でM07へ延期し、M05ゲージ・HP・HUDを保持する。ストック／コンボ／防御／ステップは未実装。M06の実装制約・操作・検証はREADME末尾とDEVELOPMENT_STATUSの最新ログを参照。以下の旧工程記述／原文はこの注記を優先して読む。
# Codex 実装計画 v0.3.0
2026-10-17 / 技術: Godot 4.x / GDScript（初期案）

## 0. 初回の指示
1. `AGENTS.md` と `docs/08_DECISIONS.md`, `docs/10_SYSTEM_SPEC_GODOT.md`, `docs/12_TEST_PLAN.md`, `docs/14_TARGET_DASH_COMBAT_SPEC.md`, `docs/DEVELOPMENT_STATUS.md` を読む。
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
ADR-008によりM06〜M12を改訂。M00〜M05の実装・検証記録を保持し、M05は試作範囲完了。M06は2026-10-18の最終ユーザー手動検証と既存自動／実描画検査により試作範囲完了。次工程はM07「攻撃ストック・最大3段コンボ・入力予約1個」（個数HUD移行を含む）。M07は実装・自動検証済みでユーザー操作確認待ち。M08以降は未着手。ゲームパッド・長時間性能・複雑地形・大型ボス等の未検証は継続。下表の後続工程は計画であり実装完了を意味しない。

| ID | 実装内容 | 依存 | 完了条件 |
|---|---|---|---|
| M00 | Godot空プロジェクト/入力/README | なし | 起動、ヘッドレス読み込みが成功 |
| M01 | 3Dテスト地形と当たり判定 | M00 | 平地・壁・坂・段差がある |
| M02 | 2Dスプライト+CharacterBody3D移動 | M01 | 8方向移動の速度一定、3D衝突 |
| M03 | ジャンプ/落下/着地 | M02 | 連続ジャンプせず段差越え可能 |
| M04 | 斜め見下ろし追従カメラ+水平回転 | M02 | 回転後も入力方向が画面基準 |
| M05 | HP/攻撃ゲージ/HUD | M02 | 時間ベースで0→100回復 |
| M06 | 対象選択・踏み込み・単発命中・自動帰還 | M05 | 有効なマーク／体／指定部位を選択、1斬撃1対象1ヒット、攻撃終了後の安全帰還、壁貫通なし。M05ゲージ／HUD保持（C01〜C03・C05・C08） |
| M07 | 攻撃ストック・武器別コンボ（初期片手剣3段）・予約1個・個数HUD | M06 | 武器上限とストック上限を独立管理、1入力1斬撃、予約時非消費、安全帰還、多重消費／ヒットなし。1／2／3／5段Resource差し替え試験とユーザー手動確認（C04） |
| M08 | 対象向きの方向ステップ・防御・割込み | M07 | 押下1回で1ステップ、長押し連続不可、防御中断・追撃／帰還成立。帰還中割込みと短い回避判定の採否を検証（C06・C07） |
| M09 | 敵AI・予兆・攻撃開始距離と実判定範囲の分離 | M08 | 1対1で接近／攻撃／帰還中にも敵が反撃し、被弾・防御・回避・死亡が成立（C07・C11） |
| M10 | 洞窟・小ボス・10〜15分デモ・大型敵の視認性 | M09 | 敵全体と主人公を認識でき、攻撃地点と安全な帰還先が成立。ボス用フレーミングは比較後判断 |
| M11 | 保存／ロード・装備武器とストックの保存方針 | M10 | 保存対象／初期化方針を記録、再起動・破損／旧版から安全復帰。戦闘中セーブ不可を維持 |
| M12 | 品質・性能・新戦闘と既存操作の回帰 | M11 | 30/60fps、入力遅延、画像遷移、壁／坂／空中、複数敵、カメラを検証し残件記録（C01〜C12） |
| M13 | 残響アクション技術試作（任意） | M12 | 一時復元橋が安全に機能 |

### M06の旧小Issue案（仕様統合時の履歴、最新範囲は冒頭注記）
番号順に分け、各Issueで検証する。今回は文書統合のみ。

1. 対象検出・入力整理: 円形範囲／マーク、生存・壁・高低差・経路・着地判定、最前面対象、UI競合を検証（C01）。右クリックは現行dodgeと競合。J／左クリック・K・パッドを無断廃止せず、状態別の割当方針を記録する。
2. ストック移行: M05のAttackGaugeComponent／AttackPreview接続を正式な攻撃受理とストックへ置換。初期3、1受理1消費、0拒否、FREEのみ1.5秒ごと回復は仮値。HUDを個数＋数字へ変更。旧T05の成果を保持しT05-S／T06で新仕様を検証。ゲージ量による威力倍率は導入しない。
3. 踏み込みと単発命中: return_anchorを3D保存、既存player_jump.pngを仮使用、player_attack.pngで1斬撃1ヒット（C02・C03・C09）。画像自体は変更せず、M05のnull／範囲確認を保持する。
4. 安全帰還・統合: 入力停止後に開始位置へ帰還、塞がれた場合は安全な最寄りへ移動し差を表示。対象喪失・死亡・シーン終了で状態を解放（C05・C08・C11・C12）。接近／帰還は無敵化しない。実敵の反撃評価はM09で行う。

M07の複数攻撃・予約、M08の防御／ステップ、M09の敵AIをM06で完成扱いしない。キャンセル時の消費／返却、回復の端数、空中開始条件など未確定の境界は各Issueで仮方針を明示して検証する。

## 3. 実装上の責務分離
- `PlayerController`: 移動/ジャンプのみ。HP・攻撃判定を直書きしない。
- `CameraRig`: カメラ回転・追従・衝突補正。プレイヤーはカメラ水平方向だけ参照。
- `PlayerCombat`: 対象選択・踏み込み・単発攻撃・予約・防御／ステップ・帰還の状態遷移を管理。通常移動との競合を制御する。
- `AttackStockComponent`（M07新設推奨）: 消費・FREE時回復・上下限・変更通知。実値は個体別、設定はResource。
- `Targetable`: 選択可否・攻撃位置・click_collider_pathsによる体／部位のクリック形状を所有。練習敵は1対象。大型敵は部位ごとに分離可能、実ボスの実装は後続。死亡／喪失時は安全に中止。
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
## M07：攻撃ストックと武器別コンボ（2026-10-19）

- 最大3段は初期武器「片手剣」の試作設定で、ゲーム全体の固定上限ではない。WeaponData.max_combo_hitsとAttackStockSettings.maximumは独立。追加攻撃には残段数と必要ストックの両方が必要。武器名による分岐は設けない。
- WeaponDataはscripts/combat/weapon_data.gd、初期Resourceはresources/weapons/one_handed_sword.tres。weapon_id／display_name／max_combo_hits／base_damage／attack_range／combo_input_window／stock_cost_per_hitを使用。攻撃速度倍率とanimation_profileは将来用、M07では未使用。威力10・範囲5mをTargetDashSettingsから移し所有者を一本化した。
- Player/TargetDash.equipped_weaponから取得・設定する。FREE（Idle）のみ参照差し替え可能。戦闘開始時にデータを複製して一巡中の値を固定する。Resourceの共有原本に戦闘進捗を書き戻さない。装備UI・入手・インベントリ・保存・成長・特殊消費は後工程。
- ストック設定はresources/attack_stock_settings.tresとscripts/combat/attack_stock_settings.gd。初期3／最大3／FREEで1.5秒ごと1回復は試作値。AttackStockComponentが個体別実値を保持。戦闘・入力待ち・帰還・HP0では回復しない。回復禁止へ入ると端数を破棄し、帰還後は0秒から再開する仮ルール。
- 右クリックで対象選択、接近中・攻撃中・終了後の猶予中に追加右クリックで次の1斬撃を予約。予約はboolで最大1個、登録時非消費。接近中は未消費の初段分も差し引いて可否判定。実斬撃の再生開始成功時だけ消費しattack_acceptedを通知、拒否はattack_rejectedで通知。開始済み斬撃の中断は返却しない仮ルール。
- 1斬撃ごとにattack_idを増やし命中済みフラグを初期化。既存48pxアニメを段数によらず再利用し、中央コマで1回だけダメージ。原本PNG・フルビルボード・影・M04方式Bは維持。
- 入力なしではアニメ終了後0.5秒（WeaponDataの試作値）で帰還。上限・残量不足では最終アニメ終了後帰還。対象死亡／消失／移動・経路遮断は予約を破棄しM06の安全帰還へ。アニメ終了通知が来なければTargetDashSettings.attack_timeout（2秒）で帰還。プレイヤーHP0は既存cancelで停止、シーン退出時も予約を解放する。
- J／左クリック／パッド西の旧プレビューはデバッグビルドのFREE時のみ保持し、ダメージ・ストック消費なし。本編シーンから旧AttackGaugeComponent／AttackPreviewを外した。旧M05ゲージ試験は検査専用アダプターとtests/fixtures/m05_legacy_hud.gdで再現し、T05成果を保持する。
- HUDは個数アイコン・数値、控えめな回復進捗、戦闘状態（WAITが追加入力猶予）・段数・予約・帰還誤差を読み取り表示。HP／FPS／Yawも保持。
- tests/fixtures/weapon_1.tres／weapon_2.tres／weapon_5.tresは大槌／大剣／短剣相当の検査専用例。正式ラインナップではない。槍4段も同じデータ方式で追加可能。武器例、威力、攻撃速度その他数値は正式なバランスとして未確定。
- 受入はtests/m07_combo.gdの武器×ストック行列、予約・消費・回復・例外処理とM00〜M06回帰、実描画、ユーザーF5確認で判定。手動確認前はM07を正式完了にしない。M08防御・ステップや敵AIは未実装。
