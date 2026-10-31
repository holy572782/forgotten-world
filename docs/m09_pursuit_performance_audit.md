# M09完了後：敵の追跡・攻撃計画の性能改善（ADR-053）

日付：2026-11-01。M09基本戦闘完了を維持。今回の実環境での操作感／長時間性能はユーザーF5確認待ち、M10は別指示待ち。commit／push未実行。

## 原因

対象を確認した時点の基準は `f392acda20c6126dee3d70a9f5448d7d60e0e409`。

1. `enemy_pursuit_route.goal()`は再探索待機を確認する前に、長さ最大3mの歩行経路、ジャンプ全身軌道、既存経由点、近距離経路の安全検査を毎physics tick実行していた。
2. 局所A*の最大160地点×8方向の検査を1回の呼び出しで処理していた。失敗した場合も0.75秒ごとに同じ探索を再実行していた。
3. CHASEの攻撃可能判定は同tickで最大2回、戦闘中の追跡からも呼ばれ、失敗結果を保存していなかった。
4. WINDUPでも静止中に同一の剣・候補地点・往復経路を毎tick再計算していた。安全検査自体が誤りなのではなく、同じ計算の反復と1フレームへの集中が負荷の原因。

最初のカウンター計測では、閉塞階段の約3秒に362回の攻撃計画、物理問い合わせは毎秒54,796回。坂道の同一再現配置では平均34.22FPS／フレームp95 179.18msを観測した。ユーザーの「約6FPS」と完全に同じ配置は再現できていないため、この数値をユーザー環境の6FPSの直接測定とは扱わない。

## 修正方式

### 攻撃候補と予告

- CHASEで結果を1回取得して共有。候補判断の成功／失敗を最大0.15秒保存し、敵または主人公の実3D変位0.08m、AttackDataの切替、無制限モードの変更、AI状態変更で無効化する。同physics tickの重複も保存結果を使う。
- **保存結果で攻撃を許可しない。** `_start_windup()`は必ず新たに計画し、照準確定のtickも新たに計画する。踏み込み／帰還、実移動と命中時の検査は従来どおり。
- 静止中のWINDUPプレビューは0.1秒ごと、失敗中は0.05秒ごと。敵／対象の変位0.08mでも更新する。向きは毎tick追従し、確定時刻・固定後の最低回避猶予・0.12秒の失敗猶予とFire1単発を維持する。
- 保存した失敗理由は診断の視線表示に上書きされないよう保持する。

### デバッグ局所経路

- A*のopen／closed・親／コスト・展開中の辺を保存し、複数フレームで続行。従来の最大160地点／半径6m／セル0.75mを維持する。
- 全敵共通で描画1フレーム最大8辺、計測約1.2msまで。physics catch-upでも同描画フレームの上限は共有する。1辺の既存の安全検査は不可分であり、約1.2msは途中で物理問い合わせを打ち切る厳密なCPU上限ではない。
- 直進／ジャンプ／経由点の判断は最大0.15秒保存。敵0.2m／目標0.35mの変位で判断を更新。保存するのは移動意図であり、魔導士などが毎tick更新する微小な移動先そのものは凍結しない。
- 失敗探索の再試行は1.5秒。失敗時の敵0.35m／目標0.5m変位では早期再試行できる。探索中の開始地点／目標変位でも探索を破棄し、状態変更時は探索・経由点・保存結果を破棄する。
- 検索中や失敗時は安全停止し、`NO_SAFE_LOCAL_ROUTE (SEARCHING)`／`NO_SAFE_LOCAL_ROUTE`を表示。地形が変化した場合にも短い直進判定を定期的にやり直す。
- `EnemyWalk`の実歩行／通常ジャンプの支持・全身衝突・離陸検査は変更しない。保存した経路は移動の意図であり、安全性の許可証にしない。

## 維持したもの

