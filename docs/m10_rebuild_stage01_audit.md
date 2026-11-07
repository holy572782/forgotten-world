# M10 新フィールド・工程00／01　構図確認

2026-11-07／ADR-064。工程00の既存調査と工程01の立体試作を実施。現在は**ユーザーの構図確認待ち**。9工程版の工程02は承認後に開始する。[今回の制作指示](briefs/m10_rebuild_nine_stages.md) ／ [参考画像と実画面を並べて見る](m10_rebuild_comparison.html)

## 工程00　既存実装と再利用

開始時HEADは `4509084`（旧M10-B01）。旧工程A・B01の実装と進捗記録が一致した。開始時の未追跡項目はEffekseerのエディター用一時DLLだけだった。既存の地形・材質生成は `scripts/maps/wind_hills/` にあり、通常シーンは既存Player、CameraRig、HUD、TargetDash、CombatFeedbackを明示接続している。工程00では旧入口をGodotで実際に起動し、主人公の接地と画面を記録した。[工程00・既存入口の実画面](images/m10_rebuild/stage00_existing.png)

新規マップの実装先は `scenes/maps/wind_hills_rebuild/`、`scripts/maps/wind_hills_rebuild/`、`resources/maps/wind_hills_rebuild/`。通常プレイは同じPlayer・方式B CameraRig・HUD・戦闘コンポーネントを参照する。比較用は独立Camera3Dと入力停止した実寸Playerを置く。敵は0体。M09の終了判断と旧M10の個別受入待ちは従来の監査を参照する。[M09](m09_closeout_summary.md) ／ [旧工程A](m10_wind_hills_audit.md) ／ [旧B01](m10_b01_entrance_watercolor_audit.md)

今回の参考PNGと登録済み原本のSHA-256は `22fc79c56c0cb5fca427fda0973f5b33780c217e70c04cffcbaab0246755d476` で一致。比較ページもこの原本を直接参照する。[参考画像](../assets/source/concepts/wind_hills_scale_reference.png)

作業前後のSHA-256照合では、素材台帳を除く既存のシーン・スクリプト・Resource・テスト・アセット・`project.godot` の536ファイルがすべて一致した。工程00の旧入口実行は2項目合格。[工程00検証結果](measurements/m10_rebuild_baseline_results.json)

## 6領域の読み取りと仮配置

単一の絵から奥行きやレンズを一意に復元することはできない。門と人物の見かけの寸法を手前の基準にし、山頂の位置と左右の谷の広がりに合わせて奥行きを仮置きした。下表は**実ワールド座標（X, Y, Z／m）**。画面座標は左上を(0%,0%)とする。画像目安は目視、Godot値は固定カメラから実マーカーを投影した値。

|領域|参考画像から読んだ形・奥行き|主な仮座標 m|画像上の目安 → Godot|
|---|---|---|---|
|A 門・主人公|手前やや左の低い尾根。門の向こうに街道が続き、人物は門の開口より小さい|門 `(-11.66, 0, 0)`、人物 `(-11.66, 0.04, 1.50)`|門の地面 `(40%,85%) → (40.0%,85.0%)`|
|B 街道・階段|入口で左へ振り、中腹へ右上がりに登る。曲がりごとに水平な棚と短い石段が見える|中腹 `(7.50, 6.53, -67.50)`、上段 `(30.75, 23.93, -133.50)`|中腹 `(53%,48%) → (53.5%,47.5%)`|
|C 左の見晴らし台|谷に張り出した独立した高台。手前の分岐と背後の尾根で主山につながる|`(-85.50, 20.25, -86.25)`|`(14%,34%) → (14.0%,33.8%)`|
|D 川・橋|右手に切れ込む低い谷。主街道より下の水面を橋が横切る|橋中央 `(59.25, -15.30, -48.75)`、水面は同付近で `Y=-18.38`|`(80%,71%) → (80.0%,71.0%)`|
|E 山頂遺跡|上部中央のやや右。広場に複数の柱と高さの異なるアーチが並ぶ|広場 `(36.83, 45.00, -180.00)`|広場 `(60%,15%) → (60.0%,14.9%)`、最高アーチ頂部 `(61.0%,5.8%)`|
|F 遠景|左奥に連続アーチ、右奥に塔。山頂より奥の山稜に置く|高架の左端 `(-198.75, 48.75, -390.00)`、右塔 `(322.50, 56.25, -487.50)`|左端 `(20.9%,14.2%)`、右塔の基部 `(88.9%,12.8%)`|

