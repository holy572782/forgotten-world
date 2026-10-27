# M09完了後：雑兵の直前照準・戦闘中歩行・マークの影

2026-10-27／ADR-037。M09基本戦闘完了を維持、追加改善の見た目／操作感はユーザーF5確認待ち。新工程は作成せずcommit／push未実行。

## 事前確認・原因

開始HEAD `10d0790`。開始時の未コミット変更はユーザーによる旧日本語画像名の.import6枚の削除のみ。保持し、復元／追加削除や画像変更は行わない。AGENTS・開発状況・指定仕様08／10／11／12／14と既存M09監査・実装を確認。

以前は_start_windupでaimed_position／facing／dash_destinationを確定していた。帰還後の追跡もpreferred_distanceへ到達すると停止する設計だった。今回の敵AIの変更は、雑兵の予告中照準とRECOVERY／クールダウン中の歩行選択に限定する。

金色マークはTargetable._make_markerが作るImmediateMeshをMarker/Meshで描く。MeshInstance3Dのcast_shadowが既定ONのため、地面に円状の影が落ちていた。別の影SpriteやShader演出ではない。

## 照準固定と回避猶予

1. 雑兵の予告開始時はプレビューの位置だけ計算し、aim_locked=false。
2. 予告中は毎物理tick、主人公の現在位置／向き／踏み込み予定を更新する。敵自身は移動せず攻撃態勢の先頭コマを使用。
3. 元の予告0.9秒の終了時に位置・向き・踏み込み先を確定し、以後は更新しない。
4. 確定から既存命中コマまで最低猶予を確保するため、不足分だけ攻撃態勢で固定待機。その後、固定経路をWalkで踏み込み→Attack→従来どおり帰還する。射程内なら既存のその場攻撃。
5. Fire1は予告入り際の1回だけ。赤点滅の切替0.09秒と回数2、白flash優先は変更しない。固定後の不足待機では元の予告時間を過ぎているため赤点滅を繰り返さず通常色の攻撃態勢を保つ。

追加待機 = max(0, 最低猶予 − 実施する踏み込みの計画時間 − 到着後待機 − 命中コマまでの時間)。踏み込み／剣振り自体を遅くしたり、リーチ・角度・ダメージを変更したりしない。既存の物理tick丸めで最低値より少し長くなる。対象予約で移動を保留した場合は従来の保留／再予告処理に従い、危険経路では中断する。

初期値は**最低0.45秒**。ユーザー目安の0.25秒は距離4.5mの実WASD退避で被弾（実際の確定→判定0.367秒、移動約1.31m）。現行リーチ2.5m・停止距離1.1m・プレイヤー速度5m/s／加速22m/s²を維持して回避するため仮の0.45秒を採用した。近距離1.2mの後退と遠距離4.5mの横移動を、4カメラ方向の実InputMap入力で検査する。回避方向・開始位置／速度・障害物次第で被弾する場合はあり、全方向の回避成功を保証する設定ではない。

魔導士や武器未指定の既存profileはこの機能を使わず従来の予告／弾発射を維持する。設定は攻撃開始時に読み取り、共通剣／Motionの原本は変更しない。

## 帰還後の動き

- 雑兵のみ、既存3秒RECOVERYと攻撃待機中のCHASEで局所的な歩行を行う。初回接近、予告、踏み込み、攻撃、帰還、死亡には重ねない。
- 初期サイクルは左→右→軽い接近→軽い後退→短い待機→左→右→繰返し。左右各2、接近／後退／待機各1の重みを交互に並べる決定的なサイクル。敵別に重みを変更でき、全重み0は待機とする。
- 方向と目標を選択時に固定。到着しても区間の残り時間を待ち、閉塞時も即別方向へ向きを振らず次の区間まで停止。移動は毎tick最大speed×delta、Walkを再生。
- 射程＋0.15mを超えた場合は既存の安全追跡へ切替え、理想距離へ到達するまで継続。射程境界で局所移動と追跡を高速に切り替えない。
- 主人公のカプセル／停止距離、homeからのleash、同じ足場／高さ、Path.clear、move_and_collideを維持。目標区間と毎tickの両方で壁・崖を検査する。予約中は停止し、予告開始時は局所移動の目標を破棄する。
- 次の攻撃ではその時点の位置Bをattack_anchorへ記録し、Bへ帰還する。元homeと区別し、前のAへ戻すことはしない。

