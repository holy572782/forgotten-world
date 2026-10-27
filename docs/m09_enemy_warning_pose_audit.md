# M09完了後：日本語敵画像と攻撃予告姿勢の修正

2026-10-27／ADR-036。M09基本戦闘は完了のまま、今回の表示修正はユーザーF5確認待ち。commit／push未実行。

## 原因と変更範囲

ADR-035で旧waitを通常Idleと解釈していたが、ユーザー指定により正しくは攻撃予告用と判明した。WINDUPは従来Attackを使っていたため、通常停止／攻撃予告の両方の割当を訂正した。開始HEADはe3c316d。開始時の未コミット変更はユーザーによる元PNG6枚の日本語名への変更（旧名削除＋新名未追跡）のみ。これを保持し、画像自体を編集／移動／削除／改名しない。

## 実ファイルと用途

すべて `res://画像フォルダ/敵/` 内の実在PNG。144×192 RGBA、1枠48×48、横3コマ×縦4方向（下・左・右・上）。透明部分を保持。新旧はSHA256一致で対応を確認した。

| 現在の日本語名 | 以前の名前 | 用途 |
|---|---|---|
| 雑兵_歩行.png | 雑兵_walk.png（以前は雑兵_w.png） | 歩行・踏み込み・帰還・追跡。通常停止は先頭コマ |
| 雑兵_攻撃.png | 雑兵_a.png | 実攻撃 |
| 雑兵_攻撃態勢.png | 雑兵_wait.png | 攻撃予告のみ |
| 魔導士_歩行.png | 魔導士_walk.png（以前は魔導士_wl.png） | 歩行。通常停止は先頭コマ |
| 魔導士_攻撃.png | 魔導士_a.png | 実攻撃／弾発射 |
| 魔導士_攻撃態勢.png | 魔導士_wait.png | 攻撃予告のみ |

専用の通常待機／被弾画像はない。通常停止には独立Idle導入前のWalk先頭コマを採用し、新素材は制作しない。被弾は既存の白いflash／火花を維持する。「攻撃態勢」は各行の3コマが同じ絵。通常／赤の切替のたびにポーズを再生せず、方向別の先頭コマを固定する。

SpriteFramesのTexture2D参照は日本語名の実ファイルへ直接変更。古い英語PNGコピー6枚は履歴として保存し、本番Framesからは参照しない。元フォルダに残る旧名の.importは以前の自動生成sidecarであり、実行時の参照先には使用しない。新しい名前の.importはGodotが生成する。利用可能な日本語PNG6枚はすべて使用、専用被弾PNGは存在しない。古い履歴コピーやsidecarは勝手に削除しない。

## 表示の仕組み・Inspector

- `EnemyVisual.warning_frames`を追加し、雑兵／魔導士へ各warning SpriteFramesを設定。任意の敵で差し替え可能。未指定の旧fixtureは従来Attackで予告する。
- `EnemySprite`が既存の攻撃予告開始通知を受け、その瞬間に姿勢を更新する。フレーム処理でもWINDUPを読み、warning先頭コマを固定。赤点滅は既存Shaderの色変更のみで行う。独自の予告時計やAI状態は追加しない。
- 通常停止はidle_framesに設定したWalk先頭コマ1枚で静止。将来の専用Idleは既存idle_frames／idle_fpsで引き続き差し替え可能。専用Idleを推測して作らない。
- 実ATTACKは既存Attack共通タイムライン、歩行／踏み込み／帰還はWalk。予告後に通常の選択へ戻り、死亡でも予告素材を残さない。
- Inspectorは `resources/enemies/zouhyou_visual.tres`／`mage_visual.tres` の Warning Frames／Idle Frames／Walk Frames／Attack Frames。予告速度0.09秒、回数2、Fire1開始時1回、白優先、pixel_size0.0375／offset(0,23)、方向・影・壁深度は維持。
- 敵AI・Path・命中／ダメージ・攻撃／帰還時間・追跡・主人公／InputMap・SE再生スクリプトは変更していない。

## 変更ファイル

