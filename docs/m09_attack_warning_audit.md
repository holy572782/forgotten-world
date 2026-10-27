# M09完了後：敵の赤色点滅予告（ADR-034）

2026-10-27。ユーザーの最終手動確認完了報告に基づき、**M09は完了（試作範囲・基本戦闘）**。今回の予告表示改善は別途ユーザーF5・見やすさ確認待ち。M10開始・工程番号変更なし、commit／push未実行。

## 実装

近接の雑兵・遠距離の魔導士の既存WINDUPに合わせ、敵本体の色を赤→通常色へ2回切り替える。従来の予告時間（近接0.9秒／遠距離1.0秒）を変更せず、既存elapsed／windup_secondsを読む。新しい攻撃タイマー・AI状態・当たり判定は追加しない。

通常の点滅は予告時間を回数×2の区間へ分け、赤と通常色を交互に表示する。既定2回では近接0.225秒／遠距離0.25秒ずつの点灯・消灯となる。片側0.1秒より速くならないよう予告が短い敵では実際の回数を減らし、0.2秒未満ではWINDUP中の単発点灯を使う。0秒／非有限の予告では着色せず、予告終了時には消す。1描画フレームより短い予告では、表示できない可能性がある。視認性のためにAIの予告時間を延長することはしない。

`AttackWarning`は表示専用ノード。敵本体の既存私有ShaderMaterialへ、専用の色と強度だけを書き込む。現在の最近傍サンプリング・透明画素の破棄・頂点／深度処理・pixel_size／offset・画像・SpriteFrames・衝突形状は変更しない。共有body Shaderの警告強度初期値は0で、主人公へ色を付けない。

WINDUP以外（接近・踏み込み・攻撃・帰還・待機）は強度0。死亡通知、非表示、ツリー離脱でも消去する。従来の予備動作・方向アニメーションは維持する。

## Inspector

ファイルシステムで `resources/enemies/melee_practice.tres` または `resources/enemies/ranged_practice.tres` を開き、**Attack warning presentation**グループを編集する。実行シーン内では敵の **Settings** Resource内にある。通常敵2種類とも以下が初期値。

| 項目 | 変数名 | 初期値／範囲 |
|---|---|---|
| Attack Warning Flash Enabled | attack_warning_flash_enabled | true、ON/OFF |
| Attack Warning Flash Color | attack_warning_flash_color | Color(1.0,0.15,0.1,1.0)、任意の色 |
| Attack Warning Flash Count | attack_warning_flash_count | 2、1〜8・整数。短時間では実際の回数を減らす |
| Attack Warning Flash Strength | attack_warning_flash_strength | 0.75、0〜1・刻み0.01 |
| Attack Range Indicator Enabled | attack_range_indicator_enabled | false、ON/OFF |

点滅時間は既存 **Attack → Windup Seconds**へ追従する。今回はその値を変更していない。範囲表示をtrueにすると従来の攻撃扇形／円と、近接の踏み込み経路を再表示する。falseでは両方隠す。実行中のRemote Inspectorによる切り替えも次の描画更新で反映する。実行後も保持する変更は元のResourceを編集して保存する。

将来の敵やボスには既存EnemySettingsを複製して個別に割り当てる。画像の寸法に依存した点滅計算はない。現在の敵本体と同じbody Shaderを利用する表示で使用でき、任意の独自Shaderへ置き換える場合は同じ警告用uniformへの対応が必要となる。共用Resourceを編集すると同じ設定を使う個体へ反映されるため、個体だけ変える場合はResourceを固有化する。

## 被弾演出との優先順位

優先は白い被弾flash → 赤い予告 → 通常色。

- 赤は専用のbody Shaderパラメーターだけを使用。既存の白いflashは従来のmaterial_overlayと寿命／復帰処理を使う。
- HitFeedback.remainingが正の間は赤の強度を0にする。白いoverlayの色・強さ・材質・位置・期間を上書きしない。
- 白が終わってもWINDUPが続いていれば、その時点の予告phaseへ復帰する。非致死被弾でAIが中断しない従来仕様は維持し、被弾を理由に予告を延長／再開始しない。状態終了・死亡なら赤には戻さない。
- 実ダメージ時の音／火花の発生と座標・寿命は既存処理のまま。

## 攻撃範囲表示と戦闘の保護

PracticeEnemyの変更は_refresh_visuals内のtelegraph.visible／dash_guide.visibleの2条件だけ。形状の表示可否以外のコードはHEADと一致する。表示OFFでも位置更新を維持し、ONで従来の描画を再構成できる。

攻撃開始距離・リーチ・予告／移動／攻撃／帰還の時間・インターバル、狙い、命中判定・壁／足場・HP／死亡・弾・主人公入力・コンボ・音・既存エフェクト・武器や敵の数値Resourceは変更しない。範囲メッシュは従来どおり表示専用で、非表示でもダメージは成立する。金色ターゲットマークには新しい表示フラグを適用していない。

## 変更ファイル

