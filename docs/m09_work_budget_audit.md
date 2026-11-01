# M09完了後：1FPS報告に対する実マップの負荷調査（ADR-054）

2026-11-01。M09基本戦闘完了を維持。追加改善のユーザーF5確認待ち、M10は別指示待ち。commit／push未実行。

## 調査の範囲と前回の不足

受領した症状はRECOVERY／UNLIMITED・約4.19m・STEP_OR_JUMP_UNSAFE／BLADE_BLOCKEDで約1FPSになるもの。開始時はgit clean、基準は `2a60c59f15e4ec8c807b0a3bf224319163c896ec`。現在のScene・Resourceの武器リーチ2.5m、攻撃候補範囲5m・上下1.8mとユーザーの設定を保持した。

ADR-053の固定fixtureは主人公のphysics更新を止め、主人公の武器をElevationなしの旧設定へ固定していた。その測定は敵単体の負荷であり、F5全体の性能を表していなかった。今回は本番の `scenes/main.tscn` を読み、主人公の自動選択・マーク更新も止めずに測る。

**この環境では1FPSそのものは未再現。ただし同じ階段の端・開始距離4.19mのRECOVERYで約18FPS、最長292msの大幅な低下を再現した。** 修正後も移動不能な場所はSTEP_OR_JUMP_UNSAFEで停止するが、同条件では約60FPSになった。今回の短時間の結果を「ユーザーの1FPS問題が完全に解消」「すべて60FPS達成」の根拠にはしない。

## 実測で最も重かった処理

主人公の自動ターゲット選択／マーク更新からの次の呼び出しが中心だった。

`PlayerController → TargetDash.physics_step → _refresh_selection／_update_markers → _elevation_plan → Elevation.attack → plan／corridor → Ground.sample／_ray`

同一physics frame内の保存はあったが、次のtickでは破棄されるため、待機中にも攻撃・往復の詳細計画を毎tick作っていた。敵がRECOVERYであってもこの処理は継続する。途中の床検査では、既に歩ける面を検出した場所でも、遠い高さからの問い合わせのため継ぎ目用の追加rayを繰り返していた。

診断導入直後の実main測定では約2秒にElevation.attack 121回／合計約1.26秒。A*・通常ジャンプ探索・詳細表示を個別にOFFにしても攻撃計画は残り、B（攻撃計画）や主人公更新をOFFにした場合にこの負荷が消えた。これはFPSだけでなく関数の回数・合計／最大時間から判定した。

## 診断スイッチ

F5起動後、Godotの**Remote → Main → PracticeSelector → Performance Diagnostics**を開く。設定は生成される敵とPlayer/TargetDashへ同じResourceを渡すため、実行中の変更も共通で反映される。

| 区分 | Inspector名 | OFF時 |
| --- | --- | --- |
| A | Local Astar Enabled | 局所A*の継続・開始を止める。安全な直進確認は残す。迂回が必要なら停止する |
| B | Attack Planning Enabled | 詳細な近接攻撃計画と主人公の表示用計画を止める。保存済みヒントで新規攻撃を許可しない |
| C | Terrain Search Enabled | 通常歩行の新たなジャンプ／段差探索を止める。平地の接地歩行は残り、越せない段差では衝突前に停止する |
| D | Details Enabled | 敵の詳細ラベルを非表示にする。金色マークや通常HUDは維持する |

4項目は既定すべてON。診断が済んだら全ONへ戻す。既に実行中の空中移動は着地を優先し、スイッチ操作で空中停止やワープをさせない。Bは魔法属性・魔導士の攻撃データを変更する設定ではない。

**Capture Timings**をONにすると関数別`calls`／`total_us`／`max_us`を採取する。`us`はマイクロ秒で、1000us＝1ms。**Print Report**もONにすると約1秒ごとに`ENEMY WORK`を出力する。同じ内容は**Last Report**で確認できる。実際の敵／主人公位置、AI状態、移動／開始／中断理由、追跡モード、render／physics frame番号、Physics Timeとスイッチ設定も含む。通常は両項目OFFで、毎フレームのログや時間の蓄積を行わない。

関数名は`player.physics`／`player.preview_plan`、`enemy.physics`／`enemy.attack_plan`、`walk.can_reach`／`walk.jump_plan`／`walk.step_plan`、`route.goal`／`route.astar`、`elevation.attack`／`elevation.step`、`blade.clear`など。親子の合計時間は重複するため足し合わせない。

## 改善内容

