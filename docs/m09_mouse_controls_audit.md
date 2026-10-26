# M09 左クリック攻撃・右クリック防御（2026-10-25、ADR-028）

状態：実装・自動検査済み、ユーザーF5操作確認待ち。M08試作範囲完了・M09検証待ち・M10別指示待ちを維持する。

## 開始時の確認

main、HEAD `1bb2af840de659e3eedab2eeccd2bd5bb1ddef6b`、作業ツリーに変更なし。AGENTS、開発状況、08／10／11／12／14、入力・方向選択・防御・InputMap・UIと関連検査を照合した。

変更前も左クリックの本体／部位直接指定は攻撃まで接続済みだった。方向補助は右クリック専用で、右はtarget_attack、左はattackへ割当。防御はI／パッドLBのguardをイベントと保持状態で受け付けていた。今回は入力を移行し、攻撃・防御の状態機械を共用する。

## 現在の入力と処理

| 入力 | 動作 |
|---|---|
| 左クリック | 直接指定＋攻撃。直接対象がなければ画面方向で選択。戦闘中は既存の次段予約1個 |
| 右クリック保持／解除 | 既存Guardの開始／維持／解除。右で攻撃・踏み込み・次段予約は発生しない |
| J／I／L | 選択対象を攻撃／防御／切替。キーボードだけで利用でき、カーソル位置は不要 |
| WASD・矢印／Space／Q・E | 既存の移動・方向帰還／ジャンプ／カメラ回転 |

左右20度とInspectorの `Player → TargetDash → Settings → Directional Click Tolerance Degrees` は維持。直接指定を最優先、方向指定は有効な扇内の選択対象→角度差→距離→NodePathで決める。候補なしは空振り・消費なし。pick_target／pick_attack_target、request_attack／request_followupと既存の命中処理を共用する。

InputMapのattackはJ／左／パッド西を維持し、右だけguardへ移動。guardはI／LB／右。旧target_attackは既存設定の参照を壊さないため空の予約枠として残し、戦闘の受信条件から除外する。14アクション・32割当、キーボードの追加／変更なし。

防御の発動条件、姿勢、軽減、割り込み・Recover／Returnへの復帰は既存処理を使う。マウスの開始だけを_unhandled_inputで受け、UI上の押下を除外する。解除は_inputでも受けるためHUD上で離しても残らない。全体Inputの右保持だけでは防御を開始させず、UIで押して画面へ移動しても無効とする。同時保持のキーボード／パッドはInputMapの既存割当に従う。短いタップは既存_pending_guardと同じ受信方式。

命中・ダメージ、武器／Motion／効果、近距離省略、踏み込み、連撃、撃破後の予定時間、帰還上下限・経路／衝突、カメラ固定、敵AIは変更しない。敵試験の案内文だけ新操作へ合わせる。

## 変更ファイル

- 本番：project.godot、scripts/player/target_dash.gd、scripts/ui/hud.gd、scripts/enemies/practice_selector.gd（案内のみ）。
- 検査：tests/m00_input_map.gd、m06_target_dash.gd、m06_target_selection.gd、m07_combo.gd、directional_click.gd、m09_startup.gd。既存検査の攻撃イベントは左へ移し、方向専用だった左空地の期待値を新操作へ更新。命中・消費・地形・帰還の合否条件は維持する。
- 文書：README、08／10／11／12／14、DEVELOPMENT_STATUS、旧方向クリック記録の操作更新注記、本書。

## 自動検査

Godot `4.7.2.stable.official.ed1daf0bf`／Windows／Compatibility・GTX1080、物理60Hz。検証用Godotは逐次実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --script tests/m00_input_map.gd
& $godotExe --path . --script tests/directional_click.gd
& $godotExe --path . --script tests/directional_click.gd -- --fps30
& $godotExe --headless --path . --script tests/directional_click.gd -- --reload
& $godotExe --path . --script tests/m09_startup.gd
$regressions = @('m06_target_dash','m06_target_selection','m07_controls','m07_auto_aim',
    'm07_combo','m07_chain','m07_wall_contact','m08_defense','m08_guard_sprite',
    'in_place_attack','defeat_return_timing','return_travel','attack_motion',
    'weapon_effects','m09_enemy_combat','m09_enemy_dash')
