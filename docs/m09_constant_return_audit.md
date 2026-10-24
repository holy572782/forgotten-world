# M09 主人公の一定速度帰還（2026-10-24、ADR-025）

状態：M09追加改善として実装・自動検査済み。ユーザーF5受入は未実行。M08試作範囲完了・既存残件・M10別指示待ちを維持する。

## 調査と変更範囲

開始時はmain、HEAD `b82f3d83a19ff8185831b97e865a6b05f303c51a`、git statusクリーン。AGENTS、開発状況、必読資料、ADR、10／11／12／14とPlayer・TargetDash・Motion・WeaponData・手動帰還／連撃を照合した。

従来はReturnの計画時間を距離÷速度の後0.10〜0.35秒へ制限し、実移動にもApproachと共通のsmoothstepを使用していた。前者は距離に応じた平均速度、後者は帰還中の瞬間速度を変える。今回、Returnだけ両方を外す。踏み込み速度12m/s・時間上下限0.25〜0.40秒・smoothstepを維持する。

保存済みの剣リーチ2.5m、Combo Input Window0.1秒、Motionのフレーム比率[0.4,0.2,1.5]は維持する。Motion原本にReturn Speedの上書きはなく、今回の仮基準12.0m/sをクラス既定値として適用する。将来の武器ごとの上書きは既存WeaponData.motionを使用する。

## 帰還の計算と互換性

- 安全補正後の経路距離÷Return Speedをそのまま_durationへ設定。Returnには時間の最小／最大制限を適用しない。
- 共通の物理進行_elapsed÷_durationをReturnでは線形に使用する。中間点を新しい時計やイージングで計算しない。等しい物理時間に等しい距離を進む。
- 最終区間だけは残距離を超えないよう終点で止める。物理tick未満の帰還も、最低時間で引き延ばさず最初の更新で到着する。所要時間の観測値は物理／描画tickに丸められる。
- 元位置との距離1mm以内は従来どおり移動・スナップなしで既存終了処理へ進む。時間計算後に経路長が0となる場合も、進行率を1とし0除算を防ぐ。
- 旧return_minimum_travel_time／return_maximum_travel_timeは@export_storageにして旧tresの読込／再保存に保持する。Inspectorからは非表示、時間計算・snapshotの制限処理には使わない。削除やResourceの書換え・移行は行わない。将来の制限再導入のための機能や切替フラグは追加しない。
- Return Speedの既存0.1〜40m/sの制限を維持。NaN／INFのフォールバックは新既定12。0／負値は既存どおり下限0.1へ制限する。低い有効速度なら長時間かけて帰還することが正しく、時間上限で強制加速しない。

基準点・経路安全補正・原寸カプセル・Path.clear／move_and_collide・毎tickの足場検査は従来どおり。安全経路が塞がれば安全位置で停止してFREEへ戻る。Guardで止めたReturnの再開も既存_begin_travelで残距離と同じ速度から再計算する。

攻撃終了条件・Combo Input Window・Final Attack Wait・撃破後の予定スロット・手動帰還優先順位は変更しない。剣／白斬撃／本体の共通時計・ダメージ・敵AI・カメラ・Controller・盾も維持する。

## Inspector

F8で停止し、main→Player→TargetDash→Equipped Weapon→Motion→**Return travel (metres per second)**→**Return Speed**を編集する。FileSystemから`resources/weapons/default_attack_motion.tres`を直接開くか、`resources/weapons/one_handed_sword.tres`のMotionを展開しても同じ設定になる。

| 項目 | 初期値 | 単位・範囲 |
|---|---:|---|
| Return Speed | 12.0（仮基準） | m/s、0.1〜40 |
| Approach Speed（維持） | 12.0 | m/s、0.1〜40 |
| Minimum Travel Time（踏み込み専用、維持） | 0.25 | 秒、0.05〜2 |
| Maximum Travel Time（踏み込み専用、維持） | 0.40 | 秒、0.05〜2 |

Resourceを保存してF5。リモート側だけの編集は保存されない。旧帰還時間の上下限は表示しない。武器ごとに別のMotion Resourceを割り当てれば別速度を保存できる。共有Motionを直接編集すると、それを使う武器に共通で反映される。装備UIは追加しない。

| 実際の帰還距離 | 12m/sでの計画時間 |
|---|---:|
| 1mm以内 | 移動省略 |
| 0.4m | 約0.0333秒 |
| 0.8m | 約0.0667秒 |
| 1.4m | 約0.1167秒 |
| 3.7m | 約0.3083秒 |

速度2m/sでは1.4mを0.70秒で帰還し、旧最大0.35秒を超えても一定速度を保つ。速度24m/sでは同じ距離の計画時間は12m/sの半分になる。

## 変更ファイル

- 本番：`scripts/combat/attack_motion_settings.gd`、`scripts/player/target_dash.gd`。
- 検査：`tests/return_travel.gd`（一定速度の実移動量・時間比例・旧Resource互換）、`tests/attack_motion.gd`（低速度時も距離÷速度に応じた有限の検査待ち上限を使う）。
- 文書：README、08／10／11／12／14、DEVELOPMENT_STATUS、旧return_travel／attack_motion実装記録、本書。
- 既存の武器／Motionのtres原本、画像・Shader・敵AI・DashPath・Controller・カメラ・描画制御は変更しない。新マイルストーンなし。