## 工程01　形状と縮尺

入口から山頂までの比高は45m。主地形の外接は330×322.5m。中央の裾野の上に、中心・幅・奥行き・縁の起伏が異なる段丘を配置した。街道には5か所の階段位置を横桟で示した。左の見晴らし台は折り返しのある支道で接続し、右の谷には川と橋の仮形状を置いた。遠景は輪郭と遺構の位置を示す単色面である。

|対象|仮寸法・扱い|
|---|---|
|主人公|既存48px原画像、カプセル1.8m、scale=1。比較画像で投影した1.8mは22.9px（参考人物は目視で約24px）|
|主街道|幅4.05m。始点から山頂まで制御点を直線で結んだ長さ249.86m。線分最大勾配約23°。曲線上の実歩行距離・勾配は工程02の対象|
|左支道／川支道|幅2.63m／2.85m。制御点折線は221.93m／151.14m。川支道の急な区間は工程02で歩行面を検討する|
|門|開口幅4.50m、高さ7.65m、輪郭の外側まで約8.66m|
|山頂|広場36.75×18m。中央アーチ外側まで約17.78m、開口幅9m|
|橋|仮橋面17.25×4.13m、水面との高低差約3.08m|
|入口操作|22.5×24mの仮床の内側で移動・ジャンプ・回転。操作範囲を出ると入口へ戻る。建物や全ルートの衝突は後続工程|

調整元は [layout.json](../resources/maps/wind_hills_rebuild/layout.json)。地形とレビュー用カメラの制作座標に `world_scale=0.75` を掛けると上表のm値になる。主人公と通常CameraRigは等倍。初回の地形寸法では人物の投影が17.1pxだったため、人物を基準にフィールドと比較カメラの距離をそろえて調整した。

## 実画面・一致点と残件

- [固定カメラ](images/m10_rebuild/comparison.png)と[参考画像](../assets/source/concepts/wind_hills_scale_reference.png)を同じ1672×941で比較した。門→中央道→上部のアーチの順に目を移せる。左の展望地と右の橋は主山の反対側に分かれ、中央街道より橋が低く見える。
- 初回の実画面では段丘が孤立した台状に見え、道が深く切れ込んでいた。広い裾野・道肩を持たせ、左の道の曲がりを増やした。遠景の面の向きと遺構の土台も修正した。
- **未一致**。参考画像よりも中央の草面が広く滑らかで、段丘の縁と左右の崖は単純。右谷は絵より細い水路として見える。山頂は正面主体の疎なアーチ列で、参考の奥へ連なる壁や柱ほど幅と厚みを感じにくい。遠景の山稜は粗く、空には雲や大気の階調がない。これらが構図に及ぼす印象をユーザーが確認する。
- [俯瞰画像](images/m10_rebuild/overview.png)では丘・谷・支道の接続と広場の面積を確認できる。[入口プレイ画面](images/m10_rebuild/entrance_play.png)は通常カメラでの門と主人公の縮尺確認用。水彩材質・小物・敵・最終カメラ調整は工程表の後続項目。

## F6と撮影条件

|目的|Godotで開いてF6を押すシーン|条件|
|---|---|---|
|最初に確認する固定構図|[comparison.tscn](../scenes/maps/wind_hills_rebuild/comparison.tscn)|透視、位置 `(0,43.5,63.75)`、Pitch −17°、Yaw 0°、縦FOV 48°、near 0.1m／far 2400m。記録画像と同じ縦横比は約16:9|
|丘と谷を上から確認|[overview.tscn](../scenes/maps/wind_hills_rebuild/overview.tscn)|正投影318.75m、位置 `(202.5,255,191.25)`、注視点 `(7.5,6,-93.75)`|
|入口のサイズと操作|[playground.tscn](../scenes/maps/wind_hills_rebuild/playground.tscn)|既存方式B、距離10m・Pitch −45°。WASD／矢印、Space、Q/E。F8で終了|
|地形単体の編集確認|[field.tscn](../scenes/maps/wind_hills_rebuild/field.tscn)|シーンを開くと仮地形を生成する。JSON変更後は開き直す|

