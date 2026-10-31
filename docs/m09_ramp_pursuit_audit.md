# M09追加修正：坂の接触・予告中断とデバッグ追跡

2026-10-31／ADR-052。M09基本戦闘完了を維持し、今回の追加修正のユーザーF5確認は未実行。M10は別指示待ち。commit／pushは実行しない。

## 事前確認・原因

AGENTS・開発状況、関連仕様08／10／11／12／14、指定された敵AI／歩行・高低差／剣／平地Dashを照合。開始時からの`addons/effekseer/bin/windows/~libeffekseer.x86_64.dll`の削除差分は保持し、復元／追加削除をしない。

実マップの坂に実カプセルを下向き掃引で接地させて再現した。下端・上端は足元が単一平面に一致しない。特に上端は、回転した坂の板の短い急傾斜端面へ中心の床rayが当たり、カプセルは支持されていても地面未検出／支持不可となる。同高度の踏み込みでも中心rayだけで「両端が平地」と判断し、坂への接触を含む経路を平地Dashの失敗で打ち切っていた。剣の経路も両端の中心が平地ならその判定で終了していた。

予告中の追跡計画は1回の失敗で即帰還していた。また診断の具体的な理由をgenericなcancelledで上書きしていた。

## 地形と攻撃の修正

- TerrainGroundに実地面の検査を共通化。通常の歩ける面は1本のrayで返す。小さな継ぎ目では両側の歩ける実支持面を要求し、既存の歩行側の最大0.15mの探索余裕／支持高さ差を使用する。戦闘側の探索余裕はカプセル半径にも制限する。両側で支持されない崖・穴、垂直壁・天井は認めない。急な板の端面を歩ける坂として無条件に扱わない。
- Elevationの単一平面の検査をまず維持し、不一致時だけ足元の面の連続性を密に検査する。床が欠けたり実法線から説明できない急な高低差があれば拒否する。候補の実カプセル着地・往復の全身掃引／他キャラ・壁／天井は継続する。
- 同高度の平地判定は中心だけでなく足元全体で判断する。平地DashPath自体は変更しない。剣の平地検査が失敗しても、独立した剣の線／地面／遮蔽物検査へ進む。移動許可とは分離する。
- 予告中の一時失敗は初期0.12秒、移動せず再計画する。無効な古い経路では発進しない。再検査で安全と確認できたときだけ既存の照準固定／最低猶予へ進み、継続失敗なら具体的な理由で中断する。赤点滅とFire1を再開・重複再生しない。

剣の上下1.8m、跳躍踏み込みの上り1m／下り1.1m、通常ジャンプ・踏み込み／帰還速度とダメージ値を維持する。

## 無制限追跡

- PracticeEnemyの`debug_unlimited_pursuit`は既定false。ONでは索敵距離・home半径・視線喪失時間だけを理由に追跡を中断しない。プレイヤー位置は見えなくても追跡目標に使うが、攻撃には従来の視線・剣／発射判定を要求する。
- inside_homeとEnemyWalkの通常歩行・小段差・ジャンプ経路の境界を同じフラグへ統合。OFFへ戻すと9m／10m等の元の設定が復帰する。範囲外でOFFにした場合は、確認済みのhome経路を内側へ戻る移動を許可する。
- デバッグ時だけ、既存の安全な歩行検査を使った局所A*で障害物を迂回する。0.75m格子・半径6m・最大160展開、失敗時の再探索は0.75秒間隔。遠くの目標へは局所経路を更新する。全マップのNavMeshや任意の大迷路の経路保証ではなく、追跡距離の上限を撤廃する仕組みである。経路が見つからなければ停止し`NO_SAFE_LOCAL_ROUTE`を表示する。
- 通れる直進経路を優先し、主人公のカプセルに重なる到着点を避ける。段差は既存の安全な自動ジャンプ計画を利用し、実移動はEnemyWalkだけが所有する。別のジャンプ時計や瞬間移動は作らない。
- 長い歩行プローブが段差を越えられなくても、安全な次の1歩で通常の段差／ジャンプ開始位置へ近づける。迂回中は経由点を保持し、実際に直進が通れる時だけ短縮する。歩行プローブは最初の床接触が後方の壁を隠さないよう、支持平面からのカプセルの離隔を計算した掃引と到着点の全接触も検査する。これは検査座標だけで、実体を移動させない。
- 雑兵の攻撃後の周辺移動・攻撃anchorへの帰還、魔導士の射程内停止／魔法・詠唱後の行動を維持する。プレイヤー死亡時は既存の帰還、敵死亡時は即DEAD／衝突無効を優先する。

## Inspector

| 場所 | 項目 | 初期値・作用 |
| --- | --- | --- |
| 通常のPracticeEnemyノード | Debug Unlimited Pursuit | OFF。敵種に共通 |
| Main/PracticeSelector | Debug Unlimited Pursuit | M09テストマップのみON。切替で生成する両敵へ適用 |
| Main/PracticeSelector | Show Enemy Diagnostics | M09マップのみON。生成する敵のShow Attack Diagnosticsへ適用 |
| 各敵のSettings→Melee aim commitment | Windup Replan Grace Seconds | 0.12秒、0〜0.30秒／0.01刻み |

