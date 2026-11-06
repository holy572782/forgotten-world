# M10-B01：入口地面の水彩風試作

2026-11-06／ADR-063。入口地面の試作実装・自動検証済み、ユーザーの見た目・操作感確認待ち。工程Aの個別未確認は保持し、M10全体／工程B全体を完了にしない。

## 目的・開始時照合

ユーザー提供の[制作指示](briefs/m10_b01_entrance_watercolor_ground.md)に基づき、工程Bのうち入口の草地と石板上面だけを対象にした。開始時HEAD `f1676ab`、Git差分なし。前回の工程Aと監査・進捗は実物と一致した。今回を入口地面への明示着手指示として扱い、工程A全項目の合格や、工程B全体の開始へ拡張していない。GitHub Issueは新規作成していない。

対象はA `(0,0,12)`→門B→最初の曲がり `(14,1,-22)`→C `(0,2,-45)`。本体X=-20〜20／Z=-50〜20m、外側の最大調整帯X=-24〜24／Z=-54〜24m内で、草の色面・路面判定・傾斜を使って選択する。門・柱・階段・崖・橋・他区画・遠景の材質は変更していない。地形高さ、道幅、形、衝突、Player、操作・戦闘、カメラ、照明・Environmentも維持した。

主な変更・追加ファイル：

- `scripts/maps/wind_hills/wind_hills.gd`：入口限定の表示surface・UV・石板上面を接続。
- `scripts/maps/wind_hills/entrance_ground_settings.gd`、`resources/maps/wind_hills/entrance_ground.tres`：専用調整項目。
- `scripts/maps/wind_hills/entrance_ground_materials.gd`：不透明な混合、連続UV、石面の参照。
- `assets/textures/maps/wind_hills/entrance/`：提供PNG2枚とimport設定。`assets/source/maps/wind_hills/entrance/`に生成指示・メモ。
- `tests/m10_b01_entrance.gd`、`tools/validate_m10_b01.ps1`：同条件比較・幾何・歩行・フェード・性能の再現。
- 本監査、制作指示の保存、比較画像・計測JSON、素材台帳、AGENTS／README／仕様10・11・12／ADR／DEVELOPMENT_STATUSを更新。

## 実装と採用した試作値

|項目|試作値／方法|
|---|---|
|草の反復寸法|1枚4×4m。3／4／6mを通常カメラの実画像で比較|
|草の混合率|55%。既存の頂点色と提供画像をMix。元の黄緑を画像へそのまま乗算しない|
|石面の混合率|80%。既存の0.80×1.12m石板を保持し、上面だけ画像内の石の内側をUVで参照|
|石の側面|従来の石色材質。画像全体や石畳の目地を箱側面へ貼らない|
|背景画像のimport|元PNG1254×1254を無加工コピー、lossless、MipMapあり、サイズ制限なし|
|フィルタ|地面専用Linear＋MipMap＋Anisotropic。主人公のNearestは変更なし|
|材質|StandardMaterial3D、粗さ0.95、Lambert、Specular disabledを継承。基本不透明、独自Shader／next_pass／透明な重ね床なし|

設定は `resources/maps/wind_hills/entrance_ground.tres` のEnabled／Grass Repeat Meters／Grass Strength／Paving Strength／Region Min・Max／Feather Meters、石面の4つのUV領域に集約した。今回の値は試作採用であり、ユーザーの美術受入ではない。

`wind_hills.gd`への追加は、専用設定とhelperの接続、対象区画の表示surface分割とUV、石板上面の表示UVだけ。`height_at()`、`route_sample()`、layout.json、衝突を作る元のSurfaceToolの頂点処理は変更していない。表示用の草と従来面を分ける一方、Colliderは従来の全三角形から生成する。新しい床やColliderは増やさない。

草のUV2はワールドX/Z座標、材質のUV2 Scaleで1/4にする。20m区画ごとにUV原点を戻さない。UV1は境界の混合率だけを表し、コード由来の1次元GradientTextureをmaskに使う。画像に手を加えず、不透明な1surfaceの中で元色へ徐々に戻す。境界は波形と4mの幅で崩し、道路の肩と急斜面は元色側へ戻す。既存の街道・崖判定を優先し、法線Y<0.90の急斜面には草画像を付けない。

