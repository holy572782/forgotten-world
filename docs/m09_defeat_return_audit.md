# M09 敵撃破時の帰還タイミング修正

2026-10-21、ADR-020。M09追加改善。**実装・自動検査とユーザー手動受入を区別し、M09検証待ちを維持する。** 新マイルストーンは作成しない。

## 開始と変更範囲

main、HEAD `cfc6322b37eb8e3fee137dbb06f10ac0521e5433`、開始時git statusクリーン。前回の剣深度修正はユーザー側でコミット済み。DEVELOPMENT_STATUSと実物に差異なし。今回の目的は「途中撃破で予定の攻撃終了を早めない」こと。Issue／PRは作成していない。

本番ソースの変更は`scripts/player/target_dash.gd`のみ。新検査`tests/defeat_return_timing.gd`、README・ADR・システム／戦闘仕様・実装計画・検査計画・進捗・本書を更新する。画像・武器Resourceの値・敵AI／HP／死亡処理・描画／カメラ・踏み込み／帰還経路・InputMapは変更しない。

## 原因と旧仕様との差分

旧TargetDashはphysics_stepの無効参照、_attackの開始時・命中直後の対象不成立、_advance_queuedの予約先不成立で_begin_returnを直接呼んでいた。命中フレームでHP0になると、再生中の一撃や予約を中断して帰還していた。

今回のユーザー指示で、旧ADR-011／017等の「対象死亡／喪失で帰還」を変更する。生存対象の移動・画面外・壁／足場の異常は引き続き安全中断する。移動安全性を緩めて死亡先へ踏み込む修正ではない。

## 実装仕様

1. 開始時の武器複製を維持し、予定回数を`min(max_combo_hits, floor(開始時stock.current / stock_cost_per_hit))`で固定する。途中で元の武器設定が変わっても現在のサイクルは変えない。
2. `combo_hits`／`attack_id`は実斬撃専用。別の`_sequence_slots`で、実斬撃と対象なしで経過した回数を管理する。架空の命中・ID発行・支払いはしない。
3. 命中で倒した現在の一撃は完了まで再生する。以降に生存予約先があれば従来の段間・1個予約・安全判定・踏み込みへ進む。待機中もクリック、Lで選択してJなどの新しい予約を受理する。
4. 対象がなければ残り各回の`attack_duration / attack_speed_multiplier`と段間`combo_stance_duration`をStanceで保つ。歩行画像0コマ・停止、剣非表示。予定の最終回終了後に既存Returnへ移る。
5. 接近中の対象消失では安全停止し、接近残時間と未開始サイクルを待機へ置換。死亡／解放した予約先も同じ待機へ。生存する予約先が壁・範囲外等で不適切なら従来どおり安全帰還する。
6. 方向帰還・I防御・主人公HP0／reset・シーン終了は待機にも優先する。開始済み斬撃のアニメーション異常timeoutを維持する。待機中のストック回復は禁止のまま、実斬撃開始だけで支払う。
7. 生存対象に予約しない通常の入力猶予`combo_input_window`は変更しない。生存敵への予約なし自動攻撃は追加しない。別対象へ移動する時間は従来の実距離／安全経路による。
8. HealthComponentのHP0通知は即時。敵の死亡表示・弾削除も従来どおり。正式な報酬／死亡・リスポーンは既存未実装のままで、今回新設しない。

## 自動検査と仕様の対応

検査は本番Playerと実物理・アニメーション・HealthComponent.damageを使い、命中コールバックを手動で呼ばない。通常の全回予約サイクルと、各撃破ケースの初段開始→Return開始の物理tick数を比較する。

| ユーザー指定 | 検査 |
|---|---|
| 1／2撃目でも即帰還しない、開始時回数と時間を維持 | HP10／20で撃破、通常3段との時間比較、武器／ストック／費用／速度行列、開始後の元Resource変更 |
| 最終撃後は通常帰還 | HP30の3撃目撃破、通常完走との時間比較・元の帰還位置 |
| 他の生存対象があれば継続 | A撃破前のB予約、撃破後待機中のB予約、A→B各1命中・2支払い |
| 対象なしなら空振りしない | 待機中はwalkの0コマ・剣非表示・速度0、新しいattack_accepted／hitなし、未開始消費なし |
| 通常終了後に既存帰還 | Return開始tick・元位置誤差0.03m未満・カメラ／予約解除 |
| 死亡処理維持・無効参照安全 | HP0通知1回、Targetableの即時free、敵のqueue_free、命中前／接近中の消失、死亡した予約先 |
| キャンセル維持 | 待機中の方向入力・Guard・cancel・主人公HP0、生存対象移動／動的障害物による中断 |
| 武器別回数 | 1／2／3／5回、武器5・ストック3、費用2・速度2倍。残り時間と実支払いを分離 |

