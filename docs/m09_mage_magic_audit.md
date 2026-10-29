# M09完了後：魔導士の魔法陣・炎弾・防御貫通

2026-10-29／ADR-042。M09基本戦闘完了を維持。今回の操作・見た目・聴感はユーザーF5確認待ち、M10へ移行しない。commit／push未実行。

## 開始時・受入条件

開始HEAD `b9dec5a`、git statusクリーン。AGENTS／DEVELOPMENT_STATUS、必読仕様08／10／11／12／14、最新ADR-040／041監査、指定Enemy／Projectile／AttackData／Settings／Player TargetDash／HealthとResource／テストを照合した。

対象は魔導士の表示・属性・射程内停止。雑兵AI／剣／照準／周辺歩行・主人公のコンボ／ジャンプ／帰還／通常Guard・マーク・HP／撃破表示・既存画像／音は維持する。新PNG・音声・外部依存は追加しない。既存Effekseerは導入状態を維持するが、今回の描画はGodot標準Mesh／Shaderのみを使用する。

## 赤い魔法陣

EnemyAttackData.magic_visualが指定された敵にだけCastingCircleを生成。既存attack_warning_startedから開始し、WINDUPのelapsed／windup_secondsを参照して少し強める。PlaneMesh上のShaderが赤い二重円と独自の幾何学記号（短い放射線・横線・六角形・中心十字／円）を描く。外部作品の文字・画像は使用しない。

足元の実地面を既存ground_belowで探し、地面＋0.035mへ水平配置する。地面が見つからなければ表示しない。低解像度96分割・通常の深度テスト・depth_draw_never、影生成OFF、衝突なし。通常の攻撃範囲表示とは別ノードであり、範囲表示OFFでも魔法陣を表示できる。中心側の色／Emissionだけ少し明るくし、Light3Dや画面全体の光は追加しない。

毎秒0.25radで回転し、既存attack_startedから0.12秒だけフェードアウトする。攻撃中断／非予告状態では解除、HP0通知では即非表示、敵が解放されれば子ノードも解放される。赤点滅・攻撃態勢画像・Fire1の単発開始音は既存のまま。

## 炎弾

従来の青いSphere表示に代わり、magic_visualがあればFireballVisualを生成する。QuadMeshのShaderを24分割のUVへ量子化し、黄色中心・橙・赤の段階色と輪郭の揺らぎを描く。現在のCamera3Dのbasisへ追従するbillboardで、3D壁／床の通常深度を維持し、影を落とさない。

見た目の枠は直径1.8m（不規則な炎輪郭には透明余白を含む）。後方1.1mを目安に小さな火花5個を配置し、射出方向の後ろへ流す。表示は弾の子ノードで、弾の消費／解放と同時に消える。弾自身の物理時計ageを参照し、別の攻撃／ダメージ時計は作らない。magic_visual未指定の弾は従来の簡易表示を維持する。

魔導士だけ速度5m/s・最大飛距離13.2mを保存。発射位置は既存の足元＋0.9mで、発射時の実3D目標へ向く。その後は追尾しない。travelledを発射点から積算し、最終stepを残距離で制限して13.2mで解放する。13.2÷5=約2.64秒、既存の寿命6秒は安全上限として先に到達した条件で終了する。

衝突は元のSphere半径0.2m、terrain＋playerのmask3、初期重なりとmove_and_collideの連続衝突、壁優先・一度だけの消費を維持。視覚サイズを衝突半径へ流用しない。発射開始距離6m、ダメージ10、予告1秒、攻撃時間0.12秒、回復1.5秒、最短発射間隔2.5秒、同時上限1発も維持する。既存の上限判定により前弾が存命なら新弾を増やさない。

## 物理・魔法とGuard

- damage_types.gdのPHYSICAL／MAGICをAttackDataに保持し、近接と飛び道具の配送方式とは分ける。魔導士ResourceだけMAGIC、雑兵・旧データの既定はPHYSICAL。
- Health.damage(amount,source,kind)の第3引数は任意で既定PHYSICAL。従来の呼び出し、2引数damage_filter、damage_applied／hp_changed／depletedの通知と元の攻撃者Nodeを維持する。
- incoming_damage_kindは受信側damage_filterの呼出中だけ設定し、直後に以前の値へ復元する。攻撃者の現在の状態や武器から属性を推測しない。飛行中の弾は発射時のAttack snapshotを使う。
- TargetDashのGuardフィルターはMAGICかつ通常Defenseの場合、そのまま通常ダメージを返す。guard_succeededを発行しないため既存Sword2も鳴らず、Guard姿勢自体は解除しない。HP減少／被弾表示／死亡は従来の経路。
- 将来用にDefense.guard_magic_enabled（既定false）を追加。明示ONの魔法対応盾は既存の正面方向判定・軽減・成功通知を再利用できる。新しい盾や装備UIは作成していない。
- PHYSICALの矢も通常どおり防御可能。MAGIC近接も通常Guardを貫通する。属性と見た目／配送を独立して設定できる。

