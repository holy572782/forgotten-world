# M09 戦闘効果音・敵の被弾演出（2026-10-26、ADR-029）

状態：M09追加改善。自動検査結果は下記へ集約し、音の聴感・見た目・F5操作はユーザー確認待ち。M08試作範囲完了、M09検証待ち、M10別指示待ちを維持する。

## 現在の音声割当とピッチ（2026-10-26、ADR-030）

初回ADR-029の合成WAVから、ユーザー指定の3音へ変更。今回の開始HEADは `17ef4c01bc0e35c9bb76f1cacc25c344abba125e`。既存の未追跡 `RPGツクールMZのaudio/` があり、音声3本を確認・無加工コピーした。元の音声と以前の合成WAVは保持し、新しい音声管理機構は追加しない。

| 用途 | 元の実在ファイル | 現在の再生ファイル |
|---|---|---|
| 片手剣の風切り | RPGツクールMZのaudio/se/Evasion1.ogg | assets/audio/sfx/mz_evasion1.ogg |
| 片手剣の実命中 | RPGツクールMZのaudio/se/Slash1.ogg | assets/audio/sfx/mz_slash1.ogg |
| 防御成功 | RPGツクールMZのaudio/se/Sword2.ogg | assets/audio/sfx/mz_sword2.ogg |

コピー前後のSHA256はそれぞれ `d6f1e181f2f9bdec9cd45c929403beeb95a2b826f75b324a5835cee9fb36789f`、`b6316b49764cd325307659284cd6c15171ddf311a3fc32827b1899af112421e2`、`949407c00fa6115e5db869923152940a562ed0b6717d39c980f70b5153451591` で一致する。3音ともループなし。

風切り・命中の再生位置は既存処理のまま。防御成功音は未実装だったため、既存filter_damageのGuard＋攻撃元の有効な方向・正面角度判定が成立した分岐にguard_succeeded通知だけを追加し、CombatFeedback内のAudioStreamPlayerで再生する。右／Iを押すだけでは鳴らず、実被弾で正面Guardが成立した場合に1回鳴る。0まで軽減する場合も成立音は鳴る。背面・不明・同位置の攻撃元、0／不正ダメージ、Guard外では鳴らない。ダメージ計算・防御性能は変更しない。

Swing Pitch Scale／Hit Pitch Scaleは武器Feedback、Block Success Sound／Volume Db／Pitch Scaleは既存Defense Settingsに追加。すべてのピッチは初期1.0、0.5〜2.0、刻み0.01。既存AudioStreamPlayerのpitch_scaleを再生直前に設定し、音量とは独立する。ピッチは音の高さと再生速度を変えるが、攻撃・連撃・帰還・フラッシュ／火花の時間は変えない。

今回の変更ファイル：上記Ogg3本と.import、scripts/combat/combat_feedback_settings.gd／defense_settings.gd、resources/combat_feedback.tres／defense_settings.tres、scripts/effects/combat_feedback.gd、scripts/player/target_dash.gd（通知2行のみ）、tests/combat_audio_pitch.gdとUID、tests/combat_feedback.gd（保存時の型確認をWAV専用からAudioStreamへ変更）、08／10／12／14・README・DEVELOPMENT_STATUS・ASSET_REGISTER・本書。