### 再現コマンド

プロジェクトルートで1プロセスずつ実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --script res://tests/defeat_return_timing.gd --log-file .godot/defeat_timing_headless.log
& $godotExe --path . --script res://tests/defeat_return_timing.gd --log-file .godot/defeat_timing_render60.log -- --capture
& $godotExe --path . --script res://tests/defeat_return_timing.gd --log-file .godot/defeat_timing_render30.log -- --fps30 --capture
```

Godot `4.7.2.stable.official.ed1daf0bf`／Windows、物理60Hz、実描画1152×720・Compatibility／OpenGL3.3／GTX1080。これは検証環境であり、最終対応端末の確定ではない。

| 条件 | 通常3段のReturn開始 | 1撃目で撃破 | 2撃目で撃破 | 最終撃で撃破 |
|---|---:|---:|---:|---:|
| ヘッドレス60上限 | 74tick | 74tick | 74tick | 74tick |
| 実描画60上限 | 74tick | 74tick | 74tick | 74tick |
| 実描画30上限 | 71tick | 73tick | 72tick | 71tick |

時間は初段の実斬撃開始が基準。74tickは約1.233秒、30上限の撃破差は最大2tick（約0.033秒）。30描画では既存アニメーション完了通知の量子化で通常基準自体が異なるが、撃破で早まらない。5回武器の60上限は通常／1撃目撃破とも128tick、30上限は123／127tick（約0.067秒差）。速度2倍・費用2・開始stock5の予定2回では60上限27／27tick、30上限25／26tick。厳密なフレーム固定化のための既存アニメ時計変更は対象外。

新検査：ヘッドレス1852、実描画60上限1837／30上限1042 assertions、すべてPASS・終了0。tickの観測数で件数は変動する。最終ログと一覧は`.godot/defeat_timing_*.log`／`defeat_timing_results.json`、時間行列は`defeat_return_metrics_60／30.json`。`defeat_wait_hit1_60.png`と`hit2_30.png`でHP0後の自然な停止姿勢・剣非表示を目視した。初回の検査で存在しないInputMap名をreleaseした2件のERRORを、実入力のみreleaseするよう検査側で修正し、最終3条件で再合格した。

### 既存回帰・最終点検

- 既存19種類がすべてPASS・終了0：ヘッドレスのm06_target_dash／m06_target_selection、m07_combo／m07_chain／m07_controls／m07_auto_aim／m07_left_selection／m07_range_display／m07_wall_contact、m08_defense／m08_guard_sprite、m09_enemy_combat／m09_enemy_dash／m09_timing／m09_startup、weapon_sweep／player_damage_visual／iron_sword_animationの18種類と、実描画weapon_depth（37 assertions）。新規と合わせ20種類であり、M00以降の全スイート再実行ではない。既存テストの期待値・ソースは変更していない。
- 最後に、元対象の同期free／敵のqueue_freeと生存予約の組み合わせを新検査へ追加し、`--freed-chain`をヘッドレス60／実描画30で実行。各17 assertions、PASS・終了0。_advance_queuedで元対象を比較する前にも生存を確認する。新検査の全ケースは先の3条件で、追加した2ケースはこの重点実行で確認した。ログは`defeat_freed_headless／render30.log`。再実行コマンドは上記script引数の末尾へ`-- --freed-chain`（描画30は`-- --freed-chain --fps30`）を付ける。
- 回帰の一覧は`.godot/defeat_reg_results.json`、ログは`defeat_reg_*.log`。全最終ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。証明書ストアERROR、editor importの設定保存ERROR、M04の意図したCamera safety警告とは区別する。
- 最終headless editor importは終了0、新検査のUID生成済み。git diff --check成功。Controller／本体・ダメージ・剣表示、combat共通部、敵AI、カメラ、assets／resources／scenesはHEADと差分なし。本番変更はTargetDashのみ。検証用Godotプロセスは終了済み。

## ユーザー手動確認

README末尾「敵撃破後の帰還」のF8→F5・静止敵手順を使用する。標準HP40／10ダメージで、先に3／2／1回当てHP10／20／30にし、帰還・ストック回復後に1／2／3連撃で倒す。途中撃破の待機、最終撃の帰還、生存予約先への連撃、空振りなし、方向帰還、I防御、リモートでの武器回数変更を確認する。

この修正版のユーザー実キー操作・操作感受入は未実行。実機ゲームパッド、長時間性能、複雑地形、多数／大型敵と既存の個別未検証事項を維持する。剣深度修正の手動受入と原画の上向き柄位置も未報告のまま。M08試作範囲完了、M09検証待ち、M10別指示待ち。commit／pushは未実行。
