# M09 攻撃モーション調整（2026-10-23、ADR-022）

状態：実装・自動検査済み。ユーザーF5受入は未実行。M08試作範囲完了、M09検証待ち、M10別指示待ちを維持する。新しい工程・武器・装備UI・画像は追加しない。

## 開始時の照合・範囲

開始HEAD `d64afe1180beb41b6dc2335e4e234c2ffe1900b7`、git statusはクリーン。AGENTS、README、制作資料、DEVELOPMENT_STATUS、ADR、10／11／12／14と実物を照合した。ADR-021の剣・白斬撃は実装済みでユーザー操作確認待ちという記録と一致。今回の目的は既存の攻撃タイミングを保持してInspector調整を追加すること。攻撃数・威力・判定範囲・敵AI・画像・描画深度は今回の変更対象外。

## 設定場所・初期値

Godotで実行を止め、FileSystemの `resources/weapons/one_handed_sword.tres` を選択する。WeaponData直下の既存時間項目と、展開した **Motion** の追加項目を編集する。シーンからは `scenes/main.tscn` → Player → TargetDash → **Equipped Weapon** → **Motion** で同じResourceを開ける。Motionの実体は `resources/weapons/default_attack_motion.tres`。各Resourceを保存してF5。リモート側だけの変更は保存されない。

| 場所・項目 | 初期値 | 単位・範囲 |
|---|---:|---|
| WeaponData / Attack Duration（既存） | 0.32 | 秒、0.1〜2 |
| Attack Speed Multiplier（既存） | 1 | 倍、0.1〜5。実際の一振り=Duration÷Multiplier |
| Combo Stance Duration（既存） | 0.12 | 秒、0〜1。予約済み／撃破後の段間待機 |
| Combo Input Window（既存） | 0.5 | 秒、0〜2。生存対象・予約なしの従来の入力猶予 |
| Motion / Approach Speed | 12 | m/s、0.1〜40 |
| Motion / Return Speed | 10 | m/s、0.1〜40 |
| Minimum Travel Time | 0.25 | 秒、0.05〜2。従来の移動時間下限 |
| Maximum Travel Time | 0.4 | 秒、0.05〜2。従来の上限、下限未満なら下限を適用 |
| Approach Attack Delay | 0 | 秒、0〜5。踏み込み到着後の待機 |
| Final Attack Wait | 0 | 秒、0〜5。通常の最終終了条件成立後に追加する待機 |
| Frame Time Ratios | [1, 1, 1] | 無単位、現在は配列サイズ3。正値0.001〜1000へ制限、0／負値／非有限値は1 |
| Hit Frame | 1 | 0始まり、0〜63。1は2コマ目。現在コマ数に収める |
| Hit Frame Percent | 0 | 指定したコマ内の0〜100%。100はそのコマの末尾 |

移動の主設定は速度。経路距離÷速度を従来の最小／最大時間へ収め、既存smoothstepで移動する。速度を変えても上下限に収まる距離では変化しないことがある。移動所要時間という別の主設定は追加していない。既存TargetDashSettingsの速度・移動時間上下限・hit_frameはMotionへ移した。現在のtresに個別上書き値がないことを確認し、同じ初期値を移行した。経路安全性設定はTargetDashSettingsに残す。

斬撃は `resources/weapons/iron_sword_slash_effect.tres`（または Equipped Weapon → Attack Visual → Slash Effect）。Weapon Effectにも同じ項目があるが、提供素材が1枚のため無効枠を維持する。

| エフェクト項目 | 初期値 | 単位・範囲 |
|---|---:|---|
| Start Percent | 0 | 共通の一振りに対して0〜100% |
| Duration Percent | 100 | 共通の一振りに対して0.1〜100%。実秒数=実際の一振り秒数×割合÷100 |
| Offset Down / Left / Right / Up | (0,0) | px、Vector2。+X右、+Y上。数値上の範囲制限なし |
| Enabled / Enabled Directions / Frames | 従来どおり | 有効化、対象方向、画像・コマ構成 |

開始と長さは独立。例：Start25、Duration40で一振りの25〜65%に全コマを再生する。終端が100%を超える場合も攻撃終了で切る。旧start_phase／end_phase／playback_speedは既存Resource互換の保存表現として保持し、Inspectorには表示しない。新しい％項目はその値を読む／書く別名で、重複保存しない。新UI編集時は速度1へ正規化し、全コマが指定長さに収まる。既存コードからの旧パラメーター利用は互換を維持。

## 共通タイムライン

本体AnimatedSprite3Dのエンジン再生だけが時計。既存attack_duration／attack_speed_multiplierから実際の一振り時間を計算し、プレイヤー専用SpriteFramesの相対時間を設定してspeed_scaleを合わせる。元の共有SpriteFrames／画像は変更しない。

