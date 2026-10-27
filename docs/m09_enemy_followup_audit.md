# M09完了後：敵Idle・高速予告音・雑兵の位置取り（ADR-035）

2026-10-27。M09基本戦闘の完了を維持し、今回の追加改善はユーザーF5・見た目／聴感／動きの確認待ちとして管理する。新工程なし、commit／push未実行。開始HEAD：51f3961d1d803b1285acd1f6f78ec950bc55d084、開始時git statusはクリーン。

## 1. 実ファイルと画像名の対応

| 役割 | 現在の元画像 | ゲーム用PNG | 旧名との対応 |
|---|---|---|---|
| 雑兵Idle | 画像フォルダ/敵/雑兵_wait.png | assets/sprites/enemies/zouhyou_idle.png | 新規接続 |
| 雑兵Walk | 画像フォルダ/敵/雑兵_walk.png | assets/sprites/enemies/zouhyou_walk.png | 旧雑兵_w.pngと同一バイト |
| 雑兵Attack | 画像フォルダ/敵/雑兵_a.png | assets/sprites/enemies/zouhyou_attack.png | 変更なし |
| 魔導士Idle | 画像フォルダ/敵/魔導士_wait.png | assets/sprites/enemies/mage_idle.png | 新規接続 |
| 魔導士Walk | 画像フォルダ/敵/魔導士_walk.png | assets/sprites/enemies/mage_walk.png | 旧魔導士_wl.pngと同一バイト |
| 魔導士Attack | 画像フォルダ/敵/魔導士_a.png | assets/sprites/enemies/mage_attack.png | 変更なし |

全6枚とも現在は144×192、横3列×下／左／右／上の4行、1コマ48×48。主人公の既存行対応と画像内容を照合。WalkのSHA256は雑兵86bcfd80474041a85ed0cf7d75936f55c2c5b3d73c4a8c18266be581cb0d34c3、魔導士ce2795e7f13ad6f9f38a3011e8d2c8267b4af72884d25096f4912761b1d4743bで、以前のゲーム用コピーと一致。推測で別画像を割り当てていない。既存のWalk／Attack PNGは変更せず、Idleだけ無加工コピーして接続した。元画像の削除・改名・描き直しはしていない。

IdleのSHA256：雑兵655f924c7039c5b774145dc005fda9de5fad68ae52f1b0bc9b4fd859b0a8dd05、魔導士2c8f6ced7f08f9e5d13ca5c576256f926e5e26423f53c81429846a490f9b9619。**各方向の横3コマは全画素が同じ**。エンジン上は3コマを循環するが、現在の素材のままでは待機中に見た目の動きはない。素材の差分を勝手に制作しない。

実行時の画像参照は従来の英数字名を維持し、素材台帳の旧Walk名を新しい元ファイル名へ更新した。scripts／resources／scenes／assets／project.godot／現行画像importに旧日本語名の参照なし。過去の監査本文の旧名は作成当時の履歴として保持する。

## 2. Idle／Walk／Attack

EnemyVisualにIdle FramesとIdle FPSを追加。初期4fpsで、3フレームを0→1→2→0と繰り返す。Idle SpriteFramesの基準速度は1、実行時speed_scaleをIdle FPSへ換算し、共有Framesを書き換えず1つの主設定で速度を決める。

- 待機・停止中のCHASE／RECOVERY：Idleループ
- 通常歩行・踏み込みDASH_APPROACH・攻撃帰還DASH_RETURN・帰還後の歩行：Walkループ
- WINDUP：既存のAttack先頭による予備姿勢を維持
- ATTACK：従来の加重共通タイムラインでAttack画像・剣・白い斬撃を同期
- 死亡：Idleの先頭を静止保持。死亡専用画像は未提供

移動がないクールダウン中に古いvelocityが残ってWalkにならないよう、CHASEの停止時は表示用velocityを0へ戻す。実際の移動方式・魔導士の攻撃時間は変えない。

敵の方向は既存のカメラbasisとdirection_sector、pixel_size／sprite_offsetも既存値を使用する。画像の寸法を48pxに正規化しない。Atlasは元画像の実寸から作成し、コードに48px固定の処理はない。検査では既存の112px Atlasをテスト用に割り当て、サイズが異なってもpixel_sizeが維持されることを確認する。

## 3. 高速予告とFire1

初期切替間隔は0.09秒。通常0〜0.09→赤0.09〜0.18→通常0.18〜0.27→赤0.27〜0.36→通常色、という短い2回の演出にする。近接0.9秒／遠距離1.0秒のWINDUP自体は維持し、点滅が先に終わっても攻撃開始を早めない。回数は予告に収まる数へ制限し、2区間より短い予告は従来どおり単発点灯へフォールバックする。

色・強さ・Count・Flash Enabledと白い被弾flash優先は既存の仕組みを再利用。Flash Intervalを0.08〜1.0秒で調整でき、Flash Enabled=falseで赤色を無効化できる。