## 魔導士の移動

PROJECTILEのCHASE／RECOVERYだけ専用の小さな距離分岐を利用し、移動自体は既存_walk_towards／Path.clear／元の衝突形状を再利用する。6mを越えれば追跡再開、停止目安5.8m（余裕0.2m）で止める。攻撃が可能なら6m内で従来どおり予告へ移行し、予告／攻撃中は停止する。6mのすぐ外側で永遠に攻撃も移動もしない状態は作らない。

射程内の回復／クールダウンでは待機、主人公が外へ離れた場合は回復中も接近だけ再開する。回復時間／最短発射間隔は短縮しない。左右歩行・後退・ランダム移動は追加しない。索敵8m／leash10m／視線喪失・壁／崖／平坦足場／Playerによる移動予約は元のまま。雑兵のCHASE／RECOVERY分岐は従来どおり。

## Inspector

| Resource | 項目 | 初期値／意味 |
|---|---|---|
| resources/enemies/ranged_attack.tres | Damage Kind | MAGIC（PHYSICALは通常物理） |
| 同上 | Projectile Speed / Range / Lifetime | 5m/s／13.2m／6秒 |
| 同上 | Projectile Radius | 0.2m、表示から独立 |
| 同上 | Magic Visual | mage_magic_visual.tres。nullなら従来の簡易表示 |
| resources/enemies/mage_magic_visual.tres | Circle Enabled / Diameter | ON／2.8m |
| 同上 | Ground Offset / Rotation Speed | 0.035m／0.25rad毎秒 |
| 同上 | Circle Color / Release Fade Seconds | 赤／0.12秒 |
| 同上 | Fireball Diameter / Pixel Grid | 1.8m／24分割 |
| 同上 | Trail Count / Length | 5個／1.1m |
| resources/enemies/ranged_practice.tres | Ranged Stop Margin | 0.2m（停止距離の余裕） |
| resources/defense_settings.tres | Guard Magic Enabled | OFF。将来の専用盾だけ明示ON |

FileSystemで該当Resourceを選択しInspectorで変更して保存する。攻撃データは次のシーケンス開始時にsnapshotされる。将来の別魔法はAttack／Magic Visual Resourceを複製して敵別割当できる。

## 変更ファイル

- 攻撃／属性：scripts/combat/damage_types.gd（新規）、health_component.gd、defense_settings.gd、scripts/player/target_dash.gd（Guardの属性分岐だけ）。
- 敵：scripts/enemies/enemy_attack_data.gd、enemy_settings.gd、practice_enemy.gd、practice_projectile.gd、resources/enemies/ranged_attack.tres。
- 表示（新規）：scripts/effects/magic_visual_settings.gd、mage_cast_visual.gd、fireball_visual.gd、assets/shaders/mage_circle.gdshader、fireball.gdshader、resources/enemies/mage_magic_visual.tres。新スクリプト／ShaderのGodot生成UIDも保持。
- 検査：新規tests/mage_magic.gdとUID、tests/m09_enemy_combat.gd、m09_timing.gd、enemy_jump_strike.gd、enemy_attack_warning.gd。
- 記録：AGENTS.md、DEVELOPMENT_STATUS、08_DECISIONS、10_SYSTEM_SPEC_GODOT、11_CODEX_IMPLEMENTATION_PLAN、12_TEST_PLAN、14_TARGET_DASH_COMBAT_SPEC、m09_enemy_combat_auditと本書。

Playerの移動／攻撃／アニメーション・共有武器／雑兵Resource／DashPath／Sweep・既存シーン／画像／音声／Effekseer／project.godotは変更しない。

## 検査結果

Godot 4.7.2.stable.official.ed1daf0bf／Compatibility／GTX 1080、実描画fps上限60／30、物理60Hzで実行。15種類17条件すべてPASS・終了0。assertion件数はフレーム中の観測を含むため実行時に変動する。

| 検査 | 実行結果 |
|---|---|
| combat | M09 PASS: 56 assertions; fps cap=60 |
| timing | M09 TIMING PASS |
| jump | ENEMY JUMP PASS: 539 assertions; fps cap=60 |
| tactics | ENEMY TACTICS PASS: 1238 assertions; fps cap=60 |
| sword | ENEMY SWORD PASS: 441 assertions; fps cap=60 |
| defense | PASS M08 return: directional intent, hold/neutral/taps/noise, guard, stock/hits, safe Return, camera, reset, reserved K/east |
| chain | PASS M07 chain: facing aim, manual release, pivot lock, orbit, ABC, replacement, invalid next, return |
| near | IN PLACE ATTACK PASS: 3273 assertions; fps cap=60 |
| warning | ATTACK WARNING PASS: 110 assertions; fps cap=60 |
| defeat | BOUNCE CRY PASS: 2908 assertions; fps cap=60 |
| startup | M09 STARTUP PASS: default enemy attacks, left attack/right guard, GUI switches and resets |
| new60 | MAGE MAGIC PASS: 113 assertions; fps cap=60 |
| new30 | MAGE MAGIC PASS: 81 assertions; fps cap=30 |
| reload | MAGE MAGIC RELOAD PASS |
| feedback | COMBAT FEEDBACK PASS: 629 assertions; fps cap=60 |
| actions | ACTION AUDIO PASS: 122 assertions; fps cap=60 |
| effekseer | Effekseer integration: PASS (13 checks, changed samples 3387) |

