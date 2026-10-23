# M09 攻撃範囲内での踏み込み省略（2026-10-23、ADR-023）

状態：M09追加改善として実装、ユーザーF5受入待ち。M08試作範囲完了、M10別指示待ち、既存の個別未検証事項を維持する。

## 開始時の照合

HEAD `a5c317a`、main、git statusクリーン。AGENTS、開発状況、ADR-008〜022、M06〜M09を含む10／11／12／14と実物を確認。直前の調査どおり、近距離でも初撃は必ずApproachへ入り、停止距離1.1m以下でも最低0.25秒の移動状態と帰還状態が残っていた。武器の実リーチ1.4mと停止距離1.1mが別で、1.3m先へも踏み込んでいた。

現在の設定原本にはユーザー保存済みのframe_time_ratios=[0.4,0.2,1.5]がある。これを初期比率へ戻さず維持する。今回の目的は移動分岐と安全検査の共用であり、装備／敵AI／アニメーション全体の改修ではない。

## 実装

- 初撃も予約先への連撃も、対象へ向くことを前提に既存の命中形状で到達可否を確認。範囲内は直接_start_strike、範囲外だけ従来の_begin_travel(Approach)を使う。別の敵への近距離連撃、防御後の近距離追撃でも同じ分岐を使用する。
- 従来の命中形状の確認を_strike_in_rangeへまとめ、攻撃判定と移動判定が共用する。初期鉄の剣は既存MeleeSweep.contains（melee_reach1.4m・前方100度・高低差条件）。ターゲットへ向くため選択対象の方角を使う。命中時は従来のstrike_facingで受け手を列挙する。
- 検査用の旧SINGLE_TARGET方式は従来のstop_distance+0.1m（既定1.2m）の命中条件を共用し、範囲やダメージを変更しない。正式な鉄の剣と将来のSWEEP武器はWeaponData.melee_reachで分岐する。
- 範囲外の停止距離は既存1.1mを基本とし、SWEEPのリーチがそれより短ければリーチまでに収める。移動速度・時間上下限・smoothstep・実カプセル・安全余白・接触解消の上限は維持。
- 近距離では踏み込み状態全体（移動・Jump姿勢・移動の最低時間・到着後待機）を省略し、現在位置から通常の攻撃を開始する。剣振り、フレーム配分、命中タイミング、段間、入力猶予、最終待機は既存設定をそのまま使う。
- return_anchorはシーケンス開始時に一度だけ記録。最後に現在位置がその基準とis_equal_approxで一致するならReturnへ入らず通常の_finish(true)を呼び、予約・姿勢・カメラ固定・入力制御を解除する。移動していれば既存Return。方向入力で中断した未移動の攻撃も即終了し、移動済みなら従来の帰還を行う。
- 既存の命中進行、1振り1回／HP所有者の重複除外、支払い・予定スロット、撃破後の無表示待機、生存予約先への継続は変更しない。AttackHitboxという独立ノードは現行実装に存在せず、TargetDashの既存_strike_targetsとHealthComponentへの適用を維持する。新しいダメージ経路・Hitboxは追加しない。

## 距離と安全性

| 用途 | 現在の基準 | 今回の扱い |
|---|---|---|
| 金色マーク／対象選択 | WeaponData.attack_range=5m、足場・壁・ストック等 | 維持。連撃は最初のreturn_anchor基準 |
| 実際の鉄の剣の命中範囲 | melee_reach=1.4m、前方100度 | 判定を共用して踏み込みを省略 |
| 遠距離からの停止位置 | stop_distance=1.1m | 基本値を維持、短いSWEEPリーチだけ上限にする |
| 画像の大きさ | 剣112px／主人公48px | 攻撃距離・判定には使用しない |

近距離では従来の「踏み込み先までの安全検査」だけでは、敵までの途中にある隙間を調べきれない。DashPath.clearからカプセル掃引と5点の足場サンプリングを抽出し、strike_clearで見通し・地形だけの掃引・敵まで連続する平坦な足場を確認する。選択、予約、攻撃継続、巻き込み相手の命中時に共用する。

地形掃引は既存の主人公カプセル・原寸・margin0・床から0.01mの分離を使用するため、旧0.8mの見通しrayより低い障害物も拒否する。ダメージ判定ではなく、既存の保守的な経路安全性を近距離にも適用する処理。地形layer1を使い、複数の敵を巻き込むSWEEPを敵本体の衝突で遮らない。壁際の小さな接触は既存の最大0.002mのnative接触解消で仮想経路を平行移動し、見た目・実位置を動かさず検証する。壁の除外・カプセル縮小・無制限な補正はしない。