1. 表示／自動選択の計画を実操作の計画と分離。表示用は1候補ずつ、1対象につき1描画フレーム1回までに分割する。処理待ちは未確定のヒントであり、攻撃許可に使わない。実入力ではフレーム内計画も破棄して新たに安全確認する。
2. 表示用の完了結果は成功0.12秒／失敗0.4秒まで保存。小さな移動では次候補を更新し、直近の有効候補を先に新たに検査する。短い更新待ちだけ旧ヒントを維持することがあるが、死亡／大きな位置変更は従来の候補条件で拒否し、入力／発進・実命中は最新の検査を通す。
3. 敵の攻撃候補も同じ1候補単位で分割。予告開始や照準確定・実移動／命中は従来の検証を残す。同期の`Elevation.attack()` APIは直接操作／安全検査用に維持する。分割候補はその1回の呼び出しで、最新の着地点・剣と全身の往復をすべて確認する。過去フレームの部分証明を接合しない。
4. 途中の床は実際の歩行面が既に得られた場合に利用し、空白や急な端面では従来の継ぎ目証明へ戻す。端点のカプセル支持・継ぎ目、元の大きさの全身移動、壁／天井・床／他キャラと復路の検査を残す。床・壁・高さの許容値を広げて通す修正ではない。
5. A*の事前確認も共通PlanningBudgetへ含める。長い3mの直進検査はセル長0.75mの安全な手前区間を優先し、実歩行の各tickの衝突／支持検査は維持する。事前確認の途中でも予算を使い切れば停止し、次の描画フレームからその段階を再開する。
6. 共通予算は1描画フレーム8検査／約1.2ms。途中で分割できない1候補／native問い合わせは残るので、厳密な1.2ms以内の保証ではない。physics catch-upでも同じ描画フレームの予算は共有する。検索の辺は予算取得後にだけ進め、未確認の辺を飛ばさない。
7. 移動側のブロック待機中は、経路／ジャンプの事前確認も待機する。保存期限は計算の終了後から数え、重い計算だけで期限を使い切らないようにする。敵の失敗候補は0.4秒保存する。
8. `PLANNING_PENDING`は「攻撃不能」と分ける。未完了だからといって停止距離を0.95mへ縮めたり、予告前に余分に歩いたりしない。危険な経路や未知の候補では発進しない。
9. その場から剣が届くかを先に調べ、届かず離陸点の支持も成立しない場合は`NO_SAFE_TAKEOFF`として候補探索前に停止する。別の着地点を探しても開始地点の危険は解消しないため、全候補で同じ失敗を繰り返さない。既存の水平経路の証明も残す。階段端からの危険な発進を許可する修正ではない。
10. キーボード攻撃では表示用の処理待ちで選択対象が一時的に空でも、実入力時に新たに有効対象を解決する。J入力を表示予算のために捨てず、マウス座標にも依存させない。

NavMeshへの移行は今回見送った。今回測れた主な負荷はプレイヤーの攻撃計画からの床確認であり、移動用A*だけを置き換えても残る。任意の大迷路／多数敵への経路探索は別途検証が必要。

## 計測条件・結果

Godot 4.7.2／Windows／Compatibility・GeForce GTX 1080（driver 572.16）、1152×720・60FPS上限。実mainの最新Resourceを使用。階段中央の開始位置は主人公(3.3,1.003,5)、雑兵(-0.89,0.253,5)で水平4.19m。階段端は両者のZを3.1へ変更する。雑兵を既存のRECOVERY（残り3秒）へ置き、行動は実AIに任せる。各ケースは1.1秒ウォームアップ後に配置し直して約2秒測定する。測定中の敵の歩行や主人公の接地は止めず、記録のpositionは測定終了時の値。

FPSはprocess frame間隔の壁時計、Physics TimeはGodot Performanceモニターを記録する。追加の末尾physics Nodeで、ノードのphysics実行区間も別に採取する。この区間はPhysicsServer全体／描画待ちと同義ではない。時間採取OFFでも同じ場面を測り、内蔵Script Profilerは単発攻撃計画の関数内訳の確認に使う。

### 階段端の切り分けと比較

各行は独立した約2秒の測定。物理時間はGodot Performanceのp95、ノード区間はphysics_frame通知から末尾の計測Nodeまでのp95。モニターの更新間隔と計測対象が異なるため両者は一致しない。

