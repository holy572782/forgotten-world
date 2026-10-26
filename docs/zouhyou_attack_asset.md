# zouhyou_attack 4方向素材（2026-10-26）

目的はユーザーがAsepriteで開いていた`$zouhyou_attack_left.png`の上下左右の攻撃姿勢の作成。ゲームへの導入、敵AI・戦闘・マイルストーンの変更は対象外。Issue番号の指定なし。開始時のgit statusはクリーン。

## 元画像とユーザー指定

- 開いていたタイトルは`$zouhyou_attack_left.png - Aseprite v1.3.18.6`。画面キャプチャは`FrameArrived timed out`で失敗、アクセシビリティでタイトルを確認した。
- Desktop配下で見つかった同名PNG7個はすべて同じSHA256。入力として`C:/Users/INVESTFX/Desktop/Indies - android  アニメーション/img/characters/$zouhyou_attack_left.png`を使用。144×192、48px×3列×4行で全12枠が同じ左向き姿勢。
- 正面・背面は同フォルダーの同キャラクター`$zouhyou_all.png`の中央列／下向き行・上向き行を使用。他のキャラクターやゲーム機構の流用なし。
- 保存済み画像には3×3に揃わない細部があると報告したところ、ユーザーは**「元の細部を保ち、追加部分だけ3×3にする」**を選択。原画の全面リサイズやドット統一は行わない。
- 左原本SHA256：`157e2d1323991f66c209e602a667a00e1a41a78778789d19ff14adbe0c80e4f7`。
- 方向資料SHA256：`9063aad1b5e022b2b20e00c644576cc3038317fd94972c43a53ba92c67b55027`。両入力とも作業後にハッシュ不変。

## 作成物

- `assets/source/enemies/zouhyou_attack_four_directions.aseprite`：144×192、行順は下／左／右／上。3列は元画像同様に同じ姿勢を反復し、3コマ攻撃アニメーションを新作したものではない。
- `assets/export/enemies/zouhyou_attack/zouhyou_attack.png`：上記の透過PNG。
- 同フォルダーの`zouhyou_attack_down/left/right/up.png`：各48×48の個別PNG。
- `tools/aseprite/create_zouhyou_attack_directions.lua`：Aseprite Luaによる再現可能な制作処理。既存出力への上書きを拒否する。

編集元には可視の`direction_bases_original_detail`と`attack_arms_3x3`、非表示の`reference_attack_left_original`と`reference_four_directions_original`の4レイヤーを保持。グリッドを3×3に設定。

左は元画像の全画素を保持、右はセル内の正確な左右反転。上下は元資料の顔・頭巾・胴・足の細部を保ち、攻撃する腕だけを組み替えた。腕の旧領域の削除も3×3単位、新規描画もすべて3×3のブロック。元の黒・茶灰・影・肌色のパレットのみ使用。上下の拳の位置・姿勢は今回作成した案で、ユーザーレビュー待ち。

## 再現・確認

PowerShellでリポジトリ直下から実行。再生成時は既存ファイルと異なる出力先を指定する。

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe' --batch --script-param 'output=D:/Game/forgotten-world/.godot/zouhyou_art/review.aseprite' --script-param 'export_dir=D:/Game/forgotten-world/.godot/zouhyou_art/review_export' --script 'tools/aseprite/create_zouhyou_attack_directions.lua'
```

- Aseprite 1.3.18.6 Luaで生成・保存、別バッチで再読込して検査。4レイヤーと表示状態、非表示の両資料の全RGBA一致、左原画一致、右反転一致、全12枠の列反復、合成PNGと保存済みAsepriteの全RGBA一致を確認、PASS。
- 保存後の追加レイヤーは126論理ブロック＝1134物理画素。全ブロックが3×3の同色9画素、違反0。
- 4方向の拡大画像で見た目をCodexが確認。原画の細部・パレットと透過を保持。ユーザーによる見た目の受入とAseprite GUIでの確認は未実行。
- ゲームの敵画像・Resource・コードへの接続、Godot／F5検査は未実行。M08試作範囲完了・M09検証待ち・M10別指示待ちと既存残件を維持。commit／push未実行。
- 画像生成モデル不使用。Luaによる手続き編集。原画の作者／ライセンス詳細は未報告として素材台帳へ記録。
