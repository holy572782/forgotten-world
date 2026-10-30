# M09追加修正：キャラクターに隠れる金色マーク

2026-10-31／ADR-051。M09基本戦闘完了を維持し、今回のユーザーF5確認は未実行。M10は別指示待ち。commit／pushは実行しない。

## 原因と再現

開始時はADR-050のコード・テスト・文書が未コミットで、Effekseerの一時DLLも未追跡だった。すべて保持し、その上へ今回の描画修正を追加した。

ユーザーの追加報告は満円／中空の選択差ではなく、キャラクターがマークを覆う描画順の問題だった。前回のtarget_marker_unifiedはキャラ本体を隠してマーク単体を比較しており、この問題を検出できていなかった。前回の照準表示修正は保持しつつ、今回の問題を別に記録する。

雑兵・魔導士／主人公のplayer_depth Shaderは画面の深度を参照し、輪郭のはみ出しを補正した深度を出力する。従来のマークは不透明StandardMaterial3Dで先に描かれ、後のキャラの描画で覆われていた。静止敵のカプセルはこのスプライトShaderを使用しないため、同じマーク材質でも重なり方が違っていた。

新target_marker_depthは実キャラを表示して、2敵種×4カメラ×満円／中空×主人公の前後4位置を描画する。修正前は例として満円1250画素のうち26画素しか残らず、中空670画素が全消失する場面も再現した。画像を`.godot/marker_depth_before.log`と検証コピー内のスクリーンショットへ記録した。

## 修正

- 共通Targetableのマークだけを専用ShaderMaterialへ変更する。半径／32分割／金色・不透明度1／頭上Y+2m／カメラ正対とcast_shadow=OFFは維持する。
- ALPHA出力で後段描画へ配置し、render_priority=10でキャラ・被弾フラッシュ・武器／斬撃の後に描く。
- 既に補正されたキャラの深度には隠されないよう、固定機能の深度テストを置き換える。Shader内では通常の不透明なシーン深度とマーク面を比較し、壁・床が手前にある画素を捨てる。深度バッファへは書き込まない。無条件の最前面表示にはしない。
- 既存の候補／壁・攻撃可否／死亡時の表示条件も維持する。Targetableの攻撃座標、MarkerのクリックArea、対象選択、前後切替、キャラShader／画像・AI／音・戦闘処理は変更しない。

## 変更ファイル

- assets/shaders/target_marker.gdshaderとUID（新規）
- scripts/combat/targetable.gd（既存ADR-050差分を保持）
- tests/target_marker_depth.gdとUID（新規）
- tests/target_marker_unified.gd（材質が専用Shaderになったことだけ期待値を更新。画素一致の条件は維持）
- tests/target_marker_shadow.gd（旧い影ONの再現に旧不透明材質を明示）
- AGENTS.md、docs/DEVELOPMENT_STATUS.md、docs/08_DECISIONS.md、docs/12_TEST_PLAN.md、docs/14_TARGET_DASH_COMBAT_SPEC.md、本書、前回監査の補足

## 検証

最終6種類すべてPASS・終了0、採用ログにSCRIPT ERROR／ERROR／WARNINGなし。

| 検査 | 結果 |
| --- | --- |
| target_marker_depth | 176項目。実キャラとの64の重なり、白フラッシュ／攻撃画像・武器、4カメラの全面壁／部分壁／背後の壁 |
| target_marker_unified | 121項目。3敵種の満円／中空の画素一致と前後選択・追従／死亡 |
| target_marker_shadow | 10項目。マーク影なし・旧材質の影の再現・他物体の影維持 |
| m07_auto_aim | 前方優先・背面fallback・手動選択・表示切替PASS |
| m07_chain | 3連撃・対象切替・帰還・カメラPASS |
| m08_defense | 防御・方向入力帰還・保持／解除・消費／命中と安全経路PASS |

新検査ではキャラを隠した旧不透明材質との比較により、元の金色と円の画素が変わらないことも確認した。修正後の実キャラ重なりで満円1250／中空670画素をすべて維持。修正画像を目視確認した。

Shaderの色を生成側から明示指定し、Inspector側でも値を取得できるようにした。旧影検査の「新材質を影ONにすれば旧影を再現する」という前提は材質変更後に成立しないため、旧不透明材質を明示する再現fixtureへ更新した。新表示の床に影がない条件は維持する。

最終Godotエディターimportは終了0・エラー／警告なし。検証コピーと今回のソース／Shader・テスト／UIDの7本はSHA256一致、git diff --check合格。採用ログは`.godot/marker_depth_reg_*.log`、集計は`marker_depth_reg_results.json`、最終読込は`marker_depth_import_final.log`。前回ADR-050の差分と未追跡DLLを保持し、今回キャラShader／敵AI／画像／音／Scene／Resourceへの変更はない。

再現はPowerShellで`./tools/validate_mage_fire.ps1 -ImportOnly`、次にGodot 4.7.2の`--path .godot/mage_fire_validation --script res://tests/target_marker_depth.gd`を描画ありで実行する。前回の単体表示検査と影・照準／連撃／防御帰還も回帰する。

## F5確認（ユーザー未実行）

1. F8→F5で近接敵・遠距離敵を切り替える。
2. 主人公が奥、敵が手前になる位置と、その逆の位置で、金色の満円／中空がキャラに隠れないことを確認する。
3. Q/Eで4方向に回し、歩行・ジャンプ・坂／階段・予告・踏み込み・帰還・被弾中もマークが追従すること。
4. 静止敵の形・サイズ・色・前後切替を維持し、全種で影がなく、壁の手前に不自然にマークだけ浮かび上がらないこと。
5. 左クリック／J・L切替・右クリック／I防御・方向帰還・3連撃と撃破後のマーク消去を確認する。

任意の透明材質・独自Shaderの遮蔽物、複雑な交差地形、多数敵／長時間性能、人による見やすさの受け入れは未確認。
