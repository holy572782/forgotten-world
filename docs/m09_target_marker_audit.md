# M09追加修正：金色ターゲットマークの描画統一

**2026-10-31追記（ADR-051）**：ユーザーの追加報告により、実キャラの描画がマークを覆う問題を別に再現した。本書の画素比較はキャラ本体を隠した単体検査で、この重なりを確認したものではなかった。現在のマーク材質／描画順は `m09_target_marker_depth_audit.md` を優先する。以下はADR-050時点の記録として保持する。

2026-10-30／ADR-050。M09基本戦闘完了を維持し、今回の表示のユーザーF5確認は未実行。M10は別指示待ち。commit／pushは実行しない。

## 調査と原因

AGENTS・進捗、関連仕様08／10／11／12／14、両敵シーン、Targetable／TargetDash、敵画像・被弾／予告表示とカメラの遮蔽処理を照合した。開始時の未追跡ファイル`addons/effekseer/bin/windows/~libeffekseer.x86_64.dll`は今回の対象外として保持する。

実際にはtraining_enemyとpractice_enemyのMarker設定は同一で、両者ともTargetable._readyで共通のImmediateMesh／StandardMaterial3Dを生成していた。雑兵と魔導士も同じpractice_enemyシーンを使う。敵固有の別マークShader・影用の重複描画はない。

表示差につながるのは選択対象の数である。従来は選択中なら方向に関係なく満円になる。静止敵が複数なら通常は前方の1体を選ぶ一方、雑兵／魔導士1体の試験では後方の1体にも既存のfallback選択が働くため、背面でも満円が残る。同じ1体配置にすると静止敵でも再現した。修正前の新検査は3種とも背面の表示で失敗し、それ以外の論理選択は正常だった。

## 最小修正と共通処理

- 既存Targetableをそのまま共通描画コンポーネントとして使う。set_availableに描画用のin_front引数を追加し、論理selectedと満円／中空の表示を分離した。既存の2引数呼出しは互換性を維持する。
- TargetDash._update_markersが既存の主人公facing_worldとauto_aim_half_angle_degreesから画面表示用の前方判定を渡す。XZ方向だけを使い、カメラ回転や高低差で前後が変わらない。
- 前方の選択中対象は満円、背面の対象は選択中でも中空。非選択候補は従来どおり中空である。前方コーンの角度は既存の照準設定を参照し、新しい角度／距離設定は増やさない。
- fallback・L／クリックによる手動選択、対象保持、候補／安全経路・攻撃開始条件には手を加えない。背面の中空マークでも論理選択を維持し、既存操作で攻撃できる。

## 維持する描画値

| 項目 | 静止敵と共通の値 |
| --- | --- |
| 形状 | カメラ正対の32分割の円／中空円 |
| 半径 | 外0.25m／中空の内0.17m |
| 色／透明度 | Color(1, 0.72, 0.12, 1)、不透明 |
| 位置 | 各TargetableからローカルY+2m、Meshの追加offsetなし |
| 描画 | Unshaded、両面、通常の深度テスト、render_priority=0 |
| 影 | Marker/Meshだけcast_shadow=OFF、影の代理描画なし |
| 可視／クリック | 既存の候補判定からvisibleとArea3Dのlayer8を同時切替 |

親の移動・上下移動に同じ階層で追従する。画像やカプセルの大きさからマークを拡縮しない。Targetableの攻撃座標を表示用に変更しない。HP0時の既存非表示とクリック無効化も維持する。

## 変更ファイル

- scripts/combat/targetable.gd
- scripts/player/target_dash.gd（_update_markers内の描画引数のみ）
- tests/target_marker_unified.gdとUID
- AGENTS.md、docs/DEVELOPMENT_STATUS.md、docs/08_DECISIONS.md、docs/12_TEST_PLAN.md、docs/14_TARGET_DASH_COMBAT_SPEC.md、本書

敵AI・画像・音／エフェクト・武器Resource・シーンは変更しない。

## 自動検査

Godot 4.7.2／Windows・Compatibility、同一ソースの隔離コピー`.godot/mage_fire_validation`で検査する。新target_marker_unifiedは3種×前後×4カメラの描画と実選択を確認し、雑兵・魔導士のマーク画素が静止敵と完全一致すること、位置／色／深度／影、手動後方選択と攻撃候補の維持、上下移動への追従、死亡後の可視／クリック無効を確認する。表示差分のPNGも保存し、満円／中空を目視した。

最終結果は次の7種類すべてPASS・終了0。採用ログにSCRIPT ERROR／ERROR／WARNINGなし。

| 検査 | 結果 |
| --- | --- |
| target_marker_unified | 121項目。4カメラで3種の満円／中空の画素が一致 |
| target_marker_shadow | 10項目。マーク影なし、他の物体の影は維持 |
| m07_auto_aim | 前方優先・背面fallback・手動選択・表示ON/OFF PASS |
| directional_click | 1468項目。直接指定と方向クリック／対象優先・実攻撃 PASS |
| enemy_auto_jump | 5837項目。両敵の実階段／坂・通常ジャンプ／home帰還 PASS |
| elevation_controls | 263項目。高低差・空中防御・方向帰還／連撃・安全停止 PASS |
| m07_chain | 対象切替・3連撃・帰還・カメラ PASS |

Godot最終エディターimportも終了0・エラー／警告なし。コード2本と新検査／UIDの4ファイルは隔離コピーとSHA256一致。敵AI／画像／エフェクト／音／カメラ・既存Scene／Resource／project.godotはHEAD差分なし、git diff --check合格。未追跡の既存一時DLLは保持した。

修正前の再現ログは`.godot/marker_unified_before.log`、修正後は`marker_unified_after.log`、回帰は`marker_reg_*.log`と`marker_reg_results.json`、最終importは`marker_unified_import_final.log`。比較PNGは隔離コピー内の`.godot/marker_{static,melee,ranged}_{filled,hollow}.png`。

追従の新検査は姿勢変位を直接与えるもので、実際の通常ジャンプや戦闘移動の安全性は上記の既存検査でも確認した。全行動中のマークの見やすさ・最終的な操作感はF5で別に確認する。

再現はPowerShellで`./tools/validate_mage_fire.ps1 -ImportOnly`を実行後、Godot 4.7.2へ`--path .godot/mage_fire_validation --script res://tests/target_marker_unified.gd`を指定する。描画比較を含むのでヘッドレスにはしない。

## F5確認（ユーザー未実行）

1. F8→F5。静止敵／近接敵／遠距離敵を切り替え、同じ金色・サイズ・頭上位置で表示されること。
2. 主人公の向きを変え、前方の選択対象は満円、背面は中空になること。Lによる背面の選択は維持され、左クリック／Jで従来どおり攻撃できること。
3. Q/Eで回転し、円がカメラに正対し、向きに対する切り替えも保たれること。
4. 坂・階段、通常ジャンプ、赤い予告／踏み込み／帰還中にマークが敵へ追従し、影を落とさないこと。HP0時には消えること。
5. 主人公の高低差攻撃・防御・方向帰還・3連撃と、両敵の剣／魔法・画像／音に退行がないこと。

人による見やすさ・操作感、任意の複雑地形／多数敵・長時間性能は未確認。
