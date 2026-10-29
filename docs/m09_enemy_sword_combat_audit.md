> 2026-10-29追記（ADR-040）：雑兵だけ命中高さを敵専用snapshotで上下1.4mへoverrideし、実地面の経路と空中の命中を分離。主人公の武器0.3mは維持。最新は [m09_enemy_jump_strike_audit.md](m09_enemy_jump_strike_audit.md)。以下の全共有高さ0.3mは導入当時の記録。

> **後続更新（ADR-035）**：新IdleとWalk素材改名を接続し、踏み込みはWalk、雑兵は帰還後の3秒内に歩いて位置を整える。以下は作成時の履歴。最新の参照名・設定は[m09_enemy_followup_audit.md](m09_enemy_followup_audit.md)。

# M09：雑兵の主人公共通武器・踏み込み・単発攻撃（ADR-033）

2026-10-27。ユーザー指示によりADR-032の剣位置・旧敵攻撃時間／射程を更新。**M09の追加改善、ユーザーF5・見た目／操作感確認待ち**。新工程・新素材なし。commit／push未実行。

## 今回の動作

雑兵は主人公と同じ片手剣Resourceを使用する。剣の画像だけでなく、白い斬撃・一振り時間・フレーム時間比率・命中時刻・攻撃開始範囲／命中範囲・踏み込みと帰還の時間設定を参照する。

1. 主人公を探知し、攻撃開始範囲内に入ると従来の予兆を表示する。
2. 剣が届くならその場で1回攻撃。届かなければ安全な経路で踏み込み、1回攻撃して元の攻撃開始位置へ帰還する。
3. 攻撃と必要な帰還が終了した後、既存RECOVERYで3秒待機する。まだ開始範囲内なら、次の予兆を経て再び1回攻撃する。

3秒は「数秒」に対する今回の仮値。次の攻撃までにはこの待機に加えて従来の予兆0.9秒がある。遠距離からの攻撃では帰還時間も含まれるため、命中が厳密に3秒ごとに発生する仕様ではない。

## 共通設定と雑兵だけの設定

| 項目 | 現在の設定と参照元 |
|---|---|
| 片手剣 | resources/weapons/one_handed_sword.tres |
| 攻撃開始範囲 | Weapon.attack_range＝5.0m |
| 剣の命中リーチ | Weapon.melee_reach＝2.5m |
| 命中扇形 | Weapon.sweep_angle_degrees＝100度（左右50度） |
| 命中高低差 | Weapon.hit_height_tolerance＝0.3m。ただし既存の平坦な足場／経路の安全検査も必要 |
| 一振り | Weapon.swing_duration()＝0.32秒 |
| フレーム比率 | Weapon.motion.frame_time_ratios＝[0.4,0.2,1.5] |
| 命中 | 第2コマの先頭＝一振り開始後約0.061秒、物理tickで1回だけ確定判定 |
| 踏み込み | Motion.approach_speed＝12m/s、所要時間を0.25〜0.40秒に制限 |
| 停止距離 | resources/target_dash_settings.tresのstop_distance＝1.1m。元の当たり判定より近くへは入らない |
| 帰還 | Motion.return_speed＝10m/s、所要時間を0.10〜0.32秒（保存済み値）に制限 |
| 攻撃前後の待機 | Motion.approach_attack_delay／final_attack_wait、現在ともに0秒 |
| 雑兵の予兆 | EnemyAttackData.windup_seconds＝従来の0.9秒 |
| 雑兵のダメージ | EnemyAttackData.damage＝従来の10 |
| 雑兵の攻撃回数 | 1サイクルにつき1回。Weapon.max_combo_hitsは流用しない |
| 雑兵の攻撃後インターバル | EnemyAttackData.recovery_seconds＝3.0秒（仮値） |

新しいストック・コンボ・装備UIは作らない。武器設定の変更は次の攻撃開始時にsnapshotへ取り込む。進行中の武器数値／Motionは私有コピーとし、途中で共有Resourceを編集してもその一振りの設定を変えない。主人公側のResource・コードは変更していない。

## 剣とエフェクト