検査：tests/combat_audio_pitch.gdを実描画60／30上限と別プロセス--reloadで実行し、正しい3音の再生・3連撃・各ピッチ0.8／1.2・音量独立・防御姿勢のみの無音・正面／背面／不明／完全軽減・Inspectorの範囲と保存を確認した。**8種類11条件すべてPASS・終了0**。新検査は実描画60／30で259／164 assertions、再読込4。既存combat_feedbackは633／再読込2、M00入力・M07連撃・M08防御・方向クリック1470・敵戦闘56・実起動もPASS。初回の結果は下記ADR-029の履歴として保持する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/combat_audio_pitch.gd
& $godotExe --path . --script tests/combat_audio_pitch.gd -- --fps30
& $godotExe --headless --path . --script tests/combat_audio_pitch.gd -- --reload
```

関連検査はcombat_feedback（通常／--reload）、m00_input_map、m07_chain、m08_defense、directional_click、m09_enemy_combat、m09_startupを同様の--scriptで実行。import終了0、採用ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。環境のログ・証明書・エディター設定保存ERRORは区別する。ログ・集計はGit除外の `.godot/m09_audio_pitch_*`。静的照合で、TargetDashは成立通知2行のみ、InputMap・HP・Motion・シーン・武器数値・敵AI・フラッシュ／火花・fixtureはHEAD差分なし。git diff --check合格。検証用Godotは終了済み。

F5：F8で停止→Inspectorで変更して保存→F5。左／Jで風切りEvasion1と実命中Slash1、3連撃を確認する。「静止敵」で右／Iを保持してもSword2は鳴らず、「近接敵」の正面攻撃を実際に防いだときだけ鳴ることを確認。各ピッチを他は1.0のまま個別に0.8→1.2へ変更し、低く遅い音→高く速い音を比較する。Resourceを保存しGodotを再起動して値が残ることを確認し、好みの値へ戻す。ユーザーの聴感とF5受入は待ち。新工程・自動commit／pushなし。

## 開始時の確認と変更範囲（ADR-029の履歴）

main、HEAD `c0766cc4ba6b05a06002008dccf798204df4eed3`、作業ツリーに変更なし。AGENTS、進捗・08／10／11／12／14、既存武器・タイムライン・斬撃・HP・敵・描画を照合した。既存の音声再生システムはなく、敵は画像ではなく仮カプセルMesh。今回はその見た目・AI・命中処理を維持して演出を足す。

| 要素 | 接続先と開始時刻 |
|---|---|
| 風切り音 | Player/CombatFeedbackが既存attack_acceptedを受け、その一振りの本体アニメーションの加重コマ進行を監視。既定は2コマ目開始で1回 |
| 命中音 | HealthComponentが実際にHPを減らした直後のdamage_appliedを敵HitFeedbackが受信。攻撃開始・旧hit通知だけでは鳴らさない |
| フラッシュ | 同じHP減少通知でBodyの材質へ一時overlayを重ねる。全回復・寿命・非表示・破棄時に元のoverlay参照を復元 |
| 火花 | 同じ通知で敵のカメラ側表面に独立したNode3Dを生成。通常深度を使い、寿命でqueue_free |

TargetDash、AttackHitbox相当の既存命中形状、ダメージ式、攻撃／連撃／撃破後待機／帰還の各処理には変更なし。既存の左攻撃・右防御・J／I／L・Q/E・武器Motion・斬撃は共用する。画面揺れ・ヒットストップ・ノックバック・バランス調整は追加しない。

## 初回の仮音声と制作方法（ADR-029の履歴・現在は割当なし）

- `assets/audio/sfx/sword_swing.wav`：0.16秒、mono、44.1kHz／PCM16。ピーク0.65、RMS約0.14231、SHA256 `354b276f8886e568470121beac7882dbaee79191ff6fdd12255abe9e1dfaee8b`。
- `assets/audio/sfx/sword_hit.wav`：0.12秒、mono、44.1kHz／PCM16。ピーク0.70、RMS約0.10423、SHA256 `29c743c2c79b86ce51ca0bd58e32d5756d8dae9a6564f53a3cc8902dfb690321`。
- `tools/audio/generate_combat_sfx.py`：Python標準ライブラリだけで再生成。固定seedのノイズを帯域制限し包絡を掛け、命中は短く減衰する185Hz／920Hz成分を少量追加。DC除去・両端ゼロ・クリップなしを数値検査する。外部録音・サンプル・音声モデルは使用しない。
- WAV本体を同梱するのでゲーム実行時にPythonは不要。Godotではループなし・非圧縮で読み込む。風切りと命中は別AudioStreamPlayer、Masterバス。命中は最大4声で、複数の実ダメージを扱う。1つのHP減少通知を複数経路で再生しない。聴感・最終音量は未受入。
- 4演出を `assets/ASSET_REGISTER.csv` へオリジナルの仮素材として登録。プロジェクトの正式ライセンスは未決定のままとする。

## Inspectorの調整場所と差し替え

`main → Player → TargetDash → Equipped Weapon → Feedback`。FileSystemの `resources/combat_feedback.tres` を開いても同じ設定。共有設定を武器別に変えるときはMake Uniqueまたは別名Resourceとして保存して、その武器のFeedbackへ割り当てる。

防御は `main → Player → TargetDash → Defense → Block success sound` または `resources/defense_settings.tres`。音量・ピッチを別々に変更してResourceを保存する。いずれも実行中のRemoteだけの変更ではなく、停止中のLocal／FileSystem側で保存する。

| プロパティ | 初期値 | 単位・範囲 |
|---|---|---|
| Swing Sound / Hit Sound | Evasion1 / Slash1 | AudioStream。nullでその音を無効化 |
| Swing Volume Db | -9 | dB、-60〜0 |
| Swing Pitch Scale | 1.0 | 0.5〜2.0、刻み0.01 |
| Hit Volume Db | -12 | dB、-60〜0 |
| Hit Pitch Scale | 1.0 | 0.5〜2.0、刻み0.01 |
| Block Success Sound | Sword2 | Defense SettingsのAudioStream。nullで無効化 |
| Block Success Volume Db | -12 | dB、-60〜0 |
| Block Success Pitch Scale | 1.0 | 0.5〜2.0、刻み0.01 |
| Swing Frame | 1 | 0始まりのコマ番号、0〜63。既定1は2コマ目 |
| Swing Frame Percent | 0 | 選んだコマ内の％、0〜100 |
| Flash Duration | 0.10 | 秒、0.01〜1 |
| Flash Strength | 0.55 | 0〜1。0で色の重なりを無効化 |
| Flash Color | (1, 0.96, 0.82) | 淡いクリーム色 |
| Spark Scene | scenes/effects/hit_sparks.tscn | PackedScene。nullで火花を無効化 |
| Spark Duration | 0.14 | 秒、0.01〜1 |
| Spark Count | 5 | 個、0〜12 |
| Spark Size Pixels | 2 | 相対ピクセル、1〜4 |
| Spark Spread | 0.18 | m、0〜0.5 |
| Pixel Size | 0.0375 | m/相対ピクセル、0.005〜0.1。主人公の初期pixel_sizeと同じ |

敵別には敵シーンの `HitFeedback → Override Settings` を設定する。命中側の音・フラッシュ・火花だけを上書きし、風切りは武器側を使う。`Visual Paths`はマークや予兆を含まないBodyを指定、`Impact Offset`は既定(0,0.75,0)。火花の起点はカメラからこの点へのレイと敵コリジョンの表面で求め、0.03mだけカメラ側へ寄せる。手前が壁・別の敵ならそれを越えて移さない。物理表面を得られない表示の補正用に `Surface Radius` 0.42m（0〜2）を使う。

火花の交換シーンはNode3Dをルートとし、必要ならconfigure(settings)を実装して設定を受け取る。独立した寿命を持たせ、ダメージ処理は追加しない。Sprite3Dへの将来の表示変更では透過マスクと既存shaderとの実描画確認が必要。今回は実装済みカプセルと既存overlayの保持を検査する。

## 同期・終了と描画

攻撃全体の時計は既存のAnimatedSprite3Dのみ。独立した攻撃タイマーは作らず、frame_time_ratiosを反映した進行から風切り位置を計算する。フレーム通知・進行の監視・同時刻のダメージ通知でサンプルし、攻撃IDごとのフラグで1回に制限する。命中コマは既存Motionの設定をそのまま使い、風切りと命中を別々に設定できる。

HP通知は値の更新後、既存hp_changed／depletedより前なので、致死ダメージも通知できる。致死ダメージのflashも開始するが、死亡処理を遅延しない。表示が残る敵では短いflashを完了し、消滅・非表示になる敵ではすぐに復元する。共有HPの複数部位では既存の1振り1HP所有者の重複除外を使う。音と火花はHPが減った通知だけで発生する。

フラッシュはmaterial_override・既存画像・AIのscaleを変更しない。既存overlayがあれば私有複製へflashパスを追加し、元の共有材質へ書き込まない。再被弾は表示時間を更新。火花は完全な四角形・段階的な位置・落ち着いた3色で、Emission・ぼかし・Glowなし。通常深度と敵表面の起点を使い、地面や壁を無視して描かない。敵移動・死亡後は発生地点で短く終わる。生成フレームのdeltaで発生前の時間を消費せず、最初の描画を確保してから寿命を進める。

## 追加・変更ファイル

- 音声：`assets/audio/sfx/sword_swing.wav`、`sword_hit.wav`と各`.import`。生成元：`tools/audio/generate_combat_sfx.py`。
- 設定：`scripts/combat/combat_feedback_settings.gd`、`resources/combat_feedback.tres`、`scripts/combat/weapon_data.gd`（Feedback参照だけ追加）。
- 通知：`scripts/combat/health_component.gd`（damage_applied通知だけ追加）。
- 表示：`scripts/effects/combat_feedback.gd`、`enemy_hit_feedback.gd`、`hit_sparks.gd`、`scenes/effects/hit_sparks.tscn`、`assets/shaders/enemy_hit_flash.gdshader`。
- 接続：`scenes/main.tscn`、`scenes/enemies/training_enemy.tscn`、`practice_enemy.tscn`（演出ノードのみ追加）。新しいGDScript／shaderのGodot生成UIDも同梱。
- 検査：`tests/combat_feedback.gd`とUID。既存テストの期待値やfixtureは変更しない。
- 記録：ASSET_REGISTER、README、08／10／12／14、DEVELOPMENT_STATUS、本書。

## 自動確認

Godot4.7.2／Windows／Compatibility・GTX1080、物理60Hz。検証用Godotは逐次実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --import --quit
& $godotExe --path . --script tests/combat_feedback.gd -- --capture
& $godotExe --path . --script tests/combat_feedback.gd -- --fps30
& $godotExe --headless --path . --script tests/combat_feedback.gd -- --reload
```

