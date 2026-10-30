# M09完了後：雑兵・魔導士の通常自動ジャンプ（2026-10-30、ADR-047）

## 対象と実装

既存EnemyWalkの通常追跡・周辺歩行・home帰還へ自動ジャンプを追加した。M09基本戦闘完了を維持し、今回の動きのユーザーF5確認は別に管理する。M10へ移行しない。開始HEADは50d9acb。開始時のEffekseer一時DLL削除はそのまま保持する。

従来の上昇→前進→着地は低い段差だけに限定。初期値では0.25mは歩行段差、0.5～1.0mは放物線ジャンプ。坂は従来のCharacterBody3D.move_and_slide・床／傾斜処理で歩く。画像は既存のWalk、サイズ／足元・方向管理を維持する。新しい画像・音声は追加しない。

通常移動の所有者はEnemyWalkのまま。内部Motion.WALK／STEP／JUMP／FALL／STRANDEDで通常歩行の進行だけを管理し、AIのCHASE／RECOVERY／RETURNと併用する。既存の戦闘DASH_APPROACH／DASH_RETURN・共有DashPath・主人公の状態や物理・命中判定には手を加えない。

## 軌道と安全性

- Jump Heightを離陸足元からの最高点H、Jump Takeoff Speedを初速vとして、ジャンプ専用重力g=v²/(2H)を計算する。位置は開始点＋水平速度×時間＋上方向(vt−gt²/2)。高さと跳び出しの速さを独立調整でき、二重のTween／重力制御は使わない。
- 段差への接触前に上面を探し、下降側の着地時刻と水平位置を計算する。平らな上面／全足元支持・最大上り高さ・home範囲を検査し、足元の連続した支持も検査する。既存の小さな継ぎ目補完は維持し、広い穴や崖の飛び越えには使わない。
- 離陸時に実地面があることを確認。全カプセルの軌道をnative test_moveで細かく掃引し、壁／天井を拒否する。放物線と検査用直線区間の差は0.5mm未満。飛行中も毎physics tickでmove_and_collideを使用する。
- 安全な離陸位置の狭い区間を飛ばさないよう、高い段差を検出した接近区間は歩行速度を最大1.5m/sに抑える。ジャンプ中は設定された水平速度。クールダウン中は安全な離陸位置で停止して待つ。
- 着地は実terrainと足元支持で確認し、他キャラの頭との衝突を着地扱いにしない。途中で地形が変わった場合は水平飛行を中止してFALLへ移り、通常重力で落下する。すべての床が消失した場合は落下を2秒で安全停止し、瞬間移動や空中での再ジャンプを行わない。
- クールダウンは着地から計測。ジャンプ中は通常AIの攻撃開始を保留し、明示的なWINDUP要求も拒否する。魔導士の詠唱状態では通常歩行／ジャンプを実行しない。
- 主人公が地上の敵を攻撃対象として保持している場合は従来どおり移動開始を止める。すでに離陸した敵には重力・衝突・着地を継続し、空中で静止させない。
- home帰還でも同じジャンプを使用する。ジャンプ後は実際に到達した場所に最も近い既知の帰路へ進め、飛び越した細かな歩行点へ戻ろうとする往復を防止する。

共通化に備えたscripts/combat/jump_arc.gdは純粋な軌道計算と全身掃引だけを担当する。入力・AI・ダメージや新しい攻撃状態は持たず、今回Playerの跳躍や戦闘DashPathへの割当は行わない。

## Inspector

Mainの敵ノード（TrainingEnemy系）を選択 → **Settings → Walk → Automatic Terrain Jump**。またはresources/enemies/melee_practice.tres／ranged_practice.tresのWalkを開く。個体差を持たせる場合はSettings／Walkを固有化または複製し、シーンまたはResourceを保存する。

| 表示項目 | 初期値 | Inspector範囲 | 意味 |
|---|---:|---:|---|
| Jump Enabled | ON | ON/OFF | 通常の自動ジャンプ |
| Walking Step Height | 0.30m | 0.10～0.40m、0.01刻み | ジャンプせず歩いて上る高さ |
| Jump Height | 1.10m | 0.40～1.50m、0.01刻み | 離陸点からの最高点 |
| Jump Takeoff Speed | 6.63m/s | 2～12m/s、0.01刻み | 上向き初速、ジャンプのテンポ |
| Jump Horizontal Speed | 3.0m/s | 0.5～6m/s、0.1刻み | 飛行中の水平速度 |
| Jump Cooldown Seconds | 0.80秒 | 0.10～3秒、0.05刻み | 着地から次の離陸まで |

通常歩行のMaximum Step Up／Down（既定各1.05m）、坂45度、床支持／home範囲も引き続き適用する。高さ設定だけを上げても、最大段差や安全な着地場所を超えて跳ばない。高さ・速度の組み合わせによって着地場所が確保できない場合も安全に停止する。通常歩行GravityとClimb Speedは従来の歩行／下降用。攻撃の踏み込み速度／時間・帰還設定とは独立している。

## 変更ファイル

- scripts/combat/jump_arc.gd（新規）とGodot UID
- scripts/enemies/enemy_walk.gd、enemy_walk_settings.gd、practice_enemy.gd
- tests/enemy_auto_jump.gd（新規）とGodot UID、tests/enemy_terrain.gd（通常ジャンプの初速を含む変位上限）
- AGENTS.md、docs/DEVELOPMENT_STATUS.md、08_DECISIONS.md、10_SYSTEM_SPEC_GODOT.md、11_CODEX_IMPLEMENTATION_PLAN.md、12_TEST_PLAN.md、14_TARGET_DASH_COMBAT_SPEC.md、本書