- `scripts/enemies/enemy_visual_data.gd`、`enemy_sprite.gd`
- `resources/enemies/zouhyou_visual.tres`、`mage_visual.tres`
- `assets/sprites/enemies/{zouhyou,mage}_{walk,attack,idle}_frames.tres`（既存6本）
- `assets/sprites/enemies/{zouhyou,mage}_warning_frames.tres`（新規2本）
- 日本語PNG6枚のGodot生成.import（元PNGはユーザー改名差分）
- `tests/enemy_followup.gd`、`enemy_sprites.gd`、`enemy_attack_warning.gd`
- `assets/ASSET_REGISTER.csv`、AGENTS.md、README.md、docs/08・10・11・12・14、DEVELOPMENT_STATUS、前回監査の訂正注記、本書

## 検証

Godot 4.7.2で8種類11条件が全PASS／終了0。最終一覧 `.godot/enemy_pose_results.json`。新しい期待値は画像用途の訂正だけであり、時間／HP／安全移動の受入条件は変更していない。

| 自動検査 | 結果 |
|---|---|
| enemy_followup 描画60／30fps上限 | 各221項目PASS |
| enemy_followup 別プロセス--reload | PASS |
| enemy_attack_warning 描画60／30fps上限 | 各110項目PASS |
| enemy_sprites 描画 | 408項目PASS |
| enemy_sword_combat 描画 | 445項目PASS（観測数は変動） |
| m09_timing | PASS |
| m09_startup（実mainシーン・左攻撃／右防御・切替） | PASS |
| combat_feedback 描画（白flash／火花・既存音） | 631項目PASS（観測数は変動） |
| m08_defense | PASS |

全方向とカメラYawで専用予告姿勢の固定、通常／赤の実画素復帰、白優先・火花・壁遮蔽、見た目の大きさ／足元／衝突を検査。通常画像／赤画像の描画キャプチャも目視確認した。追跡の実2回の攻撃・A帰還→Bへ歩行→B帰還、既存予告／弾時間、主人公の入力／防御／帰還は回帰合格。

最終エディターimport／スクリプト読み込みも終了0（`.godot/enemy_pose_import_final.log`）。画像参照・スクリプト／Shader解析のエラーなし。環境由来のWindowsルート証明書ストア読込エラーと、サンドボックス外のエディター設定保存拒否は既存のまま発生する。ゲーム側の読込エラーと区別する。初回検査のカメラ更新前の期待方向不一致はテストfixtureで既存カメラの更新を2tick待つよう訂正し、最終60／30両方で再実行合格。

元の日本語PNG6枚と履歴コピーの完全一致、全Framesの参照先実在、素材台帳のID重複なし、旧PNG名／英語コピーへの有効なFrames参照なし、`git diff --check`を確認。AI／主人公／攻撃・Motion・効果音・Shader・InputMap・武器の変更なし。

再現例（プロジェクトルートで1本ずつ実行）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_followup.gd
& $godotExe --path . --script res://tests/enemy_followup.gd -- --fps30
& $godotExe --path . --script res://tests/enemy_followup.gd -- --reload
& $godotExe --path . --script res://tests/enemy_attack_warning.gd
& $godotExe --path . --script res://tests/enemy_attack_warning.gd -- --fps30
```

残りの回帰は同じ--script引数に表の各tests/<名前>.gdを指定する。ログはGit除外の `.godot/enemy_pose_*.log`。自動描画・合成入力はユーザーF5や聴感の受入と区別する。

## F5での確認・未確認事項

1. F8→F5。近接敵の通常停止が歩行の先頭ポーズであり、攻撃態勢ではないことを確認。
2. 接近して予告を誘発。入り際に攻撃態勢へ変わり、同じポーズで通常→赤→通常→赤→通常となることを確認。Fire1は入り際の1回のみ。
3. 予告後のWalk踏み込み→Attack（剣／白い斬撃）→Walk帰還→通常停止または歩行追跡を確認。攻撃態勢が残らないこと。
4. 遠距離敵へ切替。通常停止→攻撃態勢赤点滅→攻撃／弾発射→通常停止または移動、Fire1と弾の挙動を確認。
5. Q/Eで4方向、敵の大きさと足元・白い被弾／火花・壁遮蔽、左／J攻撃・右／I防御・移動／ジャンプを確認。

見た目と音の自然さ・ユーザーF5は未確認。任意の複雑地形・大量敵・実機パッド・長時間性能の未検証も継続。専用Idle／被弾素材が必要な場合は別途素材提供が必要だが、本修正の通常停止は既存表示で機能する。