斜め壁に沿う既存検査では、敵側の端点に約0.02mmの接触があり、移動先の手前までは通れても、敵中心までの追加掃引だけが拒否されるケースを再現した。端点に実際の接触点ペアがある場合のみ、同じcontact_recovery_limit以内で仮想端点を補正し、経路全体を再掃引する。途中の壁で終端が接触しない場合、接触が深い場合、補正後も壁を横切る場合は拒否する。移動用clearは従来どおり端点許容0で変更なし。接触点ペアの順序・motionを無視する仕様は[Godot公式API資料](https://docs.godotengine.org/en/4.5/classes/class_physicsdirectspacestate3d.html#class-physicsdirectspacestate3d-method-collide-shape)を確認し、実際の検査は4.7.2で行った。

範囲境界は同じ命中条件をそのまま使用し、新しい別距離・画像ベースの範囲・毎tickの移動先変更は追加しない。1回の攻撃開始前に分岐を決め、境界でApproachを繰り返さない。

## 変更ファイル

- 本番：`scripts/player/target_dash.gd`、`scripts/combat/dash_path.gd`。
- 新規検査：`tests/in_place_attack.gd`とGodot生成UID。
- 既存検査：`tests/fixtures/combat_scene.gd`（F5で調整したResourceから独立した固定モーションの複製）、`tests/attack_motion.gd`（Resource非破壊確認で原本の値を記録して比較）、`tests/defeat_return_timing.gd`（一度も移動しない対象消失時はIdle終了も測定）、`tests/m08_defense.gd`（未移動時の即終了・移動済み時のReturnを区別）、`tests/weapon_sweep.gd`（長リーチで前進しなくなった分の受け手を現在位置から期待）、`tests/m09_enemy_dash.gd`（近距離の直接攻撃／短リーチでの実Approachの両方で敵の実被弾を確認し、両者帰還検査は実際に踏み込む距離から開始）。
- 文書：README、08／10／11／12／14、DEVELOPMENT_STATUS、本書。マイルストーンはM09のまま。
- 画像、Shader、PlayerSprite／武器・効果表示、Motion設定クラス／保存原本、敵AI、Controller、Camera、HP／ダメージ式は変更しない。

## 自動検査

Godot4.7.2／Windows／Compatibility、物理60Hz。検証用Godotは1プロセスずつ実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/in_place_attack.gd -- --capture
& $godotExe --path . --script tests/in_place_attack.gd -- --fps30
& $godotExe --headless --path . --script tests/m07_wall_contact.gd
& $godotExe --headless --path . --script tests/defeat_return_timing.gd
```

新検査は実際の物理／アニメーション／HP通知を使用し、hitコールバックを手動実行しない。近／遠・1.399／1.4／1.401m境界・短／長リーチ・旧SINGLE_TARGET・重み付き3コマ×4方向・Q/E・3連撃・1／2撃目撃破・A近→B遠→C近・方向中断／Guard追撃・FREEジャンプ・高い壁／低い障害物・途中に出現する壁・巻き込み相手の壁・両端だけ足場がある隙間・段差を確認する。実入力が処理される物理tickに合わせて開始する。

初回検査で、終了直後のSpace解放待ちを待たずに押すfixtureを修正。30fpsでの描画／物理時計の量子化は既存の撃破帰還検査と同じ最大4物理tickで比較する。範囲・ダメージ数・未移動・空振り防止の条件は緩めない。旧検査の「未移動でも必ずReturn状態」「長リーチでも必ず1.1mまで前進」の前提だけを新仕様へ更新する。ユーザーの保存済みフレーム配分を標準値へ書き換えて合格させない。

最終結果は**16種類・17条件すべてPASS／終了0**。最終採用ログは`.godot/in_place_final_results.json`に記録し、追試分は`in_place_verified_*.log`、それ以外は`in_place_final_*.log`を使う。初回の失敗ログを最終合格結果として扱わない。

| 検査 | 最終結果 |
|---|---|
| in_place_attack・実描画60上限 | PASS、3298 assertions |
| in_place_attack・実描画30上限 | PASS、1793 assertions |
| m07_wall_contact | PASS。斜め／平行／離脱／逆側／角／深い接触・連撃・塞がれた予約先 |
| defeat_return_timing | PASS、1869 assertions。従来の通常3段／各段撃破74tick、5段128tick |
| attack_motion／attack_motion_loading | PASS、1684／14 assertions |
| weapon_effects／weapon_sweep／player_damage_visual | PASS、2260／228／139 assertions |
| m09_enemy_dash／m09_enemy_combat | PASS、171／56 assertions。敵側コードは変更なし |
| m06_target_dash／m07_chain／m07_combo／m08_defense／m08_guard_sprite／m09_startup | 全PASS |

近距離1.3mでは攻撃開始まで0物理tick・最大位置ずれ0m。遠距離3mでは15物理tickで攻撃開始、1.9m前進後に元位置へ帰還。一振り開始以降の自然終了は60上限で両方59tick、30上限で近60／遠59tick。近距離3段の通常／1段撃破／2段撃破は、60上限ですべて101tick、30上限ですべて102tickで一致した。

敵AIとの追加検査の旧前提「1.2mでもApproach」は新仕様ではAttackとなるため、鉄の剣の直接攻撃と短い試験リーチ0.9mのApproachの両方でHP90への実被弾を確認する形に更新した。同時帰還の検査も、主人公が実際に踏み込む距離から開始する。敵AIや被ダメージ処理を変えて検査へ合わせていない。

4つのカメラYawの中央コマ画像を目視し、剣／白斬撃・床・敵との表示を確認。全12コマの同期・設定維持は新自動検査でも確認。最終editor import終了0、新規検査UID生成、スクリプト／Shaderエラーなし、git diff --check成功。証明書読込とsandbox外のeditor_settings保存に関する環境ERRORは別扱い。保護対象の画像・Resource・描画・AI・Controller・CameraにHEAD差分なし。検証用Godotは終了済み。

`in_place_metrics_60／30.json`、`iron_sword_in_place_*.png`および上記ログは`.godot`内のGit除外ファイル。

## F5手動確認（未実行）

1. **F8→F5→「静止敵」**。近くの敵まで通常移動し、剣が届く距離からクリック／J。踏み込み姿勢と前進なしで、通常の3コマ・剣・白い斬撃が始まり、終了時も足元が動かないことを確認。
2. 同じ敵から離れて攻撃。従来の踏み込み→攻撃→最初の位置への帰還があることを確認。金色マークが出る5m圏内でも、1.4mより遠ければ踏み込む。
3. 境界を正確に試す場合はF5中の「リモート」でTrainingEnemyのPositionを(-6,0,-1.3)、主人公を初期地点のままにする（このマップの初期地点は約(-6,0,0)）。敵のZを-1.399／-1.4／-1.401に一つずつ変えて、近距離と踏み込みの境界で小刻みな移動を繰り返さないことを確認。リモート変更はF8で破棄される。
4. 近距離の同じ敵へ3連撃。HUDの段数・ストック、剣／斬撃の同期を確認。先にHPを10／20へ減らしてストック回復後に再攻撃し、途中撃破でも残り時間は待機し、空振りせず通常終了することを確認。
5. 近→遠→近の再現配置は、主人公初期位置のまま、リモートでTrainingEnemy=A(-6,0,-1.2)、TrainingEnemySecond=B(-3.3,0,-1.2)、TrainingEnemyThird=C(-4.4,0,-1.9)。Aをクリックし、攻撃中にBを予約、2段目開始後にCを予約。Bだけへ踏み込み、Cはその位置で攻撃し、最後は最初の主人公位置へ戻ることを確認。
6. 攻撃中にQ/Eで4方向へ回し、全3コマと手元・弧・描画順を確認。Motionの比率／Attack Durationを変更しても共通進行が維持されることを確認。調整原本の[0.4,0.2,1.5]は今回維持している。
7. 近距離攻撃中の新しい方向入力は、その場で中断して通常操作へ戻る。移動済みの攻撃では最初の地点へ帰還する。I防御・防御後の近距離追撃、終了後のWASDとSpace、近接／遠距離AIモードの被弾も確認。Spaceを戦闘中から保持した場合は従来どおり一度離して再入力する。
8. 壁の向こう・低い障害物・段差・崖を挟む敵は、近くても選択／攻撃できず、ストックが減らないことを確認。動作中に経路が塞がれた場合も、安全中断することを確認する。

ユーザーF5の10項目、操作感、実機パッド・長時間・任意の複雑地形／大型敵は未実行。M09の追加改善として受入待ち、コミット／プッシュ未実行。
