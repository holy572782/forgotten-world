# M09完了後：ジャンプ中の雑兵攻撃・地面基準の経路判定

2026-10-29／ADR-040。M09基本戦闘完了を維持し、今回の修正はユーザーF5確認待ち。M10へ移行しない。commit／push未実行。

## 開始時と原因

開始HEAD `00c9d9b`、作業ツリークリーン。AGENTS・開発状況・08／10／11／12／14・最新M09監査、practice_enemy／dash_path／melee_sweep／weapon_dataと関連Resource／テストを照合。

予告中の再計画で空中のplayer.global_positionをPath.strike_clearへ渡していたため、supportedの平坦な足場条件（floor_tolerance 0.04m）で失敗していた。また、共有片手剣の命中許容高さ0.3mは通常ジャンプの最高点より低い。経路の不成立と剣が届かないことを分離して修正した。

## 修正

- 新しいPath.ground_belowは対象のXZからterrain layer 1へ下向きrayを行い、実際の地面のYを取得する。足元の0.05m上から既定2m下まで検索し、未検出／非平坦な面はVector3.INFで不許可。仮の敵高さへ置換しない。
- 武器を使う近接計画だけが地面座標を既存Path.strike_clearへ渡す。元の視線・全身掃引・全経路の5点足場検査・壁接触の上限2mm補正は変更しない。実際の高台や低障害物・穴も引き続き不許可。
- 予告のaimed_positionは実際の3D座標を追跡したまま。予告終了0.9秒で固定、固定後命中まで最低0.45秒、固定後の非追尾を維持する。踏み込み先と近距離省略は地面基準で計算し、命中だけは実際の高さに対して既存Sweep.containsを使う。
- EnemyAttackDataの既存hit_height_toleranceを再利用し、override_weapon_hit_heightを追加。雑兵だけtrue／1.4mを保存する。既存snapshotで複製済みの敵用Weaponへ反映し、共有の主人公Weapon 0.3mを変更しない。
- target_ground_probe_depthを命中高さとは独立させた。小型敵向けに命中高さを下げても、通常ジャンプを経路異常とせず、攻撃継続＋高さによる空振りとできる。
- 魔導士のweapon未指定PROJECTILE・3D弾は既存のまま。主人公・ダメージ計算・入力／コンボ／方向帰還／防御・赤点滅／Fire1／画像／SE／撃破演出・雑兵の帰還後歩行は変更していない。

## Inspector

FileSystemで `resources/enemies/melee_attack.tres` を選択する（雑兵のEnemy Settings → Attackと同じResource）。保存後、次の攻撃シーケンスのsnapshotへ反映する。

| 項目 | 雑兵の値 | 範囲／意味 |
|---|---|---|
| Override Weapon Hit Height | true | 敵専用の高さを使う。既定falseは元の武器値を継承 |
| Hit Height Tolerance | 1.4m | 上下の絶対高低差、0.01〜10.0m／刻み0.01。共有主人公は0.3mのまま |
| Target Ground Probe Depth | 2.0m | 足元の地面検索深さ、0.1〜10.0m／刻み0.1。命中高さとは独立 |

将来は敵種別のAttack Resourceを複製して個別設定する。より高い跳躍に対応する場合は検索深さも別調整する。検索範囲外／地面なしは安全に不許可とする。飛び道具へこの剣の高さ設定を適用しない。

## 変更ファイル

実装：`scripts/enemies/practice_enemy.gd`、`scripts/enemies/enemy_attack_data.gd`、`scripts/combat/dash_path.gd`、`resources/enemies/melee_attack.tres`。

検査：新規 `tests/enemy_jump_strike.gd` とGodot生成の同名 `.gd.uid`。

記録：`AGENTS.md`、`docs/DEVELOPMENT_STATUS.md`、`docs/08_DECISIONS.md`、`docs/10_SYSTEM_SPEC_GODOT.md`、`docs/11_CODEX_IMPLEMENTATION_PLAN.md`、`docs/12_TEST_PLAN.md`、`docs/14_TARGET_DASH_COMBAT_SPEC.md`、`docs/m09_enemy_sword_combat_audit.md`（旧高さ仕様への追記）、本書。

melee_sweep／weapon_data／共有武器Resource／Player・画像／音声／シーンは非変更。

## 自動検査