通常敵の無制限追跡は既定OFF、M09テストマップはON。正式な索敵／home9m・10m、通常ジャンプ・坂／階段、片手剣上下1.8m・跳躍上り1m／下り1.1m、主人公のGuard／方向帰還／連撃、魔導士の炎・防御貫通と敵画像／SEを維持する。移動や地形の物理検査を簡略化して負荷を下げてはいない。

## 変更ファイル

- `scripts/enemies/enemy_pursuit_route.gd`：移動意図／失敗の保存・A*の分割と共通予算。
- `scripts/enemies/practice_enemy.gd`：攻撃候補の共有／保存と予告プレビューの更新頻度、状態終了時の破棄。
- `tests/pursuit_budget.gd`、`tests/pursuit_performance.gd`、`tests/fixtures/pursuit_query_probe.gd`と各`.uid`：実安全性・予算契約と性能測定。
- `tools/instrument_pursuit_profile.cjs`：隔離コピーだけへ新旧コード／カウンターを展開・復元。
- `AGENTS.md`、`docs/08_DECISIONS.md`、`docs/12_TEST_PLAN.md`、`docs/14_TARGET_DASH_COMBAT_SPEC.md`、`docs/DEVELOPMENT_STATUS.md`と本書。

既存の `enemy_walk.gd`／`elevation_path.gd`／`melee_terrain.gd`／`terrain_ground.gd`／`dash_path.gd`は調査・計測対象だが原本は変更していない。設定Resource・画像／音声・主人公のプログラムも変更なし。

## 計測方法

Godot 4.7.2／Windows／Compatibility、GeForce GTX 1080、1152×720、60FPS上限。同じ隔離コピーと固定テストマップ、1ケース0.8秒のウォームアップ＋壁時計3秒。敵なし平地、階段の無制限OFF／ON、経路なしの閉塞階段、無制限ONの坂道を比較する。

`pursuit_performance.gd`は実process frame間隔とGodotの`TIME_PHYSICS_PROCESS`モニターを記録する。別のProbeは隔離コピーだけの明示的ray／shape／cast／contacts／native test_moveと攻撃計画／探索を数え、通常ゲームには挿入しない。engine内部のmove_and_slideの問い合わせ等は集計対象外。カウンター自身の呼出し負荷も含むため、計測なしの実描画でも別途確認する。

