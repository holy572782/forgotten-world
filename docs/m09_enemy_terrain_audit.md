# M09完了後：敵の坂・階段歩行、home範囲、高低差攻撃

2026-10-30／ADR-046。M09基本戦闘完了は維持、今回のF5操作・見た目確認はユーザー未実行。M10別指示待ち。commit／push未実行。

## 開始時・目的

開始HEAD `60b1608`。初期差分は `addons/effekseer/bin/windows/~libeffekseer.x86_64.dll` の削除だけで、ユーザー側の差分として復元／上書きせず保持する。AGENTS／開発状況・必読08／10／11／12／14と最新ADR-045／敵・Player／経路／地形・関連検査を照合。

両敵の通常歩行と踏み込みを分ける。既存DashPath.clearは水平・連続床の安全契約なので、これを緩めず敵の通常歩行だけ別実装にする。Playerの移動／ジャンプ／攻撃／コンボ／帰還、雑兵の攻撃リズム、魔導士の最新の床面魔法陣／炎弾／MAGIC／SE／10秒回復は維持する。地形や画像は編集しない。

## 通常歩行・昇降

EnemyWalkSettingsをEnemySettings.walkへ追加。EnemyWalkはCharacterBody3Dのfloor_max_angle／floor_snap_length／floor_constant_speed／floor_stop_on_slopeとmove_and_slideを使用する。原寸カプセルと元のcollision_maskを保持し、重力／床・斜面の接触をエンジンへ任せる。

上り段差は、着地面の高さ／足元5点支持と全身の上方→前方経路をtest_moveで確認してから、上昇→前進→小さな着地補正を各physics tickの速度で進める。global_positionを飛ばして段差を越えない。最大1.05m・昇降速度3.5m/sが初期値で、壁・天井・相手のBodyへ衝突すれば停止する。通常下降も先の支持面を確認し、最大1.05mまでを重力／速度上限付きで降りる。床snapは0.12mに留め、1mの下降を一瞬で吸着させない。

足元の中央＋カプセル半径95%の前後左右を検査し、急斜面／崖・支持面なしを拒否する。実マップの坂終端には細い継ぎ目があり、そのサンプルの前後または左右両側15cm以内に同程度の歩ける面があるときだけ補って判定する。片側だけの崖や広い穴へ置き換えない。実際の移動は元の物理衝突が引き続き制限する。

衝突・無支持で歩けなければ速度0とし0.5秒待って再検査する。停止中はWalkアニメーションを再生し続けない。段差の途中では新しく攻撃を開始せず、安全な昇降区間を終えてから通常の攻撃状態へ移る。主人公が攻撃／予約対象として移動を保持している場合は、昇降も一時停止する。

## home帰還・追跡範囲

homeは従来どおり出現時の座標。追跡許可はhomeから敵と主人公への**水平XZ距離**で判定し、既存Leash Radiusを雑兵9m／魔導士10mとして再利用する。敵と主人公の相互距離やジャンプ高さをleashの代用にしない。通常移動の次の位置も範囲内に制限する。

主人公が範囲外へ逃げれば追跡を中断してhomeへ戻る。home到着まで再追跡せず、IDLEからの再索敵は範囲の0.3m内側へ戻った相手だけにする。魔導士のADR-045の確定詠唱は、距離超過だけでは取り消さずその攻撃と既存回復を終えて帰還する仕様を維持する。雑兵も攻撃中は既存のattack_anchorへの安全帰還を先に完了する。

歩行時の安全な位置を記録し、home帰還では逆順にたどる。坂と階段を上った経路を、そのまま通常歩行で下って戻れる。攻撃用のattack_anchorは毎回の攻撃開始位置であり、homeや歩行記録と混同しない。

新しいNavigationAgent／NavMeshは追加しない。対象マップでは直線の接近と既知経路の逆走で成立する。任意の迷路・動的に塞がれた帰路・大規模な迂回探索は未対応で、安全に停止／再試行する。歩行記録は最大256点に制限し、長時間ループや複雑地形の一般解を保証しない。

## 視線喪失

Sight Loss Secondsの初期値を0.5→1.75秒へ変更。最後に目視できたプレイヤー座標を記録し、CHASE中に一時的に見失った場合は猶予内だけその位置へ安全歩行する。継続して見失えばhomeへ帰還する。視線がない間に攻撃を開始せず、実命中と魔法発射の既存視線条件も維持する。

## 雑兵の高低差攻撃

敵専用EnemyMeleeGeometryは**地形の許可検査だけ**で、新しいHitboxやダメージ処理ではない。共通MeleeSweep.containsの水平リーチ／角度／実高低差1.4mをそのまま使う。

計画時は目標の実地面を取得し、届く段差や坂ならその場攻撃を選べる。命中時は実際の主人公の高さで判定するため、1mの階段上や通常ジャンプで剣が届く相手に命中し、1.4mを越える実高度には命中しない。予告中のジャンプと照準確定時刻は維持する。

既存視線に加え、剣の高さの線と経路の地面・足元幅を検査する。両者の床高さの範囲に収まる段差／坂だけを許可し、同じ高さの床の間にある低障害物の山越え・壁／床下／足場の欠落は拒否する。斜面では足元幅の傾斜ぶんだけ支持面の高さを考慮する。