比較カメラの位置・回転・FOV・投影方式・正投影サイズはJSONの `comparison_camera` で変更できる。`ReviewCamera` の `Apply Layout Preset` をオフにすればInspectorの値を使う。撮影時は固定プリセットを使用した。通常プレイと固定比較の視点は独立している。

## 自動検証と再現

Godot 4.7.2.stable.official.ed1daf0bf／Windows／GTX 1080・OpenGL 3.3 Compatibility。実描画36項目、描画を省いた再確認33項目が合格。比較と俯瞰の切替、6領域の投影、主要4地点の画像上の目安、地形484区画、実Playerの入口接地・移動・ジャンプ・着地、カメラ回転、操作範囲外から入口への復帰を検査した。画面上の数値と目視による造形評価は別々に記録した。[実描画結果](measurements/m10_rebuild_stage01.json) ／ [ヘッドレス結果](measurements/m10_rebuild_stage01_headless.json)

既存mainの移動、ジャンプ、方式Bカメラ、遮蔽・影・復元、M09起動時の敵と操作切替の5試験が合格。新マップの実描画での生成は比較約9.58秒、俯瞰約9.02秒、入口約9.27秒。長時間性能・全ルート往復・複数敵性能は未実行。旧A／B01の初回停止は既存監査の既知事項として引き継ぐ。[回帰結果](measurements/m10_rebuild_regression_results.json)

最終の新マップ検証にスクリプト・パース・シェーダーコンパイルエラーはなかった。環境側では証明書取得・GLESキャッシュ書込・エディター設定保存のエラーを観測した。既存M03とM09の終了時はそれぞれObjectDB 4件／Resource 2件、16件／8件の解放ログがある。既存M04の閉鎖箱におけるカメラ描画抑止警告は試験で想定する結果。

プロジェクト直下のPowerShellで再現できる。

```powershell
./tools/validate_m10_rebuild.ps1 -Mode baseline
./tools/validate_m10_rebuild.ps1 -Mode capture
./tools/validate_m10_rebuild.ps1 -Mode smoke
./tools/validate_m10_rebuild.ps1 -Mode regression
```

## 変更ファイルと引き継ぎ

|用途|ファイル|
|---|---|
|マップ・入口・比較・俯瞰・共通照明|`scenes/maps/wind_hills_rebuild/{field,playground,comparison,overview,lighting}.tscn`|
|生成・入口接続・比較カメラ|`scripts/maps/wind_hills_rebuild/{field,playground,review_camera}.gd` と対応UID|
|仮配置・縮尺|`resources/maps/wind_hills_rebuild/layout.json`|
|検証|`tests/m10_rebuild_composition.gd` とUID、`tools/validate_m10_rebuild.ps1`|
|証跡・出典|`docs/images/m10_rebuild/` の4画像、`docs/measurements/m10_rebuild_*.json`、`docs/briefs/m10_rebuild_nine_stages.md`、比較HTML、本監査|
|制作・進捗記録|`README.md`、`AGENTS.md`、`assets/ASSET_REGISTER.csv`、`docs/08_DECISIONS.md`、仕様10・計画11・試験12、`docs/DEVELOPMENT_STATUS.md`|

**次の判断は工程01の構図確認。** 門から山頂までの道、見晴らし台の張り出し、橋の見え方、山頂遺跡の大きさを固定画像で確認する。修正希望は工程01内で反映する。承認後の工程02で3ルートの歩行面、衝突、崖からの復帰を扱う。M10全体と旧工程A／B01の受入は個別に管理する。
