# M09 ジャンプ音・防御開始音（2026-10-26、ADR-031）

状態：M09追加改善。実装と自動確認の結果を記録し、F5操作・聴感はユーザー確認待ちとする。M08試作範囲完了・既存残件・M09検証待ち・M10別指示待ちを維持する。

## 開始時の確認

HEAD `0a24992e71b687e535998ea9c8a550dc5ca42341`、作業ツリーに変更なし。AGENTS、進捗・08／10／11／12／14とPlayerController、PlayerMovement、Defense Settings、InputMap、CombatFeedbackを照合。既存の音声再生・ピッチ機構を再利用する。実ジャンプ開始は_start_jump、防御は既存state_changedとguard_succeededがあり、入力や画像から開始を推測する必要はない。

## 使用素材

| 用途 | 元のファイル | ゲーム用の無加工コピー | 初期ピッチ |
|---|---|---|---:|
| 実ジャンプ | RPGツクールMZのaudio/se/Jump1.ogg | assets/audio/sfx/mz_jump1.ogg | 1.0 |
| 防御開始 | RPGツクールMZのaudio/se/Equip1.ogg | assets/audio/sfx/mz_equip1.ogg | 1.5 |

元ファイルとのSHA256一致を検査する。Jump1＝`c29d9ee125e74f5ba1506bb92807f437da218b1d559e2ed5c4b768e99e305906`、Equip1＝`040c06a3133f46edc439970249582d69ff2013d24708ed453829174fcddf2f55`。再エンコード・加工なし、ループなし。素材の出典はユーザー申告のRPGツクールMZ標準SEとして台帳へ記録し、利用条件の確認を推測しない。

## 再生契機と既存機能の保護

- ジャンプ：PlayerController._start_jumpが既存の初速・消費／バッファ状態を確定した直後のjump_started通知へ接続する。Space入力そのもの、空中の無効再押下、長押し、通常着地、踏み込み用Jump姿勢では再生しない。コヨーテと着地バッファの実ジャンプも共通処理から1回再生する。着地バッファから直ちに飛び直す場合は「着地音」ではなく新しいジャンプ開始音となる。
- 防御開始：既存state_changedの実遷移を観測し、前の状態がGuard以外で次がGuardの場合だけEquip1を1回再生する。押し続けている間や右／Iの同時保持、Guard→他状態の解除、無効入力、UIで消費された操作では再生しない。
- 防御成功：Sword2は既存のguard_succeededを使用する。実被弾を防いだときだけ鳴り、Guard開始時には鳴らない。逆に成功判定はGuardの再入場ではないのでEquip1を再生し直さない。
- 開始音は既存CombatFeedback内のAudioStreamPlayerへ接続。InputMap・防御状態機械・ジャンプ物理・攻撃／連撃／帰還・HP・敵AI・画像／flash／sparkは変更しない。PlayerControllerの変更は通知の宣言／発行2行だけ、TargetDashは変更しない。
- 空中で防御ボタンを保持して着地後に既存ルールでGuardが成立する場合は、その実際の開始時に鳴る。無効だった押下時刻に音を予約する処理は追加しない。

## Inspectorと保存・差し替え

ジャンプ：`main → Player → Movement → Jump sound`、またはFileSystemの `resources/player_movement.tres`。

防御開始：`main → Player → TargetDash → Defense → Guard start sound`、または `resources/defense_settings.tres`。その上のBlock success sound（Sword2）とは別項目。

| 設定 | 初期値 | 範囲 |
|---|---|---|
| Jump Sound | mz_jump1.ogg | AudioStream、交換可能、nullで無効化 |
| Jump Volume Db | -12 | -60〜0dB |
| Jump Pitch Scale | 1.0 | 0.5〜2.0、刻み0.01 |
| Guard Start Sound | mz_equip1.ogg | AudioStream、交換可能、nullで無効化 |
| Guard Start Volume Db | -12 | -60〜0dB |
| Guard Start Pitch Scale | 1.5 | 0.5〜2.0、刻み0.01 |

停止中のLocal／FileSystem側でResourceを編集して保存する。音量とピッチは独立。既存AudioStreamPlayer.pitch_scaleを再生時に反映するため、高さと再生速度は変わるが、ジャンプの高さ・時間や防御性能は変わらない。実行中のRemote側だけの値は保存されない。武器・敵等の新しい設定システムは追加しない。

## 変更ファイル