起動中の敵はRemoteツリーのM09PracticeEnemyでDebug Unlimited Pursuitを直接切り替えられる。保存する初期設定はPracticeSelectorを編集してF8→F5または敵モードを切り替える。通常ゲームの敵Resourceのdetection_radius／leash_radiusは大きくせず、元の9m／10mを保持する。

Show Attack DiagnosticsはAI状態・UNLIMITED／BOUNDED・対象までのXZ距離・MOVEの停止／迂回理由、START／ABORT／HITを分けて表示する。既存Show Debug StateとともにOFFにすれば通常プレイで非表示にできる。

## 変更ファイル

- scripts/combat/terrain_ground.gd＋UID（新規）
- scripts/combat/elevation_path.gd、melee_terrain.gd
- scripts/enemies/practice_enemy.gd、enemy_walk.gd、enemy_settings.gd、practice_selector.gd
- scripts/enemies/enemy_pursuit_route.gd＋UID（新規）
- scenes/main.tscn（テスト用フラグのみ）
- tests/ramp_contact_attack.gd、unlimited_pursuit.gd＋各UID（新規）
- tests/fixtures/combat_scene.gd（既存検査は正式な距離制限のOFF条件へ固定）
- AGENTS・進捗／ADR・テスト計画／戦闘仕様・本書

## 検証

Godot 4.7.2／Windows・Compatibility、60fps上限の同一ソース隔離コピーで、次の12種類すべてPASS・終了0。採用ログにSCRIPT ERROR／ERROR／WARNINGなし。観測フレーム数によって項目数は変動する。

| 検査 | 今回の結果 |
| --- | --- |
| ramp_contact_attack | 915項目 |
| unlimited_pursuit | 5439項目 |
| elevation_controls | 228項目 |
| terrain_attack | 138項目、既存30場面 |
| enemy_auto_jump | 5837項目 |
| m09_enemy_combat | 56項目、通常索敵／home・視線・攻撃／死亡・UI |
| enemy_tactics | 1238項目、照準固定／回避・攻撃後歩行 |
| mage_cast_commitment | 29項目、回復10.0167秒／発射間隔11.15秒 |
| m08_defense | 防御・方向帰還・入力保持／解除・消費／命中PASS |
| m07_chain | 対象切替・3連撃・帰還・カメラPASS |
| terrain_diagnostics | 128項目、表示ON/OFFと実ダメージ |
| enemy_jump_strike | 547項目、通常ジャンプ中の敵攻撃継続／実高度命中 |

ramp_contact_attackは坂の下端／途中／上端の近距離／遠距離の80配置（接合付近は0.05m刻みも含む）、実予告からの1回命中・帰還、一時遮断の再確認とFire1単発／継続遮断の中断理由を検査した。unlimited_pursuitは両敵の実9m／10m越え、OFF後のhome帰還、範囲外の段差ジャンプ・実坂／階段、壁の迂回／閉塞と崖、既存の剣・魔法と死亡を検査した。M09の切替ボタンが両敵へ実際にONを転送し、通常敵の既定OFFと元Resourceの9m／10mが保たれることも確認した。

崖の停止検査は任意の座標の手前で止まることではなく、既存のカプセル95%幅の支持面が床端の内側にあり、接地・非空中／非ジャンプを維持することを要求する。移動不能な壁では実体がすり抜けず、局所経路の失敗理由が表示されることを確認する。

最終エディターimportと実mainの30フレーム起動も終了0・エラー／警告なし。ログは`.godot/ramp_pursuit_*.log`、集計は`ramp_pursuit_results.json`。検証コピーは`.godot/mage_fire_validation`、変更コード／Scene・検査とUIDの16ファイルはSHA256一致。主人公コード・平地DashPath・武器値・画像／音／エフェクト／カメラはHEAD差分なし。git diff --check合格。

再現はPowerShellで`./tools/validate_mage_fire.ps1 -ImportOnly`、Godot 4.7.2へ`--path .godot/mage_fire_validation --script res://tests/ramp_contact_attack.gd`または`res://tests/unlimited_pursuit.gd`を指定し、1本ずつ実行する。

## F5確認（ユーザー未実行）

1. F8→F5で近接敵・遠距離敵を切り替える。診断のUNLIMITEDを確認し、homeから9m／10m以上離れても追跡すること。
2. 実坂の下端・途中・上端へ誘導し、雑兵が赤予告→その場攻撃／安全な踏み込み→帰還を行うこと。接触時のSTART／ABORT理由も確認する。
3. 階段を登り、両敵が歩行／自動ジャンプで追いかけること。坂から階段へ誘導した場合も確認する。
4. 壁の陰へ移動し、安全な迂回または停止となり、壁越し攻撃や崖への移動が起こらないこと。停止時のMOVE理由を確認する。
5. 魔導士は射程に入ると停止して魔法を使用し、離れれば再追跡すること。
6. RemoteのDebug Unlimited PursuitをOFFにし、通常のhome帰還・視線喪失と再索敵の範囲が復帰すること。
7. 主人公の攻撃・防御・ジャンプ／方向帰還・3連撃、マーク・画像／音／撃破表示を確認する。

見た目と操作感の受け入れ、任意の複雑地形／大迷路・多数敵／長時間性能は未確認。局所探索の半径／展開上限内で解けない経路は停止する。