例：[1,0.4,1]なら一振りの41.667%／16.667%／41.667%を各コマへ配分する。合計時間は変わらない。Hit Frame1・Percent0の初期命中位置も、元の33.333%から41.667%へ自然に追従する。Percent50なら50%地点。命中はこのphaseを読み、既存_hit_pending／_hit_doneとHP所有者の重複防止を使う。短いコマのスキップや最終100%でも1回だけ。新Hitbox／ダメージ経路は作らない。

本体のframe／frame_progressを正規化したattack_phaseを、武器・各効果・命中で共有する。武器と効果はstop状態のままサンプリングし、別タイマーを進めない。同数のパーツには共通比率、比率数と異なるパーツにはそのSpriteFramesの相対コマ時間を用いて、同じ0〜1進行へ合わせる。将来4コマ本体／3コマ武器／5コマ効果も組み合わせられる。Q/Eで本体方向を切り替えるときは正規化進行を維持し、一振り時間へ再正規化する。

実斬撃はエンジンanimation_finished通知を維持。対象消失後の無表示スロットは従来の物理時間と同じ一振り秒数を使う（描画時計は作らない）。生存予約先の既存安全処理、予定数・1回分消費、静止待機、通常の連撃と猶予は保持。接近中の消失時は接近残時間＋到着後待機＋一振りを保持する。Final Attack Waitは自然終了だけに適用し、方向帰還・Guard・死亡／reset・危険な経路の中断には追加しない。設定はサイクル開始時に複製／数値を制限し、途中変更による停止を防ぐ。

深度Shader、中心・pixel_size・billboard、地形ray・敵／壁の遮蔽、盾、防御軽減、敵AI、攻撃対象の列挙／ダメージ式は維持する。

## 変更ファイル

- 新規：`scripts/combat/attack_motion_settings.gd`、`resources/weapons/default_attack_motion.tres`、`tests/attack_motion.gd`とGodot生成UID。
- 既存コード：`scripts/combat/weapon_data.gd`、`scripts/combat/target_dash_settings.gd`、`scripts/player/player_sprite.gd`、`scripts/player/target_dash.gd`、`scripts/player/weapon_attack_visual_data.gd`、`scripts/player/weapon_swing_visual.gd`、`scripts/player/weapon_effect_data.gd`、`scripts/player/weapon_effect_visual.gd`。既存の時間設定を再利用、武器コマ数固定制約を解除。
- 回帰検査10本：m06_target_dash、m07_combo／chain／controls／wall_contact、defeat_return_timing、iron_sword_animation、weapon_effects、weapon_sweep、player_damage_visual。命中設定の参照先だけを移行し、期待する命中数・消費・安全性は維持。
- 文書：README、ADR-022、10／11／12／14、DEVELOPMENT_STATUS、本書。

## 再現・検証結果