新検査は実アニメーション・物理・HPとAudioStreamPlayer.playingを観測する。攻撃時間とコマ比率の変更、踏み込み無音、遅い命中との前後関係、実HP減少・0軽減、壁による開始拒否／命中前中断、防御中断、3連撃、途中撃破・無表示スロット、共有HP、連続被弾・既存材質復元、4Yaw、敵死亡／破棄と粒の解放、Inspector・不正値・保存／別プロセス再読込を検査する。

関連回帰：m00_input_map、m05_hud、m07_chain、m08_defense、directional_click、in_place_attack、defeat_return_timing、return_travel、attack_motion、weapon_sweep、weapon_effects、m09_enemy_combat、m09_enemy_dash、m09_startup。再実行は上記と同様に `--script tests/<名前>.gd`。

最終結果：**15種類17条件がすべてPASS・終了0**（新規1種類の60／30／再読込3条件＋関連14種類）。音声のオフライン数値検査は別枠。

| 検査 | 最終結果 |
|---|---|
| combat_feedback・実描画60／30fps上限 | 593／365 assertions、PASS。表示画像で薄いflashと小さな白／黄の粒を確認 |
| combat_feedback・別プロセス--reload | 2 assertions、PASS。保存値・AudioStreamWAV・PackedSceneが再読込可能 |
| m00_input_map／m05_hud／m07_chain／m08_defense | PASS。14アクション・32割当、HP／HUD・連撃・防御／方向帰還を維持 |
| directional_click／in_place_attack／defeat_return_timing／return_travel／attack_motion | 1470／3276／1869／6010／1684 assertions、PASS。入力・近距離省略・撃破待機・帰還・コマ同期を維持 |
| weapon_sweep／weapon_effects／m09_enemy_combat／m09_enemy_dash／m09_startup | 226／2246／56／171 assertionsと実起動検査、PASS。共有HP・斬撃・敵AIと新操作を維持 |
| 音声2本 | 生成元からの別ディレクトリ再生成でSHA256が一致。PCM16／mono／44.1kHz、両端ゼロ、クリップなし |