- 音声：assets/audio/sfx/mz_jump1.ogg、mz_equip1.oggと各.import。
- 設定：scripts/player/player_movement.gd、resources/player_movement.tres、scripts/combat/defense_settings.gd、resources/defense_settings.tres。
- 接続：scripts/player/player_controller.gd（通知2行）、scripts/effects/combat_feedback.gd（既存再生ノード内に2音を追加）。
- 検査：tests/action_audio.gdとUID。tests/combat_audio_pitch.gdは「防御姿勢だけでSword2は鳴らない」と検査文を明確化し、既存の期待値は維持。
- 記録：ASSET_REGISTER、README、08／10／12／14、DEVELOPMENT_STATUS、既存戦闘演出記録の参照、本書。

## 自動確認

Godot4.7.2／Windows／Compatibility・GTX1080、物理60Hz。検証用Godotは逐次実行する。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --path . --script tests/action_audio.gd
& $godotExe --path . --script tests/action_audio.gd -- --fps30
& $godotExe --headless --path . --script tests/action_audio.gd -- --reload
```

新検査は実Space／I／右マウス入力から、本物の物理・状態遷移とAudioStreamPlayer.playingを観測する。実ジャンプ・空中の無効入力・長押し・通常着地・高さ、Guard中や戦闘中の無効ジャンプ／踏み込み、I／右の開始・保持／重複／解除・UI、防御成功時のSword2との分離、初期ピッチ1.0／1.5、ピッチと音量の単独反映、範囲・保存／別プロセス再読込を確認する。

関連回帰はm00_input_map、m03_jump、m03_keyboard、m08_defense、combat_audio_pitch、directional_click、m09_enemy_combat、m09_startup。上記と同じ--script指定で再現する。

最終結果：**9種類11条件が全PASS・終了0**（新1種類の60／30／再読込3条件＋既存8種類）。

| 検査 | 結果 |
|---|---|
| action_audio・実描画60／30上限 | 122／81 assertions、PASS。実Space／I／右の開始・無効／保持／通常着地／解除・UI、成功音との分離、物理高度と個別設定を確認 |
| action_audio・別プロセス--reload | 4 assertions、PASS。既存Movement／Defense Resourceの音声・音量・ピッチ・Sword2との独立性を確認 |
| m00_input_map | 14アクション・32割当、PASS |
| m03_jump／m03_keyboard | 物理・高度・長押し／二段防止・コヨーテ／バッファ・地形・合成32ジャンプ、PASS。実機の同時押し問題は解決済みとしない |
| m08_defense／combat_audio_pitch | Guard・方向帰還・成功時のSword2、既存3音のピッチ独立262 assertions、PASS |
| directional_click／m09_enemy_combat／m09_startup | 1470／56 assertionsと実main起動、PASS。既存入力・連撃・敵攻撃を維持 |

editor import終了0。最終の採用ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。ログ・証明書・エディター設定保存の環境ERRORは実装エラーと区別する。ログと集計はGit除外の `.godot/m09_action_audio_*`。検証用Godotは終了済み。

静的照合：PlayerControllerの通知2行以外の物理コードはHEADと同一。TargetDash・InputMap・HP・Motion／武器数値・敵AI・画像／flash／spark・シーン・fixtureは差分なし。Jump1／Equip1のコピーは元ファイルと同一SHA256、git diff --check合格。ユーザーF5・聴感、実機パッド・長時間等の未検証は維持する。

## F5手動確認（ユーザー確認待ち）

1. F8→F5、必要なら「静止敵」。SpaceでJump1が1回鳴る。保持したまま着地しても増えず、空中の無効再押下でも鳴らない。解放してから新たにジャンプすると再び1回鳴る。
2. 右クリックで防御開始のEquip1が1回鳴る。保持・解除では増えず、Iでも同じ。右とIを重ねて保持しても再開始しない。空中で押してすぐ離した無効防御やHUD上のクリックは鳴らない。
3. 「近接敵」で右／Iを保持し、敵の攻撃を実際に防ぐ。開始時はEquip1、実成功時はSword2。成功のたびにEquip1を鳴らし直さず、開始だけでSword2を鳴らさない。
4. ジャンプの初期ピッチ1.0、防御開始の1.5を比較する。各音量／ピッチを別々に変更して保存→F5、Godot再起動後も保持されることを確認する。音声欄の差し替えも可能。
5. 左／J攻撃・3連撃、L照準・WASD／矢印・Space・Q/E、踏み込み／帰還・右／I防御と成功音が正常で、ジャンプ高度や防御性能が変わっていないことを確認する。

聴感・最終音量はユーザー確認待ち。M09検証待ち・既存未検証事項を維持し、新工程へ移行しない。commit／push未実行。