| 条件 | 修正前FPS | 修正後FPS | 物理p95 前→後 ms | ノード区間p95 前→後 ms |
| --- | ---: | ---: | ---: | ---: |
| A～DすべてON | 17.92 | 60.03 | 47.07→1.93 | 34.77→1.22 |
| A 局所A*だけOFF | 19.48 | 60.03 | 34.95→2.00 | 29.23→1.17 |
| B 詳細攻撃計画だけOFF | 60.02 | 60.03 | 5.95→2.36 | 1.12→1.28 |
| C 通常ジャンプ／段差探索だけOFF | 17.36 | 60.02 | 59.08→2.64 | 43.84→1.05 |
| D 詳細表示だけOFF | 21.38 | 60.02 | 31.19→2.04 | 27.99→1.62 |
| 主人公のphysics更新だけOFF | 60.02 | 60.02 | 1.36→2.77 | 0.83→0.90 |
| A～D ON・時間採取OFF | 20.41 | 60.03 | 41.42→2.43 | 28.27→1.37 |

全ONの最長フレームは**291.965→17.843ms**、frame p95は230.156→17.165ms。時間採取OFFでも239.003→18.456ms。修正前は36描画サンプルに対し97回physics更新が入り、重い攻撃計画がphysics catch-upで繰り返されていた。詳細表示やA*だけをOFFにしてもこの負荷は残った。

最重経路の内訳：修正前`Elevation.attack`は97回・合計1633.601ms／最大45.099ms、`player.physics`は合計1655.900ms。修正後の表示は完全探索を毎tick実行せず、`elevation.step`23回・合計5.716ms／最大0.277ms、`player.physics`合計26.831ms。親子の時間は加算しない。

事前経路の全ON計測も記録：`walk.can_reach`の最大0.675→0.710ms、`walk.jump_plan`0.289→0.261ms、`walk.step_plan`は修正後1回0.057ms、`route.goal`0.144→0.145ms。今回のRECOVERY再現ではA*本探索は呼ばれず、これらが最大のボトルネックではなかった。予算外に放置せず事前確認も共通予算へ組み込み、別の閉塞／複数敵の回帰で上限を検査した。

### 階段中央・安全な候補がある配置

| 指標（全ON） | 修正前 | 修正後 |
| --- | ---: | ---: |
| FPS（60上限） | 60.13 | 60.00 |
| Godot物理p95 | 22.511ms | 8.001ms |
| ノードphysics区間p95 | 13.440ms | 6.115ms |
| 主人公戦闘physicsの合計 | 1297.709ms | 125.785ms |
| 計画の回数／合計 | 全探索121回／1264.129ms | 候補単位28回／92.433ms |
| 最長フレーム | 21.977ms | 25.819ms |
| frame p95 | 19.910ms | 21.297ms |

中央配置は修正前から上限付近だった。CPU合計は減ったが、候補1回は不可分で最大8.290msとなり、描画フレームのp95／最大はこの短時間標本では悪化した。**全フレームの滑らかさや厳密な1.2ms上限を達成したとはしない。** 分割待ちによるマーク更新遅延と単発の完全な安全検査は残る。

### 固定座標の関数単体・内蔵Script Profiler

`enemy_work_micro`だけは位置を固定して両者のphysicsを止め、実mainの武器設定で完全な`Elevation.attack`を3回実行する。この単体値と上記の実AI測定は分ける。

- 有効な中央配置：修正前12.270／11.151／13.130ms → 修正後4.163／4.753／4.743ms。3回とも有効な同じ経路を返す。
- 主人公だけ階段端Z=3.1、雑兵はZ=5の安全な床に固定した無効な離陸点：26.476／25.388／23.566ms → 0.259／0.216／0.209ms。3回とも攻撃不可。候補を全探索する前に安全に拒否する。
- 内蔵Profiler（有効な中央配置3回）の`Ground.sample`：951→162回、inclusive29.720→3.902ms。`Ground._ray`：4407→1428回、17.529→5.465ms。`Elevation.corridor`：6回のまま24.442→5.924ms。全身軌道`Arc.clear`も6回のまま0.853→0.917msで、全身検査を省略していない。ray数はこのhelper経由の内訳で、全物理問い合わせ数とは呼ばない。

Profilerの親子inclusive時間は重複する。割合表示の合算は使わず実時間／呼出数を読む。`--debug`時の既存警告は前後とも10件（既存の名前隠蔽、変数、整数除算等）。今回の通常import／起動と回帰ログにエラー／警告はない。

生データは[measurements/m09_work_budget.json](measurements/m09_work_budget.json)。基準revisionへの診断のみの差分は[measurements/m09_work_budget_baseline.patch](measurements/m09_work_budget_baseline.patch)。元ソースに最適化を加える前のコードへ計測／4スイッチだけを挿入したもの。隔離コピーに基準revisionを展開し、このpatchと現在の`enemy_work_diagnostics.gd`／計測テストを用いて比較できる。作業ツリーを巻き戻して測定しない。