遠い相手への踏み込みと攻撃後のattack_anchor帰還には、元のDashPath.strike_clear／clearを使う。水平・連続床・全身掃引を緩めない。剣が届かず踏み込めない場合は、予告の開始／中断を繰り返さず通常歩行で接近する。攻撃後の追跡でも、踏み込みが不成立なら理想距離3.5mだけで停止せず、攻撃が成立する位置まで通常歩行を継続する。

魔導士の床面魔法陣も、敵用の歩行可能な地面検出へ接続し、床の法線に沿って投影する。坂で表示が消えたり半分埋まったりする平坦前提を解消し、Native素材・回転／色／SE／詠唱／fadeは維持。平地では従来と同じ配置。

## Inspector

EnemyのSettings（雑兵melee_practice.tres／魔導士ranged_practice.tres）から調整。武器やPlayerのMotion設定とは別。

| 項目 | 初期値 | 用途 |
|---|---|---|
| Leash Radius | 雑兵9m／魔導士10m | home基準の水平追跡範囲 |
| Leash Reentry Margin | 0.3m | home帰還後の境界再索敵の余裕 |
| Sight Loss Seconds | 1.75秒 | 最終確認位置へ向かう猶予 |
| Walk → Max Slope Degrees | 45度 | 通常歩行の斜面上限 |
| Walk → Maximum Step Up / Down | 1.05m／1.05m | 通常昇降の最大高さ |
| Walk → Climb Speed | 3.5m/s | 上りと下降速度の上限 |
| Walk → Gravity | 20m/s² | 通常歩行の下降加速度 |
| Walk → Snap Length | 0.12m | 小さな床接触補正 |
| Walk → Blocked Retry Seconds | 0.5秒 | 歩けない場合の待機 |
| Walk → Floor Seam Tolerance | 0.15m | 支持面を両側に探す距離、0で補完OFF |

雑兵の剣のHit Height Toleranceは従来のmelee_attack.tresの1.4m。通常の歩行速度・周辺移動重み／時間・魔導士のRanged Stop Marginは既存項目を使用する。個々の敵で異なる値を使う場合はSettings／Walkを固有化または複製して割り当てる。保存／再読込は追加検査対象。

## 変更ファイル

- scripts/enemies/enemy_walk_settings.gd、enemy_walk.gd、enemy_melee_geometry.gd（新規）
- scripts/enemies/enemy_settings.gd、practice_enemy.gd、scripts/effects/mage_cast_visual.gd（坂面への床投影だけ）
- tests/enemy_terrain.gd（新規）、enemy_jump_strike.gd（届く段差の新仕様だけ更新）と新規Godot UID
- AGENTS.md、docs/DEVELOPMENT_STATUS.md、08_DECISIONS.md、10_SYSTEM_SPEC_GODOT.md、11_CODEX_IMPLEMENTATION_PLAN.md、12_TEST_PLAN.md、14_TARGET_DASH_COMBAT_SPEC.md、本書

共有DashPath／MeleeSweep・Player・既存武器／敵攻撃Resource・シーン／マップ・画像／音声／Shader／配布プラグインは変更しない。開始時からの一時DLL削除は今回の実装差分と分ける。

## 自動確認

Godot 4.7.2.stable.official.ed1daf0bf／Compatibility／GTX 1080、物理60Hz、実描画fps上限60／30。**15種類17条件すべてPASS・終了0**。観測assertion件数は描画と物理フレームの対応で変動する。

| 検査 | 結果 |
|---|---|
| jump | ENEMY JUMP PASS: 543 assertions; fps cap=60 |
| sword | ENEMY SWORD PASS: 445 assertions; fps cap=60 |
| combat | M09 PASS: 56 assertions; fps cap=60 |
| timing | M09 TIMING PASS |
| defense | PASS M08 return: directional intent, hold/neutral/taps/noise, guard, stock/hits, safe Return, camera, reset, reserved K/east |
| chain | PASS M07 chain: facing aim, manual release, pivot lock, orbit, ABC, replacement, invalid next, return |
| near | IN PLACE ATTACK PASS: 3274 assertions; fps cap=60 |
| warning | ATTACK WARNING PASS: 110 assertions; fps cap=60 |
| defeat | BOUNCE CRY PASS: 2909 assertions; fps cap=60 |
| mage | MAGE CAST PASS: 29 assertions; fps cap=60 |
| mage_feedback | MAGE FIRE FEEDBACK PASS: 33 assertions; fps cap=60 |
| startup | M09 STARTUP PASS: default enemy attacks, left attack/right guard, GUI switches and resets |
| terrain60 | ENEMY TERRAIN PASS: 4758 assertions; fps cap=60 |
| terrain30 | ENEMY TERRAIN PASS: 2414 assertions; fps cap=30 |
| reload | ENEMY TERRAIN RELOAD PASS |
| tactics | ENEMY TACTICS PASS: 1242 assertions; fps cap=60 |
| followup | ENEMY FOLLOWUP PASS: 221 assertions; fps cap=60 |

