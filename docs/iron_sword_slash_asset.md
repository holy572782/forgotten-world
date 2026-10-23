# 鉄の剣・編集可能な斬撃弧（2026-10-22）

ユーザー依頼によるAseprite素材制作。ゲームへの導入・戦闘仕様の変更は対象外。Issue番号の指定なし。見た目はユーザーレビュー待ち。

- 元画像：`画像フォルダ/武器/鉄の剣.png`。作業開始時から未コミット変更あり。その編集済みPNGを読み込み、原本を変更せず保持した。開始／終了SHA256は `83a197fd6a9c890ec505227dbd84a2de02ac61e83e103a21790e5916ca7c4135`。
- 編集元：`assets/source/weapons/iron_sword_slash.aseprite`。336×448、112px×3列×4方向の配置を維持。元の`Layer`と、新規`slash_arc`の計2レイヤー、1フレーム。
- PNG：`assets/export/weapons/iron_sword_slash.png`。剣と弧を合成した透過シート。現在のゲーム用`assets/sprites/weapons/iron_sword_attack.png`とResource参照は変更していない。
- 生成：`tools/aseprite/create_iron_sword_slash.lua`。各枠の茶色の柄・明るい刃から方向を検出し、2pxグリッドで先細りの弧を描く。白銀・原画の薄紫／青灰色を使用。左向きだけ逆回り、他は時計回り。振り始めは短く、中央は強く、終わりは薄くする。各枠の中心・半径・角度は見た目用の仮値で、攻撃判定を表さない。
- 新規レイヤーは剣の下に置き、元の画素を覆わない。レイヤーの表示切り替えで比較・再編集できる。PNGはレイヤーを保持できないため、編集には`.aseprite`を使用する。

## 再現手順

リポジトリ直下から、Aseprite 1.3.18.6で次を実行する。既存出力の上書きは拒否するため、再生成時は別名を指定する。

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe' --batch --script-param 'output=D:/Game/forgotten-world/.godot/iron_sword_slash/review.aseprite' --script 'tools/aseprite/create_iron_sword_slash.lua'
```

Asepriteで`iron_sword_slash.aseprite`を開き、`slash_arc`の表示を切り替えて12枠の軌道・色・太さを確認する。ゲーム用画像への置換は今回行っていない。

## 実施した検証と残件

- Aseprite Luaバッチ実行：終了0。12枠に計4712エフェクト画素。
- 保存済みファイルをAsepriteで再読込してレイヤー別PNGへ書き出し、元レイヤーの全RGBA画素と入力PNG、エフェクトレイヤーの全RGBA画素と生成画像が一致。
- 合成画像で元の可視4032画素がすべて不変。新規画素は各112px枠の2〜109px内、枠間の混入なし。元PNGのSHA256不変。
- 合成シートの画像をCodexが目視確認。Asepriteの画面取得は`FrameArrived timed out`で失敗し、GUI上でのレイヤー切り替え確認は未実行。
- ユーザーの見た目の受入、Godotへの導入、F5での表示確認は未実行。M08完了（試作範囲）・M09検証待ち・M10別指示待ちと既存残件を維持。
- 生成AI画像モデルは使用せず、Codex作成のLuaによる手続き描画。原画の作者・ライセンスは従来どおり未報告。commit／push未実行。