Player・共有武器／DashPath／MeleeSweep・既存の攻撃Resource、画像／音／シーン／地形・Effekseerは変更対象外。

## 検証

Godot 4.7.2.stable.official.ed1daf0bf／Compatibility／GTX 1080。物理60Hz、実描画上限60／30fps。**12種類14条件すべてPASS・終了0、実行ログにScript／Shader／参照エラー・警告なし。** 観測assertion件数は物理と描画のフレーム対応で変動する。

| 検査 | 結果 |
|---|---|
| enemy_auto_jump／60fps上限 | 5837 assertions PASS |
| enemy_auto_jump／30fps上限 | 2956 assertions PASS |
| enemy_auto_jump／別プロセスreload | PASS |
| enemy_terrain | 4356 assertions PASS |
| enemy_walk_facing | 694 assertions／208移動サンプル PASS |
| enemy_tactics | 1242 assertions PASS |
| enemy_sword_combat | 445 assertions PASS |
| enemy_jump_strike | 547 assertions PASS |
| mage_cast_commitment | 29 assertions PASS |
| mage_fire_feedback | 33 assertions PASS |
| m08_defense | 防御・方向帰還／安全性・入力と状態解除 PASS |
| m07_chain | 3体連撃・照準／帰還・無効対象切替 PASS |
| in_place_attack | 3273 assertions PASS |
| m09_startup | 実mainの敵攻撃／左攻撃・右防御／UI切替・リセット PASS |

新規検査は両敵の0.25m歩行・0.5／1m各1ジャンプとhome帰還、homeが1m高所にある場合の上り帰還、実TestArenaの坂（ジャンプ0回）と3段階段（ジャンプあり）を確認。通常移動を分離して観測するため、この地形fixtureだけ攻撃開始距離を短くしている。本番の剣／魔法の射程は変更しておらず、射程内の魔導士は従来どおり停止して攻撃する。

初期ジャンプの実最高点は約1.099977m、軌道誤差は約0.000100m。初速・水平速度・高さを変更した別設定でも実最高点1.2mと解析軌道への追従を確認した。連続1m段差で2回だけ跳び、2回目は1回目の着地から0.8秒以上待機することも確認。低天井・home外・高すぎる段差・穴・空中再離陸を拒否し、着地点の動的消失は落下／全床消失は安全停止、地上保持と空中保持の違い・明示WINDUP拒否・詠唱中停止も検査した。

剣の同期／照準・回避猶予・主人公ジャンプ中の命中、雑兵の戦闘後歩行／向き、魔導士の確定詠唱／Fire3・大きな炎被弾／Guard貫通と10秒待機、主人公のGuard／方向帰還／3連撃／近距離省略、実mainの操作を回帰した。魔導士の回復時間は約10.0167秒・発射間隔11.15秒で従来値を維持。

同じソースの検証コピー `.godot/mage_fire_validation/` で実行し、開いているユーザーのエディター／native DLLと分離。変更した実装／検査6ファイルと新規UID2ファイルを元プロジェクトとバイト照合。最終headless editor importは終了0・エラー／警告なし、git diff --check合格。両敵の最高点キャプチャを目視し、既存Walk画像とドット表示を確認した。F5の実操作／動き全体の自然さは未確認として残す。

結果一覧 `.godot/autojump_results.json`、実行ログ `.godot/autojump_final_*.log`、最終import `.godot/autojump_import_final.log`。軌道計測は検証コピー内 `.godot/enemy_auto_jump_metrics.json`、最高点画像は同 `.godot/auto_jump_kind0.png`／`auto_jump_kind1.png`。これらはGit対象外。再現は `tools/validate_mage_fire.ps1 -ImportOnly` で同一ソースを準備し、Godotの `--path .godot/mage_fire_validation --script res://tests/enemy_auto_jump.gd`、追加引数 `-- --fps30`／`-- --reload` を順番に実行する。各回のAPPDATA／LOCALAPPDATAは同じworkspace内 `.godot/mage_runtime_appdata` を使用する。

## ユーザーF5確認（未実行）

1. F8で停止→F5。練習敵の切替で雑兵／魔導士を選び、坂の上り下りと0.25／0.5／1.0m階段へ誘導する。0.25mは歩行、0.5～1mは必要な接近時だけ跳び、Walk画像と向きが自然なことを確認。
2. 段差上へ主人公を移動し、敵が移動を必要とする距離へ離れる。すでに攻撃射程内なら、段差を登らず剣／魔法を使う既存仕様は維持している。
3. home範囲（雑兵9m／魔導士10m）の外へ逃げる。追跡を諦め、坂・階段を通ってhomeへ帰還すること。上りの必要な帰還も確認。
4. 壁／低い天井・崖では無理に跳ばず停止し、ジャンプ中に地形をすり抜けたり、空中で予告／攻撃を始めたりしないことを確認。
5. Inspectorの高さ・初速・水平速度・クールダウンを一つずつ変更→保存→F5。再起動後も設定が残ること、Q/Eの4方向で表示が正常なことを確認。
6. 雑兵の赤い攻撃態勢／Fire1・踏み込み／剣／帰還・左右移動、魔導士の魔法陣／炎弾／防御貫通・待機、主人公の左攻撃／J・右防御／I・Space・方向帰還・3連撃を確認。

F5実操作の見た目／自然さ、任意の複雑地形・多数の敵・動的な帰路封鎖・長時間性能は未確認。直線の接近と既知の帰路を使う方式で、任意迷路の迂回やNavMeshは今回追加しない。