内蔵Script Profilerはローカルデバッガーからケースごとに開始／停止し、`ACCUMULATED`の関数別total／self／tcallsを採取する。GUI画面のスクリーンショット検査とは区別する。[EngineDebuggerの公式API](https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html#class-enginedebugger-method-profiler-enable)、[公式LocalDebuggerの出力処理](https://github.com/godotengine/godot/blob/master/core/debugger/local_debugger.cpp)を参照。

### 再現手順

検証コピー作成：PowerShellで `./tools/validate_mage_fire.ps1 -ImportOnly`。

1. `node tools/instrument_pursuit_profile.cjs --revision f392acda20c6126dee3d70a9f5448d7d60e0e409`で旧版だけを検証コピーへ展開／計測用にする。
2. Godotへ `--path .godot/mage_fire_validation --script res://tests/pursuit_performance.gd --log-file .godot/pursuit_before.log -- --label before`を指定する。
3. `node tools/instrument_pursuit_profile.cjs`で現行版を同コピーへ計測用に展開し、同じ条件で`--label after`として実行する。
4. 内蔵Profilerは同じ起動へ`--debug`、ユーザー引数へ`--native-profile`を追加する。出力に各ケースの`PROFILE CASE BEGIN/END`と`ACCUMULATED`を確認する。Profiler出力の負荷はFPS基準測定と分ける。
5. `node tools/instrument_pursuit_profile.cjs --clean`で計測処理を除いた現行版へ復帰し、同じ実描画計測／回帰を実行する。検証用project.godotは最後に原本から戻す。

APPDATA／LOCALAPPDATAは検証用の`.godot/mage_runtime_appdata`を使用する。同時に複数のゲームを動かさず、各テストは描画ありで1本ずつ実行する。初期のheadless試行は描画待ちのある既存テストを完走できず、採用結果には含めない。

## 検証結果

### 同条件のカウンター付き実描画

各セルは修正前→修正後。Profilerの大量出力を含めない通常起動。3秒の短い測定窓のため、60FPS上限でも端数が僅かに60を超える場合がある。

| 場面 | 平均FPS | フレームp95 ms | 明示的物理問い合わせ／秒 | 攻撃計画回数／測定窓 |
| --- | --- | --- | --- | --- |
| 敵なし平地 | 60.00→60.00 | 16.69→16.68 | 0→0 | 0→0 |
| 階段・無制限OFF | 59.73→59.93 | 21.16→30.05 | 26,920→5,383 | 50→8 |
| 階段・無制限ON | 60.35→59.99 | 18.61→22.08 | 27,554→5,411 | 51→8 |
| 経路なしの閉塞階段 | 58.37→60.00 | 20.80→21.40 | 54,796→4,717 | 362→19 |
| 坂道・無制限ON | 34.22→59.51 | 179.18→39.67 | 56,155→11,242 | 56→10 |

閉塞階段の問い合わせは約91.4%減、攻撃計画は約94.8%減。Godotの物理処理時間モニターのp95は閉塞階段53.64→10.33ms。坂道は54.49→55.79msで、単発のフル安全検査は依然重い。階段のp95もすべてが改善しているわけではない。同期検査1回の処理時間を消した変更ではなく、反復と連続したフレーム落ちを抑えた変更として扱う。

カウンターを除いた現行コードでも同一5場面を再実行した。

| 場面 | 平均FPS | フレームp95 ms | 最大フレーム ms |
| --- | --- | --- | --- |
| 敵なし平地 | 60.00 | 16.76 | 16.93 |
| 階段・無制限OFF | 59.95 | 26.69 | 35.08 |
| 階段・無制限ON | 59.98 | 21.68 | 36.73 |
| 経路なしの閉塞階段 | 60.00 | 19.07 | 21.27 |
| 坂道・無制限ON | 59.77 | 37.46 | 58.45 |

### Godot内蔵Script Profiler

`--debug --ignore-error-breaks`のローカルScript Profilerで5場面を比較。各場面の`ACCUMULATED`のinclusive totalを示す。入れ子の関数時間は重複するため合計しない。Profiler出力の時間を含む平均FPSは上記の基準値と混同しない。

| 場面／関数 | 修正前 回数／合計ms | 修正後 回数／合計ms |
| --- | --- | --- |
| 敵なし／攻撃計画・局所経路 | 0／0 | 0／0 |
| 階段OFF／`_terrain_plan` | 50／831.34 | 8／116.89 |
| 階段ON／`_terrain_plan` | 51／808.38 | 8／119.22 |
| 閉塞階段／`_attack_position_available` | 362／1,225.52 | 181／55.62 |
| 閉塞階段／`_terrain_plan` | 362／1,218.55 | 18／54.47 |
| 閉塞階段／`goal` | 181／685.17 | 181／95.24 |
| 閉塞階段／A* | `_find` 4／139.43 | `_advance_search` 22分割／33.44 |
| 坂道／`_terrain_plan` | 56／1,926.26 | 10／273.66 |
| 坂道／`_plan_attack` | 55／1,897.99 | 9／245.06 |

Profilerなし計測と回数が1回異なるのは測定窓／保存期限の位相による。計測用タイマーの閉塞階段A*最大1呼び出しは、旧版35.69ms（Profiler付き）に対し分割版は約2.10ms（Profilerなし・カウンター付き）。問い合わせ1辺は不可分のため、共通1.2ms予算を境界で僅かに越えることがある。検索全体の完了を待つ間は安全停止する。

### 回帰・読み込み

以下の13種類は実描画・60FPS上限で全PASS／終了0。項目数は観測フレーム数で変動する。

| 検査 | 結果 |
| --- | --- |
| pursuit_budget | 216項目、保存／変位／期限・新しい壁の開始拒否・微小目標更新・共通探索予算／破棄 |
| ramp_contact_attack | 919項目、坂の80配置・実命中／帰還・一時／継続遮断 |
| unlimited_pursuit | 5547項目、両敵の実範囲越え／OFF帰還・坂／階段・ジャンプ・壁迂回／閉塞・崖 |
| elevation_controls | 231項目、主人公の高低差Guard／方向帰還・コンボ／封鎖帰路 |
| terrain_attack | 138項目、既存30場面 |
| enemy_auto_jump | 5837項目 |
| m09_enemy_combat | 56項目 |
| enemy_tactics | 1242項目、照準／回避・周辺歩行 |
| mage_cast_commitment | 29項目、Recovery 10.0167秒／発射間隔11.15秒 |
| m08_defense | 防御・方向帰還・入力保持／解除・消費／命中PASS |
| m07_chain | 照準／対象切替・3連撃・帰還・カメラPASS |
| terrain_diagnostics | 160項目 |
| enemy_jump_strike | 547項目 |

最終Godot editor import、計測なしの実main60フレーム起動とも終了0・エラー／警告なし。通常回帰ログにもエラー／警告なし。`--debug`のProfiler起動だけでは変更前／後とも同じ既存GDScript警告12件が出る（EnemyWalkのcollision、既存flash／basis／name／saved、旧テストenum、TargetDashのbest／整数除算）。今回の変更箇所による新規警告は残していない。既存警告を直すための主人公や被弾演出の改修は実施しない。

計測終了後はカウンターを除いた現行ソースと原本project.godotへ復元。対象8スクリプト・新規3つのGDScript（検査／計測fixture）とproject.godotのSHA256一致を確認。`git diff --check`合格。採用ログは`.godot/perf_regression_*.log`／`perf_final_import.log`／`perf_final_main.log`、計測は`pursuit_before.log`／`pursuit_final_after.log`／`pursuit_clean_after.log`／`pursuit_native_before.log`／`pursuit_native_after.log`。JSONは検証コピーの`.godot/pursuit_perf_*.json`。

## F5確認（ユーザー未実行）

1. F8→F5。雑兵・魔導士を切り替え、同じ階段上へ主人公を移動。UNLIMITED／DIST 2.4m付近・BLADE_BLOCKED／NO_SAFE_LOCAL_ROUTEとなる場面も維持し、FPSと操作応答を確認する。
2. 坂の下端／途中／上端へ誘導し、近距離のその場攻撃、踏み込みと帰還、両敵の追跡／自動ジャンプを確認する。
3. 壁で閉塞したまま10秒以上待ち、探索中／停止が続いても大きくFPSが低下しないこと、壁・床／崖を通過しないこと。主人公が安全な側へ移動したとき追跡を再開すること。
4. Remoteの`Debug Unlimited Pursuit`をOFFにし、正式home制限と帰還が復帰すること。ONでも魔導士は射程内で停止し魔法を使うこと。
5. 主人公の攻撃・3連撃・Guard／ジャンプ・方向帰還、雑兵の固定照準／赤予告・攻撃／帰還、魔法の防御貫通、画像／SE／ターゲットを確認する。
6. GodotのDebugger→Profilerを開始し、同じ配置でFrame Time／Physics Timeと`goal`／`_advance_search`／`_attack_position_available`／`_plan_attack`を比較する。

## 残る限界

- ユーザーの6FPSとなった厳密な配置、GUI Profilerの操作受け入れ、長時間／多数敵／任意の大迷路は未確認。局所経路の探索範囲は拡大していない。
- フル安全検査1回は同期処理のまま。平均60FPS付近でも個別の攻撃計画や描画準備で16.7ms超のフレームが残り得る。測定p95／最大時間を併記し、完全に一定の60FPSとは記録しない。
- 本変更の許可は入力／物理安全判定／戦闘バランスの変更には使用しない。
