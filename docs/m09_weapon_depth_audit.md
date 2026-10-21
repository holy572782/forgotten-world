# M09 鉄の剣の描画順・地面埋没の修正記録

日付：2026-10-21、ADR-019。**実装・自動検査済み、ユーザーF5再確認待ち。**

## 目的・開始状態

ユーザーの「上方向以外で剣が敵の後ろ／地面へ消える」という手動報告を受け、表示だけを修正する。開始はmain、HEAD `71ca155269cb8e127d81c67e7e1b15dac5eb3a26`、git statusクリーン。進捗と実物に差異なし。Issue／PRは作成していない。

受入条件は4方向各3コマの欠け解消、主人公との中心／同倍率／同期維持、敵・不透明壁の遮蔽、Q/E、段差／崖での表示、戦闘回帰。主人公48px・剣112px／336×448シートと原画配置、攻撃・踏み込み・連撃・帰還・防御・敵AIは維持する。

## 原因と設定調査

| 調査項目 | 実物と判断 |
|---|---|
| 親子・座標 | Player直下のAnimatedSprite3DとWeaponSwingは兄弟。剣へ本体transformをコピーし、基準のglobal_positionは両方(0,0,0)。位置ずれが原因ではない |
| 画像・倍率・中心 | 本体48px、剣112px。pixel_size=0.0375、scale=(1,1,1)、offset=(0,23)、方向別offset=0。同ピクセル倍率・中心一致を維持 |
| Billboard | 両方1（カメラ正面）。Q/Eに伴う方向とフレームは本体を参照。カメラ傾斜に沿った大きい剣の平面が地面を横切る |
| 深度 | 本体はplayer_depth.gdshaderで直立カプセルの深度へ補正。従来の剣はmaterial_override=nullで通常のビルボード平面。本体だけが補正され、敵との奥行きも一致しない |
| 地面 | キャンバスの高さは48px=1.8mに対し112px=4.2m。中央が同じでも下方の可視画素は足元を下回る。下向き全コマと横向き後半で床による欠けを再現 |
| 透明処理 | alpha_cut=DISCARD、nearest。新シェーダーもalpha<0.5をdiscardし、ALPHA出力による透明ソートへ切り替えない |
| render_priority | 0のまま。描画優先度の引き上げによる解決はしない |
| no_depth_test | 本番はfalse。一時比較でtrueの壁貫通を再現し、検査内で直後にfalseと正式materialへ戻す。最後にも復元を検査 |
| 敵 | 現在の練習敵はSprite3Dではなく3DカプセルMesh、敵layer4。画素ごとの3D深度で前後を判定する |
| 壁フェード | 既存OcclusionFaderはBaseMaterial3DのALPHAを0.3へ変更。地形遮蔽補助もこの既存状態を読み取り、カメラ／フェードの実装自体は変更しない |

## 修正

`weapon_swing_visual.gd`が剣専用ShaderMaterialを生成し、`actor_attachment_depth.gdshader`へ主人公のカプセル半径／高さと現在のシートを渡す。画面上の頂点・画像の中心は動かさず、本体と同じ直立カプセルを基準に奥行きを求める。

剣の各画素でシーン深度をワールド座標へ復元する。足元+0.015m以下の床／下方地形はキャンバスを切らないよう出力深度を補正し、それより上の不透明壁・敵は重なった画素の深度で遮蔽する。手前の敵が主人公の足元を隠すだけで剣全体を消す処理は入れない。微小なlayer_depth_bias=0.000002は本体との競合回避用で、物理移動や無条件の最前面表示ではない。

足元近くの壁では、床へはみ出す剣が壁より手前の床に漏れる可能性があるため、カメラ→足元+0.015mへの地形layer1専用rayで補助する。不透明な可視Meshが足元を隠す場合だけ床補正部分を非表示にする。最大16層、非表示・shadow-only・既存ALPHAフェード面は除外し、敵layer4は検査対象に含めない。この読み取りで既存の壁フェードと整合させる。

独立AnimatedSprite3D、WeaponData→WeaponAttackVisualData→SpriteFrames、方向別offset、単一のアニメーション時計を維持した。SubViewport合成は不要と判断した。付属レイヤー用深度とbiasは後の斬撃表示にも利用可能だが、新エフェクト／装備UIは今回追加していない。

## 描画比較

`tests/weapon_depth.gd`は本番Playerの本体と剣を静止させた最小描画fixture。剣の表示あり／なしの差分画素を取り、地面なしの参照と地面ありの修正後で**画素集合の完全一致**を検査する。実戦操作や命中の検査とは区別する。

| 方向・コマ | 地面なし参照 | 旧通常面＋地面 | 修正後＋地面 |
|---|---:|---:|---:|
| 下0／1／2（各） | 1059 | 0 | 1059 |
| 左0・右0（各） | 1045 | 1045 | 1045 |
| 左1／2・右1／2（各） | 1062 | 565 | 1062 |
| 上0／1／2（各） | 1045 | 1045 | 1045 |