- `EnemyAttackData.weapon.attack_visual`から主人公と同じ`iron_sword_visual.tres`を参照。鉄の剣は112px×3コマ×4方向、白い斬撃は既存の`iron_sword_slash_effect.tres`、本体は提供済み48pxの雑兵画像。
- 前回の雑兵専用コマ別柄補正を本番Resourceから外し、主人公と同じ中心・方向offset・pixel_sizeで描画する。本体は各方向の固定攻撃姿勢、剣と斬撃が共通進行で動く。主人公の体画像へ置き換えたり、新しい本体動作コマを制作したりはしない。
- 本体・剣・斬撃は既存の敵ATTACK elapsedを一振り時間で正規化し、共有Motionの重みを使ってサンプリングする。独立した攻撃タイマーや二重のダメージ判定は追加しない。
- WeaponEffect／SlashEffectは独立ノード。WeaponEffectData.sampleと既存attachment depth Shaderを使い、開始／長さ／有効方向／位置は主人公と同じ設定を使用。武器付随エフェクトは既存設定どおり無効、白い斬撃は有効。
- 攻撃終了・帰還・RECOVERY・死亡・モード切替で表示を終了する。床の欠け、壁越し表示を避ける既存の深度テスト・地形検査は維持する。no_depth_testを有効化していない。
- 既存の風切り／命中／防御成功音、被弾flash／火花の再生処理・性能は変更していない。

## 攻撃・安全性

共有`MeleeSweep.contains`を射程内分岐と実命中の両方に使用。`DashPath.strike_clear`で地形の形状掃引・視線・足場を検査する。壁や低い障害物、段差／崖・隙間を越えた攻撃を距離だけで許可しない。命中時も現在の主人公位置と経路を再検査する。

踏み込みは既存の`move_and_collide`・元のカプセル・安全な経路検査、固定した予兆の狙い、移動予約の競合解消、遮断時の安全停止を維持。移動／帰還の所要時間だけを共有Motionの距離÷速度と上下限から計算する。未移動なら帰還を省略する。最初のattack_anchorを保持し、homeへの通常帰還と区別する。

weapon未指定の敵は旧攻撃設定のまま動作する。魔導士の予兆・弾・ダメージ・間隔、静止練習敵、主人公の入力／武器・Motion・防御・HP計算は変更しない。

## Inspectorの設定場所

1. ファイルシステムから`resources/enemies/melee_attack.tres`を開く。
2. **Recovery Seconds**：攻撃／必要な帰還の終了後の待機時間。初期3.0秒。雑兵だけを調整できる。
3. **Weapon**：既存の`one_handed_sword.tres`を参照。射程・モーション・画像を開いて確認できる。共有のため、武器／Motionを変更すると主人公にも反映される。
4. **Travel Settings**：既存の`target_dash_settings.tres`を参照し、停止距離を共用する。
5. Weapon内の**Attack Visual → Slash Effect**で画像・開始／長さ・方向offsetなどを確認できる。

weaponを指定した雑兵では、EnemyAttackDataに従来からあるAttack Seconds／Hit Delay Seconds／Hit Radius／角度／Dash Seconds／Return Seconds等は実行snapshotで武器／Motion由来の値へ解決する。今回の本番調整ではWeapon／Motion側を参照する。weapon未指定の旧敵では従来の各値が有効。

## 変更ファイル

- `scripts/enemies/enemy_attack_data.gd`：任意の共通武器／移動設定参照、武器・Motionのsnapshotと時間／形状の解決
- `scripts/enemies/practice_enemy.gd`：共通射程・その場／踏み込み分岐・移動時間・共有命中形状／経路・未移動帰還省略
- `scripts/enemies/enemy_sprite.gd`、`enemy_weapon_visual.gd`：共通フレーム比率と主人公と同じ配置
- 新規`enemy_effect_visual.gd`とUID：共有エフェクトの表示・深度同期
- `scenes/enemies/practice_enemy.tscn`：WeaponEffect／SlashEffect
- `resources/enemies/melee_attack.tres`：既存片手剣／停止設定とRecovery Seconds=3.0
- `resources/enemies/zouhyou_visual.tres`：旧コマ別柄補正を解除
- 新規`tests/enemy_sword_combat.gd`とUID、`tests/fixtures/enemy_dash_attack.tres`
- `tests/enemy_sprites.gd`、`tests/m09_enemy_dash.gd`、`tests/m09_startup.gd`
- 本記録・DEVELOPMENT_STATUS・ADR-033・システム仕様・戦闘仕様・テスト計画、以前の敵画像記録への更新注記

## 自動検証

