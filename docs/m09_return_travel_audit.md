# M09 帰還時間の距離比例制御（2026-10-24、ADR-024）

> 同日追記（ADR-025）：帰還の上下限制限とsmoothstepを廃止し、Return Speed初期12m/sの一定速度へ更新した。本書は導入時の履歴。現在の設定・検査・手順は[一定速度帰還の実装記録](m09_constant_return_audit.md)を優先する。

状態：M09追加改善として実装・自動検査済み。ユーザーF5受入は未実行。M08試作範囲完了・既存残件・M10別指示待ちを維持する。

## 調査・原因

開始時はmain、HEAD `23726db53c11842ae4c3fdc5c9b297c4fbc6f2a6`、git statusクリーン。AGENTS、開発状況、ADR、M06〜M09の10／11／12／14と、Player・TargetDash・Motion・WeaponData・連撃／手動帰還の実物を照合した。

TargetDash._begin_travelは既に「経路距離÷速度」を計算していたが、ApproachとReturnの両方にMotion.minimum_travel_time=0.25秒／maximum_travel_time=0.40秒を適用していた。距離0.4mと1.4mが両方0.25秒になることを修正前の実描画検査で確認。距離比例そのものの不足ではなく、帰還にも同じ下限が適用されることが原因。

保存済みの剣はmelee_reach=2.5m、combo_input_window=0.1秒、Motionはframe_time_ratios=[0.4,0.2,1.5]。これらはユーザーの調整値として維持する。現行のApproach速度12、上下限0.25／0.40、Return速度10は個別上書きがなくクラス既定値。直前工程の記録にある1.4m／0.5秒は当時の値で、今回保存値を戻さない。

## 修正

- Motionにreturn_minimum_travel_time／return_maximum_travel_timeを追加し、既存return_speedと同じReturn travelグループへ表示。既存minimum_travel_time／maximum_travel_timeは名前・保存互換・初期値を維持し、Approach travelグループへ整理する。
- Returnのみ`clamp(安全補正後の経路距離 / return_speed, return_minimum_travel_time, return_maximum_travel_time)`を使う。Approachは従来の計算と値を使用。補正後の距離を使う点も従来どおり。
- snapshotで新しい秒数を0.01〜2へ制限し、最大が最小未満なら最小へ揃える。NaN／INFは各既定値へ戻す。速度の既存0.1〜40m/s制限と開始時の武器別複製を維持する。原本は変更しない。
- 帰還開始時の基準点との距離が1mm以下ならReturnを開始せず既存_finish(true)へ進む。絶対距離を使い、ワールド座標の大きさに依存する比較を避ける。微小な実位置はスナップせず、return_errorへ記録する。1mm超は通常の帰還を行う。
- 距離ゼロ判定は既存の帰還開始箇所だけに置く。攻撃終了の猶予・Final Attack Wait・撃破後の残り時間・手動帰還の優先順位は変更しない。
- 帰還先・既存smoothstep・Return姿勢・毎物理tickのPath.clear／move_and_collide・元カプセル・壁／段差／崖の安全停止・Guard割り込みと再開・カメラ固定解除は維持。瞬間移動・迂回・無敵・追加Hitboxを導入しない。

## Inspectorと保存

F8で実行を止め、FileSystemの`resources/weapons/one_handed_sword.tres`→Motionを展開する。シーンからはmain→Player→TargetDash→Equipped Weapon→Motionでも同じ設定へ到達する。直接`resources/weapons/default_attack_motion.tres`を開いてもよい。

| グループ／表示名 | 保存プロパティ | 初期値 | 単位・編集範囲 |
|---|---|---:|---|
| Approach travel / Approach Speed | approach_speed | 12.0 | m/s、0.1〜40。維持 |
| Minimum Travel Time | minimum_travel_time | 0.25 | 秒、0.05〜2。踏み込み専用、維持 |
| Maximum Travel Time | maximum_travel_time | 0.40 | 秒、0.05〜2。踏み込み専用、維持 |
| Return travel / Return Speed | return_speed | 10.0 | m/s、0.1〜40。既存項目 |
| Return Minimum Travel Time | return_minimum_travel_time | 0.10 | 秒、0.01〜2。新規 |
| Return Maximum Travel Time | return_maximum_travel_time | 0.35 | 秒、0.01〜2。新規 |