- 全面不透明壁：診断用no_depth=trueは1059画素漏れ、修正後は0。診断設定は復元済み。
- 部分壁：1059→415画素。手前のカプセル：1059→325画素。奥のカプセル：1059画素で参照と完全一致。
- 主人公の足元だけに重なる手前のカプセル：外側の剣は参照と完全一致し、不必要な全消去なし。
- 足元近くの不透明壁：剣0画素。既存方式のALPHA=0.3へ変更すると補助遮蔽が解除され、剣が見える。
- 足元を0.6m上げ、広い床と2m角の崖端で、カメラYaw=0／90／180／270の各シルエットが地面なしと完全一致。

## 実行と結果

Godot `4.7.2.stable.official.ed1daf0bf`／Windows、物理60Hz。描画はCompatibility／OpenGL3.3、GTX1080。一度に1プロセスずつ実行した。これは対象環境の記録であり、最終対応端末や性能保証ではない。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script res://tests/weapon_depth.gd --log-file .godot/weapon_depth_fixed.log -- --capture
& $godotExe --path . --script res://tests/iron_sword_animation.gd --log-file .godot/weapon_depth_live60.log -- --capture
& $godotExe --path . --script res://tests/iron_sword_animation.gd --log-file .godot/weapon_depth_live30.log -- --fps30 --capture
& $godotExe --headless --path . --editor --quit --log-file .godot/weapon_depth_final_import.log
```

- 新weapon_depth：37 assertions、PASS・終了0。画像・全12コマの比較値は`.godot/weapon_depth_*.png`／`weapon_depth_metrics.json`に保存。
- 実戦経路iron_sword_animation：最終60上限2113、30上限1154 assertions、PASS・終了0。件数は観測tick数で変動する。4方向／Q/E実入力中の同期、画像と倍率、武器参照、被弾／防御、命中・消費・帰還を検査。実画面でも下向きの剣が床から消えず、手前の敵との関係を確認した。
- 関連9種類：m04_camera／m04_occlusion／m04_shadows／m07_chain／m08_defense／m08_guard_sprite／m09_enemy_dash／weapon_sweep／player_damage_visualはヘッドレスPASS・終了0。最終調整後にはm04_occlusion／m09_enemy_dash／weapon_sweepと上記描画2条件を再実行し合格。新規と既存を合わせ11種類で、全スイート再実行の主張ではない。
- 一覧は`weapon_depth_results.json`、最終再実行は`weapon_depth_final_results.json`。最終ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。証明書ストア・GLES3キャッシュ保存・エディター設定保存の環境ERROR、M04の意図したCamera safety警告とは区別する。
- 調査中はfixtureの物理処理停止時点と診断material切替順序を修正した。主人公をTreeへ追加後に停止し、診断から次のposeへ進む前に正式materialを復元している。これらの初期失敗を合格結果に含めない。
- 最終weapon_depthの再実行37 assertionsとヘッドレスeditor importは終了0。新Shader／検査のUIDを生成した。git diff --check成功、保護対象の本体／戦闘／画像／武器データ／カメラはHEADと差分なし。確認用Godotプロセスは終了済み。

## 変更ファイル

- 本番：`scripts/player/weapon_swing_visual.gd`、新規`assets/shaders/actor_attachment_depth.gdshader`。
- 検査：新規`tests/weapon_depth.gd`とGodot生成UID。
- 記録：README、ASSET_REGISTER、ADR-019、システム仕様、実装計画、テスト計画、戦闘仕様、DEVELOPMENT_STATUS、本書。
- 本体シェーダー、シーン階層、主人公／剣の画像、SpriteFrames、武器判定データ、戦闘・防御・敵AI・カメラのソースは変更なし。鉄の剣PNGのSHA256は`1b666a412cf6c3ddfa00df05f6ff83d69449e1bda5b41a2668ac2ad3748953ba`を維持。

## Godotでの手動再確認

1. F8で停止→F5。J／クリックで攻撃し、Q/Eで回転しながら北・南・東・西各3コマを確認。地面で欠けず、中心・倍率・手元が本体と揃うこと。
2. 敵の前後・近くで攻撃。手前の敵に重なった部分だけが隠れ、奥の敵に剣が隠れたり、本体と剣が別々の奥行きに見えたりしないこと。
3. 不透明壁の背後／際、段差・崖で確認。壁越しの剣の漏れ・床への埋没がないこと。既存方式で壁が半透明になる場合は本体と剣が一緒に見えること。
4. 連撃、方向入力帰還、I防御と盾維持、敵AIの接近・反撃を確認。範囲攻撃はweapon_sweep_trial.tscnをF6で前方3体への命中・1消費・帰還を確認。

ユーザーのこの修正版でのF5／F6操作は未実行。任意の透明Shader、複雑な交差地形、多数／大型敵、長時間性能、実機ゲームパッドは未検証。先行ADR-018の上向き一部コマの柄と手元の隙間は原画像の配置に関する別件として要レビューを保持する。M08試作範囲完了、M09検証待ち、M10別指示待ち。commit／pushは未実行。