- 新規 `scripts/enemies/enemy_attack_warning.gd`とUID：既存の予告経過時間から点滅をサンプルし、白優先／消去／範囲スイッチの更新を行う表示専用ノード
- `scripts/enemies/enemy_settings.gd`：既存Resourceへ5項目を追加
- `scripts/enemies/practice_enemy.gd`：攻撃範囲／経路の表示フラグのみ追加
- `assets/shaders/player_depth.gdshader`：既定0の警告色／強度とALBEDOの補間。透明／深度／頂点の処理は維持
- `scenes/enemies/practice_enemy.tscn`：AttackWarningノード追加
- 新規 `tests/enemy_attack_warning.gd`とUID
- 文書：本記録、AGENTS、README、DEVELOPMENT_STATUS、08_DECISIONS、10_SYSTEM_SPEC_GODOT、11_CODEX_IMPLEMENTATION_PLAN、12_TEST_PLAN、14_TARGET_DASH_COMBAT_SPEC

開始時HEADは71accbdcb41e3744df804b010a2fe3f51edb853c。未コミットの既存差分（旧画像2枚の.import削除・雑兵_wait.png.importの未追跡）を保持。今回画像ファイル自体や最近の素材・サイズ調整を編集・削除していない。

## 自動検証

Godot4.7.2.stable.official.ed1daf0bf／Windows、物理60Hz、Compatibility／GTX1080。**11種類13条件が全PASS・終了0**、1プロセスずつ実行。Godotエディター読み込みも終了0、最終ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。環境の証明書ストア読み取り・GLES3キャッシュ／エディター設定保存ERRORは別扱い。

| 最終検査 | 結果 |
|---|---|
| enemy_attack_warning 実描画60／30 | 各102項目PASS |
| 同・別プロセス--reload | PASS |
| enemy_sword_combat 実描画 | 445項目PASS |
| m09_enemy_combat | 56項目PASS |
| m09_enemy_dash | 171項目PASS |
| m09_timing | 予告／回復／弾の時間・速度PASS |
| m09_startup 実描画 | 実F5シーンの攻撃・左攻撃／右防御・モード切替PASS |
| combat_feedback 実描画 | 630項目PASS |
| weapon_depth 実描画 | 37項目PASS |
| m08_defense | 防御／方向帰還／安全経路／リセットPASS |
| m07_chain | 3体連撃／照準／入力予約／カメラ／帰還PASS |
| m03_jump | ジャンプ／着地／保持／コヨーテ・バッファ／移動安全性、30／60fps比較PASS |

ログと画像はGit除外の`.godot/attack_warning_*.log`、`warning_normal_*／warning_red_*／warning_white_priority.png`。結果一覧は`attack_warning_results.json`。実画像をCodexが目視し、通常／赤・白優先を確認。git diff --checkも合格。静的保護検査でAIの変更が表示条件2か所のみ、共有Shaderの頂点／深度／透明処理が元のまま、主人公／戦闘／被弾／弾のコード・Resource・画像・SpriteFramesがHEADと一致することを確認した。

新テストは実描画60／30fps上限と別プロセス再読込で確認する。近接／遠距離の4カメラYawで輪郭内の赤着色と通常画像への画素完全復帰、サイズ／transform／衝突の保持、2回／3回・色／強さ、範囲ON/OFFの実描画、壁遮蔽、非WINDUP・非表示・死亡・離脱の消去を検査する。実ダメージで白いflashが赤無効時と画素一致し、火花も発生することを確認する。

近接／遠距離それぞれについて実AIを予告から攻撃・必要な帰還まで動かし、表示ON/OFFで**全物理tickの状態・経過時間・位置・向き・攻撃回数・主人公HP・弾数が完全一致**することを検査する。Inspector設定の保存・別プロセス再読込も確認する。

再現（リポジトリ直下。各終了コード0とログを確認）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_attack_warning.gd -- --capture
& $godotExe --path . --script res://tests/enemy_attack_warning.gd -- --fps30
& $godotExe --headless --path . --script res://tests/enemy_attack_warning.gd -- --reload
```

## F5確認

1. F8停止→F5で近接敵の雑兵を確認。赤→通常色が2回、その後に必要なら踏み込んで一撃・帰還となり、範囲や経路のメッシュが表示されないことを確認する。リーチ内のその場攻撃・未移動帰還省略は従来どおり。
2. 赤い予告を見て右クリック／Iで防御、またはWASDで回避する。反応しやすい点滅速度／強さかを確認する。予告0.9秒や攻撃性能は変えていない。
3. 遠距離モードで魔導士を確認。赤点滅後に従来の弾を発射し、WASDで回避できることを確認する。予告1.0秒・弾速度・間隔は維持する。
4. 予告中の敵へ左クリック／Jで攻撃し、白い被弾flashと火花が従来どおり出ること、白を赤が上書きせず、撃破時も赤が残らないことを確認する。
5. Q/Eで回転し、向き・ピクセルの鮮明さ・透明部分・金色マーク・剣／斬撃・壁の前後を確認する。
6. EnemySettingsのAttack Range Indicator Enabledをtrueにして保存→F5で範囲と近接経路を確認し、falseへ戻す。Flash Enabled／Color／Count／Strengthも個別に調整・保存できることを確認する。
7. 主人公の左／J攻撃・3連撃・L切替・右／I防御・方向帰還・WASD／Space、近距離省略／遠距離踏み込みが維持されることを確認する。

未確認：新しい赤予告を見てから実際に防御／回避できるかのユーザー評価・見た目の受入、任意の複雑地形／多数敵・実機パッド・長時間性能。極端に短い予告では描画タイミング上表示できない場合がある。M09基本戦闘の完了は維持し、新表示のF5確認待ちのみを残す。