新規魔法検査は60fps上限113／30fps上限81項目。魔法陣は4方向のA/B実画像で約712〜3914画素の差分を確認し、水平配置／回転・Fire1単発・発射fade／中断／HP0消去を検証。炎は実画像の黄中心／橙赤色と時間によるピクセル変化、Camera方向へのbillboard追従、独立した見た目／衝突を確認した。魔法陣と炎の自動キャプチャも目視した。

実弾は5m/sの非追尾、発射点から13.2m（許容誤差1mm以内）／約2.64秒で解放。MAGIC弾とPHYSICAL弾は同じ物理経路でGuard時HP90／95、成功通知0／1、Guard姿勢を維持。MAGIC近接・旧2引数呼出・属性復元・将来の魔法対応盾ON・実雑兵の半減も確認した。射程外からの安全歩行、射程内と回復中の停止、追跡再開・境界余裕・6mすぐ外での再開・壁／崖を検証した。

関連回帰は連続衝突／壁／初期重なり／単発HP・旧近接／弾の時間、雑兵のジャンプ中攻撃／照準と周辺歩行、主人公のGuard／方向帰還／近距離省略／連撃、赤／白flash・火花・撃破飛行／Cry1・既存SE、実main起動／操作／モード切替、既存Effekseer再生／解放が合格。指定変更の速度と魔導士MAGICの期待値だけ更新し、旧形状・ダメージ／安全判定を緩和していない。

初回30fpsの中断検査は、中断後にAIが次の予告へ入り直すケースを一緒に観測していた。検査だけAIを停止して中断状態を分離し、最終60／30の両方で合格した。初期のShader型推論エラーは明示Vector3で修正済み。初回の環境側Shader cache保存診断とheadless check-onlyでのEffekseer終了時disconnect診断は区別し、最終の実描画回帰／editor importにはエラー・警告なし。検査プロセスだけAPPDATA／LOCALAPPDATAを `.godot/mage_runtime_appdata` に分離し、ユーザーの個人設定／プラグイン配布物は変更していない。

最終headless editor importは終了0。テストとimportのScript／Parse／Shader／画像・Resource参照エラーなし、git diff --check合格。元の画像／音声、雑兵Resource／共有武器、DashPath／Sweep、既存シーン／project.godot／addonsへの差分なし。

一覧は `.godot/mage_results_final.json`、各ログは `.godot/mage_*`、画像／計測は `.godot/mage_circle.png`／`mage_fireball.png`／`mage_flying.png`／`mage_visual_metrics.json`（Git対象外、再生成可能）。再現例（プロジェクト直下PowerShell、Godotは1プロセスずつ）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script res://tests/mage_magic.gd
& $godotExe --path . --script res://tests/mage_magic.gd -- --fps30
& $godotExe --path . --script res://tests/mage_magic.gd -- --reload
& $godotExe --path . --script res://tests/m09_startup.gd
& $godotExe --headless --path . --editor --quit
```

ユーザーのF5操作／最終見た目の受入は未実行。

## F5での確認（未実行）

1. F8で旧実行を停止しF5。上部の「遠距離敵」を選択。魔導士の予告で足元に赤い二重魔法陣が出て、ゆっくり回り、Fire1が開始時1回だけ鳴ること。
2. 発射で魔法陣が自然に消え、黄色中心の炎弾と短い後方の火花が見えること。Q/Eの4方向でも地面から浮きすぎず、壁越しに透けないこと。
3. 右クリック／Iで防御して弾を受ける。姿勢を維持したまま通常10ダメージ、防御成功Sword2なし。WASDで横に避けると追尾しないこと。
4. 弾が遮られず飛ぶ場所では発射点から約13.2m（約2.64秒）で消えること。表示が大きくても当たり判定まで広がっていないこと。
5. 魔導士が6m外では歩き、6m内の予告／攻撃／回復では基本停止すること。離れると再接近し、境界で小刻みに振動せず、壁や崖を越えないこと。
6. 予告中に魔導士を撃破／モード切替し、魔法陣や弾が残らないこと。元の吹き飛び／Cry1が維持されること。
7. 「近接敵」へ戻し、物理Guardの半減、雑兵の予告／踏み込み／帰還／周辺歩行とジャンプ中攻撃、主人公の左クリック／J・連撃／方向帰還・Space／Q/Eが従来どおりであること。

今回の見た目・回避しやすさ・聴感、任意の複雑地形、実機パッド／エクスポート、長時間性能は未確認。M09基本戦闘完了と追加改善のF5確認待ちは別に管理する。
