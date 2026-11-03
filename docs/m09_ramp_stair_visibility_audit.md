# M09完了後：坂の透明描画・階段上り・魔導士の下り（ADR-058）

作業日2026-11-03。開始時HEAD `4d7c8b3`。未コミットは敵AttackData2件のaim_lock_ratioを雑兵0.4／魔導士0.5へ戻したユーザー変更で、そのまま保持する。M09基本戦闘完了を維持。本件の操作感／見た目と長時間性能はユーザーF5確認待ち、M10別指示待ち。commit／push未実行。

## 原因と再現

### A：坂と敵の半透明表示

OcclusionFaderは地形のMeshInstance3Dだけに複製Materialを割り当て、敵のmodulate.aは1.0だった。主人公／敵共通のplayer_depth Shaderは深度テクスチャを読む後段描画だが、補正したカプセル深度を後続の半透明地形に対して書き込んでいなかった。坂が後から敵の画素にブレンドされ、敵自体が薄くなったように見えていた。

共通Shaderへdepth_draw_alwaysを指定し、既存のカプセル代理深度と画素ごとの不透明地形遮蔽を維持する。坂の透明化対象／範囲／opacity、キャラクターの画像・サイズ・alpha・nearest、影用オブジェクトと金色マークShaderは変更しない。壁の前後関係を無視するdepth_test_disabledは追加しない。

### B：階段に密着した雑兵

階段中央の下からの連続追跡は旧版でも成功。実マップ中段の縁に近い位置（arenaローカル(5,0,-1.55)）からの通常移動で、身体が段差側面に接し、直ちに水平移動する既存の放物線が側面へ当たってSTEP_OR_JUMP_UNSAFEを繰り返すことを再現した。通常射程ならその場攻撃できるケースもあり、「上らず攻撃する正常な動作」と移動不能を区別する。

既存の軌道を先に検査し、失敗した場合だけ同じJumpArcに先行上昇の曲線2を使用する。水平の進行時間はduration×(p−0.25×tanh(p/0.25))で、初動で高さを稼ぎ、その後は設定水平速度以下に収まる。最高点／離陸速度／重力／クールダウンは共通。短くなった着地点も改めて支持／床の連続性／home／全身の軌道で検査し、計画と実移動に同じ曲線を渡す。壁や天井を通過する軌道は拒否する。従来のcurve0／±1と主人公の通常ジャンプ・戦闘飛行は変更しない。

### C：魔導士の坂道下り

坂中央から正面への下りは旧版でも成功し、6m内の安全な射線で停止して詠唱するのも正常だった。一方、坂の側縁付近から斜め下へ向かう追跡では停止を再現。5点の足場検査が既に一部張り出して接地しているカプセルの「内側へ戻る」小移動も拒否していた。さらに魔導士が経路探索へ渡す目標は1tick分の数cm先で、障害時の局所A*が既に到達した目標と判定し、有効な迂回へ進めなかった。

通常歩行は既存の支持検査を優先する。失敗時の復帰は0.16m以下、前後の実中心床が有効で同一支持平面からの誤差0.04m以内・法線dot0.95以上、支持のない全方向から離れる内向き移動だけに限定。坂の本来の高さ変化は平面に沿って確認し、空中／外向き／穴への移動や新しい大きな段差を許可しない。全身衝突とnative床・重力は既存処理を維持する。

魔導士のCHASEでは既存combat_goalへ本当の主人公位置を渡し、直接進めるか、左右の安全候補と予算付き分割A*を使う。局所探索の先頭の直進候補にも実移動の停止結果を反映し、通常モードでも実際に停止したCHASEではhome内の既存経路探索を継続する。身体の移動は引き続きEnemyWalkが所有し、実射程6m・実発射線が成立すれば停止／攻撃する。WINDUP以降に再探索／再照準しない。通常モードのhome制限、無制限モードの安全性、RECOVERY／魔法の仕様を維持する。

## 維持する設定と性能契約

- walking_step_height=0.3m、maximum_step_up=1.05m、jump_height=1.1m、jump_takeoff_speed=6.63m/s、jump_horizontal_speed=3m/s、jump_cooldown_seconds=0.8秒、既存maximum_step_down／snap。
- 雑兵ratio0.4／魔導士ratio0.5、予告・確定後の回避猶予・固定照準／非追尾、剣の開始と命中の分離、上下1.8m・リーチ2.5m、魔法射程6m／MAGIC。
- PlanningBudget、分割A*、短期キャッシュ、主人公の選択／金色マーク、重複照会削減。通常の安全な経路では元の軌道だけを使い、追加検査は失敗時に限定する。

