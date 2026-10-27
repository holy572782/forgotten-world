> **後続更新（ADR-035）**：新IdleとWalk素材改名を接続し、踏み込みはWalk、雑兵は帰還後の3秒内に歩いて位置を整える。以下は作成時の履歴。最新の参照名・設定は[m09_enemy_followup_audit.md](m09_enemy_followup_audit.md)。

> **後続更新（ADR-033）**：雑兵専用柄補正と旧敵攻撃時間を、主人公と共通の剣・斬撃・モーション・射程と単発／3秒待機へ更新。以下はADR-032時点の履歴。最新設定は[m09_enemy_sword_combat_audit.md](m09_enemy_sword_combat_audit.md)。

# M09：雑兵・魔導士の画像と雑兵の鉄の剣（ADR-032）

2026-10-27。実装・自動検証済み、**ユーザーF5・見た目確認待ち**。M09の追加改善。新しいマイルストーンなし。commit／push未実行。

## 使用素材

原本は全て `画像フォルダ/敵/`。そのままゲーム用の半角名へコピーし、元ファイルは変更しない。

| 役割 | 原本 | ゲーム用PNG |
|---|---|---|
| 雑兵の歩行・待機 | 雑兵_w.png | assets/sprites/enemies/zouhyou_walk.png |
| 雑兵の攻撃姿勢 | 雑兵_a.png | assets/sprites/enemies/zouhyou_attack.png |
| 魔導士の歩行・待機 | 魔導士_wl.png | assets/sprites/enemies/mage_walk.png |
| 魔導士の攻撃姿勢 | 魔導士_a.png | assets/sprites/enemies/mage_attack.png |

4枚とも144×192、1枠48×48、横3列×縦4方向（下・左・右・上）。透明画素あり、可視画素のalphaは255、補間・色・原画の加工なし。歩行は中央→右→中央→左を8fpsで再生し、待機は左列を保持。攻撃素材の3列は各方向とも同じ姿勢。新しい本体の振りコマを制作したものではない。

コピー前後のSHA256が一致：
- zouhyou_walk：86bcfd80474041a85ed0cf7d75936f55c2c5b3d73c4a8c18266be581cb0d34c3
- zouhyou_attack：cd6e3630c8d4a21b8f83e069a8fc4c455acbc53d0f22c7f7ef85b973e792eab2
- mage_walk：ce2795e7f13ad6f9f38a3011e8d2c8267b4af72884d25096f4912761b1d4743b
- mage_attack：d1f0f07b69fd53716769ee4e8cbda78c675cffc2d138a434c36b3b745727ba2f

鉄の剣は既存 `resources/weapons/iron_sword_visual.tres` → `assets/sprites/weapons/iron_sword_attack_frames.tres` → `iron_sword_attack.png` を参照。336×448、112px×3列×4方向。主人公と同じResource・画像を読み、主人公側のデータは変更しない。今回、新しい斬撃・音・攻撃判定は追加しない。素材の作者／利用条件の詳細は未報告として台帳に記録。

## 表示と同期

- 既存PracticeEnemyへ `AnimatedSprite3D`（本体＋影）と `WeaponSwing`（剣）を追加。EnemySettings.visualから雑兵／魔導士の設定を読む。仮Bodyカプセルは非表示で保持。visual未設定の既存検査fixtureは従来のカプセル表示を維持する。
- AIの `state` と `elapsed / max(attack_seconds, hit_delay_seconds)` を唯一の攻撃進行として本体・剣へ反映。WINDUP／DASH_APPROACHは攻撃姿勢の先頭、剣はATTACKだけ。現在の近接攻撃は0.15秒・命中0.05秒で、3等分の第2コマから実命中。魔導士の弾発射は既存の即時発射を維持する。
- カメラの現在のbasisと主人公と同じdirection_sectorで4方向を選び、Q/Eの途中も方向・コマを合わせる。pixel_size=0.0375、offset=(0,23)。48px／112pxの画像サイズによる拡大縮小を行わない。
- 雑兵は攻撃3列で拳の位置が同じ一方、主人公用の剣の柄は各コマで移動する。そのためEnemyVisualへ方向・コマ別の位置補正を保存し、柄の茶色部分を同じ拳へ合わせる。共有の剣Resourceには補正を書き込まない。
- 本体は既存player_depth Shader、剣は既存WeaponSwingの床／壁遮蔽・attachment depthを再利用。no_depth_testは無効のまま。フラッシュは既存の被弾処理とoverlayの復帰を維持し、スプライト用Shaderへ既存の深度補正を適用。本体を描いた後にpriority=1で重ね、透過輪郭内だけを着色する。壁の深度テストは維持する。
- 死亡専用画像は未提供のため、撃破時は歩行先頭を足元基準で静止保持し剣を消す。新しい死亡演出は制作しない。HP0・死亡状態・ターゲット無効化・弾の解放は既存のAI処理を維持する。
- AIスクリプト・Collision（半径0.4m／高さ1.5m）・HP40・予兆／移動・攻撃判定／ダメージ／帰還・主人公／InputMap・武器／防御／SE設定は変更しない。静止練習敵の表示も維持する。

## Inspectorでの調整

ファイルシステムから以下のResourceを開く。

- `resources/enemies/melee_practice.tres` → Visual＝`zouhyou_visual.tres`
- `resources/enemies/ranged_practice.tres` → Visual＝`mage_visual.tres`
- Visual内：Walk Frames／Attack Frames／Weapon Visual／Pixel Size／Sprite Offset
- 雑兵のWeapon grip correction (pixels)：Weapon Offsets Down／Left／Right／Up。各配列は攻撃の1・2・3コマの順、単位はピクセル、+xは画面右・+yは画面上。各要素をInspectorで編集・保存できる。魔導士はWeapon Visual未設定。