途中のPackedScene生成結果の型推論エラーはNode明示型へ修正し、影響した最後の5本を再実行した。不正値の検査はfloatの近似比較へ修正。敵内部に火花が埋まらないよう接触点を物理表面で取得し、発生前のdeltaで寿命を消費しないよう最初の描画を確保した。失敗試行は最終合格に含めず、60／30と再読込を修正後に再実行している。

最終の解析・採用ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。ユーザーログ・証明書・エディター設定・GLESキャッシュ保存の環境ERRORは残るが、実装エラーとは区別する。ログ・画像・音声メトリクス・集計はGit除外の `.godot/m09_feedback_*`、最終集計は `.godot/m09_feedback_final_results.json`。検証用Godotは終了済み。

静的照合：TargetDash／PlayerController／PlayerSprite、敵AI、InputMap、既存の武器数値・Motion・画像／斬撃・地形・fixtureはHEAD差分なし。Healthは通知追加、WeaponDataは設定参照追加、シーンは演出接続だけ。git diff --check合格。最終のユーザーF5操作・聴感・演出の受入・実機パッド・長時間性能・任意の複雑地形は未実行。

## F5での手動確認（ユーザー確認待ち）

1. F8→F5、必要なら「静止敵」。金色マークが出るまで近づき、左クリックまたはJで攻撃する。踏み込み中は風切り音がなく、実際の剣振りで「シュッ」、HP減少時に「ザシュッ」が鳴る。
2. 3連撃とL／別敵クリックによる対象切替を行う。各剣振り・各命中の音が1回で、不自然な重複や大音量がない。
3. 壁・崖・範囲外・対象なしでは攻撃が成立せず、命中音・フラッシュ・火花が出ない。攻撃中に右／Iで防御へ切り替え、遅れて演出が出ない。
4. 敵が短く淡いクリーム色になり、元の色へ戻る。連続被弾・撃破・試験モード切替でも色が残らず、死亡処理が進む。
5. 命中箇所付近に小さな白／黄／黄土色の四角い火花が出て、約0.14秒で消える。敵や主人公を大きく隠さず、地面に埋まったり壁越しに見えたりしない。
6. Q／Eの4方向と移動しながらの攻撃で位置・剣・既存斬撃の同期を確認。近距離は踏み込み省略、遠距離は踏み込み→攻撃→帰還になる。
7. 途中撃破後の残り時間が静かな待機となり、空振り音・命中演出が増えない。右防御の保持／解除・方向帰還・帰還後のWASD／矢印・Space・J／I／Lが正常。
8. Feedbackの音量・flash・sparkを1項目ずつ調整して保存→F5。武器Motionの時間／コマ配分を変更した場合も開始位置が追従することを確認し、試した値は好みに合わせて戻す。

仮音の聴感と演出の最終サイズ・色はユーザー受入待ち。音量などの仮値を正式バランスとして固定しない。以前の攻撃不可報告・実機パッド等の未確認事項も継続する。コミット・Pushは未実行。