Resourceを保存し、F5で再実行する。リモート側の変更は保存されない。今回は既定値が新しい設定を供給するため、既存tresを再保存／書換えする必要はない。旧tresもそのまま読み込める。将来は武器ごとのMotionを複製し、その武器のWeaponData.motionへ割り当てる。装備UIは追加しない。

| 実際の帰還距離 | 修正前（10m/s、0.25〜0.40秒） | 修正後（10m/s、0.10〜0.35秒） |
|---|---:|---:|
| 0m／1mm以内 | 移動省略／座標依存の比較 | 移動省略、位置スナップなし |
| 0.4m | 0.25秒 | 0.10秒 |
| 1.4m | 0.25秒 | 0.14秒 |
| 3.7m | 0.37秒 | 0.35秒 |

速度は補間全体の所要時間を決める主設定であり、既存smoothstepのため瞬間速度は一定ではない。実際の状態終了は60Hz物理／描画更新の刻みに丸められ、計画時間から1〜数tick程度の差があり得る。最大値は移動区間の計画時間であり、攻撃終了前の待機・Guardでの停止時間は含めない。

## 変更ファイル

- 本番：`scripts/combat/attack_motion_settings.gd`、`scripts/player/target_dash.gd`。
- 新検査：`tests/return_travel.gd`とGodot生成UID、`tests/fixtures/return_travel_before.json`（修正前に実測した比較基準）。
- 既存検査：`tests/fixtures/combat_scene.gd`。既存の固定モーションに加え、試験用の複製だけをリーチ1.4m・入力猶予0.5秒に固定。ユーザーがF5用Resourceを調整しても、以前の回帰条件を再現できるようにする。
- 文書：README、08／10／11／12／14、DEVELOPMENT_STATUS、既存モーション実装記録、本書。
- 武器／Motionのtres原本、画像、Shader、敵AI、Controller、カメラ、判定・ダメージ式・武器表示／効果制御は変更しない。

## 自動検査