例：Godotを隔離プロジェクトへ向けて、`--script res://tests/enemy_work_performance.gd -- --label final_edge --edge`を実行。中央は`--edge`を外す。単体は`--debug --ignore-error-breaks --script res://tests/enemy_work_micro.gd`（無効離陸点は末尾`-- --edge`）。結果はそのコピー内の`.godot/enemy_work_<label>.json`、ProfilerはGodotログへ出る。計測中は他のゲーム実行を重ねない。

## 回帰・読み込み確認

実コード／Resource／Scene／testsと`project.godot`が一致する隔離コピーで、次の14種類を実行してすべてPASS・終了0。

| テスト | 結果 |
| --- | --- |
| enemy_work_diagnostics | 25項目。4切替、最新の壁、入力待ち、早期離陸拒否、予算、保存 |
| pursuit_budget | 216項目。失敗保存の失効を0.45秒後で検査 |
| ramp_contact_attack | 919項目 |
| unlimited_pursuit | 5801項目 |
| terrain_attack | 138項目 |
| terrain_diagnostics | 160項目 |
| elevation_controls | 262項目 |
| enemy_auto_jump | 5839項目 |
| enemy_jump_strike | 547項目 |
| enemy_tactics | 1242項目 |
| m09_enemy_combat | 56項目 |
| mage_cast_commitment | 29項目、回復10.0167秒・弾の間隔11.15秒 |
| m08_defense | PASS、防御・方向帰還等 |
| m07_chain | PASS、照準・カメラ・複数対象連撃・帰還等 |

最後の離陸点早期拒否後はdiagnostics／坂接触／地形攻撃／高低差操作／ジャンプ中の攻撃を再実行。最終Godot editor importと実mainの60フレーム起動は終了0、読み込み・スクリプト・画像参照エラー／警告なし。新規GDScriptのUIDも取り込んだ。F5による実操作・1FPS症状の再確認はユーザー待ち。

## 変更ファイル

- 共通判定：`scripts/combat/elevation_path.gd`、`melee_terrain.gd`、`terrain_ground.gd`、新規`planning_budget.gd`。
- 敵：`scripts/enemies/practice_enemy.gd`、`enemy_walk.gd`、`enemy_pursuit_route.gd`、`practice_selector.gd`、新規`enemy_work_diagnostics.gd`。
- 主人公：`scripts/player/target_dash.gd`。入力割当・ダメージ／モーション値は非変更。
- テスト：新規`tests/enemy_work_diagnostics.gd`／`enemy_work_performance.gd`／`enemy_work_micro.gd`、既存`tests/pursuit_budget.gd`。新規5スクリプトの`.uid`。
- 記録：`AGENTS.md`、`docs/DEVELOPMENT_STATUS.md`、`08_DECISIONS.md`、`12_TEST_PLAN.md`、`14_TARGET_DASH_COMBAT_SPEC.md`、旧性能監査の限定注記、本監査と`docs/measurements/`の計測JSON／基準patch。

## F5の確認手順

1. 必ずF8で停止してからF5。近接敵を選び、RemoteのPerformance Diagnosticsで4項目がONであることを確認する。
2. Capture Timings／Print ReportをON。問題の階段へ移動し、症状の出たまま数秒待つ。`ENEMY WORK`とLast Reportに実座標／状態・関数時間が入っていることを確認する。
3. 同じ配置でAだけOFF→ON、BだけOFF→ON、CだけOFF→ON、DだけOFF→ONを順番に試し、それぞれ1秒以上待ってFPSとPhysics Timeを比較する。Bでは攻撃が止まり、Cでは段差の手前で停止することを確認する。
4. 4項目を全ONに戻し、雑兵／魔導士の坂・0.25／0.5／1m階段の追跡／自動ジャンプ、停止した場所からの再追跡、無制限OFFのhome帰還を確認する。
5. 主人公と雑兵の上下1.8m攻撃、跳躍踏み込み／帰還、Guard・方向帰還・3連撃、金色マークと魔法を確認する。計画更新の短い待機中も壁・崖へ進まないこと。
6. 終了時はCapture Timings／Print ReportをOFF。もし1FPSが続く場合、Last Reportまたは`ENEMY WORK`を報告すれば、その実際の座標と関数時間で再調査できる。

## 未確認・限界

- ユーザーの厳密な1FPS配置、実際のF5操作受け入れ、長時間／多数敵／任意の迷路、実機パッドは未確認。
- 最新安全性が必要な実入力／発進の計画と、候補内のnative問い合わせは同期処理を残す。一定の60FPSを保証しない。
- 保存されるのは表示ヒントであり、マークの更新が短く遅れる場合がある。実操作の安全検査は省略しない。
- M09基本戦闘完了を未完了へ戻さず、本件の実環境性能・操作確認はF5待ちとして扱う。