新規enemy_terrainは60fps上限4758／30fps上限2414項目。回転済み実マップの坂→踊り場→home、3段階段→home、単独0.25／0.5／1m段差→homeを両敵で確認。全移動のphysics時間に対する変位・home範囲・Walk画像、狭い継ぎ目と崖の区別、1m段差／坂へのその場剣攻撃、壁／低い障害物、視線喪失／最終確認位置・home再索敵余裕・歩行不能時の停止を確認した。

攻撃後に相手が高所へ移った場合、理想距離3.5mで停止し続けず、実際に剣の届く場所まで通常歩行するケースも確認。追跡目標の床支持を検査し、階段の実全身衝突・昇降の可否は歩行時のnative sweepで検査する。低速0.8m/sでの移動も実測約0.800m/s、旧戦術の設定検査は受入条件を変更せず合格した。

追加の描画確認では本番雑兵／魔導士画像を使用し、坂上のNative床面魔法陣が実床法線に沿って表示されることを検証して、自動キャプチャも目視した。初期の検査用静止敵fixtureには画像設定がなく、新しいWalk画像検査が失敗したため、検査側を本番雑兵の生成手順へ修正した。ゲーム画像を変更して合格させたものではない。

共有武器0.3mを維持したジャンプ中の敵攻撃・固定照準／回避猶予、既存の剣／踏み込み／攻撃後帰還と加重歩行、旧近接型と実弾・時間、魔導士の実Fire3／距離外確定詠唱・10秒待機／大きな炎被弾とGuard貫通、主人公のGuard／方向帰還／コンボ／近距離省略、赤白flash／画像・撃破の弾み／Cry1、実mainの起動／敵切替を回帰した。魔導士の待機／発射間隔は従来どおり約10.0167秒／11.15秒。

検査は開いたユーザーのエディターや一時DLLと競合しない、同一ソースの `.godot/mage_fire_validation/` で実行。変更したソース／検査8ファイルのrootとのバイト一致を照合。APPDATA／LOCALAPPDATAは検査プロセスだけworkspace内へ分離。最終headless editor importは終了0、実行ログ／importにScript／Shader／参照エラー・警告なし。git diff --check合格。開始時の一時DLL削除はそのまま維持。

結果一覧 `.godot/terrain_results_final.json`、実行ログ `.godot/terrain_final_*`、最終import `.godot/terrain_import_final.log`。計測と画像は検証コピーの `.godot/enemy_terrain_metrics.json`／`terrain_goal_*.png`／`terrain_mage_slope_circle.png`（Git対象外）。

再現例（プロジェクト直下PowerShell、Godotは1プロセスずつ）：

```powershell
./tools/validate_mage_fire.ps1 -ImportOnly
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
$validationRoot = '.godot/mage_fire_validation'
& $godotExe --path $validationRoot --script res://tests/enemy_terrain.gd
& $godotExe --path $validationRoot --script res://tests/enemy_terrain.gd -- --fps30
& $godotExe --path $validationRoot --script res://tests/enemy_terrain.gd -- --reload
& $godotExe --path $validationRoot --script res://tests/m09_startup.gd
```

ユーザーF5操作の受入は未実行。

## F5確認（未実行）

1. F8→F5。「近接敵」「遠距離敵」をそれぞれ選び、home範囲内でテストマップの坂を上って踊り場へ誘導する。最上部がhome範囲外なら追跡を終えるのは正常なので、地形だけを見る場合は一時的にLeash Radiusを広げ、範囲確認時に9／10mへ戻す。敵も坂を上り、自然な速度で歩くこと。
2. 0.25m／0.5m／1mの階段へ誘導し、両敵が上り下りすること。段差が大きい場合の短い上り動作の見た目を確認する。
3. 主人公を敵のhome水平範囲9m／10mの外へ移動する。追跡が止まり、歩いてきた坂／階段を戻ってhomeで止まること。境界で何度も追跡／帰還を切り替えないこと。確定済みの魔導士詠唱は従来どおり一発放ってから帰還する。
4. 階段や坂の裏へ短時間だけ隠れて再び現れる。約1.75秒以内なら即帰還せず、見失い続ければhomeへ戻ること。壁越しに攻撃しないこと。
5. 1m段差の上から、雑兵の剣の届く距離へ近づく。無理に踏み込まずその場で攻撃し、通常ジャンプ中も高さが届くなら命中すること。横移動で範囲外へ出れば回避できること。
6. 壁・低い障害物・床下・崖の向こうへの不正な命中／移動がないこと。歩けない場合は歩行表示を止めて待機すること。
7. 雑兵の左右／前後移動・踏み込み／攻撃／attack_anchor帰還、魔導士の床面魔法陣／Fire3／炎弾／Guard貫通と被弾・10秒待機、主人公の左／J攻撃・防御・Space・3連撃・方向帰還・Q/Eとターゲットマークを確認する。

複雑地形の全般、動的な帰路封鎖、長時間性能／ループ、実機パッド、全ての任意形状での段差昇降は未確認。今回の見た目・聴感と実際の回避しやすさはユーザーF5確認待ち。