foreach ($test in $regressions) {
    & $godotExe --headless --path . --script "tests/$test.gd"
}
```

最終結果：**19種類21条件すべてPASS・終了0**。最終コードに対する以下の結果を採用し、拡張前の試行は数に含めない。

| 検査 | 結果 |
|---|---|
| m00_input_map | 14アクション・32割当、合成押下／解除、main読込がPASS |
| directional_click・実描画60／30fps上限 | 1469／837 assertionsでPASS。直接／方向・4Yaw・角度境界・移動・複数敵・3段予約・右保持／UI解除・UI押下漏れ・I相互保持・割り込み・連打・解除後移動／ジャンプ・L/Jを含む |
| directional_click・別プロセス--reload | 2 assertions、保存設定の再読込PASS |
| m09_startup・実描画 | 実F5初期シーンで動く敵への左クリック命中・右保持防御、既存の敵攻撃・GUI切替／resetがPASS |
| 既存関連16本・ヘッドレス | 上記regressionsの全16本がPASS。近距離3276、撃破待機1869、帰還6010、モーション1684、効果2246、敵戦闘56、敵踏み込み171 assertions。残りは各ログのPASSを確認 |

editor importは終了0。最終ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。検証環境のuserログ保存・証明書読取・エディター設定保存のERRORは残るが、スクリプト解析・検査の失敗とは区別する。ログはGit除外の `.godot/m09_mouse_*.log`、集計は `.godot/m09_mouse_primary_results.json` と `.godot/m09_mouse_regression_results.json`。

静的照合：TargetDashの入力受付・保持を扱う5既存関数以外の55関数はHEADと同一。武器／Motion／画像・シーン・戦闘Resource・Controller／PlayerSprite・敵AI本体／弾・検査fixtureにHEAD差分なし。文書を含む `git diff --check` 合格。検証用Godotは終了済み。

今回のユーザーF5操作・操作感、実機ゲームパッド、長時間・複雑地形は未実行。

## F5での手動確認（ユーザー実施待ち）

F8で停止後にF5。最初は近接敵が動く。比較しやすい静止敵は上部ボタンで選択し、金色マークが出る距離まで近づく。マークのない遠距離・遮断対象は攻撃しない既存仕様。

1. 敵の本体・マークを左クリックし、その敵への指定と攻撃が1回で始まる。
2. 敵の手前／奥の地面を左クリックし、画面上の方向が合えば攻撃する。
3. 候補のない方向・許容角度の外側では攻撃も消費も起きない。
4. WASD／矢印で移動しながら左クリックし、移動方向によらずクリック方向の相手へ攻撃する。
5. Lで切り替え、扇内では選択相手が優先、敵の直接左クリックではその相手が優先される。
6. 左を保持しても自動連打せず、連打しても同じ一振りの重複ダメージや予約の増殖がない。
7. 最大3段・複数敵への次段指定・途中撃破後のリズムと空振りなしを確認する。
8. 攻撃後に元地点へ帰還し、近距離で位置不変なら不要な帰還移動がない。
9. 右を押すと既存の盾・防御姿勢になる。
10. 右保持で防御を維持し、攻撃・帰還中の右は既存の割り込みに従う。Iとの同時保持も確認する。
11. 右を離すと解除。HUDの上で離しても残らず、既存のRecover／帰還または通常状態へ戻る。
12. 右で敵や敵方向を押しても攻撃・踏み込み・連撃予約が発生しない。
13. 解除後の歩行・Space・左攻撃、方向入力帰還を確認する。
14. Q／E回転後も4方向の対象選択、剣・斬撃と防御表示が正常。
15. マウスを操作せずJ／I／L、WASD／矢印・Space・Q／Eを使える。
16. 壁・低い障害物・段差・崖を挟んだ敵へ不正に攻撃／移動しない。
17. HUD／試験ボタン上の左右クリックは戦闘を発動しない。UIで右を押したままカーソルを外しても防御しない。試験切替は通常どおり動く。

以前の「攻撃できない」報告についても、この新操作でユーザー再確認が必要。自動検査の合格だけで元の報告の原因特定・ユーザー受入済みとはしない。コミット／Pushは未実行。