この構成では、元色をベースに画像をMixするため、画像色×頂点色×albedoの二重乗算を避けられる。StandardMaterialのdetail imageにはUV2、detail maskにはUV1を使う[Godotの実装](https://github.com/godotengine/godot/blob/master/scene/resources/material.cpp)を参照し、使用中のGodot 4.7.2でも実描画・フェードを確認した。

石板の上面は提供画像の次の4領域を使う（正規化UV、左上X/Yと幅/高さ）。

```text
(0.25, 0.24, 0.19, 0.10)
(0.36, 0.40, 0.20, 0.11)
(0.18, 0.60, 0.20, 0.10)
(0.70, 0.80, 0.19, 0.12)
```

各領域は画像全体の約1.9〜2.3%。大きな目地を避けた石面を、位置から決まる4パターンで割り当てる。一枚の板の中へ路面全体を縮小していない。BoxMeshと同じ面・法線・変換を使うArrayMeshに上面／側面の2surfaceを作り、ノード数は増やさない。ArrayMeshの平面surfaceの自動AABBには約10µmの膨張があるため、描画用custom AABBを元BoxMeshと同じに指定した。面座標と描画境界は元と一致する。

変更は地形195区画のうち15区画、塗装対象5137三角形、石板162枚。その他180区画の表示メッシュは変更前と一致。実際の非ゼロmask頂点の外接範囲はX=-22〜22／Z=-52〜22mで、最大調整帯の内側。これは外接範囲であり、長方形全体を塗ったという意味ではない。

## 変更前後の画像

すべて通常カメラ-45度／10m、Yaw=0、1152×720、同じPlayer位置・照明・Environment。同じ場所へreset_motionし、接地と追従を安定させて撮影。カメラの数値差は0.1mm未満で検査した。比較カメラは今回使用していない。

|場所|変更前|変更後|
|---|---|---|
|開始地点A|[前](images/m10_b01/before_start.png)|[後](images/m10_b01/after_start.png)|
|門の下|[前](images/m10_b01/before_gate.png)|[後](images/m10_b01/after_gate.png)|
|門の先|[前](images/m10_b01/before_beyond_gate.png)|[後](images/m10_b01/after_beyond_gate.png)|
|最初の曲がり|[前](images/m10_b01/before_bend.png)|[後](images/m10_b01/after_bend.png)|
|街道広場C|[前](images/m10_b01/before_plaza_c.png)|[後](images/m10_b01/after_plaza_c.png)|

|草のスケール|開始地点|曲がり|
|---|---|---|
|3m|[画像](images/m10_b01/after_start_grass_3m.png)|[画像](images/m10_b01/after_bend_grass_3m.png)|
|4m・今回の値|[画像](images/m10_b01/after_start_grass_4m.png)|[画像](images/m10_b01/after_bend_grass_4m.png)|
|6m|[画像](images/m10_b01/after_start_grass_6m.png)|[画像](images/m10_b01/after_bend_grass_6m.png)|

4mは通常画面で草の色面を残しながら、筆跡が主人公より大きな独立物体に見えない中間値とした。6mは大きな色ムラが強く、3mは細かな反復が増える。最初の草78%／石100%では色と石面の白さが強かったため、照明を触らず55%／80%へ抑えた。

草の元画像は完全シームレスを保証しない。4m周期の色ムラの繰り返しは認識できる。20mのUVリセットはなく、入口帯の外縁は元色へ混ざるが、繰り返しや土色との境目の美術的な評価はユーザー確認待ち。原画像を補修・再生成したとは扱わない。

[東の調整帯](images/m10_b01/after_east_edge.png)／[西の調整帯](images/m10_b01/after_west_edge.png)／[X=10mの区画境界](images/m10_b01/after_chunk_seam.png)。比較画像21枚と[通常60FPS起動の入口プレビュー](images/m10_b01/after_final_entrance.png)を目視し、主人公の輪郭・石面・未変更面への移行を確認した。元の1m三角形による土と草の角張った輪郭は残るため、今回で地形の全ての角張りを仕上げたとは扱わない。

[2surfaceを0.3へフェードする制御確認](images/m10_b01/after_fade_030.png)／[復元後](images/m10_b01/after_fade_restored.png)。この2枚は材質互換性のために既存Faderを直接適用した制御試験で、通常プレイの自動判定ではない。1つの20m区画だけが透ける既存の方式と、M04の影代理Meshを維持する。画像内HUDのFPS値はスクリーンショット保存や固定フレーム検査の影響を含み、性能値として使わない。

## 検証

変更前659項目、変更後の初回検査901項目が合格・終了0。実Player／HUD／TargetDashを有効にした実行シーンで、A→B→曲がり→Cの往復、門・曲がりのQ/E回転、ジャンプ・着地・停止と、複数surfaceのフェード／影／材質復元を確認した。草画像は15区画の対象surfaceだけにあり、石板上面は画像全体の3%未満のUV、側面は元材質という条件も検査した。

全195区画について表示三角形と元の衝突三角形の一致を確認し、変更前後の衝突全三角形のハッシュ、入口外表示メッシュ、石板全1125部品の変換・描画境界ハッシュが一致した。TerrainのBody数195、RoadDetailsの部品数1125は前後で同じ。形・衝突が同じことと、UV・材質が異なることを分けて検証している。

初回の比較で、固定フレームと実時計実行のカメラ行列に数十µmの差が出たため、同一条件の判定に0.1mmの数値誤差を許容した。Playerと通常カメラの距離・ピッチ・Yawは同じ。石板は面座標が完全一致し、AABBの差は上記の表示境界の扱いで解決した。

最終の固定フレーム画像・材質検査876項目、実描画30FPS 670項目、M10歩行／復帰111項目とM04フェードはPASS・終了0。門・曲がりだけでなく、路外の草地`(6,0,10)`でもジャンプ・着地・移動停止・再移動を確認した。F5の既存mainも60フレーム起動・終了0、共有コード／ResourceとsceneのGit差分なし。既存main終了時にObjectDB 4件／Resource 2件の解放ログを観測し、今回の入口材質の修正対象には含めていない。M04の閉鎖箱のCamera safety警告は期待結果。実機でF5/F6キーを押した操作と、ユーザーの美術受入は未実行。

新しいプロセスでeditorから実行シーンを開き直し、`@tool`による5137三角形／162石板の適用をログで確認した。別プロセスの実描画・固定フレーム画像でも設定・元の幾何・対象面数が一致する。エディターGUIの見た目そのものの手動受入ではない。初回editor import／reloadにはAppDataの設定保存制限、実描画にはGLES3 `_save_to_cache: f.is_null()`の環境ERRORがある。SCRIPT／Parse／SHADER ERRORと区別し、ERRORなしと報告しない。

## 性能計測の条件と集計

Godot `4.7.2.stable.official.ed1daf0bf`、Windows、NVIDIA GeForce GTX 1080／ドライバー572.16、1152×720、Compatibility・OpenGL 3.3.0、上限60FPS／物理60Hz、敵0体。Player・HUD・TargetDash・CombatFeedback有効。既存カメラ・照明・空は変更なし。GPU時間・CPUモデル／メモリ使用量は未計測。

初回の入口〜C往復（約65m）、通過後2往復、門・曲がりの同じ回転を前後で記録した。起動時の地形生成待ちは前10.216秒／後11.597秒で、フレーム統計とは別。プロセス・実行条件によるばらつきを含み、起動時間の差を画像処理だけの因果と断定しない。

|歩行条件|前の平均FPS／p95／最大ms|後の平均FPS／p95／最大ms|
|---|---|---|
|初回1往復|59.921 / 17.030 / 54.560|59.834 / 16.956 / 96.573|
|通過後1往復目|59.937 / 17.041 / 51.730|59.915 / 16.928 / 56.013|
|通過後2往復目|59.951 / 16.838 / 44.139|59.902 / 16.899 / 60.515|
|門の360度回転|59.362 / 16.906 / 56.474|59.493 / 16.795 / 49.708|
|曲がりの360度回転|60.001 / 16.854 / 17.013|59.975 / 16.743 / 19.139|

この表の歩行・回転にはPNG保存は入っていない。定点の初回集計には直前のPNG圧縮時間が最初のフレームへ混入していたため、採用せず、画像保存なし・区間開始時の時計リセットで各地点約30秒を測り直した。最初のbefore／after JSONの定点欄はその旧集計であり、描画速度の比較に使わない。正式な定点比較は`*_stations.json`を使う。

正式な定点比較（各30秒、前→後。時間はms）：

|場所|平均FPS|Frame p95|Frame最大|Physics p95|Physics最大|
|---|---:|---:|---:|---:|---:|
|開始地点|60.004 → 60.002|17.215 → 16.977|18.165 → 19.039|2.009 → 2.896|2.050 → 2.925|
|門の下|60.002 → 60.002|16.815 → 17.006|18.807 → 19.013|0.852 → 1.285|1.050 → 1.300|
|門の先|60.002 → 60.002|17.304 → 17.319|18.888 → 19.027|3.253 → 3.137|3.288 → 3.237|
|曲がり|60.002 → 60.002|17.325 → 16.950|19.248 → 18.593|3.217 → 1.196|3.322 → 2.721|
|C|60.005 → 60.003|17.767 → 17.232|18.765 → 18.993|3.115 → 2.749|3.342 → 2.789|

この条件では平均FPSの低下は観測せず、Physics時間は増減がある。統計的な有意差や全フレーム60FPSの保証には拡張しない。定点ではPNG保存をしないため、前後の撮影画像とは別実行になるが、位置・通常カメラ・光源・設定は同じ。定点の新プロセス生成待ちは前11.631秒／後14.816秒で、起動待ちのばらつきは残る。

今回の変更前は過去に記録した約0.9秒の停止を再現しなかった。今回の材質の追加差分と過去の停止を混同せず、解消したと断定しない。シェーダー／ドライバーのキャッシュを消去した完全cold条件ではなく、確認用表示を先に実行した影響もある。変更後の初回最大96.573msは帰路の`(3.288,0.233,-5.061)`、変更前54.560msは往路の`(2.087,0.150,-3.279)`で、どちらも門の近く。今回の最大値の差は約42msだが、原因を材質だけに断定しない。通過後にも最大56〜61msの単発値が残る。長時間・多数敵・全マップ60FPSの保証ではない。

生データ：[初回・通過後の変更前](measurements/m10_b01_before.json)／[変更後](measurements/m10_b01_after.json)、[正式な定点・前](measurements/m10_b01_before_stations.json)／[後](measurements/m10_b01_after_stations.json)、[集計の採否・条件](measurements/m10_b01_measurement_notes.json)、[30FPS](measurements/m10_b01_after_30.json)、[M10歩行・復帰回帰](measurements/m10_b01_m10_regression.json)。旧工程Aの計測JSONは回帰後に元の内容へ戻して保持した。

30FPSでは短い入口往復と同じ回転・着地・フェード復元後の材質確認を実行し、空中観測tick0。往復の平均30.000FPS／Frame p95 33.721ms／最大45.840ms／Physics p95 1.728ms／最大2.916ms。各地点30秒の比較や、マップ全域の30FPS性能検査ではない。最終[固定フレーム画像検査](measurements/m10_b01_after_fast.json)は描画性能と区別する。通常起動の入口プレビューは `--after --capture --cover` で再生成でき、[カメラ・環境記録](measurements/m10_b01_cover.json)も保存した。

提供PNGはデスクトップ原本とSHA256一致：草 `71d024ce42d132eef1f0bb073cae69b1dea57b8f8541521e1100f98d9b23517e`、石 `4d53d214a0c38a16bcbee45274089095ff48f28ac8d6eeedd044b80620ddcc3f`。画像の修正・再生成は行っていない。生成指示と元メモも提供ファイルのコピーを保持した。

## 実行・調整と次の確認

通常は `scenes/maps/wind_hills/wind_hills_playground.tscn` をGodotで開いてF6。従来のF5は`scenes/main.tscn`のまま。今回専用の新しいプレイ操作は追加していない。設定を変えたらF8で停止し、シーンを閉じて開き直すか再読み込みしてからF6。`@tool`が一度生成したTerrainを毎フレーム再生成する方式にはしない。Enabled=falseで従来材質も比較できる。

```powershell
./tools/validate_m10_b01.ps1 -Mode before
./tools/validate_m10_b01.ps1 -Mode after
./tools/validate_m10_b01.ps1 -Mode before_stations
./tools/validate_m10_b01.ps1 -Mode after_stations
./tools/validate_m10_b01.ps1 -Mode views
./tools/validate_m10_b01.ps1 -Mode smoke30
./tools/validate_m10_b01.ps1 -Mode regression
```

性能のbefore／afterは同時実行せず順番に行う。beforeは専用設定のコピーを実行時にOFFにし、保存済みResourceは変更しない。viewsは固定フレームの比較画像生成で、性能測定ではない。ログは`.godot/m10_b01_*.log`（Git除外）、計測値は`docs/measurements/m10_b01_*`。最初のbeforeは変更前ソースそのもの、再現用beforeは現行ソースで材質OFFという違いがある。

次はユーザーが入口の草の色・柄密度、石面の見え方、外縁と道の境目、門の影と主人公の輪郭をF6で確認する。繰り返しが気になる場合は今回の入口内で調整する。草の揺れ・Fog・光源・環境音・敵・他区画の作り込みへ自動で進めない。

commit／pushは未実行。