Godot4.7.2／Windows／Compatibility／GTX1080、物理60Hz。検証用Godotは逐次実行する。対象OSや最終版バージョンの確定ではない。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/attack_motion.gd -- --capture
& $godotExe --path . --script tests/attack_motion.gd -- --fps30 --capture
& $godotExe --headless --path . --script tests/attack_motion.gd -- --reload
```

`--reload`は先行検査で保存した`.godot/attack_motion_saved_weapon.tres`を別プロセスで読む。保存・プロセス終了・再読込での値の維持を確認する。ログ／画像／計測値は`.godot/attack_motion*`と`iron_sword_motion_*`（Git除外）。最終結果は以下へ記録する。

### 初期値の変更前後比較

実際の物理・描画イベントを4ケース×60／30上限で採取した。開始tick・連撃開始列・消費・帰還誤差は一致。Return開始は以下のとおり（攻撃要求からの物理tick、60Hz）。単発60上限だけ1tick差を記録し、完全一致とは扱わない。共通時間の初期値は0.32秒のまま。

| 上限fps | ケース | 変更前→後のReturn開始 |
|---:|---|---:|
| 60 | 単発 | 66→67 |
| 60 | 3連撃／1撃目撃破／2撃目撃破 | 各90→90 |
| 30 | 単発 | 65→65 |
| 30 | 3連撃 | 87→87 |
| 30 | 1撃目撃破 | 89→89 |
| 30 | 2撃目撃破 | 88→88 |

独立した既存defeat_return_timingは1869 assertions PASS。最初の斬撃から通常3段・1／2／最終撃撃破はすべて74tick、5回武器は128tickで従来と一致。新しい調整値（一振り0.48秒・段間0.3秒・最終待機0.2秒）でも、生存3連撃と1撃目撃破のReturn開始は要求から各150tickで一致する。

新検査の描画60上限では、Approach Speed12→2で踏み込み16→25tick、到着後待機0→0.2秒で斬撃開始16→28tick、Return Speed10→2で帰還16→25tick、最終待機0→0.3秒で最終終了からReturnまで31→49tick。設定を単独に変えて命中数・消費を維持することを確認した。

既存18種類は全てPASS・終了0：m05_animations／m05_animation_transitions、m06_target_dash／m06_target_selection、m07_combo／m07_chain／m07_controls／m07_wall_contact、m08_defense／m08_guard_sprite、m09_enemy_combat／m09_enemy_dash、defeat_return_timing、iron_sword_animation、weapon_effects、weapon_sweep、player_damage_visual、m09_startup。`.godot/attack_motion_reg_results.json`と各`attack_motion_reg_*.log`に記録。回帰全体の再実行ではなく、この変更に関連する範囲。


### 最終検査（2026-10-23）

- 新attack_motion：実描画60上限1684／30上限882 assertions PASS・終了0。最後に到着後待機中の対象free、未開始分の時間維持と非消費、サイクル中の設定変更がactive snapshotへ波及しないことを追加確認した。観測tick数でassertion件数は変動する。
- 別プロセス--reload：9 assertions PASS・終了0。Motionと独立効果の値、方向offset、Inspectorでの新％項目の公開と旧保存項目の非公開、重複保存なしを確認。
- weapon_depth：剣／斬撃それぞれ37 assertions PASS・終了0。4方向×3コマの床なし基準と床ありの全差分画素集合が一致。不透明壁では各0画素、敵前後・部分壁・半透明壁・段差／崖・4Yawも従来の期待値を維持。no_depth_test診断は検査後に復元。Shaderの変更なし。
- 最終一覧：関連18実行＋新モーション2条件／再読込1条件／深度2条件＝23実行、20種類。全PASS・終了0、SCRIPT／Parse／Compile／SHADERエラーなし。結果はattack_motion_results.json／attack_motion_reg_results.json、再描画ログはattack_motion_final_*.log。中央コマの4方向画像を目視確認。
- 最終editor import終了0、UID生成、git diff --check成功。証明書読み込み・sandbox外のeditor_settings保存ERRORは既存の環境制限として区別し、コンパイルエラーや検査失敗に置き換えない。最初の検査fixtureでは外部Resourceをduplicate(true)だけで分離できず、効果設定が共有されたため、必要な参照を明示複製して修正した。最終検査は修正後の結果のみ。
- 画像／Shader／シーン／敵AI／Controller／Camera／経路・HP処理・防御設定はHEADから差分なし。ユーザーF5受入・最終調整、実機パッド・長時間・複雑地形等は未実行。検証用Godotは終了済み。コミット／プッシュ未実行。

## F5手動確認（未実行）

1. **初期値のままF5**。静止敵でJ／クリックの単発・3連撃、Lとクリックによる別対象予約、方向帰還、I防御、帰還後Spaceジャンプ、敵AIモードを確認する。以後、毎回F8で止めて1項目ずつ変更し保存→F5。
2. Approach Speedを12→2、Return Speedを10→2にして、それぞれの移動だけ変わるか確認する。Approach Attack Delayを0→0.2にして到着後だけ待つことを確認。移動の上下限による飽和に注意。
3. Attack Durationを0.32→0.72、Frame Time Ratiosを[1,0.4,1]にし、3コマの総時間を保って中央コマが短くなることを確認。Hit Frame1・Percent0→50で命中が中央コマ後半へ動き、1撃10ダメージ・1消費のままか確認する。
4. Slash EffectのStart Percent0→25、Duration Percent100→40、必要なら方向offsetを少量変更。攻撃全体の25〜65%だけ表示し、剣振り・HP減少・移動速度には影響しないか確認する。
5. Combo Stance Durationを0.12→0.3、Final Attack Waitを0→0.2にし、連撃間／最終終了後の待機を区別する。予約なしでは従来Combo Input Windowの後に最終待機を追加する。待機中の方向帰還と防御も確認する。
6. 敵HPを先に減らし1／2撃目で倒す。残りを待機姿勢で維持し、空振りせず通常の時間に帰還するか確認。別の生存敵を予約して継続、壁・段差・崖で不正な移動を拒否するか確認する。
7. 北南東西の全3コマ、Q/Eの攻撃中回転、敵近傍・壁越し・段差／崖の描画、被弾とGuardの終了を確認する。剣／弧の残像、地面への埋没、壁越し表示がないことを確認する。
8. Resourceを保存してGodotを終了・再起動し、編集値と動作が保たれることを確認する。終わったら好みの値を保存する。今回の初期値は従来互換値であり、最終的な速度・見た目の調整はユーザー受入後に行う。

実機パッド、長時間性能、任意の複雑地形・大型敵、ユーザー実操作の受入は未実行。既存未検証項目を一律合格にしない。

## 将来の武器

WeaponDataを複製し、Motionを「ユニーク化」または別名保存して割り当てる。同じMotion参照を編集すると共有する全武器へ反映される。Attack Visual／各効果も別設定が必要なら個別にユニーク化する。Framesは既存attack_down／left／right／upを用意し、共通配分に合わせるコマ数ならMotionの比率配列、異なるコマ数なら各SpriteFramesの相対時間を設定する。装備UIや武器名ごとのコード分岐は不要。