Godot4.7.2／Windows／Compatibility、物理60Hz。検証用Godotは1プロセスずつ実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/return_travel.gd
& $godotExe --path . --script tests/return_travel.gd -- --fps30
& $godotExe --headless --path . --script tests/return_travel.gd -- --reload
```

新検査は実際の攻撃・アニメーション・HP・状態遷移・物理移動を観測する。0／短／中／長距離、1／2／3連撃、1／2段目撃破、時間と速度の単独変更、踏み込み上下限との独立、0.5mm／1.5mmの誤差、不正／逆転値、実行開始後の設定変更、保存・別プロセス再読込・Inspector公開・原本非破壊を確認する。新旧の比較基準は修正前の実測JSONで、ダメージ・消費・予定回数・攻撃開始／帰還開始時刻を比較する。`--baseline`は修正前コードで基準を取得するための補助オプションで、現在の通常検査には使用しない。

関連する近距離攻撃、M06〜M09、壁際、手動帰還／Guard／保持歩行／ジャンプ、撃破待機、モーション／効果同期・型読込・敵AIを回帰する。

新検査の修正前実描画60上限は3664 assertionsでPASS。修正後の実描画60上限は6001、30上限は3181、別プロセス再読込は4 assertionsでPASS・終了0。60上限の比較8条件で、踏み込み／攻撃開始・Return開始はすべて0tick差。通常3段／1段撃破／2段撃破はいずれも116tickでReturn開始し、移動だけが短縮された。途中撃破の即帰還・空振り・追加消費はない。

実測JSONは`.godot/return_travel_60.json`／`return_travel_30.json`。0.4mの帰還区間は60上限で16→7物理tick、1.4mは16→9tick、3.7mは23→21tick。計画時間の0.10／0.14／0.35秒と物理刻みの違いを含む。修正前の入力猶予は固定fixture0.5秒であり、本番の保存値0.1秒を書き換えた測定ではない。

最終は**13種類15条件すべてPASS・終了0**。一覧は`.godot/return_final_results.json`、各ログは`.godot/return_final_*.log`。修正前の実描画はこれとは別に実施した。

| 最終検査 | 結果 |
|---|---|
| 新return_travel・実描画60／30・別プロセス再読込 | PASS、6001／3181／4 assertions |
| in_place_attack | PASS、3276 assertions。近距離・境界・武器別リーチ・混在連撃・4方向／Q/E・障害物／隙間／段差 |
| m06_target_dash／m07_chain／m07_combo／m07_wall_contact | 全PASS。右クリック・連撃・帰還閉塞・壁際を維持 |
| m08_defense | PASS。方向帰還・連打／保持・Guard割り込み／再開・帰還後歩行／ジャンプ・安全停止 |
| defeat_return_timing | PASS、1869 assertions。通常3段と各撃破74tick、5段128tick |
| attack_motion／attack_motion_loading | PASS、1684／14 assertions |
| weapon_effects | PASS、2246 assertions |
| m09_enemy_combat／m09_enemy_dash | PASS、56／171 assertions。敵側のコード変更なし |

最終editor import終了0、return_travelのUID生成、スクリプト／Shaderエラーなし、git diff --check成功。証明書読込・sandbox外のeditor_settings保存に関する環境ERRORはコードの失敗と区別する。保護対象のResource・画像・Shader・AI・カメラ・Controller・DashPath・描画コードにHEAD差分なし。検証用Godotは終了済み。ログと実測JSONは`.godot`内のGit除外ファイル。

## F5手動確認（未実行）

1. **F8→F5→静止敵**。保存済みの剣リーチは2.5m。2.5mより少し遠い敵へ右クリックまたはJで攻撃し、踏み込み・通常攻撃の後、素早く元位置へ戻ることを確認する。
2. 正確に試す場合、F5のリモートで主人公初期位置を維持し、TrainingEnemyを(-6,0,-2.6)へ置く。帰還距離は約1.5m、計画時間は約0.15秒。次にF8→F5でやり直し、(-6,0,-4.8)へ置くと約3.7m／0.35秒になる。金色マークの5m圏内・画面内を保つ。リモート配置はF8で破棄される。
3. 2.5m以内の安全な相手へ攻撃し、従来の踏み込み省略と帰還移動なしを確認する。
4. 1／2／3回攻撃と複数敵への連撃を確認。1／2段目で撃破しても即帰還せず、残り時間の自然待機・空振りなし・最初の基準点への帰還を確認する。保存済みCombo Input Window0.1秒は維持している。
5. 攻撃中の新しい方向入力による手動帰還、Return中のI防御・解除後の帰還再開、Q/E回転、Return終了後の保持WASD歩行とSpaceジャンプを確認。Spaceを戦闘中から保持した場合は従来どおり離して押し直す。
6. InspectorのReturn Minimumを0.20秒にして保存→F5、短距離の帰還だけが遅くなることを確認。元へ戻し、Return SpeedやReturn Maximumも1つずつ変更して確認する。踏み込みの速さ・剣振り・連撃間隔・帰還開始までの待機が変わらないことを確認する。
7. 壁／低い障害物／段差／崖の近くで不正に越境しないこと、剣・白斬撃が4方向で同期し、帰還中に残らないことを確認する。近接／遠距離モードで敵AIが通常どおり攻撃することも確認する。

操作感・ユーザーF5受入・実機パッド・長時間・任意の複雑地形／大型敵は未実行。既存の平坦な安全直線経路のみで、障害物迂回は未実装。M09検証待ちを維持し、新マイルストーンなし。commit／push未実行。