## Inspector

Godotファイルシステムで `resources/enemies/melee_practice.tres` を選択する。設定はResource保存で永続化する。以下は仮の初期値。

| 項目 | 初期値 | 範囲・単位 |
|---|---|---|
| Track Windup Target | ON（雑兵のみ） | ON/OFF |
| Aim Commit Minimum Seconds | 0.45 | 0.10〜1.50秒、0.01刻み |
| Combat Movement Enabled | ON（雑兵のみ） | ON/OFF。OFFなら従来の射程へ接近して停止 |
| Pursuit Speed（既存を共用） | 2.0 | 0.1〜10.0m/s |
| Pursuit Step Distance（既存を共用） | 1.0 | 0.1〜3.0m／区間 |
| Preferred Attack Distance（既存を共用） | 雑兵3.5 | 入力0.5〜20m、実際は衝突・停止距離〜攻撃開始範囲へ制限 |
| Combat Direction Interval | 0.70 | 0.20〜3.00秒、0.05刻み |
| Combat Wait Seconds | 0.20 | 0.05〜2.00秒、0.05刻み |
| Combat Strafe Weight | 2 | 左右それぞれ0〜8 |
| Combat Approach／Retreat／Wait Weight | 各1 | それぞれ0〜8 |

速度・区間距離・理想距離は既存設定を共用し、二重設定を作らない。他敵の既定は新機能OFF。将来の重装兵・素早い敵は別のEnemySettingsに速度／重みを保存できる。新敵や装備UIは追加していない。

## 金色マークの影

`Targetable/Marker/Mesh.cast_shadow = OFF`。既存のpractice_enemy／training_enemy両シーンと共通Targetable._readyで指定し、コード生成の敵でも適用する。輪／満円・色・材質・位置・billboard・クリック用Area／対象選択は変更しない。

実DirectionalLight・床で4カメラ方向の旧ON／現OFFを描画比較し、同じ金色円が残ったまま床の影だけが消えることを確認。別のBoxの影も同じライトで描画されることを確認。比較画像はGit除外 `.godot/marker_shadow_before.png`／`marker_shadow_after.png`、目視済み。シーン全体やキャラクターの影は無効にしない。

## 変更ファイル

- scripts/enemies/practice_enemy.gd（予告照準と局所歩行）、enemy_settings.gd（敵別設定）
- resources/enemies/melee_practice.tres（雑兵だけ有効化・理想距離）
- scripts/combat/targetable.gd、scenes/enemies/practice_enemy.tscn、training_enemy.tscn（マークだけ影OFF）
- tests/enemy_tactics.gd、target_marker_shadow.gdと生成UID（新規）
- tests/enemy_followup.gd（旧追跡単独profileを明示）
- AGENTS.md、docs/08・10・11・12・14、DEVELOPMENT_STATUS、本書

画像・音・Shader・武器／Motion・主人公・敵の命中処理／弾・魔導士Resourceは変更しない。新規素材はない。

## 自動検査

Godot 4.7.2、描画60／30fps上限・物理60Hzで**12種類14条件すべてPASS・終了0**。最終一覧 `.godot/enemy_tactics_all_results.json`。