Godot4.7.2.stable.official.ed1daf0bf／Windows、Compatibility／GTX1080、物理60Hz。**8種類13条件すべてPASS・終了0**。実描画の60／30fps上限を1プロセスずつ実行した。ユーザーのF5受入とは区別する。

| 最終検査 | 結果 |
|---|---|
| enemy_sword_combat・実描画60／30 | PASS・425／239項目（観測数により変動） |
| 同・別プロセス--reload | PASS |
| enemy_sprites・剣60／30 | PASS・408／394項目 |
| enemy_sprites・白い斬撃60／30 | PASS・各408／394項目 |
| m09_enemy_combat | PASS・56項目 |
| m09_enemy_dash・旧3profile／安全性／競合 | PASS・171項目 |
| m09_startup・実F5シーン／左攻撃・右防御／モード切替 | PASS |
| weapon_effects・主人公の効果回帰 | PASS・2246項目 |
| m08_defense・防御／方向帰還／安全性 | PASS |
| m09_timing・旧近接／魔導士の時間／単発弾 | PASS |

最終コード／Shader解析エラーなし。環境の証明書ストア読み取り／エディター設定保存ERRORは区別する。ログはGit除外の`.godot/enemy_sword_*.log`、統合した最終一覧は`enemy_sword_all_results.json`。剣と斬撃の実描画、実AIの命中・帰還・Guard軽減、3秒待機を確認した。主人公の武器／Motion原本が検査前後に変化しないこと、保存した別武器profileが別プロセスで読めることも確認した。

検査内容：実AIの近距離／遠距離、開始／リーチ境界・角度、1回だけの命中と実Guard軽減、3秒の非攻撃時間、次の予兆、共通時間／重み／剣／斬撃、低壁・動的遮断・足場欠け、死亡・snapshot・保存再読込。剣／白い斬撃は各4方向×4カメラYaw×3コマの床あり／なし画素完全比較と不透明壁の遮蔽を検査する。

旧m09_enemy_dashはweapon未指定の既定profileを固定fixtureへ保存して従来3種類の安全性・時間・競合の期待を維持。新しい本番の共通剣は専用検査で扱う。m09_startupは攻撃して元位置へ戻った敵を「未移動」と誤認しないよう、途中の最大変位と実攻撃回数を観測する。リーチ内のその場攻撃も有効とする。

再現（各コマンド後に終了0とログを確認）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_sword_combat.gd -- --capture
& $godotExe --path . --script res://tests/enemy_sword_combat.gd -- --fps30
& $godotExe --headless --path . --script res://tests/enemy_sword_combat.gd -- --reload
& $godotExe --path . --script res://tests/enemy_sprites.gd
& $godotExe --path . --script res://tests/enemy_sprites.gd -- --fps30
& $godotExe --path . --script res://tests/enemy_sprites.gd -- --effect
& $godotExe --path . --script res://tests/enemy_sprites.gd -- --effect --fps30
```

## F5手動確認

1. F8で停止してF5。近接敵の雑兵に近づき、主人公と同じ剣・白い斬撃・3コマの時間配分を確認する。
2. 約2.5m以内ではその場で1回、2.5〜5mでは予兆の後に踏み込み→1回→帰還となることを確認する。5mより遠い場合はまず通常の追跡で近づく。
3. 攻撃／帰還終了から約3秒待ち、まだ範囲内なら次の予兆が始まることを確認する。待機中に剣・斬撃が残らず、余分な命中がないことを確認する。
4. 右クリック／Iで防御、左クリック／Jで攻撃、Lで照準。近距離／遠距離攻撃、コンボ、方向帰還、WASD／Spaceが維持されることを確認する。
5. 上下左右・Q/E、敵近傍、壁・低い障害物・段差／崖で、表示と攻撃・移動制限を確認する。
6. 敵を途中で撃破して剣／斬撃が消えること、遠距離モードで魔導士の従来の弾攻撃が維持されることを確認する。
7. Recovery Secondsを変更して保存しF5を再起動、雑兵の待機だけが変わることを確認する。

作業中にユーザー側で画像フォルダの歩行素材名変更と魔導士待機画像の追加を検出。今回のAI変更と分けて保持し、原画像やゲーム用コピーを上書きしていない。

未実行：ユーザーF5・操作感／見た目の受入、任意の複雑地形／多数敵・実機パッド・長時間性能。M09検証待ちを維持する。