## 検証結果

採用した機能検査は**18種類・19実行条件、すべて実描画・通常時間でPASS／終了0**。新規の再現地点24条件は116項目、表示16配置と遮蔽／復元は53項目。中央の坂／階段上下も24条件を別実行し、移動単独と正式射程の攻撃AIを分離した。密着段差の移動単独は旧版のSTEP_OR_JUMP_UNSAFE・停止から、1回の跳躍と頂点約1.1mを経て最上段へ到達する状態へ改善した。坂側縁は安全な内向き復帰／迂回から攻撃を再開し、移動単独での危険な外向き進行は引き続き拒否した。

描画は旧版で敵alpha=1.0のまま最大2077画素に坂が混ざったのに対し、修正版の両敵×4位置×2方向では全配置で上書き0。opaque壁で完全に隠れること、実際に手前の半透明壁は合成されることも検査した。金色マーク176項目、剣の深度37項目、既存カメラfade／影の復元も合格。

|機能検査|実行条件|結果|
|---|---|---|
|enemy_ramp_stair_regression|focus_native|PASS 116|
|enemy_faded_terrain|native|PASS 53|
|target_marker_depth|native|PASS 176|
|weapon_depth|native|PASS 37|
|m04_occlusion|native|PASS|
|enemy_sword_combat|native|PASS 447|
|elevation_strike|native|PASS 349|
|elevation_controls|native|PASS 263|
|ramp_contact_attack|native|PASS 920|
|pursuit_budget|native|PASS 216|
|mage_magic|native|PASS 120|
|mage_cast_commitment|native|PASS 29|
|m07_chain|native|PASS|
|m08_defense|native|PASS|
|enemy_auto_jump|native|PASS 5839|
|enemy_descent|native|PASS 312|
|enemy_aim_lock|native|PASS 818|
|enemy_edge_attack|native|PASS 241|
|enemy_ramp_stair_regression|central_native|PASS 116|

前後の画像／物理再現用probe、全採用ログのSHA256、実行結果、最終ソースのSHA256は [測定JSON](measurements/m09_ramp_stair_visibility.json) に保存。初期の物理再現はheadless／固定physics、採用結果は通常時間の実描画。早送りでは実時間のキャッシュ／再試行期間を十分に経過せず未完了となる場合があり、初期のheadless終了時のObjectDB／Resource残存ログも採用版の実描画で再確認した。最終の採用機能ログにその残存／スクリプト・参照エラーはない。M04が意図的に経路なしを作るCamera safety警告と、sandboxの証明書ストア読込ログは別に記録する。

### 性能比較

GTX1080（driver572.16）／Godot4.7.2／Compatibility、1152×720・上限60FPS／物理60Hz。実mainのPlayer更新・選択／金色マークを動かし、攻撃AIなし／雑兵／魔導士／両敵×平地／坂／階段×通常／無制限の24配置を、それぞれ約3秒ずつ単独プロセスで順番に測定した。この24配置は実mainの既存静止敵4体を残した同一条件で、攻撃AIなしを完全な敵なしと混同しない。別途、静止敵も除いた完全な敵なし6配置を前後測定した。開始時のユーザーratio0.4／0.5と正式射程を前後で共用した。

|地形（各8配置）|平均FPSの範囲 前→後|Physics p95 msの範囲 前→後|
|---|---|---|
|flat|59.80〜60.01 → 59.94〜60.06|3.135〜4.772 → 3.311〜5.571|
|ramp|59.99〜60.00 → 59.99〜60.00|2.654〜5.758 → 2.922〜5.571|
|stairs|59.99〜60.00 → 59.99〜60.00|2.955〜4.574 → 2.769〜4.273|

全24配置では平均FPS **59.805〜60.009 → 59.939〜60.060**、Physics p95 **2.654〜5.758 → 2.769〜5.571 ms**、単発最大フレーム **43.158 → 34.079ms**。継続的なFPS低下は今回の短い測定で再発していないが、一律の処理時間短縮や全フレーム60FPSを示すものではない。

