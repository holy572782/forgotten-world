> **2026-10-13更新**: システム先行で開発。Godot採用。詳細仕様 `docs/10_SYSTEM_SPEC_GODOT.md`、Codex順序 `docs/11_CODEX_IMPLEMENTATION_PLAN.md`、テスト `docs/12_TEST_PLAN.md`。

# 忘れられた世界の旅人 / The Last Fable

> オリジナル・幻想アクションアドベンチャー企画。版 `0.1.0`（2026-10-13）。**M01完了。Godot 4.7.2で3Dテスト地形の描画・物理衝突を確認済み。プレイヤー操作は未実装です。**

## 一言でいうと
夢・記憶・願いが風景になる幻想世界「エルディア」を、白化から救う旅。2Dスプライトの登場人物と3D世界を組み合わせ、七つの試練を順不同に探索するアクションアドベンチャー。

## 最初に読む順番
1. `docs/00_PROJECT_CHARTER.md`：核となる企画と確定／仮／未決定の区別
2. `docs/01_WORLD_BIBLE.md`：世界のルールと設定
3. `docs/02_STORY_AND_CHARACTERS.md`：物語と登場人物
4. `docs/03_SEVEN_TRIALS.md`：七地域・七つの試練
5. `docs/04_GAME_DESIGN.md`：遊びとシステム
6. `AGENTS.md`：Codex・AI開発エージェントの作業ルール
7. `docs/05_PRODUCTION_RULES.md`：制作・アセット・著作権ルール
8. `docs/06_TECH_AND_GITHUB.md`：技術選定とGitHub導入

## ステータスの意味
- **合意済み**：この会話で採用した制作方針。変更はADRに記録。
- **企画案**：以前の提案に含まれるが詳細未承認、または新たに整理した案。
- **未決定**：推測で確定させない。

## 始め方
1. 新規プライベートGitHubリポジトリを作り、フォルダの中身を入れてコミット。
2. `docs/08_DECISIONS.md` と `docs/09_BACKLOG.md` を確認。
3. 使用エンジン（Godot／Unityなど）、発売プラットフォーム、画面解像度・目標fpsを決める。
4. 最小試作：草原一画面、2D主人公、3D地形、敵一体、攻撃ゲージ、回避、会話、残響。
5. Codexには`AGENTS.md`を読ませ、Issue単位の小さな変更を依頼。

## この資料の運用
重要な設定変更は `docs/08_DECISIONS.md` に理由を記載し、該当資料と同時更新。会話中に決まった内容も、**ファイルに追記してコミットするまではプロジェクトの正式な最新版ではありません**。

## M00：Godotプロジェクトの起動

- 対象：Godot 4.x。今回の検証版：`4.7.2.stable.official.ed1daf0bf`。
- 検証（2026-10-13）：ユーザーがF5で灰色の実行画面を確認。Codexがヘッドレス読み込み・60フレーム実行・InputMap全12アクション／30割り当ての合成入力検査に成功（終了コード0、エラー・警告なし）。記録は `docs/DEVELOPMENT_STATUS.md` を参照。
- `project.godot` と `scenes/main.tscn`（Node3D）から起動します。M01で `scenes/test_arena.tscn` を接続しました。外部アセットやプラグインは不要です。
- Compatibilityレンダラーは起動用の仮設定、物理は仕様の初期値60 tick/sです。対応OSや最終描画方式を確定するものではありません。
- 既存資料に残る「エンジン未決定」については、Godot採用を決定したADR-003を優先します。

### エディターでの確認

1. Godot 4.xのプロジェクトマネージャーで、このフォルダの `project.godot` をインポートして開く。
2. プロジェクト設定 → Input Map（入力マップ）で、下表の12アクションとデッドゾーン `0.2` を確認する。
3. mainシーンを開いてF6、またはF5でプロジェクトを実行する。M01の地形が表示され、エラーが出ないことを確認する。停止はF8を使用する。

現在は地形と確認用の固定カメラのみです。移動・攻撃・ポーズ等の反応はありません。プレイヤー操作はM02、ジャンプはM03、追従・回転カメラはM04の範囲です。

### ヘッドレスでの確認（PowerShell）