## 自動検査

Godot4.7.2／Windows／Compatibility、物理60Hz。検証用Godotは逐次実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/return_travel.gd
& $godotExe --path . --script tests/return_travel.gd -- --fps30
& $godotExe --headless --path . --script tests/return_travel.gd -- --reload
```

return_travelでは実際の物理更新間の変位÷経過物理時間を観測する。中間区間は設定速度と一致し、最終区間は速度上限を超えず到着することを確認。短／中／長距離、2倍距離、速度2／12／24、極小距離、無移動、1／2／3連撃と途中撃破、旧上下限変更が無効、踏み込み設定との独立、不正速度・実行後の設定変更を検査する。保存／別プロセス再読込で速度・旧プロパティとInspector非表示を確認する。

既存の実測比較fixtureから攻撃／連撃とReturn開始時刻・命中／消費／予定数が変わらないことを比較する。関連M06〜M09、近距離攻撃、壁際、手動帰還／Guard再開／歩行／ジャンプ、撃破待機、演出同期・型読込・敵AIも回帰する。

新検査の実描画60上限は7173 assertions、30上限は3795、別プロセス再読込は4でPASS・終了0。60上限の中間区間では0.4／1.4／3.7mの帰還が約11.99999〜12.00002m/s。速度2では約2m/s、24では約24m/sを確認した。0.4→0.8mで計画時間が約0.0333→0.0667秒、1.4m／速度2では0.70秒で旧最大時間の制限がないことを確認。0.5mmは移動なし、1.5mm超の帰還は1物理tickで安全終了した。

比較基準8条件の踏み込み／攻撃開始・Return開始は60上限ですべて0tick差。通常3段／1段撃破／2段撃破は同じ116tickでReturn開始。帰還移動以外の戦闘リズムを保持した。実測値は`.godot/return_travel_60.json`／`return_travel_30.json`、最終採用ログ一覧は`.godot/constant_return_results.json`へ集約する。

最終は**13種類15条件すべてPASS・終了0**。個別ログは`.godot/constant_return_*.log`。初回の補助検査constant_return_firstは最終件数へ含めない。

| 最終検査 | 結果 |
|---|---|
| return_travel実描画60／30・別プロセス再読込 | PASS、7173／3795／4 assertions |
| in_place_attack | PASS、3254 assertions。近距離・境界・近遠混在・4方向／Q/E・障害物／足場 |
| m06_target_dash／m07_chain／m07_combo／m07_wall_contact | 全PASS。右クリック・連撃・帰還閉塞・壁際接触を維持 |
| m08_defense | PASS。手動帰還・保持／連打・Guard割り込み／再開・通常歩行／ジャンプ・安全停止 |
| defeat_return_timing | PASS、1869 assertions。従来3段と各撃破74tick・5段128tickを維持 |
| attack_motion／attack_motion_loading | PASS、1684／14 assertions。負の外部速度を0.1へ制限した約14秒の帰還も終了 |
| weapon_effects | PASS、2244 assertions |
| m09_enemy_combat／m09_enemy_dash | PASS、56／171 assertions。敵側コード・時間データは変更なし |

最終editor import終了0、スクリプト／Shaderエラーなし、git diff --check成功。証明書読込とsandbox外editor_settings保存に関する環境ERRORは別扱い。保護対象のResource・画像・Shader・AI・DashPath・Controller・カメラ・描画コードにHEAD差分なし。検証用Godotは終了済み。自動検査の合格をユーザーのF5受入や最終速度決定として扱わない。

## F5確認（未実行）

1. **F8→F5→静止敵**。現在の保存済みリーチ2.5mを超える近・中・遠距離から右クリック／Jで攻撃。Returnが等速で、距離に応じて長くなることを確認する。
2. 再現配置は主人公初期地点のまま、リモートでTrainingEnemyを(-6,0,-2.6)、(-6,0,-3.5)、(-6,0,-4.8)へ1つずつ置く。帰還距離は約1.5／2.4／3.7m、12m/sの計画時間は約0.125／0.20／0.308秒。各回F8→F5で再初期化し、画面内・金色マーク5m圏内を保つ。リモート配置は保存しない。
3. 安全な2.5m以内から攻撃し、踏み込みもReturn移動もないことを確認する。
4. 1／2／3回攻撃、複数敵への連撃、1／2段目での撃破を確認。Return開始までの待機と残りスロット、空振りなし、最初の基準点への帰還を確認する。
5. InspectorでReturn Speedを6へ保存→F5で同じ距離を比較し、12の約2倍の移動時間になることを確認する。次に24で約半分、最後に好みの速度へ調整して保存する。踏み込みの速度・攻撃モーション・入力猶予は変わらないことを確認する。
6. Q/E、方向入力帰還、Return中のI防御／解除後の再開、帰還後WASD・Space、4方向の剣／白斬撃、壁・段差・崖の安全停止、近接／遠距離AIを確認する。Spaceを戦闘中から保持した場合は従来どおり離して押し直す。

ユーザーの操作感・最終速度決定・F5受入は未実行。実機パッド・長時間・任意の複雑地形／大型敵等の既存残件と、保守的な平坦直線経路のみという制約を維持する。M09検証待ち、M10へ進まない。commit／push未実行。