素材を差し替える場合は対応するFramesのAtlasTextureと矩形を更新する。別の武器を敵へ装備する場合はEnemyVisualのWeapon Visual参照と柄補正を変更する。共有の主人公用Resource自体を編集すると主人公にも反映されるため、敵だけ変えたい場合は別Resourceに複製する。画像の大きさを攻撃範囲として使用しない。

## 追加・変更ファイル

- 新規：`scripts/enemies/enemy_visual_data.gd`、`enemy_sprite.gd`、`enemy_weapon_visual.gd`とUID
- 新規：`resources/enemies/zouhyou_visual.tres`、`mage_visual.tres`
- 新規：`assets/sprites/enemies/` の4PNG／4Frames／4import
- 新規：`assets/shaders/enemy_sprite_flash.gdshader`とUID、`tests/enemy_sprites.gd`とUID
- 変更：`scripts/enemies/enemy_settings.gd`、`scripts/effects/enemy_hit_feedback.gd`、`scenes/enemies/practice_enemy.tscn`、`resources/enemies/melee_practice.tres`、`ranged_practice.tres`
- 文書：本記録、DEVELOPMENT_STATUS、ADR-032、システム仕様、戦闘仕様、テスト計画、ASSET_REGISTERの4行

開始時から存在した素材制作の変更（zouhyou_attack_asset.md、Aseprite／Lua／書出し等）を保持。本作業でそれらを編集・上書きしていない。

## 自動確認

Godot4.7.2.stable.official.ed1daf0bf／Windows、物理60Hz、Compatibility／GTX1080。1プロセスずつ実行。新enemy_spritesの60／30fpsは実描画で検査する。

- 4カメラYaw×4方向×3コマでphase・同倍率・中心／柄位置を確認。
- 全コマで剣の差分画素を床なし／床ありで完全比較、欠落なし。不透明壁で本体・剣・flashが隠れる。
- HPラベルを隠してflashの実描画差を計測し、その全差分がキャラクター輪郭内にあること・元材質へ復帰することを確認。
- 実AIを動作させ、両敵の攻撃0／1／2コマ、雑兵の1回の実命中・基準位置への帰還、魔導士の実弾発射を確認。
- 関連回帰は下表。終了0・最終ログにSCRIPT ERROR／Parse Error／SHADER ERRORなし。証明書ストア読み取り、GLES3 Shaderキャッシュ／エディター設定保存の環境ERRORは区別する。

| 検査 | 結果 |
|---|---|
| enemy_sprites 実描画60／30fps上限 | PASS（最終件数はログ参照、実AIの観測数で変動） |
| m09_enemy_combat | PASS・56項目 |
| m09_enemy_dash | PASS・171項目 |
| m09_startup 実描画 | PASS・実F5シーンの左攻撃／右防御／敵モード切替 |
| combat_feedback 実描画 | PASS・629項目 |
| weapon_depth 実描画 | PASS・37項目 |
| m00_input_map | PASS・14actions／32bindings |
| m08_defense | PASS・方向帰還／防御／移動安全性／リセット |

合計8種類9条件。初期の検査fixtureのfloat比較／方向符号を調整し、最終では実描画の遮蔽・フラッシュ条件を満たすことを確認。ログはGit除外の `.godot/enemy_sprites_*.log`、回帰一覧は `enemy_sprites_results.json`、新検査の最終結果は `enemy_sprites_final.json`。描画画像をCodexが目視。ユーザーF5、任意の複雑地形、実機パッド、多数敵／長時間性能は未実行。

再現（リポジトリ直下）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_sprites.gd -- --capture
& $godotExe --path . --script res://tests/enemy_sprites.gd -- --fps30
& $godotExe --headless --path . --script res://tests/m09_enemy_combat.gd
& $godotExe --headless --path . --script res://tests/m09_enemy_dash.gd
& $godotExe --path . --script res://tests/m09_startup.gd -- --capture
& $godotExe --path . --script res://tests/combat_feedback.gd
& $godotExe --path . --script res://tests/weapon_depth.gd
& $godotExe --headless --path . --script res://tests/m00_input_map.gd
& $godotExe --headless --path . --script res://tests/m08_defense.gd
```

## F5手動確認

1. F8で実行を止め、F5で起動。既定の「近接敵」が雑兵の姿で接近・予兆・踏み込み・鉄の剣による一撃・帰還を行うことを確認。
2. 画面上の「遠距離敵」を選び、魔導士の歩行・攻撃姿勢と従来の単発弾を確認。魔導士には鉄の剣が出ないことを確認。
3. 上下左右から敵を誘導し、Q/Eで回転して画像の向き・雑兵の柄位置・床欠け・敵との前後を確認。
4. 左クリック／Jで敵を攻撃し、短いflash・火花・命中音を確認。右／Iで防御し、従来の防御・防御成功音を確認。
5. 近距離のその場攻撃、遠距離踏み込み、コンボ、撃破後の待機・帰還、方向入力帰還、WASD／Spaceを確認。
6. 壁・段差・崖の近くでも不正な移動や壁越し表示がなく、撃破で剣が消え、モードを切り替えても前の敵／剣／弾が残らないことを確認。

残件：固定攻撃姿勢の見た目・柄補正値のユーザーレビュー、死亡専用画像、以前からの実機パッド／複雑地形／長時間性能。M09は検証待ちを維持。