| 検査 | 結果 |
|---|---|
| enemy_tactics 描画60／30fps上限 | 1242／1019項目PASS（観測数は変動） |
| enemy_tactics 別プロセス--reload | PASS |
| target_marker_shadow 描画 | 10項目PASS、4方向の実床影比較 |
| enemy_sword_combat | 445項目PASS（観測数は変動） |
| enemy_followup（旧追跡profile） | 221項目PASS |
| enemy_attack_warning | 110項目PASS |
| enemy_sprites | 408項目PASS |
| m09_enemy_dash | 171項目PASS |
| m09_timing | 旧予告／回復と魔導士の弾速度・間隔PASS |
| m09_startup | 実main・左攻撃／右防御・モード切替PASS |
| combat_feedback | 631項目PASS（観測数は変動） |
| m08_defense | 防御／方向帰還／安全移動PASS |
| m07_chain | 複数敵3連撃／照準／カメラ／帰還PASS |

0.45秒設定の実WASD回避は、近距離1.2mで後退・遠距離4.5mで横移動を4カメラ方向、各fpsで全成功。観測した確定→判定は約0.467〜0.500秒（描画観測の物理tick丸めを含む）。同じ剣・同じダメージ判定で、移動しなければ1回被弾することも確認する。測定ログ `.godot/enemy_tactics_measurements.json`。

左右／接近／後退／待機と設定変更、最低区間時間、速度×実物理経過時間の上限、射程外追跡の連続性・壁／崖・死亡／遠距離除外、次回の新しい帰還基準を確認した。30fpsでは1描画間に複数物理tickが進むため、帰還直後に歩き始めた位置を帰還失敗と誤認しないようRECOVERY入り際を物理優先100のTraceで記録し、速度検査も実物理時刻差を使う。受入条件の距離・衝突・ダメージは緩和していない。

最終editor import／解析は終了0、画像／スクリプト／Shader読込エラーなし。既存のWindows証明書ストア読込エラーと、サンドボックス外のエディター設定保存拒否は残り、ゲーム側エラーと区別する。git diff --check合格。画像・音・Shader・主人公／InputMap・共通剣とMotion・命中関数・魔導士設定に変更なし。

再現（プロジェクトルートで1本ずつ）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_tactics.gd
& $godotExe --path . --script res://tests/enemy_tactics.gd -- --fps30
& $godotExe --path . --script res://tests/enemy_tactics.gd -- --reload
& $godotExe --path . --script res://tests/target_marker_shadow.gd
```

回帰は表の他のtests/<名前>.gdを同じ--scriptで実行する。ログはGit除外 `.godot/tactics_*.log`。最終読み込み `.godot/tactics_import_final.log`。自動描画・合成入力はユーザーF5の受入と区別する。

## F5と未確認事項

1. F8→F5で近接敵を選ぶ。予告中にWASDで横へ動き、攻撃態勢の敵が向きを合わせることを確認。
2. 予告後は狙いが固定される。固定直後から離れる／横へ動くと回避でき、踏み込みが追尾せず、空振り後も帰還することを確認。近距離では固定待機後にその場で斬る。
3. 一度攻撃させて帰還後、左右・軽い接近／後退・短い待機とWalk、3秒の攻撃間隔を確認。次の予告で停止し、次の帰還先が新しい開始位置になっていることを確認。
4. 主人公が射程から離れると接近を続け、射程境界で小刻みに切り替わらないことを確認。壁・段差・崖で無理に進まず、予約／被弾／死亡も確認。
5. L／マウスで金色の輪と選択円を切り替え、床にマークの影がなく、キャラクター・地形の影は残ることを確認。Q/Eの4方向でも確認。
6. 左／J攻撃、右／I防御、移動／Spaceジャンプ、方向帰還・3連撃、Fire1単発・既存SE・白flash／火花と、遠距離敵の従来の予告／弾を確認。
7. Settingsの最低猶予・速度／区間／間隔／待機／重みを1つずつ変更して保存→再起動し、狙いどおりか確認。

ユーザーF5の自然さ・緊張感・回避猶予の最終調整と聴感は未確認。任意の複雑地形／迂回、実機ゲームパッド、大量敵・長時間性能は既存残件として維持する。壁や崖の迂回経路を新設する変更ではない。環境由来の証明書・エディター設定保存エラーはゲーム側の画像／スクリプトエラーと区別して記録する。