Godot 4.7.2.stable.official.ed1daf0bf、Compatibility／GTX 1080、実描画のfps上限60／30。物理更新数に依存する観測assertionの件数は実行条件で変動する。12スクリプト・14条件すべてPASS、終了0。実行ログ `.godot/jump_enemy_*.log`、一覧 `.godot/enemy_jump_results.json`、計測 `.godot/enemy_jump_metrics.json`（ローカルの再生成可能な検査記録、Git対象外）。

| 検査 | 結果 |
|---|---|
| enemy_jump_strike：60／30fps上限 | PASS、543／297項目 |
| enemy_jump_strike：別プロセス--reload | PASS |
| enemy_tactics | PASS、1238項目 |
| enemy_sword_combat | PASS、445項目 |
| enemy_followup | PASS、221項目 |
| m09_enemy_dash | PASS、171項目 |
| m09_timing／m09_startup | 各PASS |
| m08_defense／m07_chain | 各PASS |
| in_place_attack | PASS、3274項目 |
| enemy_defeat_audio | PASS、716項目 |
| enemy_attack_warning | PASS、110項目 |

新規検査は実Space入力で予告の赤点滅中からジャンプし、追跡継続・Fire1単発・0.9秒固定・通常帰還を確認。さらに近距離2.0mと遠距離4.5mからの攻撃へ実ジャンプ最高点を合わせ、最高点約1.284m、実命中時1.284m／1.279m、各1回・HP100→90を確認。着地後の次攻撃でHP80となる。

高さ1.4mは命中・1.401mは非命中、低い敵設定0.5mでは計画継続＋高さ1.2mの非命中。上下形状と主人公0.3mの非変更も検査。既存の正面Guard状態を保持して高さを与える検査ではHP95となり、従来の軽減が使われる（新たな空中Guard発動機能の検査ではない）。

壁／低障害物・本物の高台とその上のジャンプ・足場の切れ目・地面未検出・検索深さ外は攻撃開始不可。固定後の実WASD移動による回避、魔導士の実ジャンプ中目標への3D弾の発射・速度3.0、設定保存／別プロセス再読込も確認。主人公の共有Weaponのファイルhashと実メモリ値が変わらないことを確認。

再現例（プロジェクト直下PowerShell、Godotは1プロセスずつ）：

```powershell
& 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/enemy_jump_strike.gd
& 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/enemy_jump_strike.gd -- --fps30
& 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . --script res://tests/enemy_jump_strike.gd -- --reload
```

最終のheadless editor importは終了0、Script／Parse／画像参照エラーなし。通常のAPPDATAではworkspace外のeditor_settings保存不可という環境診断が出たため、検査プロセスだけAPPDATAを `.godot/jump_editor_appdata` へ設定して再実行し、エラーなしで終了した（`.godot/jump_enemy_import_isolated.log`）。ユーザーの既存個人設定は変更せず、環境制限そのものを修正済みとは扱わない。実mainシーンの起動・既定敵／左攻撃／右防御とモード切替はm09_startupで確認。テストログにScript／Parse／Shader／実行エラーなし。git diff --check合格。

## F5でのユーザー確認（未実行）

1. F8で旧実行を停止してF5。近距離と遠距離それぞれで、雑兵の赤点滅中にSpace。途中中断せず、攻撃態勢→Walk踏み込み→攻撃→帰還となり、Fire1が1回だけ鳴ること。
2. ジャンプを少し遅らせ、最高点付近でも射程内なら命中すること。通常ジャンプだけでは剣を回避できない。着地後の次の攻撃も正常であること。
3. 赤点滅終了後、WASDで横へ離れる。固定後に追尾せず、水平の攻撃範囲外なら回避できること。右クリック／Iの防御軽減も従来どおりであること。
4. 壁・低い障害物・段差／高台・崖を挟む場合、不正な踏み込みや命中が発生しないこと。
5. 左クリック／J攻撃、3連撃・ターゲット切替、方向入力の素早い帰還、Q/E回転、雑兵の周辺歩行、魔導士の弾・既存SEと撃破表示を確認する。
6. 上記Resourceの高さを変更・保存して再起動し、敵だけへ反映することを確認。試験後は雑兵1.4m／検索2mへ戻す。

F5での実際の回避しやすさ・聴感／見た目、任意の複雑地形、実機パッド、長時間性能は未確認。既存の平坦な安全経路方針を拡張する修正ではない。M09基本戦闘完了と今回の追加確認待ちは区別する。
