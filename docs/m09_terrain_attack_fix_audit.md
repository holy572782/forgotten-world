# M09追加修正：坂・階段の攻撃開始と踏み込み候補

## 原因と修正
- 開始時git statusは空。既存ADR-048・関連仕様と実装を照合した。M09基本戦闘完了／追加改善F5待ち／M10別指示待ちを維持する。
- 高低差用ElevationPathにも平坦床専用Path.ground_below（normal.y>=0.99）を使っていた。支持面の0.04mは水平面との差だったため、歩ける坂も拒否していた。高低差側だけ歩行最大傾斜角を参照し、足元5点が実際の支持面の平面と一致するかを検査する。0.04mの精度を無条件に拡大せず、段差の縁を跨ぐ不安定な着地は拒否する。
- 同じ高さの坂横方向でもBlade.clearが平地のstrike_clearへ入っていた。従来分岐は両端が平坦な場合に限定し、坂は剣の線・遮蔽物／床支持の検査を使用する。水平床用DashPath自体は変更しない。
- 開始地点からの剣の経路が塞がれているだけで、候補探索前に失敗していた。現在位置で届けばその場攻撃、それ以外は候補を実地面へ投影し、実カプセルの下向き掃引で立てる位置を取得する。その位置からの剣のリーチ／実高さ／遮蔽と往復の全身経路を確認する。
- 同じ高さの平地で従来Dashが壁に遮られる場合は、新しい小跳躍への迂回を認めない。坂の踏み込みは既存の安全な飛行実行・衝突・帰還を利用する。壁・床下・穴・他キャラ・天井の検査は残す。
- 雑兵の認識は視認と剣の到達を分離。上半身の視線も使って階段上を認識できるが、命中と踏み込みは別途遮蔽物を検査する。剣の候補半径は水平距離で判定し、魔導士の距離／視線は変更しない。

数値は上下1.8m、跳躍上り1.0m・下り1.1mを維持。EnemyWalk・魔法・画像・音・InputMap・ダメージ計算は変更しない。

## 開発用表示
雑兵ノードのInspector → Show Attack Diagnostics（初期OFF）。START（開始不可）／ABORT（予告・接近後の中断）／HIT（実命中結果）を別表示。OUT_OF_RANGE、TARGET_NOT_VISIBLE、ACTOR_AIRBORNE、NO_SAFE_LANDING、DASH_PATH_BLOCKED、RETURN_PATH_BLOCKED、HEIGHT_OUT_OF_RANGE、BLADE_BLOCKED等を確認できる。既存Show Debug Stateと独立して表示できる。OFFでは診断用の再探索やログ出力を行わず、通常判定の結果を変えない。

## 変更ファイル
scripts/combat/elevation_path.gd、melee_terrain.gd、scripts/enemies/practice_enemy.gd、tests/terrain_attack.gd・terrain_diagnostics.gd（新規・各UID）、tests/elevation_controls.gd、およびAGENTS／進捗・ADR／仕様／テスト計画・本書。

旧elevation_controlsの占有試験は、新たに利用可能になった手前の下段候補も覆う配置にした。上り上限の試験は、下段で斬れる合法な代替候補を拒否させるのではなく、指定した上段への経路が上限で拒否されることを直接確認する。

## 検証
Godot 4.7.2／Windows・Compatibilityの同一ソース隔離コピーで、次の11種類がすべてPASS・終了0。採用ログにSCRIPT ERROR／ERROR／WARNINGなし。

| 検査 | 結果 |
| --- | --- |
| terrain_attack | 30場面・138項目 |
| terrain_diagnostics | 152項目、ON／OFFとも1攻撃・1回のHP減少 |
| elevation_controls | 263項目 |
| elevation_dash | 304項目、空中214サンプル |
| elevation_strike | 345項目 |
| enemy_sword_combat | 445項目 |
| enemy_tactics | 1242項目 |
| enemy_jump_strike | 543項目 |
| mage_cast_commitment | 29項目 |
| m08_defense | 方向帰還・防御・移動入力PASS |
| m07_chain | 対象切替・連撃・カメラ・帰還PASS |

terrain_attackは実TestArenaの3段階段・坂の上り／下り／同高度の横方向、雑兵と主人公の近距離／遠距離攻撃と帰還、0.25／0.5／1mの単独段差を確認した。帰還位置の誤差は最大約0.00165m。診断ONで実命中OKも確認した。

Godotの最終エディターimportは終了0・エラー／警告なし。ログは`.godot/terrain_fix_*.log`、回帰10種類の結果は`.godot/terrain_fix_results.json`。新規の診断検査と最新コードの地形再検査（再度138項目PASS）は別ログに保持した。隔離コピーは`.godot/mage_fire_validation`で、変更コード・テストとUIDの8ファイルはSHA256一致。DashPath／EnemyWalk／MeleeSweep／TargetDash・既存Resource／assets／scenes／project.godotはHEAD差分なし。git diff --checkも合格。人によるF5の視覚・操作確認とは区別する。

再現はPowerShellで`./tools/validate_mage_fire.ps1 -ImportOnly`を実行して同一ソースの隔離コピーを用意し、Godot 4.7.2の`--path .godot/mage_fire_validation --script res://tests/terrain_attack.gd`および`res://tests/terrain_diagnostics.gd`を1本ずつ実行する。音声・画像を含めるため描画ありで実行し、上表の既存スクリプトも同じ形式で指定する。

## F5確認（ユーザー未実行）
1. 雑兵を実マップの各階段へ誘導し、階下／階上の主人公へ赤い予告→その場攻撃または踏み込み→帰還が行われること。
2. 坂途中で近距離・遠距離、登り／下り／同高度の横方向を試し、攻撃と帰還を確認する。
3. 主人公の左クリック／J・防御／方向帰還・3連撃・L切替とQ/E、魔導士の魔法、両敵の通常移動を確認する。
4. 壁・天井／崖／着地占有では不正に攻撃しないこと。診断ONでSTART／ABORT／HITを確認し、確認後OFFへ戻す。

任意の複雑地形・多数の敵／長時間性能・見た目の自然さは未確認。commit／pushは実行しない。