プロジェクトのルートで実行します。`$godotExe` は実際に使用するGodot 4.x実行ファイルの絶対パスに置き換えてください。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --version
& $godotExe --headless --path . --editor --quit
$LASTEXITCODE
& $godotExe --headless --path . --quit-after 60
$LASTEXITCODE
```

各終了コードが `0` で、出力に読み込みエラーがないことを確認します。再検証時は `--version` の正確な結果を記録してください。InputMap検査は `& $godotExe --headless --path . --script res://tests/m00_input_map.gd` で再実行できます。`.godot/` キャッシュは既存の `.gitignore` で除外されています。

### 入力の試作値

`docs/10_SYSTEM_SPEC_GODOT.md` 第2節に従い、キーボード・マウス・パッドを同じアクションに登録しています。全アクションのデッドゾーンは `0.2`。キーボードは物理キー位置を使用し、割り当てはInput Mapで変更できます。ゲーム中の再割り当て画面は後続です。

| アクション | キーボード／マウス | ゲームパッド |
|---|---|---|
| `move_left` | A／左矢印 | 左スティック左 |
| `move_right` | D／右矢印 | 左スティック右 |
| `move_up` | W／上矢印 | 左スティック上 |
| `move_down` | S／下矢印 | 左スティック下 |
| `jump` | Space | 南ボタン |
| `attack` | J／左クリック | 西ボタン |
| `dodge` | K／右クリック | 東ボタン |
| `camera_left` | Q | 右スティック左 |
| `camera_right` | E | 右スティック右 |
| `lock_on` | L | 右スティック押込 |
| `interact` | F | 北ボタン |
| `pause` | Esc | Start |

`lock_on`・`interact`も入力名のみ先に登録しています。斜め移動の正規化・アナログ強弱・UI操作中の攻撃抑止は、入力を利用する後続実装の範囲です。テスト計画のT01〜T15は今回の対象外で、未実行です。

## M01：3Dテスト地形と当たり判定

`scenes/test_arena.tscn` は単独でF6実行でき、mainからもインスタンス化されます。外部素材なしのプリミティブ地形です。以下の寸法・色・カメラは検証用の仮置き値です。

- 平地：28×28m、上面Y=0。壁：幅8m、高さ3m、厚さ0.6m。
- 坂道：幅4m、水平距離6m、高低差2m（約18.4°）、高さ2mの高台に接続。
- 段差：上面Y=0.25／0.5／1.0m、各幅4m・奥行き2m。自動ステップ登りは未実装。
- `Terrain` 配下の各 `StaticBody3D` に、同寸法・同変換の `BoxMesh` と `BoxShape3D` を配置。地形はcollision layer=1、mask=0。
- `PlayerSpawn` は足元基準の `(0, 0, 6)`。M02で足元原点のCharacterBody3Dを配置し、collision maskのレイヤー1を有効にする。検査用カプセルは高さ1.8m・半径0.3m、中心Y=0.9m。
- `Preview` に固定カメラ・照明・案内表示を集約。後続のプレイヤー／カメラリグと地形を分離して差し替え可能。
- 外周には壁なし。落下復帰は後続実装で、現時点では操作キャラクター自体がありません。

検証コマンド（リポジトリ直下、各コマンド後に終了コード0とエラー・警告なしを確認）:

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --headless --path . --quit-after 60
& $godotExe --headless --path . --script res://tests/m00_input_map.gd
& $godotExe --headless --path . --script res://tests/m01_terrain.gd
# 実レンダラーで同じ物理検査＋画像保存（.godot/m01_preview.png）
& $godotExe --path . --resolution 1152x720 --script res://tests/m01_terrain.gd -- --capture
```

2026-10-13、Godot `4.7.2.stable.official.ed1daf0bf` で全コマンド成功。M01検査は使い捨てのCharacterBody3Dで平地・高台・各段差への接地、壁と段差正面の遮断、坂道の往復と接続部の接地を確認します。プレイヤー操作を実装したものではなく、T01〜T15は未実行です。手動確認ではF5で地形全景、F8で停止し、エディターでTerrainのメッシュとコリジョンの一致を確認できます。