追加の密着段差／坂縁の8配置（両敵・通常／無制限、実Player更新あり、修正後のみ）は平均 **59.946〜59.998 FPS**、Physics p95 **2.970〜6.598 ms**。3秒時点の攻撃回数だけで最終攻撃成否を判定せず、完了まで待つ上記機能検査と区別する。長時間・多数敵・任意地形は未測定、今回のF5操作感／見た目はユーザー確認待ち。

静止敵／攻撃AIとも0の6配置（平地／坂／階段×追跡設定ON/OFF）は、平均FPS **60.002〜60.006 → 60.002〜60.003**、Physics p95 **1.753〜2.751 → 2.508〜2.992ms**。JSONのstatic_targets=0／kinds=[]で確認する。

最終Godot importと実main起動60フレームは終了0。scripts／scenes／resources／tests／assets/shaders／assets/sprites／画像フォルダ／project.godotの**570ファイル**は隔離検証コピーと一致。画像フォルダ170ファイルは内容一致。SpriteFrames8件の旧検証コピーはUID／書式だけ異なっていたため、全アニメーションの順序・速度／ループ／時間とAtlas領域・画像参照の同値を確認し、現行ファイルへ同期して描画／読み込みを最終確認した。入力・主人公の戦闘／移動・武器値・攻撃判定・PlanningBudget／Ground／DESCENDの数値を変えるファイルは非変更。開始時のユーザーResource2件もSHA256一致。

再実行例：

```powershell
$godotExe='D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script res://tests/enemy_ramp_stair_regression.gd -- --focus
& $godotExe --path . --script res://tests/enemy_ramp_stair_regression.gd -- --central
& $godotExe --path . --script res://tests/enemy_faded_terrain.gd
& $godotExe --path . --script res://tests/enemy_aim_performance.gd -- --edge --regression --label ramp_local
& $godotExe --path . --script res://tests/enemy_aim_performance.gd -- --edge --empty --label ramp_empty_local
& $godotExe --path . --script res://tests/enemy_ramp_stair_regression.gd -- --performance --label ramp_focus_local
```

## 変更ファイル

- `assets/shaders/player_depth.gdshader`：共通カプセル深度の後段書き込み。
- `scripts/enemies/enemy_walk.gd`：内向き支持復帰／密着段差の代替軌道。
- `scripts/combat/jump_arc.gd`：曲線2の位置と全身掃引の誤差上限。
- `scripts/enemies/practice_enemy.gd`：魔導士CHASEの実目標による既存位置取り。
- `scripts/enemies/enemy_pursuit_route.gd`：実停止後の直進再選択の抑制。
- `tests/enemy_ramp_stair_regression.gd`／UID、`enemy_faded_terrain.gd`／UID、新規再現・安全性検査。
- `tests/enemy_auto_jump.gd`：選択された軌道と実表示の同期検査。
- `tests/enemy_aim_performance.gd`：敵なし／単体／両敵×地形×追跡モードの前後計測。
- AGENTS、DEVELOPMENT_STATUS、08_DECISIONS、10_SYSTEM_SPEC_GODOT、12_TEST_PLANと本監査・測定JSON。

## F5確認

1. F8→F5。近接敵／遠距離敵を切り替え、青い坂の手前・途中・奥でQ/Eを回す。敵画像の色が坂の透明化で薄くならず、実際に手前の壁がある部分は従来どおり遮蔽されることを確認する。金色マーク・影・白フラッシュ・剣／斬撃も確認。
2. 橙色の階段を下から上へ主人公を移動。雑兵は0.25mを歩行、必要なら0.5／1mを自動ジャンプして追跡する。中段側面に近い位置で攻撃後に主人公が離れても上りを再開する。届く場合にその場攻撃するのは正常。
3. 魔導士を坂の上・途中・側縁へ誘導して主人公が下へ離れる。内向きの安全な位置へ戻りながら下り、射程内で発射可能なら停止して詠唱する。無制限ON／OFFの両方で試す。
4. 坂の側面外へ直接降りる危険な移動、床なし・低い天井・壁越しは拒否することを確認。両敵の下り／home帰還、主人公の攻撃・防御・3連撃・方向帰還、固定後の横回避と魔法貫通を確認する。
5. 敵なし・単体・両敵、坂／階段、診断ON／OFFでFPSとPhysics Timeを確認。長時間・多数敵・任意地形は短い自動測定から断定しない。