Fire1は`RPGツクールMZのaudio/se/Fire1.ogg`（8596bytes）を選択し、`assets/audio/sfx/mz_fire1.ogg`へバイト一致コピーした。BGSフォルダーの同名ファイルは選んでいない。SHA256：a56d0f918a26a7661d9a15e718ef771e379490bd9991fac7de0fa97111be578e。非ループ、初期-12dB・pitch_scale=1.0。

PracticeEnemyがWINDUPへ実遷移した時だけattack_warning_startedを通知し、既存AttackWarning内のAudioStreamPlayerで1回再生する。同じ状態の保持・色の切替では再生しない。移動予約のタイムアウト等で新しいWINDUPに入り直す場合は、その新しい予告につき1回。FlashとSoundのON/OFFは独立しており、点滅を切っても音の予告を利用できる。死亡／解放で再生を終了する。既存の攻撃・命中・防御・ジャンプ等の音声設定／処理は変更しない。素材の利用条件は既存と同様、独立確認済みとは扱わず台帳へ記録。

## 4. 雑兵の帰還後の位置取り

既存のIDLE／CHASE／WINDUP／DASH_APPROACH／ATTACK／DASH_RETURN／RECOVERY／RETURN／DEADを利用し、新しいAI状態や戦闘システムは作らない。

雑兵だけPursuit Enabled=true。攻撃と元位置への帰還を完了した後、既存3秒RECOVERYの残り時間内で通常歩行により次の位置を整える。既存クールダウンとRECOVERY経過時間は進み続け、歩行で短縮・延長・再開始しない。時間が来て攻撃開始範囲内なら次の予告に入る。範囲外なら既存CHASEから距離を詰める。

初期Preferred Attack Distance=5mは現在の踏み込み攻撃開始範囲と同じ。**主人公がすでにこの距離内なら無理に歩かず待機する**。主人公が離れた場合はSpeed=2m/sで、Step Distance=1mを目安に安全な区間目標を更新する。歩行区間を細かくしても、1物理tickの移動量より区間を小さく制限して速度が落ちないようにする。区間や最終位置への到達フレームだけ残距離へclampする。転送・イージングは使わない。

目標距離は現在の攻撃開始範囲以下、元の停止距離・カプセルの余裕以上へ解決する。境界の再開には0.1mの帯を設け、停止位置は丸めで射程外に残らないよう最大5mm内側へ補正する。目標が小さすぎても元の停止距離1.1mと当たり判定の余裕を守る。Pursuit OFFでは従来どおりRECOVERY中に待機し、終了後は通常CHASEを使用する。

各_start_windupで現在位置をattack_anchorへ記録する既存仕様を維持。帰還中や歩行中には書き換えない。Aから攻撃→Aへ帰還→Bへ歩行→Bから攻撃→Bへ帰還となる。homeは索敵／縄張りからの通常帰還用として別に保持する。

追跡はRECOVERYと攻撃後のCHASEだけ。予告・踏み込み・攻撃・帰還・死亡では動かさない。既存Path.clear／move_and_collideを使い、壁・同じ足場高・足元全体・崖／段差・元のleashと視線、主人公の攻撃による対象予約を尊重する。行けない場合はvelocity=0で安全に停止する。魔導士／weapon未指定の旧AIには新追跡を適用しない。

## 5. Inspector

| 調整場所 | 項目 | 初期値／範囲 |
|---|---|---|
| resources/enemies/zouhyou_visual.tres、mage_visual.tres | Idle Frames／Idle FPS | 新Idle、4.0fps／0.1〜30fps |
| melee_practice.tres、ranged_practice.tres → Attack warning presentation | Flash Interval | 0.09秒／0.08〜1.0秒・0.01刻み |
| 同上 | Flash Count／Color／Strength／Enabled | 2／赤／0.75／ON（既存項目） |
| 同上 → Attack warning sound | Sound／Sound Enabled | mz_fire1.ogg／ON |
| 同上 | Volume Db／Pitch Scale | -12dB（-60〜0）／1.0（0.5〜2.0・0.01刻み） |
| melee_practice.tres → Post-attack pursuit | Pursuit Enabled | 雑兵ON、魔導士OFF |
| 同上 | Pursuit Speed | 2.0m/s／0.1〜10m/s |
| 同上 | Preferred Attack Distance | 5.0m／Inspector0.5〜20m、実行時は有効な攻撃距離へ制限 |
| 同上 | Pursuit Step Distance | 1.0m／0.1〜3m |

全て既存Resourceへ保存できる。実行中のRemote Inspectorだけで行った編集の永続化を前提にせず、元Resourceを編集して保存する。点滅と音の速度は別設定で、音のPitchは再生速度も変わる。予告総時間・既存の踏み込み／帰還・攻撃／ダメージ・射程のResource値は今回変更していない。

## 6. 追加・変更ファイル

- 新Idleの2PNG／2SpriteFrames／import：assets/sprites/enemies/*_idle*
- 新SE／import：assets/audio/sfx/mz_fire1.ogg
- scripts/enemies/enemy_visual_data.gd、enemy_sprite.gd：Idle／FPSとWalk切替
- scripts/enemies/enemy_settings.gd、enemy_attack_warning.gd：高速点滅・Fire1と調整項目
- scripts/enemies/practice_enemy.gd：予告開始通知、帰還後の安全な歩行・停止、表示用velocity
- resources/enemies/zouhyou_visual.tres、mage_visual.tres、melee_practice.tres、ranged_practice.tres
- 新規tests/enemy_followup.gdとUID、更新tests/enemy_attack_warning.gd／enemy_sprites.gd
- 素材台帳、AGENTS、README、DEVELOPMENT_STATUS、ADR-035、システム／戦闘仕様／テスト計画、本記録と過去監査への更新注記

元PNG／既存Walk・Attackコピー、主人公コード／InputMap、武器・敵攻撃時間／ダメージの設定、飛び道具コード、既存音声・被弾処理は変更しない。

## 7. 自動検証

Godot4.7.2.stable.official.ed1daf0bf／Windows、物理60Hz、Compatibility／GTX1080。**12種類15条件が全PASS・終了0**。描画試験は60／30fps上限、1プロセスずつ実行。Godotエディター読み込みも終了0、最終スクリプト／Shader／画像参照エラーなし。環境の証明書ストア読み取り・エディター設定保存ERRORは区別する。

| 検査 | 最終結果 |
|---|---|
| enemy_followup 実描画60／30 | 各75項目PASS |
| 同・別プロセス--reload | PASS |
| enemy_attack_warning 実描画60／30 | 各102項目PASS |
| enemy_sprites 実描画 | 408項目PASS |
| enemy_sword_combat 実描画 | 441項目PASS（観測数で変動） |
| m09_enemy_combat | 56項目PASS |
| m09_enemy_dash | 171項目PASS |
| m09_timing | 既存予告・回復・弾の速度／間隔PASS |
| m09_startup 実描画 | 実F5シーンの起動・左攻撃／右防御・モード切替PASS |
| combat_feedback 実描画 | 633項目PASS（観測数で変動） |
| m08_defense | 防御／方向帰還／安全移動PASS |
| m07_chain | 複数敵3連撃／照準／カメラ／帰還PASS |
| action_audio 実描画 | ジャンプ／防御開始／防御成功の既存SE等122項目PASS |

最終一覧は`.godot/enemy_followup_all_results.json`。静的保護検査で主人公・InputMap・武器／攻撃時間／ダメージ・飛び道具／被弾処理・既存画像／Walk／Attack Framesの変更なしを確認。元Idle2枚・Fire1のコピー前後一致、素材台帳の列・ID・参照ファイル、git diff --checkも確認した。

新enemy_followupは実描画60／30と別プロセス--reloadで検査する。Idle実3コマと4方向／FPS、112px Atlas対応、実WINDUPのFire1単発・ピッチ／音量／切替、実2回の攻撃・帰還とA／B、3秒RECOVERY・速度上限／実測速度・小さい歩行区間、射程停止・再開帯・対象予約・予告中の停止・壁／崖・接近しすぎ／死亡／魔導士除外、設定保存を確認する。

関連の予告描画・敵画像・敵剣・旧AI／安全経路・予告／弾時間・実F5起動／入力・白い被弾／火花・防御／連撃・既存のジャンプ／防御開始音を回帰する。以前の静止画比較は新Idleループを固定して測定し、新しい点滅時刻へ検査点を更新した。戦闘の期待値は緩和しない。

再現例：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_followup.gd
& $godotExe --path . --script res://tests/enemy_followup.gd -- --fps30
& $godotExe --headless --path . --script res://tests/enemy_followup.gd -- --reload
```

ログはGit除外の.godot/enemy_followup_*.logと結果JSON。ユーザーの実音の聴感・見た目の受入・操作のしやすさとは区別する。

## 8. F5確認・残件

1. F8停止→F5。雑兵が停止中にIdle、歩行／踏み込み／帰還中にWalk、攻撃中にAttackを使うことを確認する。待機の3コマは元画像が同じ絵なので見た目は静止する。
2. 上下左右・Q/Eで各方向を確認。VisualのIdle FPSを変更し、保存→再起動で維持されることを確認する。見た目の動きを付けたい場合は将来ユーザー側で3列に差分を用意できる。
3. 通常→赤→通常→赤→通常の素早い予告と、入り際のFire1が1回だけ鳴ることを確認する。予告時間や攻撃開始は従来どおり。Flash／Soundは個別にOFFできる。
4. 雑兵の一撃・帰還後に主人公が距離を取り、クールダウン中に雑兵が歩いて射程へ入り停止することを確認する。主人公が射程内なら不要な移動をしない。
5. 2回以上攻撃させ、歩いた後の新しい開始地点へ帰還することを確認する。壁・低障害物・段差／崖では止まり、予告／踏み込み／帰還に追跡を重ねないことを確認する。
6. 魔導士のIdle・Walk・赤予告・Fire1と従来の弾を確認。新しい雑兵用追跡をしないことを確認する。
7. 左／J攻撃、右／I防御、WASD／Space、L切替・3回コンボ・主人公の踏み込み／帰還、既存SE、白いflash／火花を確認する。

残件は追加改善のユーザーF5・聴感／滑らかさとIdle素材の表情、任意の複雑地形／大量敵・実機パッド・長時間性能。M09の基本戦闘完了は維持する。
